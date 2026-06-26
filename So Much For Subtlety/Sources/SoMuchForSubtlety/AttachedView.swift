import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import ScryerCore

/// After a backend is selected: load its workspace/pane graph and let the user open
/// any existing pane (reattaching to the live PTY session by its real paneId).
struct AttachedView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    let backend: BackendMachine

    @State private var state: AppState?
    @State private var selectedPaneId: String?
    @State private var loadError: String?
    @State private var store = TerminalStore()
    @State private var showingSettings = false
    @State private var showingMachinePicker = false
    @State private var showingQuickInputs = false
    @State private var showingInteraction = false
    @State private var showingActivity = false
    @State private var showingScryerPicker = false
    @State private var showingDictation = false
    @State private var wasBackgrounded = false   // gate scenePhase auto-reconnect
    @State private var hoveredWorkspaceId: String?
    @State private var renamingWorkspaceId: String?
    @State private var renameDraft = ""
    #if os(iOS)
    @State private var keyboardVisibility: KeyboardVisibility = .shown   // iPad floating keyboard
    @State private var keyboardVisibilityBeforeModal: KeyboardVisibility? // restore after a sheet closes
    @AppStorage("smfs.kbOffsetX") private var kbOffsetX: Double = 0      // remembered drag position
    @AppStorage("smfs.kbOffsetY") private var kbOffsetY: Double = 0

    private var anyModalOpen: Bool {
        showingSettings || showingMachinePicker || showingQuickInputs
            || showingInteraction || showingActivity || showingScryerPicker
            || showingDictation || renamingWorkspaceId != nil
    }
    private var keyboardOffset: Binding<CGSize> {
        Binding(get: { CGSize(width: kbOffsetX, height: kbOffsetY) },
                set: { kbOffsetX = $0.width; kbOffsetY = $0.height })
    }
    #endif

    private static let workspaceColors: [(name: String, hex: String, swatch: String)] = [
        ("Blue", "#5AA6F0", "🟦"), ("Amber", "#E8B65A", "🟨"), ("Green", "#6FCB7F", "🟩"), ("Cyan", "#4FC9D4", "🟦"),
        ("Purple", "#B47BE8", "🟪"), ("Coral", "#F0786E", "🟥"), ("Slate", "#8A93A3", "⬛️"),
    ]

    private var terminalBackground: Color { Color(hex: model.theme.terminal.background.hex) ?? .black }
    private var chromeBackground: Color { Color(hex: model.theme.terminal.chrome.hex) ?? .black }

    // Larger touch targets on iPad; compact on the Mac.
    private func platformValue(_ ios: CGFloat, mac: CGFloat) -> CGFloat {
        #if os(iOS)
        ios
        #else
        mac
        #endif
    }
    private var chromeGlyph: CGFloat { platformValue(17, mac: 11) }
    private var chromeSpacing: CGFloat { platformValue(18, mac: 8) }
    private var chromeMinHeight: CGFloat { platformValue(48, mac: 32) }

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
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(.black.opacity(0.22), lineWidth: 1))
                        .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 8)
                        #if os(iOS)
                        // Scrolling the terminal collapses the keyboard to faint (a compact bar,
                        // top-right); a single tap restores the full keyboard; a double tap raises
                        // it when it's been fully hidden.
                        .simultaneousGesture(DragGesture(minimumDistance: 14).onChanged { _ in
                            if keyboardVisibility == .shown { withAnimation(.easeOut(duration: 0.25)) { keyboardVisibility = .faint } }
                        })
                        .simultaneousGesture(TapGesture().onEnded {
                            if keyboardVisibility == .faint { withAnimation(.easeOut(duration: 0.18)) { keyboardVisibility = .shown } }
                        })
                        .simultaneousGesture(TapGesture(count: 2).onEnded {
                            if keyboardVisibility == .hidden { withAnimation(.easeOut(duration: 0.18)) { keyboardVisibility = .shown } }
                        })
                        // Faint state: the collapsed essentials bar, pinned to the terminal's
                        // top-right. Added after the gestures above so its key taps fire on their
                        // own without also triggering the terminal's restore-tap.
                        .overlay(alignment: .topTrailing) {
                            if keyboardVisibility == .faint, let controller = activeController {
                                CompactKeyboardBar(
                                    onKey: { controller.type($0, modifiers: []) },
                                    theme: AppTheme.matte.terminal
                                )
                                .disabled(!terminalConnected)
                                .opacity(terminalConnected ? 1 : 0.45)
                                .padding(.top, 14).padding(.trailing, 18)
                                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .topTrailing)))
                            }
                        }
                        // Dedicated, mostly-transparent voice trigger floating on the terminal's
                        // center-right. Large hit target; opens the dictation modal.
                        .overlay(alignment: .trailing) {
                            Button(action: { showingDictation = true }) {
                                Image(systemName: terminalConnected ? "mic.fill" : "mic.slash")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .frame(width: 60, height: 60)            // generous tap target
                                    .background(.black.opacity(0.22), in: Circle())
                                    .overlay(Circle().stroke(.white.opacity(0.18)))
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!terminalConnected)             // no dictating into a dead socket
                            .opacity(terminalConnected ? 1 : 0.4)
                            .padding(.trailing, 12)
                            .accessibilityLabel("Voice dictation")
                        }
                        #endif
                }
            } else {
                loadingOrError
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(chromeBackground)   // chrome is the container; the terminal nests inside it
        #if os(iOS)
        .overlay(alignment: .bottom) {
            if keyboardVisibility == .shown, let controller = activeController {
                GeometryReader { geo in
                    FloatingKeyboardView(
                        onText: { controller.type($0, modifiers: $1) },
                        onSpecialKey: { controller.type($0, modifiers: $1) },
                        onHide: { withAnimation(.easeOut(duration: 0.18)) { keyboardVisibility = .hidden } },
                        onActivate: {
                            if keyboardVisibility == .faint { withAnimation(.easeOut(duration: 0.18)) { keyboardVisibility = .shown } }
                        },
                        theme: AppTheme.matte.terminal,   // keyboard is always matte black, every theme
                        containerHeight: geo.size.height,
                        topInset: chromeMinHeight + 12,
                        position: keyboardOffset
                    )
                    .environment(\.colorScheme, .dark)   // keep handle/picker legible on the black surface
                    .disabled(!terminalConnected)        // dim + lock while the socket is down
                    .opacity(terminalConnected ? 1 : 0.45)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        #endif
        #if os(macOS)
        .ignoresSafeArea(.container, edges: .top)   // top bar shares the traffic-light row
        #endif
        .task(id: backend.id) { await loadState() }
        .onDisappear { store.teardown() }
        .onChange(of: model.fontSize) { _, newValue in store.setFontSize(CGFloat(newValue)) }
        .onChange(of: model.theme) { _, newTheme in store.setTheme(newTheme.terminal) }
        // Returning from background: the WS socket was suspended and is silently dead, so
        // reconnect the live pane automatically (input UI stays disabled until it's back up).
        // Track a flag because the phase walks .background → .inactive → .active, so the
        // step right before .active is .inactive, not .background.
        .onChange(of: scenePhase) { _, new in
            if new == .background { wasBackgrounded = true }
            else if new == .active, wasBackgrounded { wasBackgrounded = false; activeController?.reconnect() }
        }
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
        .sheet(isPresented: $showingInteraction) {
            if let controller = activeController, let request = controller.pendingInteraction {
                InteractionModalView(
                    request: request,
                    updates: controller.updates,
                    onRespond: { controller.respondToInteraction($0) },
                    onDismissRequest: { controller.dismissInteraction() }
                )
            } else {
                noInteractionPlaceholder
            }
        }
        .sheet(isPresented: $showingActivity, onDismiss: { activeController?.activityVisible = false }) {
            ActivityModalView(updates: activeController?.updates ?? [])
        }
        #if os(iOS)
        // Voice dictation: a short panel that fills an editable transcript, then injects it
        // into the terminal and submits (text + Enter) on Send. Uses the same raw-input
        // submit path as the Scryer picker / quick inputs (proven; also refocuses terminal).
        .sheet(isPresented: $showingDictation) {
            DictationView(silenceTimeout: model.voicePauseLength) { text in
                guard !text.isEmpty else { return }
                activeController?.send(text + "\r")
            }
            .presentationDetents([.height(440)])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(6)
            .presentationBackground(Color.black.opacity(0.15))   // ~85% transparent: terminal shows through
        }
        #endif
        #if os(iOS)
        // Scryer is a near-full-screen panel (85%, square corners), not a system sheet.
        .fullScreenCover(isPresented: $showingScryerPicker) {
            if let endpoint = model.endpoint {
                ScryerCover(isPresented: $showingScryerPicker) {
                    ScryerPickerView(backendId: backend.id, endpoint: endpoint) { text in activeController?.send(text) }
                }
                .presentationBackground(.clear)
            }
        }
        #else
        .sheet(isPresented: $showingScryerPicker) {
            if let endpoint = model.endpoint {
                ScryerPickerView(backendId: backend.id, endpoint: endpoint) { text in activeController?.send(text) }
            }
        }
        #endif
        .alert("Rename Workspace", isPresented: Binding(get: { renamingWorkspaceId != nil }, set: { if !$0 { renamingWorkspaceId = nil } })) {
            TextField("Name", text: $renameDraft)
            Button("Save") { Task { await renameWorkspace() } }
            Button("Cancel", role: .cancel) { renamingWorkspaceId = nil }
        }
        // Surface a freshly-arrived interaction on *every* frame, the way gateway-ui
        // does (driven by an epoch counter, not the request id, so a re-pushed id
        // still re-presents).
        .onChange(of: activeController?.interactionEpoch) { _, _ in
            if activeController?.pendingInteraction != nil, model.hostButtons.interaction {
                showingInteraction = true
            }
        }
        // Re-scan terminal state for the producer marker whenever the active pane
        // changes, so "listening" reflects the terminal we just switched to.
        .onChange(of: selectedPaneId) { _, _ in activeController?.refreshProducerState() }
        #if os(iOS)
        // Any sheet opening hides the floating keyboard; closing restores its prior state.
        .onChange(of: anyModalOpen) { _, open in
            if open {
                if keyboardVisibilityBeforeModal == nil { keyboardVisibilityBeforeModal = keyboardVisibility }
                keyboardVisibility = .hidden
            } else if let prior = keyboardVisibilityBeforeModal {
                keyboardVisibility = prior
                keyboardVisibilityBeforeModal = nil
            }
        }
        #endif
    }

    private var displayMachineName: String {
        model.machineName(for: backend.id) ?? state?.hostName ?? backend.label
    }

    private var machineNameColor: Color? {
        model.machineNameColor(for: backend.id).flatMap { Color(hex: $0) }
    }

    private var topBar: some View {
        HStack(spacing: chromeSpacing) {
            Button(action: { withAnimation(.easeInOut(duration: 0.18)) { model.sidebarCollapsed.toggle() } }) {
                Image(systemName: "sidebar.left").font(.system(size: chromeGlyph))
            }
            .buttonStyle(.borderless)
            .help(model.sidebarCollapsed ? "Show terminals" : "Hide terminals")

            Button(action: { showingMachinePicker = true }) {
                HStack(spacing: 5) {
                    ForEach(model.icons(for: backend.id), id: \.self) { iconId in
                        MachineIconGlyph(id: iconId, selected: true, compact: true)
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

            #if os(iOS)
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    keyboardVisibility = (keyboardVisibility == .hidden) ? .shown : .hidden
                }
            } label: {
                Image(systemName: keyboardVisibility == .hidden ? "keyboard" : "keyboard.chevron.compact.down")
                    .font(.system(size: chromeGlyph))
            }
            .buttonStyle(.borderless)
            .help(keyboardVisibility == .hidden ? "Show keyboard" : "Hide keyboard")
            #endif

            Button(action: { Task { await refresh() } }) { Image(systemName: "arrow.clockwise").font(.system(size: chromeGlyph)) }
                .buttonStyle(.borderless)
                .help("Refresh (reconnect after suspend)")

            Button(action: { showingSettings = true }) { Image(systemName: "gearshape").font(.system(size: chromeGlyph)) }
                .buttonStyle(.borderless)
                .help("Settings")
        }
        #if os(macOS)
        .padding(.leading, 78)   // clear the macOS traffic-light buttons
        #else
        .padding(.leading, 12)
        #endif
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity, minHeight: chromeMinHeight, alignment: .leading)
        .background(chromeBackground)
    }

    @ViewBuilder private var hostActions: some View {
        if model.hostButtons.interaction {
            let pending = activeController?.pendingInteraction != nil
            let listening = activeController?.hasProducer == true
            Button { showingInteraction = true } label: {
                Image(systemName: "bubble.left.and.bubble.right").font(.system(size: chromeGlyph))
                    // Filled when listening (a producer is attached); red dot when a
                    // response is actually needed.
                    .foregroundStyle(listening ? Color.white : Color.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 3)
                    .background(listening ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                    .overlay(alignment: .topTrailing) {
                        if pending { Circle().fill(Color.red).frame(width: 6, height: 6).offset(x: 2, y: -2) }
                    }
            }
            .buttonStyle(.borderless)
            .help(pending ? "Interaction needed" : (listening ? "Listening for interactions" : "Interaction"))
        }
        if model.hostButtons.agentUpdates {
            let unread = activeController?.unreadUpdates ?? 0
            Button {
                activeController?.activityVisible = true
                activeController?.markUpdatesRead()
                showingActivity = true
            } label: {
                Image(systemName: "list.bullet.rectangle").font(.system(size: chromeGlyph))
                    .overlay(alignment: .topTrailing) {
                        if unread > 0 {
                            Circle().fill(Color.red).frame(width: 6, height: 6).offset(x: 3, y: -2)
                        }
                    }
            }
            .buttonStyle(.borderless)
            .help("Agent updates")
        }
        if model.hostButtons.scryer {
            Button { showingScryerPicker = true } label: { Image(systemName: "rectangle.3.group").font(.system(size: chromeGlyph)) }
                .buttonStyle(.borderless).help("Scryer project & ticket")
        }
        if model.hostButtons.fontSize {
            Button { adjustFontSize(-1) } label: { Image(systemName: "minus.magnifyingglass").font(.system(size: chromeGlyph)) }
                .buttonStyle(.borderless).help("Decrease font size")
            Button { adjustFontSize(1) } label: { Image(systemName: "plus.magnifyingglass").font(.system(size: chromeGlyph)) }
                .buttonStyle(.borderless).help("Increase font size")
        }
        if model.hostButtons.quickInputs {
            Button { showingQuickInputs = true } label: { Image(systemName: "keyboard").font(.system(size: chromeGlyph)) }
                .buttonStyle(.borderless).help("Quick inputs")
        }
        Divider().frame(height: 13).padding(.horizontal, 3)
    }

    private var noInteractionPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 22)).foregroundStyle(.secondary)
            Text("No interaction pending").font(.system(size: 13, weight: .medium))
            Text("Agents request input here when they need it.")
                .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(width: 360, height: 220).padding()
    }

    // Resolve (creating if needed) the controller for the selected pane. Using
    // `controller(...)` rather than `existing(...)` matters: the top bar reads this
    // *before* the terminal view builder runs, so `existing` would return nil on the
    // first render and the bar would never establish @Observable tracking on the
    // controller's `hasProducer` — leaving the listening fill stale until some other
    // re-render. Resolving here ensures the bar observes it from the first pass.
    private var activeController: TerminalController? {
        guard let paneId = selectedPaneId, let endpoint = model.endpoint else { return nil }
        return store.controller(paneId: paneId, endpoint: endpoint, backendId: backend.id, fontSize: CGFloat(model.fontSize), theme: model.theme.terminal)
    }

    /// Whether the live terminal socket is up. Drives input gating (keyboard/mic) so a dead
    /// connection after suspend is an obvious, non-silent state.
    private var terminalConnected: Bool { activeController?.isConnected ?? false }

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
        return HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: workspace.color) ?? .gray)
                .frame(width: 9, height: 9)
            Text(workspace.name).font(.system(size: 12)).lineLimit(1)
            Spacer(minLength: 4)
            Button { Task { await closeWorkspace(workspace) } } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .opacity(showClose ? 1 : 0)
            .help("Close workspace")
        }
        .padding(.leading, 8).padding(.trailing, 3).padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.25) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onTapGesture { selectWorkspace(workspace) }
        .onHover { hovering in hoveredWorkspaceId = hovering ? workspace.id : (hoveredWorkspaceId == workspace.id ? nil : hoveredWorkspaceId) }
        .contextMenu {
            Button("Rename…") { startRename(workspace) }
            Menu("Color") {
                ForEach(Self.workspaceColors.indices, id: \.self) { index in
                    let swatch = Self.workspaceColors[index]
                    Button {
                        Task { await setWorkspaceColor(swatch.hex, for: workspace) }
                    } label: {
                        Label("\(swatch.swatch)  \(swatch.name)", systemImage: workspace.color.caseInsensitiveCompare(swatch.hex) == .orderedSame ? "checkmark" : "")
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
           let controller = store.controller(paneId: paneId, endpoint: endpoint, backendId: backend.id, fontSize: CGFloat(model.fontSize), theme: model.theme.terminal) {
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

    /// Refresh button: re-pull the workspace state and reconnect the live terminal so a
    /// session that died while the app was suspended comes back without a relaunch.
    private func refresh() async {
        activeController?.reconnect()
        await loadState()
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
        #if os(macOS)
        guard let ns = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let r = Int((ns.redComponent * 255).rounded())
        let g = Int((ns.greenComponent * 255).rounded())
        let b = Int((ns.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
        #else
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
        #endif
    }
}

#if os(iOS)
/// Floating-keyboard visibility. `shown`/`hidden` are toggled by the top-bar button;
/// `faint` is a transient dimmed state entered while scrolling and cleared by a tap.
enum KeyboardVisibility {
    case shown, faint, hidden
}
#endif
