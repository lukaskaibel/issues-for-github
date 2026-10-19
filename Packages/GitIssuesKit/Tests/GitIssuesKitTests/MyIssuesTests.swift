import Foundation
import Testing
@testable import GitIssuesKit

@Suite("My Issues' filter and order, across projects")
struct MyIssuesTests {
    static let today = CalendarDay(year: 2026, month: 10, day: 19)

    /// An issue assigned to you; `project` nil puts it on no board.
    static func item(
        _ number: Int, project: String? = "P1", labels: [String] = [], closed: Bool = false, due: Int? = nil,
        updatedHoursAgo: Double = 1, created: Int = 0
    ) -> Item {
        Item(
            id: "item-\(number)", projectId: project, kind: .issue, position: Double(number),
            dueDate: due.map { today.adding(days: $0).string },
            contentId: "I\(number)", number: number, title: "Issue \(number)", body: "", state: closed ? "CLOSED" : "OPEN",
            stateReason: closed ? "COMPLETED" : nil, repo: "acme/app",
            createdAt: today.adding(days: created).date(),
            updatedAt: today.date().addingTimeInterval(-updatedHoursAgo * 3600),
            assignees: [Person(id: "U-me", login: "me")],
            labels: labels.map { LabelRef(id: "L-\($0)", name: $0, color: "ffffff") }
        )
    }

    /// The rules with what the app works out of each issue: the kind of its status and the level of its priority.
    static func rules(kinds: [Int: StatusCategory] = [:], priorities: [Int: PriorityLevel] = [:]) -> MineRules {
        var rules = MineRules(context: FilterContext(
            viewerLogin: "me", today: today, fields: [], statusFieldId: nil, priorityFieldId: nil, dueFieldId: nil,
            optionName: { _, _ in nil }, parentReference: { _ in nil }
        ))
        for (number, kind) in kinds { rules.kinds["item-\(number)"] = kind }
        for (number, level) in priorities { rules.priorities["item-\(number)"] = level }
        return rules
    }

    func shown(_ filter: String, _ items: [Item], _ rules: MineRules) -> [Int] {
        items.filter { rules.matches($0, ProjectFilter(filter)) }.compactMap(\.number)
    }

    // MARK: Filter

    @Test("Projects are picked by id, and issues on no board as no project")
    func byProject() {
        let items = [Self.item(1, project: "P1"), Self.item(2, project: "P2"), Self.item(3, project: nil)]
        let rules = Self.rules()
        #expect(shown("project:P1", items, rules) == [1])
        #expect(shown("project:P1,P2", items, rules) == [1, 2])
        #expect(shown("-project:P1", items, rules) == [2, 3])
        #expect(shown("no:project", items, rules) == [3])
        #expect(shown("has:project", items, rules) == [1, 2])
    }

    @Test("Status is compared by what it means, whatever each project calls it")
    func byKindOfStatus() {
        let items = (1...5).map { Self.item($0) }
        let rules = Self.rules(kinds: [1: .started, 2: .unstarted, 3: .completed, 4: .started])
        #expect(shown("status:started", items, rules) == [1, 4])
        #expect(shown("status:todo,done", items, rules) == [2, 3])
        #expect(shown("-status:done", items, rules) == [1, 2, 4, 5])
        #expect(shown("no:status", items, rules) == [5])
    }

    @Test("Priority is compared by level, so P0 in one project and Urgent in another are the same")
    func byPriorityLevel() {
        let items = (1...4).map { Self.item($0) }
        let rules = Self.rules(priorities: [1: .urgent, 2: .high, 3: .low])
        #expect(shown("priority:urgent,high", items, rules) == [1, 2])
        #expect(shown("priority:URGENT", items, rules) == [1])
        #expect(shown("-priority:low", items, rules) == [1, 2, 4])
        #expect(shown("no:priority", items, rules) == [4])
    }

