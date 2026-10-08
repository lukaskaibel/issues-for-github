import SwiftUI

/// One row of a picker: a status, a priority, a person or a label.
struct PickerItem: Identifiable {
    var id: String
    var title: String
    var subtitle: String?
    var selected = false
    var icon: AnyView
    var shortcut: String?
    /// Shown before the title in a quieter colour, such as an issue number.
    var prefix: String? = nil
    /// Shown at the end of the row, such as priority and assignee.
    var trailing: AnyView? = nil
    /// Stays in the list whatever is typed, at its end, such as "New sub-issue…".
    var alwaysShown = false
}

/// Subsequence match: every character of the query appears in order. Higher is better; nil is no match.
func fuzzyScore(_ query: String, _ text: String) -> Int? {
    let q = Array(query.lowercased().filter { !$0.isWhitespace })
    guard !q.isEmpty else { return 0 }
    let t = Array(text.lowercased())
    var score = 0
    var qi = 0
    var streak = 0
    for (ti, character) in t.enumerated() where qi < q.count {
        if character == q[qi] {
            streak += 1
            score += 2 + streak * 2
            if ti == 0 || !t[ti - 1].isLetter && !t[ti - 1].isNumber { score += 6 }
            qi += 1
        } else {
            streak = 0
        }
    }
    guard qi == q.count else { return nil }
    return score - t.count / 8
}

/// The rows that match what was typed, best first: by title or subtitle, and issues by number too ("12" or "#12").
func matching(_ query: String, in items: [PickerItem]) -> [PickerItem] {
    guard !query.isEmpty else { return items }
    let digits = query.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
    let byNumber = !digits.isEmpty && digits.allSatisfy(\.isNumber)
    let matches = items
        .compactMap { item -> (PickerItem, Int)? in
            guard !item.alwaysShown else { return nil }
            var score = max(fuzzyScore(query, item.title) ?? -1, item.subtitle.flatMap { fuzzyScore(query, $0) } ?? -1)
            if byNumber, let prefix = item.prefix, prefix.hasPrefix("#"), prefix.dropFirst().hasPrefix(digits) {
                score = max(score, 1000 - prefix.count)
            }
            return score >= 0 ? (item, score) : nil
        }
        .sorted { $0.1 > $1.1 }
        .map(\.0)
    return matches + items.filter(\.alwaysShown)
}

// MARK: - Picker contents for an issue

enum PickerKind: Equatable {
    case status
    case priority
    case assignees
    case labels
    case dueDate
    case subIssues
    /// The issue to make this one a sub-issue of.
    case parent
    /// An issue to make a sub-issue of this one, or a new one.
    case addSubIssue
    case blockedBy
    case blocking

    var placeholder: String {
        switch self {
        case .status: String(localized: .changeStatusPlaceholder)
        case .priority: String(localized: .changePriorityPlaceholder)
        case .assignees: String(localized: .assignToPlaceholder)
        case .labels: String(localized: .addLabelsPlaceholder)
        case .dueDate: String(localized: .dueDatePlaceholder)
        case .subIssues: String(localized: .openSubIssuePlaceholder)
        case .parent: String(localized: .setParentIssuePlaceholder)
        case .addSubIssue: String(localized: .addSubIssuePlaceholder)
        case .blockedBy: String(localized: .markAsBlockedByPlaceholder)
        case .blocking: String(localized: .markAsBlockingPlaceholder)
        }
    }

    /// The key that opens the same picker from the board.
    var hint: String? {
        switch self {
        case .status: "S"
        case .priority: "P"
        case .assignees: "A"
        case .labels: "L"
        case .dueDate: "D"
        case .subIssues, .parent, .addSubIssue, .blockedBy, .blocking: nil
        }
    }

    /// People and labels take several values; the rest one.
    var multiple: Bool { self == .assignees || self == .labels }

    var help: String {
        switch self {
        case .status: String(localized: .changeStatus)
        case .priority: String(localized: .changePriority)
        case .assignees: String(localized: .assign)
        case .labels: String(localized: .changeLabels)
        case .dueDate: String(localized: .changeDueDate)
        case .subIssues: String(localized: .subIssues)
        case .parent: String(localized: .setParentIssueHelp)
        case .addSubIssue: String(localized: .addSubIssueButton)
        case .blockedBy: String(localized: .blockedByHelp)
        case .blocking: String(localized: .blockingHelp)
        }
    }

