#if os(macOS)
import SwiftUI

struct IssueDetailView: View {
    @Environment(AppModel.self) private var model
    var item: Item

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(model.conflict(for: item)) { entry in
                            ConflictBanner(entry: entry)
                        }
                        TitleField(item: item)
                        DescriptionView(item: item)
                        if item.kind == .issue {
                            SubIssuesSection(item: item)
                        }
                        if item.kind != .draft {
                            ActivitySection(item: item)
                        }
                    }
                    .frame(maxWidth: 720, alignment: .leading)
                    .padding(.horizontal, 32)
                    .padding(.top, 32)
                    .padding(.bottom, 60)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.never)
                Rectangle().fill(Theme.panelBorder).frame(width: 1)
                PropertiesPanel(item: item)
                    .frame(width: 280)
            }
        }
        .background(Theme.panel)
        .onAppear { model.detailAppeared(item) }
        .onDisappear { model.detailDisappeared(item) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            IconButton(systemName: "chevron.left", label: "Back (Esc)") { model.leaveIssue() }
            if let project = model.project(of: item) {
                Button {
                    model.closeDetail()
                } label: {
                    HStack(spacing: 8) {
                        ProjectSwatch(title: project.title)
                        Text(project.title).foregroundStyle(Theme.textSecondary)
                    }
                }
                .buttonStyle(PlainPressStyle())
                Text("›").foregroundStyle(Theme.textTertiary)
            }
            if let parentNumber = item.parentNumber {
                // A sub-issue shows its parent on the way, as in Linear; clicking it goes up.
                let parent = item.parentId.flatMap { model.item(contentId: $0) }
                Button {
                    if let parent { model.open(parent) }
                } label: {
                    HStack(spacing: 6) {
                        Text("#\(parentNumber)").monospacedDigit().foregroundStyle(Theme.textTertiary)
                        if let title = item.parentTitle {
                            Text(title).foregroundStyle(Theme.textSecondary).lineLimit(1).truncationMode(.tail)
                        }
                    }
                    .frame(maxWidth: 260, alignment: .leading)
                }
                .buttonStyle(PlainPressStyle())
                .disabled(parent == nil)
                .help(parent == nil ? "The parent issue isn't on this board" : "Open the parent issue")
                Text("›").foregroundStyle(Theme.textTertiary)
            }
            Text(item.displayNumber).font(.uiSemibold).monospacedDigit()
            if item.isLocalOnly {
                Text("Not on GitHub yet")
                    .font(.small)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            if let position = model.position(of: item) {
                Text("\(position.index + 1) / \(position.count)")
                    .font(.small)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                IconButton(systemName: "chevron.up", label: "Previous issue (K)") { model.step(-1) }
                IconButton(systemName: "chevron.down", label: "Next issue (J)") { model.step(1) }
            }
            if item.url != nil {
                // As in Linear's issue header: the link and the branch name, a click away.
                IconButton(systemName: "link", label: "Copy link (⌘⇧C)") { model.copyLink(item) }
                    .padding(.leading, 6)
                if item.number != nil {
                    IconButton(systemName: "arrow.triangle.branch", label: "Copy branch name (⌘⇧.)") { model.copyBranchName(item) }
                }
                Button {
                    model.openOnGitHub(item)
                } label: {
                    HStack(spacing: 6) {
                        Text("Open on GitHub")
                        Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .medium))
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.leading, 6)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .frame(height: Theme.headerHeight)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.panelBorder).frame(height: 1)
        }
    }
}

// MARK: - Title and description

private struct TitleField: View {
    @Environment(AppModel.self) private var model
    var item: Item
    @State private var title = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Issue title", text: $title, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 22, weight: .semibold))
            .focused($focused)
            .disabled(!item.isEditableContent)
            .onAppear { title = item.title }
            .onChange(of: item.title) { _, new in
                if !focused { title = new }
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commit() }
            }
            .onSubmit {
                commit()
                focused = false
            }
            .onKeyPress(.escape) {
                title = item.title
                focused = false
                return .handled
            }
    }

    private func commit() {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            title = item.title
        } else {
            model.rename(item, to: title)
        }
    }
}

