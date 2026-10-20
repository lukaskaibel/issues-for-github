#if os(iOS)
import SwiftUI

/// Everything that can be done to an issue, as one menu: what a long press on a row, a card or a
/// sub-issue shows, and the same as the Mac's right-click menu. On a picked sub-issue it changes all picked ones.
struct ItemMenuContent: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation
    @Environment(\.colorScheme) private var scheme
    var item: Item
    /// Whether sub-issues hang under the issue where it shows, to fold them in or out.
    var foldable = false
    /// Hidden in the issue's own screen, where it is open already.
    var showsOpen = true
    /// On a sub-issue in its parent's list: picks it, to change several together.
    var onSelect: (() -> Void)? = nil
    var onOpen: () -> Void = {}

    var body: some View {
        let targets = model.targets(for: item)
        if targets.count > 1 {
            several(targets)
        } else {
            one
        }
    }

    @ViewBuilder
    private var one: some View {
        if showsOpen {
            Button(action: onOpen) {
                Label(.openIssue, systemImage: "arrow.up.left.and.arrow.down.right")
            }
            if let onSelect {
                Button(action: onSelect) {
                    Label(.select, systemImage: "checkmark.circle")
                }
            }
            if foldable {
                let folded = model.isFolded(item)
                Button {
                    model.toggleFolded(item)
                } label: {
                    Label(folded ? .unfoldSubIssuesMenuItem : .foldSubIssuesMenuItem, systemImage: folded ? "chevron.down" : "chevron.right")
                }
            }
            Divider()
        }
        properties([item])
        if model.canRelate(item) {
            Divider()
            RelationMenuItems(item: item)
        }
        if let url = item.webURL {
            Divider()
            Button {
                model.copyLink(item)
            } label: {
                Label(.copyLink, systemImage: "link")
            }
            if item.branchName != nil {
                Button {
                    model.copyBranchName(item)
                } label: {
                    Label(.copyBranchName, systemImage: "arrow.triangle.branch")
                }
            }
            ShareLink(item: url, subject: Text(item.title), message: Text("\(item.displayNumber) \(item.title)"), preview: SharePreview("\(item.displayNumber) \(item.title)")) {
                Label(.share, systemImage: "square.and.arrow.up")
            }
            Button {
                model.openOnGitHub(item)
            } label: {
                Label(.openOnGitHub, systemImage: "arrow.up.right.square")
            }
        }
        if item.kind == .issue || item.kind == .draft, !item.isDetached {
            Divider()
            Button(role: .destructive) {
                model.requestDelete(item)
            } label: {
                Label(item.kind == .draft ? .deleteDraft : .deleteIssue, systemImage: "trash")
            }
            .disabled(!model.canDelete(item))
        }
    }

    /// Picked sub-issues, as the Mac's menu on several: how many under a heading, what they can all get, and no
    /// opening, sharing or deleting.
    @ViewBuilder
    private func several(_ targets: [Item]) -> some View {
        Section {
            properties(targets)
        } header: {
            Text(.selectedIssueCount(count: targets.count))
        }
        if targets.allSatisfy(model.canRelate) {
            Section {
                RelationMenuItems(item: item)
            }
        }
        Section {
            if targets.contains(where: { $0.url != nil }) {
                Button {
                    model.copyLinks(targets)
                } label: {
                    Label(.copyLinks, systemImage: "link")
                }
            }
            Button {
                withAnimation(Theme.spring) { model.endPickingSubIssues() }
            } label: {
                Label(.clearSelection, systemImage: "xmark.circle")
            }
        }
    }

    /// Status, priority, assignee, labels, Assign to Me, due date and milestone. Checkmarks show what all of them share.
    @ViewBuilder
    private func properties(_ targets: [Item]) -> some View {
        StatusMenu(item: item)
        if model.project(of: item)?.priorityFieldId != nil {
            PriorityMenu(item: item)
        }
        if item.kind != .draft {
            AssigneeMenu(item: item)
            LabelsMenu(item: item)
            if let viewer = model.viewer {
                let mine = targets.allSatisfy { target in target.assignees.contains { $0.id == viewer.id } }
                Button {
                    model.toggleAssignMe(model.targets(for: model.item(id: item.id) ?? item))
                } label: {
                    Label(mine ? .unassignMe : .assignToMe, systemImage: mine ? "person.crop.circle.badge.minus" : "person.crop.circle.badge.plus")
                }
            }
        }
        if targets.contains(where: model.canHaveDueDate) {
            DueDateMenu(item: item)
        }
        if targets.contains(where: model.canHaveMilestone) {
            MilestoneMenu(item: item)
        }
    }
}

