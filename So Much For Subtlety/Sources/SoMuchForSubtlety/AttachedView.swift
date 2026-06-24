import SwiftUI
import AppKit
import ScryerCore

/// After a backend is selected: load its workspace/pane graph and let the user open
/// any existing pane (reattaching to the live PTY session by its real paneId).
struct AttachedView: View {
    @Environment(AppModel.self) private var model
    let backend: BackendMachine

    @State private var state: AppState?
    @State private var selectedPaneId: String?
    @State private var loadError: String?
    @State private var store = TerminalStore()
    @State private var showingSettings = false
    @State private var showingMachinePicker = false
    @State private var showingQuickInputs = false
    @State private var hoveredWorkspaceId: String?
    @State private var renamingWorkspaceId: String?
    @State private var renameDraft = ""

    private static let workspaceColors: [(name: String, hex: String)] = [
        ("Blue", "#5AA6F0"), ("Amber", "#E8B65A"), ("Green", "#6FCB7F"), ("Cyan", "#4FC9D4"),
        ("Purple", "#B47BE8"), ("Coral", "#F0786E"), ("Slate", "#8A93A3"),
    ]

    private var terminalBackground: Color { Color(hex: "#222B36") ?? .black }
    private var chromeBackground: Color { Color(hex: "#21252B") ?? .black }     // One Dark UI chrome

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .zIndex(1)
            if let state {
                HStack(spacing: 0) {
                    if !model.sidebarCollapsed {
                        sidebar(state)
                            .frame(width: 220)
                            .background(chromeBackground)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                        Divider()
                    }
                    terminal
                }
            } else {
                loadingOrError
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(terminalBackground)
        .ignoresSafeArea(.container, edges: .top)   // top bar shares the traffic-light row
        .task(id: backend.id) { await loadState() }
        .onDisappear { store.teardown() }
        .onChange(of: model.fontSize) { _, newValue in store.setFontSize(CGFloat(newValue)) }
        .sheet(isPresented: $showingSettings) {
            SettingsView(backendId: backend.id, defaultMachineName: state?.hostName ?? backend.label).environment(model)
        }
        .sheet(isPresented: $showingMachinePicker) {
            MachinePickerSheet(currentBackendId: backend.id) { selected in
                if selected.id != backend.id { model.select(selected) }
            }
            .environment(model)
        }
        .sheet(isPresented: $showingQuickInputs) {
            QuickInputsView { text in activeController?.send(text) }
        }
        .alert("Rename Workspace", isPresented: Binding(get: { renamingWorkspaceId != nil }, set: { if !$0 { renamingWorkspaceId = nil } })) {
            TextField("Name", text: $renameDraft)
            Button("Save") { Task { await renameWorkspace() } }
            Button("Cancel", role: .cancel) { renamingWorkspaceId = nil }
        }
    }

    private var displayMachineName: String {
        model.machineName(for: backend.id) ?? state?.hostName ?? backend.label
    }

