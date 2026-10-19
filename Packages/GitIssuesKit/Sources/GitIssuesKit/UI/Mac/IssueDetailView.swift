#if os(macOS)
import SwiftUI

/// An open issue as a page, as Notes and Mail show what is open: the title with a line about it, the description,
/// sub-issues as a checklist, what blocks it, and the conversation, with the comment field at the bottom. Its
/// properties are in the inspector beside it, and the toolbar has the way back, the issues before and after, and
/// GitHub.
struct IssueDetailView: View {
    @Environment(AppModel.self) private var model
    var item: Item

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(model.conflict(for: item)) { entry in
                    ConflictBanner(entry: entry)
                }
                VStack(alignment: .leading, spacing: 6) {
                    ParentLink(item: item)
                    TitleField(item: item)
                    IssueSubline(item: item)
                }
                DescriptionView(item: item)
                if item.kind == .issue {
                    if item.isEpic {
                        EpicWorkSection(item: item)
                    } else {
                        SubIssuesSection(item: item)
                    }
                    RelationsSection(item: item)
                }
                if item.kind != .draft {
                    ActivitySection(item: item)
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 44)
            .padding(.top, 26)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if item.kind != .draft {
                CommentComposer(item: item)
                    .frame(maxWidth: 720)
                    .padding(.horizontal, 44)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity)
            }
        }
        .background(Theme.panel)
        .onAppear { model.detailAppeared(item) }
        .onDisappear { model.detailDisappeared(item) }
    }
}

/// Over a sub-issue's title, as Linear shows it: the parent, a click away.
private struct ParentLink: View {
    @Environment(AppModel.self) private var model
    var item: Item

    var body: some View {
        if let parentNumber = item.parentNumber {
            let parent = item.parentId.flatMap { model.item(contentId: $0) }
            Button {
                if let parent { model.open(parent) }
            } label: {
                HStack(spacing: 6) {
                    if parent?.isEpic == true {
                        EpicIcon(size: 12)
                    } else {
                        Image(systemName: "arrow.turn.left.up").font(.system(size: 10, weight: .semibold))
                    }
                    Text("#\(parentNumber)").monospacedDigit()
                    if let title = item.parentTitle {
                        Text(title).lineLimit(1).truncationMode(.tail)
                    }
                }
                .font(.small)
                .foregroundStyle(Theme.textSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainPressStyle())
            .disabled(parent == nil)
            .help(parent == nil ? Text(.parentIssueNotOnBoard) : Text(.openParentIssue))
        }
    }
}

/// Under the title: the issue's number, who opened it and when, and its repository.
private struct IssueSubline: View {
    var item: Item

    var body: some View {
        let created = item.createdAt.map { created in
            item.authorLogin.map { String(localized: .createdDateByAuthor(date: relativeDate(created), author: $0)) } ?? relativeDate(created)
        }
        let parts = [item.number != nil ? item.displayNumber : nil, created, item.repo].compactMap { $0 }
        if !parts.isEmpty || item.isLocalOnly {
            HStack(spacing: 6) {
                if item.isEpic { EpicIcon(size: 12) }
                Text(parts.joined(separator: " · "))
                if item.isLocalOnly {
                    Text(.notOnGitHubYet)
                }
            }
            .font(.ui)
            .foregroundStyle(Theme.textTertiary)
            .lineLimit(1)
        }
    }
}

// MARK: - Title and description

struct TitleField: View {
    @Environment(AppModel.self) private var model
    var item: Item
    @State private var title = ""
    @FocusState private var focused: Bool

