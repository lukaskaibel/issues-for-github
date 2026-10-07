import GRDB
import SwiftUI

struct NewIssueDraft: Equatable {
    /// The board the issue goes on; nil creates it in the repository only.
    var projectId: String?
    var repoId: String?
    var title = ""
    var body = ""
    var statusId: String?
    var priorityId: String?
    var assignees: [Person] = []
    var labels: [LabelRef] = []
    var parent: Item?
}

/// What the user can do to an issue. Each action becomes one or more queued mutations.
extension AppModel {
    // MARK: Status, priority, order

    private func statusMutations(_ item: Item, _ option: FieldOption?) -> [Mutation] {
        guard let projectId = item.projectId, let fieldId = project(of: item)?.statusFieldId else { return [] }
        var result: [Mutation] = []
        if item.statusId != option?.id {
            result.append(.setField(.init(
                itemId: item.id, projectId: projectId, fieldId: fieldId, kind: .status,
                optionId: option?.id, base: item.statusId
            )))
        }
        result += stateMutations(item, for: option)
        return result
    }

    /// Keeps GitHub's open/closed state in line with the column, so the issue reads right on github.com too.
    private func stateMutations(_ item: Item, for option: FieldOption?) -> [Mutation] {
        var result: [Mutation] = []
        if item.kind == .issue, let contentId = item.contentId, let option {
            if let reason = option.statusCategory.closeReason {
                if !item.isClosed || item.stateReason != reason {
                    result.append(.setState(.init(contentId: contentId, closed: true, reason: reason)))
                }
            } else if item.isClosed {
                result.append(.setState(.init(contentId: contentId, closed: false, reason: nil)))
            }
        }
        return result
    }

    func setStatus(_ item: Item, to option: FieldOption?) {
        perform(statusMutations(item, option))
    }

    /// Puts issues that are on none of your boards onto one, in the chosen column.
    func addToProject(_ items: [Item], project: Project, status option: FieldOption?) {
        let mutations = items.filter { !$0.isOnBoard && $0.kind == .issue }.flatMap { item -> [Mutation] in
            guard let contentId = item.contentId else { return [] }
            let add = Mutation.addToProject(.init(
                itemId: item.id, contentId: contentId, projectId: project.id,
                statusFieldId: option == nil ? nil : project.statusFieldId, statusId: option?.id
            ))
            return [add] + stateMutations(item, for: option)
        }
        withAnimation(Theme.spring) { perform(mutations) }
    }

    /// Whether an issue counts as finished: in a done or cancelled column, or closed on GitHub.
    func isDone(_ item: Item) -> Bool {
        statusOption(of: item)?.statusCategory.isClosed ?? item.isClosed
    }

    func canToggleDone(_ item: Item) -> Bool {
        if project(of: item)?.statusFieldId != nil, !statusOptions(projectId: item.projectId).isEmpty { return true }
        return item.kind == .issue && item.contentId != nil
    }

    /// Marks an issue done (the first "done" column), or back to the first column to work on.
    func toggleDone(_ item: Item) {
        let statuses = statusOptions(projectId: item.projectId)
        let done = isDone(item)
        let target = done
            ? statuses.first { $0.statusCategory == .unstarted } ?? statuses.first { $0.statusCategory == .backlog } ?? statuses.first { $0.statusCategory == .started }
            : statuses.first { $0.statusCategory == .completed }
        if let target, project(of: item)?.statusFieldId != nil {
            setStatus(item, to: target)
        } else if item.kind == .issue, let contentId = item.contentId {
            perform([.setState(.init(contentId: contentId, closed: !done, reason: done ? nil : "COMPLETED"))])
        }
    }

    func setPriority(_ item: Item, to option: FieldOption?) {
        guard let projectId = item.projectId, let fieldId = project(of: item)?.priorityFieldId, item.priorityId != option?.id else { return }
        perform([.setField(.init(
            itemId: item.id, projectId: projectId, fieldId: fieldId, kind: .priority,
            optionId: option?.id, base: item.priorityId
        ))])
    }

    /// Drops a card into a column at `index`, counted among the column's other cards.
    func drop(_ item: Item, in column: BoardColumn, at index: Int) {
        guard let projectId = item.projectId else { return }
        var mutations = statusMutations(item, column.option)
        let others = column.items.filter { $0.id != item.id }
        let target = min(max(index, 0), others.count)
        let unchanged = column.items.firstIndex { $0.id == item.id } == target
        if !unchanged, !others.isEmpty {
            let afterId: String?
            if target > 0 {
                afterId = others[target - 1].id
            } else {
                // To sit above the column's first card, go right behind whatever precedes that card in the project.
                let all = allItems.filter { $0.projectId == item.projectId && $0.id != item.id }
                let first = all.firstIndex { $0.id == others[0].id } ?? 0
                afterId = first > 0 ? all[first - 1].id : nil
            }
            mutations.append(.move(.init(itemId: item.id, projectId: projectId, afterItemId: afterId)))
        }
        perform(mutations)
    }