/// Parent, sub-issues and blockers, for the issue or the picked ones it is among. The pickers open as sheets over the
/// whole window, since a long press can come from any row or card.
struct RelationMenuItems: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation
    var item: Item

    var body: some View {
        let targets = model.targets(for: item)
        let single = targets.count == 1
        let hasParent = targets.contains { $0.parentId != nil }
        Button {
            navigation.sheet = .picker(itemId: item.id, kind: .parent)
        } label: {
            Label(hasParent ? LocalizedStringResource.changeParentIssueMenuItem : .setParentIssueMenuItem, systemImage: "arrow.turn.left.up")
        }
        if hasParent {
            let number = single ? item.parentNumber : nil
            Button {
                model.setParent(of: current, to: nil)
            } label: {
                Label(number.map { .removeFromNumber(number: "#\($0)") } ?? .removeFromParentMenuItem, systemImage: "arrow.uturn.left")
            }
        }
        if single {
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
                Label(.addSubIssue, systemImage: "arrow.turn.down.right")
            }
        }
        if !targets.contains(where: \.isEpic) {
            Button {
                navigation.sheet = .picker(itemId: item.id, kind: .epic)
            } label: {
                Label(.addToEpicCommand, systemImage: "square.stack.3d.up")
            }
        }
        if targets.allSatisfy(model.canMakeEpic) {
            let isEpic = targets.allSatisfy(\.isEpic)
            Button {
                model.setEpic(current, !isEpic)
            } label: {
                Label(isEpic ? .turnIntoIssueCommand : .makeEpicCommand, systemImage: isEpic ? "square.stack.3d.down.right" : "square.stack.3d.up.fill")
            }
        }
        Menu {
            Button {
                navigation.sheet = .picker(itemId: item.id, kind: .blockedBy)
            } label: {
                Label(.blockedByMenuItem, systemImage: "flag.fill")
            }
            Button {
                navigation.sheet = .picker(itemId: item.id, kind: .blocking)
            } label: {
                Label(.blockingMenuItem, systemImage: "flag")
            }
        } label: {
            Label(.markAsMenu, systemImage: "flag")
        }
    }

    /// The latest copies of what the menu acts on, when an entry is chosen.
    private var current: [Item] {
        model.targets(for: model.item(id: item.id) ?? item)
    }
}

