#if os(macOS)
import SwiftUI

/// ⌘K. Runs commands on the issue in focus, jumps to issues by title or number, and hosts the
/// keyboard-driven pickers (S, P, A, L).
struct CommandPalette: View {
    @Environment(AppModel.self) private var model
    var mode: PaletteMode

    var body: some View {
        VStack(spacing: 0) {
            switch mode {
            case .root:
                RootPalette()
            case .status(let id):
                step(.status, id)
            case .priority(let id):
                step(.priority, id)
            case .assignees(let id):
                step(.assignees, id)
            case .labels(let id):
                step(.labels, id)
            case .dueDate(let id):
                step(.dueDate, id)
            case .parent(let id):
                step(.parent, id)
            case .addSubIssue(let id):
                step(.addSubIssue, id)
            case .blockedBy(let id):
                step(.blockedBy, id)
            case .blocking(let id):
                step(.blocking, id)
            case .milestone(let id):
                step(.milestone, id)
            case .epic(let id):
                step(.epic, id)
            case .views:
                PickerList(
                    placeholder: String(localized: .goToViewPlaceholder),
                    items: model.openProjects.flatMap { project in
                        model.views(projectId: project.id).map { view in
                            PickerItem(
                                id: view.id, title: view.name, subtitle: project.title,
                                selected: model.currentView?.id == view.id,
                                icon: AnyView(ViewLayoutIcon(view: view).foregroundStyle(Theme.textSecondary))
                            )
                        }
                    },
                    width: 640, maxRows: 10, fieldFont: .system(size: 17), large: true,
                    onPick: { id in
                        if let view = model.view(id: id) { model.show(view) }
                    },
                    onClose: { model.overlay = nil }
                )
            case .projects:
                PickerList(
                    placeholder: String(localized: .switchProjectPlaceholder),
                    items: model.projects.filter { !$0.closed }.map { project in
                        PickerItem(
                            id: project.id, title: project.title, subtitle: project.ownerLogin,
                            selected: model.scope == .project(project.id),
                            icon: AnyView(ProjectIcon(projectId: project.id))
                        )
                    } + planningItems + model.boardRepositories.map { repo in
                        PickerItem(
                            id: Self.repositoryPrefix + repo.id, title: repo.shortName, subtitle: repo.nameWithOwner,
                            selected: model.scope == .repository(repo.id),
                            icon: AnyView(RepositoryIcon().foregroundStyle(Theme.textSecondary))
                        )
                    },
                    width: 640, maxRows: 10, fieldFont: .system(size: 17), large: true,
                    onPick: { id in
                        if id.hasPrefix(Self.repositoryPrefix) {
                            model.select(.repository(String(id.dropFirst(Self.repositoryPrefix.count))))
                        } else if id.hasPrefix(Self.roadmapPrefix) {
                            model.select(.roadmap(String(id.dropFirst(Self.roadmapPrefix.count))))
                        } else if id.hasPrefix(Self.milestonePrefix) {
                            let parts = id.dropFirst(Self.milestonePrefix.count).split(separator: "\u{1F}", maxSplits: 1).map(String.init)
                            if parts.count == 2 { model.select(.milestone(projectId: parts[0], title: parts[1])) }
                        } else {
                            model.select(.project(id))
                        }
                    },
                    onClose: { model.overlay = nil }
                )
            }
        }
        .frame(width: 640)
        // Like Spotlight: a glass panel over the window.
        .glassPanel(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private static let repositoryPrefix = "repository:"
    private static let milestonePrefix = "milestone:"
    private static let roadmapPrefix = "roadmap:"

    /// Every open board's open milestones and its roadmap, to jump to.
    private var planningItems: [PickerItem] {
        model.openProjects.flatMap { project -> [PickerItem] in
            guard model.hasPlanning(projectId: project.id) else { return [] }
            let milestones = model.openMilestoneGroups(projectId: project.id).map { group in
                PickerItem(
                    id: Self.milestonePrefix + project.id + "\u{1F}" + group.title, title: group.title,
                    subtitle: "\(project.title) · \(String(localized: .milestone))",
                    selected: model.scope == .milestone(projectId: project.id, title: group.title),
                    icon: AnyView(MilestoneIcon(mark: model.mark(of: group, projectId: project.id)))
                )
            }
            let roadmap = PickerItem(
                id: Self.roadmapPrefix + project.id, title: String(localized: .roadmap), subtitle: project.title,
                selected: model.scope == .roadmap(project.id),
                icon: AnyView(RoadmapIcon().foregroundStyle(Theme.textSecondary))
            )
            return milestones + [roadmap]
        }
    }

    @ViewBuilder
    private func step(_ kind: PickerKind, _ itemId: String) -> some View {
        if let item = model.item(id: itemId) {
            ContextChip(item: item, count: model.targets(for: item).count)
            // A pick can open something else, such as the new-issue dialog; that stays.
            ItemPicker(kind: kind, itemId: itemId, width: 640, fieldFont: .system(size: 17), large: true) { [mode] in
                if model.overlay == .palette(mode) { model.overlay = nil }
            }
        }
    }
}

private struct ContextChip: View {
    var item: Item
    /// How many issues the command applies to; more than one when several are picked.
    var count = 1

    var body: some View {
        HStack(spacing: 6) {
            if count > 1 {
                Text(.selectedIssueCount(count: count))
            } else {
                Text(item.displayNumber).foregroundStyle(Theme.textSecondary)
                Text(item.title).lineLimit(1)
            }
        }
        .font(.small)
        .foregroundStyle(Theme.textBody)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Capsule().fill(Theme.field))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.top, 14)
    }
}

