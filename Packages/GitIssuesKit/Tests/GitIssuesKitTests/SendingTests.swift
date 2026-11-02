import Foundation
import GRDB
import Synchronization
import Testing
@testable import GitIssuesKit

@Suite("A change made while an earlier one to the same thing is on its way to GitHub")
struct SendingTests {
    /// Something set to another value and back, the second time while GitHub has the first change but the app hasn't
    /// heard back yet.
    enum Change: String, CaseIterable, CustomTestStringConvertible, Sendable {
        case milestone, parent, blocker, title, body

        var testDescription: String { rawValue }

        /// The change away from how GitHub has it, as the app queues it: knowing what the screen showed before.
        var away: Mutation {
            switch self {
            case .milestone: .setMilestone(.init(contentId: "I_1", isPullRequest: false, milestoneId: "M_2", milestoneTitle: "1.1", base: "M_1"))
            case .parent: .setParent(.init(child: summary(3), parentId: "I_2", parentNumber: 2, parentTitle: "Issue 2", base: "I_1"))
            case .blocker: .setBlocking(.init(blocked: summary(1), blocker: summary(2), isBlocked: true, base: false))
            case .title: .setTitle(.init(itemId: "PVTI_1", contentId: "I_1", value: "Sign in with a passkey", base: "Sign in"))
            case .body: .setBody(.init(itemId: "PVTI_1", contentId: "I_1", value: "Crashes on launch.\n\nOnly on iPad.", base: "Crashes on launch."))
            }
        }

        /// The change back, which knows the first one's value as what was shown.
        var back: Mutation {
            switch self {
            case .milestone: .setMilestone(.init(contentId: "I_1", isPullRequest: false, milestoneId: "M_1", milestoneTitle: "1.0", base: "M_2"))
            case .parent: .setParent(.init(child: summary(3), parentId: "I_1", parentNumber: 1, parentTitle: "Sign in", base: "I_2"))
            case .blocker: .setBlocking(.init(blocked: summary(1), blocker: summary(2), isBlocked: false, base: true))
            case .title: .setTitle(.init(itemId: "PVTI_1", contentId: "I_1", value: "Sign in", base: "Sign in with a passkey"))
            case .body: .setBody(.init(itemId: "PVTI_1", contentId: "I_1", value: "Crashes on launch.", base: "Crashes on launch.\n\nOnly on iPad."))
            }
        }

        /// What GitHub has at the start, and so after both changes.
        var original: String {
            switch self {
            case .milestone: "M_1"
            case .parent: "I_1"
            case .blocker: ""
            case .title: "Sign in"
            case .body: "Crashes on launch."
            }
        }

        func onGitHub(_ github: FakeGitHub) -> String? {
            let issue = github.issue(self == .parent ? "I_3" : "I_1")
            return switch self {
            case .milestone: issue?.milestone
            case .parent: issue?.parent
            case .blocker: issue?.blockedBy.joined(separator: ", ")
            case .title: issue?.title
            case .body: issue?.body
            }
        }

        /// What the app asks of GitHub to send both changes.
        var requests: [String] {
            switch self {
            case .milestone: ["milestone I_1: M_2", "milestone I_1: M_1"]
            case .parent: ["parent I_3: I_2", "parent I_3: I_1"]
            case .blocker: ["blocked I_1 by I_2", "unblocked I_1 by I_2"]
            case .title, .body: ["text I_1", "update I_1", "text I_1", "update I_1"]
            }
        }

        private func summary(_ number: Int) -> IssueSummary {
            IssueSummary(contentId: "I_\(number)", number: number, title: "Issue \(number)", state: "OPEN")
        }
    }

    /// Something a hook on the fake's thread notes, for the test to look at afterwards.
    private final class Noted<Value: Sendable>: Sendable {
        let value: Mutex<Value>
        init(_ value: Value) { self.value = Mutex(value) }
    }

