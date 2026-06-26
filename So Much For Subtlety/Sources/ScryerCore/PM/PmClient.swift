import Foundation

public enum PmError: Error, LocalizedError {
    case badStatus(Int, String)
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .badStatus(let code, let body): return "PM API HTTP \(code)\(body.isEmpty ? "" : ": \(body)")"
        case .decoding(let detail): return "Could not decode PM response: \(detail)"
        }
    }
}

/// Direct client for the JEPM PM system. Mirrors loom's `api/*.js` contract
/// (`/api/projects`, `/api/tasks`, `/api/projects/:id/tasks/reorder`, …) so the native
/// Kanbaner reads and writes the same data the web board does — full CRUD, no proxy.
public struct PmClient: Sendable {
    public let endpoint: PmEndpoint
    private let session: URLSession

    public init(endpoint: PmEndpoint, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    // MARK: Projects

    /// `GET /api/projects`
    public func listProjects() async throws -> [PmProject] {
        try await get(endpoint.apiURL("projects"))
    }

    /// `GET /api/projects/:id/subprojects`
    public func subProjects(projectId: String) async throws -> [PmProject] {
        try await get(endpoint.apiURL("projects/\(projectId)/subprojects"))
    }

    /// `GET /api/task-types?project_id=…`
    public func taskTypes(projectId: String) async throws -> [PmTaskType] {
        try await get(endpoint.apiURL("task-types", query: [URLQueryItem(name: "project_id", value: projectId)]))
    }

    // MARK: Tasks

    /// `GET /api/tasks?project_id=…`
    public func listTasks(projectId: String) async throws -> [PmTask] {
        try await get(endpoint.apiURL("tasks", query: [URLQueryItem(name: "project_id", value: projectId)]))
    }

    /// `POST /api/tasks` — returns the created task (for optimistic insertion).
    @discardableResult
    public func createTask(projectId: String, title: String, status: String,
                           taskTypeId: String?, parentTaskId: String?) async throws -> PmTask {
        var body: [String: String] = [
            "title": title,
            "status": status,
            "project_id": projectId,
            "created_by_role": "human",
            "created_by_instance_key": "user",
        ]
        if let taskTypeId { body["task_type_id"] = taskTypeId }
        if let parentTaskId { body["parent_task_id"] = parentTaskId }
        return try await send("POST", endpoint.apiURL("tasks"), json: body)
    }

    /// `PATCH /api/tasks/:id` — `fields` are any of status / title / description_md /
    /// task_type_id / project_id. Returns the updated task.
    @discardableResult
    public func updateTask(id: String, fields: [String: String]) async throws -> PmTask {
        try await send("PATCH", endpoint.apiURL("tasks/\(id)"), json: fields)
    }

    /// `DELETE /api/tasks/:id`
    public func deleteTask(id: String) async throws {
        try await sendNoContent("DELETE", endpoint.apiURL("tasks/\(id)"), json: nil)
    }

    /// `POST /api/projects/:id/tasks/reorder` — persists `taskIds` as the new display order.
    public func reorder(projectId: String, taskIds: [String]) async throws {
        try await sendNoContent("POST", endpoint.apiURL("projects/\(projectId)/tasks/reorder"),
                                json: ["task_ids": taskIds])
    }

    // MARK: Comments

    /// `GET /api/tasks/:id/comments` — oldest-first (the UI reverses for newest-on-top).
    public func comments(taskId: String) async throws -> [PmComment] {
        try await get(endpoint.apiURL("tasks/\(taskId)/comments"))
    }

    /// `POST /api/comments`
    @discardableResult
    public func createComment(taskId: String, bodyMd: String) async throws -> PmComment {
        try await send("POST", endpoint.apiURL("comments"), json: [
            "task_id": taskId,
            "body_md": bodyMd,
            "body_format": "md",
            "author_role": "human",
            "author_instance_key": "user",
        ])
    }

    /// `PATCH /api/comments/:id`
    @discardableResult
    public func updateComment(id: String, bodyMd: String) async throws -> PmComment {
        try await send("PATCH", endpoint.apiURL("comments/\(id)"), json: ["body_md": bodyMd])
    }

    /// `DELETE /api/comments/:id`
    public func deleteComment(id: String) async throws {
        try await sendNoContent("DELETE", endpoint.apiURL("comments/\(id)"), json: nil)
    }

    // MARK: Plumbing

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        let (data, response) = try await session.data(from: url)
        try Self.expectOK(response, data)
        return try Self.decode(data)
    }

    @discardableResult
    private func send<T: Decodable>(_ method: String, _ url: URL, json: Encodable?) async throws -> T {
        let (data, response) = try await perform(method, url, json: json)
        try Self.expectOK(response, data)
        return try Self.decode(data)
    }

    private func sendNoContent(_ method: String, _ url: URL, json: Encodable?) async throws {
        let (data, response) = try await perform(method, url, json: json)
        try Self.expectOK(response, data)
    }

    private func perform(_ method: String, _ url: URL, json: Encodable?) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(AnyEncodable(json))
        }
        return try await session.data(for: request)
    }

    private static func decode<T: Decodable>(_ data: Data) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw PmError.decoding(String(describing: error)) }
    }

    private static func expectOK(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw PmError.badStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }
}

/// Type-erased Encodable so the client can take heterogeneous JSON bodies.
private struct AnyEncodable: Encodable {
    private let encodeImpl: (Encoder) throws -> Void
    init(_ wrapped: Encodable) { self.encodeImpl = wrapped.encode }
    func encode(to encoder: Encoder) throws { try encodeImpl(encoder) }
}
