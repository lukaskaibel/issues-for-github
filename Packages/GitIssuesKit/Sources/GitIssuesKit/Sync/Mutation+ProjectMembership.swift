import Foundation
import GRDB

extension Mutation {
    /// Changes one board membership, leaving the underlying issue and its other memberships intact.
    public struct ProjectMembership: Codable, Sendable, Equatable {
        public var item: Item
        public var isMember: Bool
        public var base: Bool

        func apply(_ db: Database) throws {
            guard let contentId = item.contentId, let projectId = item.projectId, item.kind != .draft else { return }
            if isMember {
                if try !Item.exists(db, key: item.id) {
                    var copy = try Item.filter(Column("contentId") == contentId).fetchOne(db) ?? item
                    copy.id = item.id
                    copy.projectId = projectId
                    copy.statusId = item.statusId
                    copy.priorityId = item.priorityId
                    copy.dueDate = item.dueDate
                    copy.fieldValues = item.fieldValues
                    let last = try Double.fetchOne(db, sql: "SELECT MAX(position) FROM item WHERE projectId = ?", arguments: [projectId]) ?? 0
                    copy.position = last + 1024
                    copy.dirty = true
                    try copy.insert(db)
                }
                // Restoring a membership restores its deferred edits, even if they precede this entry in the queue.
                for entry in try Outbox.active(db) where entry.mutation.isProjectItemEdit && entry.mutation.itemId == item.id {
                    try entry.mutation.applyLocally(db)
                }
                try db.execute(sql: "DELETE FROM item WHERE contentId = ? AND projectId IS NULL", arguments: [contentId])
            } else {
                let latest = try Item.fetchOne(db, key: item.id)
                    ?? Item.filter(Column("contentId") == contentId).fetchOne(db) ?? item
                try Item.deleteOne(db, key: item.id)
                // Retain an ordinary issue when its last open project is removed, including its conversation.
                let remaining = try Bool.fetchOne(db, sql: """
                    SELECT EXISTS(SELECT 1 FROM item JOIN project ON project.id = item.projectId
                    WHERE item.contentId = ? AND project.closed = 0)
                    """, arguments: [contentId]) ?? false
                if !remaining, try !Item.exists(db, key: Item.idWithoutProject(contentId)) {
                    var loose = latest
                    loose.id = Item.idWithoutProject(contentId)
                    loose.projectId = nil
                    loose.statusId = nil
                    loose.priorityId = nil
                    loose.dueDate = nil
                    loose.fieldValues = [:]
                    loose.dirty = false
                    loose.remoteUpdatedAt = nil
                    loose.position = Item.positionWithoutProject(updatedAt: loose.updatedAt)
                    try loose.insert(db)
                }
            }
        }
    }

    var isProjectItemEdit: Bool {
        switch self {
        case .setField, .setDate, .setProjectField, .move: true
        default: false
        }
    }
}

extension Outbox {
    /// Hold a membership's field writes until a removal succeeds, is cancelled, or fails.
    static func isWaitingForProjectRemoval(_ entry: OutboxEntry, among entries: [OutboxEntry]) -> Bool {
        guard entry.mutation.isProjectItemEdit, let id = entry.mutation.itemId else { return false }
        return entries.last { candidate in
            if case .setProjectMembership(let membership) = candidate.mutation { return membership.item.id == id }
            return false
        }.map { entry in
            if case .setProjectMembership(let membership) = entry.mutation { return !membership.isMember }
            return false
        } ?? false
    }
}
