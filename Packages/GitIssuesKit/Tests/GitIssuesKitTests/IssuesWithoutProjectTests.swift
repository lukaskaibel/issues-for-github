import Foundation
import GRDB
import Testing
@testable import GitIssuesKit

@Suite("Issues on none of your boards")
struct IssuesWithoutProjectTests {
    static let projectId = "P1"
    static let statusField = "F-status"

    /// A board with one card, issue 1 of repository R1.
    private func makeDatabase() throws -> AppDatabase {
        let db = try AppDatabase.inMemory()
        try db.writer.write { db in
            try Project(
                id: Self.projectId, ownerLogin: "octo", ownerIsOrg: false, number: 1, title: "Board", url: "",
                closed: false, viewerCanUpdate: true, statusFieldId: Self.statusField
            ).insert(db)
            for (index, name) in ["Todo", "Done"].enumerated() {
                try FieldOption(
                    id: name.lowercased(), fieldId: Self.statusField, projectId: Self.projectId, kind: .status,
                    name: name, color: "GRAY", descr: "", position: index
                ).insert(db)
            }
            try Item(
                id: "item-1", projectId: Self.projectId, kind: .issue, position: 1024, statusId: "todo",
                contentId: "issue-1", number: 1, title: "On the board", body: "", state: "OPEN", repoId: "R1", repo: "octo/one"
            ).insert(db)
        }
        return db
    }

    /// An issue as a repository read or a search returns it.
    static func remote(_ number: Int, on projects: [String] = [], repoId: String = "R1", closedAt: Date? = nil) -> RemoteIssue {
        let contentId = "issue-\(number)"
        let item = Item(
            id: Item.idWithoutProject(contentId), projectId: nil, kind: .issue,
            position: Item.positionWithoutProject(updatedAt: Date()),
            contentId: contentId, number: number, title: "Issue \(number)", body: "",
            state: closedAt == nil ? "OPEN" : "CLOSED", stateReason: closedAt == nil ? nil : "COMPLETED",
            repoId: repoId, repo: repoId == "R1" ? "octo/one" : "octo/two", closedAt: closedAt
        )
        return RemoteIssue(item: item, projectIds: projects)
    }

    private func write(_ db: AppDatabase, _ issues: [RemoteIssue], prune: SyncEngine.Prune? = nil) throws -> Set<String> {
        try db.writer.write { try SyncEngine.writeIssuesWithoutProject($0, issues, prune: prune).staleBoards }
    }

    private func looseNumbers(_ db: AppDatabase) throws -> [Int] {
        try db.reader.read { db in
            try Item.filter(Column("projectId") == nil).fetchAll(db).compactMap(\.number).sorted()
        }
    }

    @Test func anIssueOnNoBoardBecomesAnItemWithoutAProject() throws {
        let db = try makeDatabase()
        try write(db, [Self.remote(2)])
        let item = try db.reader.read { try Item.fetchOne($0, key: "issue:issue-2") }
        #expect(item != nil)
        #expect(item?.projectId == nil)
        #expect(item?.isOnBoard == false)
    }

    @Test func anIssueOnOneOfYourBoardsIsLeftToTheBoard() throws {
        let db = try makeDatabase()
        // Issue 1 is on the board here already; issue 5 is on it on GitHub but not here yet.
        let stale = try write(db, [Self.remote(1, on: [Self.projectId]), Self.remote(5, on: [Self.projectId])])
        #expect(try looseNumbers(db).isEmpty)
        #expect(stale == [Self.projectId])
    }

    @Test func anIssueOnABoardYouDontHaveCountsAsOnNone() throws {
        let db = try makeDatabase()
        try write(db, [Self.remote(2, on: ["someone-elses-board"])])
        #expect(try looseNumbers(db) == [2])
    }

    @Test func aCardOnABoardIsNeverCopiedWithoutAProject() throws {
        let db = try makeDatabase()
        // Taken off the board on GitHub moments ago, or put on it here and not sent yet: the board decides.
        try write(db, [Self.remote(1)])
        #expect(try looseNumbers(db).isEmpty)
    }

    @Test func readingAWholeRepositoryDropsIssuesThatAreGone() throws {
        let db = try makeDatabase()
        try write(db, [Self.remote(2), Self.remote(3), Self.remote(4, repoId: "R2")])
        try write(db, [Self.remote(2)], prune: .repository("R1"))
        // Issue 4 belongs to another repository, which wasn't read.
        #expect(try looseNumbers(db) == [2, 4])
        try write(db, [], prune: .outside(["R1"]))
        #expect(try looseNumbers(db) == [2])
    }

