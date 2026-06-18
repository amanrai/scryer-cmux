# smux

Clean browser/mobile terminal surface inspired by cmux, built for Scryer.

Current scope is intentionally small:

- vertical workspace sidebar on desktop
- real terminal pane in the browser
- focused terminal-first layout on mobile
- mobile terminal shortcut keys
- Ghostty/cmux-compatible font and color defaults

No inline browser. No notifications. No Claude Code Teams integration. No dashboard extras.

## Running locally

```bash
npm install
npm run dev
```

Open:

```text
http://127.0.0.1:43218
```

`npm run dev` starts:

- Vite UI on `43218`
- local terminal backend on `43220`

## Build

```bash
npm run build
```

## Notes

The repo/project is still named `scryer-cmux` for now, but the product UI is `smux`.

See [`docs/architecture.md`](docs/architecture.md) for the terminal renderer and local WebSocket backend.
