import Foundation
#if os(macOS)
import AppKit
#endif
import Observation
import ScryerCore
import ScryerGhostty
import ScryerRender

/// Wires one PTY pane together: WebSocket session ↔ Ghostty engine ↔ Metal view.
///
/// The controller **owns** its `TerminalMetalView` and stays connected for its whole
/// lifetime. It is cached by `TerminalStore`, so toggling the sidebar or switching
/// panes just reparents the existing live view — no reconnect, no replay.
///
/// - session output → `engine.feed` → snapshot → `metalView.apply`
/// - keystrokes → `engine.sendKey` → encoded bytes → session `input`
/// - terminal query responses → `engine` WRITE_PTY → session `input`  (TUIs need this)
/// - view resize → `engine.resize` + session `resize`
@MainActor
@Observable
final class TerminalController: TerminalSessionDelegate, @MainActor TerminalEngineDelegate {
    let paneId: String
    let metalView: TerminalMetalView
    private(set) var title: String?
    private(set) var connectionState: TerminalSession.State = .connecting
    /// True only when the live PTY socket is up — gates input UI (keyboard/mic) so we never
    /// type into a dead connection after the app is suspended.
    var isConnected: Bool { connectionState == .connected }

    // Scryer state surfaced from the WS frames. Mirrors gateway-ui/TerminalPane.tsx.
    private(set) var hasProducer = false
    /// The producer `from` this pane is listening to (nil until a marker is detected) — used
    /// by the app-wide interaction pull to know which producers to poll.
    var producerFrom: String? { currentProducerFrom }
    private(set) var pendingInteraction: InteractionRequest?
    /// Bumped on every `interaction` frame so the UI can auto-present per-frame
    /// (not only when the request id changes), matching gateway-ui.
    private(set) var interactionEpoch = 0
    private(set) var updates: [SessionUpdate] = []
    private(set) var unreadUpdates = 0
    /// Set by the view while the activity panel is open; suppresses unread counting.
    var activityVisible = false

    // Dedup, mirroring gateway-ui's seen/dismissed Sets.
    private var seenUpdateIds: Set<String> = []
    private var dismissedUpdateIds: Set<String> = []
    /// Interaction request ids the user dismissed or responded to — never re-present
    /// these (a re-pushed/replayed same id is ignored). Closing the modal does NOT
    /// add to this set; only an explicit dismiss or a response does.
    private var dismissedInteractionIds: Set<String> = []
    /// The producer `from` we're currently listening to. Each pi session emits a new
    /// one; when it changes we treat it as a fresh session and forget old state.
    private var currentProducerFrom: String?
    /// Recency high-water mark: the newest interaction we've shown/engaged with. Older
    /// arrivals are ignored.
    private var interactionWatermark: InteractionOrder?
    /// Retained terminal text (capped like the server's replay, 250 KB) so we can
    /// re-scan for the producer marker on demand — e.g. when this pane becomes active.
    private var producerBuffer = ""
    private static let producerBufferCap = 250_000

    private let engine: GhosttyVTEngine
    private let session: TerminalSession
    /// Periodically re-evaluates listening from terminal state, so it stays current
    /// even with no new output (e.g. the marker scrolled out, or pi exited).
    private var producerScanTimer: Timer?

