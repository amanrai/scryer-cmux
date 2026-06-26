import SwiftUI
import Foundation
import ScryerCore

/// Task detail panel — slides in from the right over the board (app-specific chrome, *not*
/// an iOS system sheet). Reads the live task from the board model, so it refreshes on the
/// same cycle as the board. Edit title / status / description, or delete. Never drills.
struct KanbanerDetailView: View {
    let taskId: String
    let board: KanbanerModel
    let fg: Color
    let panelBg: Color
    let onClose: () -> Void

    @State private var title = ""
    @State private var desc = ""
    @State private var editingTitle = false
    @State private var editingDesc = false
    @State private var confirmDelete = false
    @State private var seeded = false
    @FocusState private var titleFocused: Bool

    private var task: PmTask? { board.tasks.first { $0.id == taskId } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(fg.opacity(0.1))
            if let task {
                ScrollView { content(task) }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "trash").font(.system(size: 22)).foregroundStyle(fg.opacity(0.5))
                    Text("Task removed").font(.system(size: 13, weight: .medium)).foregroundStyle(fg.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
        .background(panelBg)
        .overlay(alignment: .leading) { Rectangle().fill(fg.opacity(0.12)).frame(width: 1) }
        .shadow(color: .black.opacity(0.28), radius: 18, x: -6, y: 0)
        .onAppear { seed() }
        .onChange(of: taskId) { _, _ in seeded = false; seed() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let task { statusMenu(task) }
            if let task, let type = board.taskType(for: task) {
                Text(type.name).font(.system(size: 11)).foregroundStyle(fg.opacity(0.55)).lineLimit(1)
            }
            Spacer()
            deleteControl
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(fg.opacity(0.6)).frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func content(_ task: PmTask) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title — display text; tap to edit (matches the description + loom).
            if editingTitle {
                TextField("Title", text: $title, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(fg)
                    .focused($titleFocused)
                    .onSubmit { commitTitle(task) }
                actionRow(save: { commitTitle(task) }, cancel: { title = task.title; editingTitle = false })
            } else {
                Text(task.title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(fg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { title = task.title; editingTitle = true; titleFocused = true }
            }

            // Tags
            if let tags = task.tags, !tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(tags.prefix(6)), id: \.self) { tag in
                        Text(tag.name).font(.system(size: 11)).foregroundStyle(.tint)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(fg.opacity(0.08), in: Capsule())
                    }
                }
            }

            // Collapsible sections, mirroring loom's StoneDetail.
            DetailSection(title: "Description", fg: fg) { descriptionBody(task) }

            DetailSection(title: "Comments", fg: fg) {
                CommentsSection(taskId: task.id, endpoint: board.endpoint, fg: fg)
            }

            if let updated = task.updated_at {
                Text("Updated \(updated)")
                    .font(.system(size: 11).monospaced()).foregroundStyle(fg.opacity(0.35))
                    .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func descriptionBody(_ task: PmTask) -> some View {
        if editingDesc {
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $desc)
                    .font(.system(size: 13).monospaced())
                    .frame(minHeight: 180)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(fg.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor.opacity(0.5)))
                actionRow(save: { commitDesc(task) }, cancel: { desc = task.description_md ?? ""; editingDesc = false })
            }
        } else {
            Group {
                if (task.description_md ?? "").isEmpty {
                    Text("Tap to add a description…").font(.system(size: 13)).italic().foregroundStyle(fg.opacity(0.4))
                } else {
                    MarkdownText(text: task.description_md ?? "", fg: fg)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { desc = task.description_md ?? ""; editingDesc = true }
        }
    }

    private func actionRow(save: @escaping () -> Void, cancel: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Spacer()
            Button("Cancel", action: cancel).buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(fg.opacity(0.6))
            Button("Save", action: save).buttonStyle(.borderedProminent).controlSize(.small)
        }
    }

    private func statusMenu(_ task: PmTask) -> some View {
        Menu {
            ForEach(KanbanerModel.statusOrder, id: \.self) { status in
                Button { save(task, fields: ["status": status]) } label: {
                    if (task.status ?? "unopened") == status { Label(KanbanerModel.label(status), systemImage: "checkmark") }
                    else { Text(KanbanerModel.label(status)) }
                }
            }
        } label: {
            let status = task.status ?? "unopened"
            HStack(spacing: 6) {
                Circle().fill(Color(hex: KanbanerModel.colorHex(status)) ?? .gray).frame(width: 8, height: 8)
                Text(KanbanerModel.label(status)).font(.system(size: 12, weight: .medium)).foregroundStyle(fg)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8)).foregroundStyle(fg.opacity(0.4))
            }
        }
        .fixedSize()
    }

