import Foundation
import AppKit
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

    // Scryer state surfaced from the WS frames.
    private(set) var hasProducer = false
    private(set) var pendingInteraction: InteractionRequest?
    private(set) var updates: [SessionUpdate] = []
    private(set) var unreadUpdates = 0

    private let engine: GhosttyVTEngine
    private let session: TerminalSession

    init?(endpoint: GatewayEndpoint, backendId: String?, paneId: String, fontSize: CGFloat) {
        guard let view = TerminalMetalView(fontSize: fontSize) else { return nil }
        self.paneId = paneId
        self.metalView = view
        engine = GhosttyVTEngine(cols: 80, rows: 24)
        session = TerminalSession(endpoint: endpoint, backendId: backendId, paneId: paneId)
        engine.delegate = self
        session.delegate = self

        view.onKeyDown = { [weak self] event in self?.handleKey(event) }
        view.onGridSizeChange = { [weak self] cols, rows in self?.handleResize(cols: cols, rows: rows) }
        view.onScroll = { [weak self] deltaRows in self?.engine.scrollViewport(deltaRows: deltaRows) }
        view.onPaste = { [weak self] text in self?.handlePaste(text) }

        session.connect()
        pushSnapshot()
    }

    func disconnect() {
        session.disconnect()
    }

    func setFontSize(_ size: CGFloat) {
        metalView.updateFontSize(size)
        pushSnapshot()
    }

    /// Send raw text/control bytes to the PTY (used by quick inputs).
    func send(_ text: String) {
        session.send(.input(data: text, paneId: session.paneId))
        metalView.window?.makeFirstResponder(metalView)
    }

    private func handleKey(_ event: NSEvent) {
        guard let key = GhosttyKeymap.keyEvent(from: event) else { return }
        engine.sendKey(key)
    }

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
        Task { @MainActor in self.engine.feed(bytes) }
    }

    nonisolated func terminalSession(_ session: TerminalSession, didChangeState state: TerminalSession.State) {
        Task { @MainActor in self.connectionState = state }
    }

    nonisolated func terminalSession(_ session: TerminalSession, didReceiveInteraction request: InteractionRequest) {
        Task { @MainActor in self.pendingInteraction = request }
    }

    nonisolated func terminalSession(_ session: TerminalSession, didClearInteraction requestId: String) {
        Task { @MainActor in if self.pendingInteraction?.id == requestId { self.pendingInteraction = nil } }
    }

    nonisolated func terminalSession(_ session: TerminalSession, didDetectProducer from: String) {
        Task { @MainActor in self.hasProducer = true }
    }

    nonisolated func terminalSession(_ session: TerminalSession, didReceiveUpdates updates: [SessionUpdate]) {
        Task { @MainActor in self.mergeUpdates(updates) }
    }

    // MARK: Scryer actions

    func respondToInteraction(_ response: [String: Any]) {
        guard let interaction = pendingInteraction else { return }
        session.sendInteractionResponse(requestId: interaction.id, from: interaction.from, response: response)
        pendingInteraction = nil
    }

    func dismissInteraction() { pendingInteraction = nil }
    func markUpdatesRead() { unreadUpdates = 0 }

    private func mergeUpdates(_ incoming: [SessionUpdate]) {
        var byId = Dictionary(updates.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        var newCount = 0
        for update in incoming {
            if byId[update.id] == nil { newCount += 1 }
            byId[update.id] = update
        }
        updates = byId.values.sorted { ($0.receivedAt ?? "") < ($1.receivedAt ?? "") }.suffix(100).map { $0 }
        unreadUpdates += newCount
    }
}

/// Caches live `TerminalController`s by paneId so they persist across view churn.
/// Owned by `AttachedView`; torn down when leaving the backend. Deliberately not
/// `@Observable` — views observe the controller, and get-or-create runs during body
/// evaluation, so mutating it must not trigger a view update.
@MainActor
final class TerminalStore {
    private var controllers: [String: TerminalController] = [:]

    func controller(paneId: String, endpoint: GatewayEndpoint, backendId: String?, fontSize: CGFloat) -> TerminalController? {
        if let existing = controllers[paneId] { return existing }
        guard let created = TerminalController(endpoint: endpoint, backendId: backendId, paneId: paneId, fontSize: fontSize) else { return nil }
        controllers[paneId] = created
        return created
    }

    func setFontSize(_ size: CGFloat) {
        for controller in controllers.values { controller.setFontSize(size) }
    }

    /// Returns an already-live controller without creating one.
    func existing(paneId: String) -> TerminalController? { controllers[paneId] }

    func close(paneId: String) {
        controllers[paneId]?.disconnect()
        controllers[paneId] = nil
    }

    func teardown() {
        for controller in controllers.values { controller.disconnect() }
        controllers.removeAll()
    }
}
