import Foundation
import GRDB

/// One user intent, small enough that independent changes by different people never overwrite each other.
/// Each mutation can be applied to the local database any number of times with the same result, which is
/// what lets pending changes be re-applied on top of fresh data from GitHub.
public enum Mutation: Codable, Sendable, Equatable {
    case setField(SetField)
    case move(Move)
    case setTitle(SetText)
    case setBody(SetText)
    case setState(SetState)
    case editAssignees(EditAssignees)
    case editLabels(EditLabels)
    case addComment(AddComment)
    case createIssue(CreateIssue)
    case deleteItem(DeleteItem)
    case addToProject(AddToProject)

    public struct SetField: Codable, Sendable, Equatable {
        public var itemId: String
        public var projectId: String
        public var fieldId: String
        public var kind: OptionKind
        public var optionId: String?
        /// The value shown before the first of the still-unsent changes to this field.
        public var base: String?
    }

    public struct Move: Codable, Sendable, Equatable {
        public var itemId: String
        public var projectId: String
        /// The card this one should sit directly below in the project's order; nil means first.
        public var afterItemId: String?
    }

    public struct SetText: Codable, Sendable, Equatable {
        public var itemId: String
        public var contentId: String
        public var value: String
        public var base: String
        /// Set when GitHub's text changed too and the two versions could not be merged.
        public var theirs: String?
    }

    public struct SetState: Codable, Sendable, Equatable {
        public var contentId: String
        public var closed: Bool
        /// COMPLETED or NOT_PLANNED when closing.
        public var reason: String?
    }

    public struct EditAssignees: Codable, Sendable, Equatable {
        public var contentId: String
        public var add: [Person]
        public var remove: [Person]
    }

    public struct EditLabels: Codable, Sendable, Equatable {
        public var contentId: String
        public var add: [LabelRef]
        public var remove: [LabelRef]
    }

    public struct AddComment: Codable, Sendable, Equatable {
        public var commentId: String
        public var contentId: String
        public var body: String
        public var author: Person
        public var createdAt: Date
    }

    public struct DeleteItem: Codable, Sendable, Equatable {
        public var itemId: String
        /// Nil for an issue on none of your boards.
        public var projectId: String?
        /// The issue behind the card; nil for a draft.
        public var contentId: String?
        public var isDraft: Bool
        /// "#12 Title", for messages.
        public var label: String
    }

    public struct CreateIssue: Codable, Sendable, Equatable {
        public var itemId: String
        public var contentId: String
        /// The board the new issue goes on; nil creates it in the repository only.
        public var projectId: String?
        public var repoId: String
        public var repo: String
        public var title: String
        public var body: String
        public var statusFieldId: String?
        public var statusId: String?
        public var priorityFieldId: String?
        public var priorityId: String?
        public var assignees: [Person]
        public var labels: [LabelRef]
        public var parentContentId: String?
        public var parentNumber: Int?
        public var parentTitle: String?
        public var author: String?
        public var createdAt: Date
        /// Filled in once GitHub has created the issue, so a retry never creates it twice.
        public var createdContentId: String?
        public var createdNumber: Int?
        public var createdUrl: String?
    }

    /// Puts an issue that is on none of your boards onto one, in a column.
    public struct AddToProject: Codable, Sendable, Equatable {
        /// The issue's id while it is on no board; it becomes the project item's id once GitHub has added it.
        public var itemId: String
        public var contentId: String
        public var projectId: String
        public var statusFieldId: String?
        public var statusId: String?
    }
}

// MARK: - Identity

extension Mutation {
    /// Two unsent mutations with the same key are folded into one.
    var coalesceKey: String? {
        switch self {
        case .setField(let m): "field:\(m.itemId):\(m.fieldId)"
        case .move(let m): "move:\(m.itemId)"
        case .setTitle(let m): "title:\(m.contentId)"
        case .setBody(let m): "body:\(m.contentId)"
        case .setState(let m): "state:\(m.contentId)"
        case .deleteItem(let m): "delete:\(m.itemId)"
        case .addToProject(let m): "add:\(m.itemId)"
        default: nil
        }
    }

