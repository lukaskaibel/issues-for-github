import Foundation
import Testing
@testable import GitIssuesKit

@Suite("The order an issue lists its sub-issues in")
struct SubIssueOrderTests {
    /// A sub-issue numbered `number`, as GitHub lists it among the others.
    struct Sub {
        var number: Int
        var key: SubIssueOrder.Key
    }

    static func sub(
        _ number: Int, done: Bool = false, priority: PriorityLevel = .none, statusRank: Int = 0, created: Double? = nil
    ) -> Sub {
        Sub(number: number, key: SubIssueOrder.Key(
            done: done, priority: priority, statusRank: statusRank,
            createdAt: created.map { Date(timeIntervalSince1970: $0) }, number: number
        ))
    }

    private func numbers(_ order: SubIssueOrder, _ subs: [Sub]) -> [Int] {
        order.arrange(subs, key: \.key).map(\.number)
    }

    @Test("By priority, the most urgent comes first and those without one last; ties keep GitHub's order")
    func ordersByPriority() {
        let subs = [
            Self.sub(1, priority: .low), Self.sub(2), Self.sub(3, priority: .urgent),
            Self.sub(4, priority: .medium), Self.sub(5, priority: .urgent), Self.sub(6, priority: .high),
        ]
        #expect(numbers(.priority, subs) == [3, 5, 6, 4, 1, 2])
    }

    @Test("Done ones go last in every order but GitHub's")
    func putsDoneLast() {
        let subs = [
            Self.sub(1, done: true, priority: .urgent, statusRank: 0, created: 300),
            Self.sub(2, priority: .low, statusRank: 2, created: 100),
            Self.sub(3, done: true, priority: .high, statusRank: 1, created: 200),
            Self.sub(4, statusRank: 3, created: 50),
        ]
        #expect(numbers(.priority, subs) == [2, 4, 1, 3])
        #expect(numbers(.status, subs) == [2, 4, 1, 3])
        #expect(numbers(.newest, subs) == [2, 4, 1, 3])
        #expect(numbers(.github, subs) == [1, 2, 3, 4])
    }

    @Test("By status, the smaller rank comes first")
    func ordersByStatus() {
        let subs = [Self.sub(1, statusRank: 10_000), Self.sub(2, statusRank: 9_998), Self.sub(3, statusRank: 9_999)]
        #expect(numbers(.status, subs) == [2, 3, 1])
    }

    @Test("Newest first by when they were opened, then by number; one not yet on GitHub is the newest")
    func ordersNewestFirst() {
        let subs = [
            Self.sub(4, created: 100), Self.sub(9, created: 300), Self.sub(7), Self.sub(8), Self.sub(0, created: 50),
        ]
        // Dates first; without one, by number, and a sub-issue not yet sent (number 0) first among those.
        #expect(numbers(.newest, subs) == [9, 4, 0, 8, 7])
        #expect(numbers(.newest, [Self.sub(3), Self.sub(0), Self.sub(5)]) == [0, 5, 3])
    }

    @Test("GitHub's order is left as it is")
    func keepsGitHubOrder() {
        let subs = [Self.sub(3, priority: .low), Self.sub(1, priority: .urgent), Self.sub(2, done: true)]
        #expect(numbers(.github, subs) == [3, 1, 2])
    }
}
