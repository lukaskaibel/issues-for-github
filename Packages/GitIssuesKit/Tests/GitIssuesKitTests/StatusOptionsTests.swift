import Foundation
import GRDB
import SwiftUI
import Testing
@testable import GitIssuesKit

@Suite("A change to a board's statuses is made on GitHub's statuses as they are now")
struct OptionMergeTests {
    private func option(_ id: String?, _ name: String, _ color: String = "GRAY") -> RemoteOption {
        RemoteOption(id: id, name: name, color: color)
    }

    private let base = [
        RemoteOption(id: "a", name: "Todo", color: "GRAY"),
        RemoteOption(id: "b", name: "In Progress", color: "YELLOW"),
        RemoteOption(id: "c", name: "Done", color: "PURPLE"),
    ]

    @Test("a status added on GitHub stays when one is added here; one added in the middle goes after the one before it")
    func keepsTheirAddition() {
        let theirs = base + [option("d", "QA")]
        let mine = base + [option(nil, "Review")]
        let merged = OptionMerge.merge(base: base, mine: mine, theirs: theirs)
        #expect(merged.map(\.name) == ["Todo", "In Progress", "Done", "QA", "Review"])
        #expect(merged.map(\.id) == ["a", "b", "c", "d", nil])
        var between = base
        between.insert(option(nil, "Review"), at: 2)
        #expect(OptionMerge.merge(base: base, mine: between, theirs: theirs).map(\.name) == ["Todo", "In Progress", "Review", "Done", "QA"])
    }

    @Test("a status added on GitHub between two others stays there when one is removed here")
    func keepsTheirAdditionInPlace() {
        var theirs = base
        theirs.insert(option("d", "QA"), at: 2)
        let mine = [base[0], base[2]]
        let merged = OptionMerge.merge(base: base, mine: mine, theirs: theirs)
        #expect(merged.map(\.id) == ["a", "d", "c"])
    }

    @Test("a status removed on GitHub stays removed, even when renamed here")
    func theirRemovalWins() {
        let theirs = [base[0], base[2]]
        var mine = base
        mine[1].name = "Doing"
        #expect(OptionMerge.merge(base: base, mine: mine, theirs: theirs).map(\.id) == ["a", "c"])
    }

    @Test("a status removed here goes, even when GitHub recoloured it")
    func myRemovalWins() {
        var theirs = base
        theirs[1].color = "RED"
        let mine = [base[0], base[2]]
        #expect(OptionMerge.merge(base: base, mine: mine, theirs: theirs).map(\.id) == ["a", "c"])
    }

    @Test("a rename here and a new colour on GitHub both stay")
    func fieldsMerge() {
        var theirs = base
        theirs[1].color = "RED"
        theirs[2].descr = "Shipped"
        var mine = base
        mine[1].name = "Doing"
        let merged = OptionMerge.merge(base: base, mine: mine, theirs: theirs)
        #expect(merged[1] == option("b", "Doing", "RED"))
        #expect(merged[2].descr == "Shipped")
    }

    @Test("a new status whose name GitHub has by now isn't made twice")
    func adoptsByName() {
        let theirs = base + [option("d", "QA", "BLUE")]
        let mine = base + [option(nil, "qa ", "PINK")]
        let merged = OptionMerge.merge(base: base, mine: mine, theirs: theirs)
        #expect(merged.map(\.id) == ["a", "b", "c", "d"])
        #expect(merged.last?.color == "BLUE")
    }

    @Test("columns moved here keep their new order; one added on GitHub goes after the one before it there")
    func myOrderWithTheirAddition() {
        var theirs = base
        theirs.insert(option("d", "QA"), at: 2)
        let mine = [base[2], base[0], base[1]]
        #expect(OptionMerge.merge(base: base, mine: mine, theirs: theirs).map(\.id) == ["c", "a", "b", "d"])
    }

    @Test("columns moved on GitHub keep that order when a status is added here after In Progress")
    func theirOrderWithMyAddition() {
        let theirs = [base[2], base[0], base[1]]
        var mine = base
        mine.insert(option(nil, "Review"), at: 2)
        #expect(OptionMerge.merge(base: base, mine: mine, theirs: theirs).map(\.name) == ["Done", "Todo", "In Progress", "Review"])
    }

    @Test("nothing changed on either side sends GitHub's list as it is")
    func unchanged() {
        #expect(OptionMerge.merge(base: base, mine: base, theirs: base) == base)
    }
}

@Suite("Making a status where it is picked")
@MainActor
struct NewStatusTests {
    private func status(_ id: String, _ name: String, _ color: String = "GRAY") -> FieldOption {
        FieldOption(id: id, fieldId: "F", projectId: "P", kind: .status, name: name, color: color, descr: "", position: 0)
    }

