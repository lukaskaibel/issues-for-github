#if os(iOS)
import SwiftUI

/// One issue: title and description to edit in place, its properties, sub-issues and comments. On a wide
/// iPad window the properties stand in a column on the right, as on the Mac.
struct IssueScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation
    @Environment(\.wideLayout) private var wide
    @Environment(\.dismiss) private var dismiss
    var itemId: String
    /// Opened from the Inbox: what's new on it shows under the title, and the new comments are marked.
    var inboxEntryId: String? = nil

    @State private var picker: PickerKind?
    /// Whether the picker was opened with a key, so its search takes the typing.
    @State private var pickerFromKeyboard = false
    @State private var editingDescription = false

    var body: some View {
        if let item = model.item(id: itemId) {
            content(item)
                .onAppear {
                    model.detailAppeared(item)
                    RecentIssues.record(item.id)
                    if let entry = inboxEntry { model.selectInboxEntry(entry) }
                }
                .onDisappear { model.detailDisappeared(item) }
                .onChange(of: navigation.pickerRequest) { _, request in
                    guard let request, request.itemId == itemId else { return }
                    picker = request.kind
                    pickerFromKeyboard = true
                    navigation.pickerRequest = nil
                }
        } else {
            MobileEmptyState(
                title: String(localized: .issueGoneTitle),
                message: String(localized: .issueGoneMessage),
                systemImage: "questionmark.square.dashed"
            )
            .background(Theme.panel)
        }
    }

    private func content(_ item: Item) -> some View {
        let regular = wide
        return HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.conflict(for: item)) { entry in
                        MobileConflictBanner(entry: entry)
                            .padding(.bottom, 18)
                    }
                    IssueTitleField(item: item)
                    if !regular {
                        PropertyChips(item: item, picker: $picker)
                            .padding(.top, 14)
                    }
                    if let entry = inboxEntry, entry.isDue {
                        DueEntryBanner(entry: entry, item: item)
                            .padding(.top, 18)
                    } else if let entry = inboxEntry, !entry.activity.isEmpty {
                        MobileInboxNews(entry: entry)
                            .padding(.top, 18)
                    }
                    DescriptionEditor(item: item, editing: $editingDescription)
                        .padding(.top, 18)
                    if item.kind == .issue, !item.isDetached {
                        Group {
                            if item.isEpic { MobileEpicWork(item: item) } else { MobileSubIssues(item: item) }
                        }
                        .padding(.top, 28)
                        MobileRelations(item: item)
                    }
                    if item.kind != .draft {
                        MobileActivity(item: item, highlighted: inboxEntry?.newCommentIds ?? [])
                            .padding(.top, 28)
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, regular ? 32 : 20)
                .padding(.top, regular ? 24 : 8)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .pageFootBar {
                // While the description is edited, the keyboard bar is the only thing above the keyboard.
                if item.kind != .draft, !editingDescription {
                    CommentComposer(item: item)
                }
            }
            if regular {
                Rectangle().fill(Theme.panelBorder).frame(width: 1).ignoresSafeArea(edges: .bottom)
                PropertiesColumn(item: item, picker: $picker)
                    .frame(width: 300)
            }
        }
        .background(Theme.panel)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(regular ? .automatic : .hidden, for: .tabBar)
        .toolbar { toolbar(item) }
        .sheet(item: $picker, onDismiss: { pickerFromKeyboard = false }) { kind in
            IssuePickerSheet(kind: kind, itemId: item.id, focusesSearch: pickerFromKeyboard)
        }
        .background { keyboardShortcuts(item) }
    }

    /// Single keys on an iPad keyboard, as on the Mac: J and K step, S P A L open a property, I assigns me.
    /// Keys without modifiers go to a text field first, so typing in one is never taken over. A key can reach
    /// a screen that is just being replaced, so each acts on the issue on screen when it is pressed.
    private func keyboardShortcuts(_ item: Item) -> some View {
        ZStack {
            // Beside the Inbox's list on an iPad, the list takes J and K.
            if !besideInboxList {
                Button(.nextIssue) { stepFromCurrent(1) }.keyboardShortcut("j", modifiers: [])
                Button(.previousIssue) { stepFromCurrent(-1) }.keyboardShortcut("k", modifiers: [])
            }
            Button(.status) { navigation.requestPicker(.status) }.keyboardShortcut("s", modifiers: [])
            if model.project(of: item)?.priorityFieldId != nil {
                Button(.priority) { navigation.requestPicker(.priority) }.keyboardShortcut("p", modifiers: [])
            }
            if item.kind != .draft {
                Button(.assignee) { navigation.requestPicker(.assignees) }.keyboardShortcut("a", modifiers: [])
                Button(.labels) { navigation.requestPicker(.labels) }.keyboardShortcut("l", modifiers: [])
                Button(.assignToMe) { assignCurrentToMe() }.keyboardShortcut("i", modifiers: [])
            }
            if model.canHaveDueDate(item) {
                Button(.dueDateTitle) { navigation.requestPicker(.dueDate) }.keyboardShortcut("d", modifiers: [])
            }
        }
        .opacity(0)
        .allowsHitTesting(false)
        // The same actions are on screen as buttons and menus, so VoiceOver skips these.
        .accessibilityElement(children: .ignore)
        .accessibilityHidden(true)
    }

    private var inboxEntry: InboxEntry? {
        inboxEntryId.flatMap { model.inboxEntry(id: $0) }
    }

    /// The issue of the selected entry beside the Inbox's list, on a wide iPad.
    private var besideInboxList: Bool {
        inboxEntryId != nil && wide && navigation.tab == .inbox && navigation.path(for: .inbox).isEmpty
    }

    @ToolbarContentBuilder
    private func toolbar(_ item: Item) -> some ToolbarContent {
        ToolbarItem(placement: .principal) {
            VStack(spacing: 1) {
                Text(item.displayNumber).font(.headline).monospacedDigit()
                if let place = model.project(of: item)?.title ?? item.repoShortName {
                    Text(place).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
        }
        // From the Inbox, J and K step through the notifications instead of the project's issues.
        if wide, inboxEntryId == nil, let position = position(of: item) {
            ToolbarItemGroup(placement: .primaryAction) {
                Text("\(position.index + 1) / \(position.items.count)")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                Button {
                    step(-1, from: item)
                } label: {
                    Label(.previousIssue, systemImage: "chevron.up")
                }
                .disabled(position.index == 0)
                Button {
                    step(1, from: item)
                } label: {
                    Label(.nextIssue, systemImage: "chevron.down")
                }
                .disabled(position.index >= position.items.count - 1)
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if let entry = inboxEntry, !entry.isArchived {
                // Done with it: out of the Inbox, and back to the list.
                Button {
                    model.archive([entry])
                    navigation.pop()
                } label: {
                    Label(.archive, systemImage: "archivebox")
                }
                .accessibilityIdentifier("issue-archive")
            }
            if let url = item.webURL {
                ShareLink(item: url, subject: Text(item.title), message: Text("\(item.displayNumber) \(item.title)"), preview: SharePreview("\(item.displayNumber) \(item.title)"))
            }
            Menu {
                ItemMenuContent(item: item, showsOpen: false)
            } label: {
                Label(.more, systemImage: "ellipsis")
            }
        }
    }

    /// Where the issue sits among its project's issues, in list order, for stepping through them.
    private func position(of item: Item) -> (index: Int, items: [Item])? {
        let scope: Scope = item.projectId.map { .project($0) } ?? item.repoId.map { .repository($0) } ?? .myIssues
        let items = model.sections(for: scope).flatMap(\.items)
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return nil }
        return (index, items)
    }

    /// The issue on screen right now, from the navigation rather than from this view, which may be on its way out.
    private var currentItem: Item? {
        navigation.currentIssueId.flatMap { model.item(id: $0) }
    }

    private func stepFromCurrent(_ delta: Int) {
        if inboxEntryId != nil {
            stepInbox(delta)
        } else if let current = currentItem {
            step(delta, from: current)
        }
    }

    /// J and K on an issue opened from the Inbox: on to the next notification's issue.
    private func stepInbox(_ delta: Int) {
        let entries = model.visibleInbox
        guard let index = entries.firstIndex(where: { $0.id == inboxEntryId }) else { return }
        let target = index + delta
        guard entries.indices.contains(target), let card = model.inboxItem(for: entries[target]) else { return }
        var path = navigation.path(for: navigation.tab)
        guard !path.isEmpty else { return }
        path[path.count - 1] = .inboxIssue(entry: entries[target].id, item: card.id)
        navigation.setPath(path, for: navigation.tab)
    }

    private func assignCurrentToMe() {
        guard let current = currentItem, current.kind != .draft, let viewer = model.viewer else { return }
        model.toggleAssignee(current, viewer.person)
    }

    private func step(_ delta: Int, from item: Item) {
        guard let position = position(of: item) else { return }
        let next = position.index + delta
        guard position.items.indices.contains(next) else { return }
        var path = navigation.path(for: navigation.tab)
        guard !path.isEmpty else { return }
        path[path.count - 1] = .issue(position.items[next].id)
        navigation.setPath(path, for: navigation.tab)
    }
}

extension PickerKind: Identifiable {
    public var id: String { "\(self)" }
}

// MARK: - Title and description

private struct IssueTitleField: View {
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
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("issue-title")
        }
    }

    private var field: some View {
        TextField(.issueTitlePlaceholder, text: $title, axis: .vertical)
            .font(.title2.weight(.semibold))
            .foregroundStyle(Theme.text)
            .focused($focused)
            .submitLabel(.done)
            .accessibilityIdentifier("issue-title")
            .onAppear { title = item.title }
            .onChange(of: item.title) { _, new in
                if !focused { title = new }
            }
            .onChange(of: title) { _, new in
                // A title is one line: Return finishes it instead of breaking the line.
                guard new.contains("\n") else { return }
                title = new.replacingOccurrences(of: "\n", with: "")
                focused = false
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commit() }
            }
            .onSubmit {
                focused = false
            }
            // ⌘↵ and Escape finish the title, as on the Mac.
            .screenKey(.done, "\r", modifiers: .command, isActive: focused) { focused = false }
            .screenKey(.done, UIKeyCommand.inputEscape, isActive: focused) { focused = false }
            .accessibilityLabel(.issueTitle)
    }

    private func commit() {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            title = item.title
        } else {
            model.rename(model.item(id: item.id) ?? item, to: title)
        }
    }
}

