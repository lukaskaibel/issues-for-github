import Foundation
import GRDB
import Testing
@testable import GitIssuesKit

@Suite("A project's saved views and its own fields")
struct ViewsTests {
    static let iteration: [String: Any] = [
        "__typename": "ProjectV2IterationField", "id": "F-it", "databaseId": 3, "name": "Iteration", "dataType": "ITERATION",
        "configuration": [
            "iterations": [["id": "c17", "title": "Cycle 17 · KW 42", "startDate": "2026-10-12", "duration": 7]],
            "completedIterations": [["id": "c16", "title": "Cycle 16 · KW 41", "startDate": "2026-10-05", "duration": 7]],
        ],
    ]
    static let workstream: [String: Any] = [
        "__typename": "ProjectV2SingleSelectField", "id": "F-ws", "databaseId": 4, "name": "Workstream", "dataType": "SINGLE_SELECT",
        "options": [["id": "w1", "name": "Quick Wins: Konto & Chat", "color": "BLUE", "description": ""]],
    ]
    static let title: [String: Any] = ["__typename": "ProjectV2Field", "id": "F-title", "databaseId": 5, "name": "Title", "dataType": "TITLE"]

    static func view(_ id: String, number: Int, name: String, layout: String = "TABLE_LAYOUT", filter: String,
                     group: String? = nil, columns: String? = nil, updatedAt: String = "2026-10-01T10:00:00Z") -> [String: Any] {
        [
            "id": id, "number": number, "name": name, "layout": layout, "filter": filter, "updatedAt": updatedAt,
            "fields": ["nodes": [["id": "F-title"], ["id": "F-it"]]],
            "groupByFields": ["nodes": group.map { [["id": $0]] } ?? []],
            "verticalGroupByFields": ["nodes": columns.map { [["id": $0]] } ?? []],
            "sortByFields": ["nodes": []],
        ]
    }

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

    private func setUp() -> FakeGitHub {
        let github = FakeGitHub([
            .init(contentId: "I_1", number: 1, itemId: "PVTI_1"),
            .init(contentId: "I_2", number: 2, itemId: "PVTI_2"),
        ])
        github.extraFields = [Self.title, Self.iteration, Self.workstream]
        github.cardValues = [
            "PVTI_1": [["iterationId": "c17", "field": ["id": "F-it"]], ["optionId": "w1", "field": ["id": "F-ws"]]],
            "PVTI_2": [["text": "Issue 2", "field": ["id": "F-title"]]],
        ]
        github.views = [
            Self.view("V1", number: 2, name: "Board", layout: "BOARD_LAYOUT", filter: "", columns: "F-status"),
            Self.view("V2", number: 3, name: "Diese Woche", layout: "BOARD_LAYOUT", filter: "iteration:@current", columns: "F-status"),
            Self.view("V3", number: 6, name: "Arbeitspakete", filter: "label:AP1,AP2", group: "F-ws"),
        ]
        return github
    }

    @Test("Fields with their options and iterations, views in their order, and the cards' values are read")
    func readsFieldsViewsAndValues() async throws {
        let github = setUp()
        let (db, engine) = try await makeEngine(github)
        try await engine.pull(projectId: FakeGitHub.projectId)

        let (fields, views, items) = try await db.reader.read { db in
            (
                try ProjectField.order(Column("position")).fetchAll(db),
                try ProjectView.order(Column("position")).fetchAll(db),
                try Item.order(Column("number")).fetchAll(db)
            )
        }
        #expect(fields.map(\.name) == ["Status", "Title", "Iteration", "Workstream"])
        let iteration = try #require(fields.first { $0.kind == .iteration })
        #expect(iteration.iterations.map(\.title) == ["Cycle 16 · KW 41", "Cycle 17 · KW 42"])
        #expect(iteration.iterations.map(\.completed) == [true, false])
        #expect(fields.first { $0.name == "Workstream" }?.options.map(\.name) == ["Quick Wins: Konto & Chat"])
        #expect(views.map(\.name) == ["Board", "Diese Woche", "Arbeitspakete"])
        #expect(views.map(\.number) == [2, 3, 6])
        #expect(views[0].columnFieldId == "F-status")
        #expect(views[2].groupByFieldId == "F-ws")
        #expect(views[2].visibleFieldIds == ["F-title", "F-it"])
        #expect(items[0].fieldValues["F-it"]?.iterationId == "c17")
        #expect(items[0].fieldValues["F-ws"]?.optionId == "w1")
        // Status has its own place, and the title isn't a value of the project's own.
        #expect(items[0].fieldValues["F-status"] == nil)
        #expect(items[1].fieldValues.isEmpty)
    }

