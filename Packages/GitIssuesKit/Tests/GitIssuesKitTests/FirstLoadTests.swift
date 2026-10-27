import Foundation
import Testing
@testable import GitIssuesKit

@Suite("Projects never fetched load one right after another")
struct FirstLoadTests {
    private let never = TimeInterval.infinity

    @Test func neverFetchedProjectsComeFirstAndDontWaitForThePoll() {
        // Right after launch every project is due; the one never fetched goes ahead, and another such one waits.
        let pick = SyncEngine.nextBackgroundProject(
            open: ["fetched", "new1", "new2"], unfetched: ["new1", "new2"], active: nil, age: { _ in never }
        )
        #expect(pick?.next == "new1")
        #expect(pick?.more == true)

        // The last of them: the polls go back to their pace.
        let last = SyncEngine.nextBackgroundProject(
            open: ["fetched", "new2"], unfetched: ["new2"], active: nil, age: { _ in never }
        )
        #expect(last?.next == "new2")
        #expect(last?.more == false)
    }

    @Test func theBoardOnScreenAndProjectsReadLatelyAreLeftOut() {
        // The board on screen has its own pull; one that couldn't be read is tried again in five minutes, not at once.
        let ages = ["active": never, "failed": 10, "new": never, "fetched": 400]
        let pick = SyncEngine.nextBackgroundProject(
            open: ["active", "failed", "new", "fetched"], unfetched: ["active", "failed", "new"], active: "active",
            age: { ages[$0] ?? never }
        )
        #expect(pick?.next == "new")
        #expect(pick?.more == false)

        // With everything read lately, nothing is pulled in the background.
        #expect(SyncEngine.nextBackgroundProject(open: ["a", "b"], unfetched: [], active: nil, age: { _ in 60 }) == nil)
    }

    @Test func fetchedProjectsAreRefreshedOnePerRoundAsBefore() {
        let pick = SyncEngine.nextBackgroundProject(open: ["a", "b"], unfetched: [], active: nil, age: { _ in never })
        #expect(pick?.next == "a")
        #expect(pick?.more == false)
    }
}
