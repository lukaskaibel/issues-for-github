import Foundation
import GRDB

/// Every issue keeps its own copy of its labels. A label recoloured or renamed on GitHub changes none of its issues
/// there: not their updatedAt, not their cards, and no issue event tells of it. So the labels are asked for themselves.
extension SyncEngine {
    /// How often the labels on show are compared with GitHub's. A hundred of them cost one point of the rate limit.
    static let labelRefreshInterval: TimeInterval = 60

    /// Brings the labels of issues and Inbox entries up to date with GitHub. Writes only when one of them differs. A
    /// label GitHub no longer has stays as it is: it comes off an issue when the issue is read again.
    func refreshLabels() async throws {
        guard !isDemo else { return }
        if let last = lastLabelPull, Date().timeIntervalSince(last) < Self.labelRefreshInterval { return }
        let shown = try await db.reader.read { try Self.shownLabels($0) }
        do {
            let current = try await api.labels(ids: Set(shown.map(\.id)).sorted())
            if Self.differ(shown, from: current) {
                try await db.writer.write { try Self.write(labels: current, $0) }
            }
        } catch let error as APIError where !error.isTransient {
            // Labels that can't be read never keep the rest from syncing.
            print("Labels could not be read: \(error)")
        }
        lastLabelPull = Date()
    }

    /// The labels on issues and Inbox entries, as they are kept here, without those GitHub hasn't made yet.
    static func shownLabels(_ db: Database) throws -> Set<LabelRef> {
        var shown = Set<LabelRef>()
        for table in ["item", "inboxEntry"] {
            for json in try String.fetchAll(db, sql: "SELECT DISTINCT labels FROM \(table) WHERE labels != '[]'") {
                shown.formUnion((try? JSONDecoder().decode([LabelRef].self, from: Data(json.utf8))) ?? [])
            }
        }
        return shown.filter { !$0.id.hasPrefix(LocalID.prefix) }
    }

    private static func differ(_ shown: Set<LabelRef>, from current: [LabelRef]) -> Bool {
        let current = Dictionary(current.map { ($0.id, $0) }) { _, new in new }
        return shown.contains { label in current[label.id].map { $0 != label } ?? false }
    }

    /// Puts these labels wherever a copy of them is kept: on issues, on Inbox entries and among their repositories'.
    static func write(labels: [LabelRef], _ db: Database) throws {
        let current = Dictionary(labels.map { ($0.id, $0) }) { _, new in new }
        func refresh<Record: FetchableRecord & PersistableRecord>(_: Record.Type, _ path: WritableKeyPath<Record, [LabelRef]>) throws {
            for var record in try Record.filter(Column("labels") != "[]").fetchAll(db) {
                let fresh = record[keyPath: path].map { current[$0.id] ?? $0 }
                guard fresh != record[keyPath: path] else { continue }
                record[keyPath: path] = fresh
                try record.update(db, columns: ["labels"])
            }
        }
        try refresh(Item.self, \.labels)
        try refresh(InboxEntry.self, \.labels)
        try refresh(RepoRef.self, \.labels)
    }
}
