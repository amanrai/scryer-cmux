import SwiftUI
import ScryerCore

/// App-wide settings, styled like macOS System Settings: a sidebar `List` plus grouped
/// `Form` content. Mirrors the gateway-ui pages (Machine / Buttons / PTY / Gateway).
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let backendId: String
    let defaultMachineName: String

    enum Page: String, CaseIterable, Identifiable, Hashable {
        case appearance = "Appearance", machine = "Machine", buttons = "Buttons", pty = "PTY", gateway = "Gateway"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .appearance: return "textformat.size"
            case .machine: return "desktopcomputer"
            case .buttons: return "switch.2"
            case .pty: return "antenna.radiowaves.left.and.right"
            case .gateway: return "point.3.connected.trianglepath.dotted"
            }
        }
    }

    @State private var page: Page = .appearance
    @State private var selectedBackendId = ""
    @State private var ptyDraft: PtyConfig?
    @State private var ptyStatus: PtyConfigStatus?
    @State private var ptyMessage = ""
    @State private var ptyBusy = false
    @State private var gatewayBackends: [BackendMachine] = []
    @State private var gatewayBusy = false

    private var reachable: [BackendMachine] { model.backends.filter(\.isSelectable) }
    private var selectedLabel: String { model.backends.first { $0.id == selectedBackendId }?.label ?? defaultMachineName }

    var body: some View {
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
                Form { pageContent }.formStyle(.grouped)
            }
        }
        .frame(width: 660, height: 460)
        .onAppear { if selectedBackendId.isEmpty { selectedBackendId = backendId } }
        .onChange(of: page) { _, newPage in
            if newPage == .pty { Task { await loadPty() } }
            if newPage == .gateway { Task { await loadGateway() } }
        }
        .onChange(of: selectedBackendId) { _, _ in if page == .pty { Task { await loadPty() } } }
    }

    private var pageSelection: Binding<Page?> {
        Binding(get: { page }, set: { if let value = $0 { page = value } })
    }

    @ViewBuilder private var pageContent: some View {
        switch page {
        case .appearance: appearanceSections
        case .machine: machineSections
        case .buttons: buttonsSections
        case .pty: ptySections
        case .gateway: gatewaySections
        }
    }

    // MARK: Appearance

    @ViewBuilder private var appearanceSections: some View {
        Section("Terminal") {
            LabeledContent("Font size") {
                HStack(spacing: 12) {
                    Slider(value: fontSizeBinding, in: AppModel.fontSizeRange, step: 1).frame(width: 180)
                    Text("\(Int(model.fontSize)) pt").font(.callout.monospaced()).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Machine

    @ViewBuilder private var machineSections: some View {
        Section {
            if !reachable.isEmpty {
                Picker("Machine", selection: $selectedBackendId) {
                    ForEach(reachable) { Text($0.label).tag($0.id) }
                }
            }
            TextField("Display name", text: nameBinding, prompt: Text(selectedLabel))
            ColorPicker("Name color", selection: nameColorBinding, supportsOpacity: false)
        } header: {
            Text("Machine")
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
                                Image(systemName: option.symbol)
                                    .frame(width: 26, height: 22)
                                    .background(selected ? Color.accentColor.opacity(0.28) : Color.secondary.opacity(0.12),
                                                in: RoundedRectangle(cornerRadius: 5))
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

    // MARK: Buttons

    @ViewBuilder private var buttonsSections: some View {
        Section {
            Toggle("Font Size", isOn: hostButtonBinding(\.fontSize))
            Toggle("Interaction", isOn: hostButtonBinding(\.interaction))
            Toggle("Agent Updates", isOn: hostButtonBinding(\.agentUpdates))
            Toggle("Scryer", isOn: hostButtonBinding(\.scryer))
            Toggle("Quick Inputs", isOn: hostButtonBinding(\.quickInputs))
        } header: {
            Text("Host bar buttons")
        } footer: {
            Text("Active-pane buttons shown in the host bar. The Scryer features arrive later.")
        }
    }

    // MARK: PTY

    @ViewBuilder private var ptySections: some View {
        if let draft = ptyDraft {
            Section("PTY server") {
                TextField("Gateway URL", text: ptyString(\.gatewayUrl), prompt: Text("http://gateway-host:43223"))
                TextField("Machine ID", text: ptyString(\.machineId))
                TextField("Machine name", text: ptyString(\.machineName))
                LabeledContent("PTY URL", value: draft.publicUrl)
                Toggle("Heartbeat enabled", isOn: Binding(get: { ptyDraft?.heartbeatEnabled ?? false }, set: { ptyDraft?.heartbeatEnabled = $0 }))
            }
            Section {
                HStack {
                    Button("Reload") { Task { await loadPty() } }.disabled(ptyBusy)
                    Spacer()
                    Button("Save") { Task { await savePty(register: false) } }.disabled(ptyBusy)
                    Button("Register") { Task { await savePty(register: true) } }
                        .buttonStyle(.borderedProminent)
                        .disabled(ptyBusy || draft.gatewayUrl.isEmpty || draft.publicUrl.isEmpty)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Status: \(ptyStatus?.registered == true ? "registered" : "not registered") · Last success: \(ptyStatus?.lastSuccessAt ?? "never")")
                    if let error = ptyStatus?.lastError { Text(error).foregroundStyle(.red) }
                    if !ptyMessage.isEmpty { Text(ptyMessage) }
                }
            }
        } else {
            Section {
                Text(ptyBusy ? "Loading PTY config…" : (ptyMessage.isEmpty ? "PTY config unavailable." : ptyMessage))
                    .foregroundStyle(.secondary)
            }
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
                        Text(backend.decodingStatusFallback().rawValue)
                            .font(.caption2).foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
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
    private func ptyString(_ keyPath: WritableKeyPath<PtyConfig, String>) -> Binding<String> {
        Binding(get: { ptyDraft?[keyPath: keyPath] ?? "" }, set: { ptyDraft?[keyPath: keyPath] = $0 })
    }

    private func loadPty() async {
        guard let endpoint = model.endpoint else { ptyMessage = "No gateway."; return }
        ptyBusy = true; ptyMessage = ""
        defer { ptyBusy = false }
        do {
            let payload = try await GatewayClient(endpoint: endpoint).ptyConfig(backendId: selectedBackendId)
            ptyDraft = payload.config; ptyStatus = payload.status
        } catch {
            ptyDraft = nil; ptyMessage = error.localizedDescription
        }
    }

    private func savePty(register: Bool) async {
        guard let endpoint = model.endpoint, let draft = ptyDraft else { return }
        ptyBusy = true; ptyMessage = ""
        defer { ptyBusy = false }
        do {
            let payload = try await GatewayClient(endpoint: endpoint).writePtyConfig(backendId: selectedBackendId, draft, register: register)
            ptyDraft = payload.config; ptyStatus = payload.status
            ptyMessage = register ? "Registered with gateway." : "Saved."
        } catch {
            ptyMessage = error.localizedDescription
        }
    }

    private func loadGateway() async {
        guard let endpoint = model.endpoint else { return }
        gatewayBusy = true
        defer { gatewayBusy = false }
        gatewayBackends = (try? await GatewayClient(endpoint: endpoint).listBackends()) ?? gatewayBackends
    }
}
