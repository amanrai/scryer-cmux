import SwiftUI

/// Quick terminal inputs — send control sequences and common keys to the active pane.
/// Mirrors the gateway-ui quick-inputs modal (Scryer/agent commands deferred).
struct QuickInputsView: View {
    @Environment(\.dismiss) private var dismiss
    let onSend: (String) -> Void

    private struct Item: Identifiable {
        let id = UUID()
        let label: String
        let detail: String
        let symbol: String
        let data: String
    }
    private struct Group: Identifiable {
        let id = UUID()
        let title: String
        let items: [Item]
    }

    private let groups: [Group] = [
        Group(title: "Terminal", items: [
            Item(label: "Esc", detail: "Escape", symbol: "escape", data: "\u{1b}"),
            Item(label: "Tab", detail: "Complete / indent", symbol: "arrow.right.to.line", data: "\t"),
            Item(label: "Return", detail: "Submit line", symbol: "return", data: "\r"),
            Item(label: "Ctrl-C", detail: "Interrupt", symbol: "xmark.octagon", data: "\u{03}"),
            Item(label: "Ctrl-D", detail: "EOF / exit", symbol: "rectangle.portrait.and.arrow.right", data: "\u{04}"),
            Item(label: "Ctrl-L", detail: "Clear screen", symbol: "wind", data: "\u{0c}"),
        ]),
        Group(title: "Navigate", items: [
            Item(label: "Up", detail: "Previous history", symbol: "arrow.up", data: "\u{1b}[A"),
            Item(label: "Down", detail: "Next history", symbol: "arrow.down", data: "\u{1b}[B"),
            Item(label: "Force quit", detail: "Double Ctrl-C", symbol: "stop.circle", data: "\u{03}\u{03}"),
        ]),
        Group(title: "Git & Project", items: [
            Item(label: "git status", detail: "Run git status", symbol: "arrow.triangle.branch", data: "git status\r"),
            Item(label: "clear", detail: "Clear terminal", symbol: "eraser", data: "clear\r"),
        ]),
    ]

    var body: some View {
        List {
            ForEach(groups) { group in
                Section(group.title) {
                    ForEach(group.items) { item in
                        Button { onSend(item.data) } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.label)
                                    Text(item.detail).font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: item.symbol).foregroundStyle(.tint)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .modalList()
        .modalChrome("Quick Inputs", systemImage: "keyboard", width: 440, height: 420)
    }
}
