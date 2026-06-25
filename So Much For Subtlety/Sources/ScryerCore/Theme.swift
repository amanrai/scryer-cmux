import Foundation

/// A plain RGB color, platform-agnostic (no SwiftUI/AppKit) so the core + engine can
/// share theme data. Views convert via `Color(hex:)`.
public struct ThemeRGB: Sendable, Equatable {
    public let r: UInt8, g: UInt8, b: UInt8
    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) { self.r = r; self.g = g; self.b = b }

    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF))
    }
    public var hex: String { String(format: "#%02X%02X%02X", r, g, b) }
}

/// Terminal + chrome colors for one theme. `ansi16` is the 16-color base palette; the
/// engine fills the rest of the 256-color cube/grayscale itself.
public struct TerminalTheme: Sendable, Equatable {
    public let foreground: ThemeRGB
    public let background: ThemeRGB
    public let cursor: ThemeRGB
    public let selection: ThemeRGB
    public let ansi16: [ThemeRGB]
    public let chrome: ThemeRGB   // UI chrome (top bar / sidebar) background

    public init(foreground: ThemeRGB, background: ThemeRGB, cursor: ThemeRGB,
                selection: ThemeRGB, ansi16: [ThemeRGB], chrome: ThemeRGB) {
        self.foreground = foreground
        self.background = background
        self.cursor = cursor
        self.selection = selection
        self.ansi16 = ansi16
        self.chrome = chrome
    }
}

/// The selectable app themes.
public enum AppTheme: String, Sendable, CaseIterable, Identifiable {
    case oneDark, oneLight, matte, tokyoNight, dracula, catppuccin, nord, synthwave

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .oneDark: return "One Dark"
        case .oneLight: return "One Light"
        case .matte: return "Matte Black"
        case .tokyoNight: return "Tokyo Night"
        case .dracula: return "Dracula"
        case .catppuccin: return "Catppuccin"
        case .nord: return "Nord"
        case .synthwave: return "Synthwave"
        }
    }

    public var isDark: Bool { self != .oneLight }

    public var terminal: TerminalTheme {
        switch self {
        case .oneDark:
            return Self.make(fg: "#E6E8EC", bg: "#2A2F37", cursor: "#E8B65A", sel: "#3E4451", chrome: "#21252B", ansi: [
                "#15171C", "#E0697A", "#6FCB7F", "#E8B65A", "#5AA6F0", "#B47BE8", "#4FC9D4", "#AEB4C0",
                "#4A515E", "#E0697A", "#6FCB7F", "#E8B65A", "#5AA6F0", "#B47BE8", "#4FC9D4", "#E6E8EC"])
        case .oneLight:
            return Self.make(fg: "#383A42", bg: "#FAFAFA", cursor: "#526EFF", sel: "#D3D7DE", chrome: "#E8E8EA", ansi: [
                "#383A42", "#E45649", "#50A14F", "#C18401", "#4078F2", "#A626A4", "#0184BC", "#A0A1A7",
                "#4F525E", "#E45649", "#50A14F", "#C18401", "#4078F2", "#A626A4", "#0184BC", "#FFFFFF"])
        case .matte:
            return Self.make(fg: "#FFFFFF", bg: "#0A0A0A", cursor: "#FFFFFF", sel: "#2A2A2A", chrome: "#000000", ansi: [
                "#0A0A0A", "#FF5C57", "#5AF78E", "#F3F99D", "#57C7FF", "#FF6AC1", "#9AEDFE", "#F1F1F0",
                "#686868", "#FF5C57", "#5AF78E", "#F3F99D", "#57C7FF", "#FF6AC1", "#9AEDFE", "#FFFFFF"])
        case .tokyoNight:
            return Self.make(fg: "#C0CAF5", bg: "#1A1B26", cursor: "#C0CAF5", sel: "#283457", chrome: "#16161E", ansi: [
                "#15161E", "#F7768E", "#9ECE6A", "#E0AF68", "#7AA2F7", "#BB9AF7", "#7DCFFF", "#A9B1D6",
                "#414868", "#F7768E", "#9ECE6A", "#E0AF68", "#7AA2F7", "#BB9AF7", "#7DCFFF", "#C0CAF5"])
        case .dracula:
            return Self.make(fg: "#F8F8F2", bg: "#282A36", cursor: "#F8F8F2", sel: "#44475A", chrome: "#21222C", ansi: [
                "#21222C", "#FF5555", "#50FA7B", "#F1FA8C", "#BD93F9", "#FF79C6", "#8BE9FD", "#F8F8F2",
                "#6272A4", "#FF6E6E", "#69FF94", "#FFFFA5", "#D6ACFF", "#FF92DF", "#A4FFFF", "#FFFFFF"])
        case .catppuccin:
            return Self.make(fg: "#CDD6F4", bg: "#1E1E2E", cursor: "#F5E0DC", sel: "#585B70", chrome: "#181825", ansi: [
                "#45475A", "#F38BA8", "#A6E3A1", "#F9E2AF", "#89B4FA", "#F5C2E7", "#94E2D5", "#BAC2DE",
                "#585B70", "#F38BA8", "#A6E3A1", "#F9E2AF", "#89B4FA", "#F5C2E7", "#94E2D5", "#A6ADC8"])
        case .nord:
            return Self.make(fg: "#D8DEE9", bg: "#2E3440", cursor: "#D8DEE9", sel: "#434C5E", chrome: "#272C36", ansi: [
                "#3B4252", "#BF616A", "#A3BE8C", "#EBCB8B", "#81A1C1", "#B48EAD", "#88C0D0", "#E5E9F0",
                "#4C566A", "#BF616A", "#A3BE8C", "#EBCB8B", "#81A1C1", "#B48EAD", "#8FBCBB", "#ECEFF4"])
        case .synthwave:
            return Self.make(fg: "#F8F8F2", bg: "#262335", cursor: "#FF7EDB", sel: "#463465", chrome: "#1B172B", ansi: [
                "#262335", "#FE4450", "#72F1B8", "#FEDE5D", "#03EDF9", "#FF7EDB", "#03EDF9", "#B6B1B1",
                "#495495", "#FE4450", "#72F1B8", "#FEDE5D", "#03EDF9", "#FF7EDB", "#03EDF9", "#FFFFFF"])
        }
    }

    private static func make(fg: String, bg: String, cursor: String, sel: String, chrome: String, ansi: [String]) -> TerminalTheme {
        TerminalTheme(
            foreground: ThemeRGB(hex: fg)!, background: ThemeRGB(hex: bg)!, cursor: ThemeRGB(hex: cursor)!,
            selection: ThemeRGB(hex: sel)!, ansi16: ansi.map { ThemeRGB(hex: $0)! }, chrome: ThemeRGB(hex: chrome)!)
    }
}
