import Foundation
import GRDB

/// A board's updatedAt says when one of its cards changed, but not always: GitHub never counts a new parent,
/// sub-issue or blocker as a change of the issue, its card or its board, and passes an edit of the issue (a new title,
/// a label) on to the card a few seconds later, or at times not at all. The repository's issue events list all of
/// these as they happen, and asking for them is free as long as nothing happened.
extension SyncEngine {
    /// Events that change what a card or a row shows of an issue.
    static let shownEvents: Set<String> = [
        "renamed", "labeled", "unlabeled", "assigned", "unassigned", "closed", "reopened",
        "parent_issue_added", "parent_issue_removed", "sub_issue_added", "sub_issue_removed",
        "blocked_by_added", "blocked_by_removed", "blocking_added", "blocking_removed",
    ]

    /// How many pages of events are read to catch up. Past that, every issue of the repository is read again.
    static let issueEventPages = 15

    /// GitHub lists an event a moment after it happened, at times after a later one, so a look reaches back
    /// this far before the newest event it has seen.
    static let issueEventLag: TimeInterval = 300

    struct EventChanges {
        /// Issues that something happened to.
        var contentIds: Set<String> = []
        /// Repositories where more happened than is worth reading through; all their issues are read again.
        var repoIds: Set<String> = []
        /// Where to go on from next time, for each repository looked at, to be saved with what is read because of
        /// these changes.
        var cursors: [String: IssueEventCursor] = [:]
    }

    /// Reads what happened in the repositories since the cursors, or for a repository without one since
    /// `firstLook`: when what is shown of it was last read. A repository that can't be read is left for the next
    /// time and never keeps the rest from syncing.
    func changesFromEvents(
        in repos: [(id: String, name: String)], since cursors: [String: IssueEventCursor], firstLook: Date
    ) async throws -> EventChanges {
        var changes = EventChanges()
        for repo in repos {
            changes.cursors[repo.id] = cursors[repo.id]
            guard !eventsUnreadable.contains(repo.id) else { continue }
            let cursor = cursors[repo.id] ?? IssueEventCursor(since: firstLook.addingTimeInterval(-Self.issueEventLag))
            do {
                let first = try await api.issueEvents(repo: repo.name, ifNoneMatch: cursor.etag)
                guard case .events(var events, let etag, var hasNext) = first else { continue }
                var page = 1
                while hasNext, !Self.reachesBack(events, to: cursor), page < Self.issueEventPages {
                    page += 1
                    guard case .events(let more, _, let next) = try await api.issueEvents(repo: repo.name, page: page) else { break }
                    events += more
                    hasNext = next
                }
                if hasNext, !Self.reachesBack(events, to: cursor) {
                    changes.repoIds.insert(repo.id)
                } else {
                    changes.contentIds.formUnion(Self.changedIssues(in: events, after: cursor))
                }
                changes.cursors[repo.id] = Self.advance(cursor, over: events, etag: etag)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as APIError where error.isTransient {
                continue
            } catch {
                print("The issue events of \(repo.name) could not be read: \(error)")
                eventsUnreadable.insert(repo.id)
            }
        }
        return changes
    }

    /// Of events read newest first, the issues whose cards changed after `cursor`.
    static func changedIssues(in events: [RemoteIssueEvent], after cursor: IssueEventCursor) -> Set<String> {
        Set(events.compactMap { event in
            guard shownEvents.contains(event.event), event.createdAt >= cursor.since, !cursor.seen.contains(event.id) else { return nil }
            return event.contentId
        })
    }

    /// Whether events read newest first go back to where `cursor` left off, so none in between were missed.
    static func reachesBack(_ events: [RemoteIssueEvent], to cursor: IssueEventCursor) -> Bool {
        events.contains { $0.createdAt < cursor.since }
    }

    /// Where to go on from after reading `events`.
    static func advance(_ cursor: IssueEventCursor, over events: [RemoteIssueEvent], etag: String?) -> IssueEventCursor {
        guard let newest = events.map(\.createdAt).max() else {
            return IssueEventCursor(etag: etag, since: cursor.since, seen: cursor.seen)
        }
        let since = max(newest.addingTimeInterval(-issueEventLag), cursor.since)
        return IssueEventCursor(etag: etag, since: since, seen: Set(events.filter { $0.createdAt >= since }.map(\.id)))
    }
}

/// How far a repository's issue events have been read, by one board or for the issues on no board. Kept in the
/// database, so what happened while the app was closed is caught up on.
struct IssueEventCursor: Codable, Equatable, Sendable {
    /// GitHub's ETag for the first page, to ask "anything new?" for free.
    var etag: String?
    /// Events from then on are new unless they are among `seen`.
    var since: Date
    var seen: Set<Int> = []

    static func key(projectId: String?) -> String {
        projectId.map { "issueEvents.\($0)" } ?? "issueEvents"
    }

    /// By repository id.
    static func read(_ db: Database, projectId: String?) throws -> [String: IssueEventCursor] {
        guard let json = try KV.string(db, key(projectId: projectId)) else { return [:] }
        return (try? JSONDecoder().decode([String: IssueEventCursor].self, from: Data(json.utf8))) ?? [:]
    }

    static func write(_ db: Database, _ cursors: [String: IssueEventCursor], projectId: String?) throws {
        let json = cursors.isEmpty ? nil : String(decoding: try JSONEncoder().encode(cursors), as: UTF8.self)
        try KV.set(db, key(projectId: projectId), json)
    }
}
