import SwiftUI
import Foundation
import ScryerCore
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

/// The Kanbaner board: tasks for a PM project grouped into status columns. Drag a card
/// between columns to change its status (or within a column to reorder); tap a card to open
/// the right-sliding detail panel; drill into feature cards via the breadcrumb. Talks to the
/// PM system directly via `KanbanerModel`.
struct KanbanerView: View {
    @Environment(AppModel.self) private var model

    @State private var board: KanbanerModel?
    @State private var selection: CardSelection?
    @State private var addingStatus: String?
    @State private var addDraft = ""
    @State private var showingProjectPicker = false
    @State private var projectSearch = ""
    @State private var hiddenProjectsExpanded = false
    @State private var showingSettings = false
    @State private var showingBackendPicker = false
    @AppStorage("smfs.kanbanerDetailWidth") private var detailWidth: Double = 460
    @State private var dragStartWidth: Double?

    private static let minDetailWidth: Double = 340

    private struct CardSelection: Identifiable, Equatable { let id: String }

    // Theme-derived colors (work on any theme).
    private var bg: Color { Color(hex: model.theme.terminal.background.hex) ?? .black }
    private var chrome: Color { Color(hex: model.theme.terminal.chrome.hex) ?? .black }
    private var fg: Color { Color(hex: model.theme.terminal.foreground.hex) ?? .white }

    private func platformValue(_ ios: CGFloat, mac: CGFloat) -> CGFloat {
        #if os(iOS)
        ios
        #else
        mac
        #endif
    }
    private var columnWidth: CGFloat { platformValue(300, mac: 280) }
    private var chromeGlyph: CGFloat { platformValue(17, mac: 12) }
    private var chromeMinHeight: CGFloat { platformValue(48, mac: 36) }

    var body: some View {
        ZStack(alignment: .trailing) {
            VStack(spacing: 0) {
                topBar
                Divider().overlay(fg.opacity(0.08))
                if let board {
                    content(board)
                } else {
                    Spacer()
                    ProgressView().tint(fg)
                    Spacer()
                }
            }
            .background(bg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // App-specific detail panel: slides in from the right over the board (no iOS
            // system sheet). Reads live from the board model, so it refreshes on the same cycle.
            if let board, let sel = selection {
                detailOverlay(board: board, taskId: sel.id)
            }
        }
        #if os(macOS)
        .ignoresSafeArea(.container, edges: .top)
        #endif
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: selection)
        #if os(iOS)
        .fullScreenCover(isPresented: $showingSettings) {
            ScryerCover(isPresented: $showingSettings) {
                SettingsView(backendId: settingsBackendId, defaultMachineName: settingsBackendName).environment(model)
            }
            .presentationBackground(.clear)
        }
        #else
        .sheet(isPresented: $showingSettings) {
            SettingsView(backendId: settingsBackendId, defaultMachineName: settingsBackendName).environment(model)
        }
        #endif
        #if os(iOS)
        .fullScreenCover(isPresented: $showingBackendPicker) {
            CenteredModalCover(isPresented: $showingBackendPicker, width: 560, heightRatio: 0.56) {
                backendPicker
            }
            .presentationBackground(.clear)
        }
        #else
        .sheet(isPresented: $showingBackendPicker) { backendPicker }
        #endif
        .task {
            if board == nil {
                let created = KanbanerModel(endpoint: model.pmEndpoint, initialProjectId: model.lastKanbanerProjectId)
                board = created
                await created.loadProjects()
                model.lastKanbanerProjectId = created.selectedProjectId
            }
        }
    }

    private var detailPanelBg: Color { chrome }

