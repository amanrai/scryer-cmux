import Foundation

/// How to reach the gateway, and how to build per-backend HTTP/WS URLs.
///
/// The browser client derives this from `window.location`; a native app needs an
/// explicit origin. We normalize a user-entered host/URL into HTTP + WS bases and
/// then mirror `gateway-ui/src/constants.ts` for the backend-scoped routes.
public struct GatewayEndpoint: Hashable, Codable, Sendable {
    public let httpBase: URL   // e.g. http://machine.tailnet.ts.net:43223
    public let wsBase: URL     // e.g. ws://machine.tailnet.ts.net:43223

    public init?(rawInput: String) {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Accept "host", "host:port", "http://host:port", "https://host:port".
        var components = URLComponents()
        if trimmed.contains("://"), let parsed = URLComponents(string: trimmed) {
            components = parsed
        } else if let parsed = URLComponents(string: "http://\(trimmed)") {
            components = parsed
        } else {
            return nil
        }

        let scheme = components.scheme ?? "http"
        components.scheme = scheme
        if components.port == nil { components.port = GatewayEndpoint.defaultPort }
        components.path = ""
        components.query = nil
        components.fragment = nil

        guard let http = components.url else { return nil }

        var wsComponents = components
        wsComponents.scheme = (scheme == "https") ? "wss" : "ws"
        guard let ws = wsComponents.url else { return nil }

        self.httpBase = http
        self.wsBase = ws
    }

    public static let defaultPort = 43223

    public var displayHost: String {
        let host = httpBase.host ?? httpBase.absoluteString
        if let port = httpBase.port, port != GatewayEndpoint.defaultPort {
            return "\(host):\(port)"
        }
        return host
    }

    /// `/api/backends`
    public func backendsURL() -> URL {
        httpBase.appendingPathComponent("api").appendingPathComponent("backends")
    }

    /// Backend-scoped HTTP path, e.g. `/api/backends/:id/state`. A nil `backendId`
    /// falls through to the gateway compatibility routes (`/api/...`).
    public func backendHTTP(_ backendId: String?, _ path: String) -> URL {
        let normalized = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard let backendId, !backendId.isEmpty else {
            return httpBase.appendingPathComponent("api").appendingPathComponent(normalized)
        }
        return httpBase
            .appendingPathComponent("api")
            .appendingPathComponent("backends")
            .appendingPathComponent(backendId)
            .appendingPathComponent(normalized)
    }

    /// `WS /api/backends/:id/terminal?paneId=…`
    public func terminalWS(_ backendId: String?, paneId: String) -> URL {
        var components = URLComponents(url: wsBase, resolvingAgainstBaseURL: false)!
        if let backendId, !backendId.isEmpty {
            components.path = "/api/backends/\(backendId)/terminal"
        } else {
            components.path = "/api/terminal"
        }
        components.queryItems = [URLQueryItem(name: "paneId", value: paneId)]
        return components.url!
    }
}
