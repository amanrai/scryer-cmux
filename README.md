# smux

`smux` is a single-user, stateful browser terminal server inspired by cmux. It runs a local Node backend on a machine, keeps a global set of workspaces/panes on that server, and lets a browser connect to those real shell sessions over WebSockets.

The repository is still named `scryer-cmux`, but the UI/product name is `smux`.

## What it does

- Runs real PTY-backed shells in the browser via `xterm.js` + `node-pty`.
- Keeps one global server-side workspace graph for the machine.
- Supports multiple workspaces.
- Supports split terminal panes.
- Preserves workspace metadata across browser refreshes and backend restarts.
- Preserves live terminal sessions across browser refreshes while the backend process stays alive.
- Provides a command palette with `Cmd/Ctrl+K` for workspace and pane actions.
- Works well over a private network or Tailscale tailnet.

## Architecture

There are two processes in development:

1. **Terminal backend**
   - File: `server/terminal-server.mjs`
   - Default port: `43220`
   - Binds to `0.0.0.0`
   - Owns the global server state
   - Spawns PTY shells with `node-pty`
   - Serves:
     - `GET /healthz`
     - `GET /api/state`
     - `PUT /api/state`
     - `POST /api/state`
     - `DELETE /api/sessions/:paneId`
     - `WS /api/terminal?paneId=...`

2. **Vite frontend**
   - Default port: `43221`
   - Browser UI for workspaces, panes, command palette, and xterm rendering.

The browser is intentionally thin. The backend is the source of truth for workspace state.

## State model

`smux` is designed as a **single-user machine server**.

That means:

- There is one global workspace list for the backend process.
- There is one global set of PTY sessions keyed by pane ID.
- Any browser that connects to the server sees the same workspaces.
- There is no per-user auth, account model, or multi-tenant isolation.

Workspace metadata is persisted to:

```text
.smux-state.json
```

This file is ignored by git.

Live terminal processes are kept in memory by the running backend. They survive browser refreshes, but they do **not** survive backend restarts. After a backend restart, the workspace/pane layout returns from `.smux-state.json`, and panes reconnect by ID, but their shell processes will be new.

## Requirements

Install these on the machine that will run the server:

- Node.js 22 or newer
- npm
- A POSIX shell such as `zsh` or `bash`
- Build tools required by native Node packages if your platform cannot use the bundled `node-pty` prebuild

Optional but recommended:

- Tailscale, if you want to access the server from other devices on your tailnet.

On macOS with the Tailscale app installed, `smux` can read the MagicDNS name from:

```text
/Applications/Tailscale.app/Contents/MacOS/Tailscale status --json
```

If the `tailscale` CLI is installed in `PATH`, that works too.

## Fresh setup on a machine

Clone the repo:

```bash
git clone git@github.com:amanrai/scryer-cmux.git
cd scryer-cmux
```

Install dependencies:

```bash
npm install
```

The install runs:

```bash
node server/fix-node-pty.mjs
```

That script fixes executable permissions on the macOS `node-pty` `spawn-helper` binary when needed.

## Run in development

Start both backend and frontend:

```bash
npm run dev
```

This starts:

- backend terminal server on `43220`
- Vite frontend on `43221`

Open the frontend locally:

```text
http://localhost:43221/
```

Or from another device on your network/tailnet:

```text
http://<machine-name-or-tailnet-name>:43221/
```

Examples:

```text
http://amans-macbook-pro.tail466ab8.ts.net:43221/
http://192.168.0.102:43221/
```

The frontend connects back to the backend on the same hostname at port `43220`.

## Run the pieces separately

Backend only:

```bash
npm run dev:terminal
```

Frontend only:

```bash
npm run dev:ui
```

This is useful when debugging one side at a time.

## Verify the backend

Health check:

```bash
curl http://127.0.0.1:43220/healthz
```

State check:

```bash
curl http://127.0.0.1:43220/api/state
```

Expected shape:

```json
{
  "workspaces": [
    {
      "id": "workspace-...",
      "name": "smux",
      "color": "#E5C07B",
      "cwdLabel": "repos/scryer-cmux",
      "branchLabel": "main",
      "layout": "row",
      "panes": [
        {
          "id": "pane-...",
          "title": "Terminal 1",
          "createdAt": 1781799159865
        }
      ],
      "activePaneId": "pane-..."
    }
  ],
  "activeWorkspaceId": "workspace-...",
  "hostName": "machine.tailnet.ts.net"
}
```

## Tailscale notes

For tailnet access:

