# smux architecture

`smux` is a browser-native, mobile-capable cmux-inspired terminal surface for Scryer.

The target is intentionally narrow and clean:

- desktop: vertical workspace sidebar + terminal pane
- mobile: focused terminal pane + terminal shortcut keys
- no inline browser
- no notifications
- no Claude Code Teams integration
- no dashboard/status-card extras

## Runtime

- UI dev port: `43218`
- Local terminal backend: `43220`
- Existing Scryer PM API: `43210`

`npm run dev` starts both the Vite UI and the local terminal backend.

## Terminal renderer

React is the application shell. The terminal uses xterm in the browser, connected to a real local shell over WebSocket.

Ghostty/cmux compatibility is represented through defaults:

- terminal font default: `Menlo`, matching cmux/Ghostty config defaults found in cmux source
- font fallback stack: `Menlo`, `SF Mono`, `Berkeley Mono`, `JetBrains Mono`, `Monaco`, `Consolas`, monospace
- One Dark/Ghostty-compatible terminal colors

Browser apps cannot read the user’s local `~/.config/ghostty/config` directly. A later local backend can expose an explicit, safe config import if desired.

## Local terminal backend

The local backend exposes:

- `GET /healthz`
- `WS /api/terminal`

Client sends:

```ts
{ type: 'input', data: string }
{ type: 'interrupt' }
{ type: 'resize', cols: number, rows: number }
```

Server sends:

```ts
{ type: 'status', status: 'connected' | 'exited', shell: string, cwd: string }
{ type: 'output', data: string }
```

The current backend spawns the user shell in the repo root. This is a local development terminal backend, not a public service.

## Future tmuxer integration

The terminal transport can later be swapped to Scryer tmuxer:

1. create or attach tmux session
2. stream output into xterm
3. send xterm input to tmuxer
4. forward resize events

The UI should remain the same: clean sidebar, one terminal workspace, mobile terminal focus.
