import Foundation
import GRDB

// Taking a change back. What undoes a change is worked out from the local database right before the change is applied,
// so it brings back what was really there, and it is an ordinary change: it goes to GitHub the same way, offline too.

extension Mutation {
    /// The changes that take this one back, read from the database as it is before this one is applied. Empty when this
    /// one changes nothing, or leaves nothing that needs taking back. Nil when it can't be taken back: GitHub can't bring
    /// back a deleted issue, and taking back a new issue or a comment would mean deleting it there for good.
    func reversal(_ db: Database) throws -> [Mutation]? {
        switch self {
        case .setField(var m):
            guard let item = try Item.fetchOne(db, key: m.itemId) else { return [] }
            let current = m.kind == .status ? item.statusId : item.priorityId
            guard current != m.optionId else { return [] }
            m.base = m.optionId
            m.optionId = current
            return [.setField(m)]

        case .setDate(var m):
            guard let item = try Item.fetchOne(db, key: m.itemId), item.dueDate != m.date else { return [] }
            m.base = m.date
            m.date = item.dueDate
            return [.setDate(m)]

        case .setProjectField(var m):
            guard let item = try Item.fetchOne(db, key: m.itemId) else { return [] }
            let current = item.fieldValues[m.fieldId]
            guard current != m.value else { return [] }
            m.base = m.value
            m.value = current
            m.valueName = try current.flatMap { try Self.valueName($0, fieldId: m.fieldId, db) }
            return [.setProjectField(m)]

        case .move(var m):
            guard let item = try Item.fetchOne(db, key: m.itemId), let projectId = item.projectId else { return [] }
            let before = try String.fetchOne(
                db,
                sql: "SELECT id FROM item WHERE projectId = ? AND position < ? AND id != ? ORDER BY position DESC LIMIT 1",
                arguments: [projectId, item.position, item.id]
            )
            guard before != m.afterItemId else { return [] }
            m.afterItemId = before
            return [.move(m)]

        case .setTitle(var m):
            guard let current = try Self.issueText("title", contentId: m.contentId, db), current != m.value else { return [] }
            m.base = m.value
            m.value = current
            m.theirs = nil
            return [.setTitle(m)]

        case .setBody(var m):
            guard let current = try String.fetchOne(db, sql: "SELECT body FROM item WHERE contentId = ? LIMIT 1", arguments: [m.contentId]),
                  current != m.value else { return [] }
            m.base = m.value
            m.value = current
            m.theirs = nil
            return [.setBody(m)]

        case .setState(var m):
            guard let state = try Self.issueText("state", contentId: m.contentId, db) else { return [] }
            let reason = try Self.issueText("stateReason", contentId: m.contentId, db)
            let closed = state != "OPEN"
            guard closed != m.closed || (closed && reason != m.reason) else { return [] }
            m.closed = closed
            m.reason = closed ? reason : nil
            return [.setState(m)]

        case .editAssignees(var m):
            let current = try Item.filter(Column("contentId") == m.contentId).fetchOne(db)?.assignees
                ?? InboxEntry.filter(Column("contentId") == m.contentId).fetchOne(db)?.assignees
            let added = m.add.filter { person in current?.contains { $0.id == person.id } != true }
            let removed = m.remove.filter { person in current?.contains { $0.id == person.id } ?? true }
            guard !added.isEmpty || !removed.isEmpty else { return [] }
            m.add = removed
            m.remove = added
            return [.editAssignees(m)]

        case .editLabels(var m):
            let current = try Item.filter(Column("contentId") == m.contentId).fetchOne(db)?.labels
                ?? InboxEntry.filter(Column("contentId") == m.contentId).fetchOne(db)?.labels
            let added = m.add.filter { label in current?.contains { $0.id == label.id } != true }
            let removed = m.remove.filter { label in current?.contains { $0.id == label.id } ?? true }
            guard !added.isEmpty || !removed.isEmpty else { return [] }
            m.add = removed
            m.remove = added
            return [.editLabels(m)]

        case .setParent(var m):
            let id = m.child.contentId
            let item = try Item.filter(Column("contentId") == id).fetchOne(db)
            let parentId = try item.map(\.parentId) ?? String.fetchOne(db, sql: "SELECT parentId FROM subIssue WHERE id = ? LIMIT 1", arguments: [id])
            guard parentId != m.parentId else { return [] }
            let parent = try parentId.flatMap { try Item.filter(Column("contentId") == $0).fetchOne(db) }
            m.base = m.parentId
            m.parentId = parentId
            m.parentNumber = item?.parentNumber ?? parent?.number
            m.parentTitle = item?.parentTitle ?? parent?.title
            return [.setParent(m)]

        case .setBlocking(var m):
            let listed = try LinkedIssue.exists(
                db, key: ["issueId": m.blocked.contentId, "relation": LinkedIssue.Relation.blockedBy.rawValue, "id": m.blocker.contentId]
            )
            guard listed != m.isBlocked else { return [] }
            m.base = m.isBlocked
            m.isBlocked = listed
            return [.setBlocking(m)]

        case .setMilestone(var m):
            let row = try Row.fetchOne(db, sql: "SELECT milestoneId, milestoneTitle FROM item WHERE contentId = ? LIMIT 1", arguments: [m.contentId])
                ?? Row.fetchOne(db, sql: "SELECT milestoneId, milestoneTitle FROM subIssue WHERE id = ? LIMIT 1", arguments: [m.contentId])
            let milestoneId: String? = row?["milestoneId"]
            guard milestoneId != m.milestoneId else { return [] }
            m.base = m.milestoneId
            m.milestoneId = milestoneId
            m.milestoneTitle = row?["milestoneTitle"]
            return [.setMilestone(m)]

        case .updateMilestone(var m):
            guard let milestone = try Milestone.fetchOne(db, key: m.milestoneId) else { return [] }
            var back = GitHubAPI.MilestoneChange()
            if let title = m.change.title, title != milestone.title { back.title = milestone.title }
            if let descr = m.change.descr, descr != milestone.descr { back.descr = milestone.descr }
            if let dueOn = m.change.dueOn, dueOn != (milestone.dueOn ?? "") { back.dueOn = milestone.dueOn ?? "" }
            if let state = m.change.state, state != milestone.state { back.state = milestone.state }
            guard back != GitHubAPI.MilestoneChange() else { return [] }
            m.change = back
            return [.updateMilestone(m)]

        case .setEpic(var m):
            guard let item = try Item.filter(Column("contentId") == m.contentId).fetchOne(db), item.isEpic != m.isEpic else { return [] }
            m.isEpic = item.isEpic
            return [.setEpic(m)]

        case .setIssueType(let m):
            guard let row = try Row.fetchOne(db, sql: "SELECT issueType, issueTypeColor FROM item WHERE contentId = ? LIMIT 1", arguments: [m.contentId])
                ?? Row.fetchOne(db, sql: "SELECT issueType, issueTypeColor FROM subIssue WHERE id = ? LIMIT 1", arguments: [m.contentId])
            else { return [] }
            let name: String? = row["issueType"]
            let color: String? = row["issueTypeColor"]
            guard name != m.name else { return [] }
            // GitHub sets a type by its id, and the one this change replaces is the only one known here.
            guard name == nil || (name == m.baseName && m.baseTypeId != nil) else { return nil }
            return [.setIssueType(.init(
                contentId: m.contentId, typeId: name == nil ? nil : m.baseTypeId, name: name, color: color,
                baseName: m.name, baseColor: m.color, baseTypeId: m.typeId
            ))]

        // What was made stays: a label or a milestone nobody uses does no harm, and the changes that used it are taken back.
        case .createLabel, .createMilestone:
            return []

        // The Inbox keeps what it takes to undo these itself: they wait in the queue for a moment and are dropped from it.
        case .markThreadRead, .archiveThread, .unsubscribeThread:
            return []

        // Taking an issue off a project keeps its own undo, for the moment before the card's values are gone.
        case .createIssue, .addComment, .deleteItem, .addToProject, .setProjectMembership:
            return nil
        }
    }

