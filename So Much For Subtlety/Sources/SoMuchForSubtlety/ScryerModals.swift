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
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !recentUpdates.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(recentUpdates) { update in updateRow(update) }
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(request.payload.title ?? "Input needed").font(.system(size: 14, weight: .semibold))
                        if let body = request.payload.body, !body.isEmpty {
                            Text(body).font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                    VStack(spacing: 6) {
                        ForEach(request.payload.choices ?? []) { choice in
                            Button {
                                if choice.custom == true { composing = true }
                                else { onRespond(["kind": "choice", "choiceId": choice.id, "text": choice.send ?? choice.label]); dismiss() }
                            } label: {
                                HStack {
                                    Text(choice.label).font(.system(size: 13))
                                    Spacer()
                                    Image(systemName: "arrow.right").font(.system(size: 11)).foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 9)
                                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        Button { composing = true } label: {
                            HStack { Image(systemName: "keyboard"); Text("Type response…").font(.system(size: 13)); Spacer() }
                                .padding(.horizontal, 12).padding(.vertical, 9)
                                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if composing {
                        TextEditor(text: $draft)
                            .font(.system(size: 13, design: .monospaced)).frame(height: 90)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                        HStack {
                            Spacer()
                            Button("Send") { onRespond(["kind": "custom", "text": draft.trimmingCharacters(in: .whitespacesAndNewlines)]); dismiss() }
                                .buttonStyle(.borderedProminent)
                                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                .padding(16)
            }
            Divider()
            HStack {
                Button("Dismiss", role: .destructive) { onDismissRequest(); dismiss() }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
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
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(updates.reversed()) { update in updateRow(update) }
                    }
                    .padding(16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        VStack(alignment: .leading, spacing: 0) {
            if let error { Text(error).font(.system(size: 11)).foregroundStyle(.red).padding(12) }
            HStack(spacing: 0) {
                column(title: "Projects") {
                    ForEach(projects) { project in
                        pickRow(project.name, project.slug ?? project.id, selected: selectedProject?.id == project.id) {
                            selectedProject = project; selectedTask = nil; Task { await loadTasks(project) }
                        }
                    }
                    if loading && projects.isEmpty { ProgressView().padding() }
                }
                Divider()
                column(title: selectedProject?.name ?? "Tickets") {
                    if selectedProject == nil {
                        Text("Select a project").font(.system(size: 11)).foregroundStyle(.secondary).padding()
                    }
                    ForEach(tasks) { task in
                        pickRow(task.title, task.status ?? "", selected: selectedTask?.id == task.id) { selectedTask = task }
                    }
                }
            }
            Divider()
            HStack {
                if let project = selectedProject { Text("Project: \(project.name)").font(.system(size: 11)).foregroundStyle(.secondary) }
                Spacer()
                Button("Set") {
                    if let project = selectedProject { onSend("/pp \(project.id)\r") }
                    if let task = selectedTask { onSend("/tp \(task.id)\r") }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedProject == nil)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .modalChrome("Scryer Picker", systemImage: "rectangle.3.group", width: 620, height: 460)
        .task { await loadProjects() }
    }

    private func column<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            ScrollView { VStack(alignment: .leading, spacing: 2) { content() }.padding(8) }
        }
        .frame(maxWidth: .infinity)
    }

    private func pickRow(_ title: String, _ subtitle: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                if !subtitle.isEmpty { Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(selected ? Color.accentColor.opacity(0.25) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
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
private func updateRow(_ update: SessionUpdate, onDismiss: (() -> Void)? = nil) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
            Circle().fill(levelColor(update.level)).frame(width: 6, height: 6)
            Text(update.kind).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            Spacer()
            if let onDismiss {
                Button(action: onDismiss) { Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(.tertiary).help("Dismiss update")
            }
        }
        Text(update.title).font(.system(size: 12, weight: .medium))
        if !update.body.isEmpty { Text(update.body).font(.system(size: 11)).foregroundStyle(.secondary) }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(10)
    .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
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