private struct DescriptionView: View {
    @Environment(AppModel.self) private var model
    var item: Item
    @State private var editing = false

    var body: some View {
        DescriptionBody(text: item.body, isEditable: item.isEditableContent, onSave: save, editing: $editing) { takesFocus in
            MarkdownEditor(
                text: item.body,
                placeholder: item.isEditableContent ? "Add a description…" : "No description",
                isEditable: item.isEditableContent,
                onSave: save,
                editing: $editing,
                takesFocus: takesFocus
            )
        }
        .id(item.id)
    }

    private func save(_ text: String) {
        // The latest copy, since the view may have been drawn before the last sync.
        guard let current = model.allItems.first(where: { $0.id == item.id }) else { return }
        // Leave untouched text exactly as GitHub stores it, line endings included.
        guard text != Diff3.normalize(current.body) else { return }
        model.setBody(current, to: text)
    }
}

private struct ConflictBanner: View {
    @Environment(AppModel.self) private var model
    var entry: OutboxEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("The \(what) was also edited on GitHub. Nothing has been overwritten: your version is shown below and has not been sent.")
                .fixedSize(horizontal: false, vertical: true)
            if let theirs {
                VStack(alignment: .leading, spacing: 4) {
                    Text("On GitHub").font(.tinySemibold).foregroundStyle(Theme.warning)
                    Text(theirs)
                        .font(.small)
                        .foregroundStyle(Theme.textBody)
                        .lineLimit(8)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.warning.opacity(0.08)))
            }
            HStack(spacing: 8) {
                Button("Keep mine") { model.resolveConflict(entry, keepMine: true) }
                    .buttonStyle(PrimaryButtonStyle())
                Button("Use the GitHub version") { model.resolveConflict(entry, keepMine: false) }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.warning.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.warning.opacity(0.45), lineWidth: 1))
    }

    private var what: String {
        if case .setTitle = entry.mutation { return "title" }
        return "description"
    }

    private var theirs: String? {
        switch entry.mutation {
        case .setTitle(let m), .setBody(let m): m.theirs
        default: nil
        }
    }
}

// MARK: - Sub-issues

private struct SubIssuesSection: View {
    @Environment(AppModel.self) private var model
    var item: Item

    var body: some View {
        let subs = item.contentId.map { model.detail(for: $0).subIssues } ?? []
        let showsPriority = model.project(of: item)?.priorityFieldId != nil
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text("Sub-issues").font(.uiSemibold)
                if !subs.isEmpty {
                    let done = subs.filter(\.isClosed).count
                    Text("\(done) of \(subs.count)")
                        .font(.small)
                        .foregroundStyle(Theme.textTertiary)
                        .monospacedDigit()
                    ProgressView(value: Double(done), total: Double(subs.count))
                        .progressViewStyle(ThinProgressStyle())
                        .frame(width: 64)
                }
                Spacer()
                IconButton(systemName: "plus", label: "Add sub-issue", size: 22) {
                    model.overlay = .newIssue(statusId: nil, parentItemId: item.id)
                }
            }
            .frame(height: 32)

            if !subs.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(subs.enumerated()), id: \.element.id) { index, sub in
                        SubIssueRow(sub: sub, showsPriority: showsPriority)
                        if index < subs.count - 1 {
                            Rectangle().fill(Theme.panelBorder).frame(height: 1)
                        }
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.panelBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .animation(Theme.spring, value: subs.map(\.id))
            }
        }
    }
}

private struct SubIssueRow: View {
    @Environment(AppModel.self) private var model
    var sub: SubIssue
    var showsPriority: Bool
    @State private var hovering = false
    @State private var menuRegion = UUID()