private struct DescriptionEditor: View {
    @Environment(AppModel.self) private var model
    var item: Item
    @Binding var editing: Bool

    var body: some View {
        // Drawn as on GitHub, and a tap puts the caret where it lands.
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

// MARK: - Properties

/// The properties as chips under the title, on the iPhone.
private struct PropertyChips: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openRoute) private var openRoute
    var item: Item
    @Binding var picker: PickerKind?

    var body: some View {
        chips
            .sensoryFeedback(.selection, trigger: item.statusId)
            .sensoryFeedback(.selection, trigger: item.priorityId)
    }

    private var chips: some View {
        FlowLayout(spacing: 8) {
            Menu {
                StatusMenuItems(item: item)
            } label: {
                PropertyChip(text: model.statusText(of: item), placeholder: model.statusIsPlaceholder(item)) {
                    StatusIcon(glyph: model.glyph(of: item), size: 16)
                }
            }
            .accessibilityLabel(.statusIs(status: model.statusText(of: item)))
            .accessibilityIdentifier("chip-status")
            if model.project(of: item)?.priorityFieldId != nil {
                Menu {
                    PriorityMenuItems(item: item)
                } label: {
                    PropertyChip(text: model.priorityOption(of: item)?.name ?? String(localized: .priority), placeholder: item.priorityId == nil) {
                        PriorityIcon(level: model.priorityLevel(of: item))
                    }
                }
                .accessibilityLabel(model.priorityOption(of: item).map { .priorityIs(priority: $0.name) } ?? .priorityNone)
                .accessibilityIdentifier("chip-priority")
            }
            if item.kind != .draft {
                Button {
                    picker = .assignees
                } label: {
                    if item.assignees.isEmpty {
                        PropertyChip(text: String(localized: .assignee), placeholder: true) {
                            Image(systemName: "person").foregroundStyle(Theme.textTertiary)
                        }
                    } else {
                        PropertyChip(text: item.assignees.count == 1 ? item.assignees[0].login : String(localized: .peopleCount(count: item.assignees.count))) {
                            AvatarStack(people: item.assignees, size: 20)
                        }
                    }
                }
                .buttonStyle(PlainPressStyle())
                .accessibilityLabel(item.assignees.isEmpty ? .assigneeNone : .assigneesAre(names: item.assignees.map(\.login).joined(separator: ", ")))
                .accessibilityIdentifier("chip-assignee")
                Button {
                    picker = .labels
                } label: {
                    if item.labels.isEmpty {
                        PropertyChip(text: String(localized: .labels), placeholder: true) {
                            Image(systemName: "tag").foregroundStyle(Theme.textTertiary)
                        }
                    } else {
                        HStack(spacing: 8) {
                            ForEach(item.labels) { label in
                                PropertyChip(text: label.name) {
                                    Circle().fill(Theme.labelColor(label.color)).frame(width: 8, height: 8)
                                }
                            }
                        }
                    }
                }
                .buttonStyle(PlainPressStyle())
                .accessibilityLabel(item.labels.isEmpty ? .labelsNone : .labelsAre(names: item.labels.map(\.name).joined(separator: ", ")))
                .accessibilityIdentifier("chip-labels")
            }
            if model.canHaveDueDate(item) {
                Button {
                    picker = .dueDate
                } label: {
                    if let due = model.dueBadge(for: item) {
                        PropertyChip(text: due.day.mediumLabel(), tint: due.tone == .overdue || due.tone == .today ? due.tone.color : nil) {
                            DueDateIcon(tone: due.tone, size: 13)
                        }
                    } else {
                        PropertyChip(text: String(localized: .dueDate), placeholder: true) {
                            DueDateIcon(size: 13)
                        }
                    }
                }
                .buttonStyle(PlainPressStyle())
                .accessibilityLabel(model.dueBadge(for: item)?.tooltip ?? String(localized: .dueDateNone))
                .accessibilityIdentifier("chip-due")
            }
            if model.canHaveMilestone(item) {
                Button {
                    picker = .milestone
                } label: {
                    PropertyChip(text: model.milestoneTitle(of: item) ?? String(localized: .milestone), placeholder: item.milestoneId == nil) {
                        MilestoneIcon(mark: model.milestoneMark(of: item), size: 13)
                    }
                }
                .buttonStyle(PlainPressStyle())
                .accessibilityLabel(model.milestoneTitle(of: item).map { .milestoneTooltip(milestone: $0) } ?? .noMilestone)
                .accessibilityIdentifier("chip-milestone")
            }
            if let parentNumber = item.parentNumber {
                Button {
                    if let parentId = item.parentId, let parent = model.item(contentId: parentId) {
                        openRoute(.issue(parent.id))
                    }
                } label: {
                    if let epic = item.parentId.flatMap({ model.issue(contentId: $0) }), epic.isEpic {
                        PropertyChip(text: epic.title) { EpicIcon(size: 13) }
                    } else {
                        PropertyChip(text: String(localized: .subIssueOf(number: "#\(parentNumber)"))) {
                            SubIssueGlyph().frame(width: 12, height: 12).foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .buttonStyle(PlainPressStyle())
                .accessibilityIdentifier("chip-parent")
            } else if model.canRelate(item), !item.isEpic, let projectId = item.projectId, !model.epics(projectId: projectId).isEmpty {
                Button {
                    picker = .epic
                } label: {
                    PropertyChip(text: String(localized: .addToEpicPlaceholderShort), placeholder: true) { EpicIcon(size: 13, color: Theme.textTertiary) }
                }
                .buttonStyle(PlainPressStyle())
                .accessibilityIdentifier("chip-epic")
            }
            if item.blockedByCount > 0, model.canRelate(item) {
                Button {
                    picker = .blockedBy
                } label: {
                    PropertyChip(text: String(localized: .blockedChip)) { BlockedIcon(size: 11) }
                }
                .buttonStyle(PlainPressStyle())
                .accessibilityLabel(model.tooltip(.blockedBy, for: item))
            }
        }
    }
}

/// The properties in a column beside the issue, on a wide iPad window; the same rows as the Mac.
private struct PropertiesColumn: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openRoute) private var openRoute
    var item: Item
    @Binding var picker: PickerKind?
    /// As wide as the longest label in this language needs, and never narrower than in English.
    @State private var labelWidth: CGFloat = 88

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                row(.status) {
                    Menu {
                        StatusMenuItems(item: item)
                    } label: {
                        value {
                            StatusIcon(glyph: model.glyph(of: item), size: 15)
                            Text(model.statusText(of: item))
                                .foregroundStyle(model.statusIsPlaceholder(item) ? Theme.textTertiary : Theme.text)
                        }
                    }
                    .accessibilityLabel(.statusIs(status: model.statusText(of: item)))
                    .accessibilityIdentifier("property-status")
                }
                if model.project(of: item)?.priorityFieldId != nil {
                    row(.priority) {
                        Menu {
                            PriorityMenuItems(item: item)
                        } label: {
                            value {
                                PriorityIcon(level: model.priorityLevel(of: item))
                                Text(model.priorityOption(of: item)?.name ?? String(localized: .noPriority))
                                    .foregroundStyle(item.priorityId == nil ? Theme.textTertiary : Theme.text)
                            }
                        }
                        .accessibilityLabel(model.priorityOption(of: item).map { .priorityIs(priority: $0.name) } ?? .priorityNone)
                        .accessibilityIdentifier("property-priority")
                    }
                }
                if item.kind != .draft {
                    row(.assignee) {
                        Button { picker = .assignees } label: {
                            value {
                                if item.assignees.isEmpty {
                                    Text(.unassigned).foregroundStyle(Theme.textTertiary)
                                } else {
                                    AvatarStack(people: item.assignees, size: 20)
                                    Text(item.assignees.count == 1 ? item.assignees[0].login : String(localized: .peopleCount(count: item.assignees.count)))
                                        .foregroundStyle(Theme.text)
                                }
                            }
                        }
                        .buttonStyle(PlainPressStyle())
                        .accessibilityLabel(item.assignees.isEmpty ? .assigneeNone : .assigneesAre(names: item.assignees.map(\.login).joined(separator: ", ")))
                        .accessibilityIdentifier("property-assignee")
                    }
                    row(.labels) {
                        Button { picker = .labels } label: {
                            value {
                                if item.labels.isEmpty {
                                    Text(.addLabel).foregroundStyle(Theme.textTertiary)
                                } else {
                                    FlowLayout(spacing: 6) {
                                        ForEach(item.labels) { label in
                                            MobileChip {
                                                Circle().fill(Theme.labelColor(label.color)).frame(width: 7, height: 7)
                                                Text(label.name)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .buttonStyle(PlainPressStyle())
                        .accessibilityLabel(item.labels.isEmpty ? .labelsNone : .labelsAre(names: item.labels.map(\.name).joined(separator: ", ")))
                        .accessibilityIdentifier("property-labels")
                    }
                }
                if model.canHaveDueDate(item) {
                    row(.dueDate) {
                        Button { picker = .dueDate } label: {
                            value {
                                if let due = model.dueBadge(for: item) {
                                    DueDateIcon(tone: due.tone, size: 13)
                                    Text(due.day.mediumLabel())
                                        .foregroundStyle(due.tone == .overdue || due.tone == .today ? due.tone.color : Theme.text)
                                } else {
                                    Text(.addDueDate).foregroundStyle(Theme.textTertiary)
                                }
                            }
                        }
                        .buttonStyle(PlainPressStyle())
                        .accessibilityLabel(model.dueBadge(for: item)?.tooltip ?? String(localized: .dueDateNone))
                        .accessibilityIdentifier("property-due")
                    }
                }
                Rectangle().fill(Theme.rowSeparator).frame(height: 1).padding(.leading, 32).padding(.vertical, 12)
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
                        Menu {
                            AddToProjectMenuItems(item: item)
                        } label: {
                            value {
                                Text(.addToProjectPlaceholder).foregroundStyle(Theme.textTertiary)
                            }
                        }
                        .accessibilityIdentifier("property-project")
                    }
                }
                if model.canHaveMilestone(item) {
                    row(.milestone) {
                        Button { picker = .milestone } label: {
                            value {
                                if let title = model.milestoneTitle(of: item) {
                                    MilestoneIcon(mark: model.milestoneMark(of: item), size: 13)
                                    Text(title).foregroundStyle(Theme.text).lineLimit(1)
                                    if let due = model.milestoneGroup(of: item)?.due {
                                        Text(due.shortLabel()).foregroundStyle(Theme.textTertiary).lineLimit(1)
                                    }
                                } else {
                                    Text(.addToMilestone).foregroundStyle(Theme.textTertiary)
                                }
                            }
                        }
                        .buttonStyle(PlainPressStyle())
                        .accessibilityLabel(model.milestoneTitle(of: item).map { .milestoneTooltip(milestone: $0) } ?? .noMilestone)
                        .accessibilityIdentifier("property-milestone")
                    }
                    if item.isEpic, let span = model.milestoneSpan(of: item) {
                        row(.itsIssues) {
                            Text(span).foregroundStyle(Theme.textBody).lineLimit(1).padding(.horizontal, 8)
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
                if model.canRelate(item), !item.isEpic {
                    row(.epic) {
                        Button {
                            // Under another issue, the epic comes with that parent: it opens instead.
                            if let epic, !parentIsEpic { openRoute(.issue(epic.id)) } else { picker = .epic }
                        } label: {
                            value {
                                if let epic {
                                    EpicIcon(size: 13)
                                    Text(epic.title).foregroundStyle(Theme.text).lineLimit(1)
                                } else {
                                    Text(.addToEpicPlaceholderShort).foregroundStyle(Theme.textTertiary)
                                }
                            }
                        }
                        .buttonStyle(PlainPressStyle())
                        .accessibilityLabel(epic.map { .epicTooltip(epic: $0.title) } ?? .noEpic)
                        .accessibilityIdentifier("property-epic")
                    }
                }
                if model.canRelate(item), !parentIsEpic {
                    row(.parentIssue) {
                        Button { picker = .parent } label: {
                            value {
                                if let parentNumber = item.parentNumber {
                                    Text("#\(parentNumber)").monospacedDigit().foregroundStyle(Theme.textTertiary)
                                    Text(item.parentTitle ?? "").lineLimit(1).foregroundStyle(Theme.text)
                                } else {
                                    Text(.setParent).foregroundStyle(Theme.textTertiary)
                                }
                            }
                        }
                        .buttonStyle(PlainPressStyle())
                        .accessibilityLabel(item.parentNumber.map {
                            String(localized: .parentSpoken(number: "#\($0)", title: item.parentTitle ?? ""))
                        } ?? String(localized: .parentNoneSpoken))
                        .accessibilityIdentifier("property-parent")
                    }
                }
                if model.canRelate(item) {
                    relationRow(.blockedBy)
                    relationRow(.blocking)
                } else if let parentNumber = item.parentNumber {
                    row(.parentIssue) {
                        Button {
                            if let parentId = item.parentId, let parent = model.item(contentId: parentId) { openRoute(.issue(parent.id)) }
                        } label: {
                            value {
                                Text("#\(parentNumber) \(item.parentTitle ?? "")").lineLimit(1).foregroundStyle(Theme.text)
                            }
                        }
                        .buttonStyle(PlainPressStyle())
                    }
                }
                if let created = item.createdAt {
                    row(.created) {
                        Text(item.authorLogin.map { String(localized: .createdDateByAuthor(date: relativeDate(created), author: $0)) } ?? relativeDate(created))
                            .foregroundStyle(Theme.textBody)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                    }
                }
            }
            .font(.subheadline)
            .padding(.top, 20)
            .padding(.leading, 18)
            .padding(.trailing, 14)
        }
        .background(Theme.panel)
        .sensoryFeedback(.selection, trigger: item.statusId)
        .sensoryFeedback(.selection, trigger: item.priorityId)
    }

    private func row<Content: View>(_ title: LocalizedStringResource, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { labelWidth = max(labelWidth, $0 + 14) }
                .frame(width: labelWidth, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .frame(minHeight: 40)
    }

    private func value<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) { content() }
            .padding(.horizontal, 8)
            .frame(minHeight: 34)
            .contentShape(Rectangle())
            .hoverEffect(.highlight)
    }

    /// Blocked by or blocking: the issues' numbers, listed in full beside the description.
    private func relationRow(_ relation: LinkedIssue.Relation) -> some View {
        let links = model.links(of: item, relation)
        let count = relation == .blockedBy ? item.blockedByCount : item.blockingCount
        let title: LocalizedStringResource = relation == .blockedBy ? .blockedByHelp : .blockingHelp
        let numbers = links.isEmpty
            ? String(localized: .issuesCount(count: count)) : links.map(\.displayNumber).formatted(.list(type: .and))
        let label = switch (relation, links.isEmpty && count == 0) {
        case (.blockedBy, true): String(localized: .blockedByNoneSpoken)
        case (.blockedBy, false): String(localized: .blockedBySpoken(numbers: numbers))
        case (.blocking, true): String(localized: .blockingNoneSpoken)
        case (.blocking, false): String(localized: .blockingSpoken(numbers: numbers))
        }
        return row(title) {
            Button { picker = relation == .blockedBy ? .blockedBy : .blocking } label: {
                value {
                    if links.isEmpty, count == 0 {
                        Text(.addRelatedIssue).foregroundStyle(Theme.textTertiary)
                    } else {
                        if relation == .blockedBy { BlockedIcon() } else { BlockingIcon() }
                        Text(numbers).monospacedDigit().lineLimit(1).foregroundStyle(Theme.text)
                    }
                }
            }
            .buttonStyle(PlainPressStyle())
            .accessibilityLabel(label)
            .accessibilityIdentifier(relation == .blockedBy ? "property-blocked-by" : "property-blocking")
        }
    }
}

/// The status options as menu items with their circles, the current one checked.
struct StatusMenuItems: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    var item: Item

    var body: some View {
        if !item.isOnBoard {
            AddToProjectMenuItems(item: item)
        } else {
            picker
        }
    }

    private var picker: some View {
        Picker(.status, selection: Binding(
            get: { item.statusId },
            set: { id in
                let current = model.item(id: item.id) ?? item
                guard let option = model.statusOptions(projectId: current.projectId).first(where: { $0.id == id }) else { return }
                withAnimation(Theme.spring) { model.setStatus(current, to: option) }
            }
        )) {
            ForEach(model.statusOptions(projectId: item.projectId)) { option in
                Label {
                    Text(option.name)
                } icon: {
                    MenuImages.status(model.glyph(projectId: item.projectId, optionId: option.id), scheme)
                }
                .tag(Optional(option.id))
            }
        }
        .pickerStyle(.inline)
    }
}

struct PriorityMenuItems: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    var item: Item

    var body: some View {
        Picker(.priority, selection: Binding(
            get: { item.priorityId ?? "" },
            set: { id in
                let current = model.item(id: item.id) ?? item
                model.setPriority(current, to: model.priorityOptions(projectId: current.projectId).first { $0.id == id })
            }
        )) {
            Label {
                Text(.noPriority)
            } icon: {
                MenuImages.priority(.none, scheme)
            }
            .tag("")
            ForEach(model.priorityOptions(projectId: item.projectId)) { option in
                Label {
                    Text(option.name)
                } icon: {
                    MenuImages.priority(option.priorityLevel, scheme)
                }
                .tag(option.id)
            }
        }
        .pickerStyle(.inline)
    }
}

// MARK: - Conflicts

private struct MobileConflictBanner: View {
    @Environment(AppModel.self) private var model
    var entry: OutboxEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(message)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
            }
            .font(.subheadline)
            if let theirs {
                VStack(alignment: .leading, spacing: 4) {
                    Text(.onGitHubVersion).font(.caption.weight(.semibold)).foregroundStyle(Theme.warning)
                    Text(theirs)
                        .font(.footnote)
                        .foregroundStyle(Theme.textBody)
                        .lineLimit(8)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.warning.opacity(0.08)))
            }
            HStack(spacing: 10) {
                Button(.keepMine) { model.resolveConflict(entry, keepMine: true) }
                    .buttonStyle(.borderedProminent)
                Button(.useGitHubsVersion) { model.resolveConflict(entry, keepMine: false) }
                    .buttonStyle(.bordered)
            }
            .font(.subheadline.weight(.medium))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.warning.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.warning.opacity(0.45), lineWidth: 1))
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