    @ViewBuilder private var deleteControl: some View {
        if confirmDelete {
            HStack(spacing: 6) {
                Text("Delete?").font(.system(size: 11)).foregroundStyle(.red)
                Button("Yes", role: .destructive) { Task { await board.delete(taskId: taskId); onClose() } }
                    .buttonStyle(.borderless).font(.system(size: 11))
                Button("No") { confirmDelete = false }.buttonStyle(.borderless).font(.system(size: 11)).foregroundStyle(fg.opacity(0.6))
            }
        } else {
            Button(role: .destructive) { confirmDelete = true } label: {
                Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(fg.opacity(0.55))
                    .frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func seed() {
        guard !seeded, let task else { return }
        title = task.title
        desc = task.description_md ?? ""
        editingTitle = false
        editingDesc = false
        seeded = true
    }
    private func commitTitle(_ task: PmTask) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        titleFocused = false
        editingTitle = false
        guard !trimmed.isEmpty, trimmed != task.title else { return }
        save(task, fields: ["title": trimmed])
    }
    private func commitDesc(_ task: PmTask) {
        editingDesc = false
        guard desc != (task.description_md ?? "") else { return }
        save(task, fields: ["description_md": desc])
    }
    private func save(_ task: PmTask, fields: [String: String]) {
        Task { await board.update(taskId: task.id, fields: fields) }
    }
}

// MARK: - Sections

/// Collapsible titled section (loom's StoneDetail Section), with a top divider.
private struct DetailSection<Content: View>: View {
    let title: String
    let fg: Color
    @ViewBuilder var content: () -> Content
    @State private var open: Bool

    init(title: String, fg: Color, defaultOpen: Bool = true, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.fg = fg
        self.content = content
        _open = State(initialValue: defaultOpen)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(fg.opacity(0.08)).frame(height: 1)
            Button { withAnimation(.easeInOut(duration: 0.15)) { open.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: open ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                    Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.8)
                }
                .foregroundStyle(fg.opacity(0.5))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open { content() }
        }
        .padding(.top, 6)
    }
}

/// Task comments: add at the top, list newest-first, edit/delete inline, markdown-rendered.
private struct CommentsSection: View {
    let taskId: String
    let endpoint: PmEndpoint
    let fg: Color

    @State private var comments: [PmComment] = []
    @State private var draft = ""
    @State private var editingId: String?
    @State private var editDraft = ""
    @FocusState private var inputFocused: Bool

    private var client: PmClient { PmClient(endpoint: endpoint) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Input on top (newest-first).
            VStack(alignment: .trailing, spacing: 6) {
                TextEditor(text: $draft)
                    .font(.system(size: 13))
                    .frame(minHeight: 54)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(fg.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(fg.opacity(0.12)))
                    .focused($inputFocused)
                Button("Comment") { Task { await submit() } }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if comments.isEmpty {
                Text("No comments yet.").font(.system(size: 12)).foregroundStyle(fg.opacity(0.4))
            } else {
                ForEach(comments.reversed()) { comment in row(comment) }   // newest on top
            }
        }
        .task(id: taskId) {
            // Poll so comments stay live as the agent posts (drafts/edits are separate state).
            while !Task.isCancelled {
                await reload()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func row(_ comment: PmComment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(comment.authorLabel).font(.system(size: 11, weight: .medium)).foregroundStyle(fg.opacity(0.6))
                Spacer()
                Text(Self.timeAgo(comment.created_at)).font(.system(size: 11)).foregroundStyle(fg.opacity(0.4))
                Button("edit") { editingId = comment.id; editDraft = comment.body_md ?? "" }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(fg.opacity(0.5))
                Button("delete") { Task { await delete(comment.id) } }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(fg.opacity(0.5))
            }
            if editingId == comment.id {
                TextEditor(text: $editDraft)
                    .font(.system(size: 13)).frame(minHeight: 54).scrollContentBackground(.hidden)
                    .padding(8).background(fg.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor.opacity(0.5)))
                HStack(spacing: 8) {
                    Spacer()
                    Button("Cancel") { editingId = nil }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(fg.opacity(0.6))
                    Button("Save") { Task { await saveEdit(comment.id) } }.buttonStyle(.borderedProminent).controlSize(.small)
                }
            } else {
                MarkdownText(text: comment.body_md ?? "", fg: fg)
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(fg.opacity(0.08)).frame(height: 1) }
    }

    // MARK: Data
    private func reload() async { comments = (try? await client.comments(taskId: taskId)) ?? [] }
    private func submit() async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        draft = ""; inputFocused = false
        _ = try? await client.createComment(taskId: taskId, bodyMd: body)
        await reload()
    }
    private func saveEdit(_ id: String) async {
        let body = editDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        editingId = nil
        guard !body.isEmpty else { return }
        _ = try? await client.updateComment(id: id, bodyMd: body)
        await reload()
    }
    private func delete(_ id: String) async {
        comments.removeAll { $0.id == id }
        try? await client.deleteComment(id: id)
        await reload()
    }

