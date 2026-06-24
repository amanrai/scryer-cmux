import Foundation
import Observation
import ScryerCore

/// Which active-pane buttons appear in the host bar.
struct HostButtonSettings: Codable, Equatable {
    var fontSize = true
    var interaction = true
    var agentUpdates = true
    var scryer = true
    var quickInputs = false
}

/// Top-level app state: which gateway we're talking to and which backend is selected.
/// Backend selection is core piece 1.
@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case disconnected
        case loadingBackends
        case picking
        case attached(BackendMachine)
    }

    var phase: Phase = .disconnected
    var endpoint: GatewayEndpoint?
    var backends: [BackendMachine] = []
    var selectedBackend: BackendMachine?
    var errorMessage: String?

    /// Terminal font point size. Persisted; applied live to all open terminals.
    var fontSize: Double {
        didSet { UserDefaults.standard.set(fontSize, forKey: Self.fontSizeDefaultsKey) }
    }

    private var refreshTask: Task<Void, Never>?

    private static let endpointDefaultsKey = "smfs.gateway.endpoint"
    private static let backendDefaultsKey = "smfs.backend.id"
    private static let fontSizeDefaultsKey = "smfs.fontSize"

    static let fontSizeRange: ClosedRange<Double> = 8...28

    /// Per-backend display name overrides (local to this device).
    var machineNames: [String: String] = [:] {
        didSet { UserDefaults.standard.set(machineNames, forKey: Self.machineNamesKey) }
    }
    /// Per-backend display-name colors (hex).
    var machineNameColors: [String: String] = [:] {
        didSet { UserDefaults.standard.set(machineNameColors, forKey: Self.machineNameColorsKey) }
    }
    private static let machineNamesKey = "smfs.machineNames"
    private static let machineNameColorsKey = "smfs.machineNameColors"
    private static let lastWorkspaceKey = "smfs.lastWorkspaceByBackend"
    private static let sidebarCollapsedKey = "smfs.sidebarCollapsed"

    func machineName(for backendId: String) -> String? {
        let trimmed = machineNames[backendId]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }
    func machineNameColor(for backendId: String) -> String? { machineNameColors[backendId] }
    func setMachineName(_ name: String, for backendId: String) { machineNames[backendId] = name }
    func setMachineNameColor(_ hex: String, for backendId: String) { machineNameColors[backendId] = hex }

    /// Last selected workspace per backend, restored when switching machines.
    var lastWorkspaceByBackend: [String: String] = [:] {
        didSet { UserDefaults.standard.set(lastWorkspaceByBackend, forKey: Self.lastWorkspaceKey) }
    }
    var sidebarCollapsed = false {
        didSet { UserDefaults.standard.set(sidebarCollapsed, forKey: Self.sidebarCollapsedKey) }
    }
    func lastWorkspaceId(for backendId: String) -> String? { lastWorkspaceByBackend[backendId] }
    func setLastWorkspaceId(_ workspaceId: String, for backendId: String) { lastWorkspaceByBackend[backendId] = workspaceId }

    /// Per-backend selected machine icon ids.
    var machineIcons: [String: [String]] = [:] {
        didSet { UserDefaults.standard.set(machineIcons, forKey: Self.machineIconsKey) }
    }
    /// Which active-pane buttons appear in the host bar (Scryer features land later).
    var hostButtons = HostButtonSettings() {
        didSet {
            if let data = try? JSONEncoder().encode(hostButtons) { UserDefaults.standard.set(data, forKey: Self.hostButtonsKey) }
        }
    }
    private static let machineIconsKey = "smfs.machineIcons"
    private static let hostButtonsKey = "smfs.hostButtons"

    func icons(for backendId: String) -> [String] { machineIcons[backendId] ?? [] }
    func toggleIcon(_ id: String, for backendId: String) {
        var current = machineIcons[backendId] ?? []
        if let index = current.firstIndex(of: id) { current.remove(at: index) } else { current.append(id) }
        machineIcons[backendId] = current.isEmpty ? nil : current
    }
    func clearIcons(for backendId: String) { machineIcons[backendId] = nil }

    init() {
        let stored = UserDefaults.standard.object(forKey: Self.fontSizeDefaultsKey) as? Double
        self.fontSize = stored.map { min(max($0, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound) } ?? 13
        self.machineNames = UserDefaults.standard.dictionary(forKey: Self.machineNamesKey) as? [String: String] ?? [:]
        self.machineNameColors = UserDefaults.standard.dictionary(forKey: Self.machineNameColorsKey) as? [String: String] ?? [:]
        self.lastWorkspaceByBackend = UserDefaults.standard.dictionary(forKey: Self.lastWorkspaceKey) as? [String: String] ?? [:]
        self.sidebarCollapsed = UserDefaults.standard.bool(forKey: Self.sidebarCollapsedKey)
        self.machineIcons = UserDefaults.standard.dictionary(forKey: Self.machineIconsKey) as? [String: [String]] ?? [:]
        if let data = UserDefaults.standard.data(forKey: Self.hostButtonsKey),
           let decoded = try? JSONDecoder().decode(HostButtonSettings.self, from: data) {
            self.hostButtons = decoded
        }
        if let raw = UserDefaults.standard.string(forKey: Self.endpointDefaultsKey),
           let endpoint = GatewayEndpoint(rawInput: raw) {
            self.endpoint = endpoint
        }
    }

    var gatewayHostDraft: String {
        endpoint?.displayHost ?? ""
    }

    func connect(toGatewayInput input: String) {
        guard let endpoint = GatewayEndpoint(rawInput: input) else {
            errorMessage = "Enter a gateway host, e.g. machine.tailnet.ts.net:43223"
            return
        }
        self.endpoint = endpoint
        UserDefaults.standard.set(endpoint.displayHost, forKey: Self.endpointDefaultsKey)
        errorMessage = nil
        startRefreshing()
    }

    func disconnect() {
        refreshTask?.cancel()
        refreshTask = nil
        selectedBackend = nil
        backends = []
        phase = .disconnected
    }

    func select(_ backend: BackendMachine) {
        selectedBackend = backend
        UserDefaults.standard.set(backend.id, forKey: Self.backendDefaultsKey)
        phase = .attached(backend)
    }

    func backToPicker() {
        selectedBackend = nil
        phase = .picking
    }

    /// Poll `/api/backends` every 10s like the browser client does.
    func startRefreshing() {
        guard let endpoint else { return }
        refreshTask?.cancel()
        phase = .loadingBackends
        let client = GatewayClient(endpoint: endpoint)
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let list = try await client.listBackends()
                    await MainActor.run { self?.applyBackends(list) }
                } catch {
                    await MainActor.run { self?.applyError(error) }
                }
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private func applyBackends(_ list: [BackendMachine]) {
        errorMessage = nil
        backends = list.sorted { ($0.label).localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        // Auto-restore a previously selected, still-online backend.
        if case .attached = phase { return }
        if phase == .loadingBackends || phase == .picking {
            phase = .picking
            if selectedBackend == nil,
               let savedId = UserDefaults.standard.string(forKey: Self.backendDefaultsKey),
               let saved = backends.first(where: { $0.id == savedId && $0.isSelectable }) {
                select(saved)
            }
        }
    }

    private func applyError(_ error: Error) {
        if backends.isEmpty {
            errorMessage = error.localizedDescription
            if phase == .loadingBackends { phase = .picking }
        }
    }
}
