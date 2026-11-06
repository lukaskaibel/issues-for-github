import Foundation
import Testing
@testable import GitIssuesKit

/// Issues asks for a rating on the App Store once it was used on three days, as you finish an issue, at most once a
/// version and two months apart.
@Suite("Asking for a rating on the App Store")
@MainActor
struct AppReviewTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    private func day(_ number: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: number, hour: hour))!
    }

    /// A defaults domain of its own, gone after the test.
    private func withDefaults(_ body: (UserDefaults) async throws -> Void) async rethrows {
        let name = "issues-review-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try await body(defaults)
    }

    /// Lets the main queue run what was put on it, as the prompt is.
    private func settle() async {
        await withCheckedContinuation { done in DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { done.resume() } }
    }

    // MARK: - When

    @Test func asksOnlyOnceUsedOnThreeDays() {
        var record = ReviewRecord()
        let first = record.use(on: day(1), calendar: calendar)
        let sameDay = record.use(on: day(1, hour: 20), calendar: calendar)
        let second = record.use(on: day(2), calendar: calendar)
        #expect(first && !sameDay && second, "the same day counted twice")
        #expect(!record.isDue(version: "1.2.0", at: day(2)))
        let third = record.use(on: day(9), calendar: calendar)
        #expect(third)
        #expect(record.isDue(version: "1.2.0", at: day(9)))
        #expect(record.daysUsed == ["2026-11-01", "2026-11-02", "2026-11-09"])
    }

    @Test func asksOnceAVersionAndTwoMonthsApart() {
        var record = ReviewRecord(daysUsed: ["2026-11-01", "2026-11-02", "2026-11-03"])
        record.asked(version: "1.2.0", at: day(3))
        #expect(!record.isDue(version: "1.2.0", at: day(3).addingTimeInterval(200 * 24 * 3600)), "twice in a version")
        #expect(!record.isDue(version: "1.3.0", at: day(20)), "another version three weeks later")
        #expect(record.isDue(version: "1.3.0", at: day(3).addingTimeInterval(61 * 24 * 3600)))
    }

    // MARK: - Asking

    @Test func asksOnceTheTimeHasComeAndRemembersIt() async {
        await withDefaults { defaults in
            let review = AppReview(defaults: defaults, version: "1.2.0", mayAsk: true)
            var prompts = 0
            review.prompt = { prompts += 1; return true }
            review.delay = 0
            review.finishedSomething()
            await settle()
            #expect(prompts == 0, "asked before it was started: signed out, or on sample data")
            review.start()
            review.finishedSomething()
            await settle()
            #expect(prompts == 0, "asked on the first day")
            review.used(on: Date().addingTimeInterval(-2 * 24 * 3600))
            review.used(on: Date().addingTimeInterval(-24 * 3600))
            review.finishedSomething()
            await settle()
            #expect(prompts == 1)
            review.finishedSomething()
            await settle()
            #expect(prompts == 1, "asked twice in a version")
            #expect(AppReview(defaults: defaults, version: "1.2.0", mayAsk: true).record.askedVersion == "1.2.0", "not remembered")
        }
    }

    @Test func notWhenItNoLongerFitsOrThereIsNoWindow() async {
        await withDefaults { defaults in
            defaults.set(["2026-11-01", "2026-11-02", "2026-11-03"], forKey: "review.daysUsed")
            let review = AppReview(defaults: defaults, version: "1.2.0", mayAsk: true)
            var prompts = 0
            review.prompt = { prompts += 1; return false }
            review.delay = 0
            review.start()
            review.finishedSomething { false }
            await settle()
            #expect(prompts == 0)
            review.finishedSomething()
            await settle()
            #expect(prompts == 1)
            #expect(review.record.askedVersion == nil, "remembered as asked without a window to ask in")
        }
    }

    /// Debug builds, where the system shows its prompt every time, ask only when told to, and then every time.
    @Test func debugBuildsAskOnlyWhenTold() async {
        await withDefaults { defaults in
            defaults.set(["2026-11-01", "2026-11-02", "2026-11-03"], forKey: "review.daysUsed")
            let review = AppReview(defaults: defaults, version: "1.2.0", mayAsk: false)
            var prompts = 0
            review.prompt = { prompts += 1; return true }
            review.delay = 0
            review.start()
            review.finishedSomething()
            await settle()
            #expect(prompts == 0)
            defaults.set(true, forKey: "debugAsksForReview")
            review.finishedSomething()
            await settle()
            review.finishedSomething()
            await settle()
            #expect(prompts == 2)
            #expect(review.record.askedVersion == nil)
        }
    }

    // MARK: - The moment

    @Test func finishingAnIssueIsTheMoment() {
        let columns: [String: StatusCategory] = ["todo": .unstarted, "doing": .started, "done": .completed, "wontdo": .canceled]
        func finishes(_ mutation: Mutation) -> Bool {
            mutation.finishesWork { projectId, optionId in projectId == "P" ? columns[optionId] : nil }
        }
        func column(_ id: String?) -> Mutation {
            .setField(.init(itemId: "I", projectId: "P", fieldId: "status", kind: .status, optionId: id, base: "doing"))
        }
        #expect(finishes(.setState(.init(contentId: "C", closed: true, reason: "COMPLETED"))))
        #expect(finishes(.setState(.init(contentId: "C", closed: true, reason: nil))))
        #expect(!finishes(.setState(.init(contentId: "C", closed: true, reason: "NOT_PLANNED"))), "cancelled")
        #expect(!finishes(.setState(.init(contentId: "C", closed: false, reason: nil))), "reopened")
        #expect(finishes(column("done")))
        #expect(!finishes(column("doing")))
        #expect(!finishes(column("wontdo")))
        #expect(!finishes(column(nil)), "out of every column")
        #expect(!finishes(.setField(.init(itemId: "I", projectId: "P", fieldId: "prio", kind: .priority, optionId: "done", base: nil))),
                "another field's option")
        #expect(!finishes(.move(.init(itemId: "I", projectId: "P", afterItemId: nil))))
    }
}
