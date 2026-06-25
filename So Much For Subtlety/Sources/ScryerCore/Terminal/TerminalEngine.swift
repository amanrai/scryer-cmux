import Foundation

public struct RGBColor: Hashable, Sendable {
    public var r: UInt8, g: UInt8, b: UInt8
    public init(r: UInt8, g: UInt8, b: UInt8) { self.r = r; self.g = g; self.b = b }
    public static let black = RGBColor(r: 0, g: 0, b: 0)
    public static let white = RGBColor(r: 0xEB, g: 0xEB, b: 0xEB)
}

public struct CellFlags: OptionSet, Sendable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }
    public static let bold      = CellFlags(rawValue: 1 << 0)
    public static let italic    = CellFlags(rawValue: 1 << 1)
    public static let inverse   = CellFlags(rawValue: 1 << 2)
    public static let underline = CellFlags(rawValue: 1 << 3)
    public static let faint     = CellFlags(rawValue: 1 << 4)
    public static let strikethrough = CellFlags(rawValue: 1 << 5)
}

/// One drawable grid cell. `text` may be empty (background-only) or a multi-codepoint grapheme.
public struct TerminalCell: Sendable {
    public var col: Int
    public var row: Int
    public var text: String
    public var foreground: RGBColor
    public var background: RGBColor?
    public var flags: CellFlags

    public init(col: Int, row: Int, text: String, foreground: RGBColor, background: RGBColor?, flags: CellFlags) {
        self.col = col
        self.row = row
        self.text = text
        self.foreground = foreground
        self.background = background
        self.flags = flags
    }
}

/// Immutable snapshot of the visible terminal, produced by the engine each frame.
public struct TerminalSnapshot: Sendable {
    public var cols: Int
    public var rows: Int
    public var cursorCol: Int
    public var cursorRow: Int
    public var cursorVisible: Bool
    public var cursorColor: RGBColor
    public var defaultForeground: RGBColor
    public var defaultBackground: RGBColor
    public var cells: [TerminalCell]   // only non-empty / styled cells

    public init(cols: Int, rows: Int, cursorCol: Int, cursorRow: Int, cursorVisible: Bool,
                cursorColor: RGBColor, defaultForeground: RGBColor, defaultBackground: RGBColor, cells: [TerminalCell]) {
        self.cols = cols
        self.rows = rows
        self.cursorCol = cursorCol
        self.cursorRow = cursorRow
        self.cursorVisible = cursorVisible
        self.cursorColor = cursorColor
        self.defaultForeground = defaultForeground
        self.defaultBackground = defaultBackground
        self.cells = cells
    }

    public static let empty = TerminalSnapshot(
        cols: 0, rows: 0, cursorCol: 0, cursorRow: 0, cursorVisible: false,
        cursorColor: .white, defaultForeground: .white, defaultBackground: .black, cells: []
    )
}

// MARK: Input

public struct KeyModifiers: OptionSet, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let shift = KeyModifiers(rawValue: 1 << 0)
    public static let control = KeyModifiers(rawValue: 1 << 1)
    public static let option = KeyModifiers(rawValue: 1 << 2)
    public static let command = KeyModifiers(rawValue: 1 << 3)
}

/// Platform-neutral key event. The platform layer (AppKit/UIKit) fills this and the
/// engine hands it to libghostty's key encoder, which honors terminal modes.
public struct KeyEvent: Sendable {
    public enum Action: Sendable { case press, repeatKey, release }
    public var action: Action
    public var modifiers: KeyModifiers
    /// libghostty key code (see `GhosttyKey`); 0 = unidentified.
    public var ghosttyKeyCode: UInt32
    /// Text the platform produced (already shift/option-resolved), e.g. "a", "A".
    public var text: String?
    /// Unshifted codepoint for the physical key (Kitty protocol); 0 if none.
    public var unshiftedCodepoint: UInt32

    public init(action: Action, modifiers: KeyModifiers, ghosttyKeyCode: UInt32,
                text: String?, unshiftedCodepoint: UInt32) {
        self.action = action
        self.modifiers = modifiers
        self.ghosttyKeyCode = ghosttyKeyCode
        self.text = text
        self.unshiftedCodepoint = unshiftedCodepoint
    }
}

/// Platform-neutral special keys. The UIKit layer (which has no `NSEvent`) emits these
/// and the engine bridge maps them to libghostty key codes so terminal modes are honored.
public enum TerminalKey: Sendable {
    case enter, backspace, tab, escape, delete, space
    case arrowUp, arrowDown, arrowLeft, arrowRight
    case home, end, pageUp, pageDown
}

public struct MouseEvent: Sendable {
    public enum Action: Sendable { case press, release, motion }
    public enum Button: Sendable { case left, middle, right, none }
    public var action: Action
    public var button: Button
    public var modifiers: KeyModifiers
    public var x: Double   // pixels within the terminal surface
    public var y: Double

    public init(action: Action, button: Button, modifiers: KeyModifiers, x: Double, y: Double) {
        self.action = action
        self.button = button
        self.modifiers = modifiers
        self.x = x
        self.y = y
    }
}

// MARK: Engine

public protocol TerminalEngineDelegate: AnyObject {
    /// Bytes the terminal wants to send back to the PTY: query responses AND encoded
    /// user input. Wired to the WebSocket `input` channel. REQUIRED for TUIs.
    func terminalEngine(_ engine: TerminalEngine, writeToPTY bytes: [UInt8])
    func terminalEngine(_ engine: TerminalEngine, didChangeTitle title: String?)
    /// The visible state changed; the renderer should schedule a draw.
    func terminalEngineNeedsRedraw(_ engine: TerminalEngine)
}

/// The terminal core. The only implementation is `GhosttyVTEngine` (Ghostty-grade
/// emulation, per the product decision — no SwiftTerm fallback).
public protocol TerminalEngine: AnyObject {
    var delegate: TerminalEngineDelegate? { get set }

    /// `cellWidth`/`cellHeight` in device pixels — libghostty needs them for Kitty
    /// graphics and mouse-pixel reporting.
    func resize(cols: Int, rows: Int, cellWidth: Double, cellHeight: Double)

    /// Feed terminal output received from the PTY (WS `output`).
    func feed(_ bytes: [UInt8])

    func sendKey(_ event: KeyEvent)
    func sendMouse(_ event: MouseEvent)
    func scrollViewport(deltaRows: Int)

    /// Snapshot the visible grid for a render pass.
    func snapshot() -> TerminalSnapshot
}