    var body: some View {
        if item.isEditableContent {
            field
        } else {
            // Read-only (a pull request, or an issue on no board): plain text, not a dimmed field.
            Text(item.title)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Theme.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var field: some View {
        TextField(.issueTitlePlaceholder, text: $title, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 26, weight: .bold))
            .focused($focused)
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

struct DescriptionView: View {
    @Environment(AppModel.self) private var model
    var item: Item
    @State private var editing = false

    var body: some View {
        MarkdownEditor(
            text: item.body,
            placeholder: item.isEditableContent ? .addDescriptionPlaceholder : .noDescription,
            isEditable: item.isEditableContent,
            onSave: save,
            editing: $editing,
            accessibilityLabel: .description,
            accessibilityIdentifier: "issue-description"
        )
        .id(item.id)
    }

    private func save(_ text: String) {
        // The latest copy, since the view may have been drawn before the last sync.
        guard let current = model.item(id: item.id) else { return }
        // Leave untouched text exactly as GitHub stores it, line endings included.
        guard text != Diff3.normalize(current.body) else { return }
        model.setBody(current, to: text)
    }
}

struct ConflictBanner: View {
    @Environment(AppModel.self) private var model
    var entry: OutboxEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
            if let theirs {
                VStack(alignment: .leading, spacing: 4) {
                    Text(.onGitHubVersion).font(.tinySemibold).foregroundStyle(Theme.warning)
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
                Button(.keepMineMac) { model.resolveConflict(entry, keepMine: true) }
                    .buttonStyle(PrimaryButtonStyle())
                Button(.useGitHubVersion) { model.resolveConflict(entry, keepMine: false) }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.warning.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.warning.opacity(0.45), lineWidth: 1))
    }

    private var message: LocalizedStringResource {
        if case .setTitle = entry.mutation { return .conflictTitleEditedOnGitHub }
        return .conflictDescriptionEditedOnGitHub
    }

    private var theirs: String? {
        switch entry.mutation {
        case .setTitle(let m), .setBody(let m): m.theirs
        default: nil
        }
    }
}

// MARK: - Sub-issues

struct SubIssuesSection: View {
    @Environment(AppModel.self) private var model
    var item: Item
    @State private var adding = false

    var body: some View {
        let subs = item.contentId.map { model.detail(for: $0).subIssues } ?? []
        let showsPriority = model.project(of: item)?.priorityFieldId != nil
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(.subIssues).font(.sectionTitle)
                if !subs.isEmpty {
                    let done = subs.filter(\.isClosed).count
                    Text(.subIssuesProgress(done: done, total: subs.count))
                        .font(.small)
                        .foregroundStyle(Theme.textTertiary)
                        .monospacedDigit()
                    ProgressView(value: Double(done), total: Double(subs.count))
                        .progressViewStyle(ThinProgressStyle())
                        .frame(width: 64)
                }
                Spacer()
                if model.canRelate(item) {
                    // A new sub-issue, or one that exists already, as in Linear: type to find it.
                    IconButton(systemName: "plus", label: String(localized: .addSubIssueButton), size: 22) { adding = true }
                        .dropdown(isPresented: $adding) { close in
                            ItemPicker(kind: .addSubIssue, itemId: item.id, close: close)
                        }
                } else {
                    IconButton(systemName: "plus", label: String(localized: .addSubIssueButton), size: 22) {
                        model.overlay = .newIssue(statusId: nil, parentItemId: item.id)
                    }
                }
            }
            .frame(height: 32)

            if !subs.isEmpty {
                VStack(spacing: 0) {
                    ForEach(subs) { sub in
                        SubIssueRow(sub: sub, showsPriority: showsPriority)
                    }
                }
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
        // A checklist, as in Reminders: the status where the checkbox is, the title, then the rest on the right.
        HStack(spacing: 10) {
            if let boardItem {
                // On the board it has a status column; pick one, as on its card.
                PartButton(kind: .status, itemId: boardItem.id) {
                    StatusIcon(glyph: glyph(boardItem), size: 16)
                }
            } else {
                // Elsewhere it is only open or closed.
                Button {
                    withAnimation(Theme.spring) { model.setClosed(sub, !sub.isClosed) }
                } label: {
                    StatusIcon(glyph: glyph(boardItem), size: 16)
                }
                .buttonStyle(PlainPressStyle())
                .help(sub.isClosed ? Text(.reopen) : Text(.markAsDoneTooltip))
                .accessibilityLabel(sub.isClosed ? Text(.reopenSubIssue) : Text(.markSubIssueAsDone))
            }

            Text(sub.title)
                .font(.system(size: 14))
                .foregroundStyle(sub.isClosed ? Theme.textSecondary : Theme.text)
                .lineLimit(1)
            Spacer(minLength: 8)
            if showsPriority, let boardItem {
                PartButton(kind: .priority, itemId: boardItem.id) {
                    PriorityIcon(level: model.priorityLevel(of: boardItem))
                }
                .frame(width: 14, height: 12)
            }
            (sub.number > 0 ? Text("#\(sub.number)") : Text(.unsentIssueNumber))
                .font(.small)
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
            if boardItem == nil, sub.url != nil {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .help(Text(.subIssueOpensOnGitHub))
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
        .padding(.horizontal, 8)
        .frame(height: 38)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hovering ? Theme.hover : .clear))
        .overlay(alignment: .bottom) {
            // A hairline from where the title starts, as between a checklist's lines.
            Rectangle().fill(Theme.rowSeparator).frame(height: 1).padding(.leading, 34).opacity(hovering ? 0 : 1)
        }
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
        // On no board, it has only its own menu; one on a board has its card's (registered above).
        .glassContextMenu { [model, sub] in
            guard model.item(contentId: sub.id) == nil else { return nil }
            let menu = MenuBuilder()
            menu.item(sub.isClosed ? .reopen : .markAsDone, sub.isClosed ? "arrow.uturn.backward" : "checkmark.circle") {
                withAnimation(Theme.spring) { model.setClosed(sub, !sub.isClosed) }
            }
            menu.item(.removeFromParentMenuItem, "arrow.uturn.left") { model.removeFromParent(sub) }
            if let url = sub.url {
                menu.divider()
                menu.item(.copyLink, "link") { model.copyLink(url, for: "#\(sub.number) \(sub.title)") }
                menu.item(.openOnGitHub, "arrow.up.right.square") {
                    if let parsed = URL(string: url) { NSWorkspace.shared.open(parsed) }
                }
            }
            return menu.build()
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

// MARK: - An epic's work

/// What an epic is made of, as Linear's project page shows it: how far it is, and its sub-issues by milestone, each
/// group with a + for a new sub-issue in that milestone.
struct EpicWorkSection: View {
    @Environment(AppModel.self) private var model
    var item: Item
    @State private var adding = false

    var body: some View {
        let subs = item.contentId.map { model.detail(for: $0).subIssues } ?? []
        let groups = model.subIssuesByMilestone(of: item, subs)
        let showsPriority = model.project(of: item)?.priorityFieldId != nil
        let done = subs.filter { sub in model.issue(contentId: sub.id).map { model.isDone($0) } ?? sub.isClosed }.count
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(.progress).font(.sectionTitle)
                if !subs.isEmpty {
                    Text(.subIssuesProgress(done: done, total: subs.count))
                        .font(.small)
                        .foregroundStyle(Theme.textTertiary)
                        .monospacedDigit()
                    let milestones = groups.filter { $0.title != nil }.count
                    if milestones > 0 {
                        Text(.milestonesCount(count: milestones)).font(.small).foregroundStyle(Theme.textTertiary)
                    }
                }
                Spacer()
                if model.canRelate(item) {
                    IconButton(systemName: "plus", label: String(localized: .addSubIssueButton), size: 22) { adding = true }
                        .dropdown(isPresented: $adding) { close in
                            ItemPicker(kind: .addSubIssue, itemId: item.id, close: close)
                        }
                }
            }
            .frame(height: 32)

            if subs.isEmpty {
                Text(.epicNoIssuesYet)
                    .font(.small)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                // One bar, in a part per milestone as long as its share of the issues.
                SegmentedProgress(parts: groups.map { group in
                    SegmentedProgress.Part(
                        mark: group.group.map { model.mark(of: $0, projectId: item.projectId) } ?? .none,
                        title: group.title ?? String(localized: .noMilestone),
                        done: group.subs.filter { sub in model.issue(contentId: sub.id).map { model.isDone($0) } ?? sub.isClosed }.count,
                        total: group.subs.count
                    )
                })

                VStack(spacing: 0) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                        EpicGroupHeader(item: item, group: group.group, title: group.title, count: group.subs.count)
                        ForEach(group.subs) { sub in
                            SubIssueRow(sub: sub, showsPriority: showsPriority)
                        }
                    }
                }
                .animation(Theme.spring, value: subs.map(\.id))
            }
        }
    }
}

/// A milestone's group among an epic's sub-issues: its diamond, name, date and count, and a + for a new one in it.
private struct EpicGroupHeader: View {
    @Environment(AppModel.self) private var model
    var item: Item
    var group: MilestoneGroup?
    var title: String?
    var count: Int

