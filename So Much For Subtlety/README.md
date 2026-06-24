# So Much For Subtlety

Native client for **smux** (the scryer-cmux gateway). Connect to a gateway, pick a
backend machine, and drive a real PTY with **Ghostty-grade** terminal emulation
(libghostty-vt) so agent TUIs render correctly. macOS first; iPad/iPhone share the
core.

See [`ARCHITECTURE.md`](ARCHITECTURE.md) for the full design and the libghostty-vt
integration.

## Status

| Piece | State |
|-------|-------|
| Gateway connect + **backend selection** | ✅ runnable now (`ScryerCore` + app) |
| Terminal WebSocket round-trip | ✅ bring-up view (connect / output / input) |
| libghostty-vt vendoring | ⏳ `Vendor/libghostty-vt/build.sh` (needs `zig`) |
| `GhosttyVTEngine` bridge | ✅ written vs pinned header; needs first compile |
| Metal terminal renderer | ⏳ next milestone (where "exceptional" is won) |
| Scryer overlays (interaction/activity/picker) | later, iteratively |

## Run the bring-up app (no libghostty needed yet)

```bash
swift run SoMuchForSubtlety
```

Enter a gateway host (e.g. `machine.tailnet.ts.net:43223`), pick an online machine,
and you get a live PTY session (output + input) proving the path end-to-end.

Verify the core in isolation:

```bash
swift build --target ScryerCore
swift test
```

## Build the Ghostty terminal core

```bash
./Vendor/libghostty-vt/build.sh     # requires zig on PATH
```

Then add `ScryerGhostty` / `ScryerRender` back to the app target in `Package.swift`
and build the full app.

## Layout

```
Package.swift
Vendor/libghostty-vt/     build.sh → header + static lib (git-ignored)
Sources/
  CGhosttyVT/             C module over ghostty/vt.h
  ScryerCore/             gateway, websocket, models, engine protocol (pure Swift)
  ScryerGhostty/          GhosttyVTEngine — libghostty-vt bridge
  ScryerRender/           Metal renderer (skeleton)
  SoMuchForSubtlety/      macOS SwiftUI app
Tests/ScryerCoreTests/
```
