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
    case subIssues

    var placeholder: String {
        switch self {
        case .status: "Change status…"
        case .priority: "Change priority to…"
        case .assignees: "Assign to…"
        case .labels: "Add labels…"
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
        case .subIssues: nil
        }
    }

    var staysOpen: Bool { self == .assignees || self == .labels }

    var width: CGFloat { self == .subIssues ? 460 : 280 }
}

extension AppModel {
    func pickerItems(_ kind: PickerKind, for item: Item) -> [PickerItem] {
        switch kind {
        case .status:
            return statusOptions(projectId: item.projectId).enumerated().map { index, option in
                PickerItem(
                    id: option.id, title: option.name, selected: item.statusId == option.id,
                    icon: AnyView(StatusIcon(glyph: glyph(projectId: item.projectId, optionId: option.id))),
                    shortcut: index < 9 ? "\(index + 1)" : nil
                )
            }
        case .priority:
            let none = PickerItem(
                id: "", title: "No priority", selected: item.priorityId == nil,
                icon: AnyView(PriorityIcon(level: .none)), shortcut: "0"
            )
            return [none] + priorityOptions(projectId: item.projectId).enumerated().map { index, option in
                PickerItem(
                    id: option.id, title: option.name, selected: item.priorityId == option.id,
                    icon: AnyView(PriorityIcon(level: option.priorityLevel)),
                    shortcut: index < 9 ? "\(index + 1)" : nil
                )
            }
        case .assignees:
            return people(for: item).map { person in
                PickerItem(
                    id: person.id, title: person.login, subtitle: person.name,
                    selected: item.assignees.contains { $0.id == person.id },
                    icon: AnyView(Avatar(login: person.login, url: person.avatarUrl, size: 18))
                )
            }
        case .labels:
            return labels(for: item).map { label in
                PickerItem(
                    id: label.id, title: label.name,
                    selected: item.labels.contains { $0.id == label.id },
                    icon: AnyView(Circle().fill(Theme.labelColor(label.color)).frame(width: 9, height: 9))
                )
            }
        case .subIssues:
            return subIssueItems(of: item).map { sub in
                PickerItem(
                    id: sub.id, title: sub.title,
                    icon: AnyView(StatusIcon(glyph: glyph(of: sub))),
                    prefix: sub.displayNumber,
                    trailing: AnyView(HStack(spacing: 10) {
                        PriorityIcon(level: priorityLevel(of: sub))
                        Group {
                            if sub.assignees.isEmpty { Color.clear } else { AvatarStack(people: sub.assignees) }
                        }
                        .frame(width: 30, height: 18, alignment: .trailing)
                    })
                )
            }
        }
    }

    /// Sub-issues of an issue that are on the same board, in board order.
    func subIssueItems(of item: Item) -> [Item] {
        guard let contentId = item.contentId else { return [] }
        return allItems.filter { $0.projectId == item.projectId && $0.parentId == contentId }
    }

    func pick(_ kind: PickerKind, id: String, for item: Item) {
        // Work with the latest copy: multi-select pickers stay open across several picks.
        let current = allItems.first { $0.id == item.id } ?? item
        switch kind {
        case .status:
            if let option = statusOptions(projectId: current.projectId).first(where: { $0.id == id }) {
                withAnimation(Theme.spring) { setStatus(current, to: option) }
            }
        case .priority:
            setPriority(current, to: priorityOptions(projectId: current.projectId).first { $0.id == id })
        case .assignees:
            if let person = people(for: current).first(where: { $0.id == id }) { toggleAssignee(current, person) }
        case .labels:
            if let label = labels(for: current).first(where: { $0.id == id }) { toggleLabel(current, label) }
        case .subIssues:
            if let sub = allItems.first(where: { $0.id == id }) { open(sub) }
        }
    }

    /// People who can be assigned: the repository's assignable users, or everyone seen on the board until those load.
    func people(for item: Item) -> [Person] {
        people(projectId: item.projectId, repoId: item.repoId)
    }

    func people(projectId: String, repoId: String?) -> [Person] {
        var result = repos.first { $0.projectId == projectId && $0.id == repoId }?.assignableUsers ?? []
        if result.isEmpty {
            var seen = Set<String>()
            result = allItems.filter { $0.projectId == projectId }.flatMap(\.assignees).filter { seen.insert($0.id).inserted }
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

    func labels(projectId: String, repoId: String?) -> [LabelRef] {
        let result = repos.first { $0.projectId == projectId && $0.id == repoId }?.labels ?? []
        if !result.isEmpty { return result }
        var seen = Set<String>()
        return allItems
            .filter { $0.projectId == projectId && $0.repoId == repoId }
            .flatMap(\.labels)
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