    var body: some View {
        HStack(spacing: 8) {
            MilestoneIcon(mark: group.map { model.mark(of: $0, projectId: item.projectId) } ?? .none, size: 12)
            Text(title ?? String(localized: .noMilestone)).font(.smallMedium).foregroundStyle(title == nil ? Theme.textSecondary : Theme.text)
            if let due = group?.due {
                Text(due.shortLabel()).font(.small).foregroundStyle(Theme.textTertiary)
            }
            Text("\(count)").font(.small).monospacedDigit().foregroundStyle(Theme.textTertiary)
            Spacer()
            // A closed milestone takes no new issues.
            if item.kind == .issue, group?.isOpen ?? true {
                IconButton(systemName: "plus", label: String(localized: .newSubIssueInMilestone(milestone: title ?? String(localized: .noMilestone))), size: 20) {
                    model.newIssuePlan = NewIssuePlan(milestoneTitle: title)
                    model.overlay = .newIssue(statusId: nil, parentItemId: item.id)
                }
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 7)
        .frame(height: 32)
        .padding(.top, 6)
    }
}

// MARK: - Relations

/// What blocks the issue and what it blocks, each under its own heading, shown once there is any. Issues are added
/// from the properties, the right-click menu or the command palette, and from the heading's plus.
struct RelationsSection: View {
    @Environment(AppModel.self) private var model
    var item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(LinkedIssue.Relation.allCases, id: \.self) { relation in
                let links = model.links(of: item, relation)
                if !links.isEmpty {
                    RelationGroup(item: item, relation: relation, links: links)
                }
            }
        }
    }
}

private struct RelationGroup: View {
    @Environment(AppModel.self) private var model
    var item: Item
    var relation: LinkedIssue.Relation
    var links: [LinkedIssue]
    @State private var adding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if relation == .blockedBy { BlockedIcon() } else { BlockingIcon() }
                Text(relation == .blockedBy ? LocalizedStringResource.blockedByHelp : .blockingHelp).font(.sectionTitle)
                Text("\(links.count)").font(.small).foregroundStyle(Theme.textTertiary).monospacedDigit()
                Spacer()
                IconButton(
                    systemName: "plus",
                    label: String(localized: relation == .blockedBy ? .markAsBlockedByCommand : .markAsBlockingCommand), size: 22
                ) {
                    adding = true
                }
                .dropdown(isPresented: $adding) { close in
                    ItemPicker(kind: relation == .blockedBy ? .blockedBy : .blocking, itemId: item.id, close: close)
                }
            }
            .frame(height: 32)
            VStack(spacing: 0) {
                ForEach(links, id: \.key) { link in
                    LinkedIssueRow(item: item, link: link)
                }
            }
            .animation(Theme.spring, value: links.map(\.key))
        }
    }
}