    var body: some View {
        let boardItem = model.item(contentId: sub.id)
        // Same order as a list row: priority, number, status, title.
        HStack(spacing: 10) {
            if showsPriority {
                Group {
                    if let boardItem {
                        PartButton(kind: .priority, itemId: boardItem.id) {
                            PriorityIcon(level: model.priorityLevel(of: boardItem))
                        }
                    } else {
                        // Priority is a field of the project, so a sub-issue that isn't on the board has none.
                        Color.clear
                    }
                }
                .frame(width: 14, height: 12)
            }
            Text(sub.number > 0 ? "#\(sub.number)" : "New")
                .font(.small)
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 36, alignment: .leading)
            if let boardItem {
                // On the board it has a status column; pick one, as on its card.
                PartButton(kind: .status, itemId: boardItem.id) {
                    StatusIcon(glyph: glyph(boardItem))
                }
            } else {
                // Elsewhere it is only open or closed.
                Button {
                    withAnimation(Theme.spring) { model.setClosed(sub, !sub.isClosed) }
                } label: {
                    StatusIcon(glyph: glyph(boardItem))
                }
                .buttonStyle(PlainPressStyle())
                .help(sub.isClosed ? "Reopen" : "Mark as done")
                .accessibilityLabel(sub.isClosed ? "Reopen sub-issue" : "Mark sub-issue as done")
            }

            Text(sub.title)
                .foregroundStyle(sub.isClosed ? Theme.textSecondary : Theme.text)
                .lineLimit(1)
            Spacer(minLength: 8)
            if boardItem == nil, sub.url != nil {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .help("Not on this board; opens on GitHub")
            }
            if let boardItem {
                PartButton(kind: .assignees, itemId: boardItem.id) {
                    if boardItem.assignees.isEmpty {
                        Image(systemName: "person.crop.circle.dashed")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textTertiary)
                            .opacity(hovering ? 1 : 0)
                    } else {
                        AvatarStack(people: boardItem.assignees)
                    }
                }
            } else if !sub.assignees.isEmpty {
                AvatarStack(people: sub.assignees)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(hovering ? Theme.hover : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            if let boardItem {
                model.open(boardItem)
            } else if let url = sub.url.flatMap(URL.init(string:)) {
                NSWorkspace.shared.open(url)
            }
        }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            // A sub-issue on the board gets the same menu as its card.
            if let id = model.item(contentId: sub.id)?.id {
                ContextMenus.shared.register(menuRegion, frame: frame) { [model] _ in
                    model.allItems.first { $0.id == id }.map { ItemMenuBuilder(model: model, item: $0).menu() }
                }
            }
        }
        .onDisappear { ContextMenus.shared.remove(menuRegion) }
        .contextMenu {
            if boardItem == nil {
                Button(sub.isClosed ? "Reopen" : "Mark as Done") {
                    withAnimation(Theme.spring) { model.setClosed(sub, !sub.isClosed) }
                }
                if let url = sub.url {
                    Divider()
                    Button("Copy Link") { model.copyLink(url, for: "#\(sub.number) \(sub.title)") }
                    Button("Open on GitHub") {
                        if let parsed = URL(string: url) { NSWorkspace.shared.open(parsed) }
                    }
                }
            }
        }
    }

    private func glyph(_ boardItem: Item?) -> StatusGlyph {
        if let boardItem, boardItem.statusId != nil { return model.glyph(of: boardItem) }
        if !sub.isClosed { return StatusGlyph(category: .unstarted, progress: 0, color: Theme.textBody) }
        if sub.stateReason == "NOT_PLANNED" || sub.stateReason == "DUPLICATE" {
            return StatusGlyph(category: .canceled, progress: 0, color: Theme.textTertiary)
        }
        return StatusGlyph(category: .completed, progress: 1, color: Theme.accent)
    }
}

// MARK: - Comments

private struct ActivitySection: View {
    @Environment(AppModel.self) private var model
    var item: Item

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activity").font(.uiSemibold)

