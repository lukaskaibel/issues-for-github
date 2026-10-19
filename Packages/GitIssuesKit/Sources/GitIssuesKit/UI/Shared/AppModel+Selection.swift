import SwiftUI

/// Picking several issues to change at once, as in Linear: X, ⌘-click and Shift-click pick issues, and
/// shortcuts, dropdowns and the right-click menu then act on all of them. Space peeks at an issue
/// without leaving the board or list.
extension AppModel {
    /// The picked issues, in the order they read on screen.
    var selectedItems: [Item] {
        guard !selectedIds.isEmpty else { return [] }
        return scopedItems.filter { selectedIds.contains($0.id) }.sorted { a, b in
            let order = orderIndex
            return (order[a.id] ?? .max) < (order[b.id] ?? .max)
        }
    }

    private var orderIndex: [String: Int] {
        Dictionary(uniqueKeysWithValues: orderedItems.enumerated().map { ($1.id, $0) })
    }

    /// What shortcuts, the palette and the Issue menu act on: the picked issues (through `targets(for:)`), on an
    /// issue's page the sub-issues picked on it, else the open issue or the issue under the pointer or keyboard focus.
    var actionItem: Item? {
        if openItem == nil, let first = selectedItems.first { return first }
        if openItem != nil, let first = pickedSubIssues.first { return first }
        return targetItem
    }

    /// The issues an action on `item` applies to: the whole selection when the item is part of it.
    func targets(for item: Item) -> [Item] {
        if let openItemId, item.id != openItemId {
            // On an issue's page, its picked sub-issues; the board's picks behind the page don't count there.
            guard pickedSubIssueIds.contains(item.id) else { return [item] }
            let picked = pickedSubIssues
            return picked.count > 1 ? picked : [item]
        }
        guard selectedIds.count > 1, selectedIds.contains(item.id) else { return [item] }
        let items = selectedItems
        return items.isEmpty ? [item] : items
    }

    func isSelected(_ id: String) -> Bool {
        selectedIds.contains(id)
    }

    /// X and ⌘-click: adds the issue to the selection or takes it out.
    func toggleSelection(_ item: Item) {
        if selectedIds.contains(item.id) { selectedIds.remove(item.id) } else { selectedIds.insert(item.id) }
        selectionAnchorId = item.id
        selectionRange = []
    }

    /// Shift-click and Shift-arrows: everything from the anchor to `item`, on top of what was picked before.
    func extendSelection(to item: Item) {
        let order = orderedItems.map(\.id)
        let anchor = selectionAnchorId.flatMap { order.contains($0) ? $0 : nil } ?? cursorId ?? item.id
        guard let from = order.firstIndex(of: anchor), let to = order.firstIndex(of: item.id) else { return }
        let range = Set(order[min(from, to)...max(from, to)])
        selectedIds = selectedIds.subtracting(selectionRange).union(range)
        selectionRange = range
        selectionAnchorId = anchor
    }

    func selectAll() {
        selectedIds = Set(orderedItems.map(\.id))
        selectionAnchorId = orderedItems.first?.id
        selectionRange = []
    }

    func clearSelection() {
        // On an issue's page only its picked sub-issues show; the board's picks wait behind it.
        if openItemId != nil, !pickedSubIssueIds.isEmpty {
            pickedSubIssueIds = []
            subIssuePickAnchor = nil
            return
        }
        guard !selectedIds.isEmpty || selectionAnchorId != nil else { return }
        selectedIds = []
        selectionAnchorId = nil
        selectionRange = []
    }

    // MARK: Sub-issues on an issue's page

    /// The open issue's sub-issues that are picked and still under it.
    var pickedSubIssues: [Item] {
        guard !pickedSubIssueIds.isEmpty, let parentId = openItem?.contentId else { return [] }
        return allItems.filter { pickedSubIssueIds.contains($0.id) && $0.parentId == parentId }
    }

    /// ⌘-click on a sub-issue: picks it or puts it back.
    func toggleSubIssuePick(_ item: Item) {
        if pickedSubIssueIds.contains(item.id) { pickedSubIssueIds.remove(item.id) } else { pickedSubIssueIds.insert(item.id) }
        subIssuePickAnchor = item.id
    }

    /// Shift-click on a sub-issue: everything from the last click to this one, in `order` as they are listed.
    func extendSubIssuePick(to item: Item, in order: [String]) {
        let anchor = subIssuePickAnchor.flatMap { order.contains($0) ? $0 : nil } ?? item.id
        guard let from = order.firstIndex(of: anchor), let to = order.firstIndex(of: item.id) else { return }
        pickedSubIssueIds = Set(order[min(from, to)...max(from, to)])
        subIssuePickAnchor = anchor
    }

    // MARK: Acting on several issues

    func setStatus(of items: [Item], toOptionNamed name: String, id: String) {
        withAnimation(Theme.spring) {
            for item in items {
                // In My Issues the picked issues can come from different projects; match the option by name there.
                let options = statusOptions(projectId: item.projectId)
                if let option = options.first(where: { $0.id == id }) ?? options.first(where: { $0.name == name }) {
                    setStatus(item, to: option)
                }
            }
        }
    }

