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
    var dueDate: String?
    var assignees: [Person] = []
    var labels: [LabelRef] = []
    var parent: Item?
    /// The milestone it starts in, by title: the board's milestone of that name.
    var milestoneTitle: String?
    /// Whether it starts as an epic.
    var isEpic = false
    /// The project's own fields it starts with, such as the iteration of the view it is made in.
    var fieldValues: [String: FieldValue] = [:]
}

/// What a new issue starts with when it is begun from a milestone, an epic's group or the roadmap.
struct NewIssuePlan: Equatable {
    var milestoneTitle: String?
    var isEpic = false
}

/// What the user can do to an issue. Each action becomes one or more queued mutations.
extension AppModel {
    // MARK: Status, priority, order

    func statusMutations(_ item: Item, _ option: FieldOption?) -> [Mutation] {
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

    /// Puts issues that are on none of your boards onto one, in the chosen column. A pull request the Inbox
    /// showed can go on one too.
    func addToProject(_ items: [Item], project: Project, status option: FieldOption?) {
        let (items, inserted) = keptForAdding(items.filter { !$0.isOnBoard && $0.kind != .draft })
        let mutations = items.flatMap { item -> [Mutation] in
            guard let contentId = item.contentId else { return [] }
            let add = Mutation.addToProject(.init(
                itemId: item.id, contentId: contentId, projectId: project.id,
                statusFieldId: option == nil ? nil : project.statusFieldId, statusId: option?.id
            ))
            return [add] + stateMutations(item, for: option)
        }
        withAnimation(Theme.spring) { perform(mutations, inserting: inserted) }
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

    /// Drops a card into a column at `index`, counted among the column's cards as shown, without the card and
    /// what hangs under it. A sub-issue whose parent is in the column joins the parent's sub-issues; any other
    /// card goes in front of or after the cards that stand on their own, never between a parent and its sub-issues.
    /// Dropped between two issues of an epic's group, or right below its header (`belowEpicHeader`), it joins the epic.
    func drop(_ item: Item, in column: BoardColumn, at index: Int, belowEpicHeader: String? = nil) {
        guard let projectId = item.projectId else { return }
        let itemEpic = epic(of: item)?.contentId
        let landing = column.landing(of: item, at: index, epic: itemEpic, belowHeader: belowEpicHeader)
        var mutations = columnMutations(item, column)
        // Dropped among another epic's issues, it joins that epic.
        if let joined = landing.epic, joined != itemEpic, canRelate(item), let summary = item.summary,
           let epic = issue(contentId: joined), canRelate(epic) {
            noteRecent(.parent, joined)
            mutations.append(.setParent(.init(
                child: summary, parentId: joined, parentNumber: epic.number, parentTitle: epic.title, base: item.parentId
            )))
        }
        // A view in an order of its own keeps it; only an unordered board has places to drop into, as on GitHub.
        if !isOrdered(projectId: projectId), let move = placement(of: item, in: column, at: landing, projectId: projectId) {
            mutations.append(move)
        }
        // A sub-issue dropped onto a folded parent would vanish into it, so the parent opens.
        if let parentId = landing.parentId, column.nesting.folded.contains(parentId),
           let parent = column.nesting.members.first(where: { $0.id == parentId }) {
            setFolded(parent, false)
        }
        perform(mutations)
    }

    /// What dropping a card into a column changes: its status, or the value of the field the columns are by.
    func columnMutations(_ item: Item, _ column: BoardColumn) -> [Mutation] {
        if let value = column.value, let field = field(id: value.fieldId) {
            return valueMutations(item, field: field, value: value.value)
        }
        return statusMutations(item, column.option)
    }

    /// Whether the view open in a project has an order of its own, which dragging can't change.
    func isOrdered(projectId: String?) -> Bool {
        guard let view = currentView(projectId: projectId) else { return false }
        return !sort(of: view).isEmpty
    }

    /// The move that gives a card its place among `landing.peers`, or nil when it is there already.
    private func placement(of item: Item, in column: BoardColumn, at landing: Nesting.Landing, projectId: String) -> Mutation? {
        placements(of: [item], in: column, at: landing, projectId: projectId).first
    }

    /// The moves that give cards their place among `landing.peers`, one after the other in their board order, or
    /// none when they are there already.
    private func placements(of items: [Item], in column: BoardColumn, at landing: Nesting.Landing, projectId: String) -> [Mutation] {
        let peers = landing.peers
        let items = items.sorted { $0.position < $1.position }
        guard let first = items.first, !peers.isEmpty else { return [] }
        if column.nesting.members.contains(where: { $0.id == first.id }),
           peers.filter({ $0.position < first.position }).count == landing.rank {
            return []
        }
        var afterId: String?
        if landing.rank > 0 {
            afterId = peers[landing.rank - 1].id
        } else {
            // To sit above the first of them, go right behind whatever precedes it in the project.
            let moving = Set(items.map(\.id))
            let all = allItems.filter { $0.projectId == projectId && !moving.contains($0.id) }
            let index = all.firstIndex { $0.id == peers[0].id } ?? 0
            afterId = index > 0 ? all[index - 1].id : nil
        }
        return items.map { item in
            defer { afterId = item.id }
            return .move(.init(itemId: item.id, projectId: projectId, afterItemId: afterId))
        }
    }

    // MARK: An epic's issues together

    /// Drops `members`, the issues of an epic's group in a column, all of them together into a column at `index`,
    /// counted among that column's issues as shown without them. They take the column's status and keep their
    /// order, in front of or after what stands there on its own, or among the epic's issues the column has already.
    func drop(_ group: Nesting.EpicGroup, members: [Item], in column: BoardColumn, at index: Int) {
        guard let projectId = members.first?.projectId else { return }
        let landing = column.landing(ofGroup: group.contentId, moving: Set(members.map(\.id)), at: index)
        let placing = isOrdered(projectId: projectId) ? [] : placements(of: members, in: column, at: landing, projectId: projectId)
        if column.value != nil {
            withAnimation(Theme.spring) { perform(members.flatMap { columnMutations($0, column) } + placing) }
            return
        }
        moveIssues(members, of: group, to: column.option, title: column.title, placing: placing)
    }

    /// Gives `members`, the issues of an epic's group in a column, another status, as the group's menu does. They
    /// keep their places on the board, as an issue does whose status changes.
    func setStatus(of group: Nesting.EpicGroup, members: [Item], to option: FieldOption) {
        withAnimation(Theme.spring) {
            moveIssues(members, of: group, to: option, title: option.name, placing: [])
        }
    }

    /// Moves an epic's issues to the column of `option`, with the `placing` moves that give them their place there.
    /// Where their status changes, a message says how many moved, with a way to take it back.
    private func moveIssues(_ members: [Item], of group: Nesting.EpicGroup, to option: FieldOption?, title: String, placing: [Mutation]) {
        let changes = members.flatMap { statusMutations($0, option) }
        guard !changes.isEmpty || !placing.isEmpty else { return }
        // Undoing gives each issue its status, state and place back.
        var undo: [Mutation] = []
        for change in changes {
            switch change {
            case .setField(var field):
                swap(&field.optionId, &field.base)
                undo.append(.setField(field))
            case .setState(let state):
                guard let before = members.first(where: { $0.contentId == state.contentId }) else { break }
                undo.append(.setState(.init(contentId: state.contentId, closed: before.isClosed, reason: before.isClosed ? before.stateReason : nil)))
            default:
                break
            }
        }
        if !placing.isEmpty, let projectId = members.first?.projectId {
            let board = allItems.filter { $0.projectId == projectId }
            for member in members.sorted(by: { $0.position < $1.position }) {
                let index = board.firstIndex { $0.id == member.id } ?? 0
                undo.append(.move(.init(itemId: member.id, projectId: projectId, afterItemId: index > 0 ? board[index - 1].id : nil)))
            }
        }
        perform(changes + placing)
        guard !changes.isEmpty else { return }
        status.post(Notice(
            title: String(localized: .epicIssuesMovedToStatus(count: members.count, status: title)),
            message: group.epic.title,
            action: .undo(undo)
        ))
    }

    /// Moves an issue one place up or down within its column, which is also its section of the list: past the
    /// next card that stands on its own, or past the next sub-issue of the same parent. Returns false at either
    /// end, or where the project can't be changed.
    @discardableResult
    func move(_ item: Item, by delta: Int) -> Bool {
        guard let projectId = item.projectId, project(of: item)?.viewerCanUpdate == true, !isOrdered(projectId: projectId),
              let column = (columns.contains { $0.items.contains { $0.id == item.id } } ? columns : columns(projectId: projectId))
                .first(where: { $0.items.contains { $0.id == item.id } }),
              let index = column.items.firstIndex(where: { $0.id == item.id }) else { return false }
        var landing = column.landing(of: item, at: index, epic: epic(of: item)?.contentId)
        let rank = landing.rank + delta
        guard rank >= 0, rank <= landing.peers.count, rank != landing.rank else { return false }
        landing.rank = rank
        guard let move = placement(of: item, in: column, at: landing, projectId: projectId) else { return false }
        perform([move])
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
        if !assigned { noteRecent(.assignee, person.id) }
        perform([.editAssignees(.init(contentId: contentId, add: assigned ? [] : [person], remove: assigned ? [person] : []))])
    }

    func toggleLabel(_ item: Item, _ label: LabelRef) {
        guard item.kind != .draft, let contentId = item.contentId else { return }
        let has = item.labels.contains { $0.id == label.id }
        if !has { noteRecent(.label, label.name) }
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
        let contentId = LocalID.make()
        if let project { UserDefaults.standard.set(repo.id, forKey: "lastRepo.\(project.id)") }
        // The milestone of that name in the issue's repository, made there first if it has none.
        var mutations: [Mutation] = []
        var milestone: Milestone?
        if let title = draft.milestoneTitle,
           let group = (project.map { milestoneGroups(projectId: $0.id) } ?? milestoneGroups(repoId: repo.id)).first(where: { $0.title == title }) {
            milestone = group.milestone(inRepository: repo.id)
            if milestone == nil {
                let made = Milestone(
                    id: LocalID.make(), repoId: repo.id, repo: repo.nameWithOwner, number: 0, title: group.title,
                    descr: group.descr, dueOn: group.due?.string, state: "OPEN", closedAt: nil, url: nil
                )
                mutations.append(.createMilestone(.init(
                    milestoneId: made.id, repoId: repo.id, repo: repo.nameWithOwner, title: made.title, dueOn: made.dueOn, descr: made.descr
                )))
                milestone = made
            }
        }
        mutations.append(.createIssue(.init(
            itemId: itemId, contentId: contentId, projectId: project?.id, repoId: repo.id, repo: repo.nameWithOwner,
            title: title, body: draft.body,
            statusFieldId: project?.statusFieldId, statusId: project == nil ? nil : draft.statusId,
            priorityFieldId: project?.priorityFieldId, priorityId: project == nil ? nil : draft.priorityId,
            dueDate: project == nil ? nil : draft.dueDate,
            assignees: draft.assignees, labels: draft.labels,
            parentContentId: draft.parent?.contentId, parentNumber: draft.parent?.number, parentTitle: draft.parent?.title,
            milestoneId: milestone?.id, milestoneTitle: milestone?.title,
            fieldValues: project == nil || draft.fieldValues.isEmpty ? nil : draft.fieldValues,
            author: viewer?.login, createdAt: Date()
        )))
        if draft.isEpic {
            mutations.append(.setEpic(.init(
                contentId: contentId, repoId: repo.id, repo: repo.nameWithOwner, isEpic: true, label: epicLabel(repoId: repo.id)
            )))
        }
        perform(mutations)
        if draft.dueDate != nil { notifier.requestPermissionIfNeeded() }
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
                    title: String(localized: .columnsCouldNotBeSaved),
                    message: String(localized: .changingColumnsNeedsConnection(error: error.localizedDescription)),
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
        case .milestone(let id, let title): "listOrder.milestone.\(id).\(title)"
        case .roadmap(let id): "listOrder.roadmap.\(id)"
        case .inbox, nil: nil
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
        case .milestone(let id, let title): "collapsed.milestone.\(id).\(title)"
        case .roadmap(let id): "collapsed.roadmap.\(id)"
        case .inbox, nil: nil
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
    /// Whether a section is folded: as you left it, or else as its kind starts out (`byDefault`).
    func isSectionCollapsed(_ id: String, in scope: Scope? = nil, byDefault: Bool = false) -> Bool {
        _ = collapseVersion
        guard let key = collapsedKey(scope) else { return false }
        if UserDefaults.standard.stringArray(forKey: key)?.contains(id) ?? false { return true }
        return byDefault && !(UserDefaults.standard.stringArray(forKey: "expanded." + key)?.contains(id) ?? false)
    }

    /// Whether a section of the list is folded, with its kind's start: see `foldsByDefault`.
    func isFolded(_ section: ListSection, in scope: Scope? = nil) -> Bool {
        isSectionCollapsed(section.id, in: scope, byDefault: foldsByDefault(section))
    }

    func toggleSection(_ id: String, in scope: Scope? = nil) {
        guard let key = collapsedKey(scope) else { return }
        let list = scope.map { $0 == self.scope ? sections : sections(for: $0) } ?? sections
        let byDefault = list.first { $0.id == id }.map(foldsByDefault) ?? false
        let wasFolded = isSectionCollapsed(id, in: scope, byDefault: byDefault)
        var folded = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        var unfolded = Set(UserDefaults.standard.stringArray(forKey: "expanded." + key) ?? [])
        if wasFolded {
            folded.remove(id)
            // Remembered only where it differs from how the section starts out.
            if byDefault { unfolded.insert(id) }
        } else {
            folded.insert(id)
            unfolded.remove(id)
        }
        UserDefaults.standard.set(Array(folded), forKey: key)
        UserDefaults.standard.set(Array(unfolded), forKey: "expanded." + key)
        collapseVersion += 1
    }

    /// Option-click on a header, as in Finder: folds every section in or out, following the one clicked.
    func toggleAllSections(like id: String) {
        guard let key = collapsedKey(nil) else { return }
        let fold = !(sections.first { $0.id == id }.map { isFolded($0) } ?? isSectionCollapsed(id))
        UserDefaults.standard.set(fold ? sections.map(\.id) : [], forKey: key)
        UserDefaults.standard.set(fold ? [] : sections.map(\.id), forKey: "expanded." + key)
        collapseVersion += 1
    }

    func addPriorityField(projectId: String) {
        let engine = self.engine
        Task {
            do {
                try await engine.createPriorityField(projectId: projectId)
            } catch {
                status.post(Notice(title: String(localized: .priorityCouldNotBeAdded), message: error.localizedDescription, isWarning: true))
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
        status.post(Notice(title: String(localized: .branchNameCopied), message: name))
    }

    func copyLink(_ url: String, for label: String) {
        Platform.copy(url)
        status.post(Notice(title: String(localized: .linkCopied), message: label))
    }

    func apply(_ action: Notice.Action) {
        switch action {
        case .applyField(let mutation, _):
            perform([.setField(mutation)])
        case .applyDate(let mutation, _):
            perform([.setDate(mutation)])
        case .openItem(let id):
            if let item = allItems.first(where: { $0.id == id }) { open(item) }
        case .undo(let mutations):
            // Each change starts from what GitHub has now, which is what was done.
            let current = mutations.map { mutation -> Mutation in
                guard case .setMilestone(var change) = mutation else { return mutation }
                change.base = issue(contentId: change.contentId)?.milestoneId
                return .setMilestone(change)
            }
            withAnimation(Theme.spring) { perform(current) }
        }
    }
}

extension FieldOption {
    /// The shape GitHub wants when saving options. Options not yet saved have no id to send.
    var remote: RemoteOption {
        RemoteOption(id: id.hasPrefix(LocalID.prefix) ? nil : id, name: name, color: color, descr: descr)
    }
}
