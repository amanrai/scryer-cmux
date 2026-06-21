import { useEffect, useRef, useState } from 'react';
import { Terminal } from '@xterm/xterm';
import { FitAddon } from '@xterm/addon-fit';
import { ImageAddon } from '@xterm/addon-image';
import '@xterm/xterm/css/xterm.css';
import { WS_BASE } from './constants';
import { terminalTheme } from './terminal/theme';
import { shellQuote, uploadFile } from './terminal/upload';
import type { PaneStatus } from './types';

type InteractionChoice = { id: string; label: string; send?: string; custom?: boolean };
type InteractionRequest = {
  id: string;
  from: string;
  kind: string;
  payload: { title?: string; body?: string; choices?: InteractionChoice[] };
};

export type TerminalPaneApi = {
  sendInput: (data: string) => void;
  getRecentLines: (count?: number) => string[];
  openInteraction: () => void;
  openQuickInputs: () => void;
};

type TerminalPaneProps = {
  paneId: string;
  active: boolean;
  accentColor: string;
  fontSize: number;
  focusToken: number;
  onStatus?: (paneId: string, status: PaneStatus) => void;
  onRegisterApi?: (paneId: string, api: TerminalPaneApi | null) => void;
  onOpenCommandInput?: () => void;
  onInteractionState?: (paneId: string, state: { hasProducer: boolean; hasPending: boolean }) => void;
};

type QuickInput = { label: string; description?: string; data: string; icon: string };

const quickInputs: QuickInput[] = [
  { label: 'Esc', description: 'Send escape', data: '\x1b', icon: 'fa-door-open' },
  { label: 'Tab', description: 'Autocomplete / indent', data: '\t', icon: 'fa-arrow-right-to-bracket' },
  { label: 'Enter', description: 'Submit current line', data: '\r', icon: 'fa-turn-down' },
  { label: 'Ctrl-C', description: 'Interrupt', data: '\x03', icon: 'fa-ban' },
  { label: 'Ctrl-D', description: 'EOF / exit', data: '\x04', icon: 'fa-right-from-bracket' },
  { label: 'Ctrl-L', description: 'Clear screen', data: '\x0c', icon: 'fa-broom' },
  { label: '↑', description: 'Previous history', data: '\x1b[A', icon: 'fa-arrow-up' },
  { label: '↓', description: 'Next history', data: '\x1b[B', icon: 'fa-arrow-down' },
  { label: '/comms-init', description: 'Re-emit interaction producer marker', data: '/comms-init\r', icon: 'fa-satellite-dish' },
  { label: '/comms-test', description: 'Create test interaction', data: '/comms-test\r', icon: 'fa-vial' },
  { label: '/comms-status', description: 'Show comms state', data: '/comms-status\r', icon: 'fa-signal' },
  { label: '/reload', description: 'Reload Pi extensions', data: '/reload\r', icon: 'fa-rotate' },
  { label: '/scryer', description: 'Show Scryer command list', data: '/scryer\r', icon: 'fa-list' },
  { label: 'git status', description: 'Run git status', data: 'git status\r', icon: 'fa-code-branch' },
  { label: 'clear', description: 'Clear terminal', data: 'clear\r', icon: 'fa-eraser' },
];

function QuickInputsModal({ onClose, onSend }: { onClose: () => void; onSend: (data: string) => void }) {
  return (
    <div className="quick-input-modal" onMouseDown={(event) => event.stopPropagation()}>
      <div className="interaction-pane-header">
        <div className="interaction-eyebrow"><i className="fa-solid fa-bolt" aria-hidden="true" /> Quick inputs</div>
        <button type="button" className="interaction-close" title="Close" onClick={onClose}>
          <i className="fa-solid fa-xmark" aria-hidden="true" />
        </button>
      </div>
      <div className="quick-input-grid">
        {quickInputs.map((item) => (
          <button key={item.label} type="button" className="quick-input-item" onClick={() => onSend(item.data)}>
            <i className={`fa-solid ${item.icon}`} aria-hidden="true" />
            <span>
              <strong>{item.label}</strong>
              {item.description ? <small>{item.description}</small> : null}
            </span>
          </button>
        ))}
      </div>
    </div>
  );
}

