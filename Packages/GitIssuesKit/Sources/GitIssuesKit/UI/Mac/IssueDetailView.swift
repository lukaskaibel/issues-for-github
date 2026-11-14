#if os(macOS)
import SwiftUI

/// An open issue as a page, as Notes and Mail show what is open: the title with a line about it, the description,
/// sub-issues as a checklist, what blocks it, and the conversation, with the comment field at the bottom. Its
/// properties are in the inspector beside it, and the toolbar has the way back, the issues before and after, and
/// GitHub.
struct IssueDetailView: View {
    @Environment(AppModel.self) private var model
    var item: Item
    @State private var titleLink = TitleLink()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(model.conflict(for: item)) { entry in
                    ConflictBanner(entry: entry)
                }
                VStack(alignment: .leading, spacing: 6) {
                    ParentLink(item: item)
                    TitleField(item: item, link: titleLink)
                    IssueSubline(item: item)
                }
                DescriptionView(item: item, titleLink: titleLink)
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
        .pageUnderToolbar()
        .pageFootBar {
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
    /// The description below, which the keys go on to.
    var link: TitleLink?
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
            .titleOf(link) { focused = true }
            .onAppear { title = item.title }
            .onChange(of: item.title) { _, new in
                if !focused { title = new }
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commit() }
            }
            // Leaving with Back, the arrows or a key takes the page away without the field losing focus first.
            .onDisappear(perform: commit)
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
    var titleLink: TitleLink?
    @State private var editing = false

    var body: some View {
        MarkdownEditor(
            text: item.body,
            placeholder: item.isEditableContent ? .addDescriptionPlaceholder : .noDescription,
            isEditable: item.isEditableContent,
            onSave: save,
            editing: $editing,
            titleLink: titleLink,
            accessibilityLabel: .description,
            accessibilityIdentifier: "issue-description"
        )
        .id(item.id)
    }

    private func save(_ text: String) {
        model.saveDescription(of: item, text)
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

    private var message: LocalizedStringResource { entry.conflictMessage }
    private var theirs: String? { entry.theirText }
}

// MARK: - Sub-issues

struct SubIssuesSection: View {
    @Environment(AppModel.self) private var model
    var item: Item
    @State private var adding = false

    var body: some View {
        let detail = item.contentId.map { model.detail(for: $0) }
        let subs = model.orderedSubIssues(of: item)
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
                if subs.count > 1 { SubIssueOrderButton() }
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

            if let detail, !subs.isEmpty {
                let lines = model.subIssueLines(subs, in: detail)
                let order = lines.compactMap { model.item(contentId: $0.sub.id)?.id }
                VStack(spacing: 0) {
                    ForEach(lines) { line in
                        SubIssueRow(line: line, order: order)
                    }
                }
                .issueRowsOnPage()
                .animation(Theme.spring, value: lines.map(\.id))
            }
        }
    }
}

/// Picks the order sub-issues are listed in, for every issue: a short list that closes on the pick.
private struct SubIssueOrderButton: View {
    @Environment(AppModel.self) private var model
    @State private var open = false

    var body: some View {
        IconButton(systemName: "arrow.up.arrow.down", label: String(localized: .orderSubIssuesTooltip), size: 22) { open = true }
            .dropdown(isPresented: $open) { close in
                SelectList(
                    options: SubIssueOrder.allCases.map { .init(id: $0.rawValue, title: String(localized: $0.title)) },
                    selected: model.subIssueOrder.rawValue
                ) { id in
                    withAnimation(Theme.spring) { model.subIssueOrder = SubIssueOrder(rawValue: id) ?? .priority }
                    close()
                }
            }
    }
}

/// A sub-issue in an issue's list of them, as the lists show every issue (`IssueRowView`). One with sub-issues of its
/// own has the arrow that unfolds them under it, indented, with lines from it as in the lists. A click opens it; the
/// checkbox, ⌘-click and Shift-click pick several, and their pickers and right-click menu then change all of them,
/// such as moving them under another parent.
private struct SubIssueRow: View {
    @Environment(AppModel.self) private var model
    var line: SubIssueLine
    /// The sub-issues as listed, unfolded ones included, for Shift-click to pick a run of them.
    var order: [String]
    /// Whether the row names its milestone: not under its milestone's heading.
    var showsMilestone = true