private struct MobileSubIssues: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation
    var item: Item

    var body: some View {
        let detail = item.contentId.map { model.detail(for: $0) }
        let subs = model.orderedSubIssues(of: item)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(.subIssues).font(.sectionTitle)
                if !subs.isEmpty {
                    let done = subs.filter(\.isClosed).count
                    Text(.subIssuesProgress(done: done, total: subs.count))
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                        .monospacedDigit()
                    ProgressView(value: Double(done), total: Double(subs.count))
                        .progressViewStyle(ThinProgressStyle())
                        .frame(width: 64)
                }
                Spacer()
                if subs.count > 1 { MobileSubIssueOrderMenu() }
                // A new sub-issue, or an issue that exists already.
                Menu {
                    Button {
                        navigation.sheet = .newIssue(NewIssueContext(projectId: item.projectId, parentItemId: item.id))
                    } label: {
                        Label(.newSubIssue, systemImage: "plus")
                    }
                    Button {
                        navigation.sheet = .picker(itemId: item.id, kind: .addSubIssue)
                    } label: {
                        Label(.addExistingIssueMenuItem, systemImage: "magnifyingglass")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.medium))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(Theme.textSecondary)
                .accessibilityLabel(.addSubIssueButton)
                .accessibilityIdentifier("sub-add")
            }
            if let detail, !subs.isEmpty {
                let lines = model.subIssueLines(subs, in: detail)
                VStack(spacing: 0) {
                    ForEach(lines) { line in
                        MobileSubIssueRow(line: line, separated: line.id != lines.first?.id)
                    }
                }
                .animation(Theme.spring, value: lines.map(\.id))
            }
        }
    }
}

