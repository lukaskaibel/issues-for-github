import Foundation
import GRDB
import Testing
@testable import GitIssuesKit

@Suite("A blocked issue names what blocks it")
struct BlockersTests {
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

    /// The numbers of the open issues listed as blocking `contentId`, in order.
    private func blockers(_ db: AppDatabase, of contentId: String) throws -> [Int] {
        try db.reader.read { db in
            try LinkedIssue.filter(Column("issueId") == contentId && Column("relation") == LinkedIssue.Relation.blockedBy.rawValue)
                .order(Column("position")).fetchAll(db).filter { !$0.isClosed }.map(\.number)
        }
    }

    private static let board: [FakeGitHub.Issue] = [
        .init(contentId: "I_1", number: 1, itemId: "PVTI_1"),
        .init(contentId: "I_2", number: 2, itemId: "PVTI_2", blockedBy: ["I_1"]),
        .init(contentId: "I_3", number: 3, itemId: "PVTI_3", blockedBy: ["I_1", "I_2"]),
    ]

    @Test func aBoardReadReadsWhatBlocksItsCardsInOneGo() async throws {
        let github = FakeGitHub(Self.board)
        let (db, engine) = try await makeEngine(github)
        try await engine.pull(projectId: FakeGitHub.projectId)
        #expect(try blockers(db, of: "I_2") == [1])
        #expect(try blockers(db, of: "I_3") == [1, 2])
        #expect(try blockers(db, of: "I_1").isEmpty)
        #expect(github.requests() == ["meta", "sweep", "cards", "blockers"])

        // Known now: nothing more is asked.
        try await engine.pull(projectId: FakeGitHub.projectId)
        try await engine.pull(projectId: FakeGitHub.projectId)
        #expect(github.requests() == ["meta", "events", "meta", "events: not modified"])
    }

    @Test func aBlockerSetOrTakenAwayOnGitHubShowsUp() async throws {
        let github = FakeGitHub(Self.board)
        let (db, engine) = try await makeEngine(github)
        try await engine.pull(projectId: FakeGitHub.projectId)
        _ = github.requests()

        // Another blocker in place of the first: the count stays, the card is read again because of the events.
        github.unblock("I_2", from: "I_1")
        github.block("I_2", by: "I_3")
        try await engine.pull(projectId: FakeGitHub.projectId)
        #expect(try blockers(db, of: "I_2") == [3])
        #expect(github.requests() == ["meta", "events", "cards", "blockers"])

        github.unblock("I_3", from: "I_1")
        try await engine.pull(projectId: FakeGitHub.projectId)
        #expect(try blockers(db, of: "I_3") == [2])
    }

    @Test func blockersGitHubWontShowArentAskedForAgainAndAgain() async throws {
        let github = FakeGitHub([
            .init(contentId: "I_1", number: 1, itemId: "PVTI_1"),
            .init(contentId: "I_2", number: 2, itemId: "PVTI_2", blockedBy: ["I_1"], hiddenBlockers: 1),
        ])
        let (db, engine) = try await makeEngine(github)
        try await engine.pull(projectId: FakeGitHub.projectId)
        #expect(try blockers(db, of: "I_2") == [1])
        #expect(github.requests() == ["meta", "sweep", "cards", "blockers"])
        try await engine.pull(projectId: FakeGitHub.projectId)
        try await engine.pull(projectId: FakeGitHub.projectId)
        #expect(github.requests() == ["meta", "events", "meta", "events: not modified"])
    }

    @Test func aBlockerSetHereKeepsUntilGitHubHasIt() async throws {
        let github = FakeGitHub(Self.board)
        let (db, engine) = try await makeEngine(github)
        try await engine.pull(projectId: FakeGitHub.projectId)
        let blocked = try #require(try await db.reader.read { try Item.filter(Column("number") == 1).fetchOne($0) }?.summary)
        let blocker = try #require(try await db.reader.read { try Item.filter(Column("number") == 3).fetchOne($0) }?.summary)
        try await db.writer.write { db in
            try Outbox.enqueue(db, .setBlocking(.init(blocked: blocked, blocker: blocker, isBlocked: true, base: false)))
        }
        #expect(try blockers(db, of: "I_1") == [3])

        // The board is read again with the change unsent; what GitHub says of #1 doesn't take #3 away.
        try await engine.pull(projectId: FakeGitHub.projectId)
        #expect(try blockers(db, of: "I_1") == [3])
    }

    @Test func anIssuesPageReadsWhatBlocksItsSubIssues() async throws {
        let github = FakeGitHub([
            .init(contentId: "I_1", number: 1, itemId: "PVTI_1"),
            // Sub-issues that are on no board, so only their parent's page lists them.
            .init(contentId: "I_2", number: 2, parent: "I_1"),
            .init(contentId: "I_3", number: 3, parent: "I_1", blockedBy: ["I_2"]),
        ])
        let (db, engine) = try await makeEngine(github)
        try await engine.loadIssueDetail(contentId: "I_1")
        #expect(try blockers(db, of: "I_3") == [2])
        #expect(try blockers(db, of: "I_2").isEmpty)
    }

    // MARK: What the flag says

    private func link(_ number: Int, blocking issueId: String = "I_9", position: Int = 0) -> LinkedIssue {
        LinkedIssue(
            id: "I_\(number)", issueId: issueId, relation: .blockedBy, number: number, title: "Issue \(number)", state: "OPEN",
            repo: FakeGitHub.repo, url: nil, position: position
        )
    }

    @Test func theFlagNamesTheFirstBlockerAndCountsTheRest() {
        #expect(BlockerMark(blockers: [link(364)], count: 1).text == "#364")
        #expect(BlockerMark(blockers: [link(364), link(606, position: 1)], count: 2).text == "#364 +1")
        // GitHub counts one more than it shows.
        #expect(BlockerMark(blockers: [link(364)], count: 3).text == "#364 +2")
        // Until this device knows which issue blocks it, the flag shows alone.
        #expect(BlockerMark(blockers: [], count: 2).text == nil)
    }
}
