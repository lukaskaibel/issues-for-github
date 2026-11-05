import Foundation
import Testing
@testable import GitIssuesKit

@Suite("My Issues' cards: how the overview arranges them, where they stand, and what needs you")
struct MyIssuesCardsTests {
    static func lane(_ id: String, started: Int = 0, next: Int = 0, later: Int = 0, onNoBoard: Bool = false) -> MineLane {
        func items(_ count: Int, from start: Int) -> [Item] { (0..<count).map { MyIssuesTests.item(start + $0) } }
        var columns: [MineColumn] = []
        if onNoBoard {
            columns.append(MineColumn(key: MineColumn.noBoardKey, title: "On no board", kind: nil, optionId: nil, items: items(next, from: 200)))
        } else {
            if later > 0 { columns.append(MineColumn(key: "backlog", title: "Backlog", kind: .backlog, optionId: "S-b", items: items(later, from: 300))) }
            if next > 0 { columns.append(MineColumn(key: "todo", title: "Todo", kind: .unstarted, optionId: "S-t", items: items(next, from: 200))) }
            if started > 0 { columns.append(MineColumn(key: "in progress", title: "In Progress", kind: .started, optionId: "S-p", items: items(started, from: 100))) }
        }
        return MineLane(
            id: onNoBoard ? ListSection.noProjectId : "project/\(id)", projectId: onNoBoard ? nil : id, title: id, columns: columns
        )
    }

    static let lanes = [
        lane("none", next: 1, onNoBoard: true),
        lane("C", later: 4),
        lane("B", next: 3),
        lane("A", started: 2, next: 1),
    ]

    static let needsYou = MineSmartCard.needsYou.id

    @Test("Arranged by itself: what needs you first, then work started, things to do, quiet projects, no board last")
    func automatic() {
        let placed = MineArrangement().placed(Self.lanes, needsYou: true)
        #expect(placed == [Self.needsYou, "project/A", "project/B", "project/C", ListSection.noProjectId])
        // With nothing that needs you, there is no card for it.
        #expect(!MineArrangement().placed(Self.lanes, needsYou: false).contains(Self.needsYou))
    }

    @Test("What was taken out stays out, also while the overview arranges itself")
    func removed() {
        let arrangement = MineArrangement(removed: ["project/B", Self.needsYou])
        #expect(arrangement.placed(Self.lanes, needsYou: true) == ["project/A", "project/C", ListSection.noProjectId])
    }

    @Test("Arranged by hand: your order; projects not placed yet join at the end; gone ones wait")
    func byHand() {
        let arrangement = MineArrangement(automatic: false, order: ["project/B", Self.needsYou, "project/gone", "project/A"])
        #expect(arrangement.placed(Self.lanes, needsYou: false) == ["project/B", Self.needsYou, "project/A", "project/C", ListSection.noProjectId])
    }

    @Test("The arrangement reads back as written, and as the first overview wrote it, sizes and all")
    func codable() throws {
        let arrangement = MineArrangement(automatic: false, order: ["project/A", Self.needsYou], removed: ["project/B"])
        let data = try JSONEncoder().encode(arrangement)
        #expect(try JSONDecoder().decode(MineArrangement.self, from: data) == arrangement)
        // A device still on the first overview reads the cards as widgets of a size.
        let written = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let widgets = try #require(written["widgets"] as? [[String: String]])
        #expect(widgets.map { $0["id"] } == ["project/A", Self.needsYou])
        #expect(widgets.allSatisfy { $0["size"] != nil })
        // What it wrote: cards it had and this one hasn't, as Due this week, are left out.
        let old = #"{"automatic":false,"widgets":[{"id":"project/C","size":"large"},{"id":"smart/dueThisWeek","size":"medium"},{"id":"project/A","size":"small"}],"removed":["project/B"]}"#
        let read = try JSONDecoder().decode(MineArrangement.self, from: Data(old.utf8))
        #expect(read.order == ["project/C", "smart/dueThisWeek", "project/A"])
        #expect(read.placed(Self.lanes, needsYou: true) == ["project/C", "project/A", ListSection.noProjectId])
        #expect(MineSmartCard(id: "smart/dueThisWeek") == nil)
        #expect(MineSmartCard(id: Self.needsYou) == .needsYou)
    }

    @Test("Needs you: overdue, due today, urgent and not started, idle, on no board, in that order, each issue once")
    func needsYouOrder() {
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
            MineLane(id: "project/P1", projectId: "P1", title: "P1", columns: [
                MineColumn(key: "in progress", title: "In Progress", kind: .started, optionId: "S-p", items: [idle, overdue]),
                MineColumn(key: "todo", title: "Todo", kind: .unstarted, optionId: "S-t", items: [urgent, today, calm, overdueLonger]),
            ]),
            MineLane(id: ListSection.noProjectId, projectId: nil, title: "None", columns: [
                MineColumn(key: MineColumn.noBoardKey, title: "On no board", kind: nil, optionId: nil, items: [loose]),
            ]),
        ]
        let entries = rules.needsYou(lanes, now: MyIssuesOverviewTests.now)
        #expect(entries.compactMap(\.item.number) == [7, 1, 2, 3, 4, 6])
        #expect(entries.map(\.reason) == [.overdue, .overdue, .dueToday, .urgent, .idle, .onNoBoard])
        #expect(entries.first?.days == 5)
    }

    @Test("Cards fill the window: three across in a 1440-point window, two rows high, one size for all")
    func layout() {
        let metrics = OverviewGridLayout.Metrics.standard
        // The overview of a 1440 × 900 window: the sidebar and toolbar taken off.
        let wide = OverviewGridLayout(width: 1220, height: 848, count: 6, metrics: metrics)
        #expect(wide.columns == 3)
        #expect(wide.card == CGSize(width: 382, height: 400))
        #expect(wide.origin(4) == CGPoint(x: 20 + 382 + 16, y: 8 + 400 + 16))
        #expect(wide.rowsPerPage == 11)
        // Where a card held by its name would land: the place whose middle is nearest its middle.
        #expect(wide.nearestIndex(to: CGPoint(x: 1000, y: 700)) == 5)
        #expect(wide.nearestIndex(to: CGPoint(x: 10, y: 10)) == 0)
        // The narrowest three: a 1280-point window; narrower than that, two wider ones.
        #expect(OverviewGridLayout(width: 1060, height: 748, count: 6, metrics: metrics).card.width == 329)
        #expect(OverviewGridLayout(width: 900, height: 748, count: 6, metrics: metrics).columns == 2)
        // A single row of cards doesn't stretch to the bottom of a tall window.
        #expect(OverviewGridLayout(width: 1220, height: 1400, count: 2, metrics: metrics).card.height == metrics.maxCardHeight)
    }
}