    private var machineNameColor: Color? {
        model.machineNameColor(for: backend.id).flatMap { Color(hex: $0) }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Button(action: { withAnimation(.easeInOut(duration: 0.18)) { model.sidebarCollapsed.toggle() } }) {
                Image(systemName: "sidebar.left").font(.system(size: 13))
            }
            .buttonStyle(.borderless)
            .help(model.sidebarCollapsed ? "Show terminals" : "Hide terminals")

            Button(action: { showingMachinePicker = true }) {
                HStack(spacing: 5) {
                    ForEach(model.icons(for: backend.id), id: \.self) { iconId in
                        Image(systemName: MachineIcons.symbol(for: iconId))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(machineNameColor ?? Color.primary)
                    }
                    Text(displayMachineName).font(.system(size: 12, weight: .medium))
                        .foregroundStyle(machineNameColor ?? Color.primary)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 8)).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Switch machine")

            Spacer()

            hostActions

            Button(action: { showingSettings = true }) { Image(systemName: "gearshape").font(.system(size: 11)) }
                .buttonStyle(.borderless)
                .help("Settings")
        }
        .padding(.leading, 78)   // clear the macOS traffic-light buttons
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        .background(chromeBackground)
    }

    @ViewBuilder private var hostActions: some View {
        if model.hostButtons.fontSize {
            Button { adjustFontSize(-1) } label: { Image(systemName: "minus.magnifyingglass").font(.system(size: 11)) }
                .buttonStyle(.borderless).help("Decrease font size")
            Button { adjustFontSize(1) } label: { Image(systemName: "plus.magnifyingglass").font(.system(size: 11)) }
                .buttonStyle(.borderless).help("Increase font size")
        }
        if model.hostButtons.quickInputs {
            Button { showingQuickInputs = true } label: { Image(systemName: "keyboard").font(.system(size: 11)) }
                .buttonStyle(.borderless).help("Quick inputs")
        }
        if model.hostButtons.fontSize || model.hostButtons.quickInputs {
            Divider().frame(height: 13).padding(.horizontal, 3)
        }
    }

    private var activeController: TerminalController? {
        selectedPaneId.flatMap { store.existing(paneId: $0) }
    }

    private func adjustFontSize(_ delta: Double) {
        model.fontSize = min(max(model.fontSize + delta, AppModel.fontSizeRange.lowerBound), AppModel.fontSizeRange.upperBound)
    }

    private func selectWorkspace(_ workspace: Workspace) {
        guard let paneId = workspace.panes.first?.id else { return }
        selectedPaneId = paneId
        model.setLastWorkspaceId(workspace.id, for: backend.id)
    }

    private func rememberSelectedWorkspace(in state: AppState) {
        guard let selectedPaneId,
              let workspace = state.workspaces.first(where: { $0.panes.contains { $0.id == selectedPaneId } })
        else { return }
        model.setLastWorkspaceId(workspace.id, for: backend.id)
    }

    private func sidebar(_ state: AppState) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("WORKSPACES")
                    .font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.tertiary)
                Spacer()
                Button { Task { await addWorkspace() } } label: {
                    Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("New workspace")
            }
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)

            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(state.workspaces) { workspace in
                        workspaceRow(workspace, isSelected: workspace.panes.first?.id == selectedPaneId)
                    }
                }
                .padding(.horizontal, 8).padding(.bottom, 8)
            }
        }
    }

    // One workspace == one terminal (we cap at one pane per workspace).
    private func workspaceRow(_ workspace: Workspace, isSelected: Bool) -> some View {
        let showClose = hoveredWorkspaceId == workspace.id || isSelected
        return Button(action: { selectWorkspace(workspace) }) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: workspace.color) ?? .gray)
                    .frame(width: 9, height: 9)
                Text(workspace.name).font(.system(size: 12)).lineLimit(1)
                Spacer(minLength: 4)
                Button { Task { await closeWorkspace(workspace) } } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .opacity(showClose ? 1 : 0)
                .help("Close workspace")
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.25) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in hoveredWorkspaceId = hovering ? workspace.id : (hoveredWorkspaceId == workspace.id ? nil : hoveredWorkspaceId) }
        .contextMenu {
            Button("Rename…") { startRename(workspace) }
            Menu("Color") {
                ForEach(Self.workspaceColors.indices, id: \.self) { index in
                    let swatch = Self.workspaceColors[index]
                    Button {
                        Task { await setWorkspaceColor(swatch.hex, for: workspace) }
                    } label: {
                        Label(swatch.name, systemImage: workspace.color.caseInsensitiveCompare(swatch.hex) == .orderedSame ? "checkmark" : "circle")
                    }
                }
            }
            Divider()
            Button("Close Workspace", role: .destructive) { Task { await closeWorkspace(workspace) } }
        }
    }

    @ViewBuilder private var terminal: some View {
        if let paneId = selectedPaneId,
           let endpoint = model.endpoint,
           let pane = state?.workspaces.flatMap(\.panes).first(where: { $0.id == paneId }),
           let controller = store.controller(paneId: paneId, endpoint: endpoint, backendId: backend.id, fontSize: CGFloat(model.fontSize)) {
            TerminalHostView(controller: controller, fallbackTitle: pane.title)
                .id(paneId)
        } else {
            ZStack {
                Color.black
                Text("Select a terminal").foregroundStyle(.secondary)
            }
        }
    }

    private var loadingOrError: some View {
        VStack(spacing: 10) {
            if let loadError {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.yellow)
                Text("Couldn't load state").font(.system(size: 13, weight: .medium))
                Text(loadError).font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Retry") { Task { await loadState() } }
            } else {
                ProgressView()
                Text("Loading terminals…").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadState() async {
        guard let endpoint = model.endpoint else { return }
        loadError = nil
        do {
            let loaded = try await GatewayClient(endpoint: endpoint).loadState(backendId: backend.id)
            state = loaded
            // Restore the last workspace selected for this backend, falling back to the backend's active/default pane.
            if selectedPaneId == nil || !loaded.workspaces.flatMap(\.panes).contains(where: { $0.id == selectedPaneId }) {
                if let workspaceId = model.lastWorkspaceId(for: backend.id),
                   let workspace = loaded.workspaces.first(where: { $0.id == workspaceId }),
                   let paneId = workspace.panes.first?.id {
                    selectedPaneId = paneId
                } else {
                    selectedPaneId = loaded.activeWorkspace?.activePaneId ?? loaded.workspaces.first?.panes.first?.id
                }
            }
            rememberSelectedWorkspace(in: loaded)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func addWorkspace() async {
        guard var next = state else { return }
        let pane = Pane(title: "Terminal 1")
        let color = Self.workspaceColors[next.workspaces.count % Self.workspaceColors.count].hex
        let workspace = Workspace(name: "workspace \(next.workspaces.count + 1)", color: color, panes: [pane], activePaneId: pane.id)
        next.workspaces.append(workspace)
        next.activeWorkspaceId = workspace.id
        state = next
        selectedPaneId = pane.id   // opens (and connects) the new terminal
        model.setLastWorkspaceId(workspace.id, for: backend.id)
        await persist(next)
    }

    private func closeWorkspace(_ workspace: Workspace) async {
        guard var next = state, let endpoint = model.endpoint else { return }
        let client = GatewayClient(endpoint: endpoint)
        for pane in workspace.panes {
            store.close(paneId: pane.id)
            try? await client.killSession(backendId: backend.id, paneId: pane.id)
        }
        next.workspaces.removeAll { $0.id == workspace.id }
        if next.workspaces.isEmpty {
            let pane = Pane(title: "Terminal 1")
            next.workspaces = [Workspace(name: "workspace 1", color: Self.workspaceColors[0].hex, panes: [pane], activePaneId: pane.id)]
        }
        // Keep a valid selection.
        if !next.workspaces.contains(where: { $0.panes.contains { $0.id == selectedPaneId } }) {
            selectedPaneId = next.workspaces.first?.panes.first?.id
        }
        next.activeWorkspaceId = next.workspaces.first { $0.panes.contains { $0.id == selectedPaneId } }?.id ?? next.workspaces[0].id
        state = next
        rememberSelectedWorkspace(in: next)
        await persist(next)
    }

    private func startRename(_ workspace: Workspace) {
        renameDraft = workspace.name
        renamingWorkspaceId = workspace.id
    }

    private func renameWorkspace() async {
        guard var next = state, let id = renamingWorkspaceId,
              let index = next.workspaces.firstIndex(where: { $0.id == id }) else { return }
        let name = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        renamingWorkspaceId = nil
        guard !name.isEmpty else { return }
        next.workspaces[index].name = name
        state = next
        await persist(next)
    }

    private func setWorkspaceColor(_ hex: String, for workspace: Workspace) async {
        guard var next = state, let index = next.workspaces.firstIndex(where: { $0.id == workspace.id }) else { return }
        next.workspaces[index].color = hex
        state = next
        await persist(next)
    }

    private func persist(_ appState: AppState) async {
        guard let endpoint = model.endpoint else { return }
        do {
            let saved = try await GatewayClient(endpoint: endpoint).saveState(backendId: backend.id, appState)
            state = saved
        } catch {
            loadError = error.localizedDescription
        }
    }
}

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// "#RRGGBB" for the color in sRGB, or nil if it can't be resolved.
    func toHex() -> String? {
        guard let ns = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let r = Int((ns.redComponent * 255).rounded())
        let g = Int((ns.greenComponent * 255).rounded())
        let b = Int((ns.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
