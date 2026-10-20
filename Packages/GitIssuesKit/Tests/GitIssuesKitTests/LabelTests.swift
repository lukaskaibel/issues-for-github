import Foundation
import GRDB
import SwiftUI
import Testing
@testable import GitIssuesKit

@Suite("Labels typed into the picker that the repository doesn't have yet")
struct LabelTests {
    private func makeEngine(_ github: FakeGitHub) async throws -> (AppDatabase, SyncEngine) {
        let db = try AppDatabase.inMemory()
        try await db.writer.write { db in
            try Project(
                id: FakeGitHub.projectId, ownerLogin: "octo", ownerIsOrg: false, number: 1, title: "Board", url: "",
                closed: false, viewerCanUpdate: true
            ).insert(db)
            try RepoRef(
                id: FakeGitHub.repoId, nameWithOwner: FakeGitHub.repo, projectId: FakeGitHub.projectId,
                labels: [LabelRef(id: "LA_bug", name: "bug", color: "d73a4a")], metaLoadedAt: Date()
            ).insert(db)
            try Item(
                id: "PVTI_1", projectId: FakeGitHub.projectId, kind: .issue, position: 1024, contentId: "I_1", number: 1,
                title: "Issue 1", body: "", state: "OPEN", repoId: FakeGitHub.repoId, repo: FakeGitHub.repo
            ).insert(db)
        }
        let status = await MainActor.run { SyncStatus() }
        return (db, SyncEngine(db: db, api: github.api, status: status))
    }

    /// What the picker queues for "ui": the label, then the issue getting it.
    private func addNewLabel(_ db: AppDatabase, named name: String = "ui") throws -> LabelRef {
        let made = Mutation.CreateLabel(
            labelId: LabelRef.makeLocalId(), repoId: FakeGitHub.repoId, repo: FakeGitHub.repo, name: name,
            color: LabelRef.newColor(for: name)
        )
        try db.writer.write { db in
            try Outbox.enqueue(db, .createLabel(made))
            try Outbox.enqueue(db, .editLabels(.init(contentId: "I_1", add: [made.label], remove: [])))
        }
        return made.label
    }

    private func issue(_ db: AppDatabase) throws -> Item {
        try db.reader.read { try Item.fetchOne($0, key: "PVTI_1")! }
    }

    private func repoLabels(_ db: AppDatabase) throws -> [LabelRef] {
        try db.reader.read { try RepoRef.fetchOne($0)!.labels }
    }

    @Test("A new label shows on the issue and among the repository's labels at once, in order")
    func showsAtOnce() async throws {
        let (db, _) = try await makeEngine(FakeGitHub([]))
        let label = try addNewLabel(db)
        #expect(try issue(db).labels == [label])
        #expect(try repoLabels(db).map(\.name) == ["bug", "ui"])
        // Read again from GitHub before it is made, it stays.
        try await db.writer.write { try Outbox.rebase($0) }
        #expect(try repoLabels(db).map(\.name) == ["bug", "ui"])
    }

    @Test("GitHub makes it, the issue gets it, and everything follows it to GitHub's id")
    func makesItOnGitHub() async throws {
        let github = FakeGitHub([.init(contentId: "I_1", number: 1, itemId: "PVTI_1")])
        let (db, engine) = try await makeEngine(github)
        let label = try addNewLabel(db)
        try await engine.pushPending()
        #expect(github.requests() == ["label ui", "create label ui", "add labels LA_1"])
        #expect(github.labels.first?["color"] as? String == label.color)
        #expect(try issue(db).labels.map(\.id) == ["LA_1"])
        #expect(try repoLabels(db).map(\.id) == ["LA_bug", "LA_1"])
    }

    @Test("One made meanwhile, in another case, is used rather than made again")
    func usesOneMadeMeanwhile() async throws {
        let github = FakeGitHub([.init(contentId: "I_1", number: 1, itemId: "PVTI_1")])
        github.labels = [["id": "LA_9", "name": "UI", "color": "1d76db"]]
        let (db, engine) = try await makeEngine(github)
        _ = try addNewLabel(db)
        try await engine.pushPending()
        #expect(github.requests() == ["label ui", "add labels LA_9"])
        #expect(try issue(db).labels.map(\.id) == ["LA_9"])
    }

    @Test("A label GitHub refuses comes off the issue and the repository, and nothing waits for it")
    func refusedLabelComesOff() async throws {
        let github = FakeGitHub([.init(contentId: "I_1", number: 1, itemId: "PVTI_1")])
        github.refusesLabels = true
        let (db, engine) = try await makeEngine(github)
        _ = try addNewLabel(db)
        try await engine.pushPending()
        #expect(github.requests() == ["label ui", "create label ui"])
        #expect(try issue(db).labels.isEmpty)
        #expect(try repoLabels(db).map(\.name) == ["bug"])
        let waiting = try await db.reader.read { try OutboxEntry.fetchCount($0) }
        #expect(waiting == 0)
    }

    @Test("Changes waiting for a label and a new issue with it follow it to GitHub's id")
    func remapsWaitingChanges() {
        let local = LabelRef.makeLocalId()
        let label = LabelRef(id: local, name: "ui", color: "1d76db")
        let edit = Mutation.editLabels(.init(contentId: "I_1", add: [label], remove: []))
        guard case .editLabels(let remapped) = edit.remapping([local: "LA_1"]) else {
            Issue.record("Expected a label change")
            return
        }
        #expect(remapped.add.map(\.id) == ["LA_1"])
        #expect(remapped.add.first?.name == "ui")
    }

    @Test("A new label has one of GitHub's colours, the same for the same name whatever its case")
    func colours() {
        #expect(LabelRef.newLabelColors.contains(LabelRef.newColor(for: "ui")))
        #expect(LabelRef.newColor(for: "Needs Design") == LabelRef.newColor(for: "needs design"))
    }

    @Test("The row that makes a label comes after the labels that contain what was typed, before loose matches")
    func createRowOrder() {
        let row = { (title: String) in PickerItem(id: title, title: title, icon: AnyView(EmptyView())) }
        let items = [row("duplicate"), row("ui-kit"), row("docs")]
        let make = PickerItem(id: "new-label:ui", title: "Create label “ui”", icon: AnyView(EmptyView()), creates: true)
        #expect(matching("ui", in: items, creating: make).map(\.id) == ["ui-kit", "new-label:ui", "duplicate"])
        #expect(matching("zz", in: items, creating: make).map(\.id) == ["new-label:ui"])
        #expect(matching("ui", in: items, creating: nil).map(\.id) == ["ui-kit", "duplicate"])
    }
}