    static func timeAgo(_ string: String?) -> String {
        guard let string else { return "" }
        let normalized = (string.hasSuffix("Z") || string.contains("+")) ? string : string + "Z"
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        guard let date = fractional.date(from: normalized) ?? plain.date(from: normalized) else { return "" }
        let minutes = Int(Date().timeIntervalSince(date) / 60)
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }
}

// MARK: - Markdown rendering

/// Lightweight block-level markdown renderer (headings, lists, code fences, quotes, rules,
/// paragraphs) with inline emphasis via `AttributedString`. Enough to render PM task
/// descriptions properly, matching loom's `renderMarkdown` output in spirit.
struct MarkdownText: View {
    let text: String
    let fg: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(MarkdownBlock.parse(text).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(.system(size: headingSize(level), weight: .bold))
                .foregroundStyle(fg)
                .padding(.top, level <= 2 ? 4 : 0)
        case .paragraph(let text):
            Text(inline(text)).font(.system(size: 13)).foregroundStyle(fg.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        case .bullet(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").font(.system(size: 13)).foregroundStyle(fg.opacity(0.6))
                        Text(inline(item)).font(.system(size: 13)).foregroundStyle(fg.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .ordered(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1).").font(.system(size: 13).monospacedDigit()).foregroundStyle(fg.opacity(0.6))
                        Text(inline(item)).font(.system(size: 13)).foregroundStyle(fg.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .code(let code):
            Text(code)
                .font(.system(size: 12).monospaced())
                .foregroundStyle(fg.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(fg.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                .textSelection(.enabled)
        case .quote(let text):
            HStack(spacing: 8) {
                Rectangle().fill(fg.opacity(0.25)).frame(width: 3)
                Text(inline(text)).font(.system(size: 13)).italic().foregroundStyle(fg.opacity(0.7))
            }
            .fixedSize(horizontal: false, vertical: true)
        case .rule:
            Rectangle().fill(fg.opacity(0.12)).frame(height: 1).padding(.vertical, 2)
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level { case 1: return 18; case 2: return 16; case 3: return 14; default: return 13 }
    }

    private func inline(_ string: String) -> AttributedString {
        (try? AttributedString(markdown: string,
                               options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(string)
    }
}

/// A parsed markdown block.
enum MarkdownBlock {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet([String])
    case ordered([String])
    case code(String)
    case quote(String)
    case rule

    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = text.components(separatedBy: "\n")
        var paragraph: [String] = []
        func flushParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))); paragraph = [] }
        }

        var i = 0
        while i < lines.count {
            let raw = lines[i]
            let line = raw.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {                      // fenced code block
                flushParagraph()
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i]); i += 1
                }
                blocks.append(.code(code.joined(separator: "\n")))
                i += 1                                       // skip closing fence
                continue
            }
            if line.isEmpty { flushParagraph(); i += 1; continue }
            if line == "---" || line == "***" || line == "___" { flushParagraph(); blocks.append(.rule); i += 1; continue }
            if let heading = headingLevel(line) { flushParagraph(); blocks.append(.heading(level: heading.0, text: heading.1)); i += 1; continue }
            if line.hasPrefix(">") {
                flushParagraph()
                let body = line.hasPrefix("> ") ? String(line.dropFirst(2)) : String(line.dropFirst())
                blocks.append(.quote(body)); i += 1; continue
            }
            if isBullet(line) {
                flushParagraph()
                var items: [String] = []
                while i < lines.count, isBullet(lines[i].trimmingCharacters(in: .whitespaces)) {
                    items.append(String(lines[i].trimmingCharacters(in: .whitespaces).dropFirst(2))); i += 1
                }
                blocks.append(.bullet(items)); continue
            }
            if isOrdered(line) {
                flushParagraph()
                var items: [String] = []
                while i < lines.count, isOrdered(lines[i].trimmingCharacters(in: .whitespaces)) {
                    items.append(orderedText(lines[i].trimmingCharacters(in: .whitespaces))); i += 1
                }
                blocks.append(.ordered(items)); continue
            }
            paragraph.append(line); i += 1
        }
        flushParagraph()
        return blocks
    }

    private static func headingLevel(_ s: String) -> (Int, String)? {
        let level = s.prefix { $0 == "#" }.count
        guard level >= 1, level <= 6 else { return nil }
        let rest = s.dropFirst(level)
        guard rest.first == " " else { return nil }
        return (level, String(rest.dropFirst()).trimmingCharacters(in: .whitespaces))
    }
    private static func isBullet(_ s: String) -> Bool { s.hasPrefix("- ") || s.hasPrefix("* ") || s.hasPrefix("+ ") }
    private static func isOrdered(_ s: String) -> Bool {
        guard let dot = s.firstIndex(of: ".") else { return false }
        let number = s[s.startIndex..<dot]
        guard !number.isEmpty, number.allSatisfy(\.isNumber) else { return false }
        let after = s.index(after: dot)
        return after < s.endIndex && s[after] == " "
    }
    private static func orderedText(_ s: String) -> String {
        guard let dot = s.firstIndex(of: ".") else { return s }
        return String(s[s.index(after: dot)...]).trimmingCharacters(in: .whitespaces)
    }
}