function InteractionPaneModal({ request, onClose, onDismiss, onRespond }: {
  request: InteractionRequest;
  onClose: () => void;
  onDismiss: () => void;
  onRespond: (response: Record<string, unknown>) => void;
}) {
  const [custom, setCustom] = useState(false);
  const [draft, setDraft] = useState('');
  const choices = request.payload.choices?.length ? request.payload.choices : [{ id: 'custom', label: 'Type response…', custom: true }];
  return (
    <div className={`interaction-pane-modal${custom ? ' composing' : ''}`} onMouseDown={(event) => event.stopPropagation()}>
      <div className="interaction-pane-header">
        <div className="interaction-eyebrow"><i className="fa-solid fa-comments" aria-hidden="true" /> Interaction request</div>
        <button type="button" className="interaction-close" title="Close locally" onClick={onClose}>
          <i className="fa-solid fa-xmark" aria-hidden="true" />
        </button>
      </div>
      <div className="interaction-pane-titlebar">
        <h3>{request.payload.title ?? 'Input needed'}</h3>
        {request.payload.body ? <p>{request.payload.body}</p> : null}
      </div>
      <div className="interaction-choice-list" aria-label="Choices">
        {choices.map((choice) => (
          <button
            key={choice.id}
            type="button"
            className={`interaction-choice${choice.custom && custom ? ' selected' : ''}`}
            onClick={() => choice.custom ? setCustom(true) : onRespond({ kind: 'choice', choiceId: choice.id, text: choice.send ?? choice.label })}
          >
            <span>{choice.label}</span>
            <i className={`fa-solid ${choice.custom ? 'fa-keyboard' : 'fa-arrow-right'}`} aria-hidden="true" />
          </button>
        ))}
      </div>
      {custom ? (
        <div className="interaction-composer">
          <label htmlFor={`interaction-custom-${request.id}`}>Custom response</label>
          <textarea
            id={`interaction-custom-${request.id}`}
            className="interaction-custom-input"
            value={draft}
            autoFocus
            autoCapitalize="none"
            autoCorrect="off"
            spellCheck={false}
            placeholder="Type your response…"
            onChange={(event) => setDraft(event.target.value)}
            onKeyDown={(event) => {
              if ((event.metaKey || event.ctrlKey) && event.key === 'Enter' && draft.trim()) {
                event.preventDefault();
                onRespond({ kind: 'custom', text: draft.trim() });
              }
            }}
          />
        </div>
      ) : null}
      <div className="interaction-actions">
        <button type="button" className="ghost-button" onClick={onDismiss}>Dismiss</button>
        {custom ? <button type="button" className="create-button" disabled={!draft.trim()} onClick={() => onRespond({ kind: 'custom', text: draft.trim() })}>Send</button> : null}
      </div>
    </div>
  );
}