    /// Every id this mutation refers to, used to wait for (or give up on) issues not yet created.
    var referencedIds: [String] {
        switch self {
        case .setField(let m): [m.itemId]
        case .move(let m): [m.itemId] + (m.afterItemId.map { [$0] } ?? [])
        case .setTitle(let m), .setBody(let m): [m.itemId, m.contentId]
        case .setState(let m): [m.contentId]
        case .editAssignees(let m): [m.contentId]
        case .editLabels(let m): [m.contentId]
        case .addComment(let m): [m.contentId]
        case .createIssue(let m): m.parentContentId.map { [$0] } ?? []
        // An issue is deleted by its own id; only a draft needs the project item.
        case .deleteItem(let m): m.isDraft ? [m.itemId] : (m.contentId.map { [$0] } ?? [m.itemId])
        case .addToProject(let m): [m.contentId]
        }
    }

    /// The project item this mutation is about, if it is about exactly one.
    var itemId: String? {
        switch self {
        case .setField(let m): m.itemId
        case .move(let m): m.itemId
        case .setTitle(let m), .setBody(let m): m.itemId
        case .createIssue(let m): m.itemId
        case .deleteItem(let m): m.itemId
        case .addToProject(let m): m.itemId
        default: nil
        }
    }

    var contentId: String? {
        switch self {
        case .setTitle(let m), .setBody(let m): m.contentId
        case .setState(let m): m.contentId
        case .editAssignees(let m): m.contentId
        case .editLabels(let m): m.contentId
        case .addComment(let m): m.contentId
        case .createIssue(let m): m.contentId
        case .deleteItem(let m): m.contentId
        case .addToProject(let m): m.contentId
        default: nil
        }
    }

    /// Rewrites temporary local ids once GitHub has assigned real ones.
    func remapping(_ ids: [String: String]) -> Mutation {
        guard !ids.isEmpty else { return self }
        func r(_ id: String) -> String { ids[id] ?? id }
        func r(_ id: String?) -> String? { id.map { ids[$0] ?? $0 } }
        switch self {
        case .setField(var m):
            m.itemId = r(m.itemId)
            return .setField(m)
        case .move(var m):
            m.itemId = r(m.itemId)
            m.afterItemId = r(m.afterItemId)
            return .move(m)
        case .setTitle(var m):
            m.itemId = r(m.itemId)
            m.contentId = r(m.contentId)
            return .setTitle(m)
        case .setBody(var m):
            m.itemId = r(m.itemId)
            m.contentId = r(m.contentId)
            return .setBody(m)
        case .setState(var m):
            m.contentId = r(m.contentId)
            return .setState(m)
        case .editAssignees(var m):
            m.contentId = r(m.contentId)
            return .editAssignees(m)
        case .editLabels(var m):
            m.contentId = r(m.contentId)
            return .editLabels(m)
        case .addComment(var m):
            m.contentId = r(m.contentId)
            m.commentId = r(m.commentId)
            return .addComment(m)
        case .createIssue(var m):
            m.itemId = r(m.itemId)
            m.contentId = r(m.contentId)
            m.parentContentId = r(m.parentContentId)
            return .createIssue(m)
        case .deleteItem(var m):
            m.itemId = r(m.itemId)
            m.contentId = r(m.contentId)
            return .deleteItem(m)
        case .addToProject(var m):
            m.itemId = r(m.itemId)
            m.contentId = r(m.contentId)
            return .addToProject(m)
        }
    }
}

// MARK: - Local effect