    @ViewBuilder private func detailOverlay(board: KanbanerModel, taskId: String) -> some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { selection = nil }
                .transition(.opacity)
            GeometryReader { geo in
                let maxWidth = geo.size.width * 0.95
                let width = min(max(detailWidth, Self.minDetailWidth), maxWidth)
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    // Sibling handle (left of the panel, in the dim margin) so the drag
                    // doesn't fight the panel's scroll view.
                    resizeHandle(maxWidth: maxWidth)
                    KanbanerDetailView(taskId: taskId, board: board, fg: fg, panelBg: detailPanelBg) { selection = nil }
                        .frame(width: width)
                        .frame(maxHeight: .infinity)
                }
            }
            .transition(.move(edge: .trailing))
        }
        .dismissOnEscape { selection = nil }
        #if os(macOS)
        .background(WindowBackgroundDragSetter(isMovable: false))
        #endif
    }

    /// Drag handle just left of the detail panel; width is persisted live.
    private func resizeHandle(maxWidth: Double) -> some View {
        ZStack {
            Color.black.opacity(0.001)                 // wide, grabbable hit area
            Capsule().fill(fg.opacity(0.35)).frame(width: 4, height: 44)
        }
        .frame(width: 18)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let start = dragStartWidth ?? detailWidth
                    if dragStartWidth == nil { dragStartWidth = start }
                    detailWidth = min(max(start - value.translation.width, Self.minDetailWidth), maxWidth)
                }
                .onEnded { _ in dragStartWidth = nil }
        )
        #if os(macOS)
        .onHover { inside in
            if inside { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() }
        }
        #endif
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: { showingBackendPicker = true }) {
                HStack(spacing: 5) {
                    Image(systemName: "rectangle.split.3x1").font(.system(size: chromeGlyph, weight: .semibold))
                    Text("Kanbaner").font(.system(size: 13, weight: .medium))
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 8)).foregroundStyle(fg.opacity(0.45))
                }
                .foregroundStyle(fg.opacity(0.85))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("k", modifiers: .command)
            .help("Select backend (⌘K)")

            Divider().frame(height: 14).overlay(fg.opacity(0.15))

            breadcrumb

            Spacer()

            if board?.loadingTasks == true || board?.loadingProjects == true {
                ProgressView().controlSize(.small).tint(fg)
            }
            Button(action: { Task { await board?.reload() } }) {
                Image(systemName: "arrow.clockwise").font(.system(size: chromeGlyph))
            }
            .buttonStyle(.plain).foregroundStyle(fg.opacity(0.7))
            .help("Refresh")

            Button(action: { showingSettings = true }) {
                Image(systemName: "gearshape").font(.system(size: chromeGlyph))
            }
            .buttonStyle(.plain).foregroundStyle(fg.opacity(0.7))
            .help("Settings")
        }
        #if os(macOS)
        .padding(.leading, 78)   // clear the traffic lights
        .padding(.top, 6)
        #else
        .padding(.leading, 14)
        #endif
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity, minHeight: chromeMinHeight, alignment: .leading)
        .background(chrome)
    }

    private var backendPicker: some View {
        MachinePickerSheet(currentBackendId: "", onSelect: { selected in
            model.showingKanbaner = false
            model.select(selected)
        }, kanbanerSelected: true, onKanbaner: {}, onProjectOrganizer: {
            model.showingKanbaner = false
            model.showingProjectOrganizer = true
        })
        .environment(model)
    }

    private var settingsBackendId: String {
        if case .attached(let backend) = model.phase { return backend.id }
        return model.selectedBackend?.id ?? ""
    }

    private var settingsBackendName: String {
        if case .attached(let backend) = model.phase { return backend.label }
        return model.selectedBackend?.label ?? "Backend"
    }

    /// Breadcrumb/navigation split: project name always opens project selection; a separate
    /// up control navigates within the current project's nested ticket hierarchy.
    @ViewBuilder private var breadcrumb: some View {
        if let board {
            HStack(spacing: 8) {
                projectSwitcher

                if board.navStack.count > 1 {
                    Button { board.navigate(to: max(0, board.navStack.count - 2)) } label: {
                        Image(systemName: "arrow.uturn.left")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(fg.opacity(0.65))
                            .frame(width: 26, height: 24)
                            .background(fg.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Back one level")

                    ForEach(Array(board.navStack.enumerated()).dropFirst(), id: \.element.id) { pair in
                        let index = pair.offset
                        let isLast = index == board.navStack.count - 1
                        if index > 1 {
                            Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(fg.opacity(0.3))
                        }
                        Button { board.navigate(to: index) } label: {
                            Text(pair.element.name)
                                .font(.system(size: 13, weight: isLast ? .semibold : .regular))
                                .foregroundStyle(isLast ? fg : fg.opacity(0.6))
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .disabled(isLast)
                    }
                }
            }
        }
    }

    /// Searchable project switcher. The whole project-name control opens the picker.
    @ViewBuilder private var projectSwitcher: some View {
        if let board {
            Button {
                projectSearch = ""
                hiddenProjectsExpanded = false
                showingProjectPicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.split.3x1").font(.system(size: 11, weight: .semibold))
                    Text(board.selectedProject?.name ?? "Project")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(fg.opacity(0.45))
                }
                .foregroundStyle(fg)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(fg.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingProjectPicker, arrowEdge: .top) {
                projectPicker(board)
            }
            .fixedSize()
        }
    }

    private func projectPicker(_ board: KanbanerModel) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search projects…", text: $projectSearch)
                    .textFieldStyle(.plain)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
            }
            .font(.system(size: 14))
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(fg.opacity(0.06))

            Divider().overlay(fg.opacity(0.08))

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filteredVisibleProjectNodes(board)) { node in
                        projectRow(node, board: board)
                    }
                    let hiddenNodes = filteredHiddenProjectNodes(board)
                    if !hiddenNodes.isEmpty {
                        hiddenProjectsDisclosure
                        if hiddenProjectsExpanded {
                            ForEach(hiddenNodes) { node in projectRow(node, board: board) }
                        }
                    }
                    if filteredProjectNodes(board).isEmpty {
                        Text("No matching projects")
                            .font(.system(size: 13))
                            .foregroundStyle(fg.opacity(0.5))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 360, height: 420)
        .background(bg)
        .dismissOnEscape { showingProjectPicker = false }
    }

    private func filteredProjectNodes(_ board: KanbanerModel) -> [KanbanerModel.ProjectNode] {
        let q = projectSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return board.projectTree }
        return board.projectTree.filter { node in
            let project = node.project
            return "\(project.name) \(project.slug ?? "") \(project.relative_repo_path ?? "")"
                .lowercased()
                .contains(q)
        }
    }

    private func filteredVisibleProjectNodes(_ board: KanbanerModel) -> [KanbanerModel.ProjectNode] {
        let q = projectSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return board.visibleProjectTree }
        return filteredProjectNodes(board).filter { !$0.hidden }
    }

    private func filteredHiddenProjectNodes(_ board: KanbanerModel) -> [KanbanerModel.ProjectNode] {
        let q = projectSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return board.hiddenProjectTree }
        return filteredProjectNodes(board).filter { $0.hidden }
    }

    private var hiddenProjectsDisclosure: some View {
        Button {
            hiddenProjectsExpanded.toggle()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: hiddenProjectsExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                Text("Hidden Projects")
                Spacer()
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(fg.opacity(0.48))
            .padding(.horizontal, 10).padding(.vertical, 7)
            .overlay(alignment: .top) { Divider().overlay(fg.opacity(0.08)) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func projectRow(_ node: KanbanerModel.ProjectNode, board: KanbanerModel) -> some View {
        let project = node.project
        let selected = project.id == board.selectedProjectId
        return Button {
            showingProjectPicker = false
            Task {
                await board.select(projectId: project.id)
                model.lastKanbanerProjectId = project.id
            }
        } label: {
            HStack(spacing: 10) {
                projectTreeGlyph(node)
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.system(size: node.depth > 0 ? 12 : 13, weight: .medium))
                        .foregroundStyle(fg.opacity(selected ? 1 : node.hidden ? 0.48 : node.depth > 0 ? 0.62 : 0.92))
                        .lineLimit(1)
                    if let subtitle = projectSubtitle(project) {
                        Text(subtitle)
                            .font(.system(size: 11).monospaced())
                            .foregroundStyle(fg.opacity(0.45))
                            .lineLimit(1)
                    }
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.tint)
                }
            }
            .padding(.leading, 10 + CGFloat(node.depth) * 16).padding(.trailing, 10).padding(.vertical, 8)
            .background(selected ? Color.accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func projectTreeGlyph(_ node: KanbanerModel.ProjectNode) -> some View {
        Text(node.depth > 0 ? "◈" : "▦")
            .font(.system(size: node.depth > 0 ? 10 : 11, weight: .semibold))
            .foregroundStyle(fg.opacity(node.hidden ? 0.36 : 0.46))
            .frame(width: 30, height: 30)
            .background(fg.opacity(node.depth == 0 ? 0.07 : 0.035), in: RoundedRectangle(cornerRadius: 7))
    }

    private func projectIcon(_ project: PmProject) -> some View {
        let symbol = projectSymbol(project)
        return Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.tint)
            .frame(width: 30, height: 30)
            .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
    }

    private func projectSymbol(_ project: PmProject) -> String {
        let haystack = "\(project.name) \(project.slug ?? "") \(project.relative_repo_path ?? "")".lowercased()
        if haystack.contains("ios") || haystack.contains("ipad") || haystack.contains("swift") { return "swift" }
        if haystack.contains("web") || haystack.contains("ui") || haystack.contains("frontend") { return "globe" }
        if haystack.contains("api") || haystack.contains("server") || haystack.contains("backend") { return "server.rack" }
        if haystack.contains("agent") || haystack.contains("ai") { return "sparkles" }
        if haystack.contains("doc") { return "doc.text" }
        return "folder"
    }

    private func projectSubtitle(_ project: PmProject) -> String? {
        let parts = [project.slug, project.relative_repo_path]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Board content

    @ViewBuilder private func content(_ board: KanbanerModel) -> some View {
        if let error = board.error, board.tasks.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.yellow)
                Text("Couldn't reach the PM system").font(.system(size: 13, weight: .medium)).foregroundStyle(fg)
                Text(error).font(.system(size: 11)).foregroundStyle(fg.opacity(0.6)).multilineTextAlignment(.center)
                Text(board.endpoint.displayHost).font(.system(size: 11).monospaced()).foregroundStyle(fg.opacity(0.4))
                Button("Retry") { Task { await board.loadProjects() } }.tint(fg)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else if board.selectedProjectId == nil {
            Text("No projects").foregroundStyle(fg.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(board.statuses, id: \.self) { status in
                        column(board, status: status)
                            .frame(width: columnWidth)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }

    private func column(_ board: KanbanerModel, status: String) -> some View {
        let cards = board.cards(in: status)
        let accent = Color(hex: KanbanerModel.colorHex(status)) ?? fg
        return VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Circle().fill(accent).frame(width: 7, height: 7)
                Text(KanbanerModel.label(status).uppercased())
                    .font(.system(size: 11, weight: .semibold)).tracking(0.6)
                    .foregroundStyle(fg.opacity(0.7))
                Text("\(cards.count)")
                    .font(.system(size: 11)).foregroundStyle(fg.opacity(0.5))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(fg.opacity(0.08), in: Capsule())
                Spacer()
                Button { startAdding(status) } label: {
                    Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain).foregroundStyle(fg.opacity(0.5))
                .help("New card")
            }
            .padding(.bottom, 8)
            .overlay(alignment: .bottom) { Rectangle().fill(fg.opacity(0.1)).frame(height: 1) }
            .padding(.bottom, 8)

            // Cards + drop target. Uses the system drag (onDrag/onDrop) rather than
            // `.draggable`, so a card drag isn't swallowed by the surrounding scroll views.
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    ForEach(cards) { task in
                        let feature = board.isFeature(task)
                        KanbanerCard(task: task, taskType: board.taskType(for: task), isFeature: feature,
                                     fg: fg, elevated: cardBg, onDrill: { board.drill(into: task) })
                            // Tap = Read (open the detail panel); never drills.
                            .onTapGesture { selection = CardSelection(id: task.id) }
                            .contextMenu {
                                Button { selection = CardSelection(id: task.id) } label: { Label("Read", systemImage: "book") }
                                if feature {
                                    Button { board.drill(into: task) } label: { Label("Open", systemImage: "folder") }
                                }
                            }
                            .onDrag { NSItemProvider(object: task.id as NSString) }
                            .onDrop(of: [.text], isTargeted: nil) { providers in
                                handleDrop(providers, board: board, status: status, before: task.id)
                            }
                    }

                    if cards.isEmpty && addingStatus != status && status != "unopened" {
                        Text("Drop here")
                            .font(.system(size: 11)).foregroundStyle(fg.opacity(0.35))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .background(RoundedRectangle(cornerRadius: 6).strokeBorder(fg.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4])))
                    }

                    // Add affordance lives below the last card. Unopened always shows a
                    // persistent "+ Add"; other columns only while actively adding (header +).
                    if addingStatus == status {
                        addCardField(board, status: status)
                    } else if status == "unopened" {
                        addButton(status: status)
                    }

                    Color.clear.frame(minHeight: 24)   // drop catch-area below the cards
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .onDrop(of: [.text], isTargeted: nil) { providers in
                handleDrop(providers, board: board, status: status, before: nil)
            }
        }
    }

    /// Resolve a dropped card id (loaded async off the item provider) and apply the move.
    private func handleDrop(_ providers: [NSItemProvider], board: KanbanerModel, status: String, before beforeId: String?) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let id = object as? String else { return }
            Task { @MainActor in await board.drop(taskId: id, into: status, before: beforeId) }
        }
        return true
    }

    private func addButton(status: String) -> some View {
        Button { startAdding(status) } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                Text("Add").font(.system(size: 12))
            }
            .foregroundStyle(fg.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 7).padding(.horizontal, 9)
            .background(RoundedRectangle(cornerRadius: 6).strokeBorder(fg.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [4])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var cardBg: Color { fg.opacity(0.06) }

    private func addCardField(_ board: KanbanerModel, status: String) -> some View {
        VStack(spacing: 6) {
            TextField("Card title…", text: $addDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(fg)
                .lineLimit(1...3)
                .onSubmit { commitAdd(board, status: status) }
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { cancelAdd() }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(fg.opacity(0.6))
                Button("Add") { commitAdd(board, status: status) }
                    .buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundStyle(.tint)
                    .disabled(addDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(10)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor.opacity(0.6)))
    }

    // MARK: Add-card flow

    private func startAdding(_ status: String) {
        addDraft = ""
        addingStatus = status
    }
    private func cancelAdd() {
        addingStatus = nil
        addDraft = ""
    }
    private func commitAdd(_ board: KanbanerModel, status: String) {
        let title = addDraft
        cancelAdd()
        Task { await board.create(title: title, status: status) }
    }
}

/// One card on the board: status/type swatch, title, tags. Feature cards (those with
/// children) get a drill affordance that opens their sub-board.
private struct KanbanerCard: View {
    let task: PmTask
    let taskType: PmTaskType?
    let isFeature: Bool
    let fg: Color
    let elevated: Color
    let onDrill: () -> Void

    private var accent: Color {
        if let hex = taskType?.color, let c = Color(hex: hex) { return c }
        return Color(hex: KanbanerModel.colorHex(task.status ?? "unopened")) ?? fg
    }

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2).fill(accent).frame(width: 3)
                .padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(fg)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                if let tags = task.tags, !tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(Array(tags.prefix(3)), id: \.self) { tag in
                            Text(tag.name)
                                .font(.system(size: 10))
                                .foregroundStyle(.tint)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(fg.opacity(0.07), in: RoundedRectangle(cornerRadius: 3))
                        }
                        if tags.count > 3 {
                            Text("+\(tags.count - 3)").font(.system(size: 10)).foregroundStyle(fg.opacity(0.4))
                        }
                    }
                }
            }
            .padding(.leading, 10).padding(.trailing, isFeature ? 4 : 12).padding(.vertical, 9)
            Spacer(minLength: 0)
            if isFeature {
                // Drill into this feature's children (loom's "Open"); square-grid hints sub-tickets.
                Button(action: onDrill) {
                    Image(systemName: "rectangle.grid.1x2")
                        .font(.system(size: 12))
                        .foregroundStyle(fg.opacity(0.6))
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open sub-tickets")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(elevated, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(fg.opacity(0.1)))
        .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}
