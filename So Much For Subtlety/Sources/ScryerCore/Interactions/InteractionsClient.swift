import Foundation

/// How to reach the Scryer **interaction service** directly (tailnet), independent of the
/// gateway — the same service the pty-server polls (`SCRYER_INTERACTIONS_URL`,
/// default `100.105.192.98:43217`). Requests/updates are keyed by a producer `from`.
public struct InteractionsEndpoint: Hashable, Codable, Sendable {
    public let httpBase: URL

    public init?(rawInput: String) {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var components: URLComponents
        if trimmed.contains("://"), let parsed = URLComponents(string: trimmed) {
            components = parsed
        } else if let parsed = URLComponents(string: "http://\(trimmed)") {
            components = parsed
        } else {
            return nil
        }
        if components.scheme == nil { components.scheme = "http" }
        if components.port == nil { components.port = InteractionsEndpoint.defaultPort }
        components.path = ""; components.query = nil; components.fragment = nil
        guard let http = components.url else { return nil }
        self.httpBase = http
    }

    public static let defaultPort = 43217
    public static let defaultHost = "100.105.192.98:43217"
    public static var `default`: InteractionsEndpoint { InteractionsEndpoint(rawInput: defaultHost)! }

    public var displayHost: String {
        let host = httpBase.host ?? httpBase.absoluteString
        if let port = httpBase.port { return "\(host):\(port)" }
        return host
    }

    func apiURL(_ path: String, query: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: httpBase.appendingPathComponent("api").appendingPathComponent(path),
                                       resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        return components.url!
    }
}

/// Read-side client for the interaction service. Tolerant: any failure yields an empty list,
/// so polling never throws into the app.
public struct InteractionsClient: Sendable {
    public let endpoint: InteractionsEndpoint
    private let session: URLSession

    public init(endpoint: InteractionsEndpoint, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    private struct ActiveEnvelope: Decodable { let requests: [InteractionRequest]? }
    private struct UpdatesEnvelope: Decodable { let updates: [SessionUpdate]? }

    /// `GET /api/requests/active?from=<producer>` — active interaction requests for a producer.
    public func activeRequests(from: String) async -> [InteractionRequest] {
        guard !from.isEmpty else { return [] }
        let url = endpoint.apiURL("requests/active", query: [URLQueryItem(name: "from", value: from)])
        guard let (data, response) = try? await session.data(from: url) else { return [] }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return [] }
        return (try? JSONDecoder().decode(ActiveEnvelope.self, from: data))?.requests ?? []
    }

    /// `GET /api/updates?from=<producer>&since=&limit=` — semantic agent updates for a producer.
    public func updates(from: String, since: String? = nil, limit: Int = 100) async -> [SessionUpdate] {
        guard !from.isEmpty else { return [] }
        var query = [URLQueryItem(name: "from", value: from), URLQueryItem(name: "limit", value: String(limit))]
        if let since, !since.isEmpty { query.append(URLQueryItem(name: "since", value: since)) }
        let url = endpoint.apiURL("updates", query: query)
        guard let (data, response) = try? await session.data(from: url) else { return [] }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return [] }
        return (try? JSONDecoder().decode(UpdatesEnvelope.self, from: data))?.updates ?? []
    }
}