    /// #1 in milestone 1.0 and blocked by nothing, #3 a sub-issue of #1, all read from GitHub.
    private func fixture() async throws -> (FakeGitHub, AppDatabase, SyncEngine) {
        let github = FakeGitHub([
            .init(contentId: "I_1", number: 1, itemId: "PVTI_1", title: "Sign in", body: "Crashes on launch.", milestone: "M_1"),
            .init(contentId: "I_2", number: 2, itemId: "PVTI_2"),
            .init(contentId: "I_3", number: 3, itemId: "PVTI_3", parent: "I_1"),
        ])
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
        try await engine.pull(projectId: FakeGitHub.projectId)
        _ = github.requests()
        return (github, db, engine)
    }

    private func states(_ db: AppDatabase) async throws -> [OutboxState] {
        try await db.reader.read { try OutboxEntry.order(Column("id")).fetchAll($0).map(\.state) }
    }

    @Test(arguments: Change.allCases)
    func changingBackWhileTheFirstChangeIsSentEndsWhereItStarted(_ change: Change) async throws {
        let (github, db, engine) = try await fixture()
        try await db.writer.write { try Outbox.enqueue($0, change.away) }
        let seen = Noted<[OutboxState]?>(nil)
        github.afterNextWrite {
            seen.value.withLock {
                $0 = try? db.writer.write { db in
                    try Outbox.enqueue(db, change.back)
                    return try OutboxEntry.order(Column("id")).fetchAll(db).map(\.state)
                }
            }
        }
        try await engine.pushPending()

        // The first change may have reached GitHub, so the second wasn't folded into it: it sends what was chosen last.
        #expect(seen.value.withLock { $0 } == [.sending, .pending])
        #expect(github.requests() == change.requests)
        #expect(change.onGitHub(github) == change.original)
        #expect(try await states(db) == [.sent, .sent])
    }

    @Test func aChangeWhoseSendingBrokeOffGoesOutAgainBeforeANewerOne() async throws {
        let (github, db, _) = try await fixture()
        try await db.writer.write { db in
            try Outbox.enqueue(db, Change.milestone.away)
            // As left when the app quit before GitHub answered.
            try db.execute(sql: "UPDATE outbox SET state = ?", arguments: [OutboxState.sending.rawValue])
            try Outbox.enqueue(db, Change.milestone.back)
        }
        #expect(try await states(db) == [.sending, .pending])

        let status = await MainActor.run { SyncStatus() }
        let restarted = SyncEngine(db: db, api: github.api, status: status)
        try await restarted.pushPending()
        #expect(github.requests() == Change.milestone.requests)
        #expect(Change.milestone.onGitHub(github) == "M_1")
    }

    @Test func twoSendsAtOnceSendAChangeOnce() async throws {
        let (github, db, engine) = try await fixture()
        try await db.writer.write { try Outbox.enqueue($0, Change.milestone.away) }
        let second = Noted<Task<Void, Error>?>(nil)
        github.afterNextWrite {
            // Leaving the app sends what is queued, while a sync round still waits for GitHub's answer.
            second.value.withLock { $0 = Task { try await engine.pushPending() } }
            Thread.sleep(forTimeInterval: 0.3)
        }
        try await engine.pushPending()
        try await #require(second.value.withLock { $0 }).value

        #expect(github.requests() == ["milestone I_1: M_2"])
        #expect(try await states(db) == [.sent])
    }

    @Test func aTextEditBeingSentStaysSoWhenAReadFindsGitHubWhereItStarted() async throws {
        let (github, db, engine) = try await fixture()
        try await db.writer.write { db in
            try Outbox.enqueue(db, Change.title.away)
            try db.execute(sql: "UPDATE outbox SET state = ?", arguments: [OutboxState.sending.rawValue])
        }
        // GitHub doesn't have it yet, as far as a read can tell.
        github.rename("I_1", to: "Sign in")
        try await engine.pull(projectId: FakeGitHub.projectId)
        #expect(github.requests().contains("cards"))
        #expect(try await states(db) == [.sending])

        // So the change back is still a change of its own.
        try await db.writer.write { try Outbox.enqueue($0, Change.title.back) }
        #expect(try await states(db) == [.sending, .pending])
    }
}