    init?(endpoint: GatewayEndpoint, backendId: String?, paneId: String, fontSize: CGFloat, theme: TerminalTheme) {
        guard let view = TerminalMetalView(fontSize: fontSize) else { return nil }
        self.paneId = paneId
        self.metalView = view
        engine = GhosttyVTEngine(cols: 80, rows: 24, theme: theme)
        session = TerminalSession(endpoint: endpoint, backendId: backendId, paneId: paneId)
        engine.delegate = self
        session.delegate = self

        #if os(macOS)
        view.onKeyDown = { [weak self] event in self?.handleKey(event) }
        #elseif os(iOS)
        view.onText = { [weak self] text, mods in self?.handleText(text, modifiers: mods) }
        view.onSpecialKey = { [weak self] key, mods in self?.handleSpecialKey(key, modifiers: mods) }
        #endif
        view.onGridSizeChange = { [weak self] cols, rows in self?.handleResize(cols: cols, rows: rows) }
        view.onScroll = { [weak self] deltaRows in self?.engine.scrollViewport(deltaRows: deltaRows) }
        view.onPaste = { [weak self] text in self?.handlePaste(text) }

        session.connect()
        pushSnapshot()

        producerScanTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshProducerState() }
        }
    }

    func disconnect() {
        producerScanTimer?.invalidate()
        producerScanTimer = nil
        session.disconnect()
    }

    /// Re-establish the PTY connection and re-scan listening state. Backs the refresh
    /// button — handy after the app wakes from suspend with a dead socket.
    func reconnect() {
        session.reconnect()
        pushSnapshot()
        refreshProducerState()
    }

    /// One tick of the connection watcher (polled ~1s by the view): ping while nominally
    /// connected to catch a silently dead socket, and reconnect once it's actually closed.
    /// No-op while a connect is already in flight.
    func tickConnection() {
        switch connectionState {
        case .connected:  session.ping()
        case .closed:     reconnect()
        case .connecting: break
        }
    }

    func setFontSize(_ size: CGFloat) {
        metalView.updateFontSize(size)
        pushSnapshot()
    }

    func setTheme(_ theme: TerminalTheme) {
        engine.setTheme(theme)
    }

    /// Send raw text/control bytes to the PTY (used by quick inputs).
    func send(_ text: String) {
        session.send(.input(data: text, paneId: session.paneId))
        #if os(macOS)
        metalView.window?.makeFirstResponder(metalView)
        #elseif os(iOS)
        metalView.becomeFirstResponder()
        #endif
    }

    /// Inject typed text through the engine encoder (on-screen / floating keyboard).
    func type(_ text: String, modifiers: KeyModifiers = []) {
        engine.sendKey(GhosttyKeymap.keyEvent(text: text, modifiers: modifiers))
    }

    /// Inject a special key through the engine encoder (on-screen / floating keyboard).
    func type(_ key: TerminalKey, modifiers: KeyModifiers = []) {
        engine.sendKey(GhosttyKeymap.keyEvent(special: key, modifiers: modifiers))
    }

    #if os(macOS)
    private func handleKey(_ event: NSEvent) {
        let flags = event.modifierFlags
        if flags.contains(.control), !flags.contains(.command), !flags.contains(.option),
           (event.charactersIgnoringModifiers?.lowercased() == "c" || event.keyCode == 0x08) {
            session.sendInputBytes([0x03])
            return
        }

        guard let key = GhosttyKeymap.keyEvent(from: event) else { return }
        engine.sendKey(key)
    }
    #elseif os(iOS)
    private func handleText(_ text: String, modifiers: KeyModifiers) { type(text, modifiers: modifiers) }
    private func handleSpecialKey(_ key: TerminalKey, modifiers: KeyModifiers) { type(key, modifiers: modifiers) }
    #endif

    private func handlePaste(_ text: String) {
        // Only wrap in paste markers when the program enabled bracketed paste,
        // otherwise the \e[200~ markers leak into the input as literal text.
        if engine.bracketedPasteEnabled() {
            session.send(.bracketedPaste(text, paneId: session.paneId))
        } else {
            session.send(.input(data: text, paneId: session.paneId))
        }
    }

    private func handleResize(cols: Int, rows: Int) {
        engine.resize(cols: cols, rows: rows, cellWidth: Double(metalView.cellWidth), cellHeight: Double(metalView.cellHeight))
        session.resize(cols: cols, rows: rows)
    }

    private func pushSnapshot() {
        metalView.apply(engine.snapshot())
    }

    // MARK: TerminalEngineDelegate

    func terminalEngine(_ engine: TerminalEngine, writeToPTY bytes: [UInt8]) {
        session.sendInputBytes(bytes)
    }

    func terminalEngine(_ engine: TerminalEngine, didChangeTitle title: String?) {
        self.title = title
    }

    func terminalEngineNeedsRedraw(_ engine: TerminalEngine) {
        pushSnapshot()
    }

    // MARK: TerminalSessionDelegate

    nonisolated func terminalSession(_ session: TerminalSession, didReceiveOutput bytes: [UInt8], isReplay: Bool) {
        Task { @MainActor in
            self.engine.feed(bytes)
            self.ingestForProducer(String(decoding: bytes, as: UTF8.self))
        }
    }

    nonisolated func terminalSession(_ session: TerminalSession, didChangeState state: TerminalSession.State) {
        Task { @MainActor in self.connectionState = state }
    }

    nonisolated func terminalSession(_ session: TerminalSession, didReceiveInteraction request: InteractionRequest) {
        Task { @MainActor in self.handleInteraction(request) }
    }

    /// Only the most-recent interaction matters. Once you've engaged with one, anything
    /// older is dead even if the server still relays it — relevance is the client's call.
    private func handleInteraction(_ request: InteractionRequest) {
        // Receiving an interaction means we're engaged with its producer → listening.
        adoptProducer(request.from)
        // Answered or explicitly dismissed → never again.
        guard !dismissedInteractionIds.contains(request.id) else { return }
        // Older than the newest interaction we've already engaged with → pointless.
        if let mark = interactionWatermark, request.order < mark, request.id != pendingInteraction?.id {
            return
        }
        // A newer interaction supersedes any pending older one.
        if let pending = pendingInteraction, pending.id != request.id {
            dismissedInteractionIds.insert(pending.id)
        }
        pendingInteraction = request
        if interactionWatermark == nil || request.order > interactionWatermark! {
            interactionWatermark = request.order
        }
        interactionEpoch += 1   // fires the per-frame auto-present
    }

    nonisolated func terminalSession(_ session: TerminalSession, didClearInteraction requestId: String) {
        Task { @MainActor in if self.pendingInteraction?.id == requestId { self.pendingInteraction = nil } }
    }

    nonisolated func terminalSession(_ session: TerminalSession, didDetectProducer from: String) {
        // The server's live producer frame is a fresh marker detection — honor it so
        // listening turns on even if our own text scan misses the marker.
        Task { @MainActor in self.adoptProducer(from) }
    }

    /// Adopt the producer for the current pi session. A new `from` means a new pi
    /// session, so we forget everything from the previous one — old dismissals,
    /// seen ids, pending request, and the activity feed all reset.
    private func adoptProducer(_ from: String) {
        guard !from.isEmpty else { return }
        if from != currentProducerFrom {
            currentProducerFrom = from
            dismissedInteractionIds = Self.loadDismissed(for: from)   // durable per pi session
            dismissedUpdateIds.removeAll()
            seenUpdateIds.removeAll()
            pendingInteraction = nil
            interactionWatermark = nil
            updates.removeAll()
            unreadUpdates = 0
        }
        hasProducer = true
    }

    /// Append terminal output to the retained buffer and look for the producer marker.
    /// Until we've locked onto a producer we scan the whole buffer so a marker can't be
    /// missed (chunk boundaries, ANSI padding, wherever it landed); once listening, a
    /// tail window is enough to notice a *new* session's marker.
    private func ingestForProducer(_ text: String) {
        producerBuffer += text
        if producerBuffer.count > Self.producerBufferCap {
            producerBuffer = String(producerBuffer.suffix(Self.producerBufferCap))
        }
        let haystack = hasProducer ? String(producerBuffer.suffix(text.count + 4096)) : producerBuffer
        if let from = ProducerMarker.latestFrom(in: haystack) { adoptProducer(from) }
    }

    /// Re-scan the retained terminal state for the producer marker. Turns listening ON
    /// when present. We deliberately don't clear it when absent: pi's redraws can push
    /// the marker out of the buffer while pi is still running, so absence isn't proof
    /// pi exited — that needs a teardown signal (deferred).
    func refreshProducerState() {
        if let from = ProducerMarker.latestFrom(in: producerBuffer) { adoptProducer(from) }
    }

    nonisolated func terminalSession(_ session: TerminalSession, didReceiveUpdates updates: [SessionUpdate]) {
        Task { @MainActor in self.mergeUpdates(updates) }
    }

    // MARK: Scryer actions

    func respondToInteraction(_ response: [String: Any]) {
        guard let interaction = pendingInteraction else { return }
        session.sendInteractionResponse(requestId: interaction.id, from: interaction.from, response: response)
        dismissedInteractionIds.insert(interaction.id)   // answered → never re-present
        pendingInteraction = nil
        persistDismissed()
    }

    /// Respond to a specific request (from the app-wide store flow). The response goes back
    /// over the pane's WS (the pty-server forwards it to the interaction service).
    func respond(to request: InteractionRequest, response: [String: Any]) {
        session.sendInteractionResponse(requestId: request.id, from: request.from, response: response)
    }

    /// Explicit dismiss (not the same as closing the modal): the request is gone for good.
    func dismissInteraction() {
        if let id = pendingInteraction?.id { dismissedInteractionIds.insert(id) }
        pendingInteraction = nil
        persistDismissed()
    }

    // Dismissed interactions persist per producer (pi session), so a dismissed-but-still-
    // active request doesn't re-appear after relaunch within the same session.
    private static let dismissedDefaultsKey = "smfs.dismissedInteractions"   // [from: [id]]
    private static func loadDismissed(for from: String) -> Set<String> {
        let dict = UserDefaults.standard.dictionary(forKey: dismissedDefaultsKey) as? [String: [String]] ?? [:]
        return Set(dict[from] ?? [])
    }
    private func persistDismissed() {
        guard let from = currentProducerFrom else { return }
        var dict = UserDefaults.standard.dictionary(forKey: Self.dismissedDefaultsKey) as? [String: [String]] ?? [:]
        dict[from] = Array(dismissedInteractionIds.suffix(500))
        UserDefaults.standard.set(dict, forKey: Self.dismissedDefaultsKey)
    }
    func markUpdatesRead() { unreadUpdates = 0 }

    /// Dismiss a single update so it is filtered out and never re-added (gateway-ui parity).
    func dismissUpdate(_ id: String) {
        dismissedUpdateIds.insert(id)
        updates.removeAll { $0.id == id }
        unreadUpdates = 0
    }

    func dismissAllUpdates() {
        for update in updates { dismissedUpdateIds.insert(update.id) }
        updates.removeAll()
        unreadUpdates = 0
    }

    private func mergeUpdates(_ incoming: [SessionUpdate]) {
        // Drop anything the user dismissed; count only genuinely-unseen updates.
        let live = incoming.filter { !$0.id.isEmpty && !dismissedUpdateIds.contains($0.id) }
        let newCount = live.filter { !seenUpdateIds.contains($0.id) }.count
        for update in live { seenUpdateIds.insert(update.id) }

        var byId = Dictionary(updates.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        for update in live { byId[update.id] = update }
        updates = byId.values
            .sorted { ($0.receivedAt ?? "", $0.id) < ($1.receivedAt ?? "", $1.id) }
            .suffix(100)
            .map { $0 }

        // Only bump unread when the activity panel isn't already open.
        if !activityVisible, newCount > 0 { unreadUpdates += newCount }
    }
}