private struct PaletteCommand: Identifiable {
    var id: String
    var title: String
    /// The title in English as well, so typing a command's English name finds it in any language.
    var englishTitle: String?
    var section: String
    var icon: AnyView
    var keys: [String] = []
    var run: () -> Void
}

extension PaletteCommand {
    /// A command of the app, titled from the String Catalog.
    init(id: String, title: LocalizedStringResource, section: String, icon: AnyView, keys: [String] = [], run: @escaping () -> Void) {
        var english = title
        english.locale = Locale(identifier: "en")
        self.init(id: id, title: String(localized: title), englishTitle: String(localized: english), section: section, icon: icon, keys: keys, run: run)
    }
}

private struct RootPalette: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var index = 0
    @FocusState private var focused: Bool

    var body: some View {
        let rows = results
        VStack(spacing: 0) {
            if let target = model.actionItem {
                ContextChip(item: target, count: model.targets(for: target).count)
            }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                TextField(.commandPalettePlaceholder, text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 19))
                    .focused($focused)
                    .focusOnAppear()
            }
                .padding(.horizontal, 18)
                .frame(height: 56)
                .onKeyPress(.downArrow) {
                    index = min(index + 1, max(rows.count - 1, 0))
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    index = max(index - 1, 0)
                    return .handled
                }
                .onKeyPress(.escape) {
                    model.overlay = nil
                    return .handled
                }
                .onSubmit {
                    if rows.indices.contains(index) { run(rows[index]) }
                }
            Rectangle().fill(Theme.popoverBorder).frame(height: 1)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { position, command in
                            if position == 0 || rows[position - 1].section != command.section {
                                Text(command.section)
                                    .font(.tinySemibold)
                                    .foregroundStyle(Theme.textTertiary)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 10)
                                    .padding(.bottom, 4)
                            }
                            HStack(spacing: 10) {
                                command.icon.frame(width: 16, height: 16)
                                Text(command.title).lineLimit(1)
                                Spacer(minLength: 8)
                                HStack(spacing: 4) {
                                    ForEach(command.keys, id: \.self) { Keycap($0, emphasized: position == index) }
                                }
                            }
                            .font(.system(size: 14))
                            .padding(.horizontal, 12)
                            .frame(height: 38)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(position == index ? Theme.menuHighlight : .clear))
                            .padding(.horizontal, 8)
                            .contentShape(Rectangle())
                            .id(command.id)
                            .onTapGesture { run(command) }
                            .onHover { if $0 { index = position } }
                        }
                        if rows.isEmpty {
                            Text(.nothingMatchesQuery(query: query))
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.horizontal, 16)
                                .frame(height: 44)
                        }
                    }
                    .padding(.bottom, 6)
                }
                .scrollIndicators(.never)
                .frame(maxHeight: 400)
                .fixedSize(horizontal: false, vertical: true)
                .onChange(of: index) {
                    if rows.indices.contains(index) { proxy.scrollTo(rows[index].id) }
                }
            }
        }
        .font(.ui)
        .foregroundStyle(Theme.text)
        .onAppear { focused = true }
        .onChange(of: query) { index = 0 }
    }

    private func run(_ command: PaletteCommand) {
        // Commands that open another palette step set the overlay themselves.
        model.overlay = nil
        command.run()
    }

    private func symbol(_ name: String) -> AnyView {
        AnyView(Image(systemName: name).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textSecondary))
    }

    /// "Snooze until tomorrow (Thu 9:00)": one sentence per choice, so each reads well in every language.
    private func snoozeTitle(_ choice: SnoozeChoice) -> LocalizedStringResource {
        let time = choice.hint()
        return switch choice {
        case .laterToday: .snoozeUntilLaterTodayCommand(time: time)
        case .tomorrow: .snoozeUntilTomorrowCommand(time: time)
        case .nextWeek: .snoozeUntilNextWeekCommand(time: time)
        }
    }

    private var results: [PaletteCommand] {
        let commands = self.commands
        guard !query.isEmpty else { return commands }
        let matchedCommands = commands
            .compactMap { command -> (PaletteCommand, Int)? in
                // The shown title or the English one, whichever matches better.
                let scores = [command.title, command.englishTitle].compactMap { $0.flatMap { fuzzyScore(query, $0) } }
                return scores.max().map { (command, $0) }
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
        let pool = model.scope == .myIssues || model.scope == .inbox ? model.allItems : model.scopedItems
        let digits = query.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        let issues = pool
            .compactMap { item -> (Item, Int)? in
                if let number = item.number, !digits.isEmpty, String(number).hasPrefix(digits) { return (item, 1000 - String(number).count) }
                return fuzzyScore(query, item.title).map { (item, $0) }
            }
            .sorted { $0.1 > $1.1 }
            .prefix(8)
            .map { item, _ in
                let title = "\(item.displayNumber)  \(item.title)"
                return PaletteCommand(
                    id: "issue-\(item.id)", title: title, section: String(localized: .issues),
                    icon: AnyView(StatusIcon(glyph: model.glyph(of: item)))
                ) { model.open(item) }
            }
        return issues + matchedCommands.map { command in
            var command = command
            command.section = String(localized: .commandsSection)
            return command
        }
    }

    private var commands: [PaletteCommand] {
        var list: [PaletteCommand] = []
        if let item = model.actionItem {
            let targets = model.targets(for: item)
            let several = targets.count > 1
            let section = String(localized: several ? .selectedIssueCount(count: targets.count) : .thisIssueSection)
            list.append(PaletteCommand(id: "status", title: item.isOnBoard ? .changeStatusCommand : .addToProjectCommand, section: section, icon: AnyView(StatusIcon(glyph: model.glyph(of: item))), keys: ["S"]) {
                model.overlay = .palette(.status(itemId: item.id))
            })
            if model.project(of: item)?.priorityFieldId != nil {
                list.append(PaletteCommand(id: "priority", title: .setPriorityCommand, section: section, icon: AnyView(PriorityIcon(level: .high)), keys: ["P"]) {
                    model.overlay = .palette(.priority(itemId: item.id))
                })
            }
            if item.kind != .draft {
                list.append(PaletteCommand(id: "assign", title: .assignToCommand, section: section, icon: symbol("person"), keys: ["A"]) {
                    model.overlay = .palette(.assignees(itemId: item.id))
                })
                if let viewer = model.viewer {
                    let mine = targets.allSatisfy { target in target.assignees.contains { $0.id == viewer.id } }
                    list.append(PaletteCommand(id: "assign-me", title: mine ? .unassignMeCommand : .assignToMeCommand, section: section, icon: symbol("person.fill"), keys: ["I"]) {
                        model.toggleAssignMe(targets)
                    })
                }
                list.append(PaletteCommand(id: "labels", title: .addLabelsCommand, section: section, icon: symbol("tag"), keys: ["L"]) {
                    model.overlay = .palette(.labels(itemId: item.id))
                })
            }
            if targets.contains(where: model.canHaveDueDate) {
                list.append(PaletteCommand(id: "due", title: .setDueDateCommand, section: section, icon: symbol("calendar"), keys: ["D"]) {
                    model.overlay = .palette(.dueDate(itemId: item.id))
                })
            }
            if targets.contains(where: { $0.dueDate != nil }) {
                list.append(PaletteCommand(id: "due-remove", title: .removeDueDateCommand, section: section, icon: symbol("calendar.badge.minus")) {
                    model.setDueDate(of: targets, to: nil)
                })
            }
            if item.kind != .draft, !model.milestoneGroups(for: item).isEmpty || item.projectId != nil {
                list.append(PaletteCommand(id: "milestone", title: .moveToMilestoneCommand, section: section, icon: AnyView(MilestoneIcon(mark: model.milestoneMark(of: item))), keys: ["⇧", "M"]) {
                    model.overlay = .palette(.milestone(itemId: item.id))
                })
                if targets.contains(where: { $0.milestoneId != nil }) {
                    list.append(PaletteCommand(id: "milestone-remove", title: .removeFromMilestoneCommand, section: section, icon: AnyView(MilestoneIcon(mark: .none))) {
                        model.setMilestone(of: targets, to: nil)
                    })
                }
            }
            if model.canRelate(item), !item.isEpic {
                list.append(PaletteCommand(id: "epic", title: .addToEpicCommand, section: section, icon: AnyView(EpicIcon()), keys: ["M", "E"]) {
                    model.overlay = .palette(.epic(itemId: item.id))
                })
            }
            if model.canMakeEpic(item) {
                let epic = targets.allSatisfy(\.isEpic)
                list.append(PaletteCommand(id: "make-epic", title: epic ? .turnIntoIssueCommand : .makeEpicCommand, section: section, icon: AnyView(EpicIcon(color: Theme.textSecondary))) {
                    model.setEpic(targets, !epic)
                })
            }
            if model.canRelate(item) {
                let subIcon = AnyView(SubIssueGlyph().frame(width: 12, height: 12).foregroundStyle(Theme.textSecondary))
                if !several {
                    list.append(PaletteCommand(id: "sub", title: .createSubIssueCommand, section: section, icon: subIcon) {
                        model.overlay = .newIssue(statusId: nil, parentItemId: item.id)
                    })
                    list.append(PaletteCommand(id: "sub-existing", title: .addExistingSubIssueCommand, section: section, icon: subIcon) {
                        model.overlay = .palette(.addSubIssue(itemId: item.id))
                    })
                }
                list.append(PaletteCommand(id: "parent", title: .setParentIssueCommand, section: section, icon: symbol("arrow.turn.left.up"), keys: ["M", "P"]) {
                    model.overlay = .palette(.parent(itemId: item.id))
                })
                if targets.contains(where: { $0.parentId != nil }) {
                    list.append(PaletteCommand(id: "parent-remove", title: .removeFromParentCommand, section: section, icon: symbol("xmark")) {
                        model.setParent(of: targets, to: nil)
                    })
                }
                list.append(PaletteCommand(id: "blocked-by", title: .markAsBlockedByCommand, section: section, icon: AnyView(BlockedIcon()), keys: ["M", "B"]) {
                    model.overlay = .palette(.blockedBy(itemId: item.id))
                })
                list.append(PaletteCommand(id: "blocking", title: .markAsBlockingCommand, section: section, icon: AnyView(BlockingIcon()), keys: ["M", "X"]) {
                    model.overlay = .palette(.blocking(itemId: item.id))
                })
            }
            if model.canDelete(item), !several {
                list.append(PaletteCommand(id: "delete", title: item.kind == .draft ? .deleteDraftCommand : .deleteIssueCommand, section: section, icon: symbol("trash"), keys: ["⌘", "⌫"]) {
                    model.requestDelete(item)
                })
            }
            if item.url != nil {
                list.append(PaletteCommand(id: "copy", title: several ? .copyGitHubLinksCommand : .copyGitHubLinkCommand, section: section, icon: symbol("link"), keys: ["⌘", "⇧", "C"]) {
                    model.copyLinks(targets)
                })
                if !several {
                    list.append(PaletteCommand(id: "github", title: .openOnGitHub, section: section, icon: symbol("arrow.up.right")) {
                        model.openOnGitHub(item)
                    })
                }
            }
        }
        if model.openItem == nil, !model.orderedItems.isEmpty {
            list.append(PaletteCommand(id: "select-all", title: .selectAllIssuesCommand, section: String(localized: .selectionSection), icon: symbol("checkmark.circle"), keys: ["⌘", "A"]) {
                model.selectAll()
            })
            if !model.selectedIds.isEmpty {
                list.append(PaletteCommand(id: "select-none", title: .clearSelectionCommand, section: String(localized: .selectionSection), icon: symbol("xmark.circle"), keys: ["Esc"]) {
                    model.clearSelection()
                })
            }
        }
        if model.scope == .inbox {
            let entries = model.inboxPicked.isEmpty
                ? model.inboxSelected.map { [$0] } ?? []
                : model.visibleInbox.filter { model.inboxPicked.contains($0.id) }
            let section = String(localized: entries.count > 1 ? .selectedNotificationCount(count: entries.count) : .inbox)
            if let first = entries.first {
                let unread = model.isUnread(first)
                list.append(PaletteCommand(id: "inbox-read", title: unread ? .markAsReadCommand : .markAsUnreadCommand, section: section, icon: symbol(unread ? "circle" : "circle.inset.filled"), keys: ["U"]) {
                    model.toggleRead(entries)
                })
                list.append(PaletteCommand(id: "inbox-archive", title: .archive, section: section, icon: symbol("archivebox"), keys: ["E"]) {
                    model.archive(entries)
                })
                for choice in SnoozeChoice.allCases {
                    list.append(PaletteCommand(id: "inbox-snooze-\(choice)", title: snoozeTitle(choice), section: section, icon: symbol("clock")) {
                        model.snooze(entries, until: choice.date())
                    })
                }
                list.append(PaletteCommand(id: "inbox-unsubscribe", title: .unsubscribe, section: section, icon: symbol("bell.slash"), keys: ["⇧", "S"]) {
                    model.unsubscribe(entries)
                })
            }
            list.append(PaletteCommand(id: "inbox-read-all", title: .markAllAsReadCommand, section: String(localized: .inbox), icon: symbol("circle"), keys: ["⌥", "U"]) {
                model.markAllRead()
            })
            list.append(PaletteCommand(id: "inbox-archive-read", title: .archiveAllReadCommand, section: String(localized: .inbox), icon: symbol("archivebox"), keys: ["⇧", "⌫"]) {
                model.archiveAllRead()
            })
        }
        let go = String(localized: .goToSection)
        if model.scope != .inbox {
            list.append(PaletteCommand(id: "inbox", title: .inbox, section: go, icon: symbol("tray"), keys: ["G", "I"]) {
                model.select(.inbox)
            })
        }
        if model.currentProjectId != nil || model.currentRepositoryId != nil {
            list.append(PaletteCommand(id: "new", title: .newIssueAction, section: go, icon: symbol("plus"), keys: ["C"]) {
                model.overlay = .newIssue(statusId: nil, parentItemId: nil)
            })
        }
        if model.currentProjectId != nil {
            list.append(PaletteCommand(id: "board", title: .board, section: go, icon: symbol("rectangle.split.3x1"), keys: ["G", "B"]) {
                model.closeDetail()
                model.viewMode = .board
            })
            list.append(PaletteCommand(id: "list", title: .list, section: go, icon: symbol("list.bullet"), keys: ["G", "L"]) {
                model.closeDetail()
                model.viewMode = .list
            })
        }
        if model.currentView != nil || model.scope == .myIssues {
            list.append(PaletteCommand(id: "filter", title: .filterEllipsis, section: go, icon: symbol("line.3.horizontal.decrease"), keys: ["F"]) {
                model.overlay = nil
                model.filterMenuRequest += 1
            })
            list.append(PaletteCommand(id: "display", title: .displayOptions, section: go, icon: symbol("slider.horizontal.3"), keys: ["⇧", "V"]) {
                model.overlay = nil
                model.displayMenuRequest += 1
            })
        }
        if model.scope == .myIssues, !model.mineFilter.isEmpty {
            list.append(PaletteCommand(id: "clear-filter", title: .clearFilter, section: go, icon: symbol("line.3.horizontal.decrease.circle")) {
                model.setMineFilter(ProjectFilter(""))
            })
        }
        if let view = model.currentView {
            if model.filterChanged(view), model.canEditViews(projectId: view.projectId) {
                list.append(PaletteCommand(id: "save-view", title: .saveViewMenu, section: go, icon: symbol("square.and.arrow.down"), keys: ["⌘", "S"]) {
                    model.saveFilter(of: view)
                })
            }
            if model.canEditViews(projectId: view.projectId) {
                list.append(PaletteCommand(id: "new-view", title: .newViewEllipsis, section: go, icon: symbol("plus.rectangle.on.rectangle")) {
                    model.overlay = nil
                    model.newViewRequest += 1
                })
            }
        }
        if !model.views.isEmpty {
            list.append(PaletteCommand(id: "views", title: .goToViewEllipsis, section: go, icon: symbol("rectangle.stack")) {
                model.overlay = .palette(.views)
            })
        }
        if let projectId = model.scopeProjectId {
            if model.sidebarProject?.id == projectId {
                // Opens under the project at the top of the sidebar.
                list.append(PaletteCommand(id: "project-icon", title: .changeProjectIconEllipsis, section: go, icon: AnyView(ProjectIcon(projectId: projectId))) {
                    model.overlay = nil
                    model.projectIconRequest += 1
                })
            }
            if model.scope != .roadmap(projectId) {
                list.append(PaletteCommand(id: "roadmap", title: .roadmap, section: go, icon: AnyView(RoadmapIcon().foregroundStyle(Theme.textSecondary)), keys: ["G", "R"]) {
                    model.select(.roadmap(projectId))
                })
            }
            if model.projects.first(where: { $0.id == projectId })?.viewerCanUpdate == true {
                list.append(PaletteCommand(id: "new-milestone", title: .newMilestoneEllipsis, section: go, icon: AnyView(MilestoneIcon(mark: .upcoming))) {
                    model.overlay = .milestoneEditor(projectId: projectId, title: nil, assigning: [])
                })
                list.append(PaletteCommand(id: "new-epic", title: .newEpic, section: go, icon: AnyView(EpicIcon())) {
                    model.newIssuePlan = NewIssuePlan(isEpic: true)
                    model.overlay = .newIssue(statusId: nil, parentItemId: nil)
                })
            }
            if case .milestone(_, let title) = model.scope, let group = model.milestoneGroup(projectId: projectId, title: title) {
                list.append(PaletteCommand(id: "edit-milestone", title: .editMilestoneEllipsis, section: go, icon: symbol("pencil")) {
                    model.overlay = .milestoneEditor(projectId: projectId, title: title, assigning: [])
                })
                if group.isOpen {
                    list.append(PaletteCommand(id: "complete-milestone", title: .completeMilestoneEllipsis, section: go, icon: symbol("checkmark.circle")) {
                        model.milestoneToComplete = MilestoneRef(projectId: projectId, title: title)
                    })
                }
            }
        }
        list.append(PaletteCommand(id: "mine", title: .myIssues, section: go, icon: symbol("scope"), keys: ["G", "M"]) {
            model.select(.myIssues)
        })
        list.append(PaletteCommand(id: "projects", title: .switchProjectCommand, section: go, icon: symbol("square.stack"), keys: ["G", "P"]) {
            model.overlay = .palette(.projects)
        })
        if model.canGoBack {
            list.append(PaletteCommand(id: "back", title: .back, section: go, icon: symbol("chevron.left"), keys: ["⌘", "["]) {
                model.goBack()
            })
        }
        if model.canGoForward {
            list.append(PaletteCommand(id: "forward", title: .forward, section: go, icon: symbol("chevron.right"), keys: ["⌘", "]"]) {
                model.goForward()
            })
        }
        for setting in AppearanceSetting.allCases where setting != model.appearance {
            list.append(PaletteCommand(id: "appearance-\(setting.rawValue)", title: .appearanceCommand(appearance: setting.title), section: String(localized: .settingsSection), icon: symbol("circle.lefthalf.filled")) {
                model.appearance = setting
            })
        }
        list.append(PaletteCommand(id: "settings", title: .settingsEllipsis, section: String(localized: .settingsSection), icon: symbol("gearshape"), keys: ["⌘", ","]) {
            model.settingsRequest += 1
        })
        list.append(PaletteCommand(id: "refresh", title: .syncWithGitHubNowCommand, section: go, icon: symbol("arrow.triangle.2.circlepath"), keys: ["⌘", "R"]) {
            model.refresh()
        })
        return list
    }
}
#endif
