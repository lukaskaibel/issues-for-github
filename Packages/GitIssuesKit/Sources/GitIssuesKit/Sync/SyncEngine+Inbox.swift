import Foundation
import GRDB

/// The Inbox: GitHub's notifications about issues and pull requests, read at the pace GitHub asks for, and the
/// issues behind them read once per change.
extension SyncEngine {
    /// Asks GitHub for the notifications. Most of the time the answer is "nothing new", which is free. A token that
    /// may not read notifications (a fine-grained one) leaves the Inbox empty with a note and the rest syncing.
    public func pullInbox() async throws {
        guard !isDemo else { return }
        let meta = try await db.reader.read { try InboxMeta.read($0) }
        let list: NotificationList
        do {
            list = try await api.notifications(ifModifiedSince: meta.access == .ok ? meta.lastModified : nil)
        } catch let error as APIError {
            guard case .http(let code, _) = error, code == 403 || code == 404 else { throw error }
            nextInboxPull = Date().addingTimeInterval(300)
            try await db.writer.write { db in
                var meta = try InboxMeta.read(db)
                meta.access = .denied
                meta.lastModified = nil
                try meta.write(db)
                try InboxEntry.deleteAll(db)
            }
            return
        }
        switch list {
        case .notModified(let interval):
            scheduleInbox(interval)
        case .threads(let threads, let lastModified, let interval):
            scheduleInbox(interval)
            try await db.writer.write { db in
                try Self.writeInbox(db, threads: threads, lastModified: lastModified)
            }
        }
        try await enrichInbox()
    }

    /// The Inbox's part of a sync round. Being offline or signed out stops the round as usual; anything else that
    /// goes wrong here is retried later and never keeps the boards from syncing.
    func pullInboxInRound() async throws {
        do {
            try await pullInbox()
        } catch let error as APIError where error.isTransient {
            throw error
        } catch APIError.unauthorized {
            throw APIError.unauthorized
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            print("The Inbox could not be read: \(error)")
            nextInboxPull = Date().addingTimeInterval(120)
        }
    }

    /// Asks for the notifications in the next round instead of waiting for GitHub's interval, when the Inbox comes
    /// on screen or the app comes to the front.
    public func refreshInbox() {
        nextInboxPull = .distantPast
        kick()
    }

    private func scheduleInbox(_ interval: TimeInterval?) {
        // GitHub says how often to ask (usually 60 s); never more often than the rest of syncing.
        nextInboxPull = Date().addingTimeInterval(max(interval ?? 60, 15))
    }

    static func writeInbox(_ db: Database, threads: [RemoteThread], lastModified: String?) throws {
        var meta = try InboxMeta.read(db)
        meta.access = .ok
        meta.lastModified = lastModified
        meta.others = [:]
        for thread in threads where !thread.isIssueOrPullRequest {
            meta.others[thread.subjectType, default: 0] += 1
        }
        try meta.write(db)

        let relevant = threads.filter(\.isIssueOrPullRequest)
        // What GitHub no longer lists was archived elsewhere, or is too old to be kept.
        try InboxEntry.filter(!relevant.map(\.id).contains(Column("id"))).deleteAll(db)
        for thread in relevant {
            if var entry = try InboxEntry.fetchOne(db, key: thread.id) {
                entry.reason = thread.reason
                entry.unread = thread.unread
                entry.updatedAt = thread.updatedAt
                entry.lastReadAt = thread.lastReadAt
                entry.subjectType = thread.subjectType
                entry.title = thread.title
                entry.repo = thread.repo
                entry.number = thread.number
                try entry.update(db)
            } else {
                try InboxEntry(
                    id: thread.id, reason: thread.reason, unread: thread.unread, updatedAt: thread.updatedAt,
                    lastReadAt: thread.lastReadAt, subjectType: thread.subjectType, title: thread.title,
                    repo: thread.repo, number: thread.number
                ).insert(db)
            }
        }
        // Reading, archiving and assigning that haven't reached GitHub yet stay on screen.
        try Outbox.rebase(db)
    }

    /// Reads the issues behind entries that changed since they were last read: who did what, and enough of the
    /// issue to show it when it isn't on a board.
    func enrichInbox() async throws {
        let (viewer, wanted) = try await db.reader.read { db in
            (try KV.viewer(db)?.login, try InboxEntry.fetchAll(db).filter { $0.enrichedFor != $0.updatedAt })
        }
        guard !wanted.isEmpty else { return }
        let requests = wanted.compactMap { entry in
            entry.number.map { InboxDetailRequest(threadId: entry.id, repo: entry.repo, number: $0, since: Self.newsSince(entry)) }
        }
        let results = try await api.inboxDetails(requests, viewer: viewer)
        try await db.writer.write { db in
            for entry in wanted {
                // The thread may have moved on while this was read; then it is read again next time.
                guard var current = try InboxEntry.fetchOne(db, key: entry.id), current.updatedAt == entry.updatedAt else { continue }
                switch results[entry.id] {
                case .found(let detail)?:
                    Self.fill(&current, with: detail, unread: entry.unread)
                case .missing?:
                    current.missing = true
                case nil:
                    // Without a number there is nothing to read; what GitHub listed is all there is.
                    guard entry.number == nil else { continue }
                    current.missing = true
                }
                current.enrichedFor = current.updatedAt
                try current.update(db)
            }
            try Outbox.rebase(db)
        }
    }

    /// From when an entry's activity counts as new: since you last read it, or for one you never read, its last two
    /// weeks. A read entry shows its latest activity, so the same window.
    static func newsSince(_ entry: InboxEntry) -> Date {
        if entry.unread, let read = entry.lastReadAt { return read }
        return entry.updatedAt.addingTimeInterval(-14 * 86_400)
    }

    static func fill(_ entry: inout InboxEntry, with detail: RemoteInboxDetail, unread: Bool) {
        entry.missing = false
        entry.contentId = detail.contentId
        entry.url = detail.url
        entry.title = detail.title
        entry.body = detail.body
        entry.state = detail.state
        entry.stateReason = detail.stateReason
        entry.repoId = detail.repoId
        entry.authorLogin = detail.authorLogin
        entry.createdAt = detail.createdAt
        entry.assignees = detail.assignees
        entry.labels = detail.labels
        entry.activity = detail.activity
        entry.activityIsNew = unread
        entry.activitySince = unread ? entry.lastReadAt : nil
    }
}
