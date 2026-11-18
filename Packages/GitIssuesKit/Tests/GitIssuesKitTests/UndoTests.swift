import Foundation
import GRDB
import Testing
@testable import GitIssuesKit

@Suite("Undo and redo of changes")
struct UndoChangesTests {
    private static let project = "P1"
    private static let statusField = "F-status"
    private static let priorityField = "F-priority"
    private static let iterationField = "F-iteration"
    private static let mira = Person(id: "U1", login: "mira")
    private static let theo = Person(id: "U2", login: "theo")
    private static let bug = LabelRef(id: "L1", name: "bug", color: "d73a4a")
    private static let ui = LabelRef(id: "L2", name: "ui", color: "1d76db")

    private static func item(_ number: Int) -> Item {
        Item(
            id: "item-\(number)", projectId: project, kind: .issue, position: Double(number) * 1024, statusId: "todo",
            contentId: "issue-\(number)", number: number, title: "Issue \(number)", body: "Text \(number)", state: "OPEN"
        )
    }

    private func makeDatabase() throws -> AppDatabase {
        let db = try AppDatabase.inMemory()
        try db.writer.write { db in
            try Project(
                id: Self.project, ownerLogin: "octo", ownerIsOrg: false, number: 1, title: "Board", url: "",
                closed: false, viewerCanUpdate: true, statusFieldId: Self.statusField
            ).insert(db)
            try ProjectField(
                id: Self.iterationField, projectId: Self.project, databaseId: 1, name: "Iteration", dataType: "ITERATION", position: 0
            ).insert(db)
            for number in 1...4 {
                var item = Self.item(number)
                if number == 1 {
                    item.assignees = [Self.mira]
                    item.labels = [Self.bug]
                    item.priorityId = "high"
                    item.dueDate = "2026-11-20"
                    item.milestoneId = "M1"
                    item.milestoneTitle = "1.0"
                    item.issueType = "Task"
                    item.issueTypeColor = "YELLOW"
                    item.fieldValues[Self.iterationField] = FieldValue(iterationId: "I1")
                }
                try item.insert(db)
            }
            try Milestone(
                id: "M1", repoId: "R1", repo: "octo/app", number: 1, title: "1.0", descr: "First", dueOn: "2026-12-01",
                state: "OPEN", closedAt: nil, url: nil
            ).insert(db)
        }
        return db
    }

    private func apply(_ changes: [Mutation], to db: AppDatabase) throws -> [Mutation]? {
        try db.writer.write { database in try Outbox.enqueueReversibly(database, changes) }
    }

    private func canApply(_ change: Mutation, in db: AppDatabase) throws -> Bool {
        try db.reader.read { database in try change.canStillApply(database) }
    }

    /// Does `change`, undoes it, redoes it, and undoes it again, reading what it is about each time.
    private func expectGoesBackAndForth<Value: Equatable>(
        _ change: Mutation, read: @escaping @Sendable (Database) throws -> Value,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let db = try makeDatabase()
        let original = try db.reader.read(read)
        let undo = try #require(try apply([change], to: db), sourceLocation: sourceLocation)
        let changed = try db.reader.read(read)
        #expect(changed != original, "the change does something", sourceLocation: sourceLocation)
        #expect(!undo.isEmpty, sourceLocation: sourceLocation)

        let redo = try #require(try apply(undo, to: db), sourceLocation: sourceLocation)
        #expect(try db.reader.read(read) == original, "undo brings it back", sourceLocation: sourceLocation)

        let undoAgain = try #require(try apply(redo, to: db), sourceLocation: sourceLocation)
        #expect(try db.reader.read(read) == changed, "redo does it again", sourceLocation: sourceLocation)

        _ = try apply(undoAgain, to: db)
        #expect(try db.reader.read(read) == original, "and it can be undone again", sourceLocation: sourceLocation)
    }

    private static func read(_ number: Int = 1) -> @Sendable (Database) throws -> Item? {
        { try Item.fetchOne($0, key: "item-\(number)") }
    }