            ForEach(comments) { comment in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Avatar(login: comment.authorLogin ?? "ghost", url: comment.authorAvatarUrl, size: 18)
                        Text(comment.authorLogin ?? "ghost").font(.system(size: 12, weight: .semibold))
                        Text(comment.isLocalOnly ? "Sending…" : relativeDate(comment.createdAt))
                            .font(.small)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    MarkdownText(text: comment.body)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.groupHeader))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.panelBorder, lineWidth: 1))
                .transition(.opacity.combined(with: .offset(y: 6)))
            }

            VStack(alignment: .trailing, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text("Leave a comment…")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $draft)
                        .font(.system(size: 14))
                        .scrollContentBackground(.hidden)
                        .scrollIndicators(.never)
                        .focused($focused)
                        .frame(minHeight: 44, maxHeight: 220)
                        .fixedSize(horizontal: false, vertical: true)
                        .onKeyPress(.escape) {
                            focused = false
                            return .handled
                        }
                }
                HStack(spacing: 10) {
                    Text("⌘↵").font(.tiny).foregroundStyle(Theme.textTertiary)
                    Button("Comment", action: send)
                        .buttonStyle(PrimaryButtonStyle())
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.groupHeader))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(focused ? Theme.keycapBorder : Theme.chipBorder, lineWidth: 1))
        }
        .animation(Theme.spring, value: comments.map(\.id))
    }

    private var comments: [Comment] {
        item.contentId.map { model.detail(for: $0).comments } ?? []
    }

    private func send() {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        model.addComment(to: item, body: draft)
        draft = ""
    }
}

// MARK: - Properties

private struct PropertiesPanel: View {
    @Environment(AppModel.self) private var model
    var item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            row("Status") {
                PropertyButton(kind: .status, item: item) {
                    HStack(spacing: 8) {
                        StatusIcon(glyph: model.glyph(of: item))
                        Text(model.statusOption(of: item)?.name ?? "No status")
                            .foregroundStyle(item.statusId == nil ? Theme.textTertiary : Theme.text)
                    }
                }
            }
            if model.project(of: item)?.priorityFieldId != nil {
                row("Priority") {
                    PropertyButton(kind: .priority, item: item) {
                        HStack(spacing: 8) {
                            PriorityIcon(level: model.priorityLevel(of: item))
                            Text(model.priorityOption(of: item)?.name ?? "No priority")
                                .foregroundStyle(item.priorityId == nil ? Theme.textTertiary : Theme.text)
                        }
                    }
                }
            }
            if item.kind != .draft {
                row("Assignee") {
                    PropertyButton(kind: .assignees, item: item) {
                        if item.assignees.isEmpty {
                            Text("Unassigned").foregroundStyle(Theme.textTertiary)
                        } else {
                            HStack(spacing: 8) {
                                AvatarStack(people: item.assignees)
                                Text(item.assignees.count == 1 ? item.assignees[0].login : "\(item.assignees.count) people")
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                row("Labels") {
                    PropertyButton(kind: .labels, item: item) {
                        if item.labels.isEmpty {
                            Text("Add label").foregroundStyle(Theme.textTertiary)
                        } else {
                            WrappingLabels(labels: item.labels)
                        }
                    }
                }
            }

            Rectangle().fill(Theme.panelBorder).frame(height: 1).padding(.vertical, 10)

            if let project = model.project(of: item) {
                row("Project") {
                    HStack(spacing: 8) {
                        ProjectSwatch(title: project.title)
                        Text(project.title).lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                }
            }
            if let repo = item.repo {
                row("Repository") {
                    Text(repo).foregroundStyle(Theme.textBody).lineLimit(1).truncationMode(.middle).padding(.horizontal, 8)
                }
            }
            if let parentNumber = item.parentNumber {
                row("Parent") {
                    let parent = item.parentId.flatMap { model.item(contentId: $0) }
                    Button {
                        if let parent { model.open(parent) }
                    } label: {
                        Text("#\(parentNumber) \(item.parentTitle ?? "")")
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .frame(minHeight: 28)
                            .hoverFill()
                    }
                    .buttonStyle(PlainPressStyle())
                    .disabled(parent == nil)
                    .help(parent == nil ? "The parent issue isn't on this board" : "Open the parent issue")
                }
            }
            if let created = item.createdAt {
                row("Created") {
                    Text("\(relativeDate(created))\(item.authorLogin.map { " by \($0)" } ?? "")")
                        .foregroundStyle(Theme.textBody)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 20)
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .onAppear { model.loadRepoMeta(projectId: item.projectId) }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(title)
                .font(.small)
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 84, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .frame(minHeight: 32)
    }
}

private struct WrappingLabels: View {
    var labels: [LabelRef]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(labels) { label in
                LabelChip(label: label)
            }
        }
        .padding(.vertical, 4)
    }
}
#endif