extension Mutation {
    /// Writes this mutation's effect into the local database. Idempotent.
    func applyLocally(_ db: Database) throws {
        switch self {
        case .setField(let m):
            let column = m.kind == .status ? "statusId" : "priorityId"
            try db.execute(sql: "UPDATE item SET \(column) = ?, dirty = 1 WHERE id = ?", arguments: [m.optionId, m.itemId])

        case .move(let m):
            guard let projectId = try String.fetchOne(db, sql: "SELECT projectId FROM item WHERE id = ?", arguments: [m.itemId]) else { return }
            let position: Double
            if let afterId = m.afterItemId {
                guard let after = try Double.fetchOne(db, sql: "SELECT position FROM item WHERE id = ?", arguments: [afterId]) else { return }
                let next = try Double.fetchOne(
                    db,
                    sql: "SELECT MIN(position) FROM item WHERE projectId = ? AND position > ? AND id != ?",
                    arguments: [projectId, after, m.itemId]
                )
                position = next.map { (after + $0) / 2 } ?? after + 1024
            } else {
                let first = try Double.fetchOne(
                    db,
                    sql: "SELECT MIN(position) FROM item WHERE projectId = ? AND id != ?",
                    arguments: [projectId, m.itemId]
                )
                position = (first ?? 1024) - 1024
            }
            try db.execute(sql: "UPDATE item SET position = ? WHERE id = ?", arguments: [position, m.itemId])

        case .setTitle(let m):
            try db.execute(sql: "UPDATE item SET title = ?, dirty = 1 WHERE contentId = ?", arguments: [m.value, m.contentId])
            try db.execute(sql: "UPDATE subIssue SET title = ? WHERE id = ?", arguments: [m.value, m.contentId])

        case .setBody(let m):
            try db.execute(sql: "UPDATE item SET body = ?, dirty = 1 WHERE contentId = ?", arguments: [m.value, m.contentId])

        case .setState(let m):
            let state = m.closed ? "CLOSED" : "OPEN"
            try db.execute(
                sql: "UPDATE item SET state = ?, stateReason = ?, dirty = 1 WHERE contentId = ? AND kind = 'ISSUE'",
                arguments: [state, m.closed ? m.reason : nil, m.contentId]
            )
            try db.execute(
                sql: "UPDATE subIssue SET state = ?, stateReason = ? WHERE id = ?",
                arguments: [state, m.closed ? m.reason : nil, m.contentId]
            )

        case .editAssignees(let m):
            for var item in try Item.filter(Column("contentId") == m.contentId).fetchAll(db) {
                let removed = Set(m.remove.map(\.id))
                var people = item.assignees.filter { !removed.contains($0.id) }
                for person in m.add where !people.contains(where: { $0.id == person.id }) {
                    people.append(person)
                }
                item.assignees = people
                item.dirty = true
                try item.update(db)
            }

        case .editLabels(let m):
            for var item in try Item.filter(Column("contentId") == m.contentId).fetchAll(db) {
                let removed = Set(m.remove.map(\.id))
                var labels = item.labels.filter { !removed.contains($0.id) }
                for label in m.add where !labels.contains(where: { $0.id == label.id }) {
                    labels.append(label)
                }
                item.labels = labels.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                item.dirty = true
                try item.update(db)
            }

        case .addComment(let m):
            guard try !Comment.exists(db, key: m.commentId) else { return }
            try Comment(
                id: m.commentId, issueId: m.contentId, authorLogin: m.author.login,
                authorAvatarUrl: m.author.avatarUrl, body: m.body, createdAt: m.createdAt
            ).insert(db)

        case .deleteItem(let m):
            try Item.deleteOne(db, key: m.itemId)
            if let contentId = m.contentId {
                try db.execute(sql: "DELETE FROM item WHERE contentId = ? AND projectId IS ?", arguments: [contentId, m.projectId])
                try db.execute(sql: "DELETE FROM subIssue WHERE id = ?", arguments: [contentId])
                try db.execute(sql: "DELETE FROM comment WHERE issueId = ?", arguments: [contentId])
            }

        case .createIssue(let m):
            guard try !Item.exists(db, key: m.itemId) else { return }
            let position: Double
            if let projectId = m.projectId {
                let last = try Double.fetchOne(db, sql: "SELECT MAX(position) FROM item WHERE projectId = ?", arguments: [projectId])
                position = (last ?? 0) + 1024
            } else {
                position = Item.positionWithoutProject(updatedAt: m.createdAt)
            }
            try Item(
                id: m.itemId,
                projectId: m.projectId,
                kind: .issue,
                position: position,
                remoteUpdatedAt: nil,
                dirty: true,
                statusId: m.statusId,
                priorityId: m.priorityId,
                contentId: m.contentId,
                number: m.createdNumber,
                title: m.title,
                body: m.body,
                state: "OPEN",
                url: m.createdUrl,
                repoId: m.repoId,
                repo: m.repo,
                authorLogin: m.author,
                createdAt: m.createdAt,
                updatedAt: m.createdAt,
                parentId: m.parentContentId,
                parentNumber: m.parentNumber,
                parentTitle: m.parentTitle,
                assignees: m.assignees,
                labels: m.labels
            ).insert(db)
            if let parentId = m.parentContentId, try !SubIssue.exists(db, key: ["parentId": parentId, "id": m.contentId]) {
                let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM subIssue WHERE parentId = ?", arguments: [parentId]) ?? 0
                try SubIssue(
                    id: m.contentId, parentId: parentId, number: m.createdNumber ?? 0, title: m.title, state: "OPEN",
                    repo: m.repo, url: m.createdUrl, position: count, assignees: m.assignees
                ).insert(db)
            }

        case .addToProject(let m):
            // The issue joins the end of the board once; applying this again leaves its place alone.
            let last = try Double.fetchOne(db, sql: "SELECT MAX(position) FROM item WHERE projectId = ?", arguments: [m.projectId])
            try db.execute(
                sql: "UPDATE item SET projectId = ?, position = ?, priorityId = NULL WHERE id = ? AND projectId IS NULL",
                arguments: [m.projectId, (last ?? 0) + 1024, m.itemId]
            )
            try db.execute(sql: "UPDATE item SET statusId = ?, dirty = 1 WHERE id = ?", arguments: [m.statusId, m.itemId])
        }
    }