    /// Moves an issue one place up or down within its column, which is also its section of the list.
    /// Returns false at either end of the column, or where the project can't be changed.
    @discardableResult
    func move(_ item: Item, by delta: Int) -> Bool {
        guard project(of: item)?.viewerCanUpdate == true,
              let column = columns(projectId: item.projectId).first(where: { $0.items.contains { $0.id == item.id } }),
              let index = column.items.firstIndex(where: { $0.id == item.id }),
              column.items.indices.contains(index + delta) else { return false }
        drop(item, in: column, at: index + delta)
        return true
    }

    // MARK: Content

    func rename(_ item: Item, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard item.isEditableContent, let contentId = item.contentId, !trimmed.isEmpty, trimmed != item.title else { return }
        perform([.setTitle(.init(itemId: item.id, contentId: contentId, value: trimmed, base: item.title))])
    }

    func setBody(_ item: Item, to body: String) {
        guard item.isEditableContent, let contentId = item.contentId, body != item.body else { return }
        perform([.setBody(.init(itemId: item.id, contentId: contentId, value: body, base: item.body))])
    }

    func toggleAssignee(_ item: Item, _ person: Person) {
        guard item.kind != .draft, let contentId = item.contentId else { return }
        let assigned = item.assignees.contains { $0.id == person.id }
        perform([.editAssignees(.init(contentId: contentId, add: assigned ? [] : [person], remove: assigned ? [person] : []))])
    }

    func toggleLabel(_ item: Item, _ label: LabelRef) {
        guard item.kind != .draft, let contentId = item.contentId else { return }
        let has = item.labels.contains { $0.id == label.id }
        perform([.editLabels(.init(contentId: contentId, add: has ? [] : [label], remove: has ? [label] : []))])
    }

    func addComment(to item: Item, body: String) {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard item.kind != .draft, let contentId = item.contentId, let viewer, !trimmed.isEmpty else { return }
        perform([.addComment(.init(
            commentId: LocalID.make(), contentId: contentId, body: trimmed, author: viewer.person, createdAt: Date()
        ))])
    }

    func setClosed(_ sub: SubIssue, _ closed: Bool) {
        // A sub-issue that is on the board moves columns like any other card.
        if let item = item(contentId: sub.id) {
            let statuses = statusOptions(projectId: item.projectId)
            let wanted: StatusCategory = closed ? .completed : .unstarted
            if let option = statuses.first(where: { $0.statusCategory == wanted }) {
                setStatus(item, to: option)
                return
            }
        }
        perform([.setState(.init(contentId: sub.id, closed: closed, reason: closed ? "COMPLETED" : nil))])
    }

    @discardableResult
    func createIssue(_ draft: NewIssueDraft) -> String? {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = draft.projectId.flatMap { id in projects.first { $0.id == id } }
        guard !title.isEmpty, draft.projectId == nil || project != nil,
              let repo = repos(forNewIssueIn: draft.projectId, repoId: draft.repoId).first(where: { $0.id == draft.repoId }) else { return nil }
        let itemId = LocalID.make()
        if let project { UserDefaults.standard.set(repo.id, forKey: "lastRepo.\(project.id)") }
        perform([.createIssue(.init(
            itemId: itemId, contentId: LocalID.make(), projectId: project?.id, repoId: repo.id, repo: repo.nameWithOwner,
            title: title, body: draft.body,
            statusFieldId: project?.statusFieldId, statusId: project == nil ? nil : draft.statusId,
            priorityFieldId: project?.priorityFieldId, priorityId: project == nil ? nil : draft.priorityId,
            assignees: draft.assignees, labels: draft.labels,
            parentContentId: draft.parent?.contentId, parentNumber: draft.parent?.number, parentTitle: draft.parent?.title,
            author: viewer?.login, createdAt: Date()
        ))])
        return itemId
    }

    /// Repositories a new issue can be created in: the board's, or, for one on no board, the one it was started in.
    func repos(forNewIssueIn projectId: String?, repoId: String?) -> [RepoRef] {
        if projectId != nil { return repos(projectId: projectId) }
        return repoId.flatMap(anyRepository(id:)).map { [$0] } ?? []
    }

    /// A repository by id, also one none of your boards use, known only from an issue of it.
    func anyRepository(id: String) -> RepoRef? {
        if let known = repository(id: id) { return known }
        guard let name = allItems.first(where: { $0.repoId == id })?.repo else { return nil }
        return RepoRef(id: id, nameWithOwner: name, projectId: "")
    }

