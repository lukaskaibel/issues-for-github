import Foundation
import GRDB
import Testing
@testable import GitIssuesKit

@Suite("Changes a board's updatedAt doesn't show, or not yet")
struct IssueEventsTests {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)

    static func event(_ id: Int, _ name: String, on contentId: String, at seconds: TimeInterval) -> RemoteIssueEvent {
        RemoteIssueEvent(id: id, event: name, createdAt: start.addingTimeInterval(seconds), contentId: contentId)
    }

    // MARK: Reading GitHub's answer

    @Test func eventsAreReadFromTheRestAnswer() throws {
        let json = """
        [{"id": 33040952579, "node_id": "PIAE_1", "event": "parent_issue_added", "commit_id": null,
          "created_at": "2026-10-12T11:04:30Z", "actor": {"login": "octo"},
          "parent_issue": {"number": 24, "title": "Animate the column count"},
          "issue": {"id": 1, "node_id": "I_17", "number": 17, "title": "Command palette", "body": "Long text"}},
         {"id": 33040952515, "event": "sub_issue_added", "created_at": "2026-10-12T11:04:29Z",
          "issue": {"node_id": "I_24", "number": 24}}]
        """
        let events = try GitHubAPI.issueEvents(fromJSON: Data(json.utf8))
        #expect(events.map(\.id) == [33040952579, 33040952515])
        #expect(events.map(\.event) == ["parent_issue_added", "sub_issue_added"])
        #expect(events.map(\.contentId) == ["I_17", "I_24"])
        #expect(events[0].createdAt == ISO8601DateFormatter().date(from: "2026-10-12T11:04:30Z"))
    }

    // MARK: Telling new events from those seen

    @Test func eventsAboutWhatACardShowsCountOthersDont() {
        let old = Self.event(1, "parent_issue_added", on: "I_8", at: 0)
        let cursor = SyncEngine.advance(IssueEventCursor(since: .distantPast), over: [old], etag: "W/\"a\"")
        #expect(cursor.etag == "W/\"a\"")
        #expect(cursor.seen == [1])
        let events = [
            Self.event(9, "blocked_by_removed", on: "I_5", at: 60),
            Self.event(8, "renamed", on: "I_6", at: 50),
            Self.event(7, "mentioned", on: "I_7", at: 45),
            Self.event(6, "sub_issue_removed", on: "I_9", at: 40),
            Self.event(5, "parent_issue_removed", on: "I_3", at: 40),
            Self.event(4, "parent_issue_added", on: "I_3", at: 41),
            Self.event(3, "referenced", on: "I_2", at: 35),
            Self.event(2, "labeled", on: "I_4", at: 30),
            old,
        ]
        #expect(SyncEngine.changedIssues(in: events, after: cursor) == ["I_5", "I_6", "I_9", "I_3", "I_4"])
    }

    @Test func aFirstLookCountsWhatHappenedSinceTheBoardWasLastRead() {
        // A repository looked at for the first time starts from when the board was last read.
        let cursor = IssueEventCursor(since: Self.start.addingTimeInterval(100))
        let events = [Self.event(2, "sub_issue_added", on: "I_2", at: 120), Self.event(1, "sub_issue_added", on: "I_1", at: 80)]
        #expect(SyncEngine.changedIssues(in: events, after: cursor) == ["I_2"])
    }

    @Test func anEventListedLateStillCounts() {
        let first = [Self.event(10, "sub_issue_added", on: "I_2", at: 100), Self.event(8, "closed", on: "I_4", at: 20)]
        let cursor = SyncEngine.advance(IssueEventCursor(since: .distantPast), over: first, etag: nil)
        // GitHub lists the child's side a moment later, a second before the parent's.
        let later = [first[0], Self.event(9, "parent_issue_added", on: "I_1", at: 99), first[1]]
        #expect(SyncEngine.changedIssues(in: later, after: cursor) == ["I_1"])
    }

    @Test func eventsLongBeforeTheLastLookAreTakenAsSeen() {
        let cursor = SyncEngine.advance(IssueEventCursor(since: .distantPast), over: [Self.event(50, "closed", on: "I_1", at: 1000)], etag: nil)
        #expect(cursor.since == Self.start.addingTimeInterval(1000 - SyncEngine.issueEventLag))
        let events = [Self.event(50, "closed", on: "I_1", at: 1000), Self.event(3, "parent_issue_added", on: "I_2", at: 10)]
        #expect(SyncEngine.changedIssues(in: events, after: cursor).isEmpty)
    }

    @Test func readingGoesOnUntilItReachesTheLastLook() {
        let cursor = IssueEventCursor(since: Self.start.addingTimeInterval(700))
        let newer = (2...5).map { Self.event($0, "labeled", on: "I_2", at: 2000 + Double($0)) }
        #expect(!SyncEngine.reachesBack(newer, to: cursor))
        let older = [Self.event(1, "closed", on: "I_1", at: 1000), Self.event(0, "closed", on: "I_1", at: 10)]
        #expect(SyncEngine.reachesBack(newer + older, to: cursor))
    }

    @Test func theStartMovesOnWithTheNewestEventAndNeverBack() {
        let cursor = SyncEngine.advance(IssueEventCursor(since: .distantPast), over: [Self.event(5, "closed", on: "I_1", at: 1000)], etag: "a")
        // A comment on one of the issues changes GitHub's ETag without a new event.
        let same = SyncEngine.advance(cursor, over: [Self.event(5, "closed", on: "I_1", at: 1000)], etag: "b")
        #expect(same == IssueEventCursor(etag: "b", since: cursor.since, seen: [5]))
        let events = [
            Self.event(7, "closed", on: "I_1", at: 1200), Self.event(5, "closed", on: "I_1", at: 1000),
            Self.event(6, "closed", on: "I_2", at: 850),
        ]
        let next = SyncEngine.advance(cursor, over: events, etag: "c")
        #expect(next.since == Self.start.addingTimeInterval(1200 - SyncEngine.issueEventLag))
        #expect(next.seen == [7, 5])
        // The newest event went away with its issue; what is older than the start was seen before.
        let deleted = SyncEngine.advance(cursor, over: [Self.event(4, "closed", on: "I_3", at: 500)], etag: "d")
        #expect(deleted.since == cursor.since)
        #expect(deleted.seen.isEmpty)
        let empty = SyncEngine.advance(IssueEventCursor(since: .distantPast), over: [], etag: "e")
        #expect(empty == IssueEventCursor(etag: "e", since: .distantPast))
    }

    @Test func cursorsAreKeptPerBoard() throws {
        let db = try AppDatabase.inMemory()
        let cursor = IssueEventCursor(etag: "W/\"x\"", since: Self.start, seen: [1, 2])
        try db.writer.write { db in
            try IssueEventCursor.write(db, ["R1": cursor], projectId: "P1")
            try IssueEventCursor.write(db, ["R1": IssueEventCursor(since: .distantPast)], projectId: nil)
        }
        let (board, noBoard, other) = try db.reader.read { db in
            (try IssueEventCursor.read(db, projectId: "P1"), try IssueEventCursor.read(db, projectId: nil),
             try IssueEventCursor.read(db, projectId: "P2"))
        }
        #expect(board == ["R1": cursor])
        #expect(noBoard == ["R1": IssueEventCursor(since: .distantPast)])
        #expect(other.isEmpty)
    }

    // MARK: Pulling

    private func makeEngine(_ github: FakeGitHub) async throws -> (AppDatabase, SyncEngine) {
        let db = try AppDatabase.inMemory()
        try await db.writer.write { db in
            try Project(
                id: FakeGitHub.projectId, ownerLogin: "octo", ownerIsOrg: false, number: 1, title: "Board", url: "",
                closed: false, viewerCanUpdate: true
            ).insert(db)
        }
        let status = await MainActor.run { SyncStatus() }
        return (db, SyncEngine(db: db, api: github.api, status: status))
    }

    private func item(_ db: AppDatabase, _ number: Int) throws -> Item? {
        try db.reader.read { try Item.filter(Column("number") == number).fetchOne($0) }
    }

    @Test func aPullSeesANewParentThoughNothingsUpdatedAtMoved() async throws {
        let github = FakeGitHub([
            .init(contentId: "I_1", number: 1, itemId: "PVTI_1"),
            .init(contentId: "I_2", number: 2, itemId: "PVTI_2"),
            .init(contentId: "I_3", number: 3, itemId: "PVTI_3"),
        ])
        github.event("labeled", on: "I_1")
        let (db, engine) = try await makeEngine(github)
        try await engine.pull(projectId: FakeGitHub.projectId)
        #expect(try item(db, 1)?.parentId == nil)
        #expect(github.requests() == ["meta", "sweep", "cards"])

        github.setParent(of: "I_1", to: "I_2")
        try await engine.pull(projectId: FakeGitHub.projectId)
        #expect(try item(db, 1)?.parentNumber == 2)
        #expect(try item(db, 2)?.subTotal == 1)
        // Only the two cards are read, not the whole board.
        #expect(github.requests() == ["meta", "events", "cards"])

        // With nothing new, GitHub answers "not modified" for free and no card is read.
        try await engine.pull(projectId: FakeGitHub.projectId)
        #expect(github.requests() == ["meta", "events: not modified"])
    }

    @Test func aPullSeesAnEditGitHubDidntPassOnToTheCard() async throws {
        let github = FakeGitHub([
            .init(contentId: "I_1", number: 1, itemId: "PVTI_1"),
            .init(contentId: "I_2", number: 2, itemId: "PVTI_2"),
        ])
        let (db, engine) = try await makeEngine(github)
        try await engine.pull(projectId: FakeGitHub.projectId)
        try await engine.pull(projectId: FakeGitHub.projectId)
        let before = try #require(try item(db, 2))
        _ = github.requests()

        github.rename("I_2", to: "Renamed on GitHub")
        try await engine.pull(projectId: FakeGitHub.projectId)
        let after = try #require(try item(db, 2))
        #expect(after.title == "Renamed on GitHub")
        #expect(after.position == before.position)
        #expect(github.requests() == ["meta", "events", "cards"])
    }

    @Test func aBoardReadBeforeGitHubCaughtUpIsReadAgain() async throws {
        let github = FakeGitHub([.init(contentId: "I_1", number: 1, itemId: "PVTI_1")])
        let (db, engine) = try await makeEngine(github)
        try await engine.pull(projectId: FakeGitHub.projectId)
        try await engine.pull(projectId: FakeGitHub.projectId)
        _ = github.requests()

        github.addCard(.init(contentId: "I_2", number: 2, itemId: "PVTI_2"), listedLate: true)
        try await engine.pull(projectId: FakeGitHub.projectId)
        #expect(try item(db, 2) == nil)
        try await engine.pull(projectId: FakeGitHub.projectId)
        #expect(try item(db, 2) != nil)
        #expect(github.requests() == [
            "meta", "events: not modified", "sweep", "meta", "events: not modified", "sweep", "cards",
        ])
        // Caught up: the board is read again only when it changes.
        try await engine.pull(projectId: FakeGitHub.projectId)
        #expect(github.requests() == ["meta", "events: not modified"])
    }

    @Test func aListOlderThanItsBoardLagsBehind() {
        func meta(_ updatedAt: String, items: Int = 2) -> RemoteProjectMeta {
            RemoteProjectMeta(
                id: "P1", title: "Board", updatedAt: updatedAt, closed: false, viewerCanUpdate: true, itemsTotal: items,
                statusField: nil, priorityField: nil, dueField: nil, repos: []
            )
        }
        let sweep = [
            SweepEntry(id: "PVTI_1", updatedAt: "2026-10-12T11:27:30Z"),
            SweepEntry(id: "PVTI_2", updatedAt: "2026-10-12T11:20:00Z"),
        ]
        #expect(!SyncEngine.readLagsBehind(meta: meta("2026-10-12T11:27:30Z"), sweep: sweep, hydrated: []))
        #expect(SyncEngine.readLagsBehind(meta: meta("2026-10-12T11:27:35Z"), sweep: sweep, hydrated: []))
        // A card read in full that is older than the list says was read from behind as well.
        let card = Item(
            id: "PVTI_1", projectId: "P1", kind: .issue, position: 0, remoteUpdatedAt: "2026-10-12T11:27:00Z",
            title: "", body: "", state: "OPEN"
        )
        #expect(SyncEngine.readLagsBehind(meta: meta("2026-10-12T11:27:30Z"), sweep: sweep, hydrated: [card]))
        #expect(!SyncEngine.readLagsBehind(meta: meta("2026-10-12T11:27:30Z", items: 0), sweep: [], hydrated: []))
        #expect(SyncEngine.readLagsBehind(meta: meta("2026-10-12T11:27:30Z", items: 1), sweep: [], hydrated: []))
    }

    @Test func aRepositoryReadSeesANewParentOfAnIssueOnNoBoard() async throws {
        let github = FakeGitHub([
            .init(contentId: "I_1", number: 1, itemId: "PVTI_1"),
            .init(contentId: "I_3", number: 3),
        ])
        let (db, engine) = try await makeEngine(github)
        try await engine.pull(projectId: FakeGitHub.projectId)
        try await engine.pullRepository(FakeGitHub.repoId)
        #expect(try item(db, 3)?.projectId == nil)
        #expect(try item(db, 3)?.parentId == nil)
        _ = github.requests()

        github.setParent(of: "I_3", to: "I_1")
        try await engine.pullRepository(FakeGitHub.repoId)
        #expect(try item(db, 3)?.parentNumber == 1)
        #expect(github.requests() == ["repository", "events", "issues"])
    }
}