    @Test("a new status goes after the board's statuses of its kind, or after those of the kinds before it")
    func place() {
        let board = [status("1", "Backlog"), status("2", "Todo"), status("3", "In Progress", "YELLOW"), status("4", "Done", "PURPLE")]
        #expect(AppModel.newStatusIndex(kind: .started, among: board) == 3)
        #expect(AppModel.newStatusIndex(kind: .unstarted, among: board) == 2)
        #expect(AppModel.newStatusIndex(kind: .canceled, among: board) == 4)
        #expect(AppModel.newStatusIndex(kind: .backlog, among: Array(board.dropFirst())) == 0)
        #expect(AppModel.newStatusColor(kind: .started, among: board) == "YELLOW")
        #expect(AppModel.newStatusColor(kind: .canceled, among: board) == "GRAY")
    }

    @Test("a kind chosen in the app wins over the name's")
    func chosenKind() {
        var qa = status("5", "QA")
        #expect(qa.statusCategory == .started)
        qa.chosenKind = .completed
        #expect(qa.statusCategory == .completed)
        #expect(qa.statusCategory.closeReason == "COMPLETED")
    }

    @Test("kinds are kept per project and status; the name's kind again when set back")
    func kindsStore() {
        let kinds = StatusKinds(persistent: false)
        var changes = 0
        kinds.onChange = { changes += 1 }
        kinds.set(.completed, projectId: "P", optionId: "5")
        #expect(kinds.kind(projectId: "P", optionId: "5") == .completed)
        #expect(kinds.kind(projectId: "Q", optionId: "5") == nil)
        kinds.set(nil, projectId: "P", optionId: "5")
        #expect(kinds.kind(projectId: "P", optionId: "5") == nil)
        #expect(changes == 2)
    }

    @Test("the create row comes after statuses that contain the typed text")
    func rowOrder() {
        func row(_ name: String) -> PickerItem { PickerItem(id: name, title: name, icon: AnyView(EmptyView())) }
        let make = PickerItem(id: AppModel.newStatusPrefix + "Rev", title: "Create status “Rev”", icon: AnyView(EmptyView()), creates: true)
        let rows = [row("In Review"), row("Ready for verification"), row("Done")]
        #expect(matching("Rev", in: rows, creating: make).map(\.id) == ["In Review", "new-status:Rev", "Ready for verification"])
        #expect(AppModel.newStatusName("new-status:Rev") == "Rev")
        #expect(AppModel.newStatusName("todo") == nil)
    }
}

private extension Item {
    func with(statusId: String?) -> Item {
        var copy = self
        copy.statusId = statusId
        return copy
    }
}

@Suite("Saving a board's statuses")
struct SavingStatusesTests {
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

    private func names(_ db: AppDatabase) throws -> [String] {
        try db.reader.read { db in
            try FieldOption.filter(Column("fieldId") == "F-status").order(Column("position")).fetchAll(db).map(\.name)
        }
    }

    private static let board: [FakeGitHub.Issue] = [.init(contentId: "I_1", number: 1, itemId: "PVTI_1")]

    @Test("a status added on github.com since the last read survives a status added here")
    func keepsWebsiteStatus() async throws {
        let github = FakeGitHub(Self.board)
        let (db, engine) = try await makeEngine(github)
        try await engine.pull(projectId: FakeGitHub.projectId)
        #expect(try names(db) == ["Todo"])
        github.statusOptions.append(["id": "web", "name": "From the website", "color": "BLUE", "description": ""])
        let base = [RemoteOption(id: "todo", name: "Todo", color: "GRAY")]
        let saved = try await engine.updateOptions(
            projectId: FakeGitHub.projectId, fieldId: "F-status", kind: .status, base: base,
            options: base + [RemoteOption(id: nil, name: "QA", color: "GRAY")]
        )
        #expect(saved.map(\.name) == ["Todo", "From the website", "QA"])
        #expect(github.statusOptions.compactMap { $0["id"] as? String }.prefix(2) == ["todo", "web"])
        #expect(try names(db) == ["Todo", "From the website", "QA"])
    }

    @Test("cards shown in a status before GitHub saved it get the saved one; other cards keep theirs")
    func handsOverPlaceholders() async throws {
        let github = FakeGitHub(Self.board)
        let (db, engine) = try await makeEngine(github)
        try await engine.pull(projectId: FakeGitHub.projectId)
        let local = LocalID.make()
        let waiting = LocalID.make()
        try await db.writer.write { db in
            try FieldOption(
                id: local, fieldId: "F-status", projectId: FakeGitHub.projectId, kind: .status, name: "QA", color: "GRAY", descr: "", position: 1
            ).insert(db)
            try FieldOption(
                id: waiting, fieldId: "F-status", projectId: FakeGitHub.projectId, kind: .status, name: "Later", color: "GRAY", descr: "", position: 2
            ).insert(db)
            try db.execute(sql: "UPDATE item SET statusId = ? WHERE id = 'PVTI_1'", arguments: [local])
        }
        let base = [RemoteOption(id: "todo", name: "Todo", color: "GRAY")]
        let saved = try await engine.updateOptions(
            projectId: FakeGitHub.projectId, fieldId: "F-status", kind: .status, base: base,
            options: base + [RemoteOption(id: nil, name: "QA", color: "GRAY")], placeholders: [local: "QA"]
        )
        let qa = try #require(saved.last?.id)
        let statusId = try await db.reader.read { try String.fetchOne($0, sql: "SELECT statusId FROM item WHERE id = 'PVTI_1'") }
        #expect(statusId == qa)
        // Another status still on its way keeps its place-holding row.
        #expect(try names(db) == ["Todo", "QA", "Later"])
    }

