import SwiftUI
import ScryerCore

/// App-wide settings, styled like macOS System Settings: a sidebar `List` plus grouped
/// `Form` content. Pages: Appearance / Backends / Controls / Gateway.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let backendId: String
    let defaultMachineName: String

    enum Page: String, CaseIterable, Identifiable, Hashable {
        case appearance = "Appearance", audio = "Audio", backends = "Backends", controls = "Controls", kanbaner = "Kanbaner", gateway = "Gateway"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .appearance: return "textformat.size"
            case .audio: return "waveform"
            case .backends: return "desktopcomputer"
            case .controls: return "switch.2"
            case .kanbaner: return "square.grid.3x1.below.line.grid.1x2"
            case .gateway: return "point.3.connected.trianglepath.dotted"
            }
        }
    }

    @State private var page: Page = .appearance
    @State private var selectedBackendId = ""
    @State private var gatewayBackends: [BackendMachine] = []
    @State private var gatewayBusy = false

    private var reachable: [BackendMachine] { model.backends.filter(\.isSelectable) }
    private var selectedLabel: String { model.backends.first { $0.id == selectedBackendId }?.label ?? defaultMachineName }

    var body: some View {
        content
            .onAppear { if selectedBackendId.isEmpty { selectedBackendId = backendId } }
    }

    #if os(macOS)
    private var content: some View {
        HStack(spacing: 0) {
            List(selection: pageSelection) {
                ForEach(Page.allCases) { item in
                    Label(item.rawValue, systemImage: item.symbol).tag(item)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 184)

            Divider()

            VStack(spacing: 0) {
                HStack {
                    Text(page.rawValue).font(.headline)
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)) }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 18).padding(.vertical, 14)
                Divider()
                Form { pageContent(for: page) }.formStyle(.grouped)
            }
        }
        .frame(width: 660, height: 460)
        .onChange(of: page) { _, newPage in
            if newPage == .gateway { Task { await loadGateway() } }
        }
    }
    #else
    private var content: some View {
        // iPad-native: a sidebar + detail split (collapses to a drill-down on iPhone),
        // matching the macOS layout and Settings.app on iPad.
        NavigationSplitView {
            List(selection: pageSelection) {
                ForEach(Page.allCases) { item in
                    Label(item.rawValue, systemImage: item.symbol).tag(item)
                }
            }
            .navigationTitle("Settings")
        } detail: {
            Form { pageContent(for: page) }
                .navigationTitle(page.rawValue)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(width: 28, height: 28)
                                .overlay(Circle().stroke(.secondary.opacity(0.45), lineWidth: 1))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Close")
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .task(id: page) { if page == .gateway { await loadGateway() } }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
    #endif

    private var pageSelection: Binding<Page?> {
        Binding(get: { page }, set: { if let value = $0 { page = value } })
    }

    @ViewBuilder private func pageContent(for page: Page) -> some View {
        switch page {
        case .appearance: appearanceSections
        case .audio: audioSections
        case .backends: backendSections
        case .controls: controlsSections
        case .kanbaner: kanbanerSections
        case .gateway: gatewaySections
        }
    }

    // MARK: Kanbaner

    @ViewBuilder private var kanbanerSections: some View {
        Section {
            TextField("Host:port", text: pmHostBinding, prompt: Text(PmEndpoint.defaultHost))
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif
                .font(.callout.monospaced())
            Button("Reset to default") { model.pmHost = PmEndpoint.defaultHost }
        } header: {
            Text("PM system endpoint")
        } footer: {
            Text("The Kanbaner board talks to the JEPM PM system directly at this host. Resolves to \(model.pmEndpoint.displayHost).")
        }
    }

    private var pmHostBinding: Binding<String> {
        Binding(get: { model.pmHost }, set: { model.pmHost = $0 })
    }

    // MARK: Appearance

    @ViewBuilder private var appearanceSections: some View {
        Section("Terminal") {
            Picker("Theme", selection: themeBinding) {
                ForEach(AppTheme.allCases) { Text($0.displayName).tag($0) }
            }
            LabeledContent("Font size") {
                HStack(spacing: 12) {
                    Slider(value: fontSizeBinding, in: AppModel.fontSizeRange, step: 1).frame(width: 180)
                    Text("\(Int(model.fontSize)) pt").font(.callout.monospaced()).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var themeBinding: Binding<AppTheme> {
        Binding(get: { model.theme }, set: { model.theme = $0 })
    }

    // MARK: Audio

    @ViewBuilder private var audioSections: some View {
        Section {
            LabeledContent("Allowed pause length") {
                HStack(spacing: 12) {
                    Slider(value: pauseBinding, in: AppModel.voicePauseRange, step: 1).frame(width: 180)
                    Text("\(Int(model.voicePauseLength)) s").font(.callout.monospaced()).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Voice dictation")
        } footer: {
            Text("How long to keep listening through a silence before auto-stopping (3–15s).")
        }
    }

    private var pauseBinding: Binding<Double> {
        Binding(get: { model.voicePauseLength }, set: { model.voicePauseLength = $0 })
    }

    // MARK: Backends

    @ViewBuilder private var backendSections: some View {
        Section {
            if !reachable.isEmpty {
                Picker("Backend", selection: $selectedBackendId) {
                    ForEach(reachable) { Text($0.label).tag($0.id) }
                }
            }
            TextField("Display name", text: nameBinding, prompt: Text(selectedLabel))
            ColorPicker("Name color", selection: nameColorBinding, supportsOpacity: false)
        } header: {
            Text("Backend")
        } footer: {
            Text("Display name, color, and icons are stored locally on this device.")
        }

        Section("Icons") {
            ForEach(MachineIconOption.Group.allCases, id: \.self) { group in
                LabeledContent(group.rawValue) {
                    HStack(spacing: 6) {
                        ForEach(MachineIcons.options.filter { $0.group == group }) { option in
                            let selected = model.icons(for: selectedBackendId).contains(option.id)
                            Button { model.toggleIcon(option.id, for: selectedBackendId) } label: {
                                MachineIconGlyph(id: option.id, selected: selected)
                            }
                            .buttonStyle(.plain)
                            .help(option.label)
                        }
                    }
                }
            }
        }

        Section {
            Button("Clear icons") { model.clearIcons(for: selectedBackendId) }
            Button("Reset name & color", role: .destructive) {
                model.machineNames[selectedBackendId] = nil
                model.machineNameColors[selectedBackendId] = nil
            }
        }
    }

    // MARK: Controls

    @ViewBuilder private var controlsSections: some View {
        Section {
            Toggle("Font Size Controls", isOn: hostButtonBinding(\.fontSize))
            Toggle("Interactions", isOn: hostButtonBinding(\.interaction))
            Toggle("Agent Updates", isOn: hostButtonBinding(\.agentUpdates))
            Toggle("Scryer Picker", isOn: hostButtonBinding(\.scryer))
            Toggle("Audio Input", isOn: hostButtonBinding(\.audioInput))
            Toggle("Reconnect", isOn: hostButtonBinding(\.reconnect))
        } header: {
            Text("Host bar controls")
        } footer: {
            Text("Active-pane controls shown in the host bar.")
        }
    }

    // MARK: Gateway

    @ViewBuilder private var gatewaySections: some View {
        let list = gatewayBackends.isEmpty ? model.backends : gatewayBackends
        Section {
            if list.isEmpty {
                Text(gatewayBusy ? "Loading registry…" : "No machines registered.").foregroundStyle(.secondary)
            }
            ForEach(list) { backend in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(backend.label).fontWeight(.medium)
                        let status = backend.decodingStatusFallback()
                        Text(status.rawValue.capitalized)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(statusColor(status))
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(statusColor(status).opacity(0.18), in: Capsule())
                    }
                    Text("\(backend.id) · \(backend.transport ?? "transport?") · \(backend.source ?? "registry")")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                    if let baseUrl = backend.baseUrl {
                        Text(baseUrl).font(.caption.monospaced()).foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            HStack {
                Text("Registry")
                Spacer()
                Button("Refresh") { Task { await loadGateway() } }.disabled(gatewayBusy).font(.caption)
            }
        }
    }

    // MARK: Bindings & data

    private var fontSizeBinding: Binding<Double> {
        Binding(get: { model.fontSize }, set: { model.fontSize = $0 })
    }
    private var nameBinding: Binding<String> {
        Binding(get: { model.machineNames[selectedBackendId] ?? "" }, set: { model.setMachineName($0, for: selectedBackendId) })
    }
    private var nameColorBinding: Binding<Color> {
        Binding(
            get: { model.machineNameColor(for: selectedBackendId).flatMap { Color(hex: $0) } ?? .accentColor },
            set: { if let hex = $0.toHex() { model.setMachineNameColor(hex, for: selectedBackendId) } }
        )
    }
    private func hostButtonBinding(_ keyPath: WritableKeyPath<HostButtonSettings, Bool>) -> Binding<Bool> {
        Binding(get: { model.hostButtons[keyPath: keyPath] }, set: { model.hostButtons[keyPath: keyPath] = $0 })
    }

    private func statusColor(_ status: BackendMachine.Status) -> Color {
        switch status {
        case .online: return .green
        case .stale: return .orange
        case .offline: return .red
        case .unknown: return .gray
        }
    }

    private func loadGateway() async {
        guard let endpoint = model.endpoint else { return }
        gatewayBusy = true
        defer { gatewayBusy = false }
        gatewayBackends = (try? await GatewayClient(endpoint: endpoint).listBackends()) ?? gatewayBackends
    }
}
