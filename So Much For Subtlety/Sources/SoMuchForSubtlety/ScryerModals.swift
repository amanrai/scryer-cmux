import SwiftUI
import ScryerCore

// MARK: Interaction

struct InteractionModalView: View {
    @Environment(\.dismiss) private var dismiss
    let request: InteractionRequest
    let updates: [SessionUpdate]
    let onRespond: ([String: Any]) -> Void
    let onDismissRequest: () -> Void

    @State private var composing = false
    @State private var draft = ""

    private var recentUpdates: [SessionUpdate] { Array(updates.suffix(2)) }

    var body: some View {
        List {
            if !recentUpdates.isEmpty {
                Section("Recent activity") {
                    ForEach(recentUpdates) { update in updateRow(update) }
                }
            }

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
                    Button("Send") {
                        onRespond(["kind": "custom", "text": draft.trimmingCharacters(in: .whitespacesAndNewlines)]); dismiss()
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Section {
                Button("Dismiss", role: .destructive) { onDismissRequest(); dismiss() }
            }
        }
        .modalList()
        .modalChrome("Interaction", systemImage: "bubble.left.and.bubble.right", width: 440, height: 460)
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
        .modalChrome("Agent Activity", systemImage: "list.bullet.rectangle", width: 440, height: 460)
    }
}

// MARK: Scryer picker

struct ScryerPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let backendId: String
    let endpoint: GatewayEndpoint
    let onSend: (String) -> Void

    @State private var projects: [PmProject] = []
    @State private var tasks: [PmTask] = []
    @State private var selectedProject: PmProject?
    @State private var selectedTask: PmTask?
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        List {
            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
            Section("Project") {
                if loading && projects.isEmpty { ProgressView() }
                ForEach(projects) { project in
                    pickRow(project.name, subtitle: project.slug ?? project.id, selected: selectedProject?.id == project.id) {
                        selectedProject = project; selectedTask = nil; Task { await loadTasks(project) }
                    }
                }
            }
            if selectedProject != nil {
                Section("Ticket") {
                    if tasks.isEmpty { Text("No tickets").foregroundStyle(.secondary) }
                    ForEach(tasks) { task in
                        pickRow(task.title, subtitle: task.status ?? "", selected: selectedTask?.id == task.id) { selectedTask = task }
                    }
                }
            }
            Section {
                Button("Set project & ticket") {
                    if let project = selectedProject { onSend("/pp \(project.id)\r") }
                    if let task = selectedTask { onSend("/tp \(task.id)\r") }
                    dismiss()
                }
                .disabled(selectedProject == nil)
            }
        }
        .modalList()
        .modalChrome("Scryer Picker", systemImage: "rectangle.3.group", width: 620, height: 460)
        .task { await loadProjects() }
    }

    private func pickRow(_ title: String, subtitle: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).lineLimit(1)
                    if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer()
                if selected { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func loadProjects() async {
        loading = true; defer { loading = false }
        do { projects = try await GatewayClient(endpoint: endpoint).pmProjects(backendId: backendId).sorted { $0.name < $1.name } }
        catch { self.error = error.localizedDescription }
    }
    private func loadTasks(_ project: PmProject) async {
        do { tasks = try await GatewayClient(endpoint: endpoint).pmTasks(backendId: backendId, projectId: project.id) }
        catch { self.error = error.localizedDescription }
    }
}

// MARK: Shared

private func modalHeader(_ title: String, systemImage: String, onClose: @escaping () -> Void) -> some View {
    HStack(spacing: 8) {
        Image(systemName: systemImage).foregroundStyle(.secondary)
        Text(title).font(.headline)
        Spacer()
        Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)) }
            .buttonStyle(.plain).foregroundStyle(.secondary)
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
    /// title + a Done button and native sheet detents on iOS; the custom title bar +
    /// fixed window size on macOS.
    func modalChrome(_ title: String, systemImage: String = "rectangle", width: CGFloat, height: CGFloat) -> some View {
        modifier(ModalChrome(title: title, systemImage: systemImage, width: width, height: height))
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
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        #if os(iOS)
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }.fontWeight(.semibold)
                    }
                }
        }
        .presentationDetents([.large, .medium])
        .presentationDragIndicator(.visible)
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