/// An epic's work, as on the Mac: how far it is, in a part per milestone, and its sub-issues by milestone.
private struct MobileEpicWork: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation
    var item: Item

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
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                        .monospacedDigit()
                }
                Spacer()
                if subs.count > 1 { MobileSubIssueOrderMenu() }
                Menu {
                    Button {
                        navigation.sheet = .newIssue(NewIssueContext(projectId: item.projectId, parentItemId: item.id))
                    } label: {
                        Label(.newSubIssue, systemImage: "plus")
                    }
                    Button {
                        navigation.sheet = .picker(itemId: item.id, kind: .addSubIssue)
                    } label: {
                        Label(.addExistingIssueMenuItem, systemImage: "magnifyingglass")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.medium))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(Theme.textSecondary)
                .accessibilityLabel(.addSubIssueButton)
                .accessibilityIdentifier("sub-add")
            }
            if subs.isEmpty {
                Text(.epicNoIssuesYet).font(.footnote).foregroundStyle(Theme.textSecondary)
            } else {
                SegmentedProgress(parts: groups.map { group in
                    SegmentedProgress.Part(
                        mark: group.group.map { model.mark(of: $0, projectId: item.projectId) } ?? .none,
                        title: group.title ?? String(localized: .noMilestone),
                        done: group.subs.filter { sub in model.issue(contentId: sub.id).map { model.isDone($0) } ?? sub.isClosed }.count,
                        total: group.subs.count
                    )
                })
                let lines = detail.map { detail in groups.map { model.subIssueLines($0.subs, in: detail) } } ?? []
                VStack(spacing: 0) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                        HStack(spacing: 8) {
                            MilestoneIcon(mark: group.group.map { model.mark(of: $0, projectId: item.projectId) } ?? .none, size: 13)
                            Text(group.title ?? String(localized: .noMilestone))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(group.title == nil ? Theme.textSecondary : Theme.text)
                            if let due = group.group?.due {
                                Text(due.shortLabel()).font(.footnote).foregroundStyle(Theme.textTertiary)
                            }
                            Text("\(group.subs.count)").font(.footnote).monospacedDigit().foregroundStyle(Theme.textTertiary)
                            Spacer()
                            if group.group?.isOpen ?? true {
                                Button {
                                    navigation.sheet = .newIssue(NewIssueContext(projectId: item.projectId, parentItemId: item.id, milestoneTitle: group.title))
                                } label: {
                                    Image(systemName: "plus")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Theme.textSecondary)
                                        .frame(width: 32, height: 32)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(PlainPressStyle())
                                .accessibilityLabel(.newSubIssueInMilestone(milestone: group.title ?? String(localized: .noMilestone)))
                            }
                        }
                        .padding(.leading, 14)
                        .padding(.trailing, 4)
                        .frame(minHeight: 40)
                        .background(Theme.groupHeader)
                        .overlay(alignment: .top) {
                            if index > 0 { Rectangle().fill(Theme.rowSeparator).frame(height: 1).padding(.leading, 32) }
                        }
                        ForEach(lines.indices.contains(index) ? lines[index] : []) { line in
                            MobileSubIssueRow(line: line, separated: true)
                        }
                    }
                }
                .animation(Theme.spring, value: lines.map { $0.map(\.id) })
            }
        }
    }
}