export function TerminalPane({ paneId, active, accentColor, fontSize, focusToken, onStatus, onRegisterApi, onOpenCommandInput, onInteractionState }: TerminalPaneProps) {
  const hostRef = useRef<HTMLDivElement | null>(null);
  const termRef = useRef<Terminal | null>(null);
  const fitRef = useRef<FitAddon | null>(null);
  const socketRef = useRef<WebSocket | null>(null);
  const touchLastYRef = useRef<number | null>(null);
  const touchScrollRemainderRef = useRef(0);
  const touchStartRef = useRef<{ x: number; y: number; moved: boolean } | null>(null);
  const [status, setStatus] = useState<PaneStatus>('connecting');
  const [dropActive, setDropActive] = useState(false);
  const [hasProducer, setHasProducer] = useState(false);
  const [interaction, setInteraction] = useState<InteractionRequest | null>(null);
  const [interactionVisible, setInteractionVisible] = useState(false);
  const [quickInputsVisible, setQuickInputsVisible] = useState(false);

  useEffect(() => {
    if (!hostRef.current) return;

    function reportStatus(next: PaneStatus) {
      setStatus(next);
      onStatus?.(paneId, next);
    }

    const term = new Terminal({
      cursorBlink: true,
      fontFamily: '"JetBrainsMono Nerd Font", "JetBrains Mono", ui-monospace, "SF Mono", Menlo, Monaco, Consolas, monospace',
      fontSize,
      lineHeight: 1.35,
      scrollback: 5000,
      convertEol: true,
      theme: terminalTheme(accentColor),
    });
    const fit = new FitAddon();
    term.loadAddon(fit);
    // Inline images: Sixel + iTerm2 inline-image protocol (kitty not supported).
    term.loadAddon(new ImageAddon({ sixelSupport: true, iipSupport: true }));
    term.open(hostRef.current);
    fit.fit();
    if (active) term.focus();

    const socket = new WebSocket(`${WS_BASE}?paneId=${encodeURIComponent(paneId)}`);
    socketRef.current = socket;
    termRef.current = term;
    fitRef.current = fit;

    socket.addEventListener('open', () => {
      reportStatus('connected');
      socket.send(JSON.stringify({ type: 'resize', cols: term.cols, rows: term.rows, paneId }));
      if (active) {
        window.requestAnimationFrame(() => {
          fit.fit();
          term.focus();
          hostRef.current?.querySelector<HTMLTextAreaElement>('textarea')?.focus();
        });
      }
    });
    socket.addEventListener('message', (event) => {
      const payload = JSON.parse(event.data);
      if (payload.type === 'output') {
        if (payload.replay) term.clear();
        term.write(payload.data);
      }
      if (payload.type === 'status' && payload.interactionProducer) setHasProducer(true);
      if (payload.type === 'interaction_producer') setHasProducer(true);
      if (payload.type === 'interaction') {
        setInteraction(payload.request);
        setInteractionVisible(true);
      }
      if (payload.type === 'interaction_clear') {
        setInteraction(null);
        setInteractionVisible(false);
      }
    });
    socket.addEventListener('close', () => {
      reportStatus('closed');
      term.writeln('\r\n\x1b[31m[terminal disconnected]\x1b[0m');
    });
    socket.addEventListener('error', () => {
      term.writeln('\r\n\x1b[31m[terminal backend unavailable]\x1b[0m');
    });

    const dataDisposable = term.onData((data) => {
      if (socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify({ type: 'input', data, paneId }));
    });

    const resizeObserver = new ResizeObserver(() => {
      fit.fit();
      if (socket.readyState === WebSocket.OPEN) {
        socket.send(JSON.stringify({ type: 'resize', cols: term.cols, rows: term.rows, paneId }));
      }
    });
    resizeObserver.observe(hostRef.current);

    return () => {
      dataDisposable.dispose();
      resizeObserver.disconnect();
      socket.close();
      term.dispose();
    };
  }, [paneId]);

  useEffect(() => {
    if (termRef.current) termRef.current.options.theme = terminalTheme(accentColor);
  }, [accentColor]);

  useEffect(() => {
    const term = termRef.current;
    if (!term) return;
    term.options.fontSize = fontSize;
    fitRef.current?.fit();
    const socket = socketRef.current;
    if (socket?.readyState === WebSocket.OPEN) {
      socket.send(JSON.stringify({ type: 'resize', cols: term.cols, rows: term.rows, paneId }));
    }
  }, [fontSize, paneId]);

  useEffect(() => {
    if (!active) return;

    function focusTerminal() {
      fitRef.current?.fit();
      termRef.current?.focus();
      hostRef.current?.querySelector<HTMLTextAreaElement>('textarea')?.focus();
      const socket = socketRef.current;
      const term = termRef.current;
      if (socket?.readyState === WebSocket.OPEN && term) {
        socket.send(JSON.stringify({ type: 'resize', cols: term.cols, rows: term.rows, paneId }));
      }
    }

    const frame = window.requestAnimationFrame(focusTerminal);
    const timer = window.setTimeout(focusTerminal, 120);
    window.addEventListener('smux:focus-terminal', focusTerminal);

    return () => {
      window.cancelAnimationFrame(frame);
      window.clearTimeout(timer);
      window.removeEventListener('smux:focus-terminal', focusTerminal);
    };
  }, [active, paneId, focusToken]);

  function send(data: string, focusAfterSend = true) {
    const socket = socketRef.current;
    if (socket?.readyState === WebSocket.OPEN) socket.send(JSON.stringify({ type: 'input', data, paneId }));
    if (focusAfterSend) termRef.current?.focus();
  }

  function getRecentLines(count = 12) {
    const term = termRef.current;
    if (!term) return [];
    const buffer = term.buffer.active;
    const end = buffer.baseY + buffer.cursorY;
    const start = Math.max(0, end - count + 1);
    const lines: string[] = [];
    for (let index = start; index <= end; index += 1) {
      lines.push(buffer.getLine(index)?.translateToString(true) ?? '');
    }
    return lines;
  }

  useEffect(() => {
    if (!onRegisterApi) return;
    onRegisterApi(paneId, {
      sendInput: (data) => send(data, false),
      getRecentLines,
      openInteraction: () => { if (interaction) setInteractionVisible(true); },
      openQuickInputs: () => setQuickInputsVisible(true),
    });
    return () => onRegisterApi(paneId, null);
  }, [paneId, onRegisterApi, interaction]);

  useEffect(() => {
    onInteractionState?.(paneId, { hasProducer, hasPending: !!interaction });
  }, [paneId, hasProducer, interaction, onInteractionState]);

  useEffect(() => {
    if (active && interaction) setInteractionVisible(true);
  }, [active, interaction]);

  function respondToInteraction(response: Record<string, unknown>) {
    const socket = socketRef.current;
    if (!interaction || socket?.readyState !== WebSocket.OPEN) return;
    socket.send(JSON.stringify({ type: 'interaction_response', request: interaction, response, paneId }));
    setInteractionVisible(false);
  }

  function onDragOver(event: React.DragEvent) {
    if (!Array.from(event.dataTransfer.types).includes('Files')) return;
    event.preventDefault();
    event.dataTransfer.dropEffect = 'copy';
    setDropActive(true);
  }

  function onDragLeave(event: React.DragEvent) {
    if (event.currentTarget.contains(event.relatedTarget as Node)) return;
    setDropActive(false);
  }

  async function onDrop(event: React.DragEvent) {
    const files = Array.from(event.dataTransfer.files);
    if (files.length === 0) return;
    event.preventDefault();
    setDropActive(false);
    const paths: string[] = [];
    for (const file of files) {
      const savedPath = await uploadFile(file);
      if (savedPath) paths.push(shellQuote(savedPath));
    }
    if (paths.length > 0) send(`${paths.join(' ')} `);
  }

  function onTouchStart(event: React.TouchEvent) {
    if (event.touches.length !== 1) return;
    const touch = event.touches[0];
    touchLastYRef.current = touch.clientY;
    touchStartRef.current = { x: touch.clientX, y: touch.clientY, moved: false };
  }

  function onTouchMove(event: React.TouchEvent) {
    const term = termRef.current;
    const lastY = touchLastYRef.current;
    if (!term || event.touches.length !== 1 || lastY === null) return;
    event.preventDefault();
    const touch = event.touches[0];
    const start = touchStartRef.current;
    if (start && Math.hypot(touch.clientX - start.x, touch.clientY - start.y) > 8) start.moved = true;
    const deltaPx = lastY - touch.clientY;
    touchLastYRef.current = touch.clientY;
    touchScrollRemainderRef.current += deltaPx / Math.max(1, fontSize * 1.35);
    const deltaLines = Math.trunc(touchScrollRemainderRef.current);
    if (deltaLines !== 0) {
      term.scrollLines(deltaLines);
      touchScrollRemainderRef.current -= deltaLines;
    }
  }

  function onTouchEnd(event: React.TouchEvent) {
    const start = touchStartRef.current;
    touchLastYRef.current = null;
    touchScrollRemainderRef.current = 0;
    touchStartRef.current = null;
    if (!start || start.moved) return;
    event.preventDefault();
    onOpenCommandInput?.();
  }

  return (
    <div
      className={`terminal-wrap${dropActive ? ' drop-active' : ''}`}
      data-status={status}
      onDragOver={onDragOver}
      onDragLeave={onDragLeave}
      onDrop={onDrop}
    >
      <div
        ref={hostRef}
        className="xterm-host"
        onTouchStart={onTouchStart}
        onTouchMove={onTouchMove}
        onTouchEnd={onTouchEnd}
        onTouchCancel={onTouchEnd}
      />
      {dropActive ? <div className="drop-overlay" aria-hidden="true">Drop to add file path</div> : null}
      {interaction && interactionVisible ? (
        <InteractionPaneModal
          request={interaction}
          onClose={() => setInteractionVisible(false)}
          onDismiss={() => respondToInteraction({ kind: 'dismiss' })}
          onRespond={respondToInteraction}
        />
      ) : null}
      {quickInputsVisible ? <QuickInputsModal onClose={() => setQuickInputsVisible(false)} onSend={(data) => { send(data); setQuickInputsVisible(false); }} /> : null}
      <div className="terminal-accessory" aria-label="Terminal shortcuts">
        <button onClick={() => send('\x1b')}>Esc</button>
        <button onClick={() => send('\t')}>Tab</button>
        <button onClick={() => send('\x03')}>Ctrl-C</button>
        <button onClick={() => send('\r')}>Enter</button>
        <button onClick={() => send('[A')}>↑</button>
        <button onClick={() => send('[B')}>↓</button>
      </div>
    </div>
  );
}