/// The milestone as a submenu: none, the open ones with the current one checked, and a new one. With several picked
/// issues, the one they share is checked.
struct MilestoneMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation
    var item: Item

    var body: some View {
        let groups = model.milestoneGroups(for: item)
        let title = model.milestoneTitle(of: item)
        let titles = Set(model.targets(for: item).map { model.milestoneTitle(of: $0) })
        Menu {
            Picker(.milestone, selection: Binding(
                get: { titles.count == 1 ? title : String?.some(Self.mixed) },
                set: { new in
                    let current = model.item(id: item.id) ?? item
                    model.setMilestone(of: model.targets(for: current), to: new.flatMap { name in groups.first { $0.title == name } })
                }
            )) {
                Label(.noMilestone, systemImage: "diamond").tag(String?.none)
                ForEach(groups.filter { $0.isOpen || $0.title == title }) { group in
                    Label {
                        Text(group.title)
                        if let due = group.due { Text(due.mediumLabel()) }
                    } icon: {
                        Image(systemName: group.isOpen ? model.isCurrentMilestone(group, projectId: item.projectId) ? "diamond.inset.filled" : "diamond" : "diamond.fill")
                    }
                    .tag(Optional(group.title))
                }
            }
            .pickerStyle(.inline)
            if item.projectId != nil {
                Button {
                    navigation.sheet = .milestoneEditor(projectId: item.projectId, title: nil, assigning: model.targets(for: item).map(\.id))
                } label: {
                    Label(.newMilestoneEllipsis, systemImage: "plus")
                }
            }
        } label: {
            Label {
                Text(title.map { String(localized: .milestoneTooltip(milestone: $0)) } ?? String(localized: .milestone))
            } icon: {
                Image(systemName: "diamond")
            }
        }
    }

    /// A selection no row has, for picked issues in different milestones.
    static let mixed = "\u{1}"
}

/// Status as a submenu with the app's status circles, the current one checked: on several picked issues, the one they
/// share.
struct StatusMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    var item: Item

    var body: some View {
        if item.isOnBoard {
            statusMenu
        } else {
            // An issue on none of your boards goes onto one instead of getting a status.
            let boards = model.boards(toAdd: item)
            Menu {
                AddToProjectMenuItems(item: item)
            } label: {
                Label {
                    Text(boards.count == 1 ? .addToNamedProject(project: boards[0].title) : .addToProject)
                } icon: {
                    MenuImages.status(model.glyph(of: item), scheme)
                }
            }
            .disabled(boards.isEmpty)
        }
    }

    private var statusMenu: some View {
        let statuses = model.statusOptions(projectId: item.projectId)
        return Menu {
            Picker(.status, selection: selection) {
                ForEach(statuses) { option in
                    Label {
                        Text(option.name)
                    } icon: {
                        MenuImages.status(model.glyph(projectId: item.projectId, optionId: option.id), scheme)
                    }
                    .tag(Optional(option.id))
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label {
                Text(.status)
            } icon: {
                MenuImages.status(model.glyph(of: item), scheme)
            }
        }
        .disabled(statuses.isEmpty)
    }

    private var selection: Binding<String?> {
        let names = Set(model.targets(for: item).map { model.statusOption(of: $0)?.name })
        return Binding(
            get: { names.count == 1 ? item.statusId : nil },
            set: { id in
                guard let id else { return }
                model.pick(.status, id: id, for: item)
            }
        )
    }
}

/// For an issue on none of your boards: the columns of the boards it can go on. One tap puts it there.
struct AddToProjectMenuItems: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    var item: Item

    var body: some View {
        let boards = model.boards(toAdd: item)
        if boards.count == 1, let project = boards.first {
            Section(.addToNamedProject(project: project.title)) { columns(of: project) }
        } else {
            ForEach(boards) { project in
                Menu {
                    columns(of: project)
                } label: {
                    Text(project.title)
                }
            }
        }
    }

    @ViewBuilder
    private func columns(of project: Project) -> some View {
        let statuses = model.statusOptions(projectId: project.id)
        if statuses.isEmpty {
            Button(project.title) { add(to: project, "") }
        }
        ForEach(statuses) { option in
            Button {
                add(to: project, option.id)
            } label: {
                Label {
                    Text(option.name)
                } icon: {
                    MenuImages.status(model.glyph(projectId: project.id, optionId: option.id), scheme)
                }
            }
        }
    }

    private func add(to project: Project, _ optionId: String) {
        let current = model.item(id: item.id) ?? item
        model.pick(.status, id: "\(project.id)/\(optionId)", for: current)
    }
}

