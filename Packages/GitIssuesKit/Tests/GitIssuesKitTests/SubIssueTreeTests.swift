import Foundation
import GRDB
import Testing
@testable import GitIssuesKit

/// An issue's list of sub-issues as a tree: a sub-issue with sub-issues of its own shows how far they are, and they
/// unfold under it, read from GitHub when they first show.
@Suite("Sub-issues of sub-issues")
struct SubIssueTreeTests {
    // MARK: Reading them

    /// #1 has the sub-issue #2, which has #3 and #4; #3 has #5. #1's list has been read, before GitHub counted
    /// sub-issues' own sub-issues.
    private func makeEngine() async throws -> (FakeGitHub, AppDatabase, SyncEngine) {
        let github = FakeGitHub([
            .init(contentId: "issue-1", number: 1),
            .init(contentId: "issue-2", number: 2, parent: "issue-1"),
            .init(contentId: "issue-3", number: 3, parent: "issue-2"),
            .init(contentId: "issue-4", number: 4, parent: "issue-2", closed: true),
            .init(contentId: "issue-5", number: 5, parent: "issue-3"),
        ])
        let db = try AppDatabase.inMemory()
        try await db.writer.write { db in
            try SubIssue(id: "issue-2", parentId: "issue-1", number: 2, title: "Issue 2", state: "OPEN", position: 0).insert(db)
        }
        let status = await MainActor.run { SyncStatus() }
        return (github, db, SyncEngine(db: db, api: github.api, status: status))
    }

    private func list(_ db: AppDatabase, of parentId: String) throws -> [SubIssue] {
        try db.reader.read { try SubIssue.filter(Column("parentId") == parentId).order(Column("position")).fetchAll($0) }
    }

    @Test func aSubIssuesOwnSubIssuesAreReadWithHowFarTheirsAre() async throws {
        let (github, db, engine) = try await makeEngine()
        try await engine.loadSubIssues(parentId: "issue-2")
        #expect(github.requests() == ["sub-issues issue-2"])

        let subs = try list(db, of: "issue-2")
        #expect(subs.map(\.number) == [3, 4])
        #expect(subs.map(\.isClosed) == [false, true])
        #expect(subs.map(\.subTotal) == [1, 0])
        #expect(subs.map(\.subCompleted) == [0, 0])
        // Where #1 lists #2, it now knows how far #2's sub-issues are.
        let two = try list(db, of: "issue-1").first
        #expect(two?.subTotal == 2)
        #expect(two?.subCompleted == 1)
    }

    @Test func aListReadBeforeIsReadAgainWhenGitHubCountsOtherwise() async throws {
        let (github, db, engine) = try await makeEngine()
        try await engine.loadSubIssues(parentId: "issue-2")
        try await engine.loadSubIssues(parentId: "issue-1")
        // Nothing changed: #2's list matches its count and isn't read again.
        _ = github.requests()
        try await engine.loadSubIssues(parentId: "issue-1")
        #expect(github.requests() == ["sub-issues issue-1"])

        // Closed and added on GitHub while #2 was folded: its count says so, and its list is read again.
        github.setClosed("issue-3", true)
        github.addIssue(.init(contentId: "issue-6", number: 6, parent: "issue-2"))
        try await engine.loadSubIssues(parentId: "issue-1")
        #expect(github.requests() == ["sub-issues issue-1", "sub-issues issue-2"])
        let subs = try list(db, of: "issue-2")
        #expect(subs.map(\.number) == [3, 4, 6])
        #expect(subs.map(\.isClosed) == [true, true, false])
    }

    // MARK: Changes made here

