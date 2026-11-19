import Foundation
import GRDB
import Testing
@testable import GitIssuesKit

/// "Only My Issues" is kept in the defaults, so each test turns it off again before it returns, and none awaits while
/// it is on: no other test's model can start up in between and find it on.
@MainActor
@Suite("Only My Issues")
struct OnlyMineTests {
    static let me = Person(id: "U_me", login: "me")
    static let other = Person(id: "U_other", login: "other")

    private func item(_ id: String, _ assignees: [Person], epic: Bool = false, under parent: String? = nil, number: Int = 1) -> Item {
        var item = Item(id: id, projectId: "P", kind: .issue, position: Double(number), statusId: "todo",
                        contentId: "C_\(id)", number: number, title: id, body: "", state: "OPEN", repoId: "R1", repo: "octo/one")
        item.assignees = assignees
        if epic { item.issueType = "Epic" }
        item.parentId = parent.map { "C_\($0)" }
        return item
    }

    private func model(_ items: [Item]) throws -> AppModel {
        let database = try AppDatabase.inMemory()
        let project = Project(id: "P", ownerLogin: "octo", ownerIsOrg: false, number: 1, title: "Board", url: "",
                              closed: false, viewerCanUpdate: true, statusFieldId: "F")
        try database.writer.write { db in
            try project.insert(db)
            try FieldOption(id: "todo", fieldId: "F", projectId: "P", kind: .status, name: "Todo", color: "GRAY", descr: "", position: 0).insert(db)
            for item in items { try item.insert(db) }
            try KV.setViewer(db, Viewer(id: Self.me.id, login: Self.me.login))
        }
        let model = AppModel(database: database, api: FakeGitHub([]).api)
        model.onlyMine = false
        model.reloadNow()
        return model
    }

    private func ids(_ items: [Item]) -> Set<String> { Set(items.map(\.id)) }

    /// Yours alone, yours with someone else, someone else's, and nobody's on a board others work on too.
    private var shared: [Item] {
        [item("mine", [Self.me], number: 1), item("ours", [Self.me, Self.other], number: 2),
         item("theirs", [Self.other], number: 3), item("nobodys", [], number: 4)]
    }

    @Test("Yours is what My Issues lists: assigned to you, alone or with others, or to nobody where you work alone")
    func rule() {
        let solo: Set<String> = ["P"]
        #expect(AppModel.isMine(item("a", [Self.me]), login: "me", solo: []))
        #expect(AppModel.isMine(item("a", [Self.other, Self.me]), login: "me", solo: []))
        #expect(!AppModel.isMine(item("a", [Self.other]), login: "me", solo: solo))
        #expect(AppModel.isMine(item("a", []), login: "me", solo: solo))
        #expect(!AppModel.isMine(item("a", []), login: "me", solo: []))
        var loose = item("a", [])
        loose.projectId = nil
        #expect(!AppModel.isMine(loose, login: "me", solo: solo))
    }

    @Test("It narrows a board's pages, not My Issues or the Inbox")
    func pages() {
        #expect(AppModel.onlyMineApplies(to: .project("P")))
        #expect(AppModel.onlyMineApplies(to: .allIssues("P")))
        #expect(AppModel.onlyMineApplies(to: .milestone(projectId: "P", title: "1.0")))
        #expect(AppModel.onlyMineApplies(to: .roadmap("P")))
        #expect(!AppModel.onlyMineApplies(to: .myIssues))
        #expect(!AppModel.onlyMineApplies(to: .inbox))
    }

    @Test("On, a board shows only your issues; what it holds is still counted whole")
    func narrowsBoard() throws {
        let model = try model(shared)
        defer { model.onlyMine = false }
        #expect(ids(model.items(in: .project("P"))) == ["mine", "ours", "theirs", "nobodys"])
        model.onlyMine = true
        #expect(ids(model.items(in: .project("P"))) == ["mine", "ours"])
        #expect(ids(model.everyItem(in: .project("P"))) == ["mine", "ours", "theirs", "nobodys"])
        #expect(!model.onlyMineHidesEverything(in: .project("P")))
        model.onlyMine = false
        #expect(model.items(in: .project("P")).count == 4)
    }

    @Test("On a board only you work on, an issue assigned to nobody is yours")
    func soloBoard() throws {
        let model = try model([item("mine", [Self.me], number: 1), item("nobodys", [], number: 2)])
        defer { model.onlyMine = false }
        model.onlyMine = true
        #expect(ids(model.items(in: .project("P"))) == ["mine", "nobodys"])
    }

    @Test("An issue you take yourself off stays on the page until you go elsewhere")
    func keepsWhatYouLeft() throws {
        let model = try model(shared)
        defer { model.onlyMine = false }
        model.select(.project("P"))
        model.onlyMine = true
        var mine = try #require(model.item(id: "mine"))
        model.keepIfLeavingMine(mine, unassigning: Self.me)
        // Taking someone else off keeps nothing.
        model.keepIfLeavingMine(try #require(model.item(id: "ours")), unassigning: Self.other)
        mine.assignees = []
        try model.db.writer.write { try mine.update($0) }
        model.reloadNow()
        #expect(ids(model.items(in: .project("P"))) == ["mine", "ours"])
        model.select(.myIssues)
        model.select(.project("P"))
        #expect(ids(model.items(in: .project("P"))) == ["ours"])
    }

    @Test("The roadmap keeps the epics that are yours or hold something of yours, and the epics above them")
    func roadmap() throws {
        let model = try model([
            item("parent", [], epic: true, number: 1),
            item("holdsMine", [], epic: true, under: "parent", number: 2), item("task", [Self.me], under: "holdsMine", number: 3),
            item("holdsTheirs", [], epic: true, number: 4), item("work", [Self.other], under: "holdsTheirs", number: 5),
            item("assigned", [Self.me], epic: true, number: 6),
        ])
        defer { model.onlyMine = false }
        let all: Set<String> = ["parent", "holdsMine", "holdsTheirs", "assigned"]
        let shown = { (roadmap: Roadmap) in Set((roadmap.rows + roadmap.later).map(\.epic.id)) }
        #expect(shown(model.shownRoadmap(projectId: "P")) == all)
        model.onlyMine = true
        #expect(shown(model.shownRoadmap(projectId: "P")) == ["parent", "holdsMine", "assigned"])
        #expect(ids(model.items(in: .roadmap("P"))) == ["parent", "holdsMine", "assigned"])
        // The model's own roadmap stays whole, for what an epic's page says of its milestones.
        #expect(shown(model.roadmap(projectId: "P")) == all)
    }

    @Test("A page with issues, none of them yours, says so; a page with none doesn't")
    func emptyPage() throws {
        let theirs = try model([item("theirs", [Self.other])])
        defer { theirs.onlyMine = false }
        #expect(!theirs.onlyMineHidesEverything(in: .project("P")))
        theirs.onlyMine = true
        #expect(theirs.onlyMineHidesEverything(in: .project("P")))
        #expect(theirs.items(in: .project("P")).isEmpty)

        let empty = try model([])
        defer { empty.onlyMine = false }
        empty.onlyMine = true
        #expect(!empty.onlyMineHidesEverything(in: .project("P")))
    }
}