/// Caches live `TerminalController`s by paneId so they persist across view churn.
/// Owned by `AttachedView`; torn down when leaving the backend. Deliberately not
/// `@Observable` — views observe the controller, and get-or-create runs during body
/// evaluation, so mutating it must not trigger a view update.
@MainActor
final class TerminalStore {
    private var controllers: [String: TerminalController] = [:]

    func controller(paneId: String, endpoint: GatewayEndpoint, backendId: String?, fontSize: CGFloat, theme: TerminalTheme) -> TerminalController? {
        if let existing = controllers[paneId] { return existing }
        guard let created = TerminalController(endpoint: endpoint, backendId: backendId, paneId: paneId, fontSize: fontSize, theme: theme) else { return nil }
        controllers[paneId] = created
        return created
    }

    func setFontSize(_ size: CGFloat) {
        for controller in controllers.values { controller.setFontSize(size) }
    }

    func setTheme(_ theme: TerminalTheme) {
        for controller in controllers.values { controller.setTheme(theme) }
    }

    /// Returns an already-live controller without creating one.
    func existing(paneId: String) -> TerminalController? { controllers[paneId] }

    /// Producers across all live panes — the set the interaction pull polls.
    var activeProducers: Set<String> { Set(controllers.values.compactMap { $0.producerFrom }) }

    func close(paneId: String) {
        controllers[paneId]?.disconnect()
        controllers[paneId] = nil
    }

    func teardown() {
        for controller in controllers.values { controller.disconnect() }
        controllers.removeAll()
    }
}