    /// Whether what this change is about is still there. An issue deleted since can't be changed back.
    func canStillApply(_ db: Database) throws -> Bool {
        func hasItem(_ id: String) throws -> Bool { try Item.exists(db, key: id) }
        func hasIssue(_ id: String) throws -> Bool {
            try Bool.fetchOne(
                db,
                sql: """
                SELECT EXISTS (SELECT 1 FROM item WHERE contentId = ?1)
                    OR EXISTS (SELECT 1 FROM subIssue WHERE id = ?1)
                    OR EXISTS (SELECT 1 FROM linkedIssue WHERE id = ?1)
                    OR EXISTS (SELECT 1 FROM inboxEntry WHERE contentId = ?1)
                """,
                arguments: [id]
            ) ?? false
        }
        switch self {
        case .move(let m):
            guard try hasItem(m.itemId) else { return false }
            return try m.afterItemId.map(hasItem) ?? true
        case .setParent(let m):
            guard try hasIssue(m.child.contentId) else { return false }
            return try m.parentId.map(hasIssue) ?? true
        case .setBlocking(let m):
            return try hasIssue(m.blocked.contentId) && hasIssue(m.blocker.contentId)
        case .updateMilestone(let m):
            return try Milestone.exists(db, key: m.milestoneId)
        default:
            if let contentId { return try hasIssue(contentId) }
            if let itemId { return try hasItem(itemId) }
            return true
        }
    }

