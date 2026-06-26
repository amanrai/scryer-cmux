import Foundation

/// How to reach the JEPM PM system **directly** (not via the gateway proxy).
///
/// The Kanbaner board talks to PM's REST API at `${httpBase}/api/...` — the same contract
/// the loom web client uses through its `/api` Vite proxy (no path rewrite). PM is a single
/// shared service on the tailnet, so its host is independent of any gateway/backend.
public struct PmEndpoint: Hashable, Codable, Sendable {
    public let httpBase: URL   // e.g. http://100.105.192.98:43210

    public init?(rawInput: String) {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Accept "host", "host:port", "http://host:port", "https://host:port".
        var components: URLComponents
        if trimmed.contains("://"), let parsed = URLComponents(string: trimmed) {
            components = parsed
        } else if let parsed = URLComponents(string: "http://\(trimmed)") {
            components = parsed
        } else {
            return nil
        }

        if components.scheme == nil { components.scheme = "http" }
        if components.port == nil { components.port = PmEndpoint.defaultPort }
        components.path = ""
        components.query = nil
        components.fragment = nil

        guard let http = components.url else { return nil }
        self.httpBase = http
    }

    public static let defaultPort = 43210
    /// Known tailnet address of the shared PM system (override in Settings).
    public static let defaultHost = "100.105.192.98:43210"
    public static var `default`: PmEndpoint { PmEndpoint(rawInput: defaultHost)! }

    public var displayHost: String {
        let host = httpBase.host ?? httpBase.absoluteString
        if let port = httpBase.port { return "\(host):\(port)" }
        return host
    }

    /// `${base}/api/<path>` for a path with no query string (UUID path segments are safe).
    func apiURL(_ path: String) -> URL {
        let normalized = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return httpBase.appendingPathComponent("api").appendingPathComponent(normalized)
    }

    /// `${base}/api/<path>?<query>` — use when a query string is needed.
    func apiURL(_ path: String, query: [URLQueryItem]) -> URL {
        var components = URLComponents(url: apiURL(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        return components.url!
    }
}
