# So Much For Subtlety — Architecture

Native client for **smux** (the scryer-cmux gateway). cmux-style workspaces, Scryer
integration, and **Ghostty-grade terminal emulation** so agent TUIs render correctly.

Target platforms: macOS first, then iPad and iPhone from one shared core.

---

## 1. What this talks to

The repo already ships a bifurcated backend (see `../docs/bifurcated-backend.md`):

```
This app
  → server-gateway   (registry + HTTP/WS proxy, default :43223)
    → tailnet/tunnel
      → server-pty    (machine-local PTY runtime, default :43222)
```

The gateway is the single origin we connect to. It exposes:

- `GET  /api/backends` — list registered PTY machines (`id`, `label`, `status`, …)
- `GET  /api/backends/:id/state` — workspace/pane graph for that machine
- `PUT/POST /api/backends/:id/state` — persist layout
- `DELETE /api/backends/:id/sessions/:paneId` — kill a PTY session
- `WS   /api/backends/:id/terminal?paneId=…` — attach to a PTY session

The browser reference client is `../gateway-ui`. Its `TerminalPane.tsx` is the
protocol spec we mirror.

### Terminal WebSocket protocol (mirrors gateway-ui)

Client → server (JSON text frames):
- `{ type: "input",   data, paneId }`
- `{ type: "paste",   text, paneId }`        — bracketed paste (`\e[200~ … \e[201~`)
- `{ type: "interrupt", paneId }`
- `{ type: "resize",  cols, rows, paneId }`
- `{ type: "interaction_response", request, response, paneId }`  (Scryer — later)

Server → client:
- `{ type: "output", data, replay? }`        — terminal bytes; `replay:true` = restored buffer
- `{ type: "status", status, cols, rows, … }`
- `{ type: "interaction" | "interaction_clear" | "interaction_producer" | "session_updates", … }` (Scryer — later)

On connect: server sends a `status` then (optionally) a single `output` with
`replay:true` carrying the replay buffer. We `vt_write()` the replay, then live
output, into the same terminal instance. Reattach is by `paneId`.

---

## 2. Terminal engine: libghostty-vt + custom Metal renderer

We use **libghostty-vt** — the headless VT core extracted from Ghostty. It does
parsing, terminal state, reflow, scrollback, Unicode/grapheme handling, and
key/mouse encoding. It ships **no renderer**; it exposes a render-state API and
we draw with Metal. (This is the same split ghostling demonstrates with Raylib.)

Pinned Ghostty commit: `ae52f97dcac558735cfa916ea3965f247e5c6e9e`
(matches the API surface this code was written against; bump deliberately).

### Data flow

```
        WS "output" bytes
              │  ghostty_terminal_vt_write(term, bytes, len)
              ▼
   ┌─────────────────────┐   ghostty_render_state_update(rs, term)
   │  GhosttyTerminal     │ ─────────────────────────────────────▶ Metal renderer
   │  (VT state, scroll)  │   row iterator → cells → glyph atlas → grid draw
   └─────────────────────┘
        ▲            │
        │            │ WRITE_PTY effect (DA/XTVERSION/mode reports …)
        │            ▼
   key/mouse     send over WS as {type:"input"}   ◀── REQUIRED or vim/tmux/htop hang
   encoders
   (encode → WS "input")
```

### Key libghostty-vt C calls we rely on

Lifecycle / IO:
- `ghostty_terminal_new(alloc, &term, GhosttyTerminalOptions{cols,rows,max_scrollback})`
- `ghostty_terminal_resize(term, cols, rows, cellW, cellH)`
- `ghostty_terminal_vt_write(term, bytes, len)` — feed remote output
- `ghostty_terminal_set(term, GHOSTTY_TERMINAL_OPT_USERDATA, ctx)`
- `ghostty_terminal_set(term, GHOSTTY_TERMINAL_OPT_WRITE_PTY, &effect_write_pty)`
- also set `OPT_SIZE`, `OPT_DEVICE_ATTRIBUTES`, `OPT_XTVERSION`,
  `OPT_TITLE_CHANGED`, `OPT_COLOR_SCHEME`
- `ghostty_terminal_get(term, GHOSTTY_TERMINAL_DATA_TITLE | _MOUSE_TRACKING | _SCROLLBAR, …)`
- `ghostty_terminal_scroll_viewport(term, {tag:DELTA, value:{delta}})`
- `ghostty_terminal_free(term)`