/// Picks the order sub-issues are listed in, for every issue.
private struct MobileSubIssueOrderMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            Picker(selection: Binding(
                get: { model.subIssueOrder },
                set: { order in withAnimation(Theme.spring) { model.subIssueOrder = order } }
            )) {
                ForEach(SubIssueOrder.allCases, id: \.self) { order in
                    Text(order.title).tag(order)
                }
            } label: {
                Text(.orderBy)
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.subheadline.weight(.medium))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .foregroundStyle(Theme.textSecondary)
        .accessibilityLabel(.orderSubIssuesTooltip)
        .accessibilityIdentifier("sub-order")
    }
}

/// A sub-issue in an issue's list of them. One with sub-issues of its own shows how far they are and an arrow that
/// unfolds them under it, indented, with lines from it as in the lists.
private struct MobileSubIssueRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openRoute) private var openRoute
    @Environment(\.colorScheme) private var scheme
    var line: SubIssueLine
    /// With a hairline over it, from where its text starts.
    var separated: Bool

    /// How much further in each level of sub-issues is: as wide as the arrow, so a sub-issue's status icon stands
    /// under its parent's arrow and their numbers line up.
    private static let indent: CGFloat = 28

    private var sub: SubIssue { line.sub }

    private var indent: CGFloat {
        CGFloat(min(line.place.depth, 4)) * Self.indent
    }

    var body: some View {
        let boardItem = model.item(contentId: sub.id)
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                // A tap shows the statuses to pick from, as the status chip does, so another pick takes a wrong one back.
                Menu {
                    statusMenu(boardItem)
                } label: {
                    StatusIcon(glyph: glyph(boardItem), size: 17)
                        .frame(width: 32, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(.subIssueStatusLabel(number: sub.number, status: statusText(boardItem)))
                .accessibilityIdentifier("sub-status-#\(sub.number)")
                .sensoryFeedback(.selection, trigger: statusText(boardItem))
                if line.progress != nil {
                    foldArrow
                }
            }
            Button {
                if let boardItem {
                    openRoute(.issue(boardItem.id))
                } else if let url = sub.url.flatMap(URL.init(string:)) {
                    Platform.open(url)
                }
            } label: {
                HStack(spacing: 10) {
                    Text(sub.number > 0 ? "#\(sub.number)" : String(localized: .unsentIssueNumber))
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                    Text(sub.title)
                        .font(.subheadline)
                        .foregroundStyle(sub.isClosed ? Theme.textSecondary : Theme.text)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let progress = line.progress {
                        MobileChip {
                            SubIssueGlyph().frame(width: 11, height: 11)
                            Text("\(progress.done)/\(progress.total)").monospacedDigit()
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(.subIssuesDone(done: progress.done.formatted(), total: progress.total))
                    }
                    if boardItem == nil, sub.url != nil {
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.textTertiary)
                            .accessibilityLabel(.opensOnGitHub)
                    }
                    if !sub.assignees.isEmpty {
                        AvatarStack(people: sub.assignees, size: 20)
                    }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainPressStyle())
            .accessibilityIdentifier("sub-#\(sub.number)")
        }
        .padding(.leading, indent)
        .background {
            TreeLines(place: line.place, firstLine: 16, indent: Self.indent, iconRadius: 8.5, deepest: 4, linesDown: line.childrenShow)
        }
        .overlay(alignment: .top) {
            if separated {
                Rectangle().fill(Theme.rowSeparator).frame(height: 1).padding(.leading, 39 + indent)
            }
        }
        // The status circle stands where a checklist's box does, in line with the text above.
        .padding(.leading, -7)
        .padding(.trailing, 2)
        // Unfolded, its sub-issues are read again each time the list shows.
        .task(id: line.unfolded) {
            if line.unfolded { await model.loadSubIssues(of: sub) }
        }
        .contextMenu {
            if let boardItem {
                ItemMenuContent(item: boardItem) { openRoute(.issue(boardItem.id)) }
            } else {
                Button {
                    withAnimation(Theme.spring) { model.setClosed(sub, !sub.isClosed) }
                } label: {
                    Label(sub.isClosed ? .reopen : .markAsDone, systemImage: sub.isClosed ? "arrow.uturn.backward" : "checkmark.circle")
                }
                Button {
                    model.removeFromParent(sub)
                } label: {
                    Label(.removeFromParentMenuItem, systemImage: "arrow.uturn.left")
                }
                if let url = sub.url {
                    Divider()
                    Button {
                        model.copyLink(url, for: "#\(sub.number) \(sub.title)")
                    } label: {
                        Label(.copyLink, systemImage: "link")
                    }
                    if let parsed = URL(string: url) {
                        Button {
                            Platform.open(parsed)
                        } label: {
                            Label(.openOnGitHub, systemImage: "arrow.up.right.square")
                        }
                    }
                }
            }
        }
    }

    /// Right after the status circle; a spinner while its sub-issues are read the first time.
    private var foldArrow: some View {
        Button {
            model.toggleSubIssues(of: sub.id)
        } label: {
            ZStack {
                if line.waiting {
                    ProgressView().controlSize(.mini)
                } else {
                    FoldArrow(unfolded: line.unfolded)
                }
            }
            // The arrow stands over the status circles of the sub-issues it unfolds.
            .frame(width: 24, height: 44)
            .frame(width: Self.indent, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainPressStyle())
        .sensoryFeedback(.selection, trigger: line.unfolded)
        .accessibilityLabel(line.unfolded ? Text(.foldSubIssuesTooltip) : Text(.unfoldSubIssuesTooltip(count: line.progress?.total ?? 0)))
        .accessibilityIdentifier("sub-fold-#\(sub.number)")
    }

    /// On a board, its columns with the current one checked. Elsewhere it is only open or closed, and an issue the
    /// app knows can go onto one of your boards too.
    @ViewBuilder
    private func statusMenu(_ boardItem: Item?) -> some View {
        if let card = card(boardItem) {
            StatusMenuItems(item: card)
        } else {
            Picker(.status, selection: Binding(
                get: { sub.isClosed },
                set: { closed in withAnimation(Theme.spring) { model.setClosed(sub, closed) } }
            )) {
                Label {
                    Text(.stateOpen)
                } icon: {
                    MenuImages.status(.openOrClosed("OPEN", reason: nil), scheme)
                }
                .tag(false)
                Label {
                    Text(.stateClosed)
                } icon: {
                    MenuImages.status(.openOrClosed("CLOSED", reason: "COMPLETED"), scheme)
                }
                .tag(true)
            }
            .pickerStyle(.inline)
            if let boardItem, !model.boards(toAdd: boardItem).isEmpty {
                Divider()
                AddToProjectMenuItems(item: boardItem)
            }
        }
    }

    private func statusText(_ boardItem: Item?) -> String {
        if let card = card(boardItem) { return model.statusText(of: card) }
        return String(localized: sub.isClosed ? .stateClosed : .stateOpen)
    }

    /// The sub-issue as a card on a board with columns to pick from.
    private func card(_ boardItem: Item?) -> Item? {
        guard let boardItem, boardItem.isOnBoard, !model.statusOptions(projectId: boardItem.projectId).isEmpty else { return nil }
        return boardItem
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

// MARK: - Relations

/// What blocks the issue and what it blocks, each under its own heading, once there is any.
private struct MobileRelations: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation
    var item: Item

    var body: some View {
        ForEach(LinkedIssue.Relation.allCases, id: \.self) { relation in
            let links = model.links(of: item, relation)
            if !links.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        if relation == .blockedBy { BlockedIcon(size: 13) } else { BlockingIcon(size: 13) }
                        Text(relation == .blockedBy ? LocalizedStringResource.blockedByHelp : .blockingHelp).font(.sectionTitle)
                        Text("\(links.count)").font(.footnote).foregroundStyle(Theme.textTertiary).monospacedDigit()
                        Spacer()
                        Button {
                            navigation.sheet = .picker(itemId: item.id, kind: relation == .blockedBy ? .blockedBy : .blocking)
                        } label: {
                            Image(systemName: "plus")
                                .font(.body.weight(.medium))
                                .frame(width: 36, height: 36)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainPressStyle())
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityLabel(relation == .blockedBy ? LocalizedStringResource.markAsBlockedByCommand : .markAsBlockingCommand)
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(links.enumerated()), id: \.element.key) { index, link in
                            MobileLinkedIssueRow(item: item, link: link)
                            if index < links.count - 1 {
                                Rectangle().fill(Theme.rowSeparator).frame(height: 1).padding(.leading, 32)
                            }
                        }
                    }
                    .animation(Theme.spring, value: links.map(\.key))
                }
                .padding(.top, 28)
            }
        }
    }
}

