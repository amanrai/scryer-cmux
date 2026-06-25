#if os(iOS)
import SwiftUI
import ScryerCore

/// App-local floating keyboard for iPad. Renders its own QWERTY (so it can float and
/// drag instead of docking like the system keyboard) and routes every key through the
/// terminal's engine encoder via `onText` / `onSpecialKey`. A second tab holds pre-baked
/// control combos and common commands.
struct FloatingKeyboardView: View {
    let onText: (String, KeyModifiers) -> Void
    let onSpecialKey: (TerminalKey, KeyModifiers) -> Void
    let onHide: () -> Void
    let onActivate: () -> Void      // any tap on the keyboard (used to wake from faint)
    let theme: TerminalTheme        // keyboard reads as part of the terminal surface
    let containerHeight: CGFloat    // available height, for clamping the vertical drag
    let topInset: CGFloat           // keyboard top must stay below this (the chrome bar)
    @Binding var position: CGSize   // persisted by the host so it survives hide/show

    @GestureState private var dragOffset = CGSize.zero
    @State private var shift = false
    @State private var control = false
    @State private var tab: KeyboardTab = .keys
    @State private var kbHeight: CGFloat = 0

    private let keyHeight: CGFloat = 54
    private let rowSpacing: CGFloat = 6
    private let bottomPad: CGFloat = 10
    /// Every tab is sized to the full QWERTY height so the panel never changes size.
    private var contentHeight: CGFloat {
        CGFloat(qwertyRows.count) * keyHeight + CGFloat(qwertyRows.count - 1) * rowSpacing
    }

    /// Clamp the Y offset so the keyboard stays fully on-screen: its top can't rise
    /// above `topInset`, and it can't drop below its resting (bottom) position.
    private func clampedY(_ y: CGFloat) -> CGFloat {
        guard containerHeight > 0, kbHeight > 0 else { return min(0, y) }
        let restTop = containerHeight - bottomPad - kbHeight   // top edge at offset 0
        let minY = topInset - restTop                          // most negative (highest)
        return min(0, max(minY, y))
    }
    private var surfaceColor: Color { Color(hex: theme.background.hex) ?? .black }
    private var fgColor: Color { Color(hex: theme.foreground.hex) ?? .white }

    enum KeyboardTab: Hashable { case keys, commands, tmux, pi }

