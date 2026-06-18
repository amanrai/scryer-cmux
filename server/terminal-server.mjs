import { randomUUID } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as pty from 'node-pty';
import { WebSocketServer } from 'ws';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '..');
const port = Number(process.env.SCRYER_CMUX_API_PORT ?? 43220);
const shell = process.env.SHELL || (process.platform === 'win32' ? 'powershell.exe' : '/bin/zsh');
const shellArgs = process.platform === 'win32' ? [] : ['-il'];
const maxReplayBytes = 250_000;
const statePath = path.join(repoRoot, '.smux-state.json');

function getDisplayHostName() {
  for (const binary of ['tailscale', '/Applications/Tailscale.app/Contents/MacOS/Tailscale']) {
    try {
      const status = JSON.parse(execFileSync(binary, ['status', '--json'], { encoding: 'utf8', timeout: 1000 }));
      const dnsName = String(status?.Self?.DNSName ?? '').replace(/\.$/, '');
      if (dnsName) return dnsName;
      const hostName = String(status?.Self?.HostName ?? '');
      if (hostName) return hostName;
    } catch {}
  }
  return os.hostname();
}

function makeId(prefix) {
  return `${prefix}-${randomUUID()}`;
}

function makePane(index) {
  return {
    id: makeId('pane'),
    title: `Terminal ${index}`,
    createdAt: Date.now(),
  };
}

function makeWorkspace(index) {
  const pane = makePane(1);
  return {
    id: makeId('workspace'),
    name: index === 1 ? 'smux' : `workspace ${index}`,
    color: ['#E5C07B', '#61AFEF', '#98C379', '#56B6C2', '#C678DD', '#E06C75', '#7F8794'][(index - 1) % 7],
    cwdLabel: 'repos/scryer-cmux',
    branchLabel: 'main',
    layout: 'row',
    panes: [pane],
    activePaneId: pane.id,
  };
}

function makeDefaultState() {
  const workspace = makeWorkspace(1);
  return { workspaces: [workspace], activeWorkspaceId: workspace.id };
}

function loadState() {
  try {
    if (!existsSync(statePath)) return makeDefaultState();
    const state = sanitizeState(JSON.parse(readFileSync(statePath, 'utf8')));
    return state ?? makeDefaultState();
  } catch {
    return makeDefaultState();
  }
}

function saveState(state) {
  const tmpPath = `${statePath}.tmp`;
  writeFileSync(tmpPath, JSON.stringify(state, null, 2));
  renameSync(tmpPath, statePath);
}

let appState = loadState();

const sessions = new Map();

function corsHeaders() {
  return {
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'GET, PUT, POST, DELETE, OPTIONS',
    'access-control-allow-headers': 'content-type',
  };
}

function json(res, status, payload) {
  res.writeHead(status, { 'content-type': 'application/json', ...corsHeaders() });
  res.end(JSON.stringify(payload));
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.setEncoding('utf8');
    req.on('data', (chunk) => {
      body += chunk;
      if (body.length > 2_000_000) {
        req.destroy();
        reject(new Error('request body too large'));
      }
    });
    req.on('end', () => resolve(body));
    req.on('error', reject);
  });
}

function sanitizeState(input) {
  if (!input || !Array.isArray(input.workspaces)) return null;
  const workspaces = input.workspaces
    .map((workspace, workspaceIndex) => {
      if (!workspace || !Array.isArray(workspace.panes)) return null;
      const panes = workspace.panes
        .map((pane, paneIndex) => ({
          id: String(pane?.id || makeId('pane')),
          title: String(pane?.title || `Terminal ${paneIndex + 1}`).slice(0, 80),
          createdAt: Number(pane?.createdAt) || Date.now(),
        }))
        .slice(0, 24);
      if (panes.length === 0) panes.push(makePane(1));
      const activePaneId = panes.some((pane) => pane.id === workspace.activePaneId) ? String(workspace.activePaneId) : panes[0].id;
      return {
        id: String(workspace.id || makeId('workspace')),
        name: String(workspace.name || `workspace ${workspaceIndex + 1}`).slice(0, 80),
        color: /^#[0-9a-fA-F]{6}$/.test(String(workspace.color ?? '')) ? String(workspace.color) : '#E5C07B',
        cwdLabel: String(workspace.cwdLabel || 'repos/scryer-cmux').slice(0, 120),
        branchLabel: String(workspace.branchLabel || 'main').slice(0, 80),
        layout: workspace.layout === 'column' ? 'column' : 'row',
        panes,
        activePaneId,
      };
    })
    .filter(Boolean)
    .slice(0, 24);

  if (workspaces.length === 0) workspaces.push(makeWorkspace(1));
  const activeWorkspaceId = workspaces.some((workspace) => workspace.id === input.activeWorkspaceId)
    ? String(input.activeWorkspaceId)
    : workspaces[0].id;
  return { workspaces, activeWorkspaceId };
}

