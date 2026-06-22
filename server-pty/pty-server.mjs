import { createServer } from 'node:http';
import { WebSocketServer } from 'ws';
import { port, pmUrl } from './config.mjs';
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

async function proxyPm(req, res, pmPath) {
  try {
    const upstream = await fetch(`${pmUrl}${pmPath}`);
    const text = await upstream.text();
    if (!upstream.ok) {
      json(res, upstream.status, { error: `PM API ${upstream.status}`, body: text });
      return;
    }
    res.writeHead(200, { 'content-type': upstream.headers.get('content-type') || 'application/json', ...corsHeaders() });
    res.end(text);
  } catch (error) {
    json(res, 502, { error: error instanceof Error ? error.message : 'PM API unavailable' });
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
    json(res, 200, { ok: true, service: 'amux-pty', port });
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

  if (req.method === 'GET' && url.pathname === '/api/pm/projects') {
    await proxyPm(req, res, '/api/projects');
    return;
  }

  if (req.method === 'GET' && url.pathname === '/api/pm/tasks') {
    const projectId = url.searchParams.get('project_id') || '';
    if (!projectId) {
      json(res, 400, { error: 'project_id query param required' });
      return;
    }
    await proxyPm(req, res, `/api/tasks?project_id=${encodeURIComponent(projectId)}`);
    return;
  }

  const pmTaskMatch = url.pathname.match(/^\/api\/pm\/tasks\/([^/]+)$/);
  if (req.method === 'GET' && pmTaskMatch) {
    await proxyPm(req, res, `/api/tasks/${encodeURIComponent(decodeURIComponent(pmTaskMatch[1]))}`);
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
  console.log(`amux pty server listening on http://0.0.0.0:${port}`);
});
