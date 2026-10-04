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

/// A searchable list driven entirely from the keyboard: type to filter, arrows to move, Return to pick.
struct PickerList: View {
    var placeholder: String
    var items: [PickerItem]
    /// The key that opens this picker from the board, shown at the end of the search field.
    var hint: String? = nil
    /// Multi-select pickers stay open after a pick.
    var staysOpen = false
    var width: CGFloat = 260
    var maxRows = 9
    var fieldFont: Font = .ui
    var onPick: (String) -> Void
    var onClose: () -> Void

    @State private var query = ""
    @State private var index = 0
    @FocusState private var focused: Bool

    var body: some View {
        let visible = filtered
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField(placeholder, text: $query)
                    .textFieldStyle(.plain)
                    .font(fieldFont)
                    .focused($focused)
                    .focusOnAppear()
                if let hint { Keycap(hint) }
            }
                .padding(.horizontal, 12)
                .frame(height: 40)
                .onKeyPress(.downArrow) {
                    index = min(index + 1, max(visible.count - 1, 0))
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    index = max(index - 1, 0)
                    return .handled
                }
                .onKeyPress(.escape) {
                    onClose()
                    return .handled
                }
                .onKeyPress(phases: .down) { press in
                    // Number keys pick directly while nothing has been typed.
                    guard query.isEmpty, let item = items.first(where: { $0.shortcut == press.characters }) else { return .ignored }
                    pick(item)
                    return .handled
                }
                .onSubmit {
                    if visible.indices.contains(index) { pick(visible[index]) }
                }
            Rectangle().fill(Theme.popoverBorder).frame(height: 1)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(visible.enumerated()), id: \.element.id) { position, item in
                            PickerRow(item: item, active: position == index)
                                .id(item.id)
                                .onTapGesture { pick(item) }
                                .onHover { if $0 { index = position } }
                        }
                        if visible.isEmpty {
                            Text("No matches")
                                .foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.never)
                .frame(height: min(CGFloat(max(visible.count, 1)), CGFloat(maxRows)) * 32 + 8)
                .onChange(of: index) {
                    if visible.indices.contains(index) { proxy.scrollTo(visible[index].id) }
                }
            }
        }
        .frame(width: width)
        .font(.ui)
        .foregroundStyle(Theme.text)
        .onAppear {
            focused = true
            // Single-choice pickers start on the current value, so Return keeps it.
            if !staysOpen, let current = items.firstIndex(where: \.selected) { index = current }
        }
        .onChange(of: query) { index = 0 }
    }

    private var filtered: [PickerItem] {
        guard !query.isEmpty else { return items }
        return items
            .compactMap { item -> (PickerItem, Int)? in
                let score = max(fuzzyScore(query, item.title) ?? -1, item.subtitle.flatMap { fuzzyScore(query, $0) } ?? -1)
                return score >= 0 ? (item, score) : nil
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    private func pick(_ item: PickerItem) {
        onPick(item.id)
        if !staysOpen { onClose() }
    }
}

struct PickerRow: View {
    var item: PickerItem
    var active: Bool

    var body: some View {
        HStack(spacing: 10) {
            item.icon.frame(width: 18, height: 18)
            if let prefix = item.prefix {
                Text(prefix).font(.small).monospacedDigit().foregroundStyle(Theme.textTertiary).lineLimit(1)
            }
            Text(item.title).lineLimit(1).truncationMode(.tail)
            if let subtitle = item.subtitle {
                Text(subtitle).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let trailing = item.trailing { trailing }
            if item.selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textBody)
            }
            if let shortcut = item.shortcut {
                Text(shortcut)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(active ? Theme.textSecondary : Theme.textTertiary)
                    .frame(minWidth: 12, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(active ? Theme.popoverSelected : .clear))
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }
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

    var help: String {
        switch self {
        case .status: "Change status"
        case .priority: "Change priority"
        case .assignees: "Assign"
        case .labels: "Change labels"
        case .subIssues: "Sub-issues"
        }
    }

    var width: CGFloat { self == .subIssues ? 460 : 280 }
}

/// A picker for one property of one issue, as shown in dropdowns and the command palette.
struct ItemPicker: View {
    @Environment(AppModel.self) private var model
    var kind: PickerKind
    var itemId: String
    var width: CGFloat?
    var fieldFont: Font = .ui
    var close: () -> Void

    var body: some View {
        if let item = model.allItems.first(where: { $0.id == itemId }) {
            PickerList(
                placeholder: kind.placeholder,
                items: model.pickerItems(kind, for: item),
                hint: kind.hint,
                staysOpen: kind.staysOpen,
                width: width ?? kind.width,
                maxRows: 10,
                fieldFont: fieldFont,
                onPick: { model.pick(kind, id: $0, for: item) },
                onClose: close
            )
        }
    }
}

extension AppModel {
    func pickerItems(_ kind: PickerKind, for item: Item) -> [PickerItem] {
        // With several issues picked, a value is checked when all of them have it.
        let targets = targets(for: item)
        switch kind {
        case .status:
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
        case .subIssues:
            // Status, priority and assignee change in place, as in Linear; the rest of the row opens the issue.
            let showsPriority = project(of: item)?.priorityFieldId != nil
            let rows = subIssueItems(of: item).map { sub in
                PickerItem(
                    id: sub.id, title: sub.title,
                    icon: AnyView(PartButton(kind: .status, itemId: sub.id) { StatusIcon(glyph: glyph(of: sub)) }),
                    prefix: sub.displayNumber,
                    trailing: AnyView(HStack(spacing: 10) {
                        if showsPriority {
                            PartButton(kind: .priority, itemId: sub.id) { PriorityIcon(level: priorityLevel(of: sub)) }
                        }
                        PartButton(kind: .assignees, itemId: sub.id) {
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

    /// What a part of a card or list row shows on hover, as Linear names each value.
    func tooltip(_ kind: PickerKind, for item: Item) -> String {
        switch kind {
        case .status:
            return "Status: \(statusOption(of: item)?.name ?? "None")"
        case .priority:
            return "Priority: \(priorityOption(of: item)?.name ?? "None")"
        case .assignees:
            return item.assignees.isEmpty ? "Unassigned" : "Assigned to " + item.assignees.map(\.login).formatted(.list(type: .and))
        case .labels:
            return "Labels: " + item.labels.map(\.name).joined(separator: ", ")
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

/// A property value that opens its picker in a dropdown when clicked.
struct PropertyButton<Label: View>: View {
    var kind: PickerKind
    var item: Item
    @ViewBuilder var label: Label

    @State private var open = false

    var body: some View {
        Button {
            open = true
        } label: {
            label
                .padding(.horizontal, 8)
                .frame(minHeight: 28)
                .hoverFill(active: open)
        }
        .buttonStyle(PlainPressStyle())
        .dropdown(isPresented: $open) { close in
            ItemPicker(kind: kind, itemId: item.id, close: close)
        }
    }
}

/// A small part of a row, such as a status icon, that opens its picker for that issue in a dropdown.
/// Inside another dropdown it opens on top of it, so the list underneath stays open.
struct PartButton<Label: View>: View {
    var kind: PickerKind
    var itemId: String
    @ViewBuilder var label: Label

    @State private var open = false
    @State private var hovering = false

    var body: some View {
        // Avatars get a round halo, icons a small square, as on cards and list rows.
        let radius: CGFloat = kind == .assignees ? 12 : 5
        Button {
            open = true
        } label: {
            label
                .padding(3)
                .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(hovering || open ? Theme.partHover : .clear))
                .contentShape(Rectangle())
                .padding(-3)
        }
        .buttonStyle(PlainPressStyle())
        .onHover { hovering = $0 }
        .help(kind.help)
        .dropdown(isPresented: $open) { close in
            ItemPicker(kind: kind, itemId: itemId, close: close)
        }
    }
}