    @Test func movingAnIssueKeepsTheCountsWhereItsParentsAreListed() throws {
        let db = try AppDatabase.inMemory()
        try db.writer.write { db in
            // #1 lists #2 and #3; #2 has the sub-issue #4, which has two of its own, one of them closed.
            for (position, number) in [2, 3].enumerated() {
                try SubIssue(
                    id: "issue-\(number)", parentId: "issue-1", number: number, title: "Issue \(number)", state: "OPEN",
                    position: position, subTotal: number == 2 ? 1 : 0, subCompleted: 0
                ).insert(db)
            }
            try SubIssue(
                id: "issue-4", parentId: "issue-2", number: 4, title: "Issue 4", state: "OPEN", position: 0,
                subTotal: 2, subCompleted: 1
            ).insert(db)
        }
        let move = Mutation.setParent(.init(
            child: IssueSummary(contentId: "issue-4", number: 4, title: "Issue 4", state: "OPEN"),
            parentId: "issue-3", parentNumber: 3, parentTitle: "Issue 3", base: "issue-2"
        ))
        try db.writer.write { try Outbox.enqueue($0, move) }
        var subs = try list(db, of: "issue-1")
        #expect(subs.map(\.subTotal) == [0, 1])
        // It takes how far its own sub-issues are along.
        let moved = try list(db, of: "issue-3").first
        #expect(moved?.subTotal == 2)
        #expect(moved?.subCompleted == 1)

        // Applied again over the same data, nothing is counted twice.
        try db.writer.write { try Outbox.rebase($0) }
        subs = try list(db, of: "issue-1")
        #expect(subs.map(\.subTotal) == [0, 1])
    }

    // MARK: The tree

    private static func sub(_ number: Int, of parent: Int, closed: Bool = false, total: Int? = nil, completed: Int? = nil) -> SubIssue {
        SubIssue(
            id: "issue-\(number)", parentId: "issue-\(parent)", number: number, title: "Issue \(number)",
            state: closed ? "CLOSED" : "OPEN", position: number, subTotal: total, subCompleted: completed
        )
    }

    /// #1 has #2 and #3; #2 has #4 and #5; #4 has #6.
    private static let tree: [String: [SubIssue]] = [
        "issue-1": [sub(2, of: 1, total: 2, completed: 1), sub(3, of: 1, total: 0, completed: 0)],
        "issue-2": [sub(4, of: 2, total: 1, completed: 0), sub(5, of: 2, closed: true, total: 0, completed: 0)],
        "issue-4": [sub(6, of: 4, total: 0, completed: 0)],
    ]

    private func lines(unfolded: Set<String>, loading: Set<String> = [], tree: [String: [SubIssue]] = Self.tree) -> [SubIssueLine] {
        SubIssueLine.lines(tree["issue-1"] ?? [], of: "issue-1", tree: tree, unfolded: unfolded, loading: loading, card: { _ in nil })
    }

    @Test func subIssuesWithTheirOwnShowHowFarTheyAreAndStayFoldedAtFirst() {
        let shown = lines(unfolded: [])
        #expect(shown.map(\.sub.number) == [2, 3])
        #expect(shown.map(\.progress) == [.init(done: 1, total: 2), nil])
        #expect(shown.map(\.unfolded) == [false, false])
    }

    @Test func unfoldedSubIssuesShowTheirOwnUnderThemLevelByLevel() {
        let shown = lines(unfolded: ["issue-2", "issue-4"])
        #expect(shown.map(\.sub.number) == [2, 4, 6, 5, 3])
        #expect(shown.map(\.place.depth) == [0, 1, 2, 1, 0])
        // #4's line goes on to #5 past #6; #6 is the last under #4, #5 the last under #2.
        #expect(shown.map(\.place.continues) == [[], [true], [true, false], [false], []])
        #expect(shown.map(\.childrenShow) == [true, true, false, false, false])
        #expect(Set(shown.map(\.id)).count == shown.count)
    }