    /// What Undo and Redo call this change in the Edit menu.
    var undoName: LocalizedStringResource? {
        switch self {
        case .setField(let m): m.kind == .status ? .actionChangeStatus : .actionChangePriority
        case .setDate: .actionChangeDueDate
        case .setProjectField(let m): .actionChangeField(field: m.fieldName)
        case .move: .actionMoveIssue
        case .setTitle: .actionEditTitle
        case .setBody: .actionEditDescription
        case .setState(let m): m.closed ? .actionCloseIssue : .actionReopenIssue
        case .editAssignees: .actionChangeAssignees
        case .editLabels: .actionChangeLabels
        case .setParent: .actionChangeParent
        case .setBlocking: .actionChangeBlockers
        case .setMilestone: .actionChangeMilestone
        case .updateMilestone: .editMilestone
        case .setEpic: .actionChangeEpic
        case .setIssueType: .actionChangeIssueType
        default: nil
        }
    }

    /// A column of an issue, from wherever the app knows the issue: a card, a sub-issue, a linked issue or the Inbox.
    private static func issueText(_ column: String, contentId: String, _ db: Database) throws -> String? {
        // A pull request's state says more than open or closed, and only an issue's is ever changed.
        let onlyIssues = column == "state" || column == "stateReason"
        let queries = [
            onlyIssues
                ? "SELECT \(column) FROM item WHERE contentId = ? AND kind = 'ISSUE' LIMIT 1"
                : "SELECT \(column) FROM item WHERE contentId = ? LIMIT 1",
            "SELECT \(column) FROM subIssue WHERE id = ? LIMIT 1",
            "SELECT \(column) FROM linkedIssue WHERE id = ? LIMIT 1",
            "SELECT \(column) FROM inboxEntry WHERE contentId = ? LIMIT 1",
        ]
        for sql in queries {
            guard let row = try Row.fetchOne(db, sql: sql, arguments: [contentId]) else { continue }
            return row[column]
        }
        return nil
    }

    /// What a field's option or iteration is called, for the list of queued changes.
    private static func valueName(_ value: FieldValue, fieldId: String, _ db: Database) throws -> String? {
        guard let field = try ProjectField.fetchOne(db, key: fieldId) else { return nil }
        if let id = value.iterationId { return field.iterations.first { $0.id == id }?.title }
        if let id = value.optionId { return field.options.first { $0.id == id }?.name }
        return nil
    }
}

extension Outbox {
    /// Queues changes one after the other and returns what takes all of them back, last change first; nil when one of
    /// them can't be taken back.
    static func enqueueReversibly(_ db: Database, _ mutations: [Mutation]) throws -> [Mutation]? {
        var reversal: [Mutation]? = []
        for mutation in mutations {
            if let back = try mutation.reversal(db) {
                reversal = reversal.map { back + $0 }
            } else {
                reversal = nil
            }
            try enqueue(db, mutation)
        }
        return reversal
    }
}