private struct MobileLinkedIssueRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openRoute) private var openRoute
    var item: Item
    var link: LinkedIssue

    var body: some View {
        let boardItem = model.item(contentId: link.id)
        Button {
            if let boardItem {
                openRoute(.issue(boardItem.id))
            } else if let url = link.url.flatMap(URL.init(string:)) {
                Platform.open(url)
            }
        } label: {
            HStack(spacing: 10) {
                StatusIcon(glyph: boardItem.map { model.glyph(of: $0) } ?? .openOrClosed(link.state, reason: link.stateReason), size: 17)
                    .frame(width: 24)
                Text(link.displayNumber)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                Text(link.title)
                    .font(.subheadline)
                    .foregroundStyle(link.isClosed ? Theme.textSecondary : Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if boardItem == nil, link.url != nil {
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.textTertiary)
                        .accessibilityLabel(.opensOnGitHub)
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainPressStyle())
        .accessibilityIdentifier("link-\(link.displayNumber)")
        .contextMenu {
            Button(role: .destructive) {
                model.removeLink(link, of: item)
            } label: {
                Label(.removeRelationMenuItem, systemImage: "xmark")
            }
            if let boardItem {
                Divider()
                ItemMenuContent(item: boardItem) { openRoute(.issue(boardItem.id)) }
            } else if let url = link.url {
                Divider()
                Button {
                    model.copyLink(url, for: "\(link.displayNumber) \(link.title)")
                } label: {
                    Label(.copyLink, systemImage: "link")
                }
            }
        }
    }
}

// MARK: - Comments

private struct MobileActivity: View {
    @Environment(AppModel.self) private var model
    var item: Item
    /// Comments that are new since you last read the issue, from the Inbox; they are marked.
    var highlighted: Set<String> = []

    var body: some View {
        let comments = item.contentId.map { model.detail(for: $0).comments } ?? []
        VStack(alignment: .leading, spacing: 12) {
            Text(.activity).font(.sectionTitle)
            if comments.isEmpty {
                Text(.noCommentsYet)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textTertiary)
            }
            ForEach(comments) { comment in
                let new = highlighted.contains(comment.id)
                // As a conversation reads: the face, then who and when, then what they wrote.
                HStack(alignment: .top, spacing: 10) {
                    Avatar(login: comment.authorLogin ?? "ghost", url: comment.authorAvatarUrl, size: 30)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Text(comment.authorLogin ?? "ghost").font(.subheadline.weight(.semibold))
                            Text(comment.isLocalOnly ? String(localized: .sendingComment) : relativeDate(comment.createdAt))
                                .font(.footnote)
                                .foregroundStyle(Theme.textTertiary)
                            if new {
                                Spacer(minLength: 8)
                                Text(.newCommentBadge)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.accent)
                                    .padding(.horizontal, 7)
                                    .frame(minHeight: 18)
                                    .background(Capsule().fill(Theme.menuHighlight))
                            }
                        }
                        MarkdownText(text: comment.body)
                    }
                }
                .padding(.vertical, new ? 10 : 2)
                .padding(.horizontal, new ? 12 : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background { if new { RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.selectionFill) } }
                .accessibilityElement(children: .combine)
                .accessibilityHint(new ? String(localized: .newCommentBadge) : "")
                .transition(.opacity.combined(with: .offset(y: 6)))
            }
        }
        .animation(Theme.spring, value: comments.map(\.id))
    }
}