    @Test("Only filters with words to search for are asked of GitHub, and again when the board changed")
    func asksGitHubOnlyWhereNeeded() async throws {
        let github = setUp()
        github.views.append(Self.view("V4", number: 7, name: "Chat", filter: "chat is:open"))
        github.matching = { filter in filter == "chat is:open" ? ["PVTI_2"] : [] }
        let (db, engine) = try await makeEngine(github)
        try await engine.pull(projectId: FakeGitHub.projectId)
        let asked = github.requests().filter { $0.hasPrefix("matching") }
        #expect(asked == ["matching: chat is:open"])
        let chat = try await db.reader.read { try ProjectView.fetchOne($0, key: "V4") }
        #expect(chat?.matches == ["PVTI_2"])
        #expect(chat?.matchesFilter == "chat is:open")

        // Nothing changed on the board: the answer stands.
        try await engine.pull(projectId: FakeGitHub.projectId)
        #expect(github.requests().filter { $0.hasPrefix("matching") }.isEmpty)

        github.addCard(.init(contentId: "I_3", number: 3, itemId: "PVTI_3"))
        try await engine.pull(projectId: FakeGitHub.projectId)
        #expect(github.requests().filter { $0.hasPrefix("matching") } == ["matching: chat is:open"])
    }

    @Test("A saved filter is written to GitHub and kept while GitHub's reads still show the old one")
    func savesAFilter() async throws {
        let github = setUp()
        let (db, engine) = try await makeEngine(github)
        try await engine.pull(projectId: FakeGitHub.projectId)
        _ = github.requests()

        try await engine.updateView("V2", change: .init(filter: "iteration:@current assignee:@me"))
        #expect(github.requests() == ["update view V2"])
        var week = try await db.reader.read { try ProjectView.fetchOne($0, key: "V2") }
        #expect(week?.filter == "iteration:@current assignee:@me")

        // GitHub at times answers with what a view was a moment ago.
        github.views[1]["filter"] = "iteration:@current"
        github.views[1]["updatedAt"] = "2026-10-01T10:00:00Z"
        try await engine.pull(projectId: FakeGitHub.projectId)
        week = try await db.reader.read { try ProjectView.fetchOne($0, key: "V2") }
        #expect(week?.filter == "iteration:@current assignee:@me")
    }

    @Test("A deleted view stays away, and one deleted on GitHub goes")
    func deletesAView() async throws {
        let github = setUp()
        let (db, engine) = try await makeEngine(github)
        try await engine.pull(projectId: FakeGitHub.projectId)

        let stale = github.views
        try await engine.deleteView("V3")
        // A read from before the deletion lists it still.
        github.views = stale
        try await engine.pull(projectId: FakeGitHub.projectId)
        var names = try await db.reader.read { try ProjectView.order(Column("position")).fetchAll($0).map(\.name) }
        #expect(names == ["Board", "Diese Woche"])

        github.views.removeAll { $0["id"] as? String == "V2" }
        try await engine.pull(projectId: FakeGitHub.projectId)
        names = try await db.reader.read { try ProjectView.order(Column("position")).fetchAll($0).map(\.name) }
        #expect(names == ["Board"])
    }

