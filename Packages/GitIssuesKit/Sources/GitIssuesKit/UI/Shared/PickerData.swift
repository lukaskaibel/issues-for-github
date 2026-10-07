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

// MARK: - Picker contents for an issue

enum PickerKind: Equatable {
    case status
    case priority
    case assignees
    case labels
    case dueDate
    case subIssues

    var placeholder: String {
        switch self {
        case .status: "Change status…"
        case .priority: "Change priority to…"
        case .assignees: "Assign to…"
        case .labels: "Add labels…"
        case .dueDate: "Due date… try “fri” or “12.10.”"
        case .subIssues: "Open sub-issue…"
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
        case .subIssues: nil
        }
    }

    /// People and labels take several values; the rest one.
    var multiple: Bool { self == .assignees || self == .labels }

    var help: String {
        switch self {
        case .status: "Change status"
        case .priority: "Change priority"
        case .assignees: "Assign"
        case .labels: "Change labels"
        case .dueDate: "Change due date"
        case .subIssues: "Sub-issues"
        }
    }

    var width: CGFloat { self == .subIssues ? 460 : 280 }
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
                id: "", title: "No priority", selected: targets.allSatisfy { $0.priorityId == nil },
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
                id: Self.newSubIssueId, title: "New sub-issue…",
                icon: AnyView(Image(systemName: "plus").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textSecondary))
            )
            return rows + [add]
        }
    }

    static let newSubIssueId = "new-sub-issue"

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
            if item.state == "MERGED" { return "Merged" }
            return item.isClosed ? "Closed" : "No project"
        }
        return statusOption(of: item)?.name ?? "No status"
    }

    func statusIsPlaceholder(_ item: Item) -> Bool {
        item.isOnBoard ? item.statusId == nil : !item.isClosed
    }

    /// What a picker's field says. An issue on no board is put on one rather than given a status.
    func pickerPlaceholder(_ kind: PickerKind, for item: Item) -> String {
        guard kind == .status, !item.isOnBoard else { return kind.placeholder }
        let boards = boards(toAdd: item)
        return boards.count == 1 ? "Add to \(boards[0].title)…" : "Add to project…"
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
        switch kind {
        case .status:
            guard item.isOnBoard else { return item.isClosed ? "Closed, on no board" : "Add to project" }
            return "Status: \(statusOption(of: item)?.name ?? "None")"
        case .priority:
            return "Priority: \(priorityOption(of: item)?.name ?? "None")"
        case .assignees:
            return item.assignees.isEmpty ? "Unassigned" : "Assigned to " + item.assignees.map(\.login).formatted(.list(type: .and))
        case .labels:
            return "Labels: " + item.labels.map(\.name).joined(separator: ", ")
        case .dueDate:
            return dueBadge(for: item)?.tooltip ?? "No due date"
        case .subIssues:
            return "\(item.subCompleted) of \(item.subTotal) sub-issues done"
        }
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
            } else if let sub = allItems.first(where: { $0.id == id }) {
                open(sub)
            }
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
