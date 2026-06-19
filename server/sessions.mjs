import os from 'node:os';
import * as pty from 'node-pty';
import { maxReplayBytes, shell, shellArgs } from './config.mjs';

export class SessionManager {
  #sessions = new Map();

  constructor(send) {
    this.send = send;
  }

  get(paneId) {
    return this.#sessions.get(paneId) ?? this.#create(paneId);
  }

  kill(paneId) {
    const session = this.#sessions.get(paneId);
    if (!session) return;
    this.#sessions.delete(paneId);
    for (const ws of session.clients) {
      try { ws.close(); } catch {}
    }
    try { session.term.kill(); } catch {}
  }

  prune(livePaneIds) {
    for (const paneId of this.#sessions.keys()) {
      if (!livePaneIds.has(paneId)) this.kill(paneId);
    }
  }

  attach(ws, paneId) {
    const session = this.get(paneId);
    session.clients.add(ws);

    this.send(ws, {
      type: 'status',
      status: 'connected',
      shell,
      cwd: os.homedir(),
      paneId,
      replayed: Boolean(session.replay),
      message: `server pty session on ${os.hostname()}`,
    });
    if (session.replay) this.send(ws, { type: 'output', data: session.replay, replay: true });

    ws.on('message', (raw) => this.#handleMessage(session, raw));
    ws.on('close', () => session.clients.delete(ws));
  }

  #create(paneId) {
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

    const session = { paneId, term, clients: new Set(), replay: '', exited: false };
    term.onData((data) => this.#broadcastData(session, data));
    term.onExit(({ exitCode, signal }) => this.#handleExit(session, exitCode, signal));
    this.#sessions.set(paneId, session);
    return session;
  }

  #broadcastData(session, data) {
    session.replay = `${session.replay}${data}`.slice(-maxReplayBytes);
    for (const ws of session.clients) this.send(ws, { type: 'output', data });
  }

  #handleExit(session, exitCode, signal) {
    session.exited = true;
    for (const ws of session.clients) {
      this.send(ws, { type: 'status', status: 'exited', code: exitCode, signal });
      try { ws.close(); } catch {}
    }
    this.#sessions.delete(session.paneId);
  }

  #handleMessage(session, raw) {
    let msg;
    try {
      msg = JSON.parse(raw.toString());
    } catch {
      session.term.write(raw.toString());
      return;
    }

    if (msg.type === 'input') session.term.write(String(msg.data ?? ''));
    if (msg.type === 'paste') session.term.write(String(msg.text ?? ''));
    if (msg.type === 'interrupt') session.term.write('\x03');
    if (msg.type === 'resize') this.#resize(session, msg);
  }

  #resize(session, msg) {
    const cols = Number(msg.cols);
    const rows = Number(msg.rows);
    if (Number.isFinite(cols) && Number.isFinite(rows) && cols > 0 && rows > 0) {
      session.term.resize(Math.floor(cols), Math.floor(rows));
    }
  }
}
