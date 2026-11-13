import Foundation
import GRDB
import Testing
@testable import GitIssuesKit

@Suite("Asynchronous project field editing")
struct AsyncProjectEditsTests {
    private struct Fixture {
        var db: AppDatabase
        var item: Item
        var project: Project
        var field: ProjectField
        var target: ProjectFieldTarget { .init(item: item, fieldId: field.id) }
        var expected: AsyncProjectEdits.Expected { .init(target: target, value: FieldValue(text: "New value")) }
        var mutation: Mutation {
            .setProjectField(.init(itemId: item.id, projectId: project.id, fieldId: field.id, fieldName: field.name,
                                   value: FieldValue(text: "New value"), valueName: "New value", base: nil))
        }
    }

    private func fixture() async throws -> Fixture {
        let db = try AppDatabase.inMemory()
        let project = Project(id: "P1", ownerLogin: "octo", ownerIsOrg: false, number: 1, title: "Project", url: "", closed: false, viewerCanUpdate: true)
        let item = Item(id: "local-card", projectId: project.id, kind: .issue, position: 0, contentId: "I1", number: 1, title: "Issue", body: "", state: "OPEN")
        let field = ProjectField(id: "F1", projectId: project.id, databaseId: 1, name: "Notes", dataType: "TEXT", position: 0)
        try await db.writer.write { db in
            try project.insert(db)
            try item.insert(db)
            try field.insert(db)
        }
        return Fixture(db: db, item: item, project: project, field: field)
    }

