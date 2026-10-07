import Foundation
import GRDB

// The local effect of changing an issue's parent or what blocks it. GitHub counts a parent's sub-issues and an
// issue's open blockers on the issues themselves; the counts here follow along, so cards change at once. An issue
// is counted only while it is listed, so applying a change again leaves the counts alone.

extension Mutation.SetParent {
    func apply(_ db: Database) throws {
        let id = child.contentId
        let state = try String.fetchOne(db, sql: "SELECT state FROM item WHERE contentId = ? LIMIT 1", arguments: [id]) ?? child.state
        let done = state == "OPEN" ? 0 : 1
        // Where the issue counts now: the lists of sub-issues it is in, and the parent its card names.
        var current = try String.fetchSet(db, sql: "SELECT parentId FROM subIssue WHERE id = ?", arguments: [id])
        current.formUnion(try String.fetchAll(db, sql: "SELECT parentId FROM item WHERE contentId = ? AND parentId IS NOT NULL", arguments: [id]))
        for old in current where old != parentId {
            try db.execute(sql: "DELETE FROM subIssue WHERE parentId = ? AND id = ?", arguments: [old, id])
            try db.execute(
                sql: "UPDATE item SET subTotal = MAX(subTotal - 1, 0), subCompleted = MAX(subCompleted - ?, 0) WHERE contentId = ?",
                arguments: [done, old]
            )
        }
        if let parentId {
            if !current.contains(parentId) {
                try db.execute(
                    sql: "UPDATE item SET subTotal = subTotal + 1, subCompleted = subCompleted + ? WHERE contentId = ?",
                    arguments: [done, parentId]
                )
            }
            if try !SubIssue.exists(db, key: ["parentId": parentId, "id": id]) {
                let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM subIssue WHERE parentId = ?", arguments: [parentId]) ?? 0
                try SubIssue(
                    id: id, parentId: parentId, number: child.number ?? 0, title: child.title, state: state,
                    stateReason: child.stateReason, repo: child.repo, url: child.url, position: count, assignees: child.assignees
                ).insert(db)
            }
        }
        try db.execute(
            sql: "UPDATE item SET parentId = ?, parentNumber = ?, parentTitle = ?, dirty = 1 WHERE contentId = ?",
            arguments: [parentId, parentNumber, parentTitle, id]
        )
    }
}

extension Mutation.SetBlocking {
    func apply(_ db: Database) throws {
        try list(blocker, under: blocked, as: .blockedBy, count: "blockedByCount", db)
        try list(blocked, under: blocker, as: .blocking, count: "blockingCount", db)
    }

    /// Lists `other` among `issue`'s relations, or takes it out. The count is of open issues, as GitHub's is.
    private func list(_ other: IssueSummary, under issue: IssueSummary, as relation: LinkedIssue.Relation, count column: String, _ db: Database) throws {
        let key: [String: (any DatabaseValueConvertible)?] = ["issueId": issue.contentId, "relation": relation.rawValue, "id": other.contentId]
        let listed = try LinkedIssue.fetchOne(db, key: key)
        if isBlocked, listed == nil {
            let state = try String.fetchOne(db, sql: "SELECT state FROM item WHERE contentId = ? LIMIT 1", arguments: [other.contentId]) ?? other.state
            let position = try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM linkedIssue WHERE issueId = ? AND relation = ?", arguments: [issue.contentId, relation.rawValue]
            ) ?? 0
            try LinkedIssue(
                id: other.contentId, issueId: issue.contentId, relation: relation, number: other.number ?? 0, title: other.title,
                state: state, stateReason: other.stateReason, repo: other.repo, url: other.url, position: position
            ).insert(db)
            try db.execute(
                sql: "UPDATE item SET \(column) = \(column) + ?, dirty = 1 WHERE contentId = ?",
                arguments: [state == "OPEN" ? 1 : 0, issue.contentId]
            )
        } else if !isBlocked, let listed {
            try listed.delete(db)
            try db.execute(
                sql: "UPDATE item SET \(column) = MAX(\(column) - ?, 0), dirty = 1 WHERE contentId = ?",
                arguments: [listed.isClosed ? 0 : 1, issue.contentId]
            )
        }
    }
}
