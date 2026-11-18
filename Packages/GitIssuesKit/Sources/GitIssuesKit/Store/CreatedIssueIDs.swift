import GRDB

/// Editors and async writes may still hold a local issue ID after creation sync has finished.
/// Keep that one-way mapping in the same transaction as the remap, even after the outbox row is purged.
enum CreatedIssueIDs {
    private static let prefix = "createdIssueID."

    static func record(_ db: Database, localId: String, serverId: String) throws {
        guard localId.hasPrefix(LocalID.prefix), localId != serverId else { return }
        try KV.set(db, prefix + localId, serverId)
    }

    static func resolve(_ db: Database, _ contentId: String) throws -> String {
        guard contentId.hasPrefix(LocalID.prefix) else { return contentId }
        return try KV.string(db, prefix + contentId) ?? contentId
    }

    static func all(_ db: Database) throws -> [String: String] {
        let rows = try Row.fetchAll(db, sql: "SELECT key, value FROM kv WHERE key LIKE ?", arguments: [prefix + "%"])
        return Dictionary(uniqueKeysWithValues: rows.map { row in
            let key: String = row["key"]
            return (String(key.dropFirst(prefix.count)), row["value"] as String)
        })
    }
}
