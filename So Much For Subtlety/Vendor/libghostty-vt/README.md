# libghostty-vt (vendored)

The headless VT core extracted from [Ghostty](https://ghostty.org). It does VT
parsing, terminal state, reflow, scrollback, Unicode/grapheme handling, and
key/mouse encoding — but **no rendering** (we draw with Metal in `ScryerRender`).

## Build

```bash
./build.sh          # requires `zig` on PATH
```

Produces:
- `include/ghostty/vt.h` — the C API header
- `lib/libghostty-vt.a` — the static library

Both are git-ignored; run `build.sh` after cloning. Pinned to Ghostty commit
`ae52f97dcac558735cfa916ea3965f247e5c6e9e` (bump in `build.sh` deliberately).

## Reference

- C API usage example: https://github.com/ghostty-org/ghostling (`main.c`)
- API docs: https://libghostty.tip.ghostty.org/
