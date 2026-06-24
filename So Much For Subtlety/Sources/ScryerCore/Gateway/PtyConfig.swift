import Foundation

/// A machine-local PTY backend's gateway-registration config. Mirrors
/// `server-pty/gateway-registration.mjs` / `gateway-ui` `PtyGatewayConfig`.
public struct PtyConfig: Codable, Hashable, Sendable {
    public var gatewayUrl: String
    public var machineId: String
    public var machineName: String
    public var publicUrl: String
    public var heartbeatEnabled: Bool
    public var heartbeatMs: Double

    public init(gatewayUrl: String, machineId: String, machineName: String, publicUrl: String, heartbeatEnabled: Bool, heartbeatMs: Double) {
        self.gatewayUrl = gatewayUrl
        self.machineId = machineId
        self.machineName = machineName
        self.publicUrl = publicUrl
        self.heartbeatEnabled = heartbeatEnabled
        self.heartbeatMs = heartbeatMs
    }
}

public struct PtyConfigStatus: Codable, Hashable, Sendable {
    public var registered: Bool?
    public var lastSuccessAt: String?
    public var lastAttemptAt: String?
    public var lastError: String?
}

public struct PtyConfigPayload: Codable, Sendable {
    public var config: PtyConfig
    public var status: PtyConfigStatus?
}
