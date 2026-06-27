import Foundation
import Observation
import ScryerCore

/// State + mutations for the Kanbaner board. Talks to the PM system directly via `PmClient`
/// (full CRUD), with optimistic local updates for drag/reorder so cards move immediately.
@MainActor
@Observable
final class KanbanerModel {
    let endpoint: PmEndpoint
    var projects: [PmProject] = []
    var selectedProjectId: String?
    var tasks: [PmTask] = []
    var taskTypes: [PmTaskType] = []
    var projectTouchTimes: [String: TimeInterval] = [:]
    var loadingProjects = false
    var loadingTasks = false
    var error: String?

    /// Breadcrumb path: the project root, then any feature tasks drilled into.
    var navStack: [Crumb] = []

    struct Crumb: Identifiable, Hashable {
        let id = UUID()
        let taskId: String?   // nil = project root
        let name: String
    }

    struct ProjectNode: Identifiable, Hashable {
        var id: String { project.id }
        let project: PmProject
        let depth: Int
        let hidden: Bool

        static func == (lhs: ProjectNode, rhs: ProjectNode) -> Bool {
            lhs.project.id == rhs.project.id && lhs.depth == rhs.depth && lhs.hidden == rhs.hidden
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(project.id)
            hasher.combine(depth)
            hasher.combine(hidden)
        }
    }

    private var client: PmClient { PmClient(endpoint: endpoint) }

    static let statusOrder = ["unopened", "in_execution", "ready_for_human_review", "human_reviewed_and_closed"]