    /// Pickers that list issues to choose from, which can be many.
    var picksIssues: Bool {
        switch self {
        case .parent, .addSubIssue, .blockedBy, .blocking: true
        default: false
        }
    }

    /// Single-choice pickers open on the current value, so Return keeps it. Where several are checked and a pick
    /// takes one away, they open on the first that isn't.
    var opensOnSelection: Bool { self != .blockedBy && self != .blocking }

    var width: CGFloat { self == .subIssues || picksIssues ? 460 : 280 }
}

extension AppModel {
    func pickerItems(_ kind: PickerKind, for item: Item) -> [PickerItem] {
        // With several issues picked, a value is checked when all of them have it.
        let targets = targets(for: item)
        switch kind {
        case .status:
            guard item.isOnBoard else { return addToProjectItems(for: item) }
            return statusOptions(projectId: item.projectId).enumerated().map { index, option in
                PickerItem(
                    id: option.id, title: option.name,
                    selected: targets.allSatisfy { target in statusOption(of: target)?.name == option.name },
                    icon: AnyView(StatusIcon(glyph: glyph(projectId: item.projectId, optionId: option.id))),
                    shortcut: index < 9 ? "\(index + 1)" : nil
                )
            }
        case .priority:
            let none = PickerItem(
                id: "", title: String(localized: .noPriority), selected: targets.allSatisfy { $0.priorityId == nil },
                icon: AnyView(PriorityIcon(level: .none)), shortcut: "0"
            )
            return [none] + priorityOptions(projectId: item.projectId).enumerated().map { index, option in
                PickerItem(
                    id: option.id, title: option.name,
                    selected: targets.allSatisfy { target in priorityOption(of: target)?.name == option.name },
                    icon: AnyView(PriorityIcon(level: option.priorityLevel)),
                    shortcut: index < 9 ? "\(index + 1)" : nil
                )
            }
        case .assignees:
            return people(for: item).map { person in
                PickerItem(
                    id: person.id, title: person.login, subtitle: person.name,
                    selected: targets.allSatisfy { target in target.assignees.contains { $0.id == person.id } },
                    icon: AnyView(Avatar(login: person.login, url: person.avatarUrl, size: 18))
                )
            }
        case .labels:
            return labels(for: item).map { label in
                PickerItem(
                    id: label.id, title: label.name,
                    selected: targets.allSatisfy { target in target.labels.contains { $0.name == label.name } },
                    icon: AnyView(Circle().fill(Theme.labelColor(label.color)).frame(width: 9, height: 9))
                )
            }
        case .dueDate:
            return dueDateItems(for: item)
        case .subIssues:
            // Status, priority and assignee change in place, as in Linear; the rest of the row opens the issue.
            let showsPriority = project(of: item)?.priorityFieldId != nil
            let rows = subIssueItems(of: item).map { sub in
                PickerItem(
                    id: sub.id, title: sub.title,
                    icon: AnyView(rowPart(.status, sub.id) { StatusIcon(glyph: glyph(of: sub)) }),
                    prefix: sub.displayNumber,
                    trailing: AnyView(HStack(spacing: 10) {
                        if showsPriority {
                            rowPart(.priority, sub.id) { PriorityIcon(level: priorityLevel(of: sub)) }
                        }
                        rowPart(.assignees, sub.id) {
                            Group {
                                if sub.assignees.isEmpty {
                                    Image(systemName: "person.crop.circle.dashed")
                                        .font(.system(size: 14))
                                        .foregroundStyle(Theme.textTertiary)
                                } else {
                                    AvatarStack(people: sub.assignees)
                                }
                            }
                            .frame(minWidth: 18, minHeight: 18, alignment: .trailing)
                        }
                    })
                )
            }
            guard item.kind == .issue else { return rows }
            let add = PickerItem(
                id: Self.newSubIssueId, title: String(localized: .newSubIssueChoice),
                icon: AnyView(Image(systemName: "plus").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textSecondary))
            )
            guard canRelate(item) else { return rows + [add] }
            let existing = PickerItem(
                id: Self.existingSubIssueId, title: String(localized: .addExistingIssueChoice),
                icon: AnyView(SubIssueGlyph().frame(width: 12, height: 12).foregroundStyle(Theme.textSecondary))
            )
            return rows + [add, existing]
        case .parent:
            // Not under itself, nor under one of its own sub-issues.
            let below = descendants(of: Set(targets.compactMap(\.contentId)))
            let candidates = relatableIssues(near: item).filter { !below.contains($0.contentId ?? "") }
            let isParent = { (candidate: Item) in targets.allSatisfy { $0.parentId == candidate.contentId } }
            var rows: [PickerItem] = []
            if targets.contains(where: { $0.parentId != nil }) {
                let number = targets.count == 1 ? item.parentNumber : nil
                let title = number.map { String(localized: .removeFromNumber(number: "#\($0)")) } ?? String(localized: .removeFromParentCommand)
                rows.append(PickerItem(
                    id: Self.removeParentId, title: title,
                    icon: AnyView(Image(systemName: "xmark").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textSecondary))
                ))
            }
            rows += (candidates.filter(isParent) + candidates.filter { !isParent($0) }).map { candidate in
                issueRow(candidate, near: item, selected: isParent(candidate))
            }
            return rows
        case .addSubIssue:
            let excluded = ancestors(of: item).union(subIssueIds(of: item))
            let rows = relatableIssues(near: item)
                .filter { !excluded.contains($0.contentId ?? "") }
                .map { issueRow($0, near: item) }
            #if os(macOS)
            // Typing a title and picking this carries the title into the new issue.
            let new = PickerItem(
                id: Self.newSubIssueId, title: String(localized: .newSubIssueChoice),
                icon: AnyView(Image(systemName: "plus").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textSecondary)),
                alwaysShown: true
            )
            return [new] + rows
            #else
            return rows
            #endif
        case .blockedBy, .blocking:
            let ids = Set(targets.compactMap(\.contentId))
            let linked = { (candidate: Item) -> Bool in
                guard let other = candidate.contentId else { return false }
                return targets.allSatisfy { target in
                    guard let id = target.contentId else { return false }
                    return kind == .blockedBy ? self.isBlocked(id, by: other) : self.isBlocked(other, by: id)
                }
            }
            let candidates = relatableIssues(near: item).filter { !ids.contains($0.contentId ?? "") }
            return (candidates.filter(linked) + candidates.filter { !linked($0) }).map { candidate in
                issueRow(candidate, near: item, selected: linked(candidate))
            }
        }
    }

    static let newSubIssueId = "new-sub-issue"
    static let existingSubIssueId = "existing-sub-issue"
    static let removeParentId = "remove-parent"

    /// An issue in a picker that picks issues: status, number and title, and its repository when it is another.
    private func issueRow(_ candidate: Item, near item: Item, selected: Bool = false) -> PickerItem {
        let repo = candidate.repoId != item.repoId ? candidate.repoShortName : nil
        return PickerItem(
            id: candidate.contentId ?? candidate.id, title: candidate.title, selected: selected,
            icon: AnyView(StatusIcon(glyph: glyph(of: candidate))),
            prefix: candidate.displayNumber,
            trailing: repo.map { AnyView(Text($0).font(.small).foregroundStyle(Theme.textTertiary).lineLimit(1)) }
        )
    }

    /// For an issue on none of your boards, the status picker puts it on one: the columns of each board it can
    /// go on, named after the board when there are several. One pick adds it and sets the column.
    private func addToProjectItems(for item: Item) -> [PickerItem] {
        let boards = boards(toAdd: item)
        let several = boards.count > 1
        var index = 0
        return boards.flatMap { project -> [PickerItem] in
            let statuses = statusOptions(projectId: project.id)
            guard !statuses.isEmpty else {
                return [PickerItem(
                    id: "\(project.id)/", title: project.title,
                    icon: AnyView(ProjectSwatch(title: project.title, size: 12))
                )]
            }
            return statuses.map { option in
                index += 1
                return PickerItem(
                    id: "\(project.id)/\(option.id)", title: option.name,
                    icon: AnyView(StatusIcon(glyph: glyph(projectId: project.id, optionId: option.id))),
                    shortcut: !several && index <= 9 ? "\(index)" : nil,
                    prefix: several ? project.title : nil
                )
            }
        }
    }

    /// The status as a chip or property shows it. An issue on none of your boards has none, only open or closed.
    func statusText(of item: Item) -> String {
        guard item.isOnBoard else {
            if item.state == "MERGED" { return String(localized: .stateMerged) }
            return item.isClosed ? String(localized: .stateClosed) : String(localized: .noProject)
        }
        return statusOption(of: item)?.name ?? String(localized: .noStatus)
    }

    func statusIsPlaceholder(_ item: Item) -> Bool {
        item.isOnBoard ? item.statusId == nil : !item.isClosed
    }

    /// What a picker's field says. An issue on no board is put on one rather than given a status.
    func pickerPlaceholder(_ kind: PickerKind, for item: Item) -> String {
        guard kind == .status, !item.isOnBoard else { return kind.placeholder }
        let boards = boards(toAdd: item)
        return boards.count == 1
            ? String(localized: .addToNamedProjectPlaceholder(project: boards[0].title))
            : String(localized: .addToProjectPickerPlaceholder)
    }

    /// A part of a sub-issue row: on the Mac it opens its own picker, as in Linear; elsewhere it is only shown.
    @ViewBuilder
    private func rowPart<Content: View>(_ kind: PickerKind, _ itemId: String, @ViewBuilder _ content: () -> Content) -> some View {
        #if os(macOS)
        PartButton(kind: kind, itemId: itemId, label: content)
        #else
        content()
        #endif
    }

    /// What a part of a card or list row shows on hover, as Linear names each value.
    func tooltip(_ kind: PickerKind, for item: Item) -> String {
        let text: LocalizedStringResource
        switch kind {
        case .status:
            if !item.isOnBoard {
                text = item.isClosed ? .closedOnNoBoard : .addToProjectTooltip
            } else if let name = statusOption(of: item)?.name {
                text = .statusTooltip(name: name)
            } else {
                text = .statusNoneTooltip
            }
        case .priority:
            text = priorityOption(of: item).map { .priorityTooltip(name: $0.name) } ?? .priorityNoneTooltip
        case .assignees:
            text = item.assignees.isEmpty ? .unassigned : .assignedTo(names: item.assignees.map(\.login).formatted(.list(type: .and)))
        case .labels:
            // Narrow: "bug, design" in English, without "and", as the chips read.
            text = .labelsAre(names: item.labels.map(\.name).formatted(.list(type: .and, width: .narrow)))
        case .dueDate:
            guard let badge = dueBadge(for: item) else { return String(localized: .noDueDate) }
            return badge.tooltip
        case .subIssues:
            text = .subIssuesDone(done: item.subCompleted.formatted(), total: item.subTotal)
        case .parent:
            text = item.parentNumber.map { .subIssueOf(number: "#\($0)") } ?? .noParentIssue
        case .addSubIssue:
            text = .addSubIssueButton
        case .blockedBy, .blocking:
            let relation: LinkedIssue.Relation = kind == .blockedBy ? .blockedBy : .blocking
            let open = links(of: item, relation).filter { !$0.isClosed }
            let count = kind == .blockedBy ? item.blockedByCount : item.blockingCount
            if !open.isEmpty, open.count == count {
                let numbers = open.map(\.displayNumber).formatted(.list(type: .and))
                text = kind == .blockedBy ? .blockedByNumbers(numbers: numbers) : .blockingNumbers(numbers: numbers)
            } else {
                text = kind == .blockedBy ? .blockedByCount(count: count) : .blockingCount(count: count)
            }
        }
        return String(localized: text)
    }

    /// Sub-issues of an issue that are on the same board, in board order.
    func subIssueItems(of item: Item) -> [Item] {
        guard let contentId = item.contentId else { return [] }
        return allItems.filter { $0.projectId == item.projectId && $0.parentId == contentId }
    }

    func pick(_ kind: PickerKind, id: String, for item: Item) {
        // Work with the latest copies: multi-select pickers stay open across several picks. With several issues
        // picked, the change goes to all of them.
        let current = allItems.first { $0.id == item.id } ?? item
        let targets = targets(for: current).map { target in allItems.first { $0.id == target.id } ?? target }
        switch kind {
        case .status:
            guard current.isOnBoard else {
                let parts = id.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
                guard let project = projects.first(where: { $0.id == parts.first }) else { return }
                let option = statusOptions(projectId: project.id).first { $0.id == parts.last }
                addToProject(targets, project: project, status: option)
                return
            }
            if let option = statusOptions(projectId: current.projectId).first(where: { $0.id == id }) {
                setStatus(of: targets, toOptionNamed: option.name, id: option.id)
            }
        case .priority:
            let option = priorityOptions(projectId: current.projectId).first { $0.id == id }
            setPriority(of: targets, toOptionNamed: option?.name, id: option?.id)
        case .assignees:
            if let person = people(for: current).first(where: { $0.id == id }) { toggleAssignee(targets, person) }
        case .labels:
            if let label = labels(for: current).first(where: { $0.id == id }) { toggleLabel(targets, named: label.name) }
        case .dueDate:
            setDueDate(of: targets, to: CalendarDay(id))
        case .subIssues:
            if id == Self.newSubIssueId {
                overlay = .newIssue(statusId: nil, parentItemId: current.id)
            } else if id == Self.existingSubIssueId {
                overlay = .palette(.addSubIssue(itemId: current.id))
            } else if let sub = allItems.first(where: { $0.id == id }) {
                open(sub)
            }
        case .parent:
            if id == Self.removeParentId {
                setParent(of: targets, to: nil)
            } else if let parent = self.item(contentId: id) {
                setParent(of: targets, to: parent)
            }
        case .addSubIssue:
            if id == Self.newSubIssueId {
                overlay = .newIssue(statusId: nil, parentItemId: current.id)
            } else if let child = self.item(contentId: id) {
                setParent(of: [child], to: current)
            }
        case .blockedBy:
            if let blocker = self.item(contentId: id) { toggleBlocked(targets, by: blocker) }
        case .blocking:
            if let blocked = self.item(contentId: id) { toggleBlocking(targets, blocks: blocked) }
        }
    }

    /// People who can be assigned: the repository's assignable users, or everyone seen on the board until those load.
    func people(for item: Item) -> [Person] {
        people(projectId: item.projectId, repoId: item.repoId)
    }

    /// A repository's labels and people are the same whichever board it is on; any board's copy will do.
    private func repoMeta(projectId: String?, repoId: String?) -> RepoRef? {
        let matching = repos.filter { $0.id == repoId }
        return matching.first { $0.projectId == projectId && $0.metaLoadedAt != nil }
            ?? matching.first { $0.metaLoadedAt != nil }
            ?? matching.first { $0.projectId == projectId }
    }

    func people(projectId: String?, repoId: String?) -> [Person] {
        var result = repoMeta(projectId: projectId, repoId: repoId)?.assignableUsers ?? []
        // A repository none of your boards use.
        if result.isEmpty, let repoId, let meta = otherRepoMeta[repoId] { result = meta.people }
        if result.isEmpty {
            var seen = Set<String>()
            let nearby = allItems.filter { projectId == nil ? $0.repoId == repoId : $0.projectId == projectId }
            result = nearby.flatMap(\.assignees).filter { seen.insert($0.id).inserted }
            if let viewer, seen.insert(viewer.id).inserted { result.append(viewer.person) }
        }
        let me = viewer?.id
        return result.sorted { a, b in
            if (a.id == me) != (b.id == me) { return a.id == me }
            return a.login.localizedCaseInsensitiveCompare(b.login) == .orderedAscending
        }
    }

    func labels(for item: Item) -> [LabelRef] {
        labels(projectId: item.projectId, repoId: item.repoId)
    }

    func labels(projectId: String?, repoId: String?) -> [LabelRef] {
        var result = repoMeta(projectId: projectId, repoId: repoId)?.labels ?? []
        if result.isEmpty, let repoId, let meta = otherRepoMeta[repoId] { result = meta.labels }
        if !result.isEmpty { return result }
        var seen = Set<String>()
        return allItems
            .filter { $0.repoId == repoId }
            .flatMap(\.labels)
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
