# Fresh bifurcated backend prototype

This repo now contains a fresh, additive prototype of the next amux/smux backend split. It does **not** replace the existing `server/` backend.

## Folders

```text
server/          existing monolithic scryer-cmux backend; leave intact
server-pty/      fresh machine-local PTY backend prototype
server-gateway/  fresh gateway/backend-registry/proxy prototype
```

## Goal

The target architecture is:

```text
Browser frontend
  -> amux gateway / backend registry / proxy
    -> tailnet or tunnel
      -> machine-local PTY backend
```

The browser should eventually talk to one trusted gateway origin. The gateway selects a registered backend by ID and proxies HTTP/WebSocket traffic to that machine-local PTY runtime.

## Current prototype

### `server-pty/`

`server-pty/pty-server.mjs` is a fresh standalone PTY backend with current scryer-cmux feature parity as its starting point:

- PTY-backed shell sessions
- `/api/state`
- `/api/upload`
- `/api/pm/*` proxy
- `/api/sessions/:paneId` delete
- `/api/terminal?paneId=...` WebSocket
- replay buffer
- producer marker detection
- interaction polling/update forwarding

Defaults:

```text
AMUX_PTY_API_PORT=43222
state file: .amux-pty-state.json
uploads: $TMPDIR/amux-pty-uploads
```

### `server-gateway/`

`server-gateway/gateway-server.mjs` is a fresh gateway/proxy prototype.

It exposes:

```text
GET /healthz
GET /api/backends
GET /api/backends/:backendId/health
/api/backends/:backendId/* -> proxied to the backend's /api/*
WS /api/backends/:backendId/terminal?paneId=... -> proxied to backend /api/terminal
```

For compatibility with the current frontend, it also proxies existing routes to the `local` backend:

```text
/api/state
/api/upload
/api/pm/*
/api/sessions/*
WS /api/terminal?paneId=...
```

Defaults:

```text
AMUX_GATEWAY_PORT=43223
AMUX_LOCAL_PTY_URL=http://127.0.0.1:43222
```

The default backend registry contains one local backend:

```json
{
  "id": "local",
  "label": "Local PTY",
  "kind": "pty",
  "baseUrl": "http://127.0.0.1:43222",
  "transport": "local",
  "capabilities": ["terminal", "state", "upload", "pm-proxy"]
}
```

A static registry can be supplied with `AMUX_BACKENDS_JSON`.

## Run

Existing monolithic dev flow remains:

```bash
npm run dev
```

Fresh bifurcated prototype:

```bash
npm run dev:bifurcated
```

That starts:

- PTY backend on `43222`
- gateway on `43223`
- Vite frontend pointed at gateway port `43223`

Individual pieces:

```bash
npm run dev:pty
npm run dev:gateway
npm run dev:ui
```

If running pieces separately and using the UI against the gateway, start Vite with:

```bash
VITE_SCRYER_CMUX_API_PORT=43223 npm run dev:ui
```

## Feature parity burden

The fresh split must preserve current scryer-cmux behavior while introducing backend IDs and proxying:

- workspace state load/save
- terminal WebSocket attach/input/resize/output/replay
- session kill/delete
- uploads where returned paths are visible to the PTY runtime
- Scryer PM proxy
- producer marker detection
- interaction request/update delivery
- interaction responses
- health/status

## Known gaps / next steps

- Backend registry is static/env-based; no PTY self-registration or heartbeat yet.
- Gateway health status is not cached in `/api/backends`; `/api/backends/:id/health` proxies live.
- Uploads are compatibility-proxied to the PTY backend so paths remain local to the PTY machine; this is correct for the split, but remote/tunnel deployments need validation.
- Frontend still uses the old global `API_BASE`/`WS_BASE`; it can target the gateway through the existing port env, but it is not yet backend-ID-aware.
- No public-internet auth is implemented; this is a tailnet-only prototype.