    func defaultRepoId(projectId: String) -> String? {
        let available = repos(projectId: projectId)
        let last = UserDefaults.standard.string(forKey: "lastRepo.\(projectId)")
        if let last, available.contains(where: { $0.id == last }) { return last }
        // Otherwise the repository most cards on this board come from.
        let counts = Dictionary(grouping: allItems.filter { $0.projectId == projectId }.compactMap(\.repoId)) { $0 }.mapValues(\.count)
        return counts.max { $0.value < $1.value }?.key ?? available.first?.id
    }

    // MARK: Deleting

    /// Issues can be deleted with admin rights in their repository; drafts by anyone who can edit the board.
    /// Pull requests can't be deleted on GitHub at all.
    func canDelete(_ item: Item) -> Bool {
        switch item.kind {
        case .issue: item.viewerCanDelete || item.isLocalOnly
        case .draft: project(of: item)?.viewerCanUpdate == true
        case .pullRequest, .redacted: false
        }
    }

    /// Asks for confirmation first; deleting on GitHub can't be undone.
    func requestDelete(_ item: Item) {
        guard canDelete(item) else { return }
        deletionCandidate = item
    }

    func delete(_ item: Item) {
        deletionCandidate = nil
        let wasCurrent = openItemId == item.id || cursorId == item.id
        if openItemId == item.id { closeDetail() }
        // The keyboard carries on from the issue after it (or before it, at the end), so deleting doesn't send
        // you back to the top.
        let order = wasCurrent ? orderedItems : []
        let next = order.firstIndex { $0.id == item.id }.flatMap { index in
            order.indices.contains(index + 1) ? order[index + 1] : index > 0 ? order[index - 1] : nil
        }
        if focusedItemId == item.id { focusedItemId = nil }
        if hoveredItemId == item.id { hoveredItemId = nil }
        history.removeAll { $0.itemId == item.id }
        historyIndex = min(historyIndex, history.count - 1)
        withAnimation(Theme.spring) {
            perform([.deleteItem(.init(
                itemId: item.id, projectId: item.projectId, contentId: item.contentId,
                isDraft: item.kind == .draft, label: "\(item.displayNumber) \(item.title)"
            ))])
        }
        if let next { moveFocus(to: next.id) }
    }

    // MARK: Columns

    /// Saves a new set of status columns. Shown at once; rolled back if GitHub refuses.
    func saveColumns(projectId: String, _ newOptions: [RemoteOption]) {
        guard let fieldId = projects.first(where: { $0.id == projectId })?.statusFieldId else { return }
        do {
            try db.writer.write { db in
                try FieldOption.filter(Column("projectId") == projectId && Column("fieldId") == fieldId).deleteAll(db)
                for (index, option) in newOptions.enumerated() {
                    try FieldOption(
                        id: option.id ?? LocalID.make(), fieldId: fieldId, projectId: projectId, kind: .status,
                        name: option.name, color: option.color, descr: option.descr, position: index
                    ).insert(db)
                }
            }
        } catch {
            return
        }
        reloadNow()
        let engine = self.engine
        Task {
            do {
                try await engine.updateOptions(projectId: projectId, fieldId: fieldId, kind: .status, options: newOptions)
            } catch {
                status.post(Notice(
                    title: "Columns could not be saved",
                    message: "Changing columns needs a connection to GitHub. \(error.localizedDescription)",
                    isWarning: true
                ))
                await engine.forceRefresh()
            }
        }
    }

    // MARK: List section order

    private func listOrderKey(_ scope: Scope?) -> String? {
        switch scope ?? self.scope {
        case .project(let id): "listOrder.\(id)"
        case .myIssues: "listOrder.mine"
        case .repository(let id): "listOrder.repository.\(id)"
        case nil: nil
        }
    }

    /// The order the list's sections were put into, if they were. This is a preference of this device
    /// and does not change the project on GitHub; the board's column order does.
    func customListOrder(for scope: Scope? = nil) -> [String] {
        listOrderKey(scope).flatMap { UserDefaults.standard.stringArray(forKey: $0) } ?? []
    }

    /// Moves a list section in front of another one (or to the end).
    func moveListSection(_ id: String, before target: String?, in scope: Scope? = nil) {
        guard let scope = scope ?? self.scope, id != target else { return }
        let current = sections(for: scope)
        var order = current.map(\.id)
        // Sections that are currently empty keep their remembered place after the visible ones.
        order += customListOrder(for: scope).filter { !order.contains($0) }
        order.removeAll { $0 == id }
        if let target, let index = order.firstIndex(of: target) {
            order.insert(id, at: index)
        } else {
            order.insert(id, at: current.filter { $0.id != id }.count)
        }
        setListOrder(order, in: scope)
    }