    /// One line for the "queued changes" list, e.g. "Status changed to In Progress".
    func summary(_ db: Database) throws -> (number: String, text: String) {
        func number(itemId: String? = nil, contentId: String? = nil) throws -> String {
            let value: Int?
            if let itemId {
                value = try Int.fetchOne(db, sql: "SELECT number FROM item WHERE id = ?", arguments: [itemId])
            } else if let contentId {
                value = try Int.fetchOne(db, sql: "SELECT number FROM item WHERE contentId = ?", arguments: [contentId])
                    ?? Int.fetchOne(db, sql: "SELECT number FROM subIssue WHERE id = ?", arguments: [contentId])
            } else {
                value = nil
            }
            return value.map { "#\($0)" } ?? "New"
        }
        switch self {
        case .setField(let m):
            let name = try m.optionId.flatMap {
                try String.fetchOne(db, sql: "SELECT name FROM fieldOption WHERE fieldId = ? AND id = ?", arguments: [m.fieldId, $0])
            }
            let field = m.kind == .status ? "Status" : "Priority"
            return (try number(itemId: m.itemId), name.map { "\(field) changed to \($0)" } ?? "\(field) cleared")
        case .move(let m): return (try number(itemId: m.itemId), "Moved")
        case .setTitle(let m): return (try number(contentId: m.contentId), "Title edited")
        case .setBody(let m): return (try number(contentId: m.contentId), "Description edited")
        case .setState(let m): return (try number(contentId: m.contentId), m.closed ? "Closed" : "Reopened")
        case .editAssignees(let m): return (try number(contentId: m.contentId), "Assignees changed")
        case .editLabels(let m): return (try number(contentId: m.contentId), "Labels changed")
        case .addComment(let m): return (try number(contentId: m.contentId), "Comment added")
        case .createIssue(let m): return ("New", "Issue created: \(m.title)")
        case .deleteItem(let m): return (m.label.components(separatedBy: " ").first ?? "", "Deleted")
        case .addToProject(let m):
            let project = try String.fetchOne(db, sql: "SELECT title FROM project WHERE id = ?", arguments: [m.projectId])
            return (try number(contentId: m.contentId), "Added to \(project ?? "a project")")
        }
    }
}

// MARK: - Outbox

public enum OutboxState: String, Codable, Sendable {
    /// Waiting to be sent.
    case pending
    /// Sent; kept briefly so a stale read from GitHub cannot undo it on screen.
    case sent
    /// A text edit that clashes with a newer edit on GitHub and needs the user's decision.
    case conflict
}