    @Test func issuesClosedLongAgoDropOut() throws {
        let db = try makeDatabase()
        let longAgo = Date().addingTimeInterval(-40 * 24 * 3600)
        let lately = Date().addingTimeInterval(-3 * 24 * 3600)
        try write(db, [Self.remote(2, closedAt: longAgo), Self.remote(3, closedAt: lately)])
        #expect(try looseNumbers(db) == [3])
    }

    @Test func onlyIssuesOffYourBoardsThatChangedAreReadInFull() throws {
        let db = try makeDatabase()
        var known = Self.remote(2)
        known.item.remoteUpdatedAt = "2026-10-07T08:00:00Z"
        try write(db, [known])
        func ref(_ number: Int, _ updatedAt: String, closedAt: Date? = nil) -> IssueRef {
            IssueRef(contentId: "issue-\(number)", repoId: "R1", updatedAt: updatedAt, isClosed: closedAt != nil, closedAt: closedAt)
        }
        let wanted = try db.reader.read { db in
            try SyncEngine.issuesToRead(in: [
                ref(1, "2026-10-07T09:00:00Z"), // on the board here: the board reads it
                ref(2, "2026-10-07T08:00:00Z"), // here as it is on GitHub
                ref(3, "2026-10-07T09:00:00Z"), // new
                ref(4, "2026-10-07T09:00:00Z", closedAt: Date().addingTimeInterval(-40 * 24 * 3600)), // closed long ago
            ], db)
        }
        #expect(wanted == ["issue-3"])
    }

    @Test func puttingAnIssueOnABoardShowsAtOnceAndKeepsItsPlace() throws {
        let db = try makeDatabase()
        try write(db, [Self.remote(2)])
        let add = Mutation.addToProject(.init(
            itemId: "issue:issue-2", contentId: "issue-2", projectId: Self.projectId,
            statusFieldId: Self.statusField, statusId: "todo"
        ))
        try db.writer.write { try Outbox.enqueue($0, add) }
        let added = try db.reader.read { try Item.fetchOne($0, key: "issue:issue-2")! }
        #expect(added.projectId == Self.projectId)
        #expect(added.statusId == "todo")
        #expect(added.position > 1024)

        // Applied again over fresh data, it stays where it went; a repository read doesn't take it off again.
        try db.writer.write { try Outbox.rebase($0) }
        try write(db, [Self.remote(2)], prune: .repository("R1"))
        let again = try db.reader.read { try Item.fetchOne($0, key: "issue:issue-2")! }
        #expect(again.projectId == Self.projectId)
        #expect(again.position == added.position)

        // Once GitHub has added it, the card takes the project item's id.
        #expect(add.remapping(["issue:issue-2": "PVTI_2"]).itemId == "PVTI_2")
        #expect(add.referencedIds == ["issue-2"])
    }

    @Test func aBoardCardReplacesTheCopyWithoutAProject() throws {
        let db = try makeDatabase()
        try write(db, [Self.remote(2)])
        let remaps = try db.writer.write { db in
            try Item(
                id: "item-2", projectId: Self.projectId, kind: .issue, position: 2048, statusId: "todo",
                contentId: "issue-2", number: 2, title: "Issue 2", body: "", state: "OPEN", repoId: "R1", repo: "octo/one"
            ).insert(db)
            return try SyncEngine.dropCopiesWithoutProject(db)
        }
        #expect(remaps == ["issue:issue-2": "item-2"])
        #expect(try looseNumbers(db).isEmpty)
    }

    @Test func aNewIssueOnNoBoardComesFirst() throws {
        let db = try makeDatabase()
        let create = Mutation.CreateIssue(
            itemId: "local-item", contentId: "local-issue", projectId: nil, repoId: "R1", repo: "octo/one",
            title: "Brand new", body: "", assignees: [], labels: [], createdAt: Date()
        )
        try db.writer.write { try Outbox.enqueue($0, .createIssue(create)) }
        let item = try db.reader.read { try Item.fetchOne($0, key: "local-item")! }
        #expect(item.projectId == nil)
        #expect(item.statusId == nil)
        #expect(item.position < 0)
    }

    @Test func deletingAnIssueOnNoBoardRemovesIt() throws {
        let db = try makeDatabase()
        try write(db, [Self.remote(2)])
        try db.writer.write { db in
            try Outbox.enqueue(db, .deleteItem(.init(
                itemId: "issue:issue-2", projectId: nil, contentId: "issue-2", isDraft: false, label: "#2 Issue 2"
            )))
        }
        #expect(try looseNumbers(db).isEmpty)
    }
}