    @Test("a change giving a status still being made waits for it, then gives the saved one; dropped if it fails")
    func waitingChange() async throws {
        let github = FakeGitHub(Self.board)
        let (db, engine) = try await makeEngine(github)
        try await engine.pull(projectId: FakeGitHub.projectId)
        let local = LocalID.make()
        try await db.writer.write { db in
            try FieldOption(
                id: local, fieldId: "F-status", projectId: FakeGitHub.projectId, kind: .status, name: "QA", color: "GRAY", descr: "", position: 1
            ).insert(db)
            try Outbox.enqueue(db, .setField(.init(
                itemId: "PVTI_1", projectId: FakeGitHub.projectId, fieldId: "F-status", kind: .status, optionId: local, base: "todo"
            )))
        }
        try await engine.pushPending()
        #expect(github.fieldWrites().isEmpty, "Nothing is sent with an id GitHub doesn't know")
        let base = [RemoteOption(id: "todo", name: "Todo", color: "GRAY")]
        let saved = try await engine.updateOptions(
            projectId: FakeGitHub.projectId, fieldId: "F-status", kind: .status, base: base,
            options: base + [RemoteOption(id: nil, name: "QA", color: "GRAY")], placeholders: [local: "QA"]
        )
        try await engine.pushPending()
        let qa = try #require(saved.last?.id)
        #expect(github.fieldWrites().map { $0.variables["o"] as? String } == [qa])

        // One that couldn't be made: the change waiting for it goes, and the card shows its status again.
        let failed = LocalID.make()
        try await db.writer.write { db in
            try Outbox.enqueue(db, .setField(.init(
                itemId: "PVTI_1", projectId: FakeGitHub.projectId, fieldId: "F-status", kind: .status, optionId: failed, base: qa
            )))
        }
        let before = try await db.reader.read { try Item.fetchOne($0, key: "PVTI_1") }
        try await db.writer.write { db in
            try SyncEngine.dropStatus(db, localId: failed, restoring: [try #require(before).with(statusId: qa)])
        }
        let after = try await db.reader.read { db in
            (try Item.fetchOne(db, key: "PVTI_1")?.statusId, try OutboxEntry.fetchCount(db))
        }
        #expect(after.0 == qa)
        try await engine.pushPending()
        #expect(github.fieldWrites().count == 1, "Only the change that had its status was sent")
    }

    @Test("a status added on github.com shows when statuses are about to be picked, read at most every ten seconds")
    func refreshesOnTheirOwn() async throws {
        let github = FakeGitHub(Self.board)
        let (db, engine) = try await makeEngine(github)
        try await engine.pull(projectId: FakeGitHub.projectId)
        try await db.writer.write { try $0.execute(sql: "UPDATE project SET statusFieldId = 'F-status'") }
        github.statusOptions.append(["id": "web", "name": "From the website", "color": "BLUE", "description": ""])
        // Just read by the pull: not again yet.
        _ = github.requests()
        await engine.refreshOptions(projectId: FakeGitHub.projectId)
        #expect(!github.requests().contains("options"))
        #expect(try names(db) == ["Todo"])
        try await Task.sleep(for: .seconds(10.2))
        await engine.refreshOptions(projectId: FakeGitHub.projectId)
        #expect(github.requests() == ["options"])
        #expect(try names(db) == ["Todo", "From the website"])
    }

    @Test("two statuses made quickly one after the other are both made, once each")
    func oneAfterTheOther() async throws {
        let github = FakeGitHub(Self.board)
        let (_, engine) = try await makeEngine(github)
        try await engine.pull(projectId: FakeGitHub.projectId)
        let base = [RemoteOption(id: "todo", name: "Todo", color: "GRAY")]
        async let first = engine.updateOptions(
            projectId: FakeGitHub.projectId, fieldId: "F-status", kind: .status, base: base,
            options: base + [RemoteOption(id: nil, name: "QA", color: "GRAY")]
        )
        // The second change was made while the first was on its way: QA has no id yet there.
        async let second = engine.updateOptions(
            projectId: FakeGitHub.projectId, fieldId: "F-status", kind: .status, base: base,
            options: base + [RemoteOption(id: nil, name: "QA", color: "GRAY"), RemoteOption(id: nil, name: "Review", color: "GRAY")]
        )
        _ = try await (first, second)
        #expect(github.statusOptions.compactMap { $0["name"] as? String } == ["Todo", "QA", "Review"])
    }
}