    @Test func statusAndPriority() throws {
        try expectGoesBackAndForth(.setField(.init(
            itemId: "item-1", projectId: Self.project, fieldId: Self.statusField, kind: .status, optionId: "done", base: "todo"
        ))) { try Self.read()($0)?.statusId }
        try expectGoesBackAndForth(.setField(.init(
            itemId: "item-1", projectId: Self.project, fieldId: Self.priorityField, kind: .priority, optionId: nil, base: "high"
        ))) { try Self.read()($0)?.priorityId }
    }

    @Test func dueDateAndProjectField() throws {
        try expectGoesBackAndForth(.setDate(.init(itemId: "item-1", projectId: Self.project, date: nil, base: "2026-11-20"))) {
            try Self.read()($0)?.dueDate
        }
        try expectGoesBackAndForth(.setProjectField(.init(
            itemId: "item-1", projectId: Self.project, fieldId: Self.iterationField, fieldName: "Iteration",
            value: FieldValue(iterationId: "I2"), valueName: "Two", base: FieldValue(iterationId: "I1")
        ))) { try Self.read()($0)?.fieldValues[Self.iterationField] }
    }

    @Test func titleBodyAndState() throws {
        try expectGoesBackAndForth(.setTitle(.init(itemId: "item-1", contentId: "issue-1", value: "New", base: "Issue 1"))) {
            try Self.read()($0)?.title
        }
        try expectGoesBackAndForth(.setBody(.init(itemId: "item-1", contentId: "issue-1", value: "New", base: "Text 1"))) {
            try Self.read()($0)?.body
        }
        try expectGoesBackAndForth(.setState(.init(contentId: "issue-1", closed: true, reason: "COMPLETED"))) {
            let item = try Self.read()($0)
            return [item?.state, item?.stateReason]
        }
    }

    @Test func assigneesAndLabels() throws {
        try expectGoesBackAndForth(.editAssignees(.init(contentId: "issue-1", add: [Self.theo], remove: [Self.mira]))) {
            try Self.read()($0)?.assignees.map(\.id).sorted()
        }
        try expectGoesBackAndForth(.editLabels(.init(contentId: "issue-1", add: [Self.ui], remove: [Self.bug]))) {
            try Self.read()($0)?.labels.map(\.id).sorted()
        }
    }

    @Test func onlyWhatReallyChangedIsTakenBack() throws {
        let db = try makeDatabase()
        // Mira is assigned already, so taking this back must leave her assigned.
        let change = Mutation.editAssignees(.init(contentId: "issue-1", add: [Self.mira, Self.theo], remove: []))
        let undo = try #require(try apply([change], to: db))
        _ = try apply(undo, to: db)
        let assignees = try db.reader.read { database in try Self.read()(database)?.assignees.map(\.id) }
        #expect(assignees == ["U1"])
    }

    @Test func parentBlockerMilestoneAndEpic() throws {
        let child = try #require(Self.item(2).summary), parent = try #require(Self.item(1).summary)
        try expectGoesBackAndForth(.setParent(.init(child: child, parentId: "issue-1", parentNumber: 1, parentTitle: "Issue 1", base: nil))) {
            try Self.read(2)($0)?.parentId
        }
        try expectGoesBackAndForth(.setBlocking(.init(blocked: child, blocker: parent, isBlocked: true, base: false))) {
            try LinkedIssue.fetchCount($0)
        }
        try expectGoesBackAndForth(.setMilestone(.init(contentId: "issue-1", isPullRequest: false, milestoneId: nil, milestoneTitle: nil, base: "M1"))) {
            let item = try Self.read()($0)
            return [item?.milestoneId, item?.milestoneTitle]
        }
        try expectGoesBackAndForth(.setEpic(.init(
            contentId: "issue-1", repoId: "R1", repo: "octo/app", isEpic: true, label: LabelRef(id: "L3", name: "epic", color: "000000")
        ))) { try Self.read()($0)?.isEpic }
    }

    private static let toBug = Mutation.setIssueType(.init(
        contentId: "issue-1", typeId: "T2", name: "Bug", color: "RED", baseName: "Task", baseColor: "YELLOW", baseTypeId: "T1"
    ))

