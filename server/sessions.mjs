import os from 'node:os';
import * as pty from 'node-pty';
import { maxReplayBytes, shell, shellArgs } from './config.mjs';

// Terminal-detection markers that tools (e.g. pi-coding-agent's pi-tui) use to
// pick an inline-image protocol. smux renders via @xterm/addon-image, which
// supports Sixel + the iTerm2 inline-image protocol but NOT the kitty protocol.
// The backend inherits whatever launched it, so strip the kitty/ghostty/wezterm/
// warp/tmux markers and present as iTerm2 so tools emit a protocol we can draw.
const STRIPPED_TERM_VARS = [
  'TMUX', 'TMUX_PANE',
  'KITTY_WINDOW_ID', 'KITTY_PID', 'KITTY_LISTEN_ON',
  'GHOSTTY_RESOURCES_DIR', 'GHOSTTY_BIN_DIR',
  'WEZTERM_PANE', 'WEZTERM_EXECUTABLE', 'WEZTERM_UNIX_SOCKET',
  'WARP_SESSION_ID', 'WARP_TERMINAL_SESSION_UUID',
  'WT_SESSION', 'TERMINAL_EMULATOR',
];

function buildPtyEnv(paneId) {
  const env = {
    ...process.env,
    TERM: 'xterm-256color',
    COLORTERM: 'truecolor',
    TERM_PROGRAM: 'iTerm.app',
    TERM_PROGRAM_VERSION: '3.5.0',
    ITERM_SESSION_ID: `w0t0p0:${paneId}`,
    SCRYER_CMUX: '1',
    SCRYER_CMUX_PANE_ID: paneId,
  };
  for (const key of STRIPPED_TERM_VARS) delete env[key];
  return env;
}

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
      env: buildPtyEnv(paneId),
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
