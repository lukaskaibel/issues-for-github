import Foundation
import GRDB

extension Mutation {
    /// Makes a label in a repository, typed into a label picker. Issues it is added to wait until GitHub has made it.
    public struct CreateLabel: Codable, Sendable, Equatable {
        /// A local id until GitHub has made it, then GitHub's.
        public var labelId: String
        public var repoId: String
        /// "owner/name".
        public var repo: String
        public var name: String
        /// Hex without the leading '#'.
        public var color: String
    }
}

extension Mutation.CreateLabel {
    var label: LabelRef { LabelRef(id: labelId, name: name, color: color) }

    /// Puts it among its repository's labels, so the pickers offer it everywhere at once.
    func apply(_ db: Database) throws {
        for var repo in try RepoRef.filter(Column("id") == repoId).fetchAll(db) {
            guard !repo.labels.contains(where: { $0.id == labelId || $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { continue }
            repo.labels.append(label)
            repo.labels.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            try repo.update(db)
        }
    }

    /// GitHub didn't make it: it comes off the issues, the repository and the changes that were waiting for it.
    func withdraw(_ db: Database) throws {
        let pattern = "%\(labelId)%"
        for var item in try Item.filter(Column("labels").like(pattern)).fetchAll(db) {
            item.labels.removeAll { $0.id == labelId }
            try item.update(db)
        }
        for var entry in try InboxEntry.filter(Column("labels").like(pattern)).fetchAll(db) {
            entry.labels.removeAll { $0.id == labelId }
            try entry.update(db)
        }
        for var repo in try RepoRef.filter(Column("labels").like(pattern)).fetchAll(db) {
            repo.labels.removeAll { $0.id == labelId }
            try repo.update(db)
        }
        for var waiting in try Outbox.active(db) {
            switch waiting.mutation {
            case .editLabels(var m):
                m.add.removeAll { $0.id == labelId }
                m.remove.removeAll { $0.id == labelId }
                if m.add.isEmpty && m.remove.isEmpty {
                    try waiting.delete(db)
                } else {
                    waiting.mutation = .editLabels(m)
                    try waiting.update(db)
                }
            case .createIssue(var m):
                guard m.labels.contains(where: { $0.id == labelId }) else { continue }
                m.labels.removeAll { $0.id == labelId }
                waiting.mutation = .createIssue(m)
                try waiting.update(db)
            default:
                continue
            }
        }
    }

    /// Follows the label to GitHub's id wherever it is kept, once GitHub has made it.
    static func remap(_ db: Database, from old: String, to new: String) throws {
        let pattern = "%\(old)%"
        for table in ["item", "inboxEntry", "repo"] {
            try db.execute(
                sql: "UPDATE \(table) SET labels = REPLACE(labels, ?, ?) WHERE labels LIKE ?",
                arguments: [old, new, pattern]
            )
        }
        // The repository may have the label from GitHub already, read while it was being made.
        for var repo in try RepoRef.filter(Column("labels").like("%\(new)%")).fetchAll(db) {
            var seen = Set<String>()
            let unique = repo.labels.filter { seen.insert($0.id).inserted }
            guard unique.count != repo.labels.count else { continue }
            repo.labels = unique
            try repo.update(db)
        }
    }
}