private struct LinkedIssueRow: View {
    @Environment(AppModel.self) private var model
    var item: Item
    var link: LinkedIssue
    @State private var hovering = false
    @State private var menuRegion = UUID()

    var body: some View {
        let boardItem = model.item(contentId: link.id)
        // Laid out like a sub-issue row, so the two lists line up: status, title, then the rest on the right.
        HStack(spacing: 10) {
            if let boardItem {
                PartButton(kind: .status, itemId: boardItem.id) {
                    StatusIcon(glyph: model.glyph(of: boardItem), size: 16)
                }
            } else {
                StatusIcon(glyph: .openOrClosed(link.state, reason: link.stateReason), size: 16)
            }
            Text(link.title)
                .font(.system(size: 14))
                .foregroundStyle(link.isClosed ? Theme.textSecondary : Theme.text)
                .lineLimit(1)
            Spacer(minLength: 8)
            if model.project(of: item)?.priorityFieldId != nil, let boardItem, boardItem.projectId == item.projectId {
                PartButton(kind: .priority, itemId: boardItem.id) {
                    PriorityIcon(level: model.priorityLevel(of: boardItem))
                }
                .frame(width: 14, height: 12)
            }
            Text(link.displayNumber)
                .font(.small)
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
            if boardItem == nil, link.url != nil {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .help(Text(.notOnYourBoardsOpensOnGitHub))
            }
            if let assignees = boardItem?.assignees, !assignees.isEmpty {
                AvatarStack(people: assignees)
            }
            IconButton(systemName: "xmark", label: String(localized: .removeRelation), size: 20) {
                model.removeLink(link, of: item)
            }
            .opacity(hovering ? 1 : 0)
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .frame(height: 38)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hovering ? Theme.hover : .clear))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.rowSeparator).frame(height: 1).padding(.leading, 34).opacity(hovering ? 0 : 1)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            if let boardItem {
                model.open(boardItem)
            } else if let url = link.url.flatMap(URL.init(string:)) {
                NSWorkspace.shared.open(url)
            }
        }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            // An issue on a board gets the same menu as its card.
            if let id = model.item(contentId: link.id)?.id {
                ContextMenus.shared.register(menuRegion, frame: frame) { [model] _ in
                    model.allItems.first { $0.id == id }.map { ItemMenuBuilder(model: model, item: $0).menu() }
                }
            }
        }
        .onDisappear { ContextMenus.shared.remove(menuRegion) }
        .glassContextMenu { [model, link, item] in
            guard model.item(contentId: link.id) == nil else { return nil }
            let menu = MenuBuilder()
            menu.item(.removeRelationMenuItem, "xmark") { model.removeLink(link, of: item) }
            if let url = link.url {
                menu.divider()
                menu.item(.copyLink, "link") { model.copyLink(url, for: "\(link.displayNumber) \(link.title)") }
                menu.item(.openOnGitHub, "arrow.up.right.square") {
                    if let parsed = URL(string: url) { NSWorkspace.shared.open(parsed) }
                }
            }
            return menu.build()
        }
    }
}