    @Test("A field save yields the main actor while the database is busy and waits for observation")
    @MainActor
    func responsiveSave() async throws {
        let f = try await fixture()
        let changes = AsyncProjectEdits()
        let entered = AsyncStream<Void>.makeStream()
        let releasedByUI = AsyncStream<Bool>.makeStream()
        let release = DispatchSemaphore(value: 0)
        f.db.writer.asyncWriteWithoutTransaction { _ in
            entered.continuation.yield(())
            entered.continuation.finish()
            releasedByUI.continuation.yield(release.wait(timeout: .now() + 15) == .success)
            releasedByUI.continuation.finish()
        }
        defer { release.signal() }
        for await _ in entered.stream { break }
        var saved = false
        let task = try #require(changes.save([f.mutation], expected: [f.expected], in: f.db,
                                            onSaved: { saved = true }, onFailure: { _ in Issue.record("Save failed") }))
        await Task { @MainActor in
            #expect(!saved)
            #expect(changes.isSaving(f.target, in: f.db))
            #expect(changes.save([f.mutation], expected: [f.expected], in: f.db, onSaved: {}, onFailure: { _ in }) == nil)
            release.signal()
        }.value
        await task.value
        var released = releasedByUI.stream.makeAsyncIterator()
        #expect(await released.next() == true)
        #expect(saved)
        #expect(changes.isSaving(f.target, in: f.db))
        let items = try await f.db.reader.read { try Item.fetchAll($0) }
        #expect(changes.shouldAnimate(from: [f.item], to: items, projects: [f.project], fields: [f.field], in: f.db))
        changes.observe(revision: try await f.db.reader.read { try Outbox.revision($0) }, in: f.db)
        #expect(!changes.isSaving(f.target, in: f.db))
    }

    private enum SupersedingUpdate: CaseIterable {
        case changedValue, removedField, removedMembership
    }

    @Test("A newer snapshot settles a field save even when its value or target disappeared", arguments: SupersedingUpdate.allCases)
    @MainActor
    private func supersededSave(update: SupersedingUpdate) async throws {
        let f = try await fixture()
        let changes = AsyncProjectEdits()
        let task = try #require(changes.save([f.mutation], expected: [f.expected], in: f.db,
                                            onSaved: {}, onFailure: { _ in Issue.record("Save failed") }))
        await task.value
        changes.observe(revision: 0, in: f.db)
        #expect(changes.isSaving(f.target, in: f.db), "A snapshot from before the commit must not settle the save")
        try await f.db.writer.write { db in
            switch update {
            case .changedValue:
                var item = try #require(try Item.fetchOne(db, key: f.item.id))
                item.fieldValues[f.field.id] = FieldValue(text: "A newer value")
                try item.update(db)
            case .removedField: try ProjectField.deleteOne(db, key: f.field.id)
            case .removedMembership: try Item.deleteOne(db, key: f.item.id)
            }
            // Sync may acknowledge and purge the write before the UI receives either value.
            try OutboxEntry.deleteAll(db)
        }
        let snapshot = try await f.db.reader.read { try AppModel.fetchSnapshot($0) }
        #expect(snapshot.outbox.isEmpty)
        #expect(snapshot.outboxRevision > 0)
        #expect(!f.expected.matches(snapshot.items, projects: snapshot.projects, fields: snapshot.fields))
        changes.observe(revision: snapshot.outboxRevision, in: f.db)
        #expect(!changes.isSaving(f.target, in: f.db))
    }

    @Test("Observation can acknowledge a field commit before its save continuation resumes")
    @MainActor
    func observationBeforeSaveCompletion() async throws {
        let f = try await fixture()
        let changes = AsyncProjectEdits()
        let task = try #require(changes.save([f.mutation], expected: [f.expected], in: f.db,
                                            onSaved: {}, onFailure: { _ in Issue.record("Save failed") }))
        // This isolated database's first queued write has revision 1. Model the observation arriving first.
        changes.observe(revision: 1, in: f.db)
        #expect(changes.isSaving(f.target, in: f.db))
        await task.value
        #expect(!changes.isSaving(f.target, in: f.db))
    }

    @Test("Rapid due-date choices and reversals queue in order while the database is busy", arguments: [false, true])
    @MainActor
    func rapidDueDates(clearLast: Bool) async throws {
        let f = try await fixture()
        let changes = AsyncProjectEdits()
        let target = ProjectFieldTarget(item: f.item, fieldId: "@due")
        let entered = AsyncStream<Void>.makeStream()
        let release = DispatchSemaphore(value: 0)
        f.db.writer.asyncWriteWithoutTransaction { _ in
            entered.continuation.yield(())
            entered.continuation.finish()
            _ = release.wait(timeout: .now() + 15)
        }
        defer { release.signal() }
        for await _ in entered.stream { break }
        var days: [String?] = ["2026-11-10", "2026-11-11", "2026-11-10"]
        if clearLast { days.append(nil) }
        var saved: [String?] = []
        var tasks: [Task<Void, Never>] = []
        for day in days {
            let mutation = Mutation.setDate(.init(itemId: f.item.id, projectId: f.project.id, date: day, base: nil))
            let expected = AsyncProjectEdits.Expected(target: target, value: day.map { FieldValue(date: $0) }, dueDate: true)
            tasks.append(try #require(changes.save([mutation], expected: [expected], in: f.db,
                                                  onSaved: { saved.append(day) }, onFailure: { _ in Issue.record("Date save failed") })))
            #expect(changes.save([mutation], expected: [expected], in: f.db, onSaved: {}, onFailure: { _ in }) == nil,
                    "Only a repeated identical choice should be ignored")
        }
        #expect(saved.isEmpty)
        release.signal()
        for task in tasks { await task.value }
        #expect(saved == days)
        let snapshot = try await f.db.reader.read { try AppModel.fetchSnapshot($0) }
        #expect(snapshot.items.first?.dueDate == days.last!)
        #expect(snapshot.outbox.count == 1, "The offline queue should coalesce the choices to the last date")
        changes.observe(revision: 1, in: f.db)
        #expect(changes.isSaving(target, in: f.db), "Observing the first commit must not settle later choices")
        changes.observe(revision: snapshot.outboxRevision, in: f.db)
        #expect(!changes.isSaving(target, in: f.db))
    }

    @Test("A field transaction resolves the server card ID before enqueuing the edit")
    func remappedCard() async throws {
        let f = try await fixture()
        try await f.db.writer.write { try $0.execute(sql: "UPDATE item SET id = 'PVTI_1' WHERE id = 'local-card'") }
        try await AsyncProjectEdits.persist([f.mutation], inserting: [], expected: [f.expected], in: f.db)
        let stored = try await f.db.reader.read { try Item.fetchOne($0, key: "PVTI_1") }
        #expect(stored?.fieldValues[f.field.id]?.text == "New value")
        #expect(try await f.db.reader.read { try OutboxEntry.fetchAll($0).first?.mutation.itemId } == "PVTI_1")
    }

    @Test("A field save and its editor survive issue creation and outbox cleanup", arguments: [false, true])
    @MainActor
    func createdIssueRemap(dueDate: Bool) async throws {
        let f = try await fixture()
        let source: Item = {
            var item = f.item
            item.contentId = "local-content"
            return item
        }()
        let creation = Mutation.CreateIssue(itemId: source.id, contentId: "local-content", projectId: f.project.id,
                                            repoId: "R1", repo: "octo/one", title: source.title, body: "", assignees: [], labels: [],
                                            createdAt: Date(), createdContentId: "I1", createdNumber: 1)
        try await f.db.writer.write { try Outbox.enqueue($0, .createIssue(creation)) }
        let github = FakeGitHub([.init(contentId: "I1", number: 1, title: source.title)])
        let engine = SyncEngine(db: f.db, api: github.api, status: SyncStatus())
        try await engine.pushPending()
        // An editor can outlive the acknowledged creation row; identity must not depend on retaining that row.
        try await f.db.writer.write { _ = try OutboxEntry.deleteAll($0) }
        let before = try await f.db.reader.read { try AppModel.fetchSnapshot($0) }
        let server = try #require(before.items.first { $0.contentId == "I1" })
        #expect(server.id != source.id)
        #expect(before.createdIssueIDs["local-content"] == "I1")
        let target = ProjectFieldTarget(item: source, fieldId: dueDate ? "@due" : f.field.id)
        #expect(target.remapping(before.createdIssueIDs).resolve(in: before.items)?.id == server.id)
        let mutation = dueDate
            ? Mutation.setDate(.init(itemId: source.id, projectId: f.project.id, date: "2026-11-10", base: nil)) : f.mutation
        let value = dueDate ? FieldValue(date: "2026-11-10") : FieldValue(text: "New value")
        let expected = AsyncProjectEdits.Expected(target: target, value: value, dueDate: dueDate)
        let changes = AsyncProjectEdits()
        var saved = false
        let task = try #require(changes.save([mutation], expected: [expected], in: f.db,
                                            onSaved: { saved = true }, onFailure: { _ in Issue.record("Save lost the newly created issue") }))
        await task.value
        #expect(saved)
        let currentTarget = ProjectFieldTarget(item: server, fieldId: target.fieldId)
        #expect(changes.isSaving(currentTarget, in: f.db, remaps: before.createdIssueIDs))
        let after = try await f.db.reader.read { try AppModel.fetchSnapshot($0) }
        #expect(expected.matches(after.items, projects: after.projects, fields: after.fields, remaps: after.createdIssueIDs))
        #expect(after.outbox.first?.mutation.itemId == server.id)
        changes.observe(revision: after.outboxRevision, in: f.db)
        #expect(!changes.isSaving(currentTarget, in: f.db, remaps: after.createdIssueIDs))
    }

    @Test("A project becoming read-only or losing the field rejects the queued local write", arguments: [true, false])
    func unavailableField(readOnly: Bool) async throws {
        let f = try await fixture()
        try await f.db.writer.write { db in
            if readOnly { try db.execute(sql: "UPDATE project SET viewerCanUpdate = 0") }
            else { try ProjectField.deleteOne(db, key: f.field.id) }
        }
        await #expect(throws: (any Error).self) {
            try await AsyncProjectEdits.persist([f.mutation], inserting: [], expected: [f.expected], in: f.db)
        }
        #expect(try await f.db.reader.read { try OutboxEntry.fetchCount($0) } == 0)
        #expect(try await f.db.reader.read { try Item.fetchOne($0, key: f.item.id)?.fieldValues.isEmpty } == true)
    }

    @Test("Multi-selection toggles preserve other choices and clear an empty selection")
    func selections() {
        let field = ProjectField(id: "F", projectId: "P", databaseId: 1, name: "Platforms", dataType: "MULTI_SELECT", position: 0)
        #expect(ProjectFieldEditing.picked("android", field: field, current: FieldValue(optionIds: ["ios"]))?.optionIds == ["android", "ios"])
        #expect(ProjectFieldEditing.picked("ios", field: field, current: FieldValue(optionIds: ["ios"])) == nil)
        #expect(ProjectFieldEditing.picked("", field: field, current: FieldValue(optionIds: ["ios"])) == nil)
    }

    @Test("A due date can be saved before the project has a due-date field")
    func missingDueField() async throws {
        let f = try await fixture()
        let day = "2026-11-10"
        let expected = AsyncProjectEdits.Expected(target: .init(item: f.item, fieldId: "@due"), value: FieldValue(date: day), dueDate: true)
        try await AsyncProjectEdits.persist([.setDate(.init(itemId: f.item.id, projectId: f.project.id, date: day, base: nil))],
                                            inserting: [], expected: [expected], in: f.db)
        let items = try await f.db.reader.read { try Item.fetchAll($0) }
        #expect(expected.matches(items, projects: [f.project], fields: []))
        #expect(items.first?.dueDate == day)
    }

    @Test("The legacy add flow retains the chosen status and checks current project permissions", arguments: [true, false])
    func legacyAddition(editable: Bool) async throws {
        let f = try await fixture()
        var loose = f.item
        loose.projectId = nil
        let source = loose
        try await f.db.writer.write { db in
            try source.update(db)
            if !editable { try db.execute(sql: "UPDATE project SET viewerCanUpdate = 0") }
        }
        let expected = AsyncProjectEdits.Expected(target: .init(item: loose, fieldId: "@membership"), value: nil, addingToProject: f.project.id)
        let add = Mutation.addToProject(.init(itemId: loose.id, contentId: "I1", projectId: f.project.id, statusFieldId: "status", statusId: "todo"))
        if editable {
            try await AsyncProjectEdits.persist([add], inserting: [], expected: [expected], in: f.db)
            let items = try await f.db.reader.read { try Item.fetchAll($0) }
            #expect(expected.matches(items, projects: [f.project], fields: []))
            #expect(items.first?.statusId == "todo")
        } else {
            await #expect(throws: (any Error).self) {
                try await AsyncProjectEdits.persist([add], inserting: [], expected: [expected], in: f.db)
            }
            #expect(try await f.db.reader.read { try Item.fetchOne($0, key: source.id)?.projectId } == nil)
            #expect(try await f.db.reader.read { try OutboxEntry.fetchCount($0) } == 0)
        }
    }
}
