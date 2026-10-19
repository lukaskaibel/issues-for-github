import Foundation
import GRDB
import Testing
@testable import GitIssuesKit

@Suite("The self-test's project stays out of release builds")
struct SandboxTests {
    /// A board and the sandbox. The sandbox has a repository of its own and shares another with the board.
    private func makeDatabase() throws -> AppDatabase {
        let db = try AppDatabase.inMemory()
        try db.writer.write { db in
            for (id, title) in [("P1", "Board"), ("S1", Project.sandboxTitle)] {
                try Project(
                    id: id, ownerLogin: "octo", ownerIsOrg: false, number: 1, title: title, url: "",
                    closed: false, viewerCanUpdate: true
                ).insert(db)
            }
            for (id, name, projectId) in [
                ("R1", "octo/one", "P1"), ("RS", "octo/git-issues-sandbox", "S1"),
                ("RX", "octo/shared", "P1"), ("RX", "octo/shared", "S1"),
            ] {
                try RepoRef(id: id, nameWithOwner: name, projectId: projectId).insert(db)
            }
            for (id, projectId, repoId) in [
                ("on-board", "P1", "R1"), ("on-sandbox", "S1", "RS"),
                ("loose-one", nil, "R1"), ("loose-sandbox", nil, "RS"), ("loose-shared", nil, "RX"),
            ] as [(String, String?, String)] {
                try Item(
                    id: id, projectId: projectId, kind: .issue, position: 1024, contentId: id, number: 1,
                    title: id, body: "", state: "OPEN", repoId: repoId, repo: nil
                ).insert(db)
            }
            for (id, repo, reason) in [
                ("t-one", "octo/one", "assign"), ("t-sandbox", "octo/git-issues-sandbox", InboxEntry.selfAssignReason),
                ("t-shared", "octo/shared", "mention"),
            ] {
                try InboxEntry(
                    id: id, reason: reason, unread: true, updatedAt: Date(), subjectType: "Issue", title: id,
                    repo: repo, number: 1
                ).insert(db)
            }
        }
        return db
    }

    @Test func leavesOutTheSandboxAndWhatOnlyItsRepositoryHolds() throws {
        let db = try makeDatabase()
        let snapshot = try db.reader.read { try AppModel.fetchSnapshot($0) }.withoutSandbox()
        #expect(snapshot.projects.map(\.id) == ["P1"])
        #expect(Set(snapshot.repos.map { "\($0.projectId)/\($0.id)" }) == ["P1/R1", "P1/RX"])
        #expect(Set(snapshot.items.map(\.id)) == ["on-board", "loose-one", "loose-shared"])
        #expect(Set(snapshot.inbox.map(\.id)) == ["t-one", "t-shared"])
    }

    @Test func keepsEverythingWithoutASandbox() throws {
        let db = try makeDatabase()
        try db.writer.write { try $0.execute(sql: "UPDATE project SET title = 'Roadmap' WHERE id = 'S1'") }
        let snapshot = try db.reader.read { try AppModel.fetchSnapshot($0) }.withoutSandbox()
        #expect(snapshot.projects.count == 2)
        #expect(snapshot.repos.count == 4)
        #expect(snapshot.items.count == 5)
        #expect(snapshot.inbox.count == 3)
    }
}
