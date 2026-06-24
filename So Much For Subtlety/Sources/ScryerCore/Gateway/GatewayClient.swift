import Foundation

public enum GatewayError: Error, LocalizedError {
    case badStatus(Int)
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .badStatus(let code): return "Gateway returned HTTP \(code)"
        case .decoding(let detail): return "Could not decode gateway response: \(detail)"
        }
    }
}

/// Read-side gateway client: list backends and load workspace state.
/// State persistence and session kill land alongside terminal work.
public struct GatewayClient: Sendable {
    public let endpoint: GatewayEndpoint
    private let session: URLSession

    public init(endpoint: GatewayEndpoint, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    private struct BackendsEnvelope: Decodable {
        let backends: [BackendMachine]
    }

    /// `GET /api/backends`
    public func listBackends() async throws -> [BackendMachine] {
        let (data, response) = try await session.data(from: endpoint.backendsURL())
        try Self.expectOK(response)
        do {
            return try JSONDecoder().decode(BackendsEnvelope.self, from: data).backends
        } catch {
            throw GatewayError.decoding(String(describing: error))
        }
    }

    /// Backends the picker should offer: reachable PTY machines.
    public func listSelectableBackends() async throws -> [BackendMachine] {
        try await listBackends().filter(\.isSelectable)
    }

    /// `GET /api/backends/:id/state`
    public func loadState(backendId: String?) async throws -> AppState {
        let url = endpoint.backendHTTP(backendId, "/state")
        let (data, response) = try await session.data(from: url)
        try Self.expectOK(response)
        do {
            return try JSONDecoder().decode(AppState.self, from: data)
        } catch {
            throw GatewayError.decoding(String(describing: error))
        }
    }

    private struct StateWrite: Encodable {
        let workspaces: [Workspace]
        let activeWorkspaceId: String
    }

    /// `PUT /api/backends/:id/state` — persists the workspace/pane layout, returns the
    /// server-sanitized state.
    @discardableResult
    public func saveState(backendId: String?, _ state: AppState) async throws -> AppState {
        var request = URLRequest(url: endpoint.backendHTTP(backendId, "/state"))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(StateWrite(workspaces: state.workspaces, activeWorkspaceId: state.activeWorkspaceId))
        let (data, response) = try await session.data(for: request)
        try Self.expectOK(response)
        do {
            return try JSONDecoder().decode(AppState.self, from: data)
        } catch {
            throw GatewayError.decoding(String(describing: error))
        }
    }

    /// `DELETE /api/backends/:id/sessions/:paneId`
    public func killSession(backendId: String?, paneId: String) async throws {
        var request = URLRequest(url: endpoint.backendHTTP(backendId, "/sessions/\(paneId)"))
        request.httpMethod = "DELETE"
        let (_, response) = try await session.data(for: request)
        try Self.expectOK(response)
    }

    /// `GET /api/backends/:id/pty-config`
    public func ptyConfig(backendId: String?) async throws -> PtyConfigPayload {
        let (data, response) = try await session.data(from: endpoint.backendHTTP(backendId, "/pty-config"))
        try Self.expectOK(response)
        do { return try JSONDecoder().decode(PtyConfigPayload.self, from: data) }
        catch { throw GatewayError.decoding(String(describing: error)) }
    }

    /// `PUT /api/backends/:id/pty-config` (save) or `POST …/pty-config/register` (save + register).
    @discardableResult
    public func writePtyConfig(backendId: String?, _ config: PtyConfig, register: Bool) async throws -> PtyConfigPayload {
        var request = URLRequest(url: endpoint.backendHTTP(backendId, register ? "/pty-config/register" : "/pty-config"))
        request.httpMethod = register ? "POST" : "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(config)
        let (data, response) = try await session.data(for: request)
        try Self.expectOK(response)
        do { return try JSONDecoder().decode(PtyConfigPayload.self, from: data) }
        catch { throw GatewayError.decoding(String(describing: error)) }
    }

    /// `GET /api/backends/:id/pm/projects`
    public func pmProjects(backendId: String?) async throws -> [PmProject] {
        let (data, response) = try await session.data(from: endpoint.backendHTTP(backendId, "/pm/projects"))
        try Self.expectOK(response)
        return (try? JSONDecoder().decode([PmProject].self, from: data)) ?? []
    }

    /// `GET /api/backends/:id/pm/tasks?project_id=…`
    public func pmTasks(backendId: String?, projectId: String) async throws -> [PmTask] {
        var components = URLComponents(url: endpoint.backendHTTP(backendId, "/pm/tasks"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "project_id", value: projectId)]
        let (data, response) = try await session.data(from: components.url!)
        try Self.expectOK(response)
        return (try? JSONDecoder().decode([PmTask].self, from: data)) ?? []
    }

    private static func expectOK(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw GatewayError.badStatus(http.statusCode)
        }
    }
}
