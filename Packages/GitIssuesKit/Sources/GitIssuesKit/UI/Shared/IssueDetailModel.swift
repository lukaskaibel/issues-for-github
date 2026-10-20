import GRDB
import Observation

/// The comments and sub-issues of one issue, kept in step with the database. Each issue on screen has its
/// own, so an iPad can show two issues side by side and the Mac keeps the list beneath an open issue.
@MainActor
@Observable
final class IssueDetailModel {
    let contentId: String
    private(set) var comments: [Comment] = []
    /// The issue's own sub-issues and, by parent, those of every sub-issue below it that has been read.
    private(set) var subIssueTree: [String: [SubIssue]] = [:]

    var subIssues: [SubIssue] { subIssueTree[contentId] ?? [] }

    @ObservationIgnored private let db: AppDatabase
    @ObservationIgnored private var observation: AnyDatabaseCancellable?

    init(contentId: String, db: AppDatabase) {
        self.contentId = contentId
        self.db = db
        let id = contentId
        observation = ValueObservation
            .tracking { db in try Self.fetch(db, contentId: id) }
            .start(
                in: db.reader,
                scheduling: .immediate,
                onError: { _ in },
                onChange: { [weak self] value in
                    MainActor.assumeIsolated { self?.update(value) }
                }
            )
    }

    /// Reads right away, so a comment just written shows in the same frame.
    func reload() {
        let id = contentId
        if let value = try? db.reader.read({ try Self.fetch($0, contentId: id) }) {
            update(value)
        }
    }

    /// The sub-issues of a sub-issue below this issue, as far as they have been read.
    func subIssues(of parentId: String) -> [SubIssue] {
        subIssueTree[parentId] ?? []
    }

    private func update(_ value: (comments: [Comment], tree: [String: [SubIssue]])) {
        if comments != value.comments { comments = value.comments }
        if subIssueTree != value.tree { subIssueTree = value.tree }
    }

    private nonisolated static func fetch(_ db: Database, contentId: String) throws -> (comments: [Comment], tree: [String: [SubIssue]]) {
        // Level by level down the tree; GitHub allows eight. An issue met twice, in stale data, is read once.
        var tree: [String: [SubIssue]] = [:]
        var level = [contentId]
        var seen: Set<String> = [contentId]
        for _ in 0..<8 where !level.isEmpty {
            let subs = try SubIssue
                .filter(level.contains(Column("parentId")))
                .order(Column("position"))
                .fetchAll(db)
            level = []
            for sub in subs {
                tree[sub.parentId, default: []].append(sub)
                if seen.insert(sub.id).inserted { level.append(sub.id) }
            }
        }
        return (
            try Comment.filter(Column("issueId") == contentId).order(Column("createdAt")).fetchAll(db),
            tree
        )
    }
}
