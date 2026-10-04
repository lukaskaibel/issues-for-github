import GRDB
import Observation

/// The comments and sub-issues of one issue, kept in step with the database. Each issue on screen has its
/// own, so an iPad can show two issues side by side and the Mac keeps the list beneath an open issue.
@MainActor
@Observable
final class IssueDetailModel {
    let contentId: String
    private(set) var comments: [Comment] = []
    private(set) var subIssues: [SubIssue] = []

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

    private func update(_ value: (comments: [Comment], subIssues: [SubIssue])) {
        if comments != value.comments { comments = value.comments }
        if subIssues != value.subIssues { subIssues = value.subIssues }
    }

    private nonisolated static func fetch(_ db: Database, contentId: String) throws -> (comments: [Comment], subIssues: [SubIssue]) {
        (
            try Comment.filter(Column("issueId") == contentId).order(Column("createdAt")).fetchAll(db),
            try SubIssue.filter(Column("parentId") == contentId).order(Column("position")).fetchAll(db)
        )
    }
}
