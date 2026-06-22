import { createServer } from 'node:http';
import { WebSocket, WebSocketServer } from 'ws';
import { loadBackends, port } from './config.mjs';
import { corsHeaders, json, readBody } from './http-utils.mjs';

let backends = loadBackends();

function backendListPayload() {
  return backends.map((backend) => ({
    id: backend.id,
    label: backend.label,
    kind: backend.kind,
    transport: backend.transport,
    capabilities: backend.capabilities,
    status: 'unknown',
    hostInfo: backend.hostInfo,
  }));
}

function findBackend(id = 'local') {
  return backends.find((backend) => backend.id === id);
}

function backendWsUrl(backend, pathAndSearch) {
  const url = new URL(backend.baseUrl);
  url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
  url.pathname = pathAndSearch.pathname;
  url.search = pathAndSearch.search;
  return url.toString();
}

function copyResponseHeaders(upstream) {
  const headers = corsHeaders();
  const contentType = upstream.headers.get('content-type');
  if (contentType) headers['content-type'] = contentType;
  return headers;
}

async function proxyHttp(req, res, backend, upstreamPath) {
  try {
    const body = req.method === 'GET' || req.method === 'HEAD' ? undefined : await readBody(req);
    const headers = {};
    for (const [key, value] of Object.entries(req.headers)) {
      if (!value || ['host', 'connection', 'content-length'].includes(key.toLowerCase())) continue;
      headers[key] = Array.isArray(value) ? value.join(', ') : value;
    }
    const upstream = await fetch(`${backend.baseUrl}${upstreamPath}`, { method: req.method, headers, body });
    const buffer = Buffer.from(await upstream.arrayBuffer());
    res.writeHead(upstream.status, copyResponseHeaders(upstream));
    res.end(buffer);
  } catch (error) {
    json(res, 502, { error: error instanceof Error ? error.message : 'backend unavailable', backendId: backend.id });
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
    json(res, 200, { ok: true, service: 'amux-gateway', port, backends: backendListPayload() });
    return;
  }

  if (req.method === 'GET' && url.pathname === '/api/backends') {
    json(res, 200, { backends: backendListPayload() });
    return;
  }

  const healthMatch = url.pathname.match(/^\/api\/backends\/([^/]+)\/health$/);
  if (req.method === 'GET' && healthMatch) {
    const backend = findBackend(decodeURIComponent(healthMatch[1]));
    if (!backend) { json(res, 404, { error: 'backend not found' }); return; }
    await proxyHttp(req, res, backend, '/healthz');
    return;
  }

  const backendMatch = url.pathname.match(/^\/api\/backends\/([^/]+)(\/.*)$/);
  if (backendMatch) {
    const backend = findBackend(decodeURIComponent(backendMatch[1]));
    if (!backend) { json(res, 404, { error: 'backend not found' }); return; }
    await proxyHttp(req, res, backend, `/api${backendMatch[2]}${url.search}`);
    return;
  }

  // Compatibility routes: preserve the existing frontend contract by routing to the local backend.
  const local = findBackend('local') ?? backends[0];
  if (local && (url.pathname === '/api/state' || url.pathname === '/api/upload' || url.pathname.startsWith('/api/pm/') || url.pathname.startsWith('/api/sessions/'))) {
    await proxyHttp(req, res, local, `${url.pathname}${url.search}`);
    return;
  }

  json(res, 404, { error: 'not found' });
});

const wss = new WebSocketServer({ noServer: true });

function proxyWebSocket(client, req, backend, upstreamPath) {
  const upstreamUrl = backendWsUrl(backend, upstreamPath);
  const upstream = new WebSocket(upstreamUrl);

  upstream.on('open', () => {
    client.on('message', (data, isBinary) => {
      if (upstream.readyState === WebSocket.OPEN) upstream.send(data, { binary: isBinary });
    });
    upstream.on('message', (data, isBinary) => {
      if (client.readyState === WebSocket.OPEN) client.send(data, { binary: isBinary });
    });
  });

  upstream.on('close', () => {
    try { client.close(); } catch {}
  });
  upstream.on('error', () => {
    try { client.close(); } catch {}
  });
  client.on('close', () => {
    try { upstream.close(); } catch {}
  });
}

server.on('upgrade', (req, socket, head) => {
  const url = new URL(req.url ?? '/', `http://${req.headers.host ?? '127.0.0.1'}`);
  let backend;
  let upstreamPath;

  const match = url.pathname.match(/^\/api\/backends\/([^/]+)\/terminal$/);
  if (match) {
    backend = findBackend(decodeURIComponent(match[1]));
    upstreamPath = new URL(`/api/terminal${url.search}`, 'http://placeholder');
  } else if (url.pathname === '/api/terminal') {
    backend = findBackend('local') ?? backends[0];
    upstreamPath = new URL(`/api/terminal${url.search}`, 'http://placeholder');
  }

  if (!backend || !upstreamPath) {
    socket.write('HTTP/1.1 404 Not Found\r\n\r\n');
    socket.destroy();
    return;
  }

  wss.handleUpgrade(req, socket, head, (client) => proxyWebSocket(client, req, backend, upstreamPath));
});

server.listen(port, '0.0.0.0', () => {
  console.log(`amux gateway listening on http://0.0.0.0:${port}`);
  console.log(`registered backends: ${backends.map((backend) => `${backend.id}=${backend.baseUrl}`).join(', ') || 'none'}`);
});