function paneIdsFromState(state = appState) {
  return new Set(state.workspaces.flatMap((workspace) => workspace.panes.map((pane) => pane.id)));
}

function killSession(paneId) {
  const session = sessions.get(paneId);
  if (!session) return;
  sessions.delete(paneId);
  for (const ws of session.clients) {
    try { ws.close(); } catch {}
  }
  try { session.term.kill(); } catch {}
}

function pruneClosedPaneSessions(nextState) {
  const paneIds = paneIdsFromState(nextState);
  for (const paneId of sessions.keys()) {
    if (!paneIds.has(paneId)) killSession(paneId);
  }
}

function createSession(paneId) {
  const term = pty.spawn(shell, shellArgs, {
    name: 'xterm-256color',
    cols: 120,
    rows: 30,
    cwd: os.homedir(),
    env: {
      ...process.env,
      TERM: 'xterm-256color',
      COLORTERM: 'truecolor',
      SCRYER_CMUX: '1',
      SCRYER_CMUX_PANE_ID: paneId,
    },
  });

  const session = {
    paneId,
    term,
    clients: new Set(),
    replay: '',
    exited: false,
  };

  term.onData((data) => {
    session.replay = `${session.replay}${data}`.slice(-maxReplayBytes);
    for (const ws of session.clients) send(ws, { type: 'output', data });
  });

  term.onExit(({ exitCode, signal }) => {
    session.exited = true;
    for (const ws of session.clients) {
      send(ws, { type: 'status', status: 'exited', code: exitCode, signal });
      try { ws.close(); } catch {}
    }
    sessions.delete(paneId);
  });

  sessions.set(paneId, session);
  return session;
}

function getSession(paneId) {
  return sessions.get(paneId) ?? createSession(paneId);
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
    json(res, 200, { ...appState, hostName: getDisplayHostName() });
    return;
  }

  if ((req.method === 'PUT' || req.method === 'POST') && url.pathname === '/api/state') {
    try {
      const body = await readBody(req);
      const nextState = sanitizeState(JSON.parse(body));
      if (!nextState) {
        json(res, 400, { error: 'invalid state' });
        return;
      }
      appState = nextState;
      saveState(appState);
      pruneClosedPaneSessions(appState);
      json(res, 200, { ...appState, hostName: getDisplayHostName() });
    } catch (error) {
      json(res, 400, { error: error instanceof Error ? error.message : 'invalid request' });
    }
    return;
  }

  const sessionMatch = url.pathname.match(/^\/api\/sessions\/([^/]+)$/);
  if (req.method === 'DELETE' && sessionMatch) {
    killSession(decodeURIComponent(sessionMatch[1]));
    json(res, 200, { ok: true });
    return;
  }

  res.writeHead(404, { 'content-type': 'application/json', ...corsHeaders() });
  res.end(JSON.stringify({ error: 'not found' }));
});

const wss = new WebSocketServer({ server, path: '/api/terminal' });

function send(ws, payload) {
  if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(payload));
}

wss.on('connection', (ws, req) => {
  const url = new URL(req.url ?? '/', `http://${req.headers.host ?? '127.0.0.1'}`);
  const paneId = url.searchParams.get('paneId') || makeId('pane');
  const session = getSession(paneId);
  session.clients.add(ws);

  send(ws, {
    type: 'status',
    status: 'connected',
    shell,
    cwd: os.homedir(),
    paneId,
    replayed: Boolean(session.replay),
    message: `server pty session on ${os.hostname()}`,
  });

  if (session.replay) send(ws, { type: 'output', data: session.replay, replay: true });

  ws.on('message', (raw) => {
    let msg;
    try {
      msg = JSON.parse(raw.toString());
    } catch {
      session.term.write(raw.toString());
      return;
    }

    if (msg.type === 'input') {
      session.term.write(String(msg.data ?? ''));
    }
    if (msg.type === 'paste') {
      session.term.write(String(msg.text ?? ''));
    }
    if (msg.type === 'interrupt') {
      session.term.write('\x03');
    }
    if (msg.type === 'resize') {
      const cols = Number(msg.cols);
      const rows = Number(msg.rows);
      if (Number.isFinite(cols) && Number.isFinite(rows) && cols > 0 && rows > 0) {
        session.term.resize(Math.floor(cols), Math.floor(rows));
      }
    }
  });

  ws.on('close', () => {
    session.clients.delete(ws);
  });
});

server.listen(port, '0.0.0.0', () => {
  console.log(`scryer-cmux terminal server listening on http://0.0.0.0:${port}`);
});
