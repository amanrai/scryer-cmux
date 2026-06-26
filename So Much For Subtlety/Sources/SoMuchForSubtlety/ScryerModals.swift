import SwiftUI
import ScryerCore

// MARK: Interaction

struct InteractionModalView: View {
    @Environment(\.dismiss) private var dismiss
    /// The single interaction to surface (newest undismissed after the newest dismissed), or
    /// nil when there's nothing actionable — the notifications list still shows.
    let request: InteractionRequest?
    let updates: [SessionUpdate]
    let onRespond: ([String: Any]) -> Void
    let onDismissRequest: () -> Void

    @State private var composing = false
    @State private var draft = ""
    @FocusState private var composeFocused: Bool

    var body: some View {
        List {
            if let request {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(request.payload.title ?? "Input needed").font(.headline)
                        if let body = request.payload.body, !body.isEmpty {
                            Text(body).foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Respond") {
                    ForEach(request.payload.choices ?? []) { choice in
                        Button {
                            if choice.custom == true { composing = true }
                            else { onRespond(["kind": "choice", "choiceId": choice.id, "text": choice.send ?? choice.label]); dismiss() }
                        } label: {
                            HStack {
                                Text(choice.label)
                                Spacer()
                                Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Button { composing = true } label: {
                        Label("Type response…", systemImage: "keyboard")
                    }
                    .buttonStyle(.plain)
                }

                if composing {
                    Section("Custom response") {
                        TextEditor(text: $draft)
                            .font(.body.monospaced()).frame(minHeight: 90)
                            .focused($composeFocused)
                            .onAppear { composeFocused = true }   // raise the system keyboard
                        Button("Send") {
                            onRespond(["kind": "custom", "text": draft.trimmingCharacters(in: .whitespacesAndNewlines)]); dismiss()
                        }
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Section {
                    Button("Dismiss", role: .destructive) { onDismissRequest(); dismiss() }
                }
            } else {
                Section { Text("No interaction pending").foregroundStyle(.secondary) }
            }

            // All agent notifications for this pane (newest first).
            Section("Agent notifications") {
                if updates.isEmpty {
                    Text("No notifications for this pane.").foregroundStyle(.secondary)
                } else {
                    ForEach(updates.reversed()) { update in updateRow(update) }
                }
            }
        }
        .modalList()
        .modalChrome("Interaction", systemImage: "bubble.left.and.bubble.right", width: 440, height: 520)
    }
}

// MARK: Activity

struct ActivityModalView: View {
    @Environment(\.dismiss) private var dismiss
    let updates: [SessionUpdate]

    // Read-only feed: no dismiss controls, just the close button.
    var body: some View {
        Group {
            if updates.isEmpty {
                ContentUnavailableView("No updates yet", systemImage: "list.bullet.rectangle",
                                       description: Text("Agent activity will show up here."))
            } else {
                List {
                    ForEach(updates.reversed()) { update in updateRow(update) }
                }
                .modalList()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .modalChrome("Agent Activity", systemImage: "list.bullet.rectangle", width: 440, height: 460)
    }
}

// MARK: Scryer picker

/// Two-column Scryer screen, mirroring gateway-ui's picker: a narrow projects column on
/// the left and a wider tickets column (with descriptions) on the right. Each column has
/// its own search; tickets sort by last-updated. Picking sends `/pp` (+ optional `/tp`).
struct ScryerPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let backendId: String
    let endpoint: GatewayEndpoint
    let onSend: (String) -> Void

    @State private var projects: [PmProject] = []
    @State private var tasks: [PmTask] = []
    @State private var selectedProject: PmProject?
    @State private var selectedTask: PmTask?
    @State private var projectQuery = ""
    @State private var taskQuery = ""
    @State private var expandedTaskIds: Set<String> = []
    @State private var loadingProjects = true
    @State private var loadingTasks = false
    @State private var error: String?

    private var filteredProjects: [PmProject] {
        let q = projectQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return projects }
        return projects.filter { "\($0.name) \($0.slug ?? "") \($0.relative_repo_path ?? "")".lowercased().contains(q) }
    }
    private var filteredTasks: [PmTask] {
        let q = taskQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return tasks }
        return tasks.filter { "\($0.title) \($0.status ?? "") \($0.description_md ?? "")".lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            panelHeader
            Divider()
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.red.opacity(0.08))
            }
            HStack(spacing: 0) {
                projectsColumn.frame(width: 248)
                Divider()
                ticketsColumn.frame(maxWidth: .infinity)
            }
            Divider()
            actionBar
        }
        .background(.background)
        #if os(macOS)
        .frame(width: 760, height: 540)
        #endif
        .task { await loadProjects() }
    }

    private var panelHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.3.group").foregroundStyle(.secondary)
            Text("Scryer").font(.headline)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .overlay(Circle().stroke(.secondary.opacity(0.45), lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    // MARK: Projects column

    private var projectsColumn: some View {
        VStack(spacing: 0) {
            columnHeader("Projects", text: $projectQuery, placeholder: "Search projects…", enabled: true)
            Divider()
            ScrollView {
                LazyVStack(spacing: 3) {
                    if loadingProjects { ProgressView().padding(.top, 24) }
                    else if filteredProjects.isEmpty { emptyNote("No projects.") }
                    ForEach(filteredProjects) { project in projectRow(project) }
                }
                .padding(8)
            }
        }
        .background(Color.primary.opacity(0.03))
    }

    private func projectRow(_ project: PmProject) -> some View {
        let selected = selectedProject?.id == project.id
        return Button {
            selectedProject = project; selectedTask = nil; taskQuery = ""; tasks = []
            Task { await loadTasks(project) }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name).font(.subheadline.weight(.medium)).lineLimit(1)
                let sub = [project.slug, project.relative_repo_path].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                if !sub.isEmpty { Text(sub).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(selected ? Color.accentColor.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Tickets column

    private var ticketsColumn: some View {
        VStack(spacing: 0) {
            columnHeader(selectedProject?.name ?? "Tickets", text: $taskQuery,
                         placeholder: selectedProject == nil ? "Select a project first…" : "Search tickets…",
                         enabled: selectedProject != nil)
            Divider()
            ScrollView {
                LazyVStack(spacing: 6) {
                    if selectedProject == nil { emptyNote("Select a project to load tickets.") }
                    else if loadingTasks { ProgressView().padding(.top, 24) }
                    else if filteredTasks.isEmpty { emptyNote("No tickets found.") }
                    ForEach(filteredTasks) { task in ticketRow(task) }
                }
                .padding(10)
            }
        }
    }

    private func ticketRow(_ task: PmTask) -> some View {
        let selected = selectedTask?.id == task.id
        let expanded = expandedTaskIds.contains(task.id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(task.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Spacer(minLength: 8)
                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
            }
            HStack(spacing: 8) {
                statusPill(task.status)
                if let when = shortUpdated(task.updated_at) {
                    Text(when).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            if let desc = task.description_md?.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty {
                Text(desc).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(expanded ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
                if desc.count > 140 {
                    Button(expanded ? "Collapse" : "Expand") { toggleExpanded(task.id) }
                        .font(.caption2.weight(.medium)).buttonStyle(.plain).foregroundStyle(.tint)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { selectedTask = task }
    }

    // MARK: Action bar

    private var actionBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                if let project = selectedProject {
                    Text(project.name).font(.caption.weight(.medium)).lineLimit(1)
                    Text(selectedTask?.title ?? "No ticket — sets project only").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text("Select a project").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Set") {
                if let project = selectedProject { onSend("/pp \(project.id)\r") }
                if let task = selectedTask { onSend("/tp \(task.id)\r") }
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedProject == nil)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    // MARK: Pieces

    private func columnHeader(_ title: String, text: Binding<String>, placeholder: String, enabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.caption2).foregroundStyle(.tertiary)
                TextField(placeholder, text: text).textFieldStyle(.plain).font(.caption).disabled(!enabled)
                    #if os(iOS)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                    #endif
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    private func statusPill(_ status: String?) -> some View {
        let raw = (status ?? "unknown")
        let label = raw.replacingOccurrences(of: "_", with: " ")
        let color = statusColor(raw)
        return Text(label.capitalized)
            .font(.caption2.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.16), in: Capsule())
    }

    private func statusColor(_ status: String) -> Color {
        let s = status.lowercased()
        if s.contains("closed") || s.contains("done") || s.contains("complete") { return .green }
        if s.contains("progress") || s.contains("review") || s.contains("open") { return .blue }
        if s.contains("block") { return .red }
        if s.contains("unopened") || s.contains("backlog") { return .gray }
        return .orange
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center).padding(.top, 24)
    }

    private func shortUpdated(_ iso: String?) -> String? {
        guard let iso, !iso.isEmpty else { return nil }
        return "updated " + String(iso.prefix(10))
    }

    private func toggleExpanded(_ id: String) {
        if expandedTaskIds.contains(id) { expandedTaskIds.remove(id) } else { expandedTaskIds.insert(id) }
    }

    // MARK: Data

    private func loadProjects() async {
        loadingProjects = true; defer { loadingProjects = false }
        do { projects = try await GatewayClient(endpoint: endpoint).pmProjects(backendId: backendId).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }
        catch { self.error = error.localizedDescription }
    }
    private func loadTasks(_ project: PmProject) async {
        loadingTasks = true; defer { loadingTasks = false }
        do {
            let loaded = try await GatewayClient(endpoint: endpoint).pmTasks(backendId: backendId, projectId: project.id)
            // Newest-updated first (ISO-8601 strings sort lexicographically; missing → last).
            tasks = loaded.sorted { ($0.updated_at ?? "") > ($1.updated_at ?? "") }
        }
        catch { self.error = error.localizedDescription }
    }
}

#if os(iOS)
/// Hosts the Scryer screen as a centered panel filling 85% of the display with almost no
/// corner rounding — presented inside a transparent `fullScreenCover` so we control the
/// size and shape (a system sheet can't be sized to 85% width on iPad in iOS 17).
struct ScryerCover<Content: View>: View {
    @Binding var isPresented: Bool
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.4).ignoresSafeArea()
                    .onTapGesture { isPresented = false }
                content
                    .frame(width: geo.size.width * 0.85, height: geo.size.height * 0.85)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(.black.opacity(0.18)))
                    .shadow(color: .black.opacity(0.4), radius: 30)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
/// Centered, near-full-height panel for compact utility modals. Unlike `ScryerCover`, this
/// keeps a fixed readable width while avoiding iPad's bottom-attached sheet detents.
struct CenteredModalCover<Content: View>: View {
    @Binding var isPresented: Bool
    let width: CGFloat
    var heightRatio: CGFloat = 0.92
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.4).ignoresSafeArea()
                    .onTapGesture { isPresented = false }
                content
                    .frame(width: min(width, geo.size.width * 0.92), height: geo.size.height * heightRatio)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(.black.opacity(0.18)))
                    .shadow(color: .black.opacity(0.4), radius: 30)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
#endif

// MARK: Shared

private func modalHeader(_ title: String, systemImage: String, onClose: @escaping () -> Void) -> some View {
    HStack(spacing: 8) {
        Image(systemName: systemImage).foregroundStyle(.secondary)
        Text(title).font(.headline)
        Spacer()
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 28, height: 28)
                .overlay(Circle().stroke(.secondary.opacity(0.45), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain).foregroundStyle(.secondary)
        .accessibilityLabel("Close")
    }
    .padding(.horizontal, 16).padding(.vertical, 12)
}

@ViewBuilder
private func updateRow(_ update: SessionUpdate) -> some View {
    VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 6) {
            Circle().fill(levelColor(update.level)).frame(width: 6, height: 6)
            Text(update.kind).font(.caption.weight(.medium)).foregroundStyle(.secondary)
        }
        Text(update.title).font(.subheadline.weight(.medium))
        if !update.body.isEmpty { Text(update.body).font(.caption).foregroundStyle(.secondary) }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}

private func levelColor(_ level: String?) -> Color {
    switch level {
    case "success": return .green
    case "warning": return .yellow
    case "error": return .red
    default: return .blue
    }
}

extension View {
    /// Wraps modal content in platform-native chrome: a `NavigationStack` with an inline
    /// title + a close button and native sheet detents on iOS; the custom title bar +
    /// fixed window size on macOS.
    func modalChrome(_ title: String, systemImage: String = "rectangle", width: CGFloat, height: CGFloat,
                     detents: Set<PresentationDetent> = [.large, .medium]) -> some View {
        modifier(ModalChrome(title: title, systemImage: systemImage, width: width, height: height, detents: detents))
    }

    /// Native grouped list styling for modal content.
    @ViewBuilder
    func modalList() -> some View {
        #if os(iOS)
        listStyle(.insetGrouped)
        #else
        listStyle(.inset)
        #endif
    }
}

private struct ModalChrome: ViewModifier {
    let title: String
    let systemImage: String
    let width: CGFloat
    let height: CGFloat
    let detents: Set<PresentationDetent>
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        #if os(iOS)
        VStack(spacing: 0) {
            modalHeader(title, systemImage: systemImage) { dismiss() }
            Divider()
            content
        }
        .background(.background)
        .presentationDetents(detents)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(6)   // square off the system sheet's large default radius
        #else
        VStack(spacing: 0) {
            modalHeader(title, systemImage: systemImage) { dismiss() }
            Divider()
            content
        }
        .frame(width: width, height: height)
        #endif
    }
}