    @Test("Changing an iteration is applied here at once, sent with GitHub's iteration value, and kept over reads")
    func setsAnIteration() async throws {
        let db = try AppDatabase.inMemory()
        try await db.writer.write { db in
            try Project(id: "P1", ownerLogin: "octo", ownerIsOrg: false, number: 1, title: "Board", url: "", closed: false, viewerCanUpdate: true).insert(db)
            try Item(id: "PVTI_1", projectId: "P1", kind: .issue, position: 1, contentId: "I_1", number: 1, title: "One", body: "", state: "OPEN").insert(db)
            try Outbox.enqueue(db, .setProjectField(.init(
                itemId: "PVTI_1", projectId: "P1", fieldId: "F-it", fieldName: "Iteration",
                value: FieldValue(iterationId: "c17"), valueName: "Cycle 17", base: nil
            )))
        }
        var item = try await db.reader.read { try Item.fetchOne($0, key: "PVTI_1") }
        #expect(item?.fieldValues["F-it"]?.iterationId == "c17")
        #expect(item?.dirty == true)

        // A fresh read without the value doesn't undo the change while it waits.
        try await db.writer.write { db in
            var fresh = try Item.fetchOne(db, key: "PVTI_1")!
            fresh.fieldValues = [:]
            try fresh.update(db)
            try Outbox.rebase(db)
        }
        item = try await db.reader.read { try Item.fetchOne($0, key: "PVTI_1") }
        #expect(item?.fieldValues["F-it"]?.iterationId == "c17")

        // A second change folds into the first and keeps its base.
        try await db.writer.write { db in
            try Outbox.enqueue(db, .setProjectField(.init(
                itemId: "PVTI_1", projectId: "P1", fieldId: "F-it", fieldName: "Iteration", value: nil, valueName: nil,
                base: FieldValue(iterationId: "c17")
            )))
        }
        let entries = try await db.reader.read { try OutboxEntry.fetchAll($0) }
        #expect(entries.count == 1)
        if case .setProjectField(let change) = entries.first?.mutation {
            #expect(change.value == nil)
            #expect(change.base == nil)
        } else {
            Issue.record("Expected one change of the iteration")
        }
        let summary = try await db.reader.read { try entries[0].mutation.summary($0) }
        #expect(summary.number == "#1")
    }

    @Test("New views are asked of GitHub's REST API with every part, by the fields' numbers")
    func newViewBody() {
        let new = GitHubAPI.NewView(
            name: "Meine Woche", layout: .board, filter: "iteration:@current assignee:@me", visibleFields: [5, 3],
            groupBy: 4, columnsBy: 1, sortBy: [(field: 3, descending: true)]
        )
        let body = new.body
        #expect(body["name"] as? String == "Meine Woche")
        #expect(body["layout"] as? String == "board")
        #expect(body["filter"] as? String == "iteration:@current assignee:@me")
        #expect(body["visible_fields"] as? [Int] == [5, 3])
        #expect(body["vertical_group_by"] as? [Int] == [1])
        #expect(body["group_by"] as? [Int] == [4])
        #expect((body["sort_by"] as? [[Any]])?.first?.last as? String == "desc")
        let roadmap = GitHubAPI.NewView(name: "Roadmap", layout: .roadmap, filter: "", visibleFields: [5], columnsBy: 1).body
        #expect(roadmap["visible_fields"] == nil)
        #expect(roadmap["vertical_group_by"] == nil)
        #expect(roadmap["filter"] == nil)
    }

    @Test("Iterations count from the one under way; between two, the next one counts as current")
    func iterationOffsets() {
        let field = ProjectField(
            id: "F", projectId: "P", databaseId: nil, name: "Iteration", dataType: "ITERATION", position: 0,
            iterations: [
                IterationSpan(id: "a", title: "A", startDate: "2026-10-05", duration: 5, completed: true),
                IterationSpan(id: "b", title: "B", startDate: "2026-10-12", duration: 5, completed: false),
            ]
        )
        #expect(field.iteration(offset: 0, from: CalendarDay(year: 2026, month: 10, day: 13))?.id == "b")
        #expect(field.iteration(offset: -1, from: CalendarDay(year: 2026, month: 10, day: 13))?.id == "a")
        // The weekend after A: B comes next and counts as current.
        #expect(field.iteration(offset: 0, from: CalendarDay(year: 2026, month: 10, day: 10))?.id == "b")
        #expect(field.iteration(offset: 1, from: CalendarDay(year: 2026, month: 10, day: 13)) == nil)
    }
}

@Suite("How a view shows: progress, people, cycles and timelines")
@MainActor
struct ViewTypesTests {
    static func field(_ id: String, _ name: String, _ type: String, position: Int = 0) -> ProjectField {
        ProjectField(id: id, projectId: "P1", databaseId: position, name: name, dataType: type, position: position)
    }