    @Test("Due dates: overdue, today, the next seven days, with or without one")
    func byDueDate() {
        let items = [Self.item(1, due: -3), Self.item(2, due: 0), Self.item(3, due: 5), Self.item(4, due: 20), Self.item(5)]
        let rules = Self.rules()
        #expect(shown("due:<@today", items, rules) == [1])
        #expect(shown("due:@today", items, rules) == [2])
        #expect(shown("due:@today..@today+7d", items, rules) == [2, 3])
        #expect(shown("has:due", items, rules) == [1, 2, 3, 4])
        #expect(shown("no:due", items, rules) == [5])
    }

    @Test("Labels, open or closed, and several terms together")
    func labelsStateAndTogether() {
        let items = [Self.item(1, labels: ["bug"]), Self.item(2, labels: ["ui"], closed: true), Self.item(3, project: nil, labels: ["bug"])]
        let rules = Self.rules(priorities: [1: .urgent, 3: .urgent])
        #expect(shown("label:bug", items, rules) == [1, 3])
        #expect(shown("no:label", items, rules) == [])
        #expect(shown("is:open", items, rules) == [1, 3])
        #expect(shown("label:bug priority:urgent has:project", items, rules) == [1])
    }

    @Test("The chips know My Issues' own words and nothing else")
    func understands() {
        func knows(_ text: String) -> Bool {
            ProjectFilter(text).terms.allSatisfy { MineRules.understands($0, today: Self.today) }
        }
        #expect(knows("project:PVT_1 status:started,done priority:urgent due:<@today no:due has:project label:bug is:open"))
        #expect(!knows("status:Doing"))
        #expect(!knows("priority:P0"))
        #expect(!knows("iteration:@current"))
        #expect(!knows("chat"))
    }

    // MARK: Order

    @Test("By priority: most urgent first, ties by due date, without a priority last")
    func ordersByPriority() {
        let items = [Self.item(1), Self.item(2, due: 9), Self.item(3, due: 2), Self.item(4), Self.item(5)]
        let rules = Self.rules(priorities: [2: .high, 3: .high, 4: .urgent, 5: .low])
        let order = rules.sorted(items, by: MineDisplay()).compactMap(\.number)
        #expect(order == [4, 3, 2, 5, 1])
        // The other way round, those without a priority still come last, as in a view.
        let reversed = rules.sorted(items, by: MineDisplay(order: .priority, descending: true)).compactMap(\.number)
        #expect(reversed == [5, 3, 2, 4, 1])
    }

    @Test("By due date soonest first, by changes newest first, and as the boards have them")
    func ordersByDatesAndManually() {
        let items = [Self.item(1, due: 4, updatedHoursAgo: 5), Self.item(2, updatedHoursAgo: 1), Self.item(3, due: -1, updatedHoursAgo: 9)]
        let rules = Self.rules()
        #expect(rules.sorted(items, by: MineDisplay(order: .dueDate)).compactMap(\.number) == [3, 1, 2])
        #expect(rules.sorted(items, by: MineDisplay(order: .updated, descending: true)).compactMap(\.number) == [2, 1, 3])
        #expect(rules.sorted(items, by: MineDisplay(order: .manual)).compactMap(\.number) == [1, 2, 3])
    }

    @Test("A new order starts in its own direction")
    func ordersStartInTheirDirection() {
        #expect(MineOrder.updated.descendsByDefault)
        #expect(MineOrder.created.descendsByDefault)
        #expect(!MineOrder.priority.descendsByDefault)
        #expect(!MineOrder.dueDate.descendsByDefault)
        #expect(MineDisplay().grouping == .status)
        #expect(MineDisplay().order == .priority)
    }

    // MARK: Groups

    @Test("Grouped by due date, done issues leave the dates for a group of their own")
    func dueGroups() {
        func group(_ due: Int?, done: Bool = false) -> MineRules.DueGroup {
            MineRules.dueGroup(of: Self.item(1, due: due), done: done, today: Self.today)
        }
        #expect(group(-1) == .overdue)
        #expect(group(0) == .today)
        #expect(group(1) == .nextWeek)
        #expect(group(7) == .nextWeek)
        #expect(group(8) == .later)
        #expect(group(nil) == .none)
        #expect(group(-5, done: true) == .done)
    }
}
