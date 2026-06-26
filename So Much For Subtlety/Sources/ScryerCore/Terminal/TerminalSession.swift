import Foundation

/// Events surfaced from a live terminal WebSocket. Delivered on the main actor.
public protocol TerminalSessionDelegate: AnyObject {
    func terminalSession(_ session: TerminalSession, didReceiveOutput bytes: [UInt8], isReplay: Bool)
    func terminalSession(_ session: TerminalSession, didChangeState state: TerminalSession.State)
    func terminalSession(_ session: TerminalSession, didReceiveStatus status: TerminalProtocol.Inbound.Status)
    func terminalSession(_ session: TerminalSession, didReceiveInteraction request: InteractionRequest)
    func terminalSession(_ session: TerminalSession, didClearInteraction requestId: String)
    func terminalSession(_ session: TerminalSession, didDetectProducer from: String)
    func terminalSession(_ session: TerminalSession, didReceiveUpdates updates: [SessionUpdate])
}

public extension TerminalSessionDelegate {
    func terminalSession(_ session: TerminalSession, didReceiveStatus status: TerminalProtocol.Inbound.Status) {}
    func terminalSession(_ session: TerminalSession, didReceiveInteraction request: InteractionRequest) {}
    func terminalSession(_ session: TerminalSession, didClearInteraction requestId: String) {}
    func terminalSession(_ session: TerminalSession, didDetectProducer from: String) {}
    func terminalSession(_ session: TerminalSession, didReceiveUpdates updates: [SessionUpdate]) {}
}

/// One WebSocket attachment to a PTY pane, keyed by `paneId`. Speaks
/// `TerminalProtocol`. Reattach to the same `paneId` to resume a live session.
@MainActor
public final class TerminalSession: NSObject {
    public enum State: Equatable {
        case connecting
        case connected
        case closed(reason: String?)
    }

    public let paneId: String
    public let backendId: String?
    public private(set) var state: State = .connecting {
        didSet { delegate?.terminalSession(self, didChangeState: state) }
    }
    public weak var delegate: TerminalSessionDelegate?

    private let url: URL
    private var task: URLSessionWebSocketTask?
    private lazy var urlSession = URLSession(configuration: .default)

    public init(endpoint: GatewayEndpoint, backendId: String?, paneId: String) {
        self.url = endpoint.terminalWS(backendId, paneId: paneId)
        self.backendId = backendId
        self.paneId = paneId
        super.init()
    }

    public func connect() {
        guard task == nil else { return }
        state = .connecting
        let task = urlSession.webSocketTask(with: url)
        self.task = task
        task.resume()
        receiveLoop()
    }

    public func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        state = .closed(reason: nil)
    }

    /// Force a fresh connection. Safe whether or not the current socket is alive — used by
    /// the refresh control when the app resumes from suspend and the socket has died silently.
    public func reconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        connect()
    }

    /// Liveness probe. On a silently-dead socket (e.g. after the app was suspended) the pong
    /// handler returns an error; we surface it as a failure so a watcher can reconnect. On a
    /// live socket it's a cheap no-op.
    public func ping() {
        guard let task else { return }
        task.sendPing { [weak self] error in
            guard let error else { return }
            Task { @MainActor in self?.fail(error.localizedDescription) }
        }
    }

    // MARK: Sending

    public func send(_ message: TerminalProtocol.Outbound) {
        guard let task else { return }
        let data = message.jsonData()
        let text = String(decoding: data, as: UTF8.self)
        task.send(.string(text)) { [weak self] error in
            guard let error else { return }
            Task { @MainActor in self?.fail(error.localizedDescription) }
        }
    }

    /// Convenience for the engine's write-back channel (keystrokes + query responses).
    public func sendInputBytes(_ bytes: [UInt8]) {
        send(.input(data: String(decoding: bytes, as: UTF8.self), paneId: paneId))
    }

    public func resize(cols: Int, rows: Int) {
        send(.resize(cols: cols, rows: rows, paneId: paneId))
    }

    public func sendInteractionResponse(requestId: String, from: String, response: [String: Any]) {
        send(.interactionResponse(requestId: requestId, from: from, response: response, paneId: paneId))
    }

    // MARK: Receiving

    private func receiveLoop() {
        task?.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .failure(let error):
                    self.fail(error.localizedDescription)
                case .success(let message):
                    self.handle(message)
                    self.receiveLoop()
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        if case .connecting = state { state = .connected }
        let data: Data
        switch message {
        case .string(let string): data = Data(string.utf8)
        case .data(let raw): data = raw
        @unknown default: return
        }
        guard let inbound = TerminalProtocol.Inbound.decode(data) else { return }
        switch inbound {
        case let .output(bytes, isReplay):
            delegate?.terminalSession(self, didReceiveOutput: bytes, isReplay: isReplay)
        case let .status(status):
            delegate?.terminalSession(self, didReceiveStatus: status)
            if let from = status.producerFrom { delegate?.terminalSession(self, didDetectProducer: from) }
        case let .scryer(type, frame):
            handleScryer(type: type, data: frame)
        case .unknown:
            break
        }
    }

    private func handleScryer(type: String, data: Data) {
        switch type {
        case "interaction":
            if let request = ScryerFrame.interaction(from: data) { delegate?.terminalSession(self, didReceiveInteraction: request) }
        case "interaction_clear":
            if let requestId = ScryerFrame.clearedRequestId(from: data) { delegate?.terminalSession(self, didClearInteraction: requestId) }
        case "interaction_producer":
            if let from = ScryerFrame.producer(from: data) { delegate?.terminalSession(self, didDetectProducer: from) }
        case "session_updates":
            delegate?.terminalSession(self, didReceiveUpdates: ScryerFrame.updates(from: data))
        default:
            break
        }
    }

    private func fail(_ reason: String) {
        guard task != nil else { return }
        task = nil
        state = .closed(reason: reason)
    }
}
