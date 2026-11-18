import Foundation
import GRDB
import Testing
@testable import GitIssuesKit

@MainActor
@Suite("Project groups retain the board's status and iteration picker behavior")
struct ProjectFieldEditingTests {
    private func fixture(editable: Bool = true) throws -> (model: AppModel, field: ProjectField, target: ProjectFieldTarget) {
        let database = try AppDatabase.inMemory()
        let project = Project(id: "P", ownerLogin: "me", ownerIsOrg: false, number: 1, title: "Project", url: "",
                              closed: false, viewerCanUpdate: editable, statusFieldId: "F-status")
        let item = Item(id: "card", projectId: project.id, kind: .issue, position: 0, statusId: "ready",
                        contentId: "issue", number: 1, title: "An issue", body: "", state: "OPEN")
        // Status refreshes update FieldOption while the ProjectField's options can still describe an older sync.
        let field = ProjectField(id: "F-status", projectId: project.id, databaseId: 1, name: "Status", dataType: "SINGLE_SELECT", position: 0,
                                 options: [FieldChoice(id: "removed", name: "Old status", color: "GRAY")])
        try database.writer.write { db in
            try project.insert(db)
            try item.insert(db)
            try field.insert(db)
            try FieldOption(id: "ready", fieldId: field.id, projectId: project.id, kind: .status, name: "Ready",
                            color: "GREEN", descr: "Current option", position: 0).insert(db)
        }
        let model = AppModel(database: database, api: FakeGitHub([]).api)
        model.statusKinds.set(.completed, projectId: project.id, optionId: "ready")
        model.reloadNow()
        return (model, field, ProjectFieldTarget(item: item, fieldId: field.id))
    }

    @Test("Grouped status pickers use refreshed statuses and offer style editing only on writable projects", arguments: [true, false])
    func refreshedStatuses(editable: Bool) throws {
        let f = try fixture(editable: editable)
        let rows = f.model.projectFieldChoices(field: f.field, value: FieldValue(optionId: "ready"))
        #expect(rows.map(\.id) == ["", "ready"])
        let ready = try #require(rows.last)
        #expect(ready.title == "Ready")
        #expect(ready.subtitle == "Current option")
        #expect(ready.selected)
        #expect((ready.status != nil) == editable)
        if editable {
            #expect(ready.status?.chosenKind == .completed)
            #expect(ready.status?.color == "GREEN")
        }
        let create = f.model.newProjectStatusRow("Review", target: f.target)
        #expect((create != nil) == editable)
        #expect(create?.id == (editable ? AppModel.newStatusPrefix + "Review" : nil))
        #expect(f.model.newProjectStatusRow("Ready", target: f.target) == nil)
        var otherField = f.field
        otherField.id = "F-version"
        otherField.name = "Version"
        let generic = f.model.projectFieldChoices(field: otherField, value: nil)
        #expect(generic.map(\.id) == ["", "removed"])
        #expect(generic.allSatisfy { $0.status == nil })
        #expect(f.model.newProjectStatusRow("Review", target: ProjectFieldTarget(item: try #require(f.model.item(targetedBy: f.target)), fieldId: otherField.id)) == nil)
    }

    @Test("Grouped iteration pickers mark current and next, and keep an expired choice only when selected")
    func iterationChoices() throws {
        let model = try fixture().model
        let today = CalendarDay(year: 2026, month: 11, day: 10)
        let field = ProjectField(id: "F-sprint", projectId: "P", databaseId: 2, name: "Sprint", dataType: "ITERATION", position: 1,
                                 iterations: [
                                    IterationSpan(id: "old", title: "Previous", startDate: "2026-11-02", duration: 7, completed: true),
                                    IterationSpan(id: "current", title: "This week", startDate: "2026-11-09", duration: 7, completed: false),
                                    IterationSpan(id: "next", title: "Next week", startDate: "2026-11-16", duration: 7, completed: false),
                                 ])
        let rows = model.projectFieldChoices(field: field, value: nil, today: today)
        #expect(rows.map(\.id) == ["", "current", "next"])
        #expect(rows.map(\.subtitle) == [nil, String(localized: .currentIteration), String(localized: .nextIteration)])
        #expect(rows.first?.selected == true)
        let keepingOld = model.projectFieldChoices(field: field, value: FieldValue(iterationId: "old"), today: today)
        #expect(keepingOld.map(\.id) == ["", "old", "current", "next"])
        #expect(keepingOld.first(where: { $0.id == "old" })?.selected == true)
    }

    @Test("Multi-selection toggles preserve other choices and clear an empty selection")
    func selections() {
        let field = ProjectField(id: "F", projectId: "P", databaseId: 1, name: "Platforms", dataType: "MULTI_SELECT", position: 0)
        #expect(ProjectFieldEditing.picked("android", field: field, current: FieldValue(optionIds: ["ios"]))?.optionIds == ["android", "ios"])
        #expect(ProjectFieldEditing.picked("ios", field: field, current: FieldValue(optionIds: ["ios"])) == nil)
        #expect(ProjectFieldEditing.picked("", field: field, current: FieldValue(optionIds: ["ios"])) == nil)
    }

    @Test("A status picked for another project moves that card and leaves the issue open or closed", arguments: [false, true])
    func otherProjectStatus(closed: Bool) throws {
        let f = try fixture()
        try f.model.db.writer.write { db in
            try FieldOption(id: "done", fieldId: f.field.id, projectId: "P", kind: .status, name: "Done", color: "PURPLE", descr: "", position: 1).insert(db)
            try FieldOption(id: "todo", fieldId: f.field.id, projectId: "P", kind: .status, name: "Todo", color: "GRAY", descr: "", position: 2).insert(db)
            if closed { try db.execute(sql: "UPDATE item SET state = 'CLOSED'") }
        }
        f.model.statusKinds.set(.completed, projectId: "P", optionId: "done")
        f.model.statusKinds.set(.unstarted, projectId: "P", optionId: "todo")
        f.model.reloadNow()
        f.model.pickProjectField(closed ? "todo" : "done", target: f.target)
        let mutations = f.model.outbox.map(\.mutation)
        #expect(mutations.count == 1)
        guard case .setField(let change)? = mutations.first else { Issue.record("Expected a status change"); return }
        #expect(change.optionId == (closed ? "todo" : "done"))
        #expect(f.model.allItems.first?.isClosed == closed)
    }

    @Test("A multiple-choice field waits for its card to be read, so a pick can't replace what GitHub has")
    func unreadMultiSelect() throws {
        let f = try fixture()
        let field = ProjectField(id: "F-multi", projectId: "P", databaseId: 2, name: "Platforms", dataType: "MULTI_SELECT", position: 1,
                                 options: [FieldChoice(id: "ios", name: "iOS", color: "BLUE")])
        try f.model.db.writer.write { try field.insert($0) }
        f.model.reloadNow()
        let target = ProjectFieldTarget(item: try #require(f.model.allItems.first), fieldId: field.id)
        f.model.pickProjectField("ios", target: target)
        #expect(f.model.outbox.isEmpty)
        try f.model.db.writer.write { try $0.execute(sql: "UPDATE item SET remoteUpdatedAt = '2026-11-18T10:00:00Z'") }
        f.model.reloadNow()
        f.model.pickProjectField("ios", target: target)
        #expect(f.model.allItems.first?.fieldValues[field.id]?.optionIds == ["ios"])
        #expect(f.model.outbox.count == 1)
    }
}
