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
    case oneDark, oneLight, matte, obsidian, tokyoNight, dracula, catppuccin, nord, solarized, solarizedDark, paper, matrix, synthwave

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .oneDark: return "One Dark"
        case .oneLight: return "One Light"
        case .matte: return "Matte Black"
        case .obsidian: return "Obsidian"
        case .tokyoNight: return "Tokyo Night"
        case .dracula: return "Dracula"
        case .catppuccin: return "Catppuccin"
        case .nord: return "Nord"
        case .solarized: return "Solarized"
        case .solarizedDark: return "Solarized Dark"
        case .paper: return "Paper"
        case .matrix: return "Matrix"
        case .synthwave: return "Synthwave"
        }
    }

    public var isDark: Bool {
        switch self {
        case .oneLight, .solarized, .paper: return false
        default: return true
        }
    }

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
        case .obsidian:
            return Self.make(fg: "#E8E6E1", bg: "#111110", cursor: "#D97706", sel: "#2A2A27", chrome: "#1A1A18", ansi: [
                "#111110", "#DC2626", "#6FCB7F", "#D97706", "#5AA6F0", "#B47BE8", "#4FC9D4", "#E8E6E1",
                "#5C5A55", "#EF4444", "#86EFAC", "#F59E0B", "#60A5FA", "#C084FC", "#67E8F9", "#FFF8EB"])
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
            return Self.make(fg: "#ECEFF4", bg: "#1E2128", cursor: "#5E81AC", sel: "#363D4D", chrome: "#242931", ansi: [
                "#2E3440", "#BF616A", "#A3BE8C", "#EBCB8B", "#5E81AC", "#B48EAD", "#88C0D0", "#ECEFF4",
                "#616C7E", "#BF616A", "#A3BE8C", "#EBCB8B", "#81A1C1", "#B48EAD", "#8FBCBB", "#FFFFFF"])
        case .solarized:
            return Self.make(fg: "#586E75", bg: "#FDF6E3", cursor: "#268BD2", sel: "#E5DFC8", chrome: "#EEE8D5", ansi: [
                "#073642", "#DC322F", "#859900", "#B58900", "#268BD2", "#D33682", "#2AA198", "#EEE8D5",
                "#002B36", "#CB4B16", "#586E75", "#657B83", "#839496", "#6C71C4", "#93A1A1", "#FDF6E3"])
        case .solarizedDark:
            return Self.make(fg: "#93A1A1", bg: "#002B36", cursor: "#268BD2", sel: "#12505F", chrome: "#073642", ansi: [
                "#073642", "#DC322F", "#859900", "#B58900", "#268BD2", "#D33682", "#2AA198", "#EEE8D5",
                "#002B36", "#CB4B16", "#586E75", "#657B83", "#839496", "#6C71C4", "#93A1A1", "#FDF6E3"])
        case .paper:
            return Self.make(fg: "#1C1B19", bg: "#FAF9F7", cursor: "#B45309", sel: "#EBE9E4", chrome: "#F2F0EC", ansi: [
                "#1C1B19", "#DC2626", "#4D7C0F", "#B45309", "#2563EB", "#9333EA", "#0891B2", "#F2F0EC",
                "#A8A49C", "#EF4444", "#65A30D", "#D97706", "#3B82F6", "#A855F7", "#06B6D4", "#FFFFFF"])
        case .matrix:
            return Self.make(fg: "#00FF41", bg: "#000000", cursor: "#00FF41", sel: "#0D1F0D", chrome: "#030D03", ansi: [
                "#000000", "#FF2222", "#00B32C", "#00FF41", "#005C16", "#00B32C", "#00FF41", "#B6FFBF",
                "#005C16", "#FF5555", "#00FF41", "#7CFF91", "#00B32C", "#33FF66", "#99FFAA", "#FFFFFF"])
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
