import Foundation

/// One terminal pane. Mirrors `server-pty/state-store.mjs`.
public struct Pane: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var createdAt: Double

    public init(id: String = Pane.makeId(), title: String, createdAt: Double = Date().timeIntervalSince1970 * 1000) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
    }

    public static func makeId() -> String { "pane-\(UUID().uuidString.prefix(12).lowercased())" }
}

public struct Workspace: Identifiable, Codable, Hashable, Sendable {
    public enum Layout: String, Codable, Sendable { case row, column }

    public let id: String
    public var name: String
    public var color: String
    public var layout: Layout
    public var panes: [Pane]
    public var activePaneId: String

    public init(
        id: String = Workspace.makeId(),
        name: String,
        color: String,
        layout: Layout = .row,
        panes: [Pane],
        activePaneId: String
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.layout = layout
        self.panes = panes
        self.activePaneId = activePaneId
    }

    public static func makeId() -> String { "workspace-\(UUID().uuidString.prefix(12).lowercased())" }
}

/// Server-authoritative app state. Mirrors `GET /api/state`.
public struct AppState: Codable, Hashable, Sendable {
    public var workspaces: [Workspace]
    public var activeWorkspaceId: String
    public var hostName: String?

    public init(workspaces: [Workspace], activeWorkspaceId: String, hostName: String? = nil) {
        self.workspaces = workspaces
        self.activeWorkspaceId = activeWorkspaceId
        self.hostName = hostName
    }

    public var activeWorkspace: Workspace? {
        workspaces.first { $0.id == activeWorkspaceId } ?? workspaces.first
    }
}
