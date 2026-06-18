import { useEffect, useRef, useState } from 'react';
import { Terminal } from '@xterm/xterm';
import { FitAddon } from '@xterm/addon-fit';
import '@xterm/xterm/css/xterm.css';

const WS_URL = `ws://${window.location.hostname || '127.0.0.1'}:${import.meta.env.VITE_SCRYER_CMUX_API_PORT ?? '43220'}/api/terminal`;

export function TerminalPane() {
  const hostRef = useRef<HTMLDivElement | null>(null);
  const termRef = useRef<Terminal | null>(null);
  const fitRef = useRef<FitAddon | null>(null);
  const socketRef = useRef<WebSocket | null>(null);
  const [status, setStatus] = useState<'connecting' | 'connected' | 'closed'>('connecting');

  useEffect(() => {
    if (!hostRef.current) return;

    const term = new Terminal({
      cursorBlink: true,
      fontFamily: 'ui-monospace, "SF Mono", Menlo, Monaco, Consolas, monospace',
      fontSize: 13,
      lineHeight: 1.35,
      scrollback: 5000,
      convertEol: true,
      theme: {
        background: '#21252B',
        foreground: '#ABB2BF',
        cursor: '#E5C07B',
        selectionBackground: 'rgba(229, 192, 123, 0.25)',
        black: '#282C34',
        red: '#E06C75',
        green: '#98C379',
        yellow: '#E5C07B',
        blue: '#61AFEF',
        magenta: '#C678DD',
        cyan: '#56B6C2',
        white: '#ABB2BF',
        brightBlack: '#5C6370',
        brightRed: '#E06C75',
        brightGreen: '#98C379',
        brightYellow: '#E5C07B',
        brightBlue: '#61AFEF',
        brightMagenta: '#C678DD',
        brightCyan: '#56B6C2',
        brightWhite: '#C8CDD4',
      },
    });
    const fit = new FitAddon();
    term.loadAddon(fit);
    term.open(hostRef.current);
    fit.fit();
    term.focus();
    term.writeln('\x1b[33msmux\x1b[0m connecting to local shell...');

    const socket = new WebSocket(WS_URL);
    socketRef.current = socket;
    termRef.current = term;
    fitRef.current = fit;

    socket.addEventListener('open', () => {
      setStatus('connected');
      socket.send(JSON.stringify({ type: 'resize', cols: term.cols, rows: term.rows }));
    });
    socket.addEventListener('message', (event) => {
      const payload = JSON.parse(event.data);
      if (payload.type === 'output') term.write(payload.data);
      if (payload.type === 'status' && payload.status === 'connected') {
        term.writeln(`\r\n\x1b[2mconnected: ${payload.shell} · ${payload.cwd}\x1b[0m\r\n`);
      }
    });
    socket.addEventListener('close', () => {
      setStatus('closed');
      term.writeln('\r\n\x1b[31m[terminal disconnected]\x1b[0m');
    });
    socket.addEventListener('error', () => {
      term.writeln('\r\n\x1b[31m[terminal server unavailable — run npm run dev]\x1b[0m');
    });

    const dataDisposable = term.onData((data) => {
      if (socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify({ type: 'input', data }));
    });

    const resizeObserver = new ResizeObserver(() => {
      fit.fit();
      if (socket.readyState === WebSocket.OPEN) {
        socket.send(JSON.stringify({ type: 'resize', cols: term.cols, rows: term.rows }));
      }
    });
    resizeObserver.observe(hostRef.current);

    return () => {
      dataDisposable.dispose();
      resizeObserver.disconnect();
      socket.close();
      term.dispose();
    };
  }, []);

  function send(data: string) {
    const socket = socketRef.current;
    if (socket?.readyState === WebSocket.OPEN) socket.send(JSON.stringify({ type: 'input', data }));
    termRef.current?.focus();
  }

  return (
    <div className="terminal-wrap">
      <div className="terminal-status"><span className={`tiny-dot ${status}`} /> local shell</div>
      <div ref={hostRef} className="xterm-host" />
      <div className="terminal-accessory" aria-label="Terminal shortcuts">
        <button onClick={() => send('\x1b')}>Esc</button>
        <button onClick={() => send('\t')}>Tab</button>
        <button onClick={() => send('\x03')}>Ctrl-C</button>
        <button onClick={() => send('\r')}>Enter</button>
        <button onClick={() => send('\u001b[A')}>↑</button>
        <button onClick={() => send('\u001b[B')}>↓</button>
      </div>
    </div>
  );
}