    var body: some View {
        VStack(spacing: 6) {
            header
            switch tab {
            case .keys:     qwerty
            case .commands: commands
            case .tmux:     tmuxView
            case .pi:       piView
            }
        }
        .padding(8)
        .background(surfaceColor, in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(fgColor.opacity(0.12)))
        .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
        .frame(maxWidth: 1100)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { kbHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, h in kbHeight = h }
            }
        )
        // Any tap on the panel wakes it from faint (key taps still fire their action).
        .simultaneousGesture(TapGesture().onEnded { onActivate() })
        // Horizontally centered (x: 0), draggable only on the Y axis, clamped on-screen.
        .offset(x: 0, y: clampedY(position.height + dragOffset.height))
        .onChange(of: containerHeight) { _, _ in position.height = clampedY(position.height) }
        .onChange(of: kbHeight) { _, _ in position.height = clampedY(position.height) }
    }

    // MARK: Header (tabs + drag handle + hide)

    private var header: some View {
        HStack(spacing: 12) {
            Picker("", selection: $tab) {
                Text("abc").tag(KeyboardTab.keys)
                Text("⌃").tag(KeyboardTab.commands)
                Text("tmux").tag(KeyboardTab.tmux)
                Text("pi").tag(KeyboardTab.pi)
            }
            .pickerStyle(.segmented)
            .frame(width: 320)

            Spacer()
            Capsule().fill(.secondary.opacity(0.5)).frame(width: 56, height: 6)   // grab indicator
            Spacer()

            Button(action: onHide) { Image(systemName: "chevron.down.circle.fill").font(.system(size: 18)) }
                .buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4).padding(.vertical, 8)
        .contentShape(Rectangle())
        // Whole header drags (Y only); minimumDistance debounces taps on the picker/button.
        .gesture(
            DragGesture(minimumDistance: 10)
                .updating($dragOffset) { value, state, _ in state = value.translation }
                .onEnded { value in position.height = clampedY(position.height + value.translation.height) }
        )
    }

    // MARK: Tab 1 — QWERTY

    private enum Key: Identifiable {
        case char(String, String)              // (base, shifted) → typed text
        case special(TerminalKey, String)      // key, label
        case shift, control
        var id: String {
            switch self {
            case .char(let b, _): return "c\(b)"
            case .special(_, let l): return "s\(l)"
            case .shift: return "shift"
            case .control: return "ctrl"
            }
        }
    }

    private let qwertyRows: [[Key]] = [
        [.char("`", "~"), .char("1", "!"), .char("2", "@"), .char("3", "#"), .char("4", "$"),
         .char("5", "%"), .char("6", "^"), .char("7", "&"), .char("8", "*"), .char("9", "("),
         .char("0", ")"), .char("-", "_"), .char("=", "+"), .special(.backspace, "⌫")],
        [.special(.tab, "⇥"), .char("q", "Q"), .char("w", "W"), .char("e", "E"), .char("r", "R"),
         .char("t", "T"), .char("y", "Y"), .char("u", "U"), .char("i", "I"), .char("o", "O"),
         .char("p", "P"), .char("[", "{"), .char("]", "}"), .char("\\", "|")],
        [.special(.escape, "esc"), .char("a", "A"), .char("s", "S"), .char("d", "D"), .char("f", "F"),
         .char("g", "G"), .char("h", "H"), .char("j", "J"), .char("k", "K"), .char("l", "L"),
         .char(";", ":"), .char("'", "\""), .special(.enter, "⏎")],
        [.shift, .char("z", "Z"), .char("x", "X"), .char("c", "C"), .char("v", "V"), .char("b", "B"),
         .char("n", "N"), .char("m", "M"), .char(",", "<"), .char(".", ">"), .char("/", "?"), .shift],
        [.control, .char(" ", " "), .special(.arrowLeft, "←"), .special(.arrowUp, "↑"),
         .special(.arrowDown, "↓"), .special(.arrowRight, "→")],
    ]

    private var qwerty: some View {
        // Proportion each row to the panel width so keys are weighted like a real
        // keyboard (wide space, slightly-wider tab/shift/enter/backspace/ctrl).
        GeometryReader { geo in
            VStack(spacing: rowSpacing) {
                ForEach(Array(qwertyRows.enumerated()), id: \.offset) { _, row in
                    let u = unitWidth(for: row, totalWidth: geo.size.width)
                    HStack(spacing: rowSpacing) {
                        ForEach(row) { key in keyButton(key, width: weight(of: key) * u) }
                    }
                }
            }
        }
        .frame(height: contentHeight)
    }

    /// Per-key relative widths (1 = a letter key).
    private func weight(of key: Key) -> CGFloat {
        switch key {
        case .char(let base, _): return base == " " ? 7 : 1
        case .special(_, let label):
            switch label {
            case "⌫", "⇥", "esc": return 1.6
            case "⏎": return 1.8
            default: return 1            // arrows
            }
        case .shift: return 1.8
        case .control: return 1.6
        }
    }

    private func unitWidth(for row: [Key], totalWidth: CGFloat) -> CGFloat {
        let totalWeight = row.reduce(0) { $0 + weight(of: $1) }
        let spacing = rowSpacing * CGFloat(max(0, row.count - 1))
        return max(1, (totalWidth - spacing) / max(1, totalWeight))
    }

    @ViewBuilder
    private func keyButton(_ key: Key, width: CGFloat) -> some View {
        switch key {
        case .char(let base, let shifted):
            keyCap(base == " " ? "space" : (shift ? shifted : base), width: width) { tapChar(base, shifted) }
        case .special(let k, let label):
            keyCap(label, width: width) { tapSpecial(k) }
        case .shift:
            keyCap("⇧", width: width, active: shift) { shift.toggle() }
        case .control:
            keyCap("ctrl", width: width, active: control) { control.toggle() }
        }
    }

    private func keyCap(_ label: String, width: CGFloat, active: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 20, weight: .medium, design: label.count == 1 ? .monospaced : .default))
                .frame(width: width, height: keyHeight)
                .background(active ? Color.accentColor.opacity(0.8) : fgColor.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(active ? Color.white : fgColor)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var modifiers: KeyModifiers { control ? [.control] : [] }

    private func tapChar(_ base: String, _ shifted: String) {
        onText(shift ? shifted : base, modifiers)
        shift = false
        control = false
    }

    private func tapSpecial(_ key: TerminalKey) {
        onSpecialKey(key, modifiers)
        control = false
    }

    // MARK: Tab 2 — pre-baked combos & commands

    private enum Macro: Identifiable {
        case ctrl(String)               // ⌃ + letter
        case key(TerminalKey, String)   // special key (label)
        case command(String)            // text + Enter
        case tmux(String, String)       // Ctrl-B prefix then key (label)
        var id: String {
            switch self {
            case .ctrl(let c): return "^\(c)"
            case .key(_, let l): return "k\(l)"
            case .command(let s): return "cmd\(s)"
            case .tmux(let k, let l): return "tmux\(k)\(l)"
            }
        }
        var label: String {
            switch self {
            case .ctrl(let c): return "⌃\(c.uppercased())"
            case .key(_, let l): return l
            case .command(let s): return s
            case .tmux(_, let l): return l
            }
        }
    }

    private let controlMacros: [Macro] = [
        .ctrl("c"), .ctrl("d"), .ctrl("z"), .ctrl("l"), .ctrl("a"),
        .ctrl("e"), .ctrl("r"), .ctrl("u"), .ctrl("w"), .ctrl("k"),
    ]
    private let keyMacros: [Macro] = [
        .key(.escape, "esc"), .key(.tab, "⇥"), .key(.enter, "⏎"), .key(.backspace, "⌫"),
        .key(.arrowLeft, "←"), .key(.arrowUp, "↑"), .key(.arrowDown, "↓"), .key(.arrowRight, "→"),
    ]
    private let commandMacros: [Macro] = [
        .command("clear"), .command("ls"), .command("ls -la"), .command("cd .."), .command("exit"), .command("q"),
    ]
    // tmux: default Ctrl-B prefix then a key.
    private let tmuxMacros: [Macro] = [
        .tmux("c", "new"), .tmux("n", "next"), .tmux("p", "prev"), .tmux("w", "list"),
        .tmux("%", "split |"), .tmux("\"", "split —"), .tmux("z", "zoom"), .tmux("o", "cycle"),
        .tmux("d", "detach"), .tmux("[", "copy"), .tmux("x", "kill"), .tmux(",", "rename"),
    ]
    // pi slash-commands (text + Enter).
    private let piCommands: [Macro] = [
        .command("/comms-test"), .command("/comms-test-update"), .command("/tree"), .command("/reload"),
    ]

    private var commands: some View {
        VStack(alignment: .leading, spacing: 8) {
            macroSection("Control", controlMacros)
            macroSection("Keys", keyMacros)
            macroSection("Commands", commandMacros)
        }
        .padding(.horizontal, 2)
        .frame(height: contentHeight, alignment: .top)
    }

    private var tmuxView: some View {
        macroSection("tmux  ·  prefix ⌃B", tmuxMacros)
            .padding(.horizontal, 2)
            .frame(height: contentHeight, alignment: .top)
    }

    private var piView: some View {
        macroSection("pi", piCommands, fontSize: 13)
            .padding(.horizontal, 2)
            .frame(height: contentHeight, alignment: .top)
    }

    private func macroSection(_ title: String, _ macros: [Macro], fontSize: CGFloat = 16) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 10, weight: .semibold)).tracking(0.5).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(macros) { macro in macroButton(macro, fontSize: fontSize) }
            }
        }
    }

    private func macroButton(_ macro: Macro, fontSize: CGFloat = 16) -> some View {
        Button { run(macro) } label: {
            Text(macro.label)
                .font(.system(size: fontSize, weight: .medium, design: macro.label.hasPrefix("⌃") ? .monospaced : .default))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(fgColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(fgColor)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func run(_ macro: Macro) {
        switch macro {
        case .ctrl(let c):        onText(c, [.control])
        case .key(let k, _):      onSpecialKey(k, [])
        case .command(let cmd):   onText(cmd, []); onSpecialKey(.enter, [])
        case .tmux(let key, _):   onText("b", [.control]); onText(key, [])
        }
    }
}
#endif
