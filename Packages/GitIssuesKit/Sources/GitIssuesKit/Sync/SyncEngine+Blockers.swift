import Foundation
import GRDB

/// A blocked issue's card names the issue that blocks it. GitHub counts an issue's open blockers with the card but
/// doesn't say which they are, so they are read on their own, in one go for every blocked issue whose blockers
/// this device doesn't know yet or that was read again since.
extension SyncEngine {
    func readBlockers() async throws {
        guard !isDemo else { return }
        // Each blocked issue once, with how many open blockers GitHub counts and how many of them are known here.
        let blocked = try await db.reader.read { db in
            try Row.fetchAll(db, sql: """
                SELECT contentId, MAX(blockedByCount) AS count,
                  (SELECT COUNT(*) FROM linkedIssue l WHERE l.issueId = item.contentId AND l.relation = 'blockedBy' AND l.state = 'OPEN') AS known
                FROM item
                WHERE kind = ? AND contentId IS NOT NULL AND contentId NOT LIKE ? AND blockedByCount > 0
                GROUP BY contentId
                """, arguments: [ItemKind.issue.rawValue, LocalID.prefix + "%"])
            .map { row -> (contentId: String, count: Int, known: Int) in (row["contentId"], row["count"], row["known"]) }
        }
        var counts: [String: Int] = [:]
        var wanted: [String] = []
        for (contentId, count, known) in blocked {
            counts[contentId] = count
            let missing = known != count && blockersRead[contentId] != count
            if missing || blockersDue.contains(contentId) { wanted.append(contentId) }
        }
        blockersDue = blockersDue.intersection(counts.keys)
        guard !wanted.isEmpty else { return }
        let read = try await api.blockers(of: wanted)
        try await db.writer.write { db in
            let changing = try Self.blockersChangingHere(db)
            for (contentId, links) in read where !changing.contains(contentId) {
                try Self.replaceBlockers(of: contentId, with: links, db)
            }
        }
        for contentId in wanted {
            blockersRead[contentId] = counts[contentId]
            blockersDue.remove(contentId)
        }
    }

    /// Issues with a blocker set or taken away here that GitHub may not have yet. Their blockers as read from GitHub
    /// would undo that, so they keep their own until it has.
    static func blockersChangingHere(_ db: Database) throws -> Set<String> {
        Set(try Outbox.active(db).compactMap { entry in
            if case .setBlocking(let m) = entry.mutation { return m.blocked.contentId }
            return nil
        })
    }

    /// Lists `links` as what blocks `contentId`, in place of what was listed before.
    static func replaceBlockers(of contentId: String, with links: [LinkedIssue], _ db: Database) throws {
        try db.execute(
            sql: "DELETE FROM linkedIssue WHERE issueId = ? AND relation = ? AND id NOT LIKE ?",
            arguments: [contentId, LinkedIssue.Relation.blockedBy.rawValue, LocalID.prefix + "%"]
        )
        for link in links { try link.save(db) }
    }
}
