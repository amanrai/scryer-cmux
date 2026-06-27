import Foundation
import CGhosttyVT
import ScryerCore

/// `TerminalEngine` backed by libghostty-vt: Ghostty's own VT emulation core fed by
/// our WebSocket, rendered by `ScryerRender`. See `ARCHITECTURE.md` §2.
///
/// libghostty is single-threaded per terminal and its effect callbacks fire
/// synchronously inside `vt_write` (no reentrancy). We therefore drive the whole
/// engine from one thread — the main thread, where `TerminalSession` lives.
///
/// NOTE: written against pinned Ghostty commit ae52f97; not yet compiled. Expect a
/// few FFI adjustments (notably the `GhosttyMods`/`GhosttyKey` integer casts and the
/// function-pointer `set` calls) on first build.
public final class GhosttyVTEngine: TerminalEngine {
    public weak var delegate: TerminalEngineDelegate?

    private var terminal: GhosttyTerminal?
    private var renderState: GhosttyRenderState?
    private var rowIterator: GhosttyRenderStateRowIterator?
    private var rowCells: GhosttyRenderStateRowCells?
    private var keyEncoder: GhosttyKeyEncoder?
    private var keyEvent: GhosttyKeyEvent?

    private var cols: Int = 80
    private var rows: Int = 24
    private var theme: TerminalTheme

    public init(cols: Int = 80, rows: Int = 24, maxScrollback: Int = 10_000,
                theme: TerminalTheme = AppTheme.oneDark.terminal) {
        self.cols = cols
        self.rows = rows
        self.theme = theme

        var term: GhosttyTerminal?
        let options = GhosttyTerminalOptions(cols: UInt16(cols), rows: UInt16(rows), max_scrollback: maxScrollback)
        guard ghostty_terminal_new(nil, &term, options) == GHOSTTY_SUCCESS, let term else {
            fatalError("ghostty_terminal_new failed")
        }
        self.terminal = term

        // Route effect callbacks back to this instance.
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        ghostty_terminal_set(term, GHOSTTY_TERMINAL_OPT_USERDATA, UnsafeRawPointer(selfPtr))
        ghostty_terminal_set(term, GHOSTTY_TERMINAL_OPT_WRITE_PTY, unsafeBitCast(Self.writePtyEffect, to: UnsafeRawPointer.self))
        ghostty_terminal_set(term, GHOSTTY_TERMINAL_OPT_TITLE_CHANGED, unsafeBitCast(Self.titleChangedEffect, to: UnsafeRawPointer.self))

        // Apply the theme's fg/bg/cursor/palette. Without these the defaults read back
        // as black (invisible cursor / default text).
        applyColors()

        // Render-state handles, reused every frame.
        ghostty_render_state_new(nil, &renderState)
        ghostty_render_state_row_iterator_new(nil, &rowIterator)
        ghostty_render_state_row_cells_new(nil, &rowCells)

        // Key encoder + a reusable event.
        ghostty_key_encoder_new(nil, &keyEncoder)
        ghostty_key_event_new(nil, &keyEvent)

        _ = withVtUnused() // silence unused in case of later refactors
    }

