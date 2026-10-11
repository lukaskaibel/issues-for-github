import Foundation
import GRDB
import Testing
@testable import GitIssuesKit

@Suite("Assignments made with your own account, as Inbox entries")
struct SelfAssignedInboxTests {
    static let me = Person(id: "login:jordan", login: "jordan", name: "Jordan Lee")
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func issue(_ contentId: String = "I_1", title: String = "Crash on launch", createdAt: Date) -> RemoteInboxDetail {
        RemoteInboxDetail(
            contentId: contentId, url: "https://github.com/acme/app/issues/12", title: title, body: "Steps", state: "OPEN",
            stateReason: nil, repoId: "R_1", authorLogin: "jordan", createdAt: createdAt, assignees: [me], labels: [],
            activity: []
        )
    }

    static func assignment(
        _ eventId: String, at: Date, contentId: String = "I_1", title: String = "Crash on launch", createdAt: Date? = nil
    ) -> RemoteSelfAssignment {
        RemoteSelfAssignment(
            eventId: eventId, at: at, actor: me, repo: "acme/app", number: 12,
            issue: issue(contentId, title: title, createdAt: createdAt ?? at.addingTimeInterval(-86_400))
        )
    }

    // MARK: Reading GitHub's answer

    @Test func onlyAssignmentsByYourOwnAccountAreKept() throws {
        let json = """
        [{"__typename": "Issue", "id": "I_1", "number": 12, "url": "https://github.com/acme/app/issues/12",
          "title": "Crash on launch", "body": "Steps", "state": "OPEN", "stateReason": null, "createdAt": "2026-10-09T13:59:17Z",
          "author": {"login": "jordan", "avatarUrl": null, "name": "Jordan Lee"},
          "repository": {"id": "R_1", "nameWithOwner": "acme/app"},
          "assignees": {"nodes": [{"id": "U_j", "login": "jordan", "name": "Jordan Lee", "avatarUrl": null}]},
          "labels": {"nodes": []},
          "timelineItems": {"nodes": [
            {"__typename": "AssignedEvent", "id": "AE_1", "createdAt": "2026-10-09T13:59:18Z", "actor": {"login": "Jordan", "name": "Jordan Lee"}, "assignee": {"login": "jordan"}},
            {"__typename": "AssignedEvent", "id": "AE_2", "createdAt": "2026-10-09T14:00:00Z", "actor": {"login": "kai"}, "assignee": {"login": "jordan"}},
            {"__typename": "AssignedEvent", "id": "AE_3", "createdAt": "2026-10-09T14:01:00Z", "actor": {"login": "jordan"}, "assignee": {"login": "theo"}},
            {"__typename": "AssignedEvent", "id": "AE_4", "createdAt": "2026-10-09T10:00:00Z", "actor": {"login": "jordan"}, "assignee": {"login": "jordan"}}
          ]}},
         {}]
        """
        let since = try #require(ISO8601DateFormatter().date(from: "2026-10-09T13:00:00Z"))
        let found = try GitHubAPI.selfAssignments(fromJSON: Data(json.utf8), since: since, viewer: "jordan")
        // Kai assigning you is a notification from GitHub; you assigning Theo isn't about you; AE_4 is before "since".
        #expect(found.assignments.map(\.eventId) == ["AE_1"])
        let assignment = try #require(found.assignments.first)
        #expect(assignment.repo == "acme/app")
        #expect(assignment.number == 12)
        #expect(assignment.issue.contentId == "I_1")
        #expect(assignment.issue.repoId == "R_1")
        #expect(assignment.actor?.login == "Jordan")
        #expect(found.issues.keys.sorted() == ["I_1"])
    }

    // MARK: What a row says

    @Test func anEntryIsTheAppsOwnAndForYou() {
        let entry = InboxEntry(selfAssignment: Self.assignment("AE_1", at: Self.now))
        #expect(entry.id == "self_assign:AE_1")
        #expect(entry.isSelfAssigned)
        #expect(entry.isAppMade)
        #expect(!entry.isDue)
        #expect(entry.bucket == .forYou)
        #expect(entry.contentId == "I_1")
        #expect(entry.updatedAt == Self.now)
        #expect(entry.enrichedFor == Self.now)
        #expect(entry.activity.map(\.kind) == [.assigned])
    }

    @Test func aNewIssueSaysSo() {
        let created = InboxEntry(selfAssignment: Self.assignment("AE_1", at: Self.now, createdAt: Self.now.addingTimeInterval(-1)))
        let summary = created.summary(viewer: "jordan")
        #expect(summary.lead == "New issue, assigned to you")
        #expect(summary.sign == .assigned)
        #expect(summary.actor?.login == "jordan")

        let existing = InboxEntry(selfAssignment: Self.assignment("AE_2", at: Self.now))
        #expect(existing.summary(viewer: "jordan").lead == "You were assigned")
    }

    @Test func notificationsFromGitHubAreNotTheAppsOwn() {
        let entry = InboxEntry(id: "123", reason: "assign", unread: true, updatedAt: Self.now, subjectType: "Issue", title: "T", repo: "a/b", number: 1)
        #expect(!entry.isSelfAssigned)
        #expect(!entry.isAppMade)
    }

    // MARK: Telling the app's own assignments apart

    private func entries(_ times: [TimeInterval], contentId: String = "I_1") -> [InboxEntry] {
        times.enumerated().map { index, offset in
            InboxEntry(selfAssignment: Self.assignment("AE_\(contentId)_\(index)", at: Self.now.addingTimeInterval(offset), contentId: contentId))
        }
    }