1. Install and sign into Tailscale on the server machine.
2. Make sure the client device is on the same tailnet.
3. Start `smux` on the server machine.
4. Open:

```text
http://<tailscale-magicdns-name>:43221/
```

The backend listens on `0.0.0.0:43220`, and Vite listens on `0.0.0.0:43221` via `vite --host 0.0.0.0`, so tailnet clients can reach both ports.

If the UI shows `offline` in the toolbar, check that the browser can reach:

```text
http://<same-hostname>:43220/api/state
```

## Using the app

Open the command palette:

```text
Cmd+K on macOS
Ctrl+K elsewhere
```

Available actions include:

- New workspace
- Rename workspace
- Duplicate workspace
- Move workspace up/down
- Close workspace
- Set workspace color
- Switch workspace
- Split pane right
- Split pane down
- Close active pane
- Switch pane

The left nav contains workspaces. You can:

- click a workspace to activate it
- drag workspaces to reorder them
- click the small `×` to close a workspace
- collapse/expand the nav with the sidebar button

Workspace colors apply to the small rectangular marker in the nav.

## Terminal behavior

Each pane maps to one backend PTY session.

- Creating a pane creates a new server PTY session.
- Refreshing the browser reconnects to the same pane ID/session.
- Closing a pane kills the backend PTY for that pane.
- Closing a workspace kills all PTYs in that workspace.
- New terminal sessions start in `~`.

The backend keeps a small replay buffer per pane so recent output is restored after refresh.

## Build

Create a production build:

```bash
npm run build
```

Preview the production build:

```bash
npm run preview
```

By default, `preview` uses Vite's preview server and does not replace the terminal backend. For a real deployment, run the backend and serve the built frontend with your preferred static server or process manager.

## Typecheck

```bash
npm run typecheck
```

## Running long-term

For regular use on a machine, run the backend/frontend under a process manager instead of an interactive shell.

Options:

- `tmux` / `screen`
- `pm2`
- `systemd` on Linux
- `launchd` on macOS

The simplest manual option is:

```bash
npm run dev
```

For production-ish use, you may want separate processes:

```bash
npm run dev:terminal
npm run dev:ui
```

Or build the frontend and serve `dist/` separately while keeping `server/terminal-server.mjs` running.

## Security model

`smux` exposes an interactive shell. Treat it like SSH access to the machine.

Current assumptions:

- single trusted user
- private machine or private tailnet
- no public internet exposure
- no authentication in the app itself

Do **not** expose ports `43220` or `43221` directly to the public internet unless you add authentication and transport security in front of them.

Recommended access pattern:

- Tailscale tailnet only
- trusted devices only
- firewall public access to both ports

## Troubleshooting

### Browser says `offline`

Check backend reachability:

```bash
curl http://127.0.0.1:43220/api/state
```

From another device, use the same hostname you opened the frontend with:

```bash
curl http://<host>:43220/api/state
```

If that fails, the frontend cannot save/load server state.

### Refresh creates a new terminal

Make sure you restarted the backend after pulling the latest code. The server must support stateful pane sessions and `/api/state`.

Also check that the frontend is not blocked from reaching backend port `43220`.

### Workspace list disappears after restart

Workspace metadata is stored in `.smux-state.json`. If that file is deleted, the server starts with a default single workspace.

### Terminal prompt does not appear

The backend must use `node-pty`, not plain `child_process.spawn`. Reinstall dependencies and rerun the postinstall fix:

```bash
npm install
npm run postinstall
```

### `node-pty` fails with `posix_spawnp failed` on macOS

Run:

```bash
npm run postinstall
```

That makes the bundled `spawn-helper` executable.

### Machine name shows `smux` or `.local` instead of tailnet name

Make sure Tailscale is installed and signed in. On macOS, the app binary should exist at:

```text
/Applications/Tailscale.app/Contents/MacOS/Tailscale
```

You can test:

```bash
/Applications/Tailscale.app/Contents/MacOS/Tailscale status --json
```

If Tailscale is unavailable, the backend falls back to `os.hostname()`.

## Repository layout

```text
server/
  terminal-server.mjs    # stateful PTY/WebSocket/API backend
  fix-node-pty.mjs       # macOS node-pty permission fix
src/
  App.tsx                # workspace/pane shell
  CommandPalette.tsx     # Cmd/Ctrl+K command palette
  TerminalPane.tsx       # xterm.js WebSocket terminal pane
  styles.css             # app styling
vite.config.ts           # Vite dev server config
```

## Related docs

See [`docs/architecture.md`](docs/architecture.md) for more detail on the terminal renderer and WebSocket backend.