    @Test func unfoldedSubIssuesFollowThePickedOrderToo() {
        // The open ones first, as every order but GitHub's has them.
        let shown = SubIssueLine.lines(
            Self.tree["issue-1"] ?? [], of: "issue-1", tree: Self.tree, unfolded: ["issue-2"], loading: [], card: { _ in nil },
            arrange: { $0.sorted { !$0.isClosed && $1.isClosed } }
        )
        #expect(shown.map(\.sub.number) == [2, 4, 5, 3])
        var reversed = Self.tree
        reversed["issue-2"] = reversed["issue-2"]?.reversed()
        let arranged = SubIssueLine.lines(
            Self.tree["issue-1"] ?? [], of: "issue-1", tree: reversed, unfolded: ["issue-2"], loading: [], card: { _ in nil },
            arrange: { $0.sorted { !$0.isClosed && $1.isClosed } }
        )
        #expect(arranged.map(\.sub.number) == [2, 4, 5, 3])
    }

    @Test func aFoldedSubIssueHidesEverythingBelowIt() {
        // #4 stays unfolded, but under a folded #2 it doesn't show.
        #expect(lines(unfolded: ["issue-4"]).map(\.sub.number) == [2, 3])
    }

    @Test func anUnfoldedSubIssueWaitsForItsListTheFirstTime() {
        var tree = Self.tree
        tree["issue-2"] = nil
        let shown = lines(unfolded: ["issue-2"], loading: ["issue-2"], tree: tree)
        #expect(shown.map(\.sub.number) == [2, 3])
        #expect(shown.first?.waiting == true)
        #expect(shown.first?.childrenShow == false)
        // GitHub's count stands in until the list is read.
        #expect(shown.first?.progress == .init(done: 1, total: 2))
    }

    @Test func progressFollowsTheListOnceReadInFull() {
        let children = [Self.sub(4, of: 2, closed: true), Self.sub(5, of: 2, closed: true)]
        // Both closed here, before GitHub's count knows.
        #expect(SubIssueLine.Progress.of(Self.sub(2, of: 1, total: 2, completed: 1), children: children, card: nil) == .init(done: 2, total: 2))
        // A list missing one GitHub counts is stale: the count wins.
        #expect(SubIssueLine.Progress.of(Self.sub(2, of: 1, total: 3, completed: 1), children: children, card: nil) == .init(done: 1, total: 3))
        // Not counted yet: its card's count stands in.
        var card = OutboxTests.item(2)
        card.subTotal = 4
        card.subCompleted = 3
        #expect(SubIssueLine.Progress.of(Self.sub(2, of: 1), children: [], card: card) == .init(done: 3, total: 4))
        #expect(SubIssueLine.Progress.of(Self.sub(2, of: 1, total: 0, completed: 0), children: [], card: card) == nil)
    }

    @Test func anIssueMetAgainBelowItselfIsNotUnfoldedTwice() {
        // Stale data that loops: #2 lists #1, whose list this is.
        var tree = Self.tree
        tree["issue-2"] = [Self.sub(1, of: 2, total: 1, completed: 0)]
        let shown = lines(unfolded: ["issue-1", "issue-2"], tree: tree)
        #expect(shown.map(\.sub.number) == [2, 1, 3])
        #expect(shown[1].unfolded == false)
    }

    @MainActor
    @Test func theDetailReadsTheWholeTreeFromTheDatabase() throws {
        let db = try AppDatabase.inMemory()
        try db.writer.write { db in
            for subs in Self.tree.values {
                for sub in subs { try sub.insert(db) }
            }
            // Stale data that loops back to #1 is read once.
            try Self.sub(1, of: 6).insert(db)
        }
        let detail = IssueDetailModel(contentId: "issue-1", db: db)
        #expect(detail.subIssues.map(\.number) == [2, 3])
        #expect(detail.subIssues(of: "issue-2").map(\.number) == [4, 5])
        #expect(detail.subIssues(of: "issue-4").map(\.number) == [6])
        #expect(detail.subIssues(of: "issue-6").map(\.number) == [1])
    }
}
