import Foundation
import Observation
import ScryerCore

/// Which active-pane buttons appear in the host bar.
struct HostButtonSettings: Codable, Equatable {
    var fontSize = true
    var interaction = true
    var agentUpdates = true
    var scryer = true
    var audioInput = true
    var reconnect = false
    var quickInputs = false

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fontSize = try container.decodeIfPresent(Bool.self, forKey: .fontSize) ?? true
        interaction = try container.decodeIfPresent(Bool.self, forKey: .interaction) ?? true
        agentUpdates = try container.decodeIfPresent(Bool.self, forKey: .agentUpdates) ?? true
        scryer = try container.decodeIfPresent(Bool.self, forKey: .scryer) ?? true
        audioInput = try container.decodeIfPresent(Bool.self, forKey: .audioInput) ?? true
        reconnect = try container.decodeIfPresent(Bool.self, forKey: .reconnect) ?? false
        quickInputs = try container.decodeIfPresent(Bool.self, forKey: .quickInputs) ?? false
    }
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

    /// Active color theme. Persisted; applied live to all open terminals + the chrome.
    var theme: AppTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: Self.themeDefaultsKey) }
    }

    /// Voice dictation: trailing-silence (seconds) before auto-stop. Persisted.
    var voicePauseLength: Double {
        didSet { UserDefaults.standard.set(voicePauseLength, forKey: Self.voicePauseLengthKey) }
    }

    /// Host:port of the JEPM PM system the Kanbaner board talks to directly. Persisted;
    /// editable in Settings. Defaults to the known tailnet address.
    var pmHost: String {
        didSet { UserDefaults.standard.set(pmHost, forKey: Self.pmHostKey) }
    }

    /// Parsed PM endpoint, falling back to the default if the stored host is unparseable.
    var pmEndpoint: PmEndpoint { PmEndpoint(rawInput: pmHost) ?? .default }

    /// Host:port of the Scryer interaction service (direct, tailnet). Persisted.
    var interactionsHost: String {
        didSet {
            UserDefaults.standard.set(interactionsHost, forKey: Self.interactionsHostKey)
            interactions.endpoint = InteractionsEndpoint(rawInput: interactionsHost) ?? .default
        }
    }

    /// App-wide deduped store of interactions + agent updates, pulled from the interaction
    /// service across all open terminals' producers. Stored but not surfaced — the display
    /// flow is being reworked.
    let interactions = InteractionStore()

    /// Whether the Kanbaner board is currently shown (over the attached terminal screen).
    var showingKanbaner = false

    /// Last project opened in the Kanbaner, restored on reopen. Persisted.
    var lastKanbanerProjectId: String? {
        didSet { UserDefaults.standard.set(lastKanbanerProjectId, forKey: Self.lastKanbanerProjectKey) }
    }

    private var refreshTask: Task<Void, Never>?

    private static let endpointDefaultsKey = "smfs.gateway.endpoint"
    private static let backendDefaultsKey = "smfs.backend.id"
    private static let fontSizeDefaultsKey = "smfs.fontSize"
    private static let themeDefaultsKey = "smfs.theme"
    private static let voicePauseLengthKey = "smfs.voicePauseLength"
    private static let pmHostKey = "smfs.pmHost"
    private static let interactionsHostKey = "smfs.interactionsHost"
    private static let lastKanbanerProjectKey = "smfs.lastKanbanerProject"

    static let fontSizeRange: ClosedRange<Double> = 8...28
    static let voicePauseRange: ClosedRange<Double> = 3...15

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
        self.theme = UserDefaults.standard.string(forKey: Self.themeDefaultsKey).flatMap(AppTheme.init(rawValue:)) ?? .oneDark
        let storedPause = UserDefaults.standard.object(forKey: Self.voicePauseLengthKey) as? Double
        self.voicePauseLength = storedPause.map { min(max($0, Self.voicePauseRange.lowerBound), Self.voicePauseRange.upperBound) } ?? 6
        let storedPmHost = UserDefaults.standard.string(forKey: Self.pmHostKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.pmHost = (storedPmHost?.isEmpty == false ? storedPmHost! : PmEndpoint.defaultHost)
        let storedInteractionsHost = UserDefaults.standard.string(forKey: Self.interactionsHostKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.interactionsHost = (storedInteractionsHost?.isEmpty == false ? storedInteractionsHost! : InteractionsEndpoint.defaultHost)
        self.lastKanbanerProjectId = UserDefaults.standard.string(forKey: Self.lastKanbanerProjectKey)
        interactions.endpoint = InteractionsEndpoint(rawInput: interactionsHost) ?? .default
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

/// App-wide, deduped store of Scryer interactions and agent updates, pulled directly from the
/// interaction service for every active producer across open terminals. Dedup key is the item
/// `id`; updates are bucketed by producer `from` (they don't carry it). Dismissals are tracked
/// per producer and persisted, so the modal can surface only the relevant interaction.
@MainActor
@Observable
final class InteractionStore {
    private(set) var interactionsByFrom: [String: [String: InteractionRequest]] = [:]
    private(set) var updatesByFrom: [String: [String: SessionUpdate]] = [:]
    private(set) var dismissedByFrom: [String: Set<String>] = [:]
    var endpoint: InteractionsEndpoint = .default

    private static let dismissedKey = "smfs.dismissedInteractions"   // [from: [id]]

    init() {
        let dict = UserDefaults.standard.dictionary(forKey: Self.dismissedKey) as? [String: [String]] ?? [:]
        dismissedByFrom = dict.mapValues { Set($0) }
    }

    /// Interactions for one producer, recency-ascending. Bucketed by the producer we polled,
    /// so it doesn't depend on the service echoing `from` back in each request.
    func interactions(for from: String) -> [InteractionRequest] {
        (interactionsByFrom[from] ?? [:]).values.sorted { $0.order < $1.order }
    }
    /// Agent updates (notifications) for one producer, recency-ascending.
    func updates(for from: String) -> [SessionUpdate] {
        (updatesByFrom[from] ?? [:]).values.sorted { ($0.receivedAt ?? "", $0.id) < ($1.receivedAt ?? "", $1.id) }
    }

    /// The newest **undismissed** interaction that arrived **after** the newest one the user
    /// already dismissed for this producer (nil if none) — the single one to surface.
    func actionableInteraction(for from: String) -> InteractionRequest? {
        let dismissed = dismissedByFrom[from] ?? []
        let items = interactions(for: from)
        let floor = items.filter { dismissed.contains($0.id) }.map { $0.order }.max()
        let candidates = items.filter { request in
            guard !dismissed.contains(request.id) else { return false }
            if let floor { return request.order > floor }
            return true
        }
        return candidates.max { $0.order < $1.order }
    }

    func ingest(interactions requests: [InteractionRequest], from: String) {
        guard !from.isEmpty else { return }
        var bucket = interactionsByFrom[from] ?? [:]
        for request in requests where !request.id.isEmpty { bucket[request.id] = request }
        interactionsByFrom[from] = bucket
    }
    func ingest(updates incoming: [SessionUpdate], from: String) {
        guard !from.isEmpty else { return }
        var bucket = updatesByFrom[from] ?? [:]
        for update in incoming where !update.id.isEmpty { bucket[update.id] = update }
        updatesByFrom[from] = bucket
    }

    /// Mark an interaction dismissed for its producer (persisted) — it and anything older
    /// stop being surfaced.
    func dismiss(id: String, from: String) {
        guard !id.isEmpty, !from.isEmpty else { return }
        var ids = dismissedByFrom[from] ?? []
        ids.insert(id)
        dismissedByFrom[from] = ids
        let dict = dismissedByFrom.mapValues { Array($0.suffix(500)) }
        UserDefaults.standard.set(dict, forKey: Self.dismissedKey)
    }

    /// Poll the interaction service for each active producer, merging deduped (latest wins).
    func poll(producers: Set<String>) async {
        guard !producers.isEmpty else { return }
        let client = InteractionsClient(endpoint: endpoint)
        for from in producers {
            ingest(interactions: await client.activeRequests(from: from), from: from)
            ingest(updates: await client.updates(from: from, limit: 100), from: from)
        }
    }
}
