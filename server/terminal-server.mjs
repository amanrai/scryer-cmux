import { createServer } from 'node:http';
import { WebSocketServer } from 'ws';
import { port } from './config.mjs';
import { getDisplayHostName } from './host-name.mjs';
import { corsHeaders, json, readTextBody } from './http-utils.mjs';
import { handleUpload } from './uploads.mjs';
import { paneIdsFromState, loadState, sanitizeState, saveState } from './state-store.mjs';
import { makeId } from './ids.mjs';
import { SessionManager } from './sessions.mjs';

let appState = loadState();

function send(ws, payload) {
  if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(payload));
}

function updatePaneProducer(paneId, producer) {
  appState = {
    ...appState,
    workspaces: appState.workspaces.map((workspace) => ({
      ...workspace,
      panes: workspace.panes.map((pane) => (pane.id === paneId ? { ...pane, interactionProducer: producer } : pane)),
    })),
  };
  saveState(appState);
}

const sessions = new SessionManager(send, { onProducer: updatePaneProducer });
sessions.loadProducers(appState.workspaces.flatMap((workspace) => workspace.panes));

function statePayload() {
  return { ...appState, hostName: getDisplayHostName() };
}

async function handleStateWrite(req, res) {
  try {
    const body = await readTextBody(req);
    const nextState = sanitizeState(JSON.parse(body));
    if (!nextState) {
      json(res, 400, { error: 'invalid state' });
      return;
    }
    appState = nextState;
    saveState(appState);
    sessions.prune(paneIdsFromState(appState));
    json(res, 200, statePayload());
  } catch (error) {
    json(res, 400, { error: error instanceof Error ? error.message : 'invalid request' });
  }
}

const server = createServer(async (req, res) => {
  const url = new URL(req.url ?? '/', `http://${req.headers.host ?? '127.0.0.1'}`);

  if (req.method === 'OPTIONS') {
    res.writeHead(204, corsHeaders());
    res.end();
    return;
  }

  if (req.method === 'GET' && url.pathname === '/healthz') {
    json(res, 200, { ok: true, service: 'scryer-cmux-terminal', port });
    return;
  }

  if (req.method === 'GET' && url.pathname === '/api/state') {
    json(res, 200, statePayload());
    return;
  }

  if ((req.method === 'PUT' || req.method === 'POST') && url.pathname === '/api/state') {
    await handleStateWrite(req, res);
    return;
  }

  if (req.method === 'POST' && url.pathname === '/api/upload') {
    await handleUpload(req, res);
    return;
  }

  const sessionMatch = url.pathname.match(/^\/api\/sessions\/([^/]+)$/);
  if (req.method === 'DELETE' && sessionMatch) {
    sessions.kill(decodeURIComponent(sessionMatch[1]));
    json(res, 200, { ok: true });
    return;
  }

  json(res, 404, { error: 'not found' });
});

const wss = new WebSocketServer({ server, path: '/api/terminal' });

wss.on('connection', (ws, req) => {
  const url = new URL(req.url ?? '/', `http://${req.headers.host ?? '127.0.0.1'}`);
  sessions.attach(ws, url.searchParams.get('paneId') || makeId('pane'));
});

server.listen(port, '0.0.0.0', () => {
  console.log(`scryer-cmux terminal server listening on http://0.0.0.0:${port}`);
});