    @Test func issueType() throws {
        try expectGoesBackAndForth(Self.toBug) {
            let item = try Self.read()($0)
            return [item?.issueType, item?.issueTypeColor]
        }
        try expectGoesBackAndForth(.setIssueType(.init(contentId: "issue-2", typeId: "T2", name: "Bug", color: "RED"))) {
            try Self.read(2)($0)?.issueType
        }
    }

    @Test func undoingATypeSetsTheOneItHadByItsId() throws {
        let db = try makeDatabase()
        let undo = try #require(try apply([Self.toBug], to: db))
        guard case .setIssueType(let back)? = undo.first else {
            Issue.record("expected a change of the type")
            return
        }
        #expect(back.typeId == "T1" && back.name == "Task" && back.color == "YELLOW")
        #expect(back.baseName == "Bug" && back.baseTypeId == "T2")

        // Without the id of the type it replaces, GitHub couldn't be told to bring that type back.
        let unknown = Mutation.setIssueType(.init(contentId: "issue-1", typeId: "T3", name: "Feature", color: "BLUE", baseName: "Bug", baseColor: "RED"))
        #expect(try apply([unknown], to: db) == nil)
    }

    @Test func milestoneEditsTakeBackOnlyWhatChanged() throws {
        try expectGoesBackAndForth(.updateMilestone(.init(milestoneId: "M1", change: .init(title: "2.0", dueOn: "", state: "CLOSED")))) {
            let milestone = try Milestone.fetchOne($0, key: "M1")
            return [milestone?.title, milestone?.descr, milestone?.dueOn, milestone?.state]
        }
    }

    @Test func movesReturnToTheirPlaceInReverseOrder() throws {
        let order: @Sendable (Database) throws -> [Int] = { try Item.order(Column("position")).fetchAll($0).compactMap(\.number) }
        let db = try makeDatabase()
        let moves: [Mutation] = [
            .move(.init(itemId: "item-1", projectId: Self.project, afterItemId: "item-3")),
            .move(.init(itemId: "item-2", projectId: Self.project, afterItemId: "item-1")),
        ]
        let undo = try #require(try apply(moves, to: db))
        #expect(try db.reader.read(order) == [3, 1, 2, 4])
        let redo = try #require(try apply(undo, to: db))
        #expect(try db.reader.read(order) == [1, 2, 3, 4])
        _ = try apply(redo, to: db)
        #expect(try db.reader.read(order) == [3, 1, 2, 4])
    }

    @Test func aChangeThatChangesNothingLeavesNothingToUndo() throws {
        let db = try makeDatabase()
        let same = Mutation.setField(.init(
            itemId: "item-1", projectId: Self.project, fieldId: Self.statusField, kind: .status, optionId: "todo", base: "todo"
        ))
        #expect(try apply([same], to: db) == [])
    }

    @Test func whatGitHubCantBringBackIsNotUndoable() throws {
        let db = try makeDatabase()
        let comment = Mutation.addComment(.init(commentId: "C1", contentId: "issue-1", body: "Hi", author: Self.mira, createdAt: Date()))
        let deletion = Mutation.deleteItem(.init(itemId: "item-2", projectId: Self.project, contentId: "issue-2", isDraft: false, label: "#2"))
        let status = Mutation.setDate(.init(itemId: "item-1", projectId: Self.project, date: nil, base: "2026-11-20"))
        #expect(try apply([status, comment], to: db) == nil)
        #expect(try apply([deletion], to: db) == nil)
    }

    @Test func aChangeToADeletedIssueNoLongerApplies() throws {
        let db = try makeDatabase()
        let change = Mutation.setTitle(.init(itemId: "item-2", contentId: "issue-2", value: "Old", base: "Issue 2"))
        #expect(try canApply(change, in: db))
        try db.writer.write {
            try Outbox.enqueue($0, .deleteItem(.init(itemId: "item-2", projectId: Self.project, contentId: "issue-2", isDraft: false, label: "#2")))
        }
        #expect(try !canApply(change, in: db))
    }
}

@Suite("The undo history")
struct UndoHistoryTests {
    private typealias History = UndoHistory<String>

