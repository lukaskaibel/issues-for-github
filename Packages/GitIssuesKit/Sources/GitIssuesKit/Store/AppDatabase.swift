import Foundation
import GRDB

/// The local SQLite database. The UI reads only from here; the sync engine and user actions write to it.
public final class AppDatabase: Sendable {
    public let writer: any DatabaseWriter

    public init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    public static func onDisk() throws -> AppDatabase {
        let folder = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            // One database per bundle identifier, so a development build never shares data with the released app.
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "GitIssues", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try onDisk(at: folder.appendingPathComponent("db.sqlite"))
    }

    public static func onDisk(at url: URL) throws -> AppDatabase {
        try AppDatabase(DatabasePool(path: url.path))
    }

    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }

    public var reader: any DatabaseReader { writer }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1") { db in
            try db.create(table: "project") { t in
                t.primaryKey("id", .text)
                t.column("ownerLogin", .text).notNull()
                t.column("ownerIsOrg", .boolean).notNull()
                t.column("number", .integer).notNull()
                t.column("title", .text).notNull()
                t.column("url", .text).notNull()
                t.column("closed", .boolean).notNull()
                t.column("viewerCanUpdate", .boolean).notNull()
                t.column("remoteUpdatedAt", .text)
                t.column("itemsTotal", .integer)
                t.column("statusFieldId", .text)
                t.column("priorityFieldId", .text)
                t.column("lastSyncedAt", .datetime)
            }

            try db.create(table: "fieldOption") { t in
                t.column("id", .text).notNull()
                t.column("fieldId", .text).notNull()
                t.column("projectId", .text).notNull().indexed()
                    .references("project", onDelete: .cascade)
                t.column("kind", .text).notNull()
                t.column("name", .text).notNull()
                t.column("color", .text).notNull()
                t.column("descr", .text).notNull()
                t.column("position", .integer).notNull()
                t.primaryKey(["fieldId", "id"])
            }

            try db.create(table: "item") { t in
                t.primaryKey("id", .text)
                t.column("projectId", .text).notNull().indexed()
                    .references("project", onDelete: .cascade)
                t.column("kind", .text).notNull()
                t.column("position", .double).notNull()
                t.column("remoteUpdatedAt", .text)
                t.column("dirty", .boolean).notNull().defaults(to: false)
                t.column("statusId", .text)
                t.column("priorityId", .text)
                t.column("contentId", .text).indexed()
                t.column("number", .integer)
                t.column("title", .text).notNull()
                t.column("body", .text).notNull()
                t.column("state", .text).notNull()
                t.column("stateReason", .text)
                t.column("url", .text)
                t.column("repoId", .text)
                t.column("repo", .text)
                t.column("authorLogin", .text)
                t.column("createdAt", .datetime)
                t.column("updatedAt", .datetime)
                t.column("closedAt", .datetime)
                t.column("parentId", .text)
                t.column("parentNumber", .integer)
                t.column("parentTitle", .text)
                t.column("subTotal", .integer).notNull().defaults(to: 0)
                t.column("subCompleted", .integer).notNull().defaults(to: 0)
                t.column("commentCount", .integer).notNull().defaults(to: 0)
                t.column("assignees", .text).notNull()
                t.column("labels", .text).notNull()
            }

            try db.create(table: "comment") { t in
                t.primaryKey("id", .text)
                t.column("issueId", .text).notNull().indexed()
                t.column("authorLogin", .text)
                t.column("authorAvatarUrl", .text)
                t.column("body", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "subIssue") { t in
                t.column("id", .text).notNull()
                t.column("parentId", .text).notNull().indexed()
                t.column("number", .integer).notNull()
                t.column("title", .text).notNull()
                t.column("state", .text).notNull()
                t.column("stateReason", .text)
                t.column("repo", .text)
                t.column("url", .text)
                t.column("position", .integer).notNull()
                t.column("assignees", .text).notNull()
                t.primaryKey(["parentId", "id"])
            }

            try db.create(table: "repo") { t in
                t.column("id", .text).notNull()
                t.column("nameWithOwner", .text).notNull()
                t.column("projectId", .text).notNull()
                    .references("project", onDelete: .cascade)
                t.column("labels", .text).notNull()
                t.column("assignableUsers", .text).notNull()
                t.column("metaLoadedAt", .datetime)
                t.primaryKey(["projectId", "id"])
            }

            try db.create(table: "outbox") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("createdAt", .datetime).notNull()
                t.column("state", .text).notNull()
                t.column("mutation", .text).notNull()
                t.column("sentAt", .datetime)
                t.column("attempts", .integer).notNull().defaults(to: 0)
                t.column("lastError", .text)
            }

            try db.create(table: "kv") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }
        }
        migrator.registerMigration("v2") { db in
            try db.alter(table: "item") { t in
                t.add(column: "viewerCanDelete", .boolean).notNull().defaults(to: false)
            }
            // Fetch every card again once, so the new field is filled in.
            try db.execute(sql: "UPDATE item SET remoteUpdatedAt = NULL")
            try db.execute(sql: "UPDATE project SET remoteUpdatedAt = NULL")
        }
        // Named rather than numbered, so it can't clash with other branches; it stays after any migration that
        // rebuilds the item table.
        migrator.registerMigration("dueDates") { db in
            try db.alter(table: "project") { t in
                t.add(column: "dueFieldId", .text)
            }
            try db.alter(table: "item") { t in
                t.add(column: "dueDate", .text)
            }
            // Fetch every card again once, so due dates are filled in.
            try db.execute(sql: "UPDATE item SET remoteUpdatedAt = NULL")
            try db.execute(sql: "UPDATE project SET remoteUpdatedAt = NULL")
        }
        return migrator
    }
}

// MARK: - Small key-value store

public enum KV {
    public static func string(_ db: Database, _ key: String) throws -> String? {
        try String.fetchOne(db, sql: "SELECT value FROM kv WHERE key = ?", arguments: [key])
    }

    public static func set(_ db: Database, _ key: String, _ value: String?) throws {
        if let value {
            try db.execute(sql: "INSERT INTO kv (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value", arguments: [key, value])
        } else {
            try db.execute(sql: "DELETE FROM kv WHERE key = ?", arguments: [key])
        }
    }

    public static func viewer(_ db: Database) throws -> Viewer? {
        guard let json = try string(db, "viewer") else { return nil }
        return try? JSONDecoder().decode(Viewer.self, from: Data(json.utf8))
    }

    public static func setViewer(_ db: Database, _ viewer: Viewer?) throws {
        let json = try viewer.map { String(decoding: try JSONEncoder().encode($0), as: UTF8.self) }
        try set(db, "viewer", json)
    }
}

// MARK: - Read helpers

extension AppDatabase {
    public func viewer() -> Viewer? {
        try? reader.read { try KV.viewer($0) }
    }

    public func projects() throws -> [Project] {
        try reader.read { db in
            try Project.order(Column("closed"), Column("ownerLogin").collating(.localizedCaseInsensitiveCompare), Column("title").collating(.localizedCaseInsensitiveCompare)).fetchAll(db)
        }
    }

    /// Removes everything, for sign-out.
    public func wipe() throws {
        try writer.write { db in
            for table in ["outbox", "comment", "subIssue", "repo", "item", "fieldOption", "project", "kv"] {
                try db.execute(sql: "DELETE FROM \(table)")
            }
        }
    }
}
