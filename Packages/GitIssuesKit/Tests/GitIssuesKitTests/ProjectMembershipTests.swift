import Foundation
import GRDB
import Testing
@testable import GitIssuesKit

@Suite("Adding and removing an issue's project memberships")
struct ProjectMembershipTests {
    private func project(_ id: String, closed: Bool = false, editable: Bool = true) -> Project {
        Project(id: id, ownerLogin: "octo", ownerIsOrg: false, number: 1, title: id, url: "", closed: closed, viewerCanUpdate: editable)
    }

    private func item(_ id: String, project: String?) -> Item {
        var item = Item(id: id, projectId: project, kind: .issue, position: 1024, statusId: "todo", dueDate: "2026-11-03",
                        contentId: "I_1", number: 1, title: "Keep this issue", body: "Description", state: "OPEN", repoId: "R1", repo: "octo/one")
        item.fieldValues["version"] = FieldValue(optionId: project == "P1" ? "one" : "two")
        return item
    }

    private struct Fixture {
        var db: AppDatabase
        var github: FakeGitHub
        var engine: SyncEngine
        var source: Item
    }

    private func fixture(member: Bool, otherProject: Bool = true) async throws -> Fixture {
        let github = FakeGitHub([.init(contentId: "I_1", number: 1, itemId: member ? "PVTI_1" : nil,
                                      title: "Keep this issue", body: "Description")])
        let db = try AppDatabase.inMemory()
        let source = item(member ? "PVTI_1" : "source", project: member ? "P1" : "P2")
        try await db.writer.write { db in
            try project("P1").insert(db)
            try project("P2").insert(db)
            try source.insert(db)
            if member && otherProject { try item("other", project: "P2").insert(db) }
            try Comment(id: "comment", issueId: "I_1", authorLogin: "octo", body: "Keep the conversation", createdAt: Date()).insert(db)
        }
        let status = await MainActor.run { SyncStatus() }
        return Fixture(db: db, github: github, engine: SyncEngine(db: db, api: github.api, status: status), source: source)
    }

    private func change(_ fixture: Fixture, isMember: Bool) async throws {
        try await fixture.db.writer.write { db in
            let items = try Item.fetchAll(db)
            let project = try Project.fetchOne(db, key: "P1")!
            let mutation = IssueProjectMembership.change(fixture.source, project: project, items: items, isMember: isMember)!
            try Outbox.enqueue(db, mutation)
        }
    }

