import GRDB
import SwiftUI

/// Sub-issues hanging under their parent in lists and on boards: folding them in, and finishing the parent with
/// the last of them.
extension AppModel {
    // MARK: Folding

    /// Whether the sub-issues hanging under this issue are folded into it.
    func isFolded(_ item: Item) -> Bool {
        item.contentId.map { foldedParents.contains($0) } ?? false
    }

    func toggleFolded(_ item: Item) {
        setFolded(item, !isFolded(item))
    }

    /// Folds the sub-issues under an issue in or out, everywhere it hangs them. The keyboard focus on one of them
    /// moves up to the issue.
    func setFolded(_ item: Item, _ folded: Bool) {
        guard let contentId = item.contentId, folded != isFolded(item) else { return }
        withAnimation(Theme.spring) {
            if folded { foldedParents.insert(contentId) } else { foldedParents.remove(contentId) }
            rebuild()
        }
        if let focused = focusedItemId, !orderedItems.contains(where: { $0.id == focused }) {
            moveFocus(to: item.id)
        }
    }

    /// Folds the issues of an epic away under its header on boards and in lists, or shows them again. The
    /// keyboard focus on one of them is let go.
    func toggleEpicGroup(_ group: Nesting.EpicGroup) {
        let folding = !foldedEpics.contains(group.contentId)
        withAnimation(Theme.spring) {
            if folding { foldedEpics.insert(group.contentId) } else { foldedEpics.remove(group.contentId) }
            rebuild()
        }
        if let focused = focusedItemId, !orderedItems.contains(where: { $0.id == focused }) {
            focusedItemId = nil
        }
    }

    /// The column or group an issue is shown in right now, for what hangs under it there.
    func nesting(around item: Item) -> Nesting? {
        if openItem == nil, viewMode == .board, currentProjectId != nil {
            return columns.first { $0.nesting.members.contains { $0.id == item.id } }?.nesting
        }
        return sections.first { $0.nesting.members.contains { $0.id == item.id } }?.nesting
    }

    // MARK: Finishing the parent

    /// Changes that mark parents done because `mutations` finish the last of their open sub-issues, and the parents
    /// they finish. A parent finished this way can finish its own parent in turn. Only changes made here do this,
    /// not ones that come from GitHub, so two devices never both act on the same change.
    func parentCompletions(after mutations: [Mutation]) -> (mutations: [Mutation], parents: [Item]) {
        guard completesParents else { return ([], []) }
        var added: [Mutation] = []
        var parents: [Item] = []
        var handled = Set<String>()
        // Parents more than a few levels up are rare; GitHub allows eight.
        for _ in 0..<8 {
            let finishing = issuesFinished(by: mutations + added)
            let candidates = finishing.flatMap(parentIds(of:)).filter { !handled.contains($0) && !finishing.contains($0) }
            var found = false
            for parentId in Set(candidates) {
                handled.insert(parentId)
                guard let parent = allItems.first(where: { $0.contentId == parentId }), !wasDone(parentId),
                      allSubIssuesDone(of: parent, finishing: finishing) else { continue }
                let change = doneMutations(for: parentId)
                guard !change.isEmpty else { continue }
                added += change
                parents.append(parent)
                found = true
            }
            if !found { break }
        }
        return (added, parents)
    }

    /// Issues (node ids) that were open or not done, and that these changes close or move to a done column.
    private func issuesFinished(by mutations: [Mutation]) -> Set<String> {
        var result = Set<String>()
        for mutation in mutations {
            switch mutation {
            case .setState(let change) where change.closed:
                result.insert(change.contentId)
            case .setField(let change) where change.kind == .status:
                guard let item = allItems.first(where: { $0.id == change.itemId }), let contentId = item.contentId,
                      let option = options.first(where: {
                          $0.id == change.optionId && $0.projectId == change.projectId && $0.kind == .status
                      }), option.statusCategory.isClosed else { continue }
                result.insert(contentId)
            default:
                continue
            }
        }
        return result.filter { !wasDone($0) }
    }

    /// The parents an issue is a sub-issue of, as its cards and the lists of sub-issues seen say.
    private func parentIds(of contentId: String) -> [String] {
        var result = allItems.filter { $0.contentId == contentId }.compactMap(\.parentId)
        let listed = (try? db.reader.read { db in
            try String.fetchAll(db, sql: "SELECT parentId FROM subIssue WHERE id = ?", arguments: [contentId])
        }) ?? []
        result += listed
        return Array(Set(result))
    }

    /// Whether an issue counted as finished before the change: done on its board, or closed.
    private func wasDone(_ contentId: String) -> Bool {
        if let item = allItems.first(where: { $0.contentId == contentId }) { return isDone(item) }
        let state = try? db.reader.read { db in
            try String.fetchOne(db, sql: "SELECT state FROM subIssue WHERE id = ? LIMIT 1", arguments: [contentId])
        }
        return state.map { $0 != "OPEN" } ?? false
    }

    /// Whether every sub-issue of `parent` is finished once `finishing` are. Sub-issues the app has never seen are
    /// taken from GitHub's count of finished ones.
    private func allSubIssuesDone(of parent: Item, finishing: Set<String>) -> Bool {
        guard let parentId = parent.contentId else { return false }
        // Sub-issue → whether it was closed on GitHub before, from cards and from the parent's list of sub-issues.
        var known: [String: Bool] = [:]
        let listed = (try? db.reader.read { db in
            try SubIssue.filter(Column("parentId") == parentId).fetchAll(db)
        }) ?? []
        for sub in listed { known[sub.id] = sub.isClosed }
        for item in allItems where item.parentId == parentId {
            if let contentId = item.contentId { known[contentId] = item.isClosed }
        }
        let total = max(parent.subTotal, known.count)
        guard total > 0, !known.isEmpty,
              known.keys.allSatisfy({ finishing.contains($0) || wasDone($0) }) else { return false }
        if known.count >= total { return true }
        let newlyClosed = known.filter { finishing.contains($0.key) && !$0.value }.count
        return parent.subCompleted + newlyClosed >= total
    }

    /// Moves an issue to the first done column of every board it is on, or closes it where it is on none.
    private func doneMutations(for contentId: String) -> [Mutation] {
        var result: [Mutation] = []
        var closes = false
        for item in allItems where item.contentId == contentId {
            guard project(of: item)?.statusFieldId != nil,
                  let done = statusOptions(projectId: item.projectId).first(where: { $0.statusCategory == .completed })
            else { continue }
            for mutation in statusMutations(item, done) {
                if case .setState = mutation {
                    guard !closes else { continue }
                    closes = true
                }
                result.append(mutation)
            }
        }
        if result.isEmpty, let item = allItems.first(where: { $0.contentId == contentId }), item.kind == .issue, !item.isClosed {
            result.append(.setState(.init(contentId: contentId, closed: true, reason: "COMPLETED")))
        }
        return result
    }
}

/// Settings for sub-issues: whether finishing the last one finishes the parent too.
struct SubIssueSettingsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Section {
            Toggle(.completeParentSetting, isOn: $model.completesParents)
        } header: {
            Text(.subIssues)
        } footer: {
            Text(.completeParentFooter)
        }
    }
}
