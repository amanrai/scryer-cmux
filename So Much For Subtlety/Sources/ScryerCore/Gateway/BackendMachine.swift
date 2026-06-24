import Foundation

/// A PTY machine registered with the gateway. Mirrors `gateway-ui/src/types.ts`.
public struct BackendMachine: Identifiable, Codable, Hashable, Sendable {
    public enum Status: String, Codable, Sendable {
        case online, stale, offline, unknown
    }

    public let id: String
    public let label: String
    public let kind: String
    public var baseUrl: String?
    public var transport: String?
    public var capabilities: [String]?
    public var status: Status?
    public var lastSeenAt: String?
    public var registeredAt: String?
    public var source: String?

    public init(
        id: String,
        label: String,
        kind: String,
        baseUrl: String? = nil,
        transport: String? = nil,
        capabilities: [String]? = nil,
        status: Status? = nil,
        lastSeenAt: String? = nil,
        registeredAt: String? = nil,
        source: String? = nil
    ) {
        self.id = id
        self.label = label
        self.kind = kind
        self.baseUrl = baseUrl
        self.transport = transport
        self.capabilities = capabilities
        self.status = status
        self.lastSeenAt = lastSeenAt
        self.registeredAt = registeredAt
        self.source = source
    }

    /// A PTY backend that is currently reachable — what the picker offers.
    public var isSelectable: Bool {
        kind == "pty" && status == .online
    }

    public func decodingStatusFallback() -> Status {
        status ?? .unknown
    }
}

extension BackendMachine.Status {
    public var isOnline: Bool { self == .online }
}
