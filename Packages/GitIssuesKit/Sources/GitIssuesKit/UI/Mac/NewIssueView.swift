#if os(macOS)
import SwiftUI

struct NewIssueView: View {
    @Environment(AppModel.self) private var model
    var statusId: String?
    var parentItemId: String?

    @State private var draft = NewIssueDraft(projectId: nil)
    @State private var openPicker: PickerKind?
    /// Whether this is a draft from last time, which can be thrown away to start over.
    @State private var restored = false
    @State private var created = false
    @FocusState private var focus: Field?
    @State private var editingBody = false
    @State private var bodyHeight: CGFloat = 110
    @State private var titleLink = TitleLink()

    private enum Field {
        case title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if choosesProject {
                    // In All Issues, the issue can go on the board or on none, like Linear's project chip; where no
                    // board is on screen, on any of yours.
                    GlassMenuPicker {
                        let menu = MenuBuilder()
                        for project in boards {
                            menu.item(project.title, checked: draft.projectId == project.id) { selectProject(project.id) }
                        }
                        if inAllIssues {
                            menu.divider()
                            menu.item(.noProject, checked: draft.projectId == nil) { selectProject(nil) }
                        }
                        return menu.build()
                    } label: {
                        projectChip
                    }
                    .fixedSize()
                    .help(Text(.newIssueBoardTooltip))
                } else {
                    projectChip
                }
                Text("›").foregroundStyle(Theme.textTertiary)
                Text(draft.isEpic ? .newEpicHeader : draft.parent == nil ? .newIssueHeader : .newSubIssueHeader).font(.small).foregroundStyle(Theme.textSecondary)
                Spacer()
                if restored {
                    // Closing the dialog keeps what was typed, as in Linear; this starts over instead.
                    Button(.discardDraft) {
                        model.unsentNewIssue = nil
                        prepare()
                        focus = .title
                    }
                    .buttonStyle(PlainPressStyle())
                    .font(.small)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.trailing, 4)
                }
                IconButton(systemName: "xmark", label: String(localized: .closeWithEscShortcut)) { model.overlay = nil }
            }
            .padding(.leading, 18)
            .padding(.trailing, 14)
            .padding(.top, 14)

            VStack(alignment: .leading, spacing: 8) {
                TextField(.issueTitlePlaceholder, text: $draft.title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 21, weight: .semibold))
                    .focused($focus, equals: .title)
                    .focusOnAppear()
                    // Return, Tab, ↓ and → at the end go on to the start of the description.
                    .onSubmit { titleLink.enterText() }
                    .titleOf(titleLink) { focus = .title }

                // The description as it will look on GitHub, growing with the text up to a point and then scrolling.
                ScrollView {
                    MarkdownEditor(
                        draft: $draft.body,
                        placeholder: .addDescriptionPlaceholder,
                        editing: $editingBody,
                        onSubmit: create,
                        onEscape: { model.overlay = nil },
                        titleLink: titleLink,
                        accessibilityLabel: .description,
                        accessibilityIdentifier: "new-description"
                    )
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bodyHeight = $0 }
                    // A click below the text puts the caret at its end.
                    .frame(minHeight: 110, alignment: .top)
                    .background { Color.clear.contentShape(.rect).onTapGesture { editingBody = true } }
                }
                .scrollIndicators(.never)
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: min(max(bodyHeight, 110), 360))
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 8)

            HStack(spacing: 6) {
                if draft.projectId != nil {
                    chip(.status) {
                        StatusIcon(glyph: model.glyph(projectId: draft.projectId, optionId: draft.statusId))
                        (statuses.first { $0.id == draft.statusId }.map { Text($0.name) } ?? Text(.noStatus))
                    }
                }
                if !priorities.isEmpty {
                    chip(.priority) {
                        let option = priorities.first { $0.id == draft.priorityId }
                        PriorityIcon(level: option?.priorityLevel ?? .none)
                        (option.map { Text($0.name) } ?? Text(.priority))
                    }
                }
                chip(.assignees) {
                    if draft.assignees.isEmpty {
                        Image(systemName: "person").font(.system(size: 11, weight: .medium))
                        Text(.assignee)
                    } else {
                        AvatarStack(people: draft.assignees, size: 16)
                        draft.assignees.count == 1 ? Text(draft.assignees[0].login) : Text(.peopleCount(count: draft.assignees.count))
                    }
                }
                chip(.labels) {
                    if draft.labels.isEmpty {
                        Image(systemName: "tag").font(.system(size: 11, weight: .medium))
                        Text(.labels)
                    } else {
                        Circle().fill(Theme.labelColor(draft.labels[0].color)).frame(width: 7, height: 7)
                        draft.labels.count == 1 ? Text(draft.labels[0].name) : Text(.labelCount(count: draft.labels.count))
                    }
                }
                // The date is a field of the board, so an issue going on none has no date.
                if draft.projectId != nil {
                    chip(.dueDate) {
                        DueDateIcon(size: 11)
                        (draft.dueDate.flatMap(CalendarDay.init).map { Text($0.mediumLabel()) } ?? Text(.dueDate))
                    }
                }
                if draft.milestoneTitle != nil || !milestones.isEmpty {
                    chip(.milestone) {
                        let group = milestones.first { $0.title == draft.milestoneTitle }
                        MilestoneIcon(mark: group.map { model.mark(of: $0, projectId: draft.projectId) } ?? .none, size: 12)
                        (draft.milestoneTitle.map { Text($0) } ?? Text(.milestone))
                    }
                }
                if let parent = draft.parent {
                    HStack(spacing: 6) {
                        if parent.isEpic {
                            EpicIcon(size: 12)
                            Text(parent.title).frame(maxWidth: 180, alignment: .leading)
                        } else {
                            SubIssueGlyph().frame(width: 12, height: 12)
                            Text(.subIssueOf(number: parent.displayNumber))
                        }
                    }
                    .font(.small)
                    .foregroundStyle(Theme.textBody)
                    .padding(.horizontal, 11)
                    .frame(height: 28)
                    .background(Capsule().fill(Theme.field))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 14)

            Rectangle().fill(Theme.popoverBorder).frame(height: 1)

            HStack(spacing: 10) {
                Text(.repository).font(.small).foregroundStyle(Theme.textSecondary)
                GlassMenuPicker {
                    let menu = MenuBuilder()
                    for repo in repos {
                        menu.item(repo.nameWithOwner, "book.closed", checked: draft.repoId == repo.id) { selectRepo(repo.id) }
                    }
                    return menu.build()
                } label: {
                    HStack(spacing: 4) {
                        (repos.first { $0.id == draft.repoId }.map { Text($0.nameWithOwner) } ?? Text(.chooseRepositoryPlaceholder))
                        if !(draft.parent != nil || repos.count < 2) {
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .font(.small)
                    .foregroundStyle(Theme.textBody)
                }
                .fixedSize()
                .disabled(draft.parent != nil || repos.count < 2)
                Spacer()
                Text("⌘↵").font(.tiny).foregroundStyle(Theme.textSecondary)
                Button(draft.isEpic ? .createEpicButton : .createIssueMac, action: create)
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canCreate)
            }
            .padding(.leading, 18)
            .padding(.trailing, 14)
            .padding(.vertical, 12)
        }
        .frame(width: 720)
        .font(.ui)
        .foregroundStyle(Theme.text)
        // A glass panel over the window, as the command palette.
        .glassPanel(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onAppear(perform: prepare)
        .onDisappear {
            guard !created else { return }
            let typed = !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            model.unsentNewIssue = typed ? draft : nil
        }
        .task {
            try? await Task.sleep(for: .milliseconds(300))
            if focus == nil, !editingBody { focus = .title }
        }
        .onExitCommand { model.overlay = nil }
    }

    private var statuses: [FieldOption] { model.statusOptions(projectId: draft.projectId) }
    /// The open milestones the issue can start in: its board's, or its repository's on no board.
    private var milestones: [MilestoneGroup] {
        let groups = draft.projectId.map { model.milestoneGroups(projectId: $0) } ?? model.milestoneGroups(repoId: draft.repoId)
        return groups.filter(\.isOpen)
    }
    private var priorities: [FieldOption] { model.priorityOptions(projectId: draft.projectId) }
    /// The board's repositories, also for an issue started on none in All Issues.
    private var repos: [RepoRef] {
        if inAllIssues, let id = model.allIssuesProjectId { return model.repos(projectId: id) }
        return model.repos(forNewIssueIn: draft.projectId, repoId: draft.repoId)
    }

    /// A new issue started in All Issues chooses between the board and none, and one started where no board is on
    /// screen (My Issues, the Inbox) chooses its board; on a board, a milestone or a roadmap it goes on that board.
    private var choosesProject: Bool {
        draft.parent == nil && (inAllIssues || model.scopeProjectId == nil)
    }

    /// Started in All Issues, the issue goes on the board or on none, in one of the board's repositories.
    private var inAllIssues: Bool {
        model.allIssuesProjectId != nil && draft.parent == nil
    }

    private var boards: [Project] {
        if let id = model.allIssuesProjectId { return model.openProjects.filter { $0.id == id && $0.viewerCanUpdate } }
        return model.openProjects.filter { $0.viewerCanUpdate && (!model.hiddenProjectIds.contains($0.id) || $0.id == draft.projectId) }
    }

    @ViewBuilder
    private var projectChip: some View {
        HStack(spacing: 6) {
            if let project = model.projects.first(where: { $0.id == draft.projectId }) {
                ProjectIcon(projectId: project.id, size: 10)
                Text(project.title)
            } else {
                RepositoryIcon(size: 10)
                ((repos.first { $0.id == draft.repoId } ?? repos.first).map { Text($0.shortName) } ?? Text(.noProject))
            }
            if choosesProject {
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(Theme.textTertiary)
            }
        }
        .font(.small)
        .foregroundStyle(Theme.textBody)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.controlActive))
    }

    private func selectProject(_ id: String?) {
        guard id != draft.projectId else { return }
        draft.projectId = id
        // Another board brings its own repository along; in All Issues the issue stays in the one chosen.
        if !inAllIssues { draft.repoId = id.flatMap { model.defaultRepoId(projectId: $0) } ?? draft.repoId }
        draft.statusId = defaultStatus(projectId: id)
        draft.priorityId = nil
        if let title = draft.milestoneTitle, !milestones.contains(where: { $0.title == title }) { draft.milestoneTitle = nil }
        if let id { model.loadRepoMeta(projectId: id) }
    }

    /// What a new issue starts with in the view on screen; none for sub-issues and planned ones.
    private func viewPreset(projectId: String?, parent: Item?, planned: Bool) -> NewIssuePreset? {
        guard parent == nil, !planned, model.currentView != nil, projectId == model.currentProjectId else { return nil }
        return model.newIssuePreset(projectId: projectId)
    }

    /// The status the dialog was opened with; "No status" (from that column's plus) is none.
    private func chosenStatus(_ id: String) -> String? {
        id == BoardColumn.noStatusId ? nil : id
    }

    private func defaultStatus(projectId: String?) -> String? {
        let options = model.statusOptions(projectId: projectId)
        return options.first { $0.statusCategory == .unstarted }?.id
            ?? options.first { $0.statusCategory == .backlog }?.id
            ?? options.first?.id
    }

    private var canCreate: Bool {
        !draft.title.trimmingCharacters(in: .whitespaces).isEmpty && draft.repoId != nil
    }

    private func prepare() {
        let parent = parentItemId.flatMap { id in model.allItems.first { $0.id == id } }
        // A sub-issue goes where its parent is, on its board or on none; any other on the board on screen, also under
        // its roadmap or in its All Issues, and elsewhere on the one open last.
        let projectId: String? = if let parent { parent.projectId } else { model.scopeProjectId ?? model.sidebarProject?.id }
        // A sub-issue lives in its parent's repository.
        let repoId = parent?.repoId ?? projectId.flatMap { model.defaultRepoId(projectId: $0) }
        // A title typed into the sub-issue picker starts a fresh issue rather than last time's.
        let typed = model.newIssueTitle
        model.newIssueTitle = nil
        // Begun in a view's column or group: that value, so not last time's issue either.
        let groupPreset = model.newIssuePreset
        model.newIssuePreset = nil
        // Begun in a milestone, or from the roadmap: in that milestone, or as an epic.
        let plan = model.newIssuePlan ?? NewIssuePlan()
        model.newIssuePlan = nil
        let milestone = plan.milestoneTitle ?? model.currentMilestoneTitle
            ?? parent.flatMap { $0.isEpic ? nil : model.milestoneTitle(of: $0) }
        // In All Issues, also one left on no board in one of its repositories.
        let onNoBoardHere = parent == nil && unsent(onNoBoardIn: model.allIssuesProjectId)
        if typed == nil, groupPreset == nil, let unsent = model.unsentNewIssue, unsent.parent?.id == parent?.id, unsent.isEpic == plan.isEpic,
           model.scopeProjectId == nil || unsent.projectId == projectId || onNoBoardHere {
            draft = unsent
            if let statusId { draft.statusId = chosenStatus(statusId) }
            if let milestone { draft.milestoneTitle = milestone }
            restored = true
            focus = .title
            model.loadRepoMeta(projectId: draft.projectId)
            return
        }
        restored = false
        var new = NewIssueDraft(projectId: projectId)
        new.parent = parent
        new.repoId = repoId
        new.statusId = statusId.map(chosenStatus) ?? defaultStatus(projectId: projectId)
        new.title = typed ?? ""
        // Begun in My Issues, it is yours, so it shows up there, as on iPhone and iPad.
        if model.scope == .myIssues, parent == nil, let viewer = model.viewer { new.assignees = [viewer.person] }
        new.milestoneTitle = milestone
        new.isEpic = plan.isEpic
        // Begun in a view: what its filter asks for, and its column's or group's value, as on GitHub.
        if let preset = groupPreset ?? viewPreset(projectId: projectId, parent: parent, planned: plan != NewIssuePlan()) {
            model.apply(preset, to: &new)
            if let statusId { new.statusId = chosenStatus(statusId) }
        }
        draft = new
        focus = .title
        model.loadRepoMeta(projectId: projectId)
        if projectId == nil, let parent { model.loadRepoMeta(for: parent) }
    }

    /// Whether the issue left unsent was on no board, in a repository of this board.
    private func unsent(onNoBoardIn projectId: String?) -> Bool {
        guard let projectId, let unsent = model.unsentNewIssue, unsent.projectId == nil else { return false }
        return model.repos(projectId: projectId).contains { $0.id == unsent.repoId }
    }

    private func selectRepo(_ id: String) {
        guard id != draft.repoId else { return }
        draft.repoId = id
        // Labels belong to a repository, so a choice made for another one no longer applies.
        draft.labels = []
    }

    private func create() {
        guard canCreate else { return }
        if let id = model.createIssue(draft) {
            created = true
            model.unsentNewIssue = nil
            model.overlay = nil
            model.noteIfHidden(id)
            // The new issue takes the keyboard focus, so Return opens it and S, A or L change it right away; a folded
            // section or parent it went into opens for it.
            if model.openItem == nil, model.scopedItems.contains(where: { $0.id == id }) {
                model.reveal(id)
                // Not in a column you hid, where it doesn't show.
                if model.orderedItems.contains(where: { $0.id == id }) { model.moveFocus(to: id) }
            }
        }
    }

    private func chip<Content: View>(_ kind: PickerKind, @ViewBuilder content: () -> Content) -> some View {
        Button {
            openPicker = kind
        } label: {
            // Capsules in a row, as Reminders offers what can be set while you type.
            HStack(spacing: 6) { content() }
                .font(.small)
                .foregroundStyle(Theme.textBody)
                .lineLimit(1)
                .padding(.horizontal, 11)
                .frame(height: 28)
                .background(Capsule().fill(openPicker == kind ? Theme.controlActive : Theme.field))
        }
        .buttonStyle(PlainPressStyle())
        .dropdown(isPresented: Binding(get: { openPicker == kind }, set: { if !$0 { openPicker = nil } })) { close in
            if kind == .dueDate {
                DueDatePicker(
                    current: [draft.dueDate],
                    addsField: model.projects.first { $0.id == draft.projectId }?.dueFieldId == nil,
                    width: kind.width,
                    onPick: { draft.dueDate = $0?.string },
                    onClose: close
                )
            } else {
                PickerList(
                    placeholder: kind.placeholder,
                    items: items(kind),
                    multiple: kind.multiple,
                    width: kind.width,
                    creating: kind == .labels ? { model.newLabelRow($0, projectId: draft.projectId, repoId: draft.repoId) } : nil,
                    onPick: { pick(kind, $0) },
                    onClose: close
                )
            }
        }
    }

    private func items(_ kind: PickerKind) -> [PickerItem] {
        switch kind {
        case .status:
            // "No status" while the issue has none, as one made in that column.
            let none = draft.statusId == nil && draft.projectId != nil
                ? [PickerItem(id: "", title: String(localized: .noStatus), selected: true, icon: AnyView(StatusIcon(glyph: .none)))] : []
            return none + statuses.map { option in
                PickerItem(id: option.id, title: option.name, selected: draft.statusId == option.id, icon: AnyView(StatusIcon(glyph: model.glyph(projectId: draft.projectId, optionId: option.id))))
            }
        case .priority:
            return [PickerItem(id: "", title: String(localized: .noPriority), selected: draft.priorityId == nil, icon: AnyView(PriorityIcon(level: .none)))]
                + priorities.map { option in
                    PickerItem(id: option.id, title: option.name, selected: draft.priorityId == option.id, icon: AnyView(PriorityIcon(level: option.priorityLevel)))
                }
        case .assignees:
            return model.recentFirst(model.people(projectId: draft.projectId, repoId: draft.repoId).map { person in
                PickerItem(
                    id: person.id, title: person.login, subtitle: person.name,
                    selected: draft.assignees.contains { $0.id == person.id },
                    icon: AnyView(Avatar(login: person.login, url: person.avatarUrl, size: 18))
                )
            }, .assignee)
        case .labels:
            return model.recentFirst(model.pickableLabels(projectId: draft.projectId, repoId: draft.repoId).map { label in
                PickerItem(
                    id: label.id, title: label.name, selected: draft.labels.contains { $0.id == label.id },
                    icon: AnyView(Circle().fill(Theme.labelColor(label.color)).frame(width: 9, height: 9))
                )
            }, .label, key: \.title)
        case .milestone:
            let numbered = AppModel.numbersPickMilestones(milestones.map(\.title))
            return [PickerItem(
                id: "", title: String(localized: .noMilestone), selected: draft.milestoneTitle == nil,
                icon: AnyView(MilestoneIcon(mark: .none)), shortcut: numbered ? "0" : nil
            )] + milestones.enumerated().map { index, group in
                PickerItem(
                    id: group.id, title: group.title, selected: draft.milestoneTitle == group.title,
                    icon: AnyView(MilestoneIcon(mark: model.mark(of: group, projectId: draft.projectId))),
                    shortcut: numbered && index < 9 ? "\(index + 1)" : nil,
                    trailing: group.due.map { AnyView(Text($0.shortLabel()).font(.small).foregroundStyle(Theme.textTertiary)) }
                )
            }
        case .dueDate, .subIssues, .parent, .addSubIssue, .blockedBy, .blocking, .epic:
            return []
        }
    }

    private func pick(_ kind: PickerKind, _ id: String) {
        switch kind {
        case .status:
            draft.statusId = id.isEmpty ? nil : id
        case .priority:
            draft.priorityId = id.isEmpty ? nil : id
        case .assignees:
            if let index = draft.assignees.firstIndex(where: { $0.id == id }) {
                draft.assignees.remove(at: index)
            } else if let person = model.people(projectId: draft.projectId, repoId: draft.repoId).first(where: { $0.id == id }) {
                draft.assignees.append(person)
                model.noteRecent(.assignee, person.id)
            }
        case .labels:
            if let name = AppModel.newLabelName(id) {
                if let label = model.labelForNewIssue(named: name, projectId: draft.projectId, repoId: draft.repoId),
                   !draft.labels.contains(where: { $0.id == label.id }) {
                    draft.labels.append(label)
                }
            } else if let index = draft.labels.firstIndex(where: { $0.id == id }) {
                draft.labels.remove(at: index)
            } else if let label = model.pickableLabels(projectId: draft.projectId, repoId: draft.repoId).first(where: { $0.id == id }) {
                draft.labels.append(label)
                model.noteRecent(.label, label.name)
            }
        case .dueDate:
            draft.dueDate = CalendarDay(id)?.string
        case .milestone:
            draft.milestoneTitle = id.isEmpty ? nil : id
        case .subIssues, .parent, .addSubIssue, .blockedBy, .blocking, .epic:
            break
        }
    }
}
#endif