    private var sub: SubIssue { line.sub }

    var body: some View {
        let item = model.rowItem(for: sub)
        IssueRowView(
            row: row(item),
            open: {
                if !item.isStandIn {
                    model.open(item)
                } else if let url = sub.url.flatMap(URL.init(string:)) {
                    NSWorkspace.shared.open(url)
                }
            },
            pick: { checkbox in
                // One the app knows only from GitHub can't be changed with the others.
                guard !item.isStandIn else { return model.handleSubIssueClick(on: nil, in: order) }
                if checkbox {
                    model.toggleSubIssuePick(item)
                    return true
                }
                return model.handleSubIssueClick(on: item, in: order)
            },
            fold: { model.toggleSubIssues(of: sub.id) },
            toggleClosed: { withAnimation(Theme.spring) { model.setClosed(sub, !sub.isClosed) } },
            willOpenPart: { model.releaseSubIssuePicks(unlessPicked: item) },
            menu: { [model, sub, item] in
                // One the app has gets the same menu as its card; one known only from GitHub, its own.
                if !item.isStandIn { return model.allItems.first { $0.id == item.id }.map { ItemMenuBuilder(model: model, item: $0).menu() } }
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
        )
        // Unfolded, its sub-issues are read again each time the list shows.
        .task(id: line.unfolded) {
            if line.unfolded { await model.loadSubIssues(of: sub) }
        }
    }

    private func row(_ item: Item) -> IssueRowModel {
        var row = item.isStandIn
            ? model.issueRow(standingInFor: item, as: .subIssue, nest: line.place, nested: line.progress?.total, folded: !line.unfolded)
            : model.issueRow(
                item, selected: model.pickedSubIssueIds.contains(item.id), selecting: !model.pickedSubIssueIds.isEmpty,
                nest: line.place, nested: line.progress?.total, folded: !line.unfolded,
                milestone: showsMilestone ? model.milestoneTitle(of: item) : nil,
                chips: model.fieldChips(of: item, in: item.projectId.map { .project($0) })
            )
        row.foldWaiting = line.waiting
        return row
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
        let detail = item.contentId.map { model.detail(for: $0) }
        let subs = model.orderedSubIssues(of: item)
        let groups = model.subIssuesByMilestone(of: item, subs)
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
                if subs.count > 1 { SubIssueOrderButton() }
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

                let lines = detail.map { detail in groups.map { model.subIssueLines($0.subs, in: detail) } } ?? []
                let order = lines.joined().compactMap { model.item(contentId: $0.sub.id)?.id }
                VStack(spacing: 0) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                        EpicGroupHeader(item: item, group: group.group, title: group.title, count: group.subs.count)
                            .outOfIssueRows()
                        // Under its milestone's heading, a row doesn't name the milestone again.
                        ForEach(lines.indices.contains(index) ? lines[index] : []) { line in
                            SubIssueRow(line: line, order: order, showsMilestone: false)
                        }
                    }
                }
                .issueRowsOnPage()
                .animation(Theme.spring, value: lines.map { $0.map(\.id) })
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
                    model.newIssuePlan = NewIssuePlan(milestoneTitle: title, noMilestone: title == nil)
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
            .issueRowsOnPage()
            .animation(Theme.spring, value: links.map(\.key))
        }
    }
}

/// An issue the open one is blocked by or blocks, as the lists show every issue (`IssueRowView`), with a button at its
/// end under the pointer that takes it off the list.
private struct LinkedIssueRow: View {
    @Environment(AppModel.self) private var model
    var item: Item
    var link: LinkedIssue

