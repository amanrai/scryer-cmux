import SwiftUI
import Observation
import ScryerCore

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

@MainActor
@Observable
final class ProjectOrganizerModel {
    let endpoint: PmEndpoint
    var projects: [PmProject] = []
    var loading = false
    var saving = false
    var error: String?
    var selectedProjectId: String?
    var draftName = ""
    var draftSlug = ""
    var draftDescription = ""
    var draftParentId: String?
    var draftRemoteRepo = ""
    var repoLink: ProjectRepoLink?
    var editingDescription = false

    private var client: PmClient { PmClient(endpoint: endpoint) }

    init(endpoint: PmEndpoint) { self.endpoint = endpoint }

    struct Node: Identifiable, Hashable {
        var id: String { project.id }
        let project: PmProject
        let depth: Int

        static func == (lhs: Node, rhs: Node) -> Bool { lhs.project.id == rhs.project.id && lhs.depth == rhs.depth }
        func hash(into hasher: inout Hasher) { hasher.combine(project.id); hasher.combine(depth) }
    }

    var selectedProject: PmProject? { projects.first { $0.id == selectedProjectId } }
    var hasProjectDraftChange: Bool {
        guard let project = selectedProject else { return false }
        return draftName != project.name
            || draftSlug != (project.slug ?? "")
            || draftDescription != (project.description_md ?? "")
            || draftParentId != project.parent_project_id
    }
    var hasRepoDraftChange: Bool {
        draftRemoteRepo.trimmingCharacters(in: .whitespacesAndNewlines) != (repoLink?.remote_url ?? selectedProject?.remote_repo_url ?? "")
    }