    /// Puts the list's sections into exactly this order.
    func setListOrder(_ ids: [String], in scope: Scope) {
        guard let key = listOrderKey(scope) else { return }
        var order = ids
        order += customListOrder(for: scope).filter { !order.contains($0) }
        UserDefaults.standard.set(order, forKey: key)
        reloadNow()
    }

    /// Back to the order the list has by itself: work in progress first.
    func resetListOrder(in scope: Scope) {
        guard let key = listOrderKey(scope) else { return }
        UserDefaults.standard.removeObject(forKey: key)
        reloadNow()
    }

    // MARK: Folding list sections

    private func collapsedKey(_ scope: Scope?) -> String? {
        switch scope ?? self.scope {
        case .project(let id): "collapsed.\(id)"
        case .myIssues: "collapsed.mine"
        case .repository(let id): "collapsed.repository.\(id)"
        case nil: nil
        }
    }

    /// Hides a repository from the sidebar or brings it back. Hiding the one on screen goes to My Issues.
    func setHidden(_ repo: RepoRef, _ hidden: Bool) {
        withAnimation(Theme.spring) {
            if hidden { hiddenRepositoryIds.insert(repo.id) } else { hiddenRepositoryIds.remove(repo.id) }
        }
        if hidden, scope == .repository(repo.id) { select(.myIssues) }
    }

    /// Hides a project from the sidebar or brings it back. Hiding the one on screen moves to the next.
    func setHidden(_ project: Project, _ hidden: Bool) {
        withAnimation(Theme.spring) {
            if hidden { hiddenProjectIds.insert(project.id) } else { hiddenProjectIds.remove(project.id) }
        }
        guard hidden, scope == .project(project.id) else { return }
        if let next = projects.first(where: { !$0.closed && !hiddenProjectIds.contains($0.id) }) {
            select(.project(next.id))
        } else {
            select(.myIssues)
        }
    }

    /// Sections folded in, in the list. Kept per project on this device.
    func isSectionCollapsed(_ id: String, in scope: Scope? = nil) -> Bool {
        _ = collapseVersion
        guard let key = collapsedKey(scope) else { return false }
        return UserDefaults.standard.stringArray(forKey: key)?.contains(id) ?? false
    }

    func toggleSection(_ id: String, in scope: Scope? = nil) {
        guard let key = collapsedKey(scope) else { return }
        var folded = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        if folded.contains(id) { folded.remove(id) } else { folded.insert(id) }
        UserDefaults.standard.set(Array(folded), forKey: key)
        collapseVersion += 1
    }

    /// Option-click on a header, as in Finder: folds every section in or out, following the one clicked.
    func toggleAllSections(like id: String) {
        guard let key = collapsedKey(nil) else { return }
        let fold = !isSectionCollapsed(id)
        UserDefaults.standard.set(fold ? sections.map(\.id) : [], forKey: key)
        collapseVersion += 1
    }

    func addPriorityField(projectId: String) {
        let engine = self.engine
        Task {
            do {
                try await engine.createPriorityField(projectId: projectId)
            } catch {
                status.post(Notice(title: "Priority could not be added", message: error.localizedDescription, isWarning: true))
            }
        }
    }

    // MARK: Leaving the app

    func openOnGitHub(_ item: Item) {
        if let url = item.url.flatMap(URL.init(string:)) { Platform.open(url) }
    }

    func copyLink(_ item: Item) {
        guard let url = item.url else { return }
        copyLink(url, for: "\(item.displayNumber) \(item.title)")
    }

    /// Linear's ⌘⇧. copies a branch name for the issue; this copies the one GitHub suggests.
    func copyBranchName(_ item: Item) {
        guard let name = item.branchName else { return }
        Platform.copy(name)
        status.post(Notice(title: "Branch name copied", message: name))
    }

    func copyLink(_ url: String, for label: String) {
        Platform.copy(url)
        status.post(Notice(title: "Link copied", message: label))
    }

    func apply(_ action: Notice.Action) {
        switch action {
        case .applyField(let mutation, _):
            perform([.setField(mutation)])
        case .openItem(let id):
            if let item = allItems.first(where: { $0.id == id }) { open(item) }
        }
    }
}

extension FieldOption {
    /// The shape GitHub wants when saving options. Options not yet saved have no id to send.
    var remote: RemoteOption {
        RemoteOption(id: id.hasPrefix(LocalID.prefix) ? nil : id, name: name, color: color, descr: descr)
    }
}