    @Test func anAssignmentMadeHereIsClaimedByItsRecord() {
        // Queued at `now`, reached GitHub 20 seconds later.
        let own = InboxEntry.assignedInApp(entries([20]), noted: { $0 == "I_1" ? [Self.now] : [] })
        #expect(own == ["self_assign:AE_I_1_0"])
    }

    @Test func aLaterAssignmentWithGhIsNews() {
        // The app assigned you; someone took you off; an agent assigned you again an hour later.
        let own = InboxEntry.assignedInApp(entries([5, 3600]), noted: { _ in [Self.now] })
        #expect(own == ["self_assign:AE_I_1_0"])
    }

    @Test func anAssignmentBeforeTheAppsIsNews() {
        let own = InboxEntry.assignedInApp(entries([-600]), noted: { _ in [Self.now] })
        #expect(own.isEmpty)
    }

    @Test func aChangeThatWaitedOfflineIsStillClaimed() {
        // Clocks differ a little either way; a change can wait in the queue for days.
        #expect(InboxEntry.assignedInApp(entries([-60]), noted: { _ in [Self.now] }).count == 1)
        #expect(InboxEntry.assignedInApp(entries([3 * 86_400]), noted: { _ in [Self.now] }).count == 1)
        #expect(InboxEntry.assignedInApp(entries([8 * 86_400]), noted: { _ in [Self.now] }).isEmpty)
    }

    @Test func eachAssignmentHereClaimsOne() {
        let both = InboxEntry.assignedInApp(entries([10, 70]), noted: { _ in [Self.now, Self.now.addingTimeInterval(60)] })
        #expect(both.count == 2)
        let otherIssue = InboxEntry.assignedInApp(entries([10], contentId: "I_2"), noted: { $0 == "I_1" ? [Self.now] : [] })
        #expect(otherIssue.isEmpty)
    }

    @Test @MainActor func theAppsAssignmentsAreNotedOnceAndExpire() {
        let store = PersonalStore(persistent: false)
        let moment = Date().addingTimeInterval(-30)
        store.noteAssignedHere("I_1", at: moment)
        store.noteAssignedHere("I_1", at: moment)
        #expect(store.assignedHere("I_1") == [moment])
        #expect(store.assignedHere("I_2").isEmpty)
        // Older than a week: its assignment came back from GitHub long ago, if it ever was going to.
        store.noteAssignedHere("I_2", at: Date().addingTimeInterval(-8 * 86_400))
        #expect(store.assignedHere("I_2").isEmpty)
        // Kept apart from the entries about the issue.
        #expect(!store.isRead("I_1"))
    }

    // MARK: Keeping them

    private func makeDatabase() throws -> AppDatabase {
        try AppDatabase.inMemory()
    }

    private func selfAssigned(_ db: AppDatabase) throws -> [InboxEntry] {
        try db.reader.read { try InboxEntry.filter(Column("reason") == InboxEntry.selfAssignReason).order(Column("updatedAt")).fetchAll($0) }
    }

    @Test func assignmentsFoundBecomeEntriesOnce() throws {
        let db = try makeDatabase()
        let from = Self.now.addingTimeInterval(-3600)
        let found = SelfAssignmentList(
            assignments: [Self.assignment("AE_1", at: Self.now), Self.assignment("AE_0", at: from.addingTimeInterval(-60))],
            issues: ["I_1": Self.issue(createdAt: from)]
        )
        try db.writer.write { try SyncEngine.writeSelfAssigned($0, found, from: from, now: Self.now) }
        try db.writer.write { try SyncEngine.writeSelfAssigned($0, found, from: from, now: Self.now) }
        // Before this device first looked isn't news.
        #expect(try selfAssigned(db).map(\.id) == ["self_assign:AE_1"])
    }

    @Test func theIssueStaysUpToDate() throws {
        let db = try makeDatabase()
        let from = Self.now.addingTimeInterval(-3600)
        try db.writer.write {
            try SyncEngine.writeSelfAssigned($0, SelfAssignmentList(assignments: [Self.assignment("AE_1", at: Self.now)], issues: [:]), from: from, now: Self.now)
        }
        let renamed = SelfAssignmentList(assignments: [], issues: ["I_1": Self.issue(title: "Crash on launch on macOS 27", createdAt: from)])
        try db.writer.write { try SyncEngine.writeSelfAssigned($0, renamed, from: from, now: Self.now) }
        #expect(try selfAssigned(db).first?.title == "Crash on launch on macOS 27")
    }

    @Test func oldEntriesLeave() throws {
        let db = try makeDatabase()
        let from = Self.now.addingTimeInterval(-30 * 86_400)
        let found = SelfAssignmentList(assignments: [
            Self.assignment("AE_old", at: Self.now.addingTimeInterval(-22 * 86_400)), Self.assignment("AE_new", at: Self.now),
        ], issues: [:])
        try db.writer.write { try SyncEngine.writeSelfAssigned($0, found, from: from, now: Self.now) }
        #expect(try selfAssigned(db).map(\.id) == ["self_assign:AE_new"])
    }

    @Test func gitHubsListLeavesTheAppsOwnEntriesAlone() throws {
        let db = try makeDatabase()
        try db.writer.write { db in
            try InboxEntry(selfAssignment: Self.assignment("AE_1", at: Self.now)).insert(db)
            try SyncEngine.writeInbox(db, threads: [], lastModified: nil)
        }
        #expect(try selfAssigned(db).count == 1)
        // Nor does it read them like the issues behind GitHub's notifications.
        #expect(try selfAssigned(db).first?.enrichedFor == Self.now)
    }
}
