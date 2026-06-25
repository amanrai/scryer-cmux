import CGhosttyVT
import ScryerCore

#if os(macOS)
import AppKit
#endif

/// Builds platform-neutral `KeyEvent`s for the engine's key encoder, which turns them
/// into VT bytes honoring terminal modes (application cursor keys, etc.).
public enum GhosttyKeymap {

    // MARK: Cross-platform builders (used by the UIKit layer)

    /// A run of typed text (e.g. from a soft keyboard's insertText), optionally with
    /// modifiers (e.g. control for ⌃-combos). The encoder turns ⌃+letter into its
    /// control byte.
    public static func keyEvent(text: String, modifiers: KeyModifiers = []) -> KeyEvent {
        let unshifted = text.unicodeScalars.first.map {
            Character($0).lowercased().unicodeScalars.first?.value ?? $0.value
        } ?? 0
        return KeyEvent(
            action: .press,
            modifiers: modifiers,
            ghosttyKeyCode: GHOSTTY_KEY_UNIDENTIFIED.rawValue,
            text: text,
            unshiftedCodepoint: unshifted
        )
    }

    /// A platform-neutral special key (+ modifiers), mapped to a libghostty key code.
    public static func keyEvent(special: TerminalKey, modifiers: KeyModifiers) -> KeyEvent {
        KeyEvent(
            action: .press,
            modifiers: modifiers,
            ghosttyKeyCode: ghosttyKey(for: special).rawValue,
            text: nil,
            unshiftedCodepoint: 0
        )
    }

    private static func ghosttyKey(for key: TerminalKey) -> GhosttyKey {
        switch key {
        case .enter:      return GHOSTTY_KEY_ENTER
        case .backspace:  return GHOSTTY_KEY_BACKSPACE
        case .tab:        return GHOSTTY_KEY_TAB
        case .escape:     return GHOSTTY_KEY_ESCAPE
        case .delete:     return GHOSTTY_KEY_DELETE
        case .space:      return GHOSTTY_KEY_SPACE
        case .arrowUp:    return GHOSTTY_KEY_ARROW_UP
        case .arrowDown:  return GHOSTTY_KEY_ARROW_DOWN
        case .arrowLeft:  return GHOSTTY_KEY_ARROW_LEFT
        case .arrowRight: return GHOSTTY_KEY_ARROW_RIGHT
        case .home:       return GHOSTTY_KEY_HOME
        case .end:        return GHOSTTY_KEY_END
        case .pageUp:     return GHOSTTY_KEY_PAGE_UP
        case .pageDown:   return GHOSTTY_KEY_PAGE_DOWN
        }
    }

    #if os(macOS)
    // MARK: AppKit mapper

    /// Maps an AppKit `NSEvent` to a `KeyEvent`. Returns nil for events that shouldn't
    /// reach the PTY (e.g. ⌘ shortcuts). Hybrid mapping: special keys by macOS virtual
    /// keycode, printable keys by their unmodified character.
    public static func keyEvent(from event: NSEvent) -> KeyEvent? {
        let flags = event.modifierFlags
        var mods: KeyModifiers = []
        if flags.contains(.shift) { mods.insert(.shift) }
        if flags.contains(.control) { mods.insert(.control) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.command) { mods.insert(.command) }

        // Leave ⌘ combos to the app (copy/paste/quit/etc.).
        if mods.contains(.command) { return nil }

        let key = ghosttyKey(for: event)
        let unshifted = event.charactersIgnoringModifiers?.unicodeScalars.first.map {
            Character($0).lowercased().unicodeScalars.first?.value ?? $0.value
        } ?? 0

        return KeyEvent(
            action: event.isARepeat ? .repeatKey : .press,
            modifiers: mods,
            ghosttyKeyCode: key.rawValue,
            text: event.characters,
            unshiftedCodepoint: unshifted
        )
    }

    private static func ghosttyKey(for event: NSEvent) -> GhosttyKey {
        // Special keys by macOS virtual keycode (layout-independent).
        switch event.keyCode {
        case 0x24, 0x4C: return GHOSTTY_KEY_ENTER       // Return, Keypad Enter
        case 0x30:       return GHOSTTY_KEY_TAB
        case 0x33:       return GHOSTTY_KEY_BACKSPACE
        case 0x35:       return GHOSTTY_KEY_ESCAPE
        case 0x31:       return GHOSTTY_KEY_SPACE
        case 0x75:       return GHOSTTY_KEY_DELETE       // forward delete
        case 0x7B:       return GHOSTTY_KEY_ARROW_LEFT
        case 0x7C:       return GHOSTTY_KEY_ARROW_RIGHT
        case 0x7D:       return GHOSTTY_KEY_ARROW_DOWN
        case 0x7E:       return GHOSTTY_KEY_ARROW_UP
        case 0x73:       return GHOSTTY_KEY_HOME
        case 0x77:       return GHOSTTY_KEY_END
        case 0x74:       return GHOSTTY_KEY_PAGE_UP
        case 0x79:       return GHOSTTY_KEY_PAGE_DOWN
        default:         break
        }

        // Printable keys by their unmodified character.
        guard let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first else {
            return GHOSTTY_KEY_UNIDENTIFIED
        }
        let v = scalar.value
        if v >= 97, v <= 122 { return offset(GHOSTTY_KEY_A, v - 97) }        // a–z
        if v >= 65, v <= 90  { return offset(GHOSTTY_KEY_A, v - 65) }        // A–Z
        if v >= 48, v <= 57  { return offset(GHOSTTY_KEY_DIGIT_0, v - 48) }  // 0–9

        switch scalar {
        case "-": return GHOSTTY_KEY_MINUS
        case "=": return GHOSTTY_KEY_EQUAL
        case "[": return GHOSTTY_KEY_BRACKET_LEFT
        case "]": return GHOSTTY_KEY_BRACKET_RIGHT
        case "\\": return GHOSTTY_KEY_BACKSLASH
        case ";": return GHOSTTY_KEY_SEMICOLON
        case "'": return GHOSTTY_KEY_QUOTE
        case ",": return GHOSTTY_KEY_COMMA
        case ".": return GHOSTTY_KEY_PERIOD
        case "/": return GHOSTTY_KEY_SLASH
        case "`": return GHOSTTY_KEY_BACKQUOTE
        default:  return GHOSTTY_KEY_UNIDENTIFIED
        }
    }

    private static func offset(_ base: GhosttyKey, _ delta: UInt32) -> GhosttyKey {
        GhosttyKey(rawValue: base.rawValue + delta)
    }
    #endif
}
