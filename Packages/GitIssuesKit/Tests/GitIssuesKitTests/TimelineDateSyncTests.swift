import Foundation
import GRDB
import Testing
@testable import GitIssuesKit

@Suite("Timeline date changes sent to GitHub")
struct TimelineDateSyncTests {
    static let first = CalendarDay(year: 2026, month: 12, day: 29)
    static let last = CalendarDay(year: 2027, month: 1, day: 4)
    static let itemId = "PVTI_1"

    private struct Fixture {
        let github: FakeGitHub
        let db: AppDatabase
        let engine: SyncEngine
        let start: ProjectField
        let end: ProjectField
        let due: Bool
    }

    private func fixture(due: Bool = false) async throws -> Fixture {
        let start = ProjectField(id: "S", projectId: FakeGitHub.projectId, databaseId: 2, name: "Start date", dataType: "DATE", position: 1)
        // "Target date" is recognized as the project's special due field, so use an ordinary end field here.
        let end = ProjectField(id: "E", projectId: FakeGitHub.projectId, databaseId: 3, name: due ? "Due date" : "Finish date", dataType: "DATE", position: 2)
        let github = FakeGitHub([.init(contentId: "I_1", number: 1, itemId: Self.itemId)])
        github.extraFields = [start, end].map {
            ["__typename": "ProjectV2Field", "id": $0.id, "databaseId": $0.databaseId!, "name": $0.name, "dataType": $0.dataType]
        }
        github.cardValues = [Self.itemId: [
            ["date": Self.first.string, "field": ["id": start.id]],
            ["date": Self.last.string, "field": ["id": end.id]],
        ]]
        let db = try AppDatabase.inMemory()
        try await db.writer.write { db in
            try Project(
                id: FakeGitHub.projectId, ownerLogin: "octo", ownerIsOrg: false, number: 1, title: "Board", url: "",
                closed: false, viewerCanUpdate: true
            ).insert(db)
        }
        let status = await MainActor.run { SyncStatus() }
        let engine = SyncEngine(db: db, api: github.api, status: status)
        try await engine.pull(projectId: FakeGitHub.projectId)
        return Fixture(github: github, db: db, engine: engine, start: start, end: end, due: due)
    }

    private func item(_ fixture: Fixture) async throws -> Item {
        let stored = try await fixture.db.reader.read { try Item.fetchOne($0, key: Self.itemId) }
        return try #require(stored)
    }