    var tree: [Node] {
        var byParent: [String?: [PmProject]] = [:]
        for project in projects { byParent[project.parent_project_id, default: []].append(project) }

        func sorted(_ list: [PmProject]) -> [PmProject] {
            list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        var result: [Node] = []
        var seen = Set<String>()
        func visit(parentId: String?, depth: Int) {
            for project in sorted(byParent[parentId] ?? []) where !seen.contains(project.id) {
                seen.insert(project.id)
                result.append(Node(project: project, depth: depth))
                visit(parentId: project.id, depth: depth + 1)
            }
        }
        visit(parentId: nil, depth: 0)

        // Surface orphans/cycles too, but keep them visibly root-level.
        for project in sorted(projects) where !seen.contains(project.id) {
            seen.insert(project.id)
            result.append(Node(project: project, depth: 0))
            visit(parentId: project.id, depth: 1)
        }
        return result
    }

    var parentCandidates: [PmProject] {
        guard let selectedProjectId else { return [] }
        return projects
            .filter { candidate in candidate.id != selectedProjectId && !isDescendant(candidate.id, of: selectedProjectId) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func load() async {
        loading = true; defer { loading = false }
        do {
            projects = try await client.listProjects()
            error = nil
            if selectedProjectId == nil || !projects.contains(where: { $0.id == selectedProjectId }) {
                selectedProjectId = tree.first?.project.id
                repoLink = nil
            }
            syncDraftToSelection()
            await loadRepoLinkForSelection()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func select(_ project: PmProject) {
        selectedProjectId = project.id
        repoLink = nil
        editingDescription = false
        syncDraftToSelection()
        Task { await loadRepoLinkForSelection() }
    }

    func syncDraftToSelection() {
        guard let project = selectedProject else {
            draftName = ""; draftSlug = ""; draftDescription = ""; draftParentId = nil; draftRemoteRepo = ""; repoLink = nil; editingDescription = false
            return
        }
        draftName = project.name
        draftSlug = project.slug ?? ""
        draftDescription = project.description_md ?? ""
        draftParentId = project.parent_project_id
        draftRemoteRepo = repoLink?.remote_url ?? project.remote_repo_url ?? ""
    }

    func loadRepoLinkForSelection() async {
        guard let selectedProjectId else { return }
        repoLink = (try? await client.projectRepoLink(projectId: selectedProjectId)) ?? nil
        draftRemoteRepo = repoLink?.remote_url ?? selectedProject?.remote_repo_url ?? ""
    }

    func saveProjectSettings() async {
        guard let selectedProjectId, hasProjectDraftChange else { return }
        saving = true; defer { saving = false }
        error = nil
        do {
            _ = try await client.updateProject(projectId: selectedProjectId, fields: ProjectUpdateFields(
                name: draftName.trimmingCharacters(in: .whitespacesAndNewlines),
                slug: draftSlug.trimmingCharacters(in: .whitespacesAndNewlines),
                description_md: draftDescription.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                parent_project_id: draftParentId,
                encodeName: true, encodeSlug: true, encodeDescription: true, encodeParent: true
            ))
            await load()
        } catch {
            self.error = error.localizedDescription
            syncDraftToSelection()
        }
    }

    func saveRepoSettings() async {
        guard let selectedProjectId, hasRepoDraftChange else { return }
        let remote = draftRemoteRepo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remote.isEmpty else { error = "Remote repo URL is required to create/update a repo link."; return }
        saving = true; defer { saving = false }
        error = nil
        do {
            repoLink = try await client.upsertProjectRepoLink(projectId: selectedProjectId, remoteURL: remote)
            await load()
        } catch {
            self.error = error.localizedDescription
            await loadRepoLinkForSelection()
        }
    }

    private func isDescendant(_ candidateId: String, of projectId: String) -> Bool {
        var current = projects.first { $0.id == candidateId }
        var seen = Set<String>()
        while let node = current, !seen.contains(node.id) {
            if node.parent_project_id == projectId { return true }
            seen.insert(node.id)
            current = node.parent_project_id.flatMap { parentId in projects.first { $0.id == parentId } }
        }
        return false
    }
}

struct ProjectOrganizerView: View {
    @Environment(AppModel.self) private var model
    @State private var organizer: ProjectOrganizerModel?
    @State private var showingBackendPicker = false
    @AppStorage("smfs.projectOrganizerListWidth") private var projectListWidth: Double = 340
    @State private var projectListDragStartWidth: Double?

    private var bg: Color { Color(hex: model.theme.terminal.background.hex) ?? .black }
    private var chrome: Color { Color(hex: model.theme.terminal.chrome.hex) ?? .black }
    private var fg: Color { Color(hex: model.theme.terminal.foreground.hex) ?? .white }
    private var muted: Color { fg.opacity(0.55) }
    private let minProjectListWidth: Double = 240
    private let maxProjectListWidth: Double = 560

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().overlay(fg.opacity(0.08))
            if let organizer {
                content(organizer)
            } else {
                Spacer()
                ProgressView().tint(fg)
                Spacer()
            }
        }
        .background(bg)
        .foregroundStyle(fg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
        .ignoresSafeArea(.container, edges: .top)
        #endif
        #if os(iOS)
        .fullScreenCover(isPresented: $showingBackendPicker) {
            CenteredModalCover(isPresented: $showingBackendPicker, width: 560, heightRatio: 0.56) { backendPicker }
                .presentationBackground(.clear)
        }
        #else
        .sheet(isPresented: $showingBackendPicker) { backendPicker }
        #endif
        .task {
            if organizer == nil {
                let created = ProjectOrganizerModel(endpoint: model.pmEndpoint)
                organizer = created
                await created.load()
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button(action: { showingBackendPicker = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "folder.badge.gearshape").font(.system(size: 13, weight: .semibold))
                    Text("Project Organizer").font(.system(size: 13, weight: .semibold))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(fg.opacity(0.45))
                }
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(fg.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("k", modifiers: .command)
            .help("Select backend or screen (⌘K)")

            Text("Select a project, then choose its parent.")
                .font(.system(size: 12))
                .foregroundStyle(muted)
                .lineLimit(1)
            Spacer()
            Button { Task { await organizer?.load() } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain)
                .foregroundStyle(muted)
                .help("Reload projects")
        }
        #if os(macOS)
        .padding(.leading, 78)
        #else
        .padding(.leading, 12)
        #endif
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .background(chrome)
    }

    private var backendPicker: some View {
        MachinePickerSheet(currentBackendId: "", onSelect: { selected in
            model.showingProjectOrganizer = false
            model.select(selected)
        }, kanbanerSelected: false, projectOrganizerSelected: true,
        onKanbaner: {
            model.showingProjectOrganizer = false
            model.showingKanbaner = true
        }, onProjectOrganizer: {
            model.showingProjectOrganizer = true
        })
        .environment(model)
    }

    private func content(_ organizer: ProjectOrganizerModel) -> some View {
        HStack(spacing: 0) {
            projectList(organizer)
                .frame(width: projectListWidth)
            projectListResizeHandle
            settingsPane(organizer)
                .frame(width: 360)
            Divider().overlay(fg.opacity(0.08))
            descriptionPane(organizer)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .top) {
            if let error = organizer.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.top, 12)
            }
        }
    }

    private var projectListResizeHandle: some View {
        ZStack {
            Rectangle().fill(fg.opacity(0.08)).frame(width: 1)
            Rectangle().fill(Color.black.opacity(0.001)).frame(width: 14)
        }
        .frame(width: 14)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let start = projectListDragStartWidth ?? projectListWidth
                    if projectListDragStartWidth == nil { projectListDragStartWidth = start }
                    projectListWidth = min(maxProjectListWidth, max(minProjectListWidth, start + value.translation.width))
                }
                .onEnded { _ in projectListDragStartWidth = nil }
        )
    }

    private func projectList(_ organizer: ProjectOrganizerModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Projects").font(.system(size: 13, weight: .semibold))
                Spacer()
                if organizer.loading { ProgressView().controlSize(.small).tint(fg) }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            Divider().overlay(fg.opacity(0.08))

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(organizer.tree) { node in projectRow(node, organizer: organizer) }
                    if organizer.projects.isEmpty && !organizer.loading {
                        Text("No projects found").foregroundStyle(muted).padding(.vertical, 40)
                    }
                }
                .padding(10)
            }
        }
        .background(chrome.opacity(0.55))
    }

    private func projectRow(_ node: ProjectOrganizerModel.Node, organizer: ProjectOrganizerModel) -> some View {
        let selected = node.project.id == organizer.selectedProjectId
        return Button { organizer.select(node.project) } label: {
            HStack(spacing: 9) {
                Text(node.depth > 0 ? "◈" : "▦")
                    .font(.system(size: node.depth > 0 ? 10 : 11, weight: .semibold))
                    .foregroundStyle(fg.opacity(0.45))
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.project.name)
                        .font(.system(size: node.depth > 0 ? 12 : 13, weight: selected ? .semibold : .medium))
                        .foregroundStyle(fg.opacity(selected ? 1 : node.depth > 0 ? 0.68 : 0.9))
                        .lineLimit(1)
                    if let subtitle = projectSubtitle(node.project) {
                        Text(subtitle).font(.system(size: 10).monospaced()).foregroundStyle(fg.opacity(0.38)).lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(.leading, 8 + CGFloat(node.depth) * 16).padding(.trailing, 8).padding(.vertical, 7)
            .background(selected ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func settingsPane(_ organizer: ProjectOrganizerModel) -> some View {
        Group {
            if let project = organizer.selectedProject {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(project.name).font(.system(size: 20, weight: .semibold)).lineLimit(2)
                            if let subtitle = projectSubtitle(project) {
                                Text(subtitle).font(.system(size: 11).monospaced()).foregroundStyle(muted).lineLimit(2)
                            }
                        }

                        settingsSection("Basics") {
                            labeledField("Name") {
                                TextField("Project name", text: Binding(get: { organizer.draftName }, set: { organizer.draftName = $0 }))
                                    .textFieldStyle(.roundedBorder)
                            }
                            labeledField("Slug") {
                                TextField("project-slug", text: Binding(get: { organizer.draftSlug }, set: { organizer.draftSlug = $0 }))
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12).monospaced())
                            }
                        }

                        settingsSection("Hierarchy") {
                            labeledField("Parent") {
                                Picker("Parent project", selection: Binding(get: {
                                    organizer.draftParentId ?? "__root__"
                                }, set: { value in
                                    organizer.draftParentId = (value == "__root__") ? nil : value
                                })) {
                                    Text("No parent — root project").tag("__root__")
                                    ForEach(organizer.parentCandidates) { candidate in
                                        Text(candidate.name).tag(candidate.id)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            projectActions(organizer)
                        }

                        settingsSection("Repository") {
                            labeledField("Remote URL") {
                                TextField("git@github.com:org/repo.git", text: Binding(get: { organizer.draftRemoteRepo }, set: { organizer.draftRemoteRepo = $0 }))
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12).monospaced())
                            }
                            if let link = organizer.repoLink {
                                metadataRow("Status", [link.clone_status, link.clone_stage].compactMap { $0 }.joined(separator: " · "))
                                metadataRow("Progress", "\(link.clone_progress)%")
                                metadataRow("Rel path", link.relative_repo_path)
                                if let error = link.error_message, !error.isEmpty { metadataRow("Error", error, color: .red) }
                            } else if let path = project.relative_repo_path {
                                metadataRow("Rel path", path)
                            }
                            repoActions(organizer)
                        }

                        settingsSection("Metadata") {
                            metadataRow("Project ID", project.id)
                            if let created = project.created_at { metadataRow("Created", created) }
                            if let updated = project.updated_at { metadataRow("Updated", updated) }
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                ContentUnavailableView("Select a project", systemImage: "folder.badge.gearshape",
                                       description: Text("Choose a project on the left to edit settings."))
                    .foregroundStyle(muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(bg)
    }

    private func descriptionPane(_ organizer: ProjectOrganizerModel) -> some View {
        Group {
            if organizer.selectedProject != nil {
                VStack(spacing: 0) {
                    HStack {
                        Text("Description").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        if organizer.editingDescription {
                            Button("Done") { organizer.editingDescription = false }
                                .buttonStyle(.bordered)
                        }
                        Button {
                            Task { await organizer.saveProjectSettings() }
                        } label: {
                            if organizer.saving { ProgressView().controlSize(.small) }
                            else { Label("Save", systemImage: "checkmark") }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!organizer.hasProjectDraftChange || organizer.saving)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    Divider().overlay(fg.opacity(0.08))

                    Group {
                        if organizer.editingDescription {
                            TextEditor(text: Binding(get: { organizer.draftDescription }, set: { organizer.draftDescription = $0 }))
                                .font(.system(size: 13).monospaced())
                                .scrollContentBackground(.hidden)
                                .padding(14)
                                .background(fg.opacity(0.04))
                        } else {
                            ScrollView {
                                if organizer.draftDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text("No description. Double-click to add one.")
                                        .font(.system(size: 13))
                                        .foregroundStyle(muted)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(16)
                                } else {
                                    MarkdownText(text: organizer.draftDescription, fg: fg)
                                        .padding(16)
                                }
                            }
                            .background(fg.opacity(0.025))
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { organizer.editingDescription = true }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ContentUnavailableView("Select a project", systemImage: "doc.text",
                                       description: Text("The project description will appear here."))
                    .foregroundStyle(muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(bg)
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(muted)
            VStack(alignment: .leading, spacing: 12) { content() }
                .padding(14)
                .background(fg.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(fg.opacity(0.08)))
        }
    }

    private func labeledField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(muted)
            content()
        }
    }

    private func metadataRow(_ label: String, _ value: String, color: Color? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(muted).frame(width: 92, alignment: .leading)
            Text(value).font(.system(size: 11).monospaced()).foregroundStyle(color ?? fg.opacity(0.68)).textSelection(.enabled)
        }
    }

    private func projectActions(_ organizer: ProjectOrganizerModel) -> some View {
        HStack(spacing: 10) {
            Button {
                Task { await organizer.saveProjectSettings() }
            } label: {
                if organizer.saving { ProgressView().controlSize(.small) }
                else { Label("Save project", systemImage: "checkmark") }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!organizer.hasProjectDraftChange || organizer.saving || organizer.draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || organizer.draftSlug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button("Reset") { organizer.syncDraftToSelection() }
                .buttonStyle(.bordered)
                .disabled(!organizer.hasProjectDraftChange || organizer.saving)
        }
    }

    private func repoActions(_ organizer: ProjectOrganizerModel) -> some View {
        HStack(spacing: 10) {
            Button {
                Task { await organizer.saveRepoSettings() }
            } label: {
                if organizer.saving { ProgressView().controlSize(.small) }
                else { Label(organizer.repoLink == nil ? "Link repository" : "Update repository", systemImage: "arrow.triangle.2.circlepath") }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!organizer.hasRepoDraftChange || organizer.saving || organizer.draftRemoteRepo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button("Reset") { organizer.draftRemoteRepo = organizer.repoLink?.remote_url ?? organizer.selectedProject?.remote_repo_url ?? "" }
                .buttonStyle(.bordered)
                .disabled(!organizer.hasRepoDraftChange || organizer.saving)
        }
    }

    private func projectSubtitle(_ project: PmProject) -> String? {
        let parts = [project.slug, project.relative_repo_path]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