    static func label(_ status: String) -> String {
        switch status {
        case "unopened": return "Unopened"
        case "in_execution": return "In Execution"
        case "ready_for_human_review": return "Ready for Review"
        case "human_reviewed_and_closed": return "Reviewed & Closed"
        default: return status.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// Hex color for a status column accent (mirrors loom's STATUS_COLORS).
    static func colorHex(_ status: String) -> String {
        switch status {
        case "unopened": return "#6366F1"
        case "in_execution": return "#F59E0B"
        case "ready_for_human_review": return "#10B981"
        case "human_reviewed_and_closed": return "#6B7280"
        default: return "#5C5A55"
        }
    }

    init(endpoint: PmEndpoint, initialProjectId: String?) {
        self.endpoint = endpoint
        self.selectedProjectId = initialProjectId
    }

    var selectedProject: PmProject? { projects.first { $0.id == selectedProjectId } }

    var projectTree: [ProjectNode] {
        let byId = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        var byParent: [String?: [PmProject]] = [:]
        for project in projects { byParent[project.parent_project_id, default: []].append(project) }

        func sorted(_ list: [PmProject]) -> [PmProject] {
            list.sorted { a, b in
                let diff = (projectTouchTimes[b.id] ?? 0) - (projectTouchTimes[a.id] ?? 0)
                if diff != 0 { return diff > 0 }
                return a.name.localizedCompare(b.name) == .orderedAscending
            }
        }

        func isHidden(_ project: PmProject) -> Bool {
            if project.name.hasPrefix("~") { return true }
            if let parentId = project.parent_project_id, let parent = byId[parentId] {
                return parent.name.hasPrefix("~")
            }
            return false
        }

        var result: [ProjectNode] = []
        func visit(parentId: String?, depth: Int) {
            for project in sorted(byParent[parentId] ?? []) {
                result.append(ProjectNode(project: project, depth: depth, hidden: isHidden(project)))
                visit(parentId: project.id, depth: depth + 1)
            }
        }
        visit(parentId: nil, depth: 0)
        return result
    }

    var visibleProjectTree: [ProjectNode] { projectTree.filter { !$0.hidden } }
    var hiddenProjectTree: [ProjectNode] { projectTree.filter(\.hidden) }

    /// Current drill scope: nil = project root, else the feature task whose children we show.
    var currentParentId: String? { navStack.last?.taskId }

    /// Tasks that have children — rendered with a drill affordance.
    var featureIds: Set<String> { Set(tasks.compactMap { $0.parent_task_id }) }

    /// Tasks visible at the current drill scope.
    private var visibleTasks: [PmTask] { tasks.filter { $0.parent_task_id == currentParentId } }

    func isFeature(_ task: PmTask) -> Bool { featureIds.contains(task.id) }

    /// Columns to render: the known status order plus any unexpected statuses present.
    var statuses: [String] {
        var result = Self.statusOrder
        let extras = Set(visibleTasks.compactMap { $0.status }).subtracting(result)
        result.append(contentsOf: extras.sorted())
        return result
    }

    /// Cards in one status column at the current scope, ordered by display_order then recency.
    func cards(in status: String) -> [PmTask] {
        visibleTasks
            .filter { ($0.status ?? "unopened") == status }
            .sorted { ($0.display_order ?? 0, $0.updated_at ?? "") < ($1.display_order ?? 0, $1.updated_at ?? "") }
    }

    func taskType(for task: PmTask) -> PmTaskType? {
        guard let id = task.task_type_id else { return nil }
        return taskTypes.first { $0.id == id }
    }

    // MARK: Drill navigation (breadcrumb)

    /// Reset the breadcrumb to just the project root.
    private func setRootCrumb() {
        navStack = [Crumb(taskId: nil, name: selectedProject?.name ?? "Project")]
    }

    /// Drill into a feature task — pushes a breadcrumb and scopes to its children.
    func drill(into task: PmTask) {
        navStack.append(Crumb(taskId: task.id, name: task.title))
    }

    /// Navigate to a breadcrumb level (truncates the deeper crumbs).
    func navigate(to index: Int) {
        guard index >= 0, index < navStack.count else { return }
        navStack = Array(navStack.prefix(index + 1))
    }

    // MARK: Loading

    func loadProjects() async {
        loadingProjects = true; defer { loadingProjects = false }
        do {
            let loaded = try await client.listProjects()
            projects = loaded
            await loadProjectTouchTimes(for: loaded)
            error = nil
            if selectedProjectId == nil || !projects.contains(where: { $0.id == selectedProjectId }) {
                selectedProjectId = visibleProjectTree.first?.project.id ?? projectTree.first?.project.id
            }
            setRootCrumb()
            if let id = selectedProjectId { await loadTasks(projectId: id) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func select(projectId: String) async {
        guard projectId != selectedProjectId else { return }
        selectedProjectId = projectId
        tasks = []
        taskTypes = []
        setRootCrumb()
        await loadTasks(projectId: projectId)
    }

    func reload() async {
        guard let id = selectedProjectId else { return }
        await loadTasks(projectId: id)
    }

    /// Focus a single task's project (for the standalone terminal-side ticket detail). Seeds
    /// `tasks` with the known task so the panel shows immediately, then loads the real data.
    func focus(on task: PmTask, projectId: String) async {
        selectedProjectId = projectId
        if tasks.first(where: { $0.id == task.id }) == nil { tasks = [task] }
        await loadTasks(projectId: projectId)
    }

    private func loadProjectTouchTimes(for projects: [PmProject]) async {
        var tasksByProject: [String: [PmTask]] = [:]
        if let allTasks = try? await client.listTasks() {
            for task in allTasks {
                guard let projectId = task.project_id else { continue }
                tasksByProject[projectId, default: []].append(task)
            }
        }

        var deletedByProject: [String: [PmTask]] = [:]
        await withTaskGroup(of: (String, [PmTask]).self) { group in
            for project in projects {
                group.addTask { [client] in
                    let deleted = (try? await client.deletedTasks(projectId: project.id)) ?? []
                    return (project.id, deleted)
                }
            }
            for await (projectId, deleted) in group { deletedByProject[projectId] = deleted }
        }

        projectTouchTimes = Dictionary(uniqueKeysWithValues: projects.map { project in
            let times = [Self.time(project.updated_at), Self.time(project.created_at)]
                + (tasksByProject[project.id] ?? []).map(Self.taskTouchTime)
                + (deletedByProject[project.id] ?? []).map(Self.taskTouchTime)
            return (project.id, times.max() ?? 0)
        })
    }

    private static func taskTouchTime(_ task: PmTask) -> TimeInterval {
        max(time(task.deleted_at), time(task.updated_at), time(task.created_at))
    }

    private static func time(_ value: String?) -> TimeInterval {
        guard let value, !value.isEmpty else { return 0 }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        let isoWithFractional = ISO8601DateFormatter()
        isoWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoWithFractional.date(from: trimmed) { return date.timeIntervalSince1970 }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: trimmed) { return date.timeIntervalSince1970 }

        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX", "yyyy-MM-dd'T'HH:mm:ssXXXXX", "yyyy-MM-dd'T'HH:mm:ss.SSSSSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss.SSSSSS", "yyyy-MM-dd HH:mm:ss"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) { return date.timeIntervalSince1970 }
        }
        return 0
    }

    private func loadTasks(projectId: String) async {
        loadingTasks = true; defer { loadingTasks = false }
        do {
            let loaded = try await client.listTasks(projectId: projectId)
            guard projectId == selectedProjectId else { return }   // ignore stale switch
            tasks = loaded
            error = nil
        } catch {
            guard projectId == selectedProjectId else { return }
            self.error = error.localizedDescription
        }
        // Task types are best-effort (only used for the card swatch).
        if let types = try? await client.taskTypes(projectId: projectId), projectId == selectedProjectId {
            taskTypes = types
        }
    }

    // MARK: Mutations

    /// Move `taskId` into `status`, positioned before `beforeId` (appended if nil). Optimistic.
    func drop(taskId: String, into status: String, before beforeId: String?) async {
        guard let projectId = selectedProjectId,
              let moving = tasks.first(where: { $0.id == taskId }) else { return }
        if beforeId == taskId { return }
        let statusChanged = (moving.status ?? "unopened") != status

        // Build the target column's new order.
        var column = cards(in: status).filter { $0.id != taskId }
        let updatedMoving = moving.with(status: status)
        if let beforeId, let pos = column.firstIndex(where: { $0.id == beforeId }) {
            column.insert(updatedMoving, at: pos)
        } else {
            column.append(updatedMoving)
        }
        if !statusChanged && column.map(\.id) == cards(in: status).map(\.id) { return }   // no-op

        // Apply optimistically: new status on the moved card + fresh display_order across column.
        var byId = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for (order, task) in column.enumerated() { byId[task.id] = task.with(displayOrder: order) }
        tasks = tasks.map { byId[$0.id] ?? $0 }

        do {
            if statusChanged { try await client.updateTask(id: taskId, fields: ["status": status]) }
            try await client.reorder(projectId: projectId, taskIds: column.map(\.id))
        } catch {
            self.error = error.localizedDescription
        }
        await reload()
    }

    func create(title: String, status: String) async {
        guard let projectId = selectedProjectId else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let defaultType = taskTypes.first(where: { $0.is_default == true }) ?? taskTypes.first
        do {
            _ = try await client.createTask(projectId: projectId, title: trimmed, status: status,
                                            taskTypeId: defaultType?.id, parentTaskId: currentParentId)
            await reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func update(taskId: String, fields: [String: String]) async {
        if let idx = tasks.firstIndex(where: { $0.id == taskId }), let status = fields["status"] {
            tasks[idx] = tasks[idx].with(status: status)   // optimistic for the visible status
        }
        do {
            _ = try await client.updateTask(id: taskId, fields: fields)
        } catch {
            self.error = error.localizedDescription
        }
        await reload()
    }

    func delete(taskId: String) async {
        tasks.removeAll { $0.id == taskId }
        do {
            try await client.deleteTask(id: taskId)
        } catch {
            self.error = error.localizedDescription
        }
        await reload()
    }
}