    var body: some View {
        let linked = model.rowItem(for: link)
        IssueRowView(
            row: row(linked),
            open: {
                if !linked.isStandIn {
                    model.open(linked)
                } else if let url = link.url.flatMap(URL.init(string:)) {
                    NSWorkspace.shared.open(url)
                }
            },
            remove: { model.removeLink(link, of: item) },
            menu: { [model, link, item, linked] in
                let menu = MenuBuilder()
                menu.item(.removeRelationMenuItem, "xmark") { model.removeLink(link, of: item) }
                if !linked.isStandIn, let current = model.allItems.first(where: { $0.id == linked.id }) {
                    // One the app has gets its card's menu below.
                    let card = ItemMenuBuilder(model: model, item: current).menu()
                    menu.divider()
                    for entry in card.items {
                        card.removeItem(entry)
                        menu.menu.addItem(entry)
                    }
                } else if let url = link.url {
                    menu.divider()
                    menu.item(.copyLink, "link") { model.copyLink(url, for: "\(link.displayNumber) \(link.title)") }
                    menu.item(.openOnGitHub, "arrow.up.right.square") {
                        if let parsed = URL(string: url) { NSWorkspace.shared.open(parsed) }
                    }
                }
                return menu.build()
            }
        )
    }

    private func row(_ linked: Item) -> IssueRowModel {
        var row = linked.isStandIn
            ? model.issueRow(standingInFor: linked, as: .relation)
            : model.issueRow(
                linked, milestone: model.milestoneTitle(of: linked),
                chips: model.fieldChips(of: linked, in: linked.projectId.map { .project($0) })
            )
        // Picking is for sub-issues.
        row.pickable = false
        row.removable = true
        return row
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

    /// What was written and not sent stays with the issue while you look elsewhere, as in Mail.
    @State private var draft: String
    @State private var focused = false
    @State private var height: CGFloat = 22

    init(item: Item) {
        self.item = item
        _draft = State(initialValue: AppModel.shared.commentDrafts[item.id] ?? "")
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Markdown as it will look on GitHub, growing with the text up to a point and then scrolling.
            ScrollView {
                MarkdownEditor(
                    draft: $draft,
                    placeholder: .leaveCommentPlaceholder,
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
            // Only while writing the comment: ⌘↵ in the title or elsewhere on the page doesn't post a half-written one.
            .keyboardShortcut(focused ? KeyboardShortcut(.return, modifiers: .command) : nil)
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
        // It floats over the page: its text keeps its own menu, and elsewhere a right-click neither sends the comment
        // nor opens the menu of a sub-issue scrolled under it.
        .floatingContextMenu()
        .onChange(of: draft) { _, text in model.commentDrafts[item.id] = text.isEmpty ? nil : text }
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
                            DueDateValue(due: due).foregroundStyle(Theme.text)
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
            ForEach(model.iterationFields(for: item)) { field in
                iterationRow(field)
            }
            if let repo = item.repo {
                row(.repository) {
                    Text(repo).foregroundStyle(Theme.textBody).lineLimit(1).truncationMode(.middle).padding(.horizontal, 8)
                }
            }
            let epic = model.epic(of: item)
            let parentIsEpic = epic != nil && epic?.contentId == item.parentId
            if model.canRelate(item), !item.isEpic, parentIsEpic || item.parentId == nil && model.hasEpics(item) {
                // An issue right under an epic, or under nothing yet: its epic is chosen here. Under another issue,
                // choosing one would take it from that parent.
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
        row(Text(title), content: content)
    }

    private func row<Content: View>(_ title: Text, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            title
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

    /// One of the board's iteration fields, by the name the board gives it: the iteration with "Current", "Next" or
    /// its days after it.
    private func iterationRow(_ field: ProjectField) -> some View {
        row(Text(verbatim: field.name)) {
            PropertyButton(kind: .iteration(fieldId: field.id), item: item) {
                if let iteration = model.iteration(of: item, field: field) {
                    HStack(spacing: 7) {
                        IterationIcon(size: 13)
                            .foregroundStyle(model.isRunning(iteration, field: field) ? Theme.started : Theme.textSecondary)
                        Text(iteration.title).lineLimit(1)
                        if let when = model.iterationPlace(iteration, field: field) ?? model.iterationRange(iteration) {
                            Text(when).foregroundStyle(Theme.textTertiary).lineLimit(1)
                        }
                    }
                } else {
                    Text(.addToIteration).foregroundStyle(Theme.textTertiary)
                }
            }
        }
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