// MARK: - Comments

struct ActivitySection: View {
    @Environment(AppModel.self) private var model
    var item: Item
    /// Comments that are new since you last read the issue, from the Inbox; they are marked.
    var highlighted: Set<String> = []

    var body: some View {
        let comments = comments
        if !comments.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(.activity).font(.sectionTitle).padding(.bottom, 6)
                ForEach(comments) { comment in
                    let new = highlighted.contains(comment.id)
                    HStack(alignment: .top, spacing: 11) {
                        Avatar(login: comment.authorLogin ?? "ghost", url: comment.authorAvatarUrl, size: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 7) {
                                Text(comment.authorLogin ?? "ghost").font(.system(size: 13, weight: .semibold))
                                (comment.isLocalOnly ? Text(.sendingComment) : Text(relativeDate(comment.createdAt)))
                                    .font(.small)
                                    .foregroundStyle(Theme.textTertiary)
                                if new {
                                    Spacer(minLength: 8)
                                    Text(.newCommentBadge)
                                        .font(.tinySemibold)
                                        .foregroundStyle(Theme.accent)
                                        .padding(.horizontal, 7)
                                        .frame(height: 18)
                                        .background(Capsule().fill(Theme.menuHighlight))
                                }
                            }
                            MarkdownText(text: comment.body)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, new ? 12 : 0)
                    .background {
                        if new { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.selectionFill) }
                    }
                    .id(comment.id)
                    .transition(.opacity.combined(with: .offset(y: 6)))
                }
            }
            .animation(Theme.spring, value: comments.map(\.id))
        }
    }

    private var comments: [Comment] {
        item.contentId.map { model.detail(for: $0).comments } ?? []
    }
}

/// The field for a new comment, at the bottom of an issue as in Messages: it grows as you write, and the round
/// button or ⌘↵ sends it.
struct CommentComposer: View {
    @Environment(AppModel.self) private var model
    var item: Item

