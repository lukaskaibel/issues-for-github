import Foundation
import Testing
@testable import GitIssuesKit

@Suite("My Issues' widgets: how the overview arranges itself or as you put it, and what needs you")
struct MyIssuesWidgetsTests {
    static func lane(_ id: String, started: Int = 0, next: Int = 0, later: Int = 0, onNoBoard: Bool = false) -> MineLane {
        func items(_ count: Int, from start: Int) -> [Item] { (0..<count).map { MyIssuesTests.item(start + $0) } }
        return MineLane(
            id: onNoBoard ? ListSection.noProjectId : "project/\(id)", projectId: onNoBoard ? nil : id, title: id,
            started: items(started, from: 100), next: items(next, from: 200), later: later, overdue: 0
        )
    }

    static let lanes = [
        lane("A", started: 2, next: 1),
        lane("B", next: 3),
        lane("C", later: 4),
        lane("none", next: 1, onNoBoard: true),
    ]

    func ids(_ widgets: [MineWidget]) -> [String] { widgets.map(\.id) }

    @Test("Arranged by itself: work started first and large, then what needs you, to-do only medium, the rest small")
    func automatic() {
        let placed = MineArrangement().placed(Self.lanes, needsYou: true)
        #expect(ids(placed) == ["project/A", "smart/needsYou", "project/B", "project/C", ListSection.noProjectId])
        #expect(placed.map(\.size) == [.large, .medium, .medium, .small, .small])
        // With nothing that needs you, there is no widget for it.
        #expect(!ids(MineArrangement().placed(Self.lanes, needsYou: false)).contains("smart/needsYou"))
    }

    @Test("What was taken out stays out, also while the overview arranges itself")
    func removed() {
        let arrangement = MineArrangement(removed: ["project/B", "smart/needsYou"])
        #expect(ids(arrangement.placed(Self.lanes, needsYou: true)) == ["project/A", "project/C", ListSection.noProjectId])
    }

    @Test("Arranged by hand: your order and sizes; projects not placed yet join at the end; gone ones wait")
    func byHand() {
        let arrangement = MineArrangement(automatic: false, widgets: [
            MineWidget(id: "project/B", size: .small),
            MineWidget(id: "smart/doneThisWeek", size: .medium),
            MineWidget(id: "project/gone", size: .large),
            MineWidget(id: "project/A", size: .medium),
        ])
        let placed = arrangement.placed(Self.lanes, needsYou: true)
        #expect(ids(placed) == ["project/B", "smart/doneThisWeek", "project/A", "project/C", ListSection.noProjectId])
        #expect(placed.map(\.size) == [.small, .medium, .medium, .small, .small])
    }

    @Test("An arrangement reads back as it was written, for iCloud")
    func codable() throws {
        let arrangement = MineArrangement(automatic: false, widgets: [MineWidget(id: "project/A", size: .large)], removed: ["project/B"])
        let data = try JSONEncoder().encode(arrangement)
        #expect(try JSONDecoder().decode(MineArrangement.self, from: data) == arrangement)
        #expect(MineSmartWidget(id: MineSmartWidget.dueThisWeek.id) == .dueThisWeek)
        #expect(MineSmartWidget(id: "project/A") == nil)
    }

    @Test("Needs you: overdue, due today, urgent and not started, idle, on no board, in that order, each issue once")
    func needsYou() {
        let overdue = MyIssuesTests.item(1, due: -3)
        let today = MyIssuesTests.item(2, due: 0)
        let urgent = MyIssuesTests.item(3)
        let idle = MyIssuesTests.item(4, updatedHoursAgo: 24 * 10)
        let calm = MyIssuesTests.item(5)
        let loose = MyIssuesTests.item(6, project: nil)
        let overdueLonger = MyIssuesTests.item(7, due: -5)
        let rules = MyIssuesTests.rules(
            kinds: [1: .started, 2: .unstarted, 3: .unstarted, 4: .started, 5: .unstarted, 7: .unstarted],
            priorities: [3: .urgent, 2: .urgent]
        )
        let lanes = [
            MineLane(id: "project/P1", projectId: "P1", title: "P1", started: [idle, overdue], next: [urgent, today, calm, overdueLonger], later: 0, overdue: 2),
            MineLane(id: ListSection.noProjectId, projectId: nil, title: "None", started: [], next: [loose], later: 0, overdue: 0),
        ]
        let entries = rules.needsYou(lanes, now: MyIssuesOverviewTests.now)
        #expect(entries.compactMap(\.item.number) == [7, 1, 2, 3, 4, 6])
        #expect(entries.map(\.reason) == [.overdue, .overdue, .dueToday, .urgent, .idle, .onNoBoard])
        #expect(entries.first?.days == 5)
    }

    @Test("Due this week: open issues due from today to seven days on, soonest first")
    func dueThisWeek() {
        let items = [MyIssuesTests.item(1, due: 9), MyIssuesTests.item(2, due: 3), MyIssuesTests.item(3, due: -1), MyIssuesTests.item(4, due: 0)]
        let lanes = [MineLane(id: "project/P1", projectId: "P1", title: "P1", started: [], next: items, later: 0, overdue: 1)]
        #expect(MyIssuesTests.rules().dueThisWeek(lanes).compactMap(\.number) == [4, 2])
    }
}