    private func run(_ history: inout History, _ mode: History.Mode, leaving opposite: String) -> History.Step? {
        guard let step = history.take(mode) else { return nil }
        history.begin(mode, step)
        history.record([opposite], name: .actionMoveIssue)
        let didSomething = history.finish()
        #expect(didSomething)
        return step
    }

    @Test func undoAndRedoHandTheStepBackAndForth() {
        var history = History()
        history.record(["back"], name: .actionChangeStatus)
        history.endGroup()
        #expect(run(&history, .undoing, leaving: "again")?.actions == ["back"])
        #expect(history.undoSteps.isEmpty)
        #expect(history.nextRedo?.actions == ["again"])
        // Keeps the name of what the user did, whatever undoing it is called.
        #expect(history.nextRedo?.name.key == LocalizedStringResource.actionChangeStatus.key)
        #expect(run(&history, .redoing, leaving: "back")?.actions == ["again"])
        #expect(history.redoSteps.isEmpty)
        #expect(history.nextUndo?.actions == ["back"])
    }

    @Test func somethingNewEndsWhatCouldBeRedone() {
        var history = History()
        history.record(["one"], name: .actionMoveIssue)
        history.endGroup()
        _ = run(&history, .undoing, leaving: "again")
        history.record(["two"], name: .actionMoveIssue)
        #expect(history.redoSteps.isEmpty)
    }

    @Test func whatOneMomentDoesIsOneStepLastFirst() {
        var history = History()
        history.record(["first"], name: .actionChangeStatus)
        history.record(["second"], name: .actionMoveIssue)
        history.endGroup()
        history.record(["third"], name: .actionMoveIssue)
        #expect(history.undoSteps.map(\.actions) == [["second", "first"], ["third"]])
    }

    @Test func aDescriptionSavedAgainStaysOneStepForAWhile() {
        var history = History()
        let start = Date()
        history.record(["original"], name: .actionEditDescription, mergeKey: "body:1", now: start)
        history.endGroup()
        history.record(["later"], name: .actionEditDescription, mergeKey: "body:1", now: start.addingTimeInterval(30))
        history.endGroup()
        #expect(history.undoSteps.map(\.actions) == [["original"]])
        // Another issue, or coming back much later, is a step of its own.
        history.record(["other"], name: .actionEditDescription, mergeKey: "body:2", now: start.addingTimeInterval(40))
        history.endGroup()
        history.record(["next day"], name: .actionEditDescription, mergeKey: "body:2", now: start.addingTimeInterval(86400))
        #expect(history.undoSteps.count == 3)
    }

    @Test func aNoticeTakesBackItsOwnStepEvenWithOthersAfterIt() {
        var history = History()
        let notice = UUID()
        history.record(["moved"], name: .actionMoveIssue)
        let tagged = history.tagLastStep(notice)
        #expect(tagged)
        history.endGroup()
        let taggedAfterwards = history.tagLastStep(UUID())
        #expect(!taggedAfterwards, "nothing was recorded in this moment")
        history.record(["later"], name: .actionEditTitle)
        history.endGroup()
        let taken = history.take(.undoing, tag: notice)
        #expect(taken?.actions == ["moved"])
        #expect(history.undoSteps.map(\.actions) == [["later"]])
    }

    @Test func aStepThatCantBeTakenBackAnyMoreIsForgotten() {
        var history = History()
        let tag = UUID()
        history.record(["archived"], name: .actionMoveIssue, tag: tag)
        history.endGroup()
        history.remove(tag: tag)
        #expect(history.nextUndo == nil)
    }

    @Test func aStepThatDidNothingIsNoticed() throws {
        var history = History()
        history.record(["gone"], name: .actionMoveIssue)
        history.endGroup()
        let taken = history.take(.undoing)
        let step = try #require(taken)
        history.begin(.undoing, step)
        let didSomething = history.finish()
        #expect(!didSomething)
        #expect(history.nextRedo == nil)
    }

    @Test func theHistoryKeepsTheLatestSteps() {
        var history = History()
        for index in 0..<(History.limit + 5) {
            history.record(["\(index)"], name: .actionMoveIssue)
            history.endGroup()
        }
        #expect(history.undoSteps.count == History.limit)
        #expect(history.undoSteps.first?.actions == ["5"])
    }
}