/// The comment field at the bottom of an issue, as in Messages: it grows while typing and sends with the arrow
/// inside it, which fills with the accent colour once there is something to send.
private struct CommentComposer: View {
    @Environment(AppModel.self) private var model
    var item: Item
    @State private var draft = ""
    @State private var sent = 0
    @State private var height = EditorStyle.lineHeight
    /// The round send button, 6 points inside the field's corner, as on the Mac.
    @ScaledMetric(relativeTo: .body) private var buttonSize: CGFloat = 32

    var body: some View {
        let empty = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        HStack(alignment: .bottom, spacing: 0) {
            // Markdown as it will look on GitHub, growing with the text up to six lines and then scrolling. ⌘↵
            // sends, as on the Mac; Return alone starts a new line.
            ScrollView {
                MarkdownEditor(
                    draft: $draft,
                    placeholder: .leaveCommentPlaceholder,
                    onSubmit: send,
                    submitTitle: .sendComment,
                    accessibilityLabel: .leaveCommentPlaceholder,
                    accessibilityIdentifier: "comment-field"
                )
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            }
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(max(height, EditorStyle.lineHeight), EditorStyle.lineHeight * 6))
            .padding(.leading, 16)
            // One line is as tall as the send button's corner, as with a plain text field.
            .padding(.vertical, max(6, (buttonSize + 12 - EditorStyle.lineHeight) / 2))
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(empty ? Theme.textTertiary : Color.white)
                    .frame(width: buttonSize, height: buttonSize)
                    .background(Circle().fill(empty ? Theme.field : Theme.accentFill))
                    // The whole corner of the field takes the tap, not just the circle.
                    .frame(width: buttonSize + 12, height: buttonSize + 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainPressStyle())
            .disabled(empty)
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityLabel(.sendCommentButton)
            .accessibilityIdentifier("comment-send")
        }
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .sensoryFeedback(.success, trigger: sent)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        model.addComment(to: model.item(id: item.id) ?? item, body: text)
        draft = ""
        sent += 1
    }
}

// MARK: - Layout

/// Lays children out in rows, wrapping to the next row when one is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal: proposal, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + CGFloat(max(rows.count - 1, 0)) * spacing
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let limit = proposal.width ?? .infinity
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > limit, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let gap = rows[rows.count - 1].indices.isEmpty ? 0 : spacing
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += size.width + gap
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}
#endif