    @Test("A busy database suspends membership saves while the main actor remains responsive", arguments: [true, false])
    @MainActor
    func responsiveWhileSaving(initialMember: Bool) async throws {
        let f = try await fixture(member: initialMember)
        let changes = ProjectMembershipChanges()
        let target = project("P1")
        let entered = AsyncStream<Void>.makeStream()
        let releasedByUI = AsyncStream<Bool>.makeStream()
        let release = DispatchSemaphore(value: 0)
        f.db.writer.asyncWriteWithoutTransaction { _ in
            entered.continuation.yield(())
            entered.continuation.finish()
            // A bounded hold makes a regression fail instead of deadlocking the test process.
            let released = release.wait(timeout: .now() + 15) == .success
            releasedByUI.continuation.yield(released)
            releasedByUI.continuation.finish()
        }
        defer { release.signal() }
        for await _ in entered.stream { break }

        var saved = false
        var failed = false
        let task = try #require(changes.save(f.source, project: target, isMember: !initialMember, in: f.db,
                                            onSaved: { saved = true }, onFailure: { _ in failed = true }))
        // Give the save task a chance to enter the async database API, then run another UI task.
        await Task { @MainActor in
            #expect(!saved)
            #expect(changes.isSaving(f.source, projectId: target.id, in: f.db))
            #expect(changes.save(f.source, project: target, isMember: !initialMember, in: f.db,
                                 onSaved: {}, onFailure: { _ in }) == nil)
            release.signal()
        }.value

        await task.value
        var releases = releasedByUI.stream.makeAsyncIterator()
        let uiWasResponsive = await releases.next()
        #expect(uiWasResponsive == true)
        #expect(saved)
        #expect(!failed)
        // Keep duplicate clicks out until the UI has actually observed the committed membership.
        #expect(changes.isSaving(f.source, projectId: target.id, in: f.db))
        changes.observe(revision: 0, in: f.db)
        #expect(changes.isSaving(f.source, projectId: target.id, in: f.db))
        let items = try await f.db.reader.read { try Item.fetchAll($0) }
        #expect(changes.shouldAnimate(from: [f.source], to: items, in: f.db))
        changes.observe(revision: try await f.db.reader.read { try Outbox.revision($0) }, in: f.db)
        #expect(!changes.isSaving(f.source, projectId: target.id, in: f.db))
        #expect(items.contains { $0.projectId == target.id } == !initialMember)
        #expect(try await f.db.reader.read { try OutboxEntry.fetchCount($0) } == 1)
    }

    @Test("Observation may arrive before the async save resumes without losing animation or allowing duplicate clicks")
    @MainActor
    func observationBeforeSaveCompletion() async throws {
        let f = try await fixture(member: false)
        let changes = ProjectMembershipChanges()
        let task = try #require(changes.save(f.source, project: project("P1"), isMember: true, in: f.db,
                                            onSaved: {}, onFailure: { _ in Issue.record("Save failed") }))
        let added = item("new-card", project: "P1")
        #expect(changes.shouldAnimate(from: [f.source], to: [f.source, added], in: f.db))
        changes.observe(revision: 1, in: f.db)
        #expect(changes.isSaving(f.source, projectId: "P1", in: f.db))
        await task.value
        #expect(!changes.isSaving(f.source, projectId: "P1", in: f.db))
    }

    @Test("A membership save waiting for the writer does not recreate a deleted issue from an old notification")
    @MainActor
    func deletedSourceWhileSaving() async throws {
        let f = try await fixture(member: false)
        var notification = InboxEntry(id: "old-notification", reason: "mention", unread: true, updatedAt: Date(),
                                      subjectType: "Issue", title: f.source.title, repo: "octo/one", number: 1)
        notification.contentId = f.source.contentId
        let entry = notification
        try await f.db.writer.write { try entry.insert($0) }
        let entered = AsyncStream<Void>.makeStream()
        let release = DispatchSemaphore(value: 0)
        f.db.writer.asyncWriteWithoutTransaction { db in
            entered.continuation.yield(())
            entered.continuation.finish()
            _ = release.wait(timeout: .now() + 15)
            do { _ = try Item.deleteAll(db) }
            catch { Issue.record(error) }
        }
        defer { release.signal() }
        for await _ in entered.stream { break }

        let changes = ProjectMembershipChanges()
        var saved = false
        let task = try #require(changes.save(f.source, project: project("P1"), isMember: true, in: f.db,
                                            onSaved: { saved = true }, onFailure: { Issue.record($0) }))
        _ = await Task { @MainActor in release.signal() }.value
        await task.value
        #expect(!saved)
        #expect(!changes.isSaving(f.source, projectId: "P1", in: f.db))
        #expect(try await f.db.reader.read { try Item.fetchCount($0) } == 0)
        #expect(try await f.db.reader.read { try OutboxEntry.fetchCount($0) } == 0)
    }

    @Test("A failed async local save rolls back its transaction, reports the error and permits retry")
    @MainActor
    func localSaveFailure() async throws {
        let f = try await fixture(member: false)
        try await f.db.writer.write { db in
            try db.execute(sql: "CREATE TRIGGER reject_membership BEFORE INSERT ON \(OutboxEntry.databaseTableName) BEGIN SELECT RAISE(ABORT, 'Test failure'); END")
        }
        let changes = ProjectMembershipChanges()
        var errors = 0
        let task = try #require(changes.save(f.source, project: project("P1"), isMember: true, in: f.db,
                                            onSaved: { Issue.record("Failed save reported success") }, onFailure: { _ in errors += 1 }))
        await task.value
        #expect(errors == 1)
        #expect(!changes.isSaving(f.source, projectId: "P1", in: f.db))
        #expect(try await f.db.reader.read { try Item.filter(Column("projectId") == "P1").fetchCount($0) } == 0)
        #expect(try await f.db.reader.read { try OutboxEntry.fetchCount($0) } == 0)
        try await f.db.writer.write { try $0.execute(sql: "DROP TRIGGER reject_membership") }
        let retry = try #require(changes.save(f.source, project: project("P1"), isMember: true, in: f.db,
                                             onSaved: {}, onFailure: { _ in Issue.record("Retry failed") }))
        await retry.value
        #expect(try await f.db.reader.read { try Item.filter(Column("projectId") == "P1").fetchCount($0) } == 1)
    }

    @Test("Async removal resolves a membership ID changed by sync before the transaction starts")
    func asyncSaveUsesCurrentCard() async throws {
        let f = try await fixture(member: true)
        try await f.db.writer.write { try $0.execute(sql: "UPDATE item SET id = 'PVTI_new' WHERE id = 'PVTI_1'") }
        let saved = try await IssueProjectMembership.save(f.source, projectId: "P1", isMember: false, in: f.db)
        #expect(saved != nil)
        #expect(try await f.db.reader.read { try Item.filter(Column("projectId") == "P1").fetchCount($0) } == 0)
        let entries = try await f.db.reader.read { try OutboxEntry.fetchAll($0) }
        #expect(entries.first?.mutation.itemId == "PVTI_new")
    }

    @Test("Membership changes follow a newly created issue's content ID", arguments: [true, false])
    func createdIssueMembershipRemap(initialMember: Bool) async throws {
        let f = try await fixture(member: initialMember)
        var captured = f.source
        captured.id = "local-card"
        captured.contentId = "local-content"
        try await f.db.writer.write { try CreatedIssueIDs.record($0, localId: "local-content", serverId: "I_1") }
        #expect(try await IssueProjectMembership.save(captured, projectId: "P1", isMember: !initialMember, in: f.db) != nil)
        let snapshot = try await f.db.reader.read { try AppModel.fetchSnapshot($0) }
        #expect(snapshot.items.contains { $0.contentId == "I_1" && $0.projectId == "P1" } == !initialMember)
        #expect(!snapshot.items.contains { $0.contentId == "local-content" })
        #expect(snapshot.outbox.allSatisfy { $0.mutation.contentId == "I_1" })
    }

    @Test("A project picker captured before creation sync still removes the existing membership")
    func capturedPickerAfterCreation() async throws {
        let f = try await fixture(member: true)
        var beforeCreation = f.source
        beforeCreation.id = "local-card"
        beforeCreation.contentId = "local-content"
        let reference = IssueReference(beforeCreation)
        let snapshot = try await f.db.reader.read { try AppModel.fetchSnapshot($0) }
        let current = try #require(reference.remapping(["local-content": "I_1"]).resolve(in: snapshot.items, projects: snapshot.projects))
        #expect(current.id == f.source.id)
        let mutation = try #require(IssueProjectMembership.change(current, project: project("P1"), items: snapshot.items, isMember: false))
        try await f.db.writer.write { try Outbox.enqueue($0, mutation) }
        try await f.engine.pushPending()
        let remaining = try await f.db.reader.read { try Item.fetchAll($0) }
        #expect(!remaining.contains { $0.contentId == "I_1" && $0.projectId == "P1" })
        #expect(remaining.contains { $0.contentId == "I_1" && $0.projectId == "P2" })
    }

    @Test("An already satisfied membership does not wait for an observation that no write will trigger")
    @MainActor
    func unchangedAsyncSave() async throws {
        let f = try await fixture(member: true)
        let changes = ProjectMembershipChanges()
        let task = try #require(changes.save(f.source, project: project("P1"), isMember: true, in: f.db,
                                            onSaved: { Issue.record("No mutation should need syncing") }, onFailure: { _ in Issue.record("No-op failed") }))
        await task.value
        #expect(!changes.isSaving(f.source, projectId: "P1", in: f.db))
        #expect(try await f.db.reader.read { try OutboxEntry.fetchCount($0) } == 0)
    }

    @Test("A superseded membership save settles even if the UI never saw the requested membership", arguments: [true, false])
    @MainActor
    func supersededSave(initialMember: Bool) async throws {
        let f = try await fixture(member: initialMember)
        let changes = ProjectMembershipChanges()
        let task = try #require(changes.save(f.source, project: project("P1"), isMember: !initialMember, in: f.db,
                                            onSaved: {}, onFailure: { _ in Issue.record("Save failed") }))
        await task.value
        changes.observe(revision: 0, in: f.db)
        #expect(changes.isSaving(f.source, projectId: "P1", in: f.db))
        _ = try await IssueProjectMembership.save(f.source, projectId: "P1", isMember: initialMember, in: f.db)
        _ = try await f.db.writer.write { try OutboxEntry.deleteAll($0) }
        let snapshot = try await f.db.reader.read { try AppModel.fetchSnapshot($0) }
        #expect(snapshot.items.contains { $0.projectId == "P1" } == initialMember)
        #expect(snapshot.outbox.isEmpty)
        changes.observe(revision: snapshot.outboxRevision, in: f.db)
        #expect(!changes.isSaving(f.source, projectId: "P1", in: f.db))
        let retry = try #require(changes.save(f.source, project: project("P1"), isMember: !initialMember, in: f.db,
                                             onSaved: {}, onFailure: { _ in Issue.record("Retry failed") }))
        await retry.value
    }

    @Test("Adding to another project preserves the existing card and maps queued field edits to the new card")
    func addToAnotherProject() async throws {
        let f = try await fixture(member: false)
        try await change(f, isMember: true)
        let added = try await f.db.reader.read { try Item.filter(Column("projectId") == "P1").fetchOne($0) }
        let local = try #require(added)
        #expect(local.isLocalOnly)
        #expect(local.fieldValues.isEmpty)
        try await f.db.writer.write { db in
            try Outbox.enqueue(db, .setProjectField(.init(itemId: local.id, projectId: "P1", fieldId: "version", fieldName: "Version",
                                                        value: FieldValue(optionId: "new"), valueName: "New", base: nil)))
        }
        try await f.engine.pushPending()
        let remoteId = try #require(f.github.issue("I_1")?.itemId)
        let (source, target) = try await f.db.reader.read { (try Item.fetchOne($0, key: "source"), try Item.fetchOne($0, key: remoteId)) }
        #expect(source?.projectId == "P2")
        #expect(source?.fieldValues["version"]?.optionId == "two")
        #expect(source?.dueDate == "2026-11-03")
        #expect(target?.projectId == "P1")
        #expect(target?.fieldValues["version"]?.optionId == "new")
        #expect(f.github.fieldWrites().first?.variables["i"] as? String == remoteId)
    }

    @Test("Merging a pulled server card preserves queued values through a transient write failure", arguments: [
        FieldValue(text: "Saved notes"), FieldValue(number: 42), FieldValue(date: "2026-11-10"),
    ])
    func membershipCollision(value: FieldValue) async throws {
        let f = try await fixture(member: false)
        let github = FakeGitHub([.init(contentId: "I_1", number: 1, itemId: "PVTI_existing", title: f.source.title)])
        let type = value.number != nil ? "NUMBER" : value.date != nil ? "DATE" : "TEXT"
        github.extraFields = [["__typename": "ProjectV2Field", "id": "F-extra", "name": "Extra", "databaseId": 2, "dataType": type]]
        var remote: [String: Any] = ["field": ["id": "F-extra"]]
        if value.number != nil { remote["number"] = 7 }
        else if value.date != nil { remote["date"] = "2026-11-05" }
        else { remote["text"] = "Remote value" }
        github.cardValues["PVTI_existing"] = [remote]
        let status = await MainActor.run { SyncStatus() }
        let engine = SyncEngine(db: f.db, api: github.api, status: status)
        try await change(f, isMember: true)
        let local = try #require(try await f.db.reader.read { try Item.filter(Column("projectId") == "P1").fetchOne($0) })
        try await f.db.writer.write { db in
            try Outbox.enqueue(db, .setProjectField(.init(itemId: local.id, projectId: "P1", fieldId: "F-extra", fieldName: "Extra",
                                                        value: value, valueName: nil, base: nil)))
        }
        // GitHub already has this membership, but it was not in the cache when the local add was made.
        try await engine.pull(projectId: "P1")
        #expect(try await f.db.reader.read { try Item.filter(Column("projectId") == "P1").fetchCount($0) } == 2)
        github.failsFieldWrites = true
        await #expect(throws: (any Error).self) { try await engine.pushPending() }
        let after = try await f.db.reader.read { try AppModel.fetchSnapshot($0) }
        let card = try #require(after.items.first { $0.id == "PVTI_existing" })
        #expect(card.fieldValues["F-extra"] == value)
        #expect(!after.items.contains { $0.id == local.id })
        #expect(after.items.first { $0.id == f.source.id }?.fieldValues == f.source.fieldValues)
        #expect(after.outbox.contains { $0.state == .sending && $0.mutation.itemId == card.id })
        github.failsFieldWrites = false
        try await engine.pushPending()
        #expect(try await f.db.reader.read { try Item.fetchOne($0, key: card.id)?.fieldValues["F-extra"] } == value)
    }

    @Test("Rejected issue creation removes its pending memberships and copies", arguments: [true, false])
    func rejectedCreation(addingSecondProject: Bool) async throws {
        let f = try await fixture(member: true)
        let github = FakeGitHub([])
        github.refusesIssueCreation = true
        let status = await MainActor.run { SyncStatus() }
        let engine = SyncEngine(db: f.db, api: github.api, status: status)
        let creation = Mutation.CreateIssue(itemId: "local-card", contentId: "local-content", projectId: "P1", repoId: "R1",
                                            repo: "octo/one", title: "Offline creation", body: "", assignees: [], labels: [], createdAt: Date())
        try await f.db.writer.write { db in
            try Outbox.enqueue(db, .createIssue(creation))
            let local = try #require(try Item.fetchOne(db, key: creation.itemId))
            try Outbox.enqueue(db, .setProjectField(.init(itemId: local.id, projectId: "P1", fieldId: "notes", fieldName: "Notes",
                                                        value: FieldValue(text: "Offline edit"), valueName: nil, base: nil)))
            let mutation = try #require(IssueProjectMembership.change(local, project: project(addingSecondProject ? "P2" : "P1"),
                                                                      items: try Item.fetchAll(db), isMember: addingSecondProject))
            try Outbox.enqueue(db, mutation)
        }
        try await engine.pushPending()
        let snapshot = try await f.db.reader.read { try AppModel.fetchSnapshot($0) }
        #expect(snapshot.outbox.isEmpty)
        #expect(!snapshot.items.contains { $0.contentId == creation.contentId })
        #expect(snapshot.items.first { $0.id == f.source.id } == f.source)
        #expect(snapshot.items.contains { $0.id == "other" && $0.contentId == "I_1" })
    }

    @Test("Removing a new issue's last project survives creation progress and leaves one server issue", arguments: [false, true])
    func creationAfterLastMembershipRemoval(transientFailure: Bool) async throws {
        let f = try await fixture(member: true)
        let github = FakeGitHub([.init(contentId: "I_1", number: 1, itemId: "PVTI_1")])
        github.failsMembershipWrites = transientFailure
        let status = await MainActor.run { SyncStatus() }
        let engine = SyncEngine(db: f.db, api: github.api, status: status)
        let creation = Mutation.CreateIssue(itemId: "local-card", contentId: "local-content", projectId: "P1", repoId: "R1",
                                            repo: "octo/one", title: "Created without a project", body: "", assignees: [], labels: [], createdAt: Date())
        try await f.db.writer.write { db in
            try Outbox.enqueue(db, .createIssue(creation))
            let local = try #require(try Item.fetchOne(db, key: creation.itemId))
            let removal = try #require(IssueProjectMembership.change(local, project: project("P1"), items: try Item.fetchAll(db), isMember: false))
            try Outbox.enqueue(db, removal)
        }
        if transientFailure {
            await #expect(throws: (any Error).self) { try await engine.pushPending() }
            let progress = try await f.db.reader.read { try Item.filter(Column("contentId") == creation.contentId).fetchAll($0) }
            #expect(progress.count == 1)
            #expect(progress.first?.projectId == nil, "Saving creation progress must not restore the removed project")
            #expect(progress.first?.number == 2)
            github.failsMembershipWrites = false
        }
        try await engine.pushPending()
        let snapshot = try await f.db.reader.read { try AppModel.fetchSnapshot($0) }
        let contentId = try #require(snapshot.createdIssueIDs[creation.contentId])
        let copies = snapshot.items.filter { $0.contentId == contentId }
        #expect(copies.count == 1)
        #expect(copies.first?.id == Item.idWithoutProject(contentId))
        #expect(copies.first?.projectId == nil)
        #expect(copies.first?.number == 2)
        #expect(copies.first?.url == "https://github.com/octo/one/issues/2")
        #expect(!snapshot.items.contains { $0.id == Item.idWithoutProject(creation.contentId) })
        #expect(github.issue(contentId)?.itemId == nil)
        #expect(snapshot.outbox.allSatisfy { $0.state == .sent })
    }

    private enum DetailWatch: CaseIterable {
        case keptOpen, closed, anotherIssue
    }

    @Test("Creation transfers only an active local detail watch, including partial project setup", arguments: DetailWatch.allCases, [false, true])
    private func creationDetailWatch(watch: DetailWatch, rejectedProject: Bool) async throws {
        let f = try await fixture(member: true)
        f.github.refusedMembershipProjects = rejectedProject ? ["P1"] : []
        let creation = Mutation.CreateIssue(itemId: "local-card", contentId: "local-content", projectId: "P1", repoId: "R1",
                                            repo: "octo/one", title: "Open while creating", body: "", assignees: [], labels: [], createdAt: Date())
        try await f.db.writer.write { try Outbox.enqueue($0, .createIssue(creation)) }
        await f.engine.setWatchedIssue(creation.contentId)
        if watch == .closed { await f.engine.unwatchIssue(creation.contentId) }
        if watch == .anotherIssue { await f.engine.setWatchedIssue("I_1") }
        try await f.engine.pushPending()
        let snapshot = try await f.db.reader.read { try AppModel.fetchSnapshot($0) }
        let createdId = try #require(snapshot.createdIssueIDs[creation.contentId])
        #expect(await f.engine.watchedIssueId == (watch == .keptOpen ? createdId : watch == .anotherIssue ? "I_1" : nil))
        if watch == .keptOpen {
            // A view can disappear with its captured local ID after the acknowledgement was published.
            await f.engine.unwatchIssue(creation.contentId)
            #expect(await f.engine.watchedIssueId == nil)
            await f.engine.setWatchedIssue(creation.contentId)
            #expect(await f.engine.watchedIssueId == createdId)
            await f.engine.unwatchIssue(createdId)
            #expect(await f.engine.watchedIssueId == nil)
        } else {
            await f.engine.unwatchIssue(creation.contentId)
            #expect(await f.engine.watchedIssueId == (watch == .anotherIssue ? "I_1" : nil))
        }
    }

    @Test("Rejected initial project setup retains the created issue and other queued memberships", arguments: [false, true])
    func rejectedInitialProject(addingOtherProject: Bool) async throws {
        let f = try await fixture(member: true)
        let github = FakeGitHub([.init(contentId: "I_1", number: 1, itemId: "PVTI_1")])
        github.refusedMembershipProjects = ["P2"]
        let status = await MainActor.run { SyncStatus() }
        let engine = SyncEngine(db: f.db, api: github.api, status: status)
        let creation = Mutation.CreateIssue(itemId: "local-card", contentId: "local-content", projectId: "P2", repoId: "R1",
                                            repo: "octo/one", title: "Created despite project rejection", body: "", assignees: [], labels: [], createdAt: Date())
        try await f.db.writer.write { db in
            try Outbox.enqueue(db, .createIssue(creation))
            let local = try #require(try Item.fetchOne(db, key: creation.itemId))
            let change = try #require(IssueProjectMembership.change(local, project: project(addingOtherProject ? "P1" : "P2"),
                                                                    items: try Item.fetchAll(db), isMember: addingOtherProject))
            try Outbox.enqueue(db, change)
            if addingOtherProject, case .setProjectMembership(let membership) = change {
                try Outbox.enqueue(db, .setProjectField(.init(itemId: membership.item.id, projectId: "P1", fieldId: "version", fieldName: "Version",
                                                            value: FieldValue(optionId: "new"), valueName: nil, base: nil)))
            }
        }
        try await engine.pushPending()
        let snapshot = try await f.db.reader.read { try AppModel.fetchSnapshot($0) }
        let contentId = try #require(snapshot.createdIssueIDs[creation.contentId])
        let copies = snapshot.items.filter { $0.contentId == contentId }
        let kept = try #require(copies.first)
        #expect(copies.count == 1)
        #expect(kept.number == 2)
        #expect(kept.url == "https://github.com/octo/one/issues/2")
        #expect(kept.projectId == (addingOtherProject ? "P1" : nil))
        #expect(kept.id == (addingOtherProject ? github.issue(contentId)?.itemId : Item.idWithoutProject(contentId)))
        if addingOtherProject { #expect(kept.fieldValues["version"]?.optionId == "new") }
        #expect(!snapshot.items.contains { $0.contentId == creation.contentId })
        #expect(snapshot.outbox.allSatisfy { $0.state == .sent })
        #expect(snapshot.items.first { $0.id == f.source.id } == f.source)
    }

    @Test("A rejected initial field write preserves the created issue and later project removal")
    func rejectedInitialField() async throws {
        let f = try await fixture(member: true)
        let github = FakeGitHub([.init(contentId: "I_1", number: 1, itemId: "PVTI_1")])
        github.refusesFieldWrites = true
        let status = await MainActor.run { SyncStatus() }
        let engine = SyncEngine(db: f.db, api: github.api, status: status)
        let creation = Mutation.CreateIssue(itemId: "local-card", contentId: "local-content", projectId: "P1", repoId: "R1",
                                            repo: "octo/one", title: "Created despite field rejection", body: "", statusFieldId: "F-status", statusId: "todo",
                                            assignees: [], labels: [], createdAt: Date())
        try await f.db.writer.write { db in
            try Outbox.enqueue(db, .createIssue(creation))
            let local = try #require(try Item.fetchOne(db, key: creation.itemId))
            let change = try #require(IssueProjectMembership.change(local, project: project("P1"), items: try Item.fetchAll(db), isMember: false))
            try Outbox.enqueue(db, change)
        }
        try await engine.pushPending()
        let snapshot = try await f.db.reader.read { try AppModel.fetchSnapshot($0) }
        let contentId = try #require(snapshot.createdIssueIDs[creation.contentId])
        let copies = snapshot.items.filter { $0.contentId == contentId }
        #expect(copies.count == 1)
        #expect(copies.first?.id == Item.idWithoutProject(contentId))
        #expect(copies.first?.number == 2)
        #expect(github.issue(contentId)?.itemId == nil, "The already-created membership still needs its queued removal")
        #expect(snapshot.outbox.allSatisfy { $0.state == .sent })
    }

    @Test("Removing a project preserves the issue, other memberships and comments")
    func removeOneProject() async throws {
        let f = try await fixture(member: true)
        try await change(f, isMember: false)
        #expect(try await f.db.reader.read { try Item.fetchOne($0, key: "PVTI_1") } == nil)
        #expect(try await f.db.reader.read { try Item.fetchOne($0, key: "other")?.fieldValues["version"]?.optionId } == "two")
        #expect(try await f.db.reader.read { try Comment.fetchCount($0) } == 1)
        try await f.engine.pushPending()
        #expect(f.github.issue("I_1") != nil)
        #expect(f.github.issue("I_1")?.itemId == nil)
        #expect(f.github.requests() == ["remove membership I_1"])
        #expect(try await f.db.reader.read { try Item.fetchOne($0, key: "other") } != nil)
    }

    @Test("Removing the last open project retains the issue on no board, even with a cached closed membership")
    func lastProject() async throws {
        let f = try await fixture(member: true, otherProject: false)
        try await f.db.writer.write { db in
            try project("Closed", closed: true).insert(db)
            try item("closed-card", project: "Closed").insert(db)
        }
        try await change(f, isMember: false)
        let loose = try await f.db.reader.read { try Item.fetchOne($0, key: Item.idWithoutProject("I_1")) }
        #expect(loose?.projectId == nil)
        #expect(loose?.title == "Keep this issue")
        #expect(loose?.body == "Description")
        #expect(loose?.fieldValues.isEmpty == true)
        #expect(loose?.dueDate == nil)
        #expect(try await f.db.writer.write { try SyncEngine.dropCopiesWithoutProject($0) }.isEmpty)
        #expect(try await f.db.reader.read { try Item.fetchOne($0, key: Item.idWithoutProject("I_1")) } != nil)
        try await f.engine.pushPending()
        #expect(f.github.issue("I_1") != nil)
    }

    @Test("Adding then removing before sending is a no-op and drops edits to the temporary membership")
    func cancelPendingAdd() async throws {
        let f = try await fixture(member: false)
        try await change(f, isMember: true)
        try await f.db.writer.write { db in
            let added = try Item.filter(Column("projectId") == "P1").fetchOne(db)!
            try Outbox.enqueue(db, .setProjectField(.init(itemId: added.id, projectId: "P1", fieldId: "version", fieldName: "Version",
                                                        value: FieldValue(optionId: "new"), valueName: "New", base: nil)))
        }
        try await change(f, isMember: false)
        #expect(try await f.db.reader.read { try OutboxEntry.fetchCount($0) } == 2)
        try await f.engine.pushPending()
        #expect(f.github.requests().isEmpty)
        #expect(try await f.db.reader.read { try OutboxEntry.fetchCount($0) } == 1)
        #expect(try await f.db.reader.read { try Item.filter(Column("projectId") == "P1").fetchCount($0) } == 0)
    }

    @Test("Removing then restoring before sending keeps the original card and its field values")
    func cancelPendingRemoval() async throws {
        let f = try await fixture(member: true)
        try await change(f, isMember: false)
        try await change(f, isMember: true)
        #expect(try await f.db.reader.read { try Item.fetchOne($0, key: "PVTI_1")?.fieldValues["version"]?.optionId } == "one")
        try await f.engine.pushPending()
        #expect(f.github.requests().isEmpty)
        #expect(f.github.issue("I_1")?.itemId == "PVTI_1")
    }

    @Test("A stale refresh cannot bring a removed membership back")
    func staleRead() async throws {
        let f = try await fixture(member: true)
        try await change(f, isMember: false)
        try await f.db.writer.write { db in
            try f.source.save(db)
            try Outbox.rebase(db)
        }
        #expect(try await f.db.reader.read { try Item.fetchOne($0, key: "PVTI_1") } == nil)
        #expect(try await f.db.reader.read { try Item.fetchOne($0, key: "other") } != nil)
    }

    @Test("A stale project pull keeps navigation on the retained issue after its last membership is removed")
    func stalePullAfterLastRemoval() async throws {
        let f = try await fixture(member: true, otherProject: false)
        let status = await MainActor.run { SyncStatus() }
        let engine = SyncEngine(db: f.db, api: f.github.api, status: status)
        try await change(f, isMember: false)
        let retainedId = Item.idWithoutProject("I_1")
        // GitHub still returns the card because its removal is queued locally.
        try await engine.forcePull(projectId: "P1")
        let items = try await f.db.reader.read { try Item.fetchAll($0) }
        #expect(items.map(\.id) == [retainedId])
        let remaps = await MainActor.run { status.idRemaps }
        #expect(remaps[retainedId] == nil)
        #expect(items.contains { $0.id == (remaps[retainedId] ?? retainedId) })
        #expect(IssueReference(f.source).resolve(in: items, projects: [project("P1")])?.id == retainedId)
    }

    private enum OtherProjectChange: CaseIterable {
        case add, remove, legacyAdd
    }

    @Test("Losing a card on one project preserves queued memberships on another", arguments: OtherProjectChange.allCases)
    private func remoteRemovalKeepsOtherMembership(change: OtherProjectChange) async throws {
        let github = FakeGitHub([.init(contentId: "I_1", number: 1, itemId: nil, title: "Keep this issue")])
        let database = try AppDatabase.inMemory()
        let removed = item("PVTI_removed", project: "P1")
        let kept = try await database.writer.write { db -> Mutation in
            try project("P1").insert(db)
            try project("P2").insert(db)
            try removed.insert(db)
            let mutation: Mutation
            if change == .legacyAdd {
                let loose = item(Item.idWithoutProject("I_1"), project: nil)
                try loose.insert(db)
                mutation = .addToProject(.init(itemId: loose.id, contentId: "I_1", projectId: "P2", statusFieldId: nil, statusId: nil))
            } else {
                if change == .remove { try item("PVTI_other", project: "P2").insert(db) }
                mutation = try #require(IssueProjectMembership.change(removed, project: project("P2"), items: try Item.fetchAll(db),
                                                                     isMember: change == .add))
            }
            try Outbox.enqueue(db, mutation)
            // An edit to the missing card itself must still be discarded.
            try Outbox.enqueue(db, .setProjectField(.init(itemId: removed.id, projectId: "P1", fieldId: "version", fieldName: "Version",
                                                        value: FieldValue(optionId: "new"), valueName: "New", base: nil)))
            return mutation
        }
        let status = await MainActor.run { SyncStatus() }
        let engine = SyncEngine(db: database, api: github.api, status: status)
        try await engine.forcePull(projectId: "P1")
        let snapshot = try await database.reader.read { try AppModel.fetchSnapshot($0) }
        #expect(snapshot.outbox.map(\.mutation) == [kept])
        #expect(snapshot.outbox.first?.state == .pending)
        #expect(!snapshot.items.contains { $0.id == removed.id })
        #expect(snapshot.items.contains { $0.projectId == "P2" } == (change != .remove))
    }

    @Test("A due-date editor opened before membership sync writes to the remapped card only")
    func dueDateEditorFollowsRemap() async throws {
        let f = try await fixture(member: false)
        f.github.extraFields = [["__typename": "ProjectV2Field", "id": "F-due", "name": "Due date", "dataType": "DATE"]]
        try await change(f, isMember: true)
        let local = try #require(try await f.db.reader.read { try Item.filter(Column("projectId") == "P1").fetchOne($0) })
        #expect(local.isLocalOnly)
        // Both calendar presentations keep this target from the moment they open.
        let target = ProjectFieldTarget(item: local, fieldId: "@due")
        let identity = target.id
        try await f.engine.pushPending()
        let remoteId = try #require(f.github.issue("I_1")?.itemId)
        let items = try await f.db.reader.read { try Item.fetchAll($0) }
        let resolved = try #require(target.resolve(in: items))
        #expect(resolved.id == remoteId)
        #expect(resolved.id != local.id)
        #expect(ProjectFieldTarget(item: resolved, fieldId: "@due").id == identity)
        let day = "2026-11-12"
        let expected = AsyncProjectEdits.Expected(target: target, value: FieldValue(date: day), dueDate: true)
        try await AsyncProjectEdits.persist([.setDate(.init(itemId: local.id, projectId: "P1", date: day, base: nil))],
                                            inserting: [], expected: [expected], in: f.db)
        try await f.engine.pushPending()
        #expect(f.github.dateValue(itemId: remoteId, fieldId: "F-due") == day)
        #expect(f.github.fieldWrites().last?.variables["i"] as? String == remoteId)
        #expect(try await f.db.reader.read { try Item.fetchOne($0, key: remoteId)?.dueDate } == day)
        #expect(try await f.db.reader.read { try Item.fetchOne($0, key: f.source.id)?.dueDate } == f.source.dueDate)
    }

    @Test("The last toggle wins while an earlier membership write is in flight", arguments: [true, false])
    func inFlight(initialMember: Bool) async throws {
        let f = try await fixture(member: initialMember)
        try await change(f, isMember: !initialMember)
        f.github.afterNextWrite {
            try! f.db.writer.write { db in
                let items = try Item.fetchAll(db)
                let project = try Project.fetchOne(db, key: "P1")!
                try Outbox.enqueue(db, IssueProjectMembership.change(f.source, project: project, items: items, isMember: initialMember)!)
            }
        }
        try await f.engine.pushPending()
        #expect((f.github.issue("I_1")?.itemId != nil) == initialMember)
        #expect(try await f.db.reader.read { try Item.filter(Column("projectId") == "P1").fetchCount($0) } == (initialMember ? 1 : 0))
    }

    @Test("Rejected membership changes roll back locally without deleting the issue", arguments: [true, false])
    func rejected(initialMember: Bool) async throws {
        let f = try await fixture(member: initialMember)
        f.github.refusesMembershipChanges = true
        try await change(f, isMember: !initialMember)
        try await f.engine.pushPending()
        #expect(try await f.db.reader.read { try Item.filter(Column("projectId") == "P1").fetchCount($0) } == (initialMember ? 1 : 0))
        #expect(try await f.db.reader.read { try Comment.fetchCount($0) } == 1)
        #expect(f.github.issue("I_1") != nil)
    }

    @Test("Project field edits survive cancelling or rejecting a removal", arguments: [true, false])
    func pendingFields(reject: Bool) async throws {
        let f = try await fixture(member: true)
        try await f.db.writer.write { db in
            try Outbox.enqueue(db, .setProjectField(.init(itemId: "PVTI_1", projectId: "P1", fieldId: "version", fieldName: "Version",
                                                        value: FieldValue(optionId: "edited"), valueName: "Edited", base: FieldValue(optionId: "one"))))
        }
        try await change(f, isMember: false)
        if reject { f.github.refusesMembershipChanges = true } else { try await change(f, isMember: true) }
        try await f.engine.pushPending()
        #expect(f.github.fieldWrites().last?.variables["o"] as? String == "edited")
        #expect(try await f.db.reader.read { try Item.fetchOne($0, key: "PVTI_1")?.fieldValues["version"]?.optionId } == "edited")
        #expect(f.github.issue("I_1")?.itemId == "PVTI_1")
    }

    @Test("A rejected in-flight add followed by removal leaves no ghost card")
    func failedAddThenRemove() async throws {
        let f = try await fixture(member: false)
        try await change(f, isMember: true)
        // The fake's refusal happens before its success callback, so reverse at the first request boundary.
        f.github.refusesMembershipChanges = true
        try await f.db.writer.write { db in
            var entry = try OutboxEntry.fetchAll(db).first!
            entry.state = .sending
            try entry.update(db)
        }
        try await change(f, isMember: false)
        try await f.engine.pushPending()
        #expect(f.github.issue("I_1")?.itemId == nil)
        #expect(try await f.db.reader.read { try Item.filter(Column("projectId") == "P1").fetchCount($0) } == 0)
        #expect(try await f.db.reader.read { try OutboxEntry.fetchAll($0).allSatisfy { $0.state == .sent } })
    }

    @Test("Issue title and body edits survive cancelling the temporary membership they were edited through")
    func keepIssueEdits() async throws {
        let initial = try await fixture(member: false)
        var loose = initial.source
        loose.id = Item.idWithoutProject("I_1")
        loose.projectId = nil
        let f = Fixture(db: initial.db, github: initial.github, engine: initial.engine, source: loose)
        try await f.db.writer.write { db in
            try Item.deleteOne(db, key: "source")
            try f.source.insert(db)
        }
        try await change(f, isMember: true)
        try await f.db.writer.write { db in
            let added = try Item.filter(Column("projectId") == "P1").fetchOne(db)!
            try Outbox.enqueue(db, .setTitle(.init(itemId: added.id, contentId: "I_1", value: "Edited title", base: "Keep this issue")))
            try Outbox.enqueue(db, .setBody(.init(itemId: added.id, contentId: "I_1", value: "Edited body", base: "Description")))
        }
        try await change(f, isMember: false)
        let kept = try await f.db.reader.read { try Item.fetchOne($0, key: Item.idWithoutProject("I_1")) }
        #expect(kept?.title == "Edited title")
        #expect(kept?.body == "Edited body")
        try await f.engine.pushPending()
        #expect(f.github.issue("I_1")?.title == "Edited title")
        #expect(f.github.issue("I_1")?.body == "Edited body")
        #expect(f.github.issue("I_1")?.itemId == nil)
    }

    @Test("Rejected removals merge re-adds and later reversals into the original card", arguments: [false, true], [false, true])
    func failedRemovalThenReadd(editField: Bool, removeAgain: Bool) async throws {
        let f = try await fixture(member: true)
        try await change(f, isMember: false)
        try await f.db.writer.write { db in
            var entry = try #require(try OutboxEntry.fetchAll(db).first)
            entry.state = .sending
            try entry.update(db)
        }
        try await change(f, isMember: true)
        let temporary = try #require(try await f.db.reader.read { try Item.filter(Column("projectId") == "P1").fetchOne($0) })
        #expect(temporary.isLocalOnly)
        if editField {
            try await f.db.writer.write { db in
                try Outbox.enqueue(db, .setProjectField(.init(itemId: temporary.id, projectId: "P1", fieldId: "version", fieldName: "Version",
                                                            value: FieldValue(optionId: "edited"), valueName: "Edited", base: nil)))
            }
        }
        if removeAgain { try await change(f, isMember: false) }
        f.github.refusesMembershipChanges = true
        let status = await MainActor.run { SyncStatus() }
        let engine = SyncEngine(db: f.db, api: f.github.api, status: status)
        try await engine.pushPending()
        let cards = try await f.db.reader.read { try Item.filter(Column("projectId") == "P1").fetchAll($0) }
        #expect(cards.map(\.id) == ["PVTI_1"])
        #expect(cards.first?.statusId == f.source.statusId)
        #expect(cards.first?.dueDate == f.source.dueDate)
        #expect(cards.first?.fieldValues["version"]?.optionId == (editField ? "edited" : "one"))
        #expect(f.github.issue("I_1")?.itemId == "PVTI_1")
        #expect(try await f.db.reader.read { try Item.fetchOne($0, key: "other") } != nil)
        #expect(try await f.db.reader.read { try Comment.fetchCount($0) } == 1)
        #expect(await MainActor.run { status.idRemaps[temporary.id] } == "PVTI_1")
        #expect(try await f.db.reader.read { try OutboxEntry.fetchAll($0).allSatisfy { $0.state == .sent } })
        if editField { #expect(f.github.fieldWrites().last?.variables["i"] as? String == "PVTI_1") }
    }

    @Test("An Inbox-only issue can be added and followed through its first server card ID")
    func detachedInboxMembership() async throws {
        let f = try await fixture(member: false)
        var notification = InboxEntry(id: "outside", reason: "mention", unread: true, updatedAt: Date(), subjectType: "Issue",
                                      title: "Keep this issue", repo: "octo/outside", number: 1)
        notification.contentId = "I_1"
        notification.repoId = "R_outside"
        let entry = notification
        try await f.db.writer.write { db in
            try Item.deleteAll(db)
            try entry.insert(db)
        }
        let detached = try #require(Item(detached: entry))
        let reference = IssueReference(detached)
        #expect(try await f.db.reader.read { try Item.fetchCount($0) } == 0)
        #expect(reference.resolve(in: [], projects: [project("P1")], inbox: [entry]) == detached)
        let revision = try await IssueProjectMembership.save(detached, projectId: "P1", isMember: true, in: f.db)
        #expect(revision != nil)
        let saved = try await f.db.reader.read { try Item.fetchAll($0) }
        let local = try #require(reference.resolve(in: saved, projects: [project("P1")], inbox: [entry]))
        #expect(local.projectId == "P1")
        #expect(!local.isDetached)
        #expect(local.repo == entry.repo)
        try await f.engine.pushPending()
        let remoteId = try #require(f.github.issue("I_1")?.itemId)
        let confirmed = try await f.db.reader.read { try Item.fetchAll($0) }
        #expect(confirmed.count == 1)
        #expect(reference.resolve(in: confirmed, projects: [project("P1")], inbox: [entry])?.id == remoteId)
    }

    @Test("An Inbox-only membership save requires a current, accessible notification", arguments: [true, false])
    func detachedSourceDisappeared(missing: Bool) async throws {
        let f = try await fixture(member: false)
        var notification = InboxEntry(id: "outside", reason: "mention", unread: true, updatedAt: Date(), subjectType: "Issue",
                                      title: "Keep this issue", repo: "octo/outside", number: 1)
        notification.contentId = "I_1"
        let captured = try #require(Item(detached: notification))
        notification.missing = missing
        let entry = notification
        try await f.db.writer.write { db in
            try Item.deleteAll(db)
            if missing { try entry.insert(db) }
        }
        #expect(try await IssueProjectMembership.save(captured, projectId: "P1", isMember: true, in: f.db) == nil)
        #expect(try await f.db.reader.read { try Item.fetchCount($0) } == 0)
        #expect(try await f.db.reader.read { try OutboxEntry.fetchCount($0) } == 0)
    }

    @Test("Closed projects, read-only projects, draft issues and unchanged memberships cannot be edited")
    func permissions() {
        let source = item("source", project: "P2")
        #expect(IssueProjectMembership.change(source, project: project("P1", closed: true), items: [], isMember: true) == nil)
        #expect(IssueProjectMembership.change(source, project: project("P1", editable: false), items: [], isMember: true) == nil)
        var draft = source
        draft.kind = .draft
        #expect(IssueProjectMembership.change(draft, project: project("P1"), items: [], isMember: true) == nil)
        #expect(IssueProjectMembership.change(source, project: project("P2"), items: [source], isMember: true) == nil)
        #expect(IssueProjectMembership.change(source, project: project("P1"), items: [source], isMember: false) == nil)
    }
}
