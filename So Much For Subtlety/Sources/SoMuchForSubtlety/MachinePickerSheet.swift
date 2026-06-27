import SwiftUI
import ScryerCore
#if os(macOS)
import AppKit
#endif

/// Command-palette style switcher: pick an online backend, open Kanbaner / Project Organizer,
/// or drop back to the gateway. Optimized for keyboard-first use.
struct MachinePickerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let currentBackendId: String
    let onSelect: (BackendMachine) -> Void
    var kanbanerSelected = false
    var projectOrganizerSelected = false
    var onKanbaner: () -> Void = {}
    var onProjectOrganizer: () -> Void = {}

    @State private var query = ""
    @State private var selected = 0
    @FocusState private var searchFocused: Bool
#if os(macOS)
    @State private var keyMonitor: Any?
#endif

    private var selectable: [BackendMachine] { model.backends.filter(\.isSelectable) }
    private var normalizedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    private struct PaletteAction: Identifiable {
        let id: String
        let label: String
        let hint: String
        let icon: String
        let depth: Int
        let isCurrent: Bool
        let role: ButtonRole?
        let perform: () -> Void
    }

    private enum PaletteRow: Identifiable {
        case separator(String)
        case action(PaletteAction, Int)

        var id: String {
            switch self {
            case .separator(let id): return id
            case .action(let action, _): return action.id
            }
        }
    }

    private var actions: [PaletteAction] {
        let q = normalizedQuery
        func matches(_ values: String...) -> Bool {
            q.isEmpty || values.contains { $0.lowercased().contains(q) }
        }

        let backendActions: [PaletteAction] = selectable.compactMap { backend in
            let name = model.machineName(for: backend.id) ?? backend.label
            guard matches(name, backend.id, "backend", "machine", "terminal") else { return nil }
            let current = !kanbanerSelected && !projectOrganizerSelected && backend.id == currentBackendId
            return PaletteAction(
                id: "backend-\(backend.id)",
                label: name,
                hint: current ? "current" : backend.id,
                icon: "●",
                depth: 0,
                isCurrent: current,
                role: nil,
                perform: {
                    onSelect(backend)
                    dismiss()
                }
            )
        }

        var screenActions: [PaletteAction] = []
        if matches("Kanbaner", "Project board", "board", "tasks", "tickets") {
            screenActions.append(PaletteAction(
                id: "screen-kanbaner",
                label: "Kanbaner",
                hint: kanbanerSelected ? "current" : "Project board",
                icon: "▤",
                depth: 0,
                isCurrent: kanbanerSelected,
                role: nil,
                perform: {
                    dismiss()
                    onKanbaner()
                }
            ))
        }
        if matches("Project Organizer", "projects", "hierarchy", "repo", "repository", "settings") {
            screenActions.append(PaletteAction(
                id: "screen-project-organizer",
                label: "Project Organizer",
                hint: projectOrganizerSelected ? "current" : "Project hierarchy",
                icon: "▦",
                depth: 0,
                isCurrent: projectOrganizerSelected,
                role: nil,
                perform: {
                    dismiss()
                    onProjectOrganizer()
                }
            ))
        }

        var commandActions: [PaletteAction] = []
        if matches("Change gateway", "gateway", "disconnect", "network") {
            commandActions.append(PaletteAction(
                id: "command-gateway",
                label: "Change gateway…",
                hint: model.endpoint.map { "Connected to \($0.displayHost)" } ?? "Disconnect",
                icon: "⌁",
                depth: 0,
                isCurrent: false,
                role: .destructive,
                perform: {
                    model.disconnect()
                    dismiss()
                }
            ))
        }

        return backendActions + screenActions + commandActions
    }

    private var rows: [PaletteRow] {
        var result: [PaletteRow] = []
        var actionIndex = 0

        let backendActions = actions.filter { $0.id.hasPrefix("backend-") }
        let screenActions = actions.filter { $0.id.hasPrefix("screen-") }
        let commandActions = actions.filter { $0.id.hasPrefix("command-") }

        for action in backendActions {
            result.append(.action(action, actionIndex)); actionIndex += 1
        }
        if !backendActions.isEmpty && (!screenActions.isEmpty || !commandActions.isEmpty) {
            result.append(.separator("sep-screens"))
        }
        for action in screenActions {
            result.append(.action(action, actionIndex)); actionIndex += 1
        }
        if !commandActions.isEmpty && (!backendActions.isEmpty || !screenActions.isEmpty) {
            result.append(.separator("sep-commands"))
        }
        for action in commandActions {
            result.append(.action(action, actionIndex)); actionIndex += 1
        }

        return result
    }

    private var selectableActions: [PaletteAction] {
        rows.compactMap { row in
            if case .action(let action, _) = row { return action }
            return nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchHeader

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        if selectableActions.isEmpty {
                            Text("No results")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 26)
                        } else {
                            ForEach(rows) { row in
                                switch row {
                                case .separator:
                                    Rectangle()
                                        .fill(.secondary.opacity(0.16))
                                        .frame(height: 1)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
                                case .action(let action, let index):
                                    actionRow(action, index: index)
                                        .id(index)
                                }
                            }
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 330)
                .onChange(of: selected) { _, row in
                    withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(row, anchor: .center) }
                }
            }

            footer

            HStack {
                Button("Choose") { activateSelected() }
                    .keyboardShortcut(.defaultAction)
                    .hidden()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .hidden()
            }
            .frame(width: 0, height: 0)
            .clipped()
        }
        .focusable()
        .onAppear {
            query = ""
            selected = initialSelectedIndex()
#if os(macOS)
            searchFocused = true
#endif
            installKeyMonitorIfNeeded()
        }
        .onDisappear { removeKeyMonitorIfNeeded() }
        .onChange(of: query) { _, _ in selected = 0 }
        .onChange(of: selectableActions.count) { _, count in selected = min(selected, max(0, count - 1)) }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .modalChrome("Command Palette", systemImage: "command", width: 520, height: 450)
    }

    private var searchHeader: some View {
        HStack(spacing: 10) {
            Text("⌘")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            TextField("Search for, or do something…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($searchFocused)
                .onSubmit { activateSelected() }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Divider().opacity(0.55) }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            keyHint("↵", "select")
            keyHint("↑↓", "navigate")
            keyHint("esc", "close")
            Spacer()
            Text("⌘K")
                .font(.system(size: 11).monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Divider().opacity(0.55) }
    }

    private func keyHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10).monospaced())
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary.opacity(0.16)))
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func initialSelectedIndex() -> Int {
        if let index = selectableActions.firstIndex(where: { $0.isCurrent }) { return index }
        return 0
    }

    private func moveSelection(by delta: Int) {
        guard !selectableActions.isEmpty else { return }
        selected = min(selectableActions.count - 1, max(0, selected + delta))
    }

    private func activateSelected() {
        guard selectableActions.indices.contains(selected) else { return }
        selectableActions[selected].perform()
    }

    private func installKeyMonitorIfNeeded() {
#if os(macOS)
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard !event.modifierFlags.contains(.command) else { return event }
            switch event.keyCode {
            case 126: // up arrow
                moveSelection(by: -1)
                return nil
            case 125: // down arrow
                moveSelection(by: 1)
                return nil
            case 36, 76: // return / keypad enter
                activateSelected()
                return nil
            case 53: // escape
                dismiss()
                return nil
            default:
                return event
            }
        }
#endif
    }

    private func removeKeyMonitorIfNeeded() {
#if os(macOS)
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
#endif
    }

    private func actionRow(_ action: PaletteAction, index: Int) -> some View {
        Button(role: action.role) {
            selected = index
            action.perform()
        } label: {
            HStack(spacing: 10) {
                Text(action.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(action.id.hasPrefix("backend-") ? .green : .secondary)
                    .frame(width: 18)
                Text(action.label)
                    .font(.system(size: 14, weight: selected == index ? .semibold : .regular))
                    .foregroundStyle(action.depth > 0 ? .secondary : .primary)
                    .lineLimit(1)
                Spacer(minLength: 12)
                Text(action.hint)
                    .font(.system(size: 11).monospaced())
                    .foregroundStyle(action.isCurrent ? Color.accentColor : Color.secondary.opacity(0.65))
                    .lineLimit(1)
            }
            .padding(.leading, 10 + CGFloat(action.depth) * 18)
            .padding(.trailing, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected == index ? Color.accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
#if os(macOS)
        .onHover { hovering in if hovering { selected = index } }
#endif
    }
}