public struct OutboxEntry: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    public static let databaseTableName = "outbox"

    public var id: Int64?
    public var createdAt: Date
    public var state: OutboxState
    public var mutation: Mutation
    public var sentAt: Date?
    public var attempts: Int = 0
    public var lastError: String?

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public enum Outbox {
    /// How long a sent mutation keeps being re-applied over data read from GitHub.
    static let graceInterval: TimeInterval = 20

    /// Entries whose effect should currently be visible, oldest first.
    static func active(_ db: Database) throws -> [OutboxEntry] {
        try OutboxEntry.order(Column("id")).fetchAll(db)
    }

    /// Records a mutation and applies it locally, folding it into an unsent one for the same field if there is one.
    public static func enqueue(_ db: Database, _ mutation: Mutation) throws {
        if case .deleteItem(let deletion) = mutation {
            try enqueueDeletion(db, deletion)
            return
        }
        var mutation = mutation
        if let key = mutation.coalesceKey {
            let previous = try OutboxEntry
                .filter([OutboxState.pending.rawValue, OutboxState.conflict.rawValue].contains(Column("state")))
                .fetchAll(db)
                .filter { $0.mutation.coalesceKey == key }
            for entry in previous {
                mutation = mutation.inheritingBase(from: entry.mutation)
                try entry.delete(db)
            }
        }
        try mutation.applyLocally(db)
        var entry = OutboxEntry(createdAt: Date(), state: .pending, mutation: mutation)
        try entry.insert(db)
    }

    /// Other changes to a deleted card are pointless, so they are dropped, sent or not (a sent one would
    /// otherwise be re-applied for a while and bring the card back). A card that never reached GitHub is
    /// simply forgotten.
    private static func enqueueDeletion(_ db: Database, _ deletion: Mutation.DeleteItem) throws {
        var deletion = deletion
        var neverCreated = false
        for entry in try active(db) {
            let mutation = entry.mutation
            let related = mutation.itemId == deletion.itemId
                || (deletion.contentId != nil && mutation.contentId == deletion.contentId)
            guard related else { continue }
            if case .createIssue(let create) = mutation {
                if let created = create.createdContentId {
                    deletion.contentId = created
                } else {
                    neverCreated = true
                }
            }
            try entry.delete(db)
        }
        let mutation = Mutation.deleteItem(deletion)
        try mutation.applyLocally(db)
        guard !neverCreated else { return }
        var entry = OutboxEntry(createdAt: Date(), state: .pending, mutation: mutation)
        try entry.insert(db)
    }

    /// Re-applies everything still in the outbox, after remote data was written.
    static func rebase(_ db: Database) throws {
        for entry in try active(db) {
            try entry.mutation.applyLocally(db)
        }
    }

    /// Settles a text edit that clashed with a newer edit on GitHub.
    public static func resolveConflict(_ db: Database, entryId: Int64, keepMine: Bool) throws {
        guard var entry = try OutboxEntry.fetchOne(db, key: entryId), entry.state == .conflict else { return }
        func settle(_ m: Mutation.SetText, column: String, rebuild: (Mutation.SetText) -> Mutation) throws {
            if keepMine {
                var kept = m
                kept.base = m.theirs ?? m.base
                kept.theirs = nil
                entry.mutation = rebuild(kept)
                entry.state = .pending
                try entry.update(db)
            } else {
                try entry.delete(db)
                if let theirs = m.theirs {
                    try db.execute(sql: "UPDATE item SET \(column) = ? WHERE contentId = ?", arguments: [theirs, m.contentId])
                }
            }
        }
        switch entry.mutation {
        case .setTitle(let m): try settle(m, column: "title") { .setTitle($0) }
        case .setBody(let m): try settle(m, column: "body") { .setBody($0) }
        default: break
        }
    }

    static func purgeSent(_ db: Database, now: Date = Date()) throws {
        try db.execute(
            sql: "DELETE FROM outbox WHERE state = ? AND sentAt < ?",
            arguments: [OutboxState.sent.rawValue, now.addingTimeInterval(-graceInterval)]
        )
    }

    /// Clears the dirty flag on cards that no outbox entry refers to any more. A nil project means the issues
    /// that are on none of your boards.
    static func clearSettledDirtyFlags(_ db: Database, projectId: String?) throws {
        let entries = try active(db)
        let itemIds = Set(entries.compactMap(\.mutation.itemId))
        let contentIds = Set(entries.compactMap(\.mutation.contentId))
        for item in try Item.filter(Column("projectId") == projectId && Column("dirty") == true).fetchAll(db) {
            if itemIds.contains(item.id) { continue }
            if let contentId = item.contentId, contentIds.contains(contentId) { continue }
            try db.execute(sql: "UPDATE item SET dirty = 0 WHERE id = ?", arguments: [item.id])
        }
    }
}

extension Mutation {
    /// When folding a newer change into an unsent older one, the older one's base is the true base.
    func inheritingBase(from older: Mutation) -> Mutation {
        switch (self, older) {
        case (.setField(var new), .setField(let old)):
            new.base = old.base
            return .setField(new)
        case (.setTitle(var new), .setTitle(let old)):
            new.base = old.theirs ?? old.base
            return .setTitle(new)
        case (.setBody(var new), .setBody(let old)):
            new.base = old.theirs ?? old.base
            return .setBody(new)
        default:
            return self
        }
    }
}
