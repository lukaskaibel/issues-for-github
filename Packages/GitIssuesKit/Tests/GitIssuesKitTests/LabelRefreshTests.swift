import Foundation
import GRDB
import Testing
@testable import GitIssuesKit

@Suite("Labels changed on GitHub, which their issues don't show")
struct LabelRefreshTests {
    static let bug = LabelRef(id: "LA_bug", name: "bug", color: "d73a4a")
    static let ui = LabelRef(id: "LA_ui", name: "ui", color: "0075ca")
    static let updatedAt = "2026-10-01T10:00:00Z"

    private func onGitHub(_ labels: LabelRef...) -> [[String: Any]] {
        labels.map { ["id": $0.id, "name": $0.name, "color": $0.color] }
    }

    private func makeEngine(_ github: FakeGitHub, labels: [LabelRef] = [bug, ui]) async throws -> (AppDatabase, SyncEngine) {
        let db = try AppDatabase.inMemory()
        try await db.writer.write { db in
            try Project(
                id: FakeGitHub.projectId, ownerLogin: "octo", ownerIsOrg: false, number: 1, title: "Board", url: "",
                closed: false, viewerCanUpdate: true
            ).insert(db)
            try RepoRef(
                id: FakeGitHub.repoId, nameWithOwner: FakeGitHub.repo, projectId: FakeGitHub.projectId,
                labels: [Self.bug, Self.ui], metaLoadedAt: Date()
            ).insert(db)
            var item = Item(
                id: "PVTI_1", projectId: FakeGitHub.projectId, kind: .issue, position: 1024, contentId: "I_1", number: 1,
                title: "Issue 1", body: "", state: "OPEN", repoId: FakeGitHub.repoId, repo: FakeGitHub.repo
            )
            item.labels = labels
            item.remoteUpdatedAt = Self.updatedAt
            try item.insert(db)
            var entry = InboxEntry(
                id: "1", reason: "assign", unread: true, updatedAt: Date(), subjectType: "Issue", title: "Issue 2",
                repo: FakeGitHub.repo, number: 2
            )
            entry.labels = labels
            try entry.insert(db)
        }
        let status = await MainActor.run { SyncStatus() }
        return (db, SyncEngine(db: db, api: github.api, status: status))
    }

    private func issue(_ db: AppDatabase) async throws -> Item {
        try await db.reader.read { try Item.fetchOne($0, key: "PVTI_1")! }
    }

    private func writes(_ db: AppDatabase) async throws -> Int {
        try await db.writer.read { $0.totalChangesCount }
    }

    @Test("A recoloured, renamed label changes on issues, Inbox entries and pickers, without reading the issues")
    func aChangedLabelReachesEveryCopy() async throws {
        let github = FakeGitHub([])
        let changed = LabelRef(id: "LA_bug", name: "defect", color: "eb5757")
        github.labels = onGitHub(changed, Self.ui)
        let (db, engine) = try await makeEngine(github)

        try await engine.refreshLabels()

        let item = try await issue(db)
        #expect(item.labels == [changed, Self.ui])
        #expect(item.remoteUpdatedAt == Self.updatedAt)
        let (entry, repo) = try await db.reader.read { (try InboxEntry.fetchOne($0)!, try RepoRef.fetchOne($0)!) }
        #expect(entry.labels == [changed, Self.ui])
        #expect(repo.labels == [changed, Self.ui])
        #expect(github.requests() == ["labels LA_bug, LA_ui"])
    }

    @Test("Labels as GitHub has them cost no write, so nothing on screen is redrawn")
    func unchangedLabelsWriteNothing() async throws {
        let github = FakeGitHub([])
        github.labels = onGitHub(Self.bug, Self.ui)
        let (db, engine) = try await makeEngine(github)
        let before = try await writes(db)

        try await engine.refreshLabels()

        #expect(try await writes(db) == before)
    }

    @Test("One stale copy is enough for the label to be written again")
    func oneStaleCopyIsFound() async throws {
        let github = FakeGitHub([])
        let changed = LabelRef(id: "LA_bug", name: "bug", color: "eb5757")
        github.labels = onGitHub(changed, Self.ui)
        let (db, engine) = try await makeEngine(github)
        // The issue was read again after the change, the Inbox entry wasn't.
        try await db.writer.write { db in
            var item = try Item.fetchOne(db, key: "PVTI_1")!
            item.labels = [changed, Self.ui]
            try item.update(db)
        }

        try await engine.refreshLabels()

        let entry = try await db.reader.read { try InboxEntry.fetchOne($0)! }
        #expect(entry.labels == [changed, Self.ui])
    }

    @Test("A label GitHub no longer has stays until its issue is read again")
    func aMissingLabelStays() async throws {
        let github = FakeGitHub([])
        github.labels = onGitHub(Self.ui)
        let (db, engine) = try await makeEngine(github)

        try await engine.refreshLabels()

        #expect(try await issue(db).labels == [Self.bug, Self.ui])
    }

    @Test("A label still being made isn't asked for")
    func aLocalLabelIsNotAskedFor() async throws {
        let github = FakeGitHub([])
        github.labels = onGitHub(Self.bug)
        let local = LabelRef(id: LabelRef.makeLocalId(), name: "new", color: "0e8a16")
        let (db, engine) = try await makeEngine(github, labels: [Self.bug, local])

        try await engine.refreshLabels()

        #expect(github.requests() == ["labels LA_bug"])
        #expect(try await issue(db).labels == [Self.bug, local])
    }

    @Test("A label added here and not sent yet stays while another one changes")
    func anUnsentLabelStays() async throws {
        let github = FakeGitHub([])
        let changed = LabelRef(id: "LA_bug", name: "bug", color: "eb5757")
        github.labels = onGitHub(changed, Self.ui)
        let (db, engine) = try await makeEngine(github, labels: [Self.bug])
        try await db.writer.write { try Outbox.enqueue($0, .editLabels(.init(contentId: "I_1", add: [Self.ui], remove: []))) }

        try await engine.refreshLabels()

        let item = try await issue(db)
        #expect(item.labels == [changed, Self.ui])
        #expect(item.dirty)
    }

    @Test("Labels are asked for once a minute, and at once after Sync Now")
    func labelsAreAskedForOnceAMinute() async throws {
        let github = FakeGitHub([])
        github.labels = onGitHub(Self.bug, Self.ui)
        let (_, engine) = try await makeEngine(github)

        try await engine.refreshLabels()
        try await engine.refreshLabels()
        #expect(github.requests().count == 1)

        await engine.forceRefresh()
        try await engine.refreshLabels()
        #expect(github.requests().count == 1)
    }
}