/// Priority as a submenu with the bars, from "No priority" to "Urgent". Several picked issues share the checkmark.
struct PriorityMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    var item: Item

    var body: some View {
        Menu {
            Picker(.priority, selection: selection) {
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
        } label: {
            Label {
                Text(.priority)
            } icon: {
                MenuImages.priority(model.priorityLevel(of: item), scheme)
            }
        }
    }

    private var selection: Binding<String> {
        let names = Set(model.targets(for: item).map { model.priorityOption(of: $0)?.name })
        return Binding(
            get: { names.count == 1 ? item.priorityId ?? "" : MilestoneMenu.mixed },
            set: { id in model.pick(.priority, id: id, for: item) }
        )
    }
}

/// People who can be assigned, each with a checkmark when assigned (to all picked issues, with several).
struct AssigneeMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    var item: Item

    var body: some View {
        let targets = model.targets(for: item)
        Menu {
            ForEach(model.people(for: item)) { person in
                Toggle(isOn: Binding(
                    get: { targets.allSatisfy { target in target.assignees.contains { $0.id == person.id } } },
                    set: { _ in model.pick(.assignees, id: person.id, for: item) }
                )) {
                    Label {
                        Text(person.login)
                    } icon: {
                        MenuImages.avatar(person, scheme)
                    }
                }
            }
        } label: {
            Label {
                Text(.assignee)
            } icon: {
                if let first = item.assignees.first {
                    MenuImages.avatar(first, scheme)
                } else {
                    Image(systemName: "person.crop.circle")
                }
            }
        }
        .onAppear { model.loadRepoMeta(for: item) }
    }
}

/// The repository's labels, each with a checkmark when set (on all picked issues, with several).
struct LabelsMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    var item: Item

    var body: some View {
        let labels = model.labels(for: item)
        let targets = model.targets(for: item)
        Menu {
            if labels.isEmpty {
                Text(.noLabelsInRepository)
            }
            ForEach(labels) { label in
                Toggle(isOn: Binding(
                    get: { targets.allSatisfy { target in target.labels.contains { $0.name == label.name } } },
                    set: { _ in model.pick(.labels, id: label.id, for: item) }
                )) {
                    Label {
                        Text(label.name)
                    } icon: {
                        MenuImages.label(label.color, scheme)
                    }
                }
            }
        } label: {
            Label(.labels, systemImage: "tag")
        }
    }
}

/// The lifted preview of a long-pressed issue: where it is, its title and its properties.
struct IssuePreview: View {
    @Environment(AppModel.self) private var model
    var item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                StatusIcon(glyph: model.glyph(of: item), size: 15)
                Text(item.displayNumber).monospacedDigit()
                if let project = model.project(of: item) {
                    ProjectIcon(projectId: project.id, size: 10)
                    Text(project.title).lineLimit(1)
                } else if let repo = item.repoShortName {
                    RepositoryIcon(size: 9)
                    Text(repo).lineLimit(1)
                }
            }
            .font(.footnote)
            .foregroundStyle(Theme.textTertiary)
            Text(item.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                if let status = model.statusOption(of: item) {
                    PropertyChip(text: status.name) { StatusIcon(glyph: model.glyph(of: item), size: 14) }
                }
                if let priority = model.priorityOption(of: item) {
                    PropertyChip(text: priority.name) { PriorityIcon(level: priority.priorityLevel) }
                }
                if let person = item.assignees.first {
                    PropertyChip(text: item.assignees.count == 1 ? person.login : String(localized: .peopleCount(count: item.assignees.count))) {
                        AvatarStack(people: item.assignees, size: 18)
                    }
                }
                if let due = model.dueBadge(for: item) {
                    PropertyChip(text: due.label, tint: due.tone == .overdue || due.tone == .today ? due.tone.color : nil) {
                        DueDateIcon(tone: due.tone, size: 12)
                    }
                }
            }
            if !item.body.isEmpty {
                Text(item.body)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textBody)
                    .lineLimit(4)
            }
        }
        .padding(18)
        .frame(width: 340, alignment: .leading)
        .background(Theme.panel)
    }
}
#endif