    @State private var draft = ""
    @State private var focused = false
    @State private var height: CGFloat = 22

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Markdown as it will look on GitHub, growing with the text up to a point and then scrolling.
            ScrollView {
                MarkdownEditor(
                    text: draft,
                    placeholder: .leaveCommentPlaceholder,
                    onChange: { draft = $0 },
                    editing: $focused,
                    onSubmit: send,
                    accessibilityLabel: .leaveCommentPlaceholder,
                    accessibilityIdentifier: "comment-field"
                )
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            }
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(max(height, 18), 220))
            .padding(.vertical, 9)
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(canSend ? Color.white : Theme.textTertiary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(canSend ? Theme.accentFill : Theme.field))
            }
            .buttonStyle(PlainPressStyle())
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!canSend)
            .help(Text(.titleWithShortcutKey(title: String(localized: .postComment), key: "⌘↵")))
            .accessibilityLabel(Text(.sendCommentButton))
            .padding(.bottom, 7)
        }
        .padding(.leading, 14)
        .padding(.trailing, 7)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .glassPanel(in: RoundedRectangle(cornerRadius: 21, style: .continuous))
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        guard canSend else { return }
        model.addComment(to: item, body: draft)
        draft = ""
    }
}

// MARK: - Properties

/// An issue's properties, in the inspector beside it as Notes and Mail show details: each value opens its picker
/// right there, as on a card.
struct IssueProperties: View {
    @Environment(AppModel.self) private var model
    var item: Item
    /// As wide as the longest label in this language needs, and never narrower than in English.
    @State private var labelWidth: CGFloat = 84

    var body: some View {
        ScrollView {
            properties
        }
        .scrollIndicators(.never)
    }