    /// Re-apply the current theme's colors to the live terminal (init + theme switch).
    private func applyColors() {
        guard let terminal else { return }
        var fg = theme.foreground.ghostty
        var bg = theme.background.ghostty
        var cur = theme.cursor.ghostty
        ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_COLOR_FOREGROUND, &fg)
        ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_COLOR_BACKGROUND, &bg)
        ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_COLOR_CURSOR, &cur)
        let palette = GhosttyVTEngine.palette(ansi16: theme.ansi16)
        palette.withUnsafeBufferPointer { buffer in
            _ = ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_COLOR_PALETTE, buffer.baseAddress)
        }
    }

    /// Switch theme live — the next snapshot picks up the new colors.
    public func setTheme(_ theme: TerminalTheme) {
        self.theme = theme
        applyColors()
        delegate?.terminalEngineNeedsRedraw(self)
    }

    /// 256-color palette: the theme's ANSI 0–15, standard xterm cube + grayscale 16–255.
    private static func palette(ansi16: [ThemeRGB]) -> [GhosttyColorRgb] {
        func rgb(_ r: Int, _ g: Int, _ b: Int) -> GhosttyColorRgb {
            GhosttyColorRgb(r: UInt8(r), g: UInt8(g), b: UInt8(b))
        }
        var palette = [GhosttyColorRgb](repeating: rgb(0, 0, 0), count: 256)
        for (index, color) in ansi16.prefix(16).enumerated() { palette[index] = color.ghostty }
        let steps = [0, 95, 135, 175, 215, 255]
        var index = 16
        for r in 0..<6 { for g in 0..<6 { for b in 0..<6 {
            palette[index] = rgb(steps[r], steps[g], steps[b]); index += 1
        } } }
        for i in 0..<24 { let v = 8 + i * 10; palette[232 + i] = rgb(v, v, v) }
        return palette
    }

    deinit {
        if let keyEvent { ghostty_key_event_free(keyEvent) }
        if let keyEncoder { ghostty_key_encoder_free(keyEncoder) }
        if let rowCells { /* freed by render_state? cells handle has no explicit free in header beyond iterator */ _ = rowCells }
        if let rowIterator { ghostty_render_state_row_iterator_free(rowIterator) }
        if let renderState { ghostty_render_state_free(renderState) }
        if let terminal { ghostty_terminal_free(terminal) }
    }

    private func withVtUnused() -> Int { 0 }

    public var alternateScreenActive: Bool {
        guard let terminal else { return false }
        var enabled = false
        _ = ghostty_terminal_mode_get(terminal, ghostty_mode_new(1049, false), &enabled)
        return enabled
    }

    // MARK: TerminalEngine

    public func resize(cols: Int, rows: Int, cellWidth: Double, cellHeight: Double) {
        guard let terminal, cols > 0, rows > 0 else { return }
        self.cols = cols
        self.rows = rows
        ghostty_terminal_resize(terminal, UInt16(cols), UInt16(rows), UInt32(cellWidth.rounded()), UInt32(cellHeight.rounded()))
        delegate?.terminalEngineNeedsRedraw(self)
    }

    public func feed(_ bytes: [UInt8]) {
        guard let terminal, !bytes.isEmpty else { return }
        bytes.withUnsafeBufferPointer { buffer in
            ghostty_terminal_vt_write(terminal, buffer.baseAddress, buffer.count)
        }
        delegate?.terminalEngineNeedsRedraw(self)
    }

    public func scrollViewport(deltaRows: Int) {
        guard let terminal else { return }
        var behavior = GhosttyTerminalScrollViewport()
        behavior.tag = GHOSTTY_SCROLL_VIEWPORT_DELTA
        behavior.value.delta = deltaRows
        ghostty_terminal_scroll_viewport(terminal, behavior)
        delegate?.terminalEngineNeedsRedraw(self)
    }

    public func sendKey(_ event: KeyEvent) {
        guard let terminal, let keyEncoder, let keyEvent else { return }

        ghostty_key_encoder_setopt_from_terminal(keyEncoder, terminal)

        ghostty_key_event_set_action(keyEvent, event.action.ghostty)
        ghostty_key_event_set_key(keyEvent, GhosttyKey(rawValue: event.ghosttyKeyCode))
        ghostty_key_event_set_mods(keyEvent, event.modifiers.ghosttyMods)
        ghostty_key_event_set_unshifted_codepoint(keyEvent, event.unshiftedCodepoint)

        // Shift is "consumed" when the platform already folded it into `text`.
        var consumed: Int32 = 0
        if event.text != nil, event.modifiers.contains(.shift) { consumed |= GHOSTTY_MODS_SHIFT }
        ghostty_key_event_set_consumed_mods(keyEvent, GhosttyMods(consumed))

        // The encoder reads the utf8 text during encode(), so the buffer MUST stay
        // alive across both set_utf8 and encode — keep them in the same scope.
        let textBytes: [CChar]
        if let text = event.text, event.action != .release, !text.isEmpty {
            textBytes = text.utf8.map { CChar(bitPattern: $0) }
        } else {
            textBytes = []
        }

        textBytes.withUnsafeBufferPointer { textBuf in
            ghostty_key_event_set_utf8(keyEvent, textBuf.baseAddress, textBuf.count)

            var out = [CChar](repeating: 0, count: 128)
            var written = 0
            let result = out.withUnsafeMutableBufferPointer { buf in
                ghostty_key_encoder_encode(keyEncoder, keyEvent, buf.baseAddress, buf.count, &written)
            }
            if result == GHOSTTY_SUCCESS, written > 0 {
                delegate?.terminalEngine(self, writeToPTY: out.prefix(written).map { UInt8(bitPattern: $0) })
            }
        }
    }

    public func sendMouse(_ event: MouseEvent) {
        // Mouse encoder bridge lands with the renderer's pixel geometry. (next iteration)
    }

    /// Whether the running program enabled bracketed paste (DEC private mode 2004).
    /// Used to decide whether a paste should be wrapped in paste markers.
    public func bracketedPasteEnabled() -> Bool {
        guard let terminal else { return false }
        var enabled = false
        _ = ghostty_terminal_mode_get(terminal, ghostty_mode_new(2004, false), &enabled)
        return enabled
    }

    public func snapshot() -> TerminalSnapshot {
        guard let terminal, let renderState, let rowIterator, let rowCells else { return .empty }
        guard ghostty_render_state_update(renderState, terminal) == GHOSTTY_SUCCESS else { return .empty }

        var colors = GhosttyRenderStateColors()
        colors.size = MemoryLayout<GhosttyRenderStateColors>.size
        _ = ghostty_render_state_colors_get(renderState, &colors)
        let defaultFg = colors.foreground.swift
        let defaultBg = colors.background.swift
        let cursorColor = colors.cursor_has_value ? colors.cursor.swift : defaultFg

        // Cursor (viewport-relative).
        var cursorX: UInt16 = 0, cursorY: UInt16 = 0, cursorVisible = false
        _ = ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_X, &cursorX)
        _ = ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_Y, &cursorY)
        _ = ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_CURSOR_VISIBLE, &cursorVisible)

        var cells: [TerminalCell] = []
        cells.reserveCapacity(cols * rows)

        // Re-seat the row iterator on the fresh snapshot.
        var iterator: GhosttyRenderStateRowIterator? = rowIterator
        guard ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_ROW_ITERATOR, &iterator) == GHOSTTY_SUCCESS else {
            return TerminalSnapshot(cols: cols, rows: rows, cursorCol: Int(cursorX), cursorRow: Int(cursorY),
                                    cursorVisible: cursorVisible, cursorColor: cursorColor,
                                    defaultForeground: defaultFg, defaultBackground: defaultBg, cells: cells)
        }

        var rowIndex = 0
        while ghostty_render_state_row_iterator_next(rowIterator) {
            var cellsHandle: GhosttyRenderStateRowCells? = rowCells
            if ghostty_render_state_row_get(rowIterator, GHOSTTY_RENDER_STATE_ROW_DATA_CELLS, &cellsHandle) != GHOSTTY_SUCCESS {
                rowIndex += 1
                continue
            }
            var colIndex = 0
            while ghostty_render_state_row_cells_next(rowCells) {
                var graphemeLen: UInt32 = 0
                ghostty_render_state_row_cells_get(rowCells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_LEN, &graphemeLen)

                // Per-cell style: bold/italic for the atlas, inverse to swap fg/bg.
                // TUIs (e.g. pi-tui) draw their cursor as a reverse-video cell, so the
                // inverse swap is what makes that block appear.
                var style = GhosttyStyle()
                style.size = MemoryLayout<GhosttyStyle>.size
                _ = ghostty_render_state_row_cells_get(rowCells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_STYLE, &style)

                var fgRgb = colors.foreground
                _ = ghostty_render_state_row_cells_get(rowCells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_FG_COLOR, &fgRgb)
                var bgRgb = GhosttyColorRgb()
                let hasBg = ghostty_render_state_row_cells_get(rowCells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_BG_COLOR, &bgRgb) == GHOSTTY_SUCCESS

                var fg = fgRgb.swift
                var bg: RGBColor? = hasBg ? bgRgb.swift : nil
                if style.inverse {
                    let previousBg = bg ?? defaultBg
                    bg = fg
                    fg = previousBg
                }

                var flags: CellFlags = []
                if style.bold { flags.insert(.bold) }
                if style.italic { flags.insert(.italic) }
                if style.faint { flags.insert(.faint) }
                if style.strikethrough { flags.insert(.strikethrough) }
                if style.underline != 0 { flags.insert(.underline) }

                if graphemeLen == 0 {
                    if let bg {
                        cells.append(TerminalCell(col: colIndex, row: rowIndex, text: "",
                                                  foreground: fg, background: bg, flags: flags))
                    }
                    colIndex += 1
                    continue
                }

                let count = Int(min(graphemeLen, 16))
                var codepoints = [UInt32](repeating: 0, count: 16)
                codepoints.withUnsafeMutableBufferPointer { buf in
                    _ = ghostty_render_state_row_cells_get(rowCells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_BUF, buf.baseAddress)
                }
                var scalars = String.UnicodeScalarView()
                for i in 0..<count {
                    if let scalar = Unicode.Scalar(codepoints[i]) { scalars.append(scalar) }
                }
                let text = String(scalars)

                cells.append(TerminalCell(col: colIndex, row: rowIndex, text: text,
                                          foreground: fg, background: bg, flags: flags))
                colIndex += 1
            }
            rowIndex += 1
        }

        return TerminalSnapshot(cols: cols, rows: rows, cursorCol: Int(cursorX), cursorRow: Int(cursorY),
                                cursorVisible: cursorVisible, cursorColor: cursorColor,
                                defaultForeground: defaultFg, defaultBackground: defaultBg, cells: cells)
    }

    // MARK: Effect callbacks (C ABI)

    private func handleWriteBack(_ bytes: [UInt8]) {
        delegate?.terminalEngine(self, writeToPTY: bytes)
    }

    private func handleTitleChanged() {
        guard let terminal else { return }
        var string = GhosttyString()
        var title: String?
        if ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_TITLE, &string) == GHOSTTY_SUCCESS, let ptr = string.ptr, string.len > 0 {
            title = String(decoding: UnsafeBufferPointer(start: ptr, count: string.len), as: UTF8.self)
        }
        delegate?.terminalEngine(self, didChangeTitle: title)
    }

    private static let writePtyEffect: GhosttyTerminalWritePtyFn = { _, userdata, data, len in
        guard let userdata, let data else { return }
        let engine = Unmanaged<GhosttyVTEngine>.fromOpaque(userdata).takeUnretainedValue()
        let bytes = Array(UnsafeBufferPointer(start: data, count: len))
        engine.handleWriteBack(bytes)
    }

    private static let titleChangedEffect: GhosttyTerminalTitleChangedFn = { _, userdata in
        guard let userdata else { return }
        let engine = Unmanaged<GhosttyVTEngine>.fromOpaque(userdata).takeUnretainedValue()
        engine.handleTitleChanged()
    }
}

// MARK: Small bridges

private extension GhosttyColorRgb {
    var swift: RGBColor { RGBColor(r: r, g: g, b: b) }
}

private extension ThemeRGB {
    var ghostty: GhosttyColorRgb { GhosttyColorRgb(r: r, g: g, b: b) }
}

private extension KeyEvent.Action {
    var ghostty: GhosttyKeyAction {
        switch self {
        case .press: return GHOSTTY_KEY_ACTION_PRESS
        case .repeatKey: return GHOSTTY_KEY_ACTION_REPEAT
        case .release: return GHOSTTY_KEY_ACTION_RELEASE
        }
    }
}

private extension KeyModifiers {
    var ghosttyMods: GhosttyMods {
        var m: Int32 = 0
        if contains(.shift)   { m |= GHOSTTY_MODS_SHIFT }
        if contains(.control) { m |= GHOSTTY_MODS_CTRL }
        if contains(.option)  { m |= GHOSTTY_MODS_ALT }
        if contains(.command) { m |= GHOSTTY_MODS_SUPER }
        return GhosttyMods(m)
    }
}
