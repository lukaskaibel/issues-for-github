import Foundation
import GRDB
import Testing
@testable import GitIssuesKit

@Suite("Issue detail lifecycle across creation acknowledgement")
@MainActor
struct AppModelDetailTests {
    @Test("Captured local views release the server detail only after the last view closes", arguments: [1, 2], [false, true])
    func capturedDetailCleanup(viewCount: Int, followBeforeClosing: Bool) async throws {
        let database = try AppDatabase.inMemory()
        let github = FakeGitHub([])
        let creation = Mutation.CreateIssue(itemId: "local-card", contentId: "local-content", projectId: nil, repoId: "R1",
                                            repo: "octo/one", title: "Open while creating", body: "", assignees: [], labels: [], createdAt: Date())
        let local = try await database.writer.write { db in
            try Outbox.enqueue(db, .createIssue(creation))
            return try #require(try Item.fetchOne(db, key: creation.itemId))
        }
        let model = AppModel(database: database, api: github.api)
        for _ in 0..<viewCount {
            let appeared = try #require(model.detailAppeared(local))
            await appeared.value
        }
        #expect(await model.engine.watchedIssueId == creation.contentId)
        try await model.engine.pushPending()
        let serverId = try #require(model.status.idRemaps[creation.contentId])
        #expect(await model.engine.watchedIssueId == serverId)
        // Rendering may ask for the server model before RootView follows the acknowledgement.
        let shown = model.detail(for: serverId)
        if followBeforeClosing { model.follow(remaps: model.status.idRemaps) }
        for index in 0..<viewCount {
            let disappeared = model.detailDisappeared(local)
            if index + 1 < viewCount {
                #expect(disappeared == nil)
                #expect(model.detail(for: serverId) === shown)
                #expect(await model.engine.watchedIssueId == serverId)
            } else {
                let cleanup = try #require(disappeared)
                await cleanup.value
            }
        }
        #expect(await model.engine.watchedIssueId == nil)
        #expect(model.detail(for: serverId) !== shown)
    }
}