    private var properties: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(.issueDetailsHeading)
                .font(.tinySemibold)
                .foregroundStyle(Theme.textTertiary)
                .padding(.bottom, 6)
            row(.status) {
                PropertyButton(kind: .status, item: item) {
                    HStack(spacing: 8) {
                        StatusIcon(glyph: model.glyph(of: item))
                        // An issue on no board has no status; clicking here puts it on one.
                        Text(model.statusText(of: item))
                            .foregroundStyle(model.statusIsPlaceholder(item) ? Theme.textTertiary : Theme.text)
                    }
                }
            }
            if model.project(of: item)?.priorityFieldId != nil {
                row(.priority) {
                    PropertyButton(kind: .priority, item: item) {
                        HStack(spacing: 8) {
                            PriorityIcon(level: model.priorityLevel(of: item))
                            (model.priorityOption(of: item).map { Text($0.name) } ?? Text(.noPriority))
                                .foregroundStyle(item.priorityId == nil ? Theme.textTertiary : Theme.text)
                        }
                    }
                }
            }
            if item.kind != .draft {
                row(.assignee) {
                    PropertyButton(kind: .assignees, item: item) {
                        if item.assignees.isEmpty {
                            Text(.unassigned).foregroundStyle(Theme.textTertiary)
                        } else {
                            HStack(spacing: 8) {
                                AvatarStack(people: item.assignees)
                                (item.assignees.count == 1 ? Text(item.assignees[0].login) : Text(.peopleCount(count: item.assignees.count)))
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                row(.labels) {
                    PropertyButton(kind: .labels, item: item) {
                        if item.labels.isEmpty {
                            Text(.addLabel).foregroundStyle(Theme.textTertiary)
                        } else {
                            WrappingLabels(labels: item.labels)
                        }
                    }
                }
            }
            if model.canHaveDueDate(item) {
                row(.dueDate) {
                    PropertyButton(kind: .dueDate, item: item) {
                        if let due = model.dueBadge(for: item) {
                            HStack(spacing: 7) {
                                DueDateIcon(tone: due.tone, size: 12)
                                Text(due.day.mediumLabel())
                                    .foregroundStyle(due.tone == .overdue || due.tone == .today ? due.tone.color : Theme.text)
                            }
                            .help(due.tooltip)
                        } else {
                            Text(.addDueDate).foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
            }

            Divider().padding(.vertical, 10)

            if let project = model.project(of: item) {
                row(.project) {
                    HStack(spacing: 8) {
                        ProjectIcon(projectId: project.id)
                        Text(project.title).lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                }
            } else if !item.isOnBoard, !model.boards(toAdd: item).isEmpty {
                row(.project) {
                    PropertyButton(kind: .status, item: item) {
                        Text(.addToProjectPlaceholder).foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            if model.canHaveMilestone(item) {
                row(.milestone) {
                    PropertyButton(kind: .milestone, item: item) {
                        if let title = model.milestoneTitle(of: item) {
                            HStack(spacing: 7) {
                                MilestoneIcon(mark: model.milestoneMark(of: item), size: 12)
                                Text(title).lineLimit(1)
                                if let due = model.milestoneGroup(of: item)?.due {
                                    Text(due.shortLabel()).foregroundStyle(Theme.textTertiary).lineLimit(1)
                                }
                            }
                        } else {
                            Text(.addToMilestone).foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
                if item.isEpic, let span = model.milestoneSpan(of: item) {
                    row(.itsIssues) {
                        Text(span)
                            .foregroundStyle(Theme.textBody)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .help(Text(.epicSpanTooltip))
                    }
                }
            }
            if let repo = item.repo {
                row(.repository) {
                    Text(repo).foregroundStyle(Theme.textBody).lineLimit(1).truncationMode(.middle).padding(.horizontal, 8)
                }
            }
            let epic = model.epic(of: item)
            let parentIsEpic = epic != nil && epic?.contentId == item.parentId
            if model.canRelate(item), !item.isEpic, epic == nil || parentIsEpic {
                // An issue right under an epic, or under nothing yet: its epic is chosen here.
                row(.epic) {
                    PropertyButton(kind: .epic, item: item) {
                        if let epic {
                            HStack(spacing: 7) {
                                EpicIcon(size: 13)
                                Text(epic.title).lineLimit(1)
                            }
                        } else {
                            Text(.addToEpicPlaceholderShort).foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
            } else if let epic {
                // Under another issue: the epic comes with that parent.
                row(.epic) {
                    Button {
                        model.open(epic)
                    } label: {
                        HStack(spacing: 7) {
                            EpicIcon(size: 13)
                            Text(epic.title).lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .frame(minHeight: 28)
                        .hoverFill()
                    }
                    .buttonStyle(PlainPressStyle())
                    .help(Text(.openEpic))
                }
            }
            if model.canRelate(item), !parentIsEpic {
                // The breadcrumb above opens the parent; here it is chosen.
                row(.parentIssue) {
                    PropertyButton(kind: .parent, item: item) {
                        if let parentNumber = item.parentNumber {
                            HStack(spacing: 6) {
                                Text("#\(parentNumber)").monospacedDigit().foregroundStyle(Theme.textTertiary)
                                Text(item.parentTitle ?? "").lineLimit(1)
                            }
                        } else {
                            Text(.setParent).foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
            }
            if model.canRelate(item) {
                relationRow(.blockedBy)
                relationRow(.blocking)
            } else if let parentNumber = item.parentNumber {
                row(.parentIssue) {
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
                    .help(parent == nil ? Text(.parentIssueNotOnBoard) : Text(.openParentIssue))
                }
            }
            if let created = item.createdAt {
                row(.created) {
                    (item.authorLogin.map { Text(.createdDateByAuthor(date: relativeDate(created), author: $0)) } ?? Text(relativeDate(created)))
                        .foregroundStyle(Theme.textBody)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                }
            }
        }
        .padding(.top, 14)
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.bottom, 20)
        .onAppear { model.loadRepoMeta(for: item) }
    }

    private func row<Content: View>(_ title: LocalizedStringResource, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(title)
                .font(.small)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { labelWidth = max(labelWidth, $0 + 14) }
                .frame(width: labelWidth, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .frame(minHeight: 30)
    }

    /// Blocked by or blocking: the issues' numbers, listed in full beside the description.
    private func relationRow(_ relation: LinkedIssue.Relation) -> some View {
        let links = model.links(of: item, relation)
        let count = relation == .blockedBy ? item.blockedByCount : item.blockingCount
        return row(relation == .blockedBy ? .blockedByHelp : .blockingHelp) {
            PropertyButton(kind: relation == .blockedBy ? .blockedBy : .blocking, item: item) {
                if links.isEmpty, count == 0 {
                    Text(.addRelatedIssue).foregroundStyle(Theme.textTertiary)
                } else {
                    HStack(spacing: 6) {
                        if relation == .blockedBy { BlockedIcon() } else { BlockingIcon() }
                        Text(links.isEmpty ? String(localized: .issuesCount(count: count)) : links.map(\.displayNumber).formatted(.list(type: .and)))
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
            }
        }
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
