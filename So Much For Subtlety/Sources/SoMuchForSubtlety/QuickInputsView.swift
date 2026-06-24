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
        VStack(spacing: 0) {
            HStack {
                Text("Quick Inputs").font(.headline)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title.uppercased())
                                .font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.tertiary)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                                ForEach(group.items) { item in
                                    Button { onSend(item.data) } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: item.symbol).frame(width: 16)
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(item.label).font(.system(size: 12, weight: .medium))
                                                Text(item.detail).font(.system(size: 10)).foregroundStyle(.secondary)
                                            }
                                            Spacer(minLength: 0)
                                        }
                                        .padding(.horizontal, 10).padding(.vertical, 7)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(18)
            }
        }
        .frame(width: 440, height: 420)
    }
}