Input encoding (encoder reads terminal modes → emits exact VT bytes):
- `ghostty_key_encoder_new`, `ghostty_key_event_new`
- `ghostty_key_encoder_setopt_from_terminal(enc, term)`
- `ghostty_key_event_set_{key,action,mods,unshifted_codepoint,consumed_mods,utf8}`
- `ghostty_key_encoder_encode(enc, event, buf, cap, &written)` → write bytes to WS
- mouse equivalents: `ghostty_mouse_encoder_*`, `ghostty_mouse_event_*`

Render state (rebuilt each frame from the terminal):
- `ghostty_render_state_new`, `_row_iterator_new`, `_row_cells_new`
- `ghostty_render_state_update(rs, term)` then `_get(rs, ROW_ITERATOR, &it)`
- `ghostty_render_state_colors_get(rs, &colors)` — palette + default fg/bg
- iterate: `_row_iterator_next(it)` → `_row_get(it, ROW_DATA_CELLS, &cells)`
- cells: `_row_cells_next(cells)` → `_row_cells_get(cells, …)` for
  `GRAPHEMES_LEN`, `GRAPHEMES_BUF`, `FG_COLOR`, `BG_COLOR`, and `GhosttyStyle` flags

Types: `GhosttyResult` (`GHOSTTY_SUCCESS`), `GhosttyColorRgb{r,g,b}`,
`GhosttyStyle` (use `GHOSTTY_INIT_SIZED`).

> Kitty graphics protocol is exposed too (`ghostty_kitty_graphics_*`) — parked
> until after the text renderer is solid. Inline images come later.

---

## 3. Swift module layout (SwiftPM)

```
Package.swift
Vendor/libghostty-vt/         built artifact (see build.sh); not committed binary
  build.sh                    zig build lib-vt @ pinned commit → include/ + lib/
  include/ghostty/vt.h        vendored header
  lib/libghostty-vt.a         vendored static lib
Sources/
  CGhosttyVT/                 systemLibrary target → module.modulemap over vt.h
  ScryerCore/                 pure-Swift, platform-agnostic
    Gateway/  GatewayClient, BackendMachine, GatewayConfig
    Terminal/ TerminalProtocol (WS message codec), TerminalSession (URLSessionWebSocketTask),
              TerminalEngine (protocol), GhosttyVTEngine (C bridge), GhosttyKeymap
    Model/    Workspace/Pane/AppState
  ScryerRender/               Metal renderer: GlyphAtlas, TerminalRenderer, cell pipeline
  SoMuchForSubtlety/          @main SwiftUI app (macOS): BackendPicker, TerminalSurface (NSViewRepresentable)
```

`ScryerCore` and `ScryerRender` are reusable by the future iOS/iPad Xcode
targets. The `SoMuchForSubtlety` executable is the macOS bring-up app.

### The engine seam

```swift
protocol TerminalEngine: AnyObject {
    var delegate: TerminalEngineDelegate? { get set }   // onWriteBack(bytes), onTitle, onBell, setNeedsDisplay
    func resize(cols: Int, rows: Int, cellWidth: Double, cellHeight: Double)
    func feed(_ bytes: [UInt8])                          // WS output → vt_write
    func sendKey(_ event: KeyEvent)                      // → encoder → delegate.onWriteBack
    func sendMouse(_ event: MouseEvent)
    func scrollViewport(deltaRows: Int)
    func withRenderSnapshot(_ body: (RenderSnapshot) -> Void)  // for the Metal pass
}
```

`GhosttyVTEngine` is the only implementation (no SwiftTerm fallback — Ghostty core
per product decision). `delegate.onWriteBack` is wired to the WebSocket `input`
channel, so BOTH user keystrokes and terminal query responses go back to the PTY.

---

## 4. Build / bring-up order

1. **Gateway + backend selection** (pure Swift, no libghostty): list `/api/backends`,
   pick an online PTY machine, persist choice. ← core piece 1
2. **Terminal session**: open WS, mirror the protocol, prove round-trip.
3. **libghostty-vt vendoring**: run `Vendor/libghostty-vt/build.sh` (needs `zig`).
4. **GhosttyVTEngine**: bridge the C API; wire `vt_write` + `WRITE_PTY` + encoders.
5. **Metal renderer**: glyph atlas (JetBrains Mono Nerd Font), cell grid, cursor,
   selection. ← where "exceptional" is won.
6. Iterate: scrollback UI, resize/reflow polish, then Scryer overlays + Kitty images.

Scryer interaction/activity/picker features come **after** the terminal is great
(server already delivers them over the same WS, so the client gets them cheaply).

## 5. Build commands

```bash
# one-time: build the Ghostty VT core (requires zig on PATH)
cd "So Much For Subtlety" && ./Vendor/libghostty-vt/build.sh

# build / run the macOS bring-up app
swift build
swift run SoMuchForSubtlety
```
