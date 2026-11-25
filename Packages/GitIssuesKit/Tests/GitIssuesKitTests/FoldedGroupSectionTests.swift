import Foundation
import GRDB
import Testing
@testable import GitIssuesKit

/// A status whose issues all stand under a header, a parent's or an epic's, keeps its group in the list when the header
/// is folded: the header stays to show them again. Folded headers are kept in the defaults, so each test unfolds what it
/// folded before it returns.
@MainActor
@Suite("A list's status stays while its issues are folded under a header", .serialized)
struct FoldedGroupSectionTests {
    private func item(_ number: Int, status: String, parent: Int? = nil, epic: Bool = false) -> Item {
        var item = Item(id: "item-\(number)", projectId: "P", kind: .issue, position: Double(number), statusId: status,
                        contentId: "issue-\(number)", number: number, title: "Issue \(number)", body: "", state: "OPEN",
                        repoId: "R1", repo: "octo/one")
        item.parentId = parent.map { "issue-\($0)" }
        item.parentNumber = parent
        if epic { item.issueType = "Epic" }
        return item
    }

    private func model(_ items: [Item]) throws -> AppModel {
        let database = try AppDatabase.inMemory()
        let project = Project(id: "P", ownerLogin: "octo", ownerIsOrg: false, number: 1, title: "Board", url: "",
                              closed: false, viewerCanUpdate: true, statusFieldId: "F")
        try database.writer.write { db in
            try project.insert(db)
            try FieldOption(id: "todo", fieldId: "F", projectId: "P", kind: .status, name: "Todo", color: "GRAY", descr: "", position: 0).insert(db)
            try FieldOption(id: "done", fieldId: "F", projectId: "P", kind: .status, name: "Done", color: "PURPLE", descr: "", position: 1).insert(db)
            for item in items { try item.insert(db) }
        }
        let model = AppModel(database: database, api: FakeGitHub([]).api)
        model.onlyMine = false
        model.groupsByParent = true
        model.reloadNow()
        return model
    }

    @Test("Folding a parent's header over every issue of a status keeps the status and the header")
    func parentHeader() throws {
        // #9 is in Todo; its sub-issues #10 and #11 are the only issues in Done.
        let model = try model([item(9, status: "todo"), item(10, status: "done", parent: 9), item(11, status: "done", parent: 9)])
        defer { model.setGroup(.parent, "issue-9", folded: false) }
        #expect(model.sections(for: .project("P")).map(\.id) == ["todo", "done"])

        model.setGroup(.parent, "issue-9", folded: true)
        let done = try #require(model.sections(for: .project("P")).first { $0.id == "done" })
        #expect(done.items.isEmpty)
        #expect(done.count == 2)
        #expect(done.nesting.rows.map(\.id) == [Nesting.Group.id(parent: "issue-9")])
        #expect(done.nesting.groups.first?.folded == true)
    }

    @Test("Folding an epic's header over every issue of a status keeps the status and the header")
    func epicHeader() throws {
        // The epic #1 is in Todo; its issues #2 and #3 are the only issues in Done.
        let model = try model([item(1, status: "todo", epic: true), item(2, status: "done", parent: 1), item(3, status: "done", parent: 1)])
        defer { model.setGroup(.epic, "issue-1", folded: false) }
        model.setGroup(.epic, "issue-1", folded: true)
        let done = try #require(model.sections(for: .project("P")).first { $0.id == "done" })
        #expect(done.items.isEmpty)
        #expect(done.nesting.rows.map(\.id) == [Nesting.Group.id(epic: "issue-1")])
    }

    @Test("A status without issues still isn't listed")
    func emptyStatus() throws {
        let model = try model([item(9, status: "todo")])
        #expect(model.sections(for: .project("P")).map(\.id) == ["todo"])
    }
}
