import { useEffect, useRef, useState } from 'react';
import { Terminal } from '@xterm/xterm';
import { FitAddon } from '@xterm/addon-fit';
import { ImageAddon } from '@xterm/addon-image';
import '@xterm/xterm/css/xterm.css';
import { WS_BASE } from './constants';
import { terminalTheme } from './terminal/theme';
import { shellQuote, uploadFile } from './terminal/upload';
import type { PaneStatus } from './types';

export type TerminalPaneApi = {
  sendInput: (data: string) => void;
  getRecentLines: (count?: number) => string[];
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
};

export function TerminalPane({ paneId, active, accentColor, fontSize, focusToken, onStatus, onRegisterApi, onOpenCommandInput }: TerminalPaneProps) {
  const hostRef = useRef<HTMLDivElement | null>(null);
  const termRef = useRef<Terminal | null>(null);
  const fitRef = useRef<FitAddon | null>(null);
  const socketRef = useRef<WebSocket | null>(null);
  const touchLastYRef = useRef<number | null>(null);
  const touchScrollRemainderRef = useRef(0);
  const touchStartRef = useRef<{ x: number; y: number; moved: boolean } | null>(null);
  const [status, setStatus] = useState<PaneStatus>('connecting');
  const [dropActive, setDropActive] = useState(false);

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
    });
    return () => onRegisterApi(paneId, null);
  }, [paneId, onRegisterApi]);

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