    @Test("Groups of something that gets finished show progress, groups by person their load, others are lists")
    func groupStyles() {
        #expect(AppModel.groupStyle(of: Self.field("F1", "Parent issue", "PARENT_ISSUE")) == .progress)
        #expect(AppModel.groupStyle(of: Self.field("F2", "Milestone", "MILESTONE")) == .progress)
        #expect(AppModel.groupStyle(of: Self.field("F3", "Sprint", "ITERATION")) == .progress)
        #expect(AppModel.groupStyle(of: Self.field("F4", "Assignees", "ASSIGNEES")) == .people)
        #expect(AppModel.groupStyle(of: Self.field("F5", "Labels", "LABELS")) == .plain)
        #expect(AppModel.groupStyle(of: Self.field("F6", "Workstream", "SINGLE_SELECT")) == .plain)
    }

    @Test("Only groups with progress and nothing under way start folded")
    func foldedByDefault() {
        func section(_ style: GroupStyle, started: Int, total: Int) -> ListSection {
            let items = (0..<total).map { ProjectFilterTests.item($0) }
            return ListSection(
                id: "S", title: "S", glyph: .none, option: nil, items: items, nesting: Nesting.arrange(items, folded: []).nesting,
                style: style, progress: GroupProgress(done: 0, started: started, total: total)
            )
        }
        #expect(AppModel.foldsByDefault(section(.progress, started: 0, total: 3)))
        #expect(!AppModel.foldsByDefault(section(.progress, started: 1, total: 3)))
        #expect(!AppModel.foldsByDefault(section(.people, started: 0, total: 3)))
        #expect(!AppModel.foldsByDefault(section(.plain, started: 0, total: 3)))
        #expect(!AppModel.foldsByDefault(section(.progress, started: 0, total: 0)))
    }

    @Test("Stepping through iterations keeps GitHub's words relative to the one under way")
    func iterationTokens() {
        #expect(AppModel.iterationToken(offset: 0) == "@current")
        #expect(AppModel.iterationToken(offset: 1) == "@next")
        #expect(AppModel.iterationToken(offset: -1) == "@previous")
        #expect(AppModel.iterationToken(offset: 2) == "@current+2")
        #expect(AppModel.iterationToken(offset: -3) == "@current-3")
        #expect(AppModel.iterationValue(after: "@current", offset: 1, title: "Cycle 5") == "@next")
        #expect(AppModel.iterationValue(after: "@next", offset: 2, title: "Cycle 6") == "@current+2")
    }

    @Test("Stepping from an iteration named by its title names the next one by its title")
    func namedIterations() {
        #expect(AppModel.iterationValue(after: "Cycle 4", offset: 1, title: "Cycle 5") == "Cycle 5")
        let filter = ProjectFilter(#"iteration:"Cycle 4" is:open"#)
        let stepped = filter.replacing(0, with: filter.terms[0].changed { $0.values = ["Cycle 5"] })
        #expect(stepped.text == #"iteration:"Cycle 5" is:open"#)
    }

    @Test("A timeline finds start and end fields by name in several languages, else by their order")
    func dateFields() {
        let start = Self.field("S", "Start date", "DATE", position: 1)
        let target = Self.field("T", "Target date", "DATE", position: 2)
        let due = Self.field("D", "Due", "DATE", position: 3)
        var picked = AppModel.timelineDateFields([due, target, start])
        #expect(picked.start?.id == "S")
        #expect(picked.end?.id == "T")

        picked = AppModel.timelineDateFields([Self.field("B", "Beginn", "DATE"), Self.field("E", "Fällig am", "DATE")])
        #expect(picked.start?.id == "B")
        #expect(picked.end?.id == "E")

        picked = AppModel.timelineDateFields([Self.field("A", "Kickoff", "DATE", position: 1), Self.field("Z", "Launch", "DATE", position: 2)])
        #expect(picked.start?.id == "A")
        #expect(picked.end?.id == "Z")

        picked = AppModel.timelineDateFields([due, Self.field("X", "Title", "TITLE")])
        #expect(picked.start == nil)
        #expect(picked.end?.id == "D")

        picked = AppModel.timelineDateFields([Self.field("X", "Title", "TITLE")])
        #expect(picked.start == nil && picked.end == nil)
    }
}
