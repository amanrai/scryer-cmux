import os from 'node:os';
import * as pty from 'node-pty';
import { maxReplayBytes, shell, shellArgs } from './config.mjs';

const interactionsUrl = (process.env.SCRYER_INTERACTIONS_URL || 'http://100.105.192.98:43217').replace(/\/$/, '');
const producerMarkerRe = /@@SCRYER_INTERACTION_PRODUCER_V1@@(\{[^@]*\})@@END_SCRYER_INTERACTION_PRODUCER@@/g;
const interactionPollMs = Number(process.env.SCRYER_INTERACTIONS_POLL_MS || 1500);

function interactionTime(request) {
  const ts = Date.parse(request?.receivedAt ?? request?.createdAt ?? request?.updatedAt ?? '');
  return Number.isFinite(ts) ? ts : 0;
}

function latestInteractionRequest(requests) {
  if (!Array.isArray(requests) || !requests.length) return null;
  return [...requests].sort((a, b) => interactionTime(a) - interactionTime(b) || String(a?.id ?? '').localeCompare(String(b?.id ?? ''))).at(-1) ?? null;
}

function normalizeTerminalText(text) {
  return String(text)
    // OSC sequences, including hyperlink resets.
    .replace(/\x1b\][\s\S]*?(?:\x07|\x1b\\)/g, '')
    // CSI SGR/cursor/control sequences.
    .replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, '')
    // Other short escape sequences.
    .replace(/\x1b[@-Z\\-_]/g, '')
    // Pi's rendered message can wrap/pad the marker across terminal rows.
    // The producer marker JSON is emitted with JSON.stringify(), so whitespace
    // inside the marker is display noise for our routing fields.
    .replace(/\s+/g, '');
}

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

  constructor(send, { onProducer } = {}) {
    this.send = send;
    this.onProducer = onProducer;
    this.producerByPane = new Map();
    this.pollTimer = setInterval(() => {
      this.#pollInteractions();
      this.#pollUpdates();
    }, interactionPollMs);
  }

  setProducer(paneId, producer) {
    if (!producer?.from) return;
    const current = this.producerByPane.get(paneId);
    if (current?.emittedAt && producer.emittedAt && Date.parse(current.emittedAt) > Date.parse(producer.emittedAt)) return;
    this.producerByPane.set(paneId, producer);
    this.onProducer?.(paneId, producer);
    const session = this.#sessions.get(paneId);
    if (session) {
      session.producer = producer;
      session.lastUpdateSince = '';
      for (const ws of session.clients) this.send(ws, { type: 'interaction_producer', producer });
    }
  }

  loadProducers(panes) {
    for (const pane of panes) if (pane?.interactionProducer?.from) this.producerByPane.set(pane.id, pane.interactionProducer);
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
      interactionProducer: session.producer ?? null,
      message: `server pty session on ${os.hostname()}`,
      cols: session.cols,
      rows: session.rows,
    });
    if (session.replay) this.send(ws, { type: 'output', data: session.replay, replay: true });
    if (session.activeInteractionRequest) this.send(ws, { type: 'interaction', request: session.activeInteractionRequest });

    ws.on('message', (raw) => this.#handleMessage(session, ws, raw));
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

    const session = { paneId, term, cols: 120, rows: 30, clients: new Set(), replay: '', exited: false, producer: this.producerByPane.get(paneId), activeInteractionId: null, activeInteractionRequest: null, lastInteractionAvailableId: null, lastInteractionShownId: null, lastUpdateSince: '', altScreen: false };
    term.onData((data) => this.#broadcastData(session, data));
    term.onExit(({ exitCode, signal }) => this.#handleExit(session, exitCode, signal));
    this.#sessions.set(paneId, session);
    return session;
  }

  #broadcastData(session, data) {
    session.replay = `${session.replay}${data}`.slice(-maxReplayBytes);
    // Only truncate on \x1b[3J (erase saved lines — what `clear` emits to wipe scrollback).
    // Never truncate on \x1b[2J alone: TUIs use that for every frame redraw.
    const clearRe = /\x1b\[3J/g;
    let lastClearEnd = -1;
    let m;
    while ((m = clearRe.exec(session.replay)) !== null) lastClearEnd = m.index + m[0].length;
    if (lastClearEnd >= 0) session.replay = session.replay.slice(lastClearEnd);
    // Track alternate screen state so we know whether a TUI is active.
    const altScreenRe = /\x1b\[\?1049([hl])/g;
    let am;
    while ((am = altScreenRe.exec(data)) !== null) session.altScreen = am[1] === 'h';
    this.#scanProducerMarkers(session);
    for (const ws of session.clients) this.send(ws, { type: 'output', data });
  }

  #scanProducerMarkers(session) {
    const normalized = normalizeTerminalText(session.replay);
    for (const match of normalized.matchAll(producerMarkerRe)) {
      try {
        const producer = JSON.parse(match[1]);
        if (typeof producer.from === 'string' && producer.from) this.setProducer(session.paneId, producer);
      } catch {}
    }
  }

  async #pollInteractions() {
    for (const session of this.#sessions.values()) {
      const from = session.producer?.from;
      if (!from) continue;
      try {
        const res = await fetch(`${interactionsUrl}/api/requests/active?from=${encodeURIComponent(from)}`);
        if (!res.ok) continue;
        const data = await res.json();
        const activeRequests = Array.isArray(data.requests) ? data.requests : [];
        const request = latestInteractionRequest(activeRequests);
        session.lastInteractionAvailableId = request?.id ?? null;
        if (request && request.id !== session.lastInteractionShownId) {
          session.activeInteractionId = request.id;
          session.activeInteractionRequest = request;
          session.lastInteractionShownId = request.id;
          for (const ws of session.clients) this.send(ws, { type: 'interaction', request, availableRequestCount: activeRequests.length });
        } else if (request) {
          session.activeInteractionId = request.id;
          session.activeInteractionRequest = request;
        } else if (!request && session.activeInteractionId) {
          const requestId = session.activeInteractionId;
          session.activeInteractionId = null;
          session.activeInteractionRequest = null;
          for (const ws of session.clients) this.send(ws, { type: 'interaction_clear', requestId });
        }
      } catch {}
    }
  }

  async #pollUpdates() {
    for (const session of this.#sessions.values()) {
      const from = session.producer?.from;
      if (!from || session.clients.size === 0) continue;
      try {
        const since = session.lastUpdateSince ? `&since=${encodeURIComponent(session.lastUpdateSince)}` : '';
        const res = await fetch(`${interactionsUrl}/api/updates?from=${encodeURIComponent(from)}${since}&limit=100`);
        if (!res.ok) continue;
        const data = await res.json();
        const updates = Array.isArray(data.updates) ? data.updates : [];
        if (!updates.length) continue;
        const latest = updates[updates.length - 1];
        if (latest?.receivedAt) session.lastUpdateSince = latest.receivedAt;
        for (const ws of session.clients) this.send(ws, { type: 'session_updates', updates });
      } catch {}
    }
  }

  #handleExit(session, exitCode, signal) {
    session.exited = true;
    for (const ws of session.clients) {
      this.send(ws, { type: 'status', status: 'exited', code: exitCode, signal });
      try { ws.close(); } catch {}
    }
    this.#sessions.delete(session.paneId);
  }

  #handleMessage(session, ws, raw) {
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
    if (msg.type === 'interaction_response') this.#submitInteractionResponse(session, msg);
  }

  async #submitInteractionResponse(session, msg) {
    const request = msg.request;
    if (!request?.id || !request?.from || !msg.response) return;
    try {
      const res = await fetch(`${interactionsUrl}/api/responses`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          id: globalThis.crypto.randomUUID(),
          requestId: request.id,
          from: request.from,
          responder: { kind: 'smux', paneId: session.paneId },
          response: msg.response,
        }),
      });
      if (res.ok) {
        session.activeInteractionId = null;
        session.activeInteractionRequest = null;
        for (const ws of session.clients) this.send(ws, { type: 'interaction_clear', requestId: request.id });
      }
    } catch {}
  }

  #resize(session, msg) {
    const cols = Number(msg.cols);
    const rows = Number(msg.rows);
    if (Number.isFinite(cols) && Number.isFinite(rows) && cols > 0 && rows > 0) {
      session.cols = Math.floor(cols);
      session.rows = Math.floor(rows);
      session.term.resize(session.cols, session.rows);
      for (const ws of session.clients) this.send(ws, { type: 'status', status: 'resized', paneId: session.paneId, cols: session.cols, rows: session.rows });
    }
  }
}
