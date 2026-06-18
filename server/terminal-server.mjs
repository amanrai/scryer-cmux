import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { WebSocketServer } from 'ws';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '..');
const port = Number(process.env.SCRYER_CMUX_API_PORT ?? 43220);
const shell = process.env.SHELL || (process.platform === 'win32' ? 'powershell.exe' : '/bin/zsh');
const shellArgs = process.platform === 'win32' ? [] : ['-il'];

const server = createServer((req, res) => {
  if (req.url === '/healthz') {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ ok: true, service: 'scryer-cmux-terminal', port }));
    return;
  }
  res.writeHead(404, { 'content-type': 'application/json' });
  res.end(JSON.stringify({ error: 'not found' }));
});

const wss = new WebSocketServer({ server, path: '/api/terminal' });

function send(ws, payload) {
  if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(payload));
}

wss.on('connection', (ws) => {
  const child = spawn(shell, shellArgs, {
    cwd: repoRoot,
    env: {
      ...process.env,
      TERM: 'xterm-256color',
      COLORTERM: 'truecolor',
      SCRYER_CMUX: '1',
    },
    stdio: ['pipe', 'pipe', 'pipe'],
  });

  send(ws, {
    type: 'status',
    status: 'connected',
    shell,
    cwd: repoRoot,
    message: `real shell on ${os.hostname()}`,
  });

  child.stdout.on('data', (chunk) => send(ws, { type: 'output', data: chunk.toString('utf8') }));
  child.stderr.on('data', (chunk) => send(ws, { type: 'output', data: chunk.toString('utf8') }));

  child.on('exit', (code, signal) => {
    send(ws, { type: 'status', status: 'exited', code, signal });
    try { ws.close(); } catch {}
  });

  ws.on('message', (raw) => {
    let msg;
    try {
      msg = JSON.parse(raw.toString());
    } catch {
      child.stdin.write(raw.toString());
      return;
    }

    if (msg.type === 'input') {
      child.stdin.write(String(msg.data ?? ''));
    }
    if (msg.type === 'paste') {
      child.stdin.write(String(msg.text ?? ''));
    }
    if (msg.type === 'interrupt') {
      child.stdin.write('\x03');
    }
  });

  ws.on('close', () => {
    if (!child.killed) child.kill('SIGHUP');
  });
});

server.listen(port, '127.0.0.1', () => {
  console.log(`scryer-cmux terminal server listening on http://127.0.0.1:${port}`);
});