    func setPriority(of items: [Item], toOptionNamed name: String?, id: String?) {
        for item in items {
            guard let id, let name else {
                setPriority(item, to: nil)
                continue
            }
            let options = priorityOptions(projectId: item.projectId)
            if let option = options.first(where: { $0.id == id }) ?? options.first(where: { $0.name == name }) {
                setPriority(item, to: option)
            }
        }
    }

    /// Assigns the person to all of them, or, when every one already has them, unassigns them from all.
    func toggleAssignee(_ items: [Item], _ person: Person) {
        let editable = items.filter { $0.kind != .draft }
        let all = editable.allSatisfy { item in item.assignees.contains { $0.id == person.id } }
        for item in editable where item.assignees.contains(where: { $0.id == person.id }) == all {
            toggleAssignee(item, person)
        }
    }

    /// Adds the label to all of them, or takes it off when every one has it. Labels belong to a repository,
    /// so each issue gets its own repository's label of that name.
    func toggleLabel(_ items: [Item], named name: String) {
        let editable = items.filter { $0.kind != .draft }
        let all = editable.allSatisfy { item in item.labels.contains { $0.name == name } }
        for item in editable where item.labels.contains(where: { $0.name == name }) == all {
            if let label = item.labels.first(where: { $0.name == name }) ?? labels(for: item).first(where: { $0.name == name }) {
                toggleLabel(item, label)
            }
        }
    }

    /// Adds a label typed into the picker to all of them, made first in each of their repositories that has none.
    func addNewLabel(named name: String, to items: [Item]) {
        var mutations: [Mutation] = []
        var labels: [String: LabelRef] = [:]
        for item in items where item.kind != .draft {
            guard let contentId = item.contentId, let repoId = item.repoId,
                  let label = labels[repoId]
                    ?? newLabel(named: name, projectId: item.projectId, repoId: repoId, repo: item.repo, making: &mutations)
            else { continue }
            labels[repoId] = label
            noteRecent(.label, label.name)
            if !item.labels.contains(where: { $0.name.caseInsensitiveCompare(label.name) == .orderedSame }) {
                mutations.append(.editLabels(.init(contentId: contentId, add: [label], remove: [])))
            }
        }
        perform(mutations)
    }

    /// A label typed into a new issue's picker: the repository's own of that name, else one made there now.
    func labelForNewIssue(named name: String, projectId: String?, repoId: String?) -> LabelRef? {
        guard let repoId else { return nil }
        var mutations: [Mutation] = []
        let label = newLabel(named: name, projectId: projectId, repoId: repoId, repo: nil, making: &mutations)
        perform(mutations)
        noteRecent(.label, label?.name)
        return label
    }

    /// The repository's label of that name, or one to make, with the change that makes it. `repo` names a repository
    /// known only from an issue in the Inbox.
    private func newLabel(
        named name: String, projectId: String?, repoId: String, repo: String?, making mutations: inout [Mutation]
    ) -> LabelRef? {
        if let known = existingLabel(named: name, projectId: projectId, repoId: repoId) { return known }
        guard let repo = anyRepository(id: repoId)?.nameWithOwner ?? repo else { return nil }
        let made = Mutation.CreateLabel(
            labelId: LabelRef.makeLocalId(), repoId: repoId, repo: repo, name: name, color: LabelRef.newColor(for: name)
        )
        mutations.append(.createLabel(made))
        // A repository none of your boards use keeps its labels here, not in the database.
        otherRepoMeta[repoId]?.labels.append(made.label)
        return made.label
    }

    func toggleAssignMe(_ items: [Item]) {
        guard let viewer else { return }
        toggleAssignee(items, viewer.person)
    }

    func copyLinks(_ items: [Item]) {
        let links = items.compactMap(\.url)
        guard !links.isEmpty else { return }
        Platform.copy(links.joined(separator: "\n"))
        let title = links.count == 1 ? String(localized: .linkCopied) : String(localized: .linksCopied(count: links.count))
        status.post(Notice(title: title, message: ""))
    }

    // MARK: Peek

    var peekItem: Item? {
        peekItemId.flatMap { id in scopedItems.first { $0.id == id } }
    }

    /// Space: a quick look at the issue under the pointer or focus, or away again.
    func togglePeek() {
        if peekItemId != nil {
            withAnimation(Theme.overlay) { peekItemId = nil }
        } else if let item = targetItem {
            withAnimation(Theme.overlay) { peekItemId = item.id }
            loadRepoMeta(for: item)
        }
    }

    /// The peek follows the keyboard as it moves through issues.
    func followPeek(to id: String) {
        guard peekItemId != nil, peekItemId != id, let item = scopedItems.first(where: { $0.id == id }) else { return }
        peekItemId = id
        loadRepoMeta(for: item)
    }
}
