import Foundation
import Testing
@testable import GitIssuesKit

@Suite("My Issues' overview: what you are doing and what comes next, by project")
struct MyIssuesOverviewTests {
    /// Noon of the tests' day.
    static let now = MyIssuesTests.today.date().addingTimeInterval(12 * 3600)
    static let projects = [(id: "P1", title: "App"), (id: "P2", title: "Website"), (id: "P3", title: "Docs")]

    func lanes(_ items: [Item], _ rules: MineRules, display: MineDisplay = MineDisplay()) -> [MineLane] {
        rules.lanes(items, projects: Self.projects, by: display, now: Self.now)
    }

    @Test("A project's issues go by what their status means; done ones count only from this week")
    func byKindOfStatus() {
        let items = (1...9).map { MyIssuesTests.item($0, updatedHoursAgo: $0 == 8 ? 24 * 10 : 1) }
        let rules = MyIssuesTests.rules(
            kinds: [1: .started, 2: .started, 3: .unstarted, 4: .unstarted, 5: .backlog, 7: .completed, 8: .completed, 9: .canceled],
            priorities: [2: .urgent, 1: .low, 4: .high]
        )
        let lane = try! #require(lanes(items, rules).first)
        #expect(lane.id == "project/P1")
        #expect(lane.title == "App")
        #expect(lane.started.compactMap(\.number) == [2, 1])
        #expect(lane.next.compactMap(\.number) == [4, 3])
        // The backlog, and the issue on the board without a status.
        #expect(lane.later == 2)
        #expect(lane.doneThisWeek == 1)
        #expect(lane.open == 6)
        #expect(!lane.isQuiet)
    }

    @Test("Projects come in the order given, those without your issues left out, the issues on no board last")
    func order() {
        let items = [
            MyIssuesTests.item(1, project: "P2"), MyIssuesTests.item(2, project: nil), MyIssuesTests.item(3, project: "P1"),
            MyIssuesTests.item(4, project: nil, closed: true),
        ]
        let rules = MyIssuesTests.rules(kinds: [1: .unstarted, 3: .started, 4: .completed])
        let result = lanes(items, rules)
        #expect(result.map(\.id) == ["project/P1", "project/P2", ListSection.noProjectId])
        let loose = try! #require(result.last)
        #expect(loose.projectId == nil)
        #expect(loose.next.compactMap(\.number) == [2])
        #expect(loose.doneThisWeek == 1)
    }

    @Test("Up next shows the most pressing few until the rest is unfolded")
    func shownNext() {
        let items = (1...5).map { MyIssuesTests.item($0) }
        let rules = MyIssuesTests.rules(
            kinds: Dictionary(uniqueKeysWithValues: (1...5).map { ($0, StatusCategory.unstarted) }),
            priorities: [5: .urgent, 3: .high, 1: .medium]
        )
        let lane = try! #require(lanes(items, rules).first)
        #expect(lane.shownNext(unfolded: false).compactMap(\.number) == [5, 3, 1])
        #expect(lane.moreNext(unfolded: false) == 2)
        #expect(lane.shownNext(unfolded: true).count == 5)
        #expect(lane.moreNext(unfolded: true) == 0)
        // Ordered by due date instead, the soonest come first.
        let byDue = [MyIssuesTests.item(1, due: 9), MyIssuesTests.item(2, due: 2), MyIssuesTests.item(3)]
        let dueRules = MyIssuesTests.rules(kinds: [1: .unstarted, 2: .unstarted, 3: .unstarted])
        #expect(lanes(byDue, dueRules, display: MineDisplay(order: .dueDate)).first?.next.compactMap(\.number) == [2, 1, 3])
    }

    @Test("Overdue counts the open issues whose due date has passed")
    func overdue() {
        let items = [
            MyIssuesTests.item(1, due: -2), MyIssuesTests.item(2, due: -1), MyIssuesTests.item(3, due: 1),
            MyIssuesTests.item(4, due: -3), MyIssuesTests.item(5, project: nil, due: -1),
        ]
        let rules = MyIssuesTests.rules(kinds: [1: .started, 2: .completed, 3: .unstarted, 4: .backlog])
        let result = lanes(items, rules)
        #expect(result.first?.overdue == 2)
        #expect(result.last?.overdue == 1)
    }

    @Test("A project with nothing started or to do is quiet")
    func quiet() {
        let items = [MyIssuesTests.item(1), MyIssuesTests.item(2, project: "P2")]
        let rules = MyIssuesTests.rules(kinds: [1: .backlog, 2: .started])
        let result = lanes(items, rules)
        #expect(result.map(\.isQuiet) == [true, false])
    }

    @Test("A started issue nobody touched for a week or more is idle")
    func idle() {
        let rules = MyIssuesTests.rules(kinds: [1: .started, 2: .started, 3: .unstarted])
        #expect(rules.idleDays(of: MyIssuesTests.item(1, updatedHoursAgo: 24 * 8), now: Self.now) == 8)
        #expect(rules.idleDays(of: MyIssuesTests.item(2, updatedHoursAgo: 24 * 2), now: Self.now) == nil)
        // Only work that has started can stop.
        #expect(rules.idleDays(of: MyIssuesTests.item(3, updatedHoursAgo: 24 * 30), now: Self.now) == nil)
    }

    @Test("What older versions kept starts with the overview; the layout is kept from then on")
    func storedDisplay() throws {
        let old = try #require(MineDisplay(stored: #"{"grouping":"project","order":"dueDate","descending":false}"#))
        #expect(old.layout == .overview)
        #expect(old.grouping == .project)
        #expect(old.order == .dueDate)
        let list = MineDisplay(layout: .list, grouping: .priority)
        #expect(MineDisplay(stored: list.stored) == list)
        // The list on its own isn't a change to the groups or the order.
        #expect(MineDisplay(layout: .list).optionsAreDefault)
        #expect(!MineDisplay(layout: .list).isDefault)
        #expect(!list.optionsAreDefault)
    }
}