    private func edit(_ item: Item, in fixture: Fixture) throws -> TimelineDateEdit {
        let context = FilterContext(
            viewerLogin: "octo", today: Self.first, fields: [fixture.start, fixture.end],
            statusFieldId: "F-status", priorityFieldId: nil, dueFieldId: fixture.due ? fixture.end.id : nil,
            optionName: { _, _ in nil }, parentReference: { _ in nil }
        )
        return try #require(TimelineDateEdit.make(
            item: item, dates: (fixture.start, fixture.end), context: context,
            displayedSpan: .stretch(Self.first, Self.last), canUpdate: true
        ))
    }

    private func enqueue(_ mutations: [Mutation], in fixture: Fixture) async throws {
        try await fixture.db.writer.write { db in
            for mutation in mutations { try Outbox.enqueue(db, mutation) }
        }
    }

    private func expectDateWrites(_ expected: [String: String], in fixture: Fixture) {
        let writes = fixture.github.fieldWrites()
        #expect(writes.count == expected.count)
        #expect(!writes.contains { $0.isClear })
        for write in writes {
            #expect(write.query.contains("updateProjectV2ItemFieldValue("))
            #expect(write.query.contains("value: {date: $d}"))
            #expect(write.variables["p"] as? String == FakeGitHub.projectId)
            #expect(write.variables["i"] as? String == Self.itemId)
            let field = write.variables["f"] as? String ?? ""
            #expect(expected[field] != nil)
            #expect(write.variables["d"] as? String == expected[field])
            #expect(Set(write.variables.keys) == ["p", "i", "f", "d"])
        }
        #expect(Set(writes.compactMap { $0.variables["f"] as? String }) == Set(expected.keys))
    }

    /// Let the server be the only source on the next pull. Sent entries otherwise mask a bad write for 20 seconds.
    private func pullWithoutOptimisticValues(_ fixture: Fixture, sentCount: Int) async throws -> Item {
        let entries = try await fixture.db.reader.read { try OutboxEntry.fetchAll($0) }
        #expect(entries.count == sentCount)
        #expect(entries.allSatisfy { $0.state == .sent })
        try await fixture.db.writer.write { db in
            try Outbox.purgeSent(db, now: Date().addingTimeInterval(Outbox.graceInterval + 1))
        }
        let count = try await fixture.db.reader.read { try OutboxEntry.fetchCount($0) }
        #expect(count == 0)
        try await fixture.engine.forcePull(projectId: FakeGitHub.projectId)
        return try await item(fixture)
    }

    @Test("Moving a bar or resizing either edge writes date values and keeps the other endpoint", arguments: [TimelineDateEdit.Part.move, .start, .end])
    func ordinaryDateFields(part: TimelineDateEdit.Part) async throws {
        let fixture = try await fixture()
        let originalItem = try await item(fixture)
        let original = try edit(originalItem, in: fixture)
        let changed = original.adjusted(by: 2, part: part)
        let mutations = changed.mutations(from: original, item: originalItem, dueFieldId: nil)
        let start = part == .end ? Self.first : Self.first.adding(days: 2)
        let end = part == .start ? Self.last : Self.last.adding(days: 2)
        var expected: [String: String] = [:]
        if part != .end { expected[fixture.start.id] = start.string }
        if part != .start { expected[fixture.end.id] = end.string }

        try await enqueue(mutations, in: fixture)
        try await fixture.engine.pushPending()

        expectDateWrites(expected, in: fixture)
        #expect(fixture.github.dateValue(itemId: Self.itemId, fieldId: fixture.start.id) == start.string)
        #expect(fixture.github.dateValue(itemId: Self.itemId, fieldId: fixture.end.id) == end.string)
        let pulled = try await pullWithoutOptimisticValues(fixture, sentCount: expected.count)
        #expect(pulled.fieldValues[fixture.start.id]?.date == start.string)
        #expect(pulled.fieldValues[fixture.end.id]?.date == end.string)
        #expect(pulled.dueDate == nil)
        #expect(!pulled.dirty)
    }

    @Test("Restoring a date while its earlier write is in flight also restores the server date")
    func restoreDateDuringSend() async throws {
        let fixture = try await fixture()
        let originalItem = try await item(fixture)
        let original = try edit(originalItem, in: fixture)
        let changed = original.adjusted(by: 2, part: .start)
        let restored = changed.adjusted(by: -2, part: .start)
        try await enqueue(changed.mutations(from: original, item: originalItem, dueFieldId: nil), in: fixture)

        fixture.github.afterNextFieldWrite {
            #expect(fixture.github.dateValue(itemId: Self.itemId, fieldId: fixture.start.id) == Self.first.adding(days: 2).string)
            do {
                try fixture.db.writer.write { db in
                    let stored = try Item.fetchOne(db, key: Self.itemId)
                    let current = try #require(stored)
                    let entries = try OutboxEntry.fetchAll(db)
                    #expect(entries.count == 1)
                    #expect(entries.first?.state == .sending)
                    let changes = restored.mutations(from: changed, item: current, dueFieldId: nil)
                    #expect(changes.count == 1)
                    for change in changes { try Outbox.enqueue(db, change) }
                    #expect(try OutboxEntry.fetchCount(db) == 2)
                    let queued = try OutboxEntry.filter(Column("state") == OutboxState.pending.rawValue).fetchOne(db)
                    let pending = try #require(queued)
                    guard case .setProjectField(let mutation) = pending.mutation else {
                        Issue.record("Expected the date restoration to remain queued")
                        return
                    }
                    // The in-flight write stays separate, so the restoration keeps the value GitHub accepted as its base.
                    #expect(mutation.value?.date == Self.first.string)
                    #expect(mutation.base?.date == Self.first.adding(days: 2).string)
                }
            } catch {
                Issue.record(error)
            }
        }
        try await fixture.engine.pushPending()

        let writes = fixture.github.fieldWrites()
        #expect(writes.count == 2)
        #expect(writes.map { $0.variables["d"] as? String } == [Self.first.adding(days: 2).string, Self.first.string])
        #expect(writes.allSatisfy { !$0.isClear && $0.variables["f"] as? String == fixture.start.id })
        #expect(fixture.github.dateValue(itemId: Self.itemId, fieldId: fixture.start.id) == Self.first.string)
        #expect(fixture.github.dateValue(itemId: Self.itemId, fieldId: fixture.end.id) == Self.last.string)
        let pulled = try await pullWithoutOptimisticValues(fixture, sentCount: 2)
        #expect(pulled.fieldValues[fixture.start.id]?.date == Self.first.string)
        #expect(pulled.fieldValues[fixture.end.id]?.date == Self.last.string)
        #expect(!pulled.dirty)
    }

    @Test("An offline field edit that returns to its original value makes no request", arguments: [
        (FieldValue(date: Self.first.string), FieldValue(date: Self.last.string)),
        (FieldValue(optionId: "option-a"), FieldValue(optionId: "option-b")),
        (FieldValue(iterationId: "iteration-a"), FieldValue(iterationId: "iteration-b")),
        (FieldValue(text: "original"), FieldValue(text: "changed")),
        (FieldValue(number: 1), FieldValue(number: 2)),
        (nil, FieldValue(date: Self.first.string)),
    ] as [(FieldValue?, FieldValue?)])
    func offlineRestorationMakesNoRequest(values: (FieldValue?, FieldValue?)) async throws {
        let fixture = try await fixture()
        let (original, changed) = values
        func change(to value: FieldValue?, base: FieldValue?) -> Mutation {
            .setProjectField(.init(
                itemId: Self.itemId, projectId: FakeGitHub.projectId, fieldId: fixture.start.id, fieldName: fixture.start.name,
                value: value, valueName: nil, base: base
            ))
        }
        try await enqueue([change(to: changed, base: original), change(to: original, base: changed)], in: fixture)
        let entries = try await fixture.db.reader.read { try OutboxEntry.fetchAll($0) }
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        guard case .setProjectField(let mutation) = entry.mutation else {
            Issue.record("Expected the edits to coalesce into a project field change")
            return
        }
        #expect(mutation.value == original)
        #expect(mutation.base == original)

        try await fixture.engine.pushPending()

        #expect(fixture.github.fieldWrites().isEmpty)
        let states = try await fixture.db.reader.read { try OutboxEntry.fetchAll($0).map(\.state) }
        #expect(states == [.sent])
    }

    @Test("A field write interrupted while sending is retried before a newer edit")
    func interruptedFieldWriteIsRetried() async throws {
        let fixture = try await fixture()
        let originalItem = try await item(fixture)
        let original = try edit(originalItem, in: fixture)
        let changed = original.adjusted(by: 2, part: .start)
        try await enqueue(changed.mutations(from: original, item: originalItem, dueFieldId: nil), in: fixture)
        // Persist the state left if the app exits before receiving the request's response.
        try await fixture.db.writer.write { db in
            try db.execute(sql: "UPDATE outbox SET state = ?", arguments: [OutboxState.sending.rawValue])
            let current = try #require(try Item.fetchOne(db, key: Self.itemId))
            for change in original.mutations(from: changed, item: current, dueFieldId: nil) {
                try Outbox.enqueue(db, change)
            }
        }

        let status = await MainActor.run { SyncStatus() }
        let restarted = SyncEngine(db: fixture.db, api: fixture.github.api, status: status)
        try await restarted.pushPending()

        #expect(fixture.github.fieldWrites().map { $0.variables["d"] as? String } == [Self.first.adding(days: 2).string, Self.first.string])
        let pulled = try await pullWithoutOptimisticValues(fixture, sentCount: 2)
        #expect(pulled.fieldValues[fixture.start.id]?.date == Self.first.string)
    }

    @Test("A concurrent flush waits for an in-flight write and drains a newly queued edit")
    func concurrentPushDoesNotDuplicateFieldWrite() async throws {
        let fixture = try await fixture()
        let originalItem = try await item(fixture)
        let original = try edit(originalItem, in: fixture)
        try await enqueue(original.adjusted(by: 2, part: .start).mutations(from: original, item: originalItem, dueFieldId: nil), in: fixture)
        let accepted = AsyncStream<Void>.makeStream()
        let response = DispatchSemaphore(value: 0)
        defer { response.signal() }
        fixture.github.afterNextFieldWrite {
            accepted.continuation.yield(())
            // Bound the hold so a regression that sends a duplicate cannot deadlock URLSession's protocol queue.
            _ = response.wait(timeout: .now() + 5)
        }
        let pushing = Task {
            defer { accepted.continuation.finish() }
            try await fixture.engine.pushPending()
        }
        var started = false
        for await _ in accepted.stream {
            started = true
            break
        }
        #expect(started)
        let anotherStarted = AsyncStream<Void>.makeStream()
        let anotherCompleted = AsyncStream<Void>.makeStream()
        let anotherPush = Task {
            defer {
                anotherStarted.continuation.finish()
                anotherCompleted.continuation.yield(())
                anotherCompleted.continuation.finish()
            }
            // A notification action may enqueue another edit while the regular sync request is still waiting.
            try await enqueue(original.adjusted(by: 3, part: .end).mutations(from: original, item: originalItem, dueFieldId: nil), in: fixture)
            anotherStarted.continuation.yield(())
            try await fixture.engine.pushPending()
        }
        var anotherDidStart = false
        for await _ in anotherStarted.stream {
            anotherDidStart = true
            break
        }
        #expect(anotherDidStart)
        // The held response makes completion forbidden here. A short inverted wait checks that the flush
        // remains suspended instead of returning early and ending the notification's background execution.
        let completedBeforeRelease = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                var events = anotherCompleted.stream.makeAsyncIterator()
                return await events.next() != nil
            }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(100))
                return false
            }
            let completed = await group.next() ?? false
            group.cancelAll()
            return completed
        }
        #expect(!completedBeforeRelease)
        #expect(fixture.github.fieldWrites().count == 1)
        response.signal()
        try await pushing.value
        try await anotherPush.value
        expectDateWrites([fixture.start.id: Self.first.adding(days: 2).string, fixture.end.id: Self.last.adding(days: 3).string], in: fixture)
        let states = try await fixture.db.reader.read { try OutboxEntry.fetchAll($0).map(\.state) }
        #expect(states == [.sent, .sent])
    }

    @Test("Moving a range with a specialized due date writes both endpoints and survives a server refresh")
    func dateAndDueDate() async throws {
        let fixture = try await fixture(due: true)
        let originalItem = try await item(fixture)
        #expect(originalItem.dueDate == Self.last.string)
        #expect(originalItem.fieldValues[fixture.end.id] == nil)
        let original = try edit(originalItem, in: fixture)
        let mutations = original.adjusted(by: -3, part: .move).mutations(from: original, item: originalItem, dueFieldId: fixture.end.id)
        let start = Self.first.adding(days: -3).string
        let end = Self.last.adding(days: -3).string

        try await enqueue(mutations, in: fixture)
        try await fixture.engine.pushPending()

        expectDateWrites([fixture.start.id: start, fixture.end.id: end], in: fixture)
        #expect(fixture.github.dateValue(itemId: Self.itemId, fieldId: fixture.start.id) == start)
        #expect(fixture.github.dateValue(itemId: Self.itemId, fieldId: fixture.end.id) == end)
        let pulled = try await pullWithoutOptimisticValues(fixture, sentCount: 2)
        #expect(pulled.fieldValues[fixture.start.id]?.date == start)
        #expect(pulled.dueDate == end)
        #expect(pulled.fieldValues[fixture.end.id] == nil)
        #expect(!pulled.dirty)
    }

    @Test("Explicitly removing an ordinary or specialized date still clears only that field", arguments: [false, true])
    func explicitClear(due: Bool) async throws {
        let fixture = try await fixture(due: due)
        let fieldId = due ? fixture.end.id : fixture.start.id
        let mutation: Mutation = due
            ? .setDate(.init(itemId: Self.itemId, projectId: FakeGitHub.projectId, date: nil, base: Self.last.string))
            : .setProjectField(.init(itemId: Self.itemId, projectId: FakeGitHub.projectId, fieldId: fieldId, fieldName: fixture.start.name, value: nil, valueName: nil, base: FieldValue(date: Self.first.string)))
        try await enqueue([mutation], in: fixture)
        try await fixture.engine.pushPending()

        let writes = fixture.github.fieldWrites()
        #expect(writes.count == 1)
        let write = try #require(writes.first)
        #expect(write.isClear)
        #expect(write.variables["p"] as? String == FakeGitHub.projectId)
        #expect(write.variables["i"] as? String == Self.itemId)
        #expect(write.variables["f"] as? String == fieldId)
        #expect(Set(write.variables.keys) == ["p", "i", "f"])
        #expect(fixture.github.dateValue(itemId: Self.itemId, fieldId: fieldId) == nil)
        let untouchedId = due ? fixture.start.id : fixture.end.id
        let untouchedDate = due ? Self.first.string : Self.last.string
        #expect(fixture.github.dateValue(itemId: Self.itemId, fieldId: untouchedId) == untouchedDate)
        let pulled = try await pullWithoutOptimisticValues(fixture, sentCount: 1)
        #expect(pulled.fieldValues[fixture.start.id]?.date == (due ? Self.first.string : nil))
        #expect(pulled.fieldValues[fixture.end.id]?.date == (due ? nil : Self.last.string))
        #expect(pulled.dueDate == nil)
        #expect(!pulled.dirty)
    }

    @Test("Unsupported text and number values cannot become a clear request", arguments: [FieldValue(text: "a value"), FieldValue(text: ""), FieldValue(number: 0)])
    func unsupportedValueDoesNotClear(value: FieldValue) async throws {
        let fixture = try await fixture()
        try await enqueue([.setProjectField(.init(
            itemId: Self.itemId, projectId: FakeGitHub.projectId, fieldId: fixture.start.id, fieldName: fixture.start.name,
            value: value, valueName: nil, base: FieldValue(date: Self.first.string)
        ))], in: fixture)
        try await fixture.engine.pushPending()

        #expect(fixture.github.fieldWrites().isEmpty)
        #expect(fixture.github.dateValue(itemId: Self.itemId, fieldId: fixture.start.id) == Self.first.string)
        let pulled = try await pullWithoutOptimisticValues(fixture, sentCount: 0)
        #expect(pulled.fieldValues[fixture.start.id]?.date == Self.first.string)
        #expect(pulled.fieldValues[fixture.end.id]?.date == Self.last.string)
        #expect(!pulled.dirty)
    }

    @Test("A queued date edit describes the new date instead of saying the field was cleared")
    func queuedDateSummary() async throws {
        let fixture = try await fixture()
        let mutation = Mutation.setProjectField(.init(
            itemId: Self.itemId, projectId: FakeGitHub.projectId, fieldId: fixture.start.id, fieldName: fixture.start.name,
            value: FieldValue(date: Self.first.string), valueName: nil, base: nil
        ))
        let summary = try await fixture.db.reader.read { try mutation.summary($0) }
        #expect(summary.number == "#1")
        #expect(summary.text == String(localized: .queuedFieldSet(field: fixture.start.name, value: Self.first.longLabel)))
    }

    @Test("An option or iteration without a name never exposes its node ID", arguments: [
        FieldValue(optionId: "PVTSSO_unknown"), FieldValue(iterationId: "PVTI_unknown"),
    ])
    func queuedUnnamedOptionSummary(value: FieldValue) async throws {
        let fixture = try await fixture()
        let mutation = Mutation.setProjectField(.init(
            itemId: Self.itemId, projectId: FakeGitHub.projectId, fieldId: fixture.start.id, fieldName: "Workstream",
            value: value, valueName: nil, base: nil
        ))
        let summary = try await fixture.db.reader.read { try mutation.summary($0) }
        #expect(summary.text == String(localized: .queuedFieldCleared(field: "Workstream")))
    }
}
