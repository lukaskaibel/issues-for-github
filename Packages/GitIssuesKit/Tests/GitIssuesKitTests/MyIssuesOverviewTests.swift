import Foundation
import Testing
@testable import GitIssuesKit

@Suite("My Issues' overview: a card per project, with a page for each column of its board")
struct MyIssuesOverviewTests {
    /// Noon of the tests' day.
    static let now = MyIssuesTests.today.date().addingTimeInterval(12 * 3600)
    static let projects = [(id: "P1", title: "App"), (id: "P2", title: "Website"), (id: "P3", title: "Docs")]

    /// The board of the tests: Backlog, Todo, In Progress, In Review, Done, in that order.
    static let board: [String: (name: String, position: Int)] = [
        "backlog": ("Backlog", 0), "todo": ("Todo", 1), "progress": ("In Progress", 2), "review": ("In Review", 3), "done": ("Done", 4),
    ]

    /// Rules that also know which column each issue is in, by the board's keys above.
    static func rules(kinds: [Int: StatusCategory], priorities: [Int: PriorityLevel] = [:], columns: [Int: String]) -> MineRules {
        var rules = MyIssuesTests.rules(kinds: kinds, priorities: priorities)
        for (number, key) in columns {
            let column = board[key]!
            rules.columns["item-\(number)"] = MineColumnRef(optionId: "S-\(key)", name: column.name, position: column.position)
        }
        return rules
    }

    func lanes(_ items: [Item], _ rules: MineRules, display: MineDisplay = MineDisplay()) -> [MineLane] {
        rules.lanes(items, projects: Self.projects, by: display, now: Self.now, doneTitle: "Done this week", noStatusTitle: "No status", noBoardTitle: "On no board", noProjectTitle: "No project")
    }

    @Test("Open issues go to their board's column: started ones first, then to do, then the backlog; done this week last")
    func columns() throws {
        let items = (1...9).map { MyIssuesTests.item($0, updatedHoursAgo: $0 == 8 ? 24 * 10 : 1) }
        let rules = Self.rules(
            kinds: [1: .started, 2: .started, 3: .unstarted, 4: .unstarted, 5: .backlog, 7: .completed, 8: .completed, 9: .canceled],
            priorities: [4: .high],
            columns: [1: "progress", 2: "review", 3: "todo", 4: "todo", 5: "backlog", 7: "done", 8: "done", 9: "done"]
        )
        let lane = try #require(lanes(items, rules).first)
        #expect(lane.id == "project/P1")
        #expect(lane.title == "App")
        #expect(lane.columns.map(\.key) == ["in progress", "in review", "todo", "backlog", MineColumn.noStatusKey, MineColumn.doneKey])
        #expect(lane.columns.map(\.title) == ["In Progress", "In Review", "Todo", "Backlog", "No status", "Done this week"])
        // Most urgent first, as My Issues orders.
        #expect(lane.columns[2].items.compactMap(\.number) == [4, 3])
        #expect(lane.columns[0].optionId == "S-progress")
        #expect(lane.started.compactMap(\.number) == [1, 2])
        #expect(lane.next.compactMap(\.number) == [4, 3])
        // Done long ago and canceled are left out.
        #expect(lane.done.compactMap(\.number) == [7])
        #expect(lane.open.count == 6)
    }

    @Test("Projects come in the order given, those without your issues left out, the issues on no board last")
    func order() throws {
        let items = [
            MyIssuesTests.item(1, project: "P2"), MyIssuesTests.item(2, project: nil), MyIssuesTests.item(3, project: "P1"),
            MyIssuesTests.item(4, project: nil, closed: true),
        ]
        let rules = Self.rules(kinds: [1: .unstarted, 3: .started, 4: .completed], columns: [1: "todo", 3: "progress"])
        let result = lanes(items, rules)
        #expect(result.map(\.id) == ["project/P1", "project/P2", ListSection.noProjectId])
        let loose = try #require(result.last)
        #expect(loose.projectId == nil)
        #expect(loose.columns.map(\.key) == [MineColumn.noBoardKey, MineColumn.doneKey])
        #expect(loose.next.compactMap(\.number) == [2])
    }

    @Test("A column's name holds across projects: one choice in Display for every board with an In Progress")
    func columnKeys() {
        #expect(MineColumn.key(forColumn: " In Progress") == MineColumn.key(forColumn: "in progress"))
    }

    @Test("Cards show what is started and what is to do until you choose; the backlog, no status and done wait")
    func shownPages() throws {
        let display = MineDisplay()
        #expect(display.showsPage(key: "in progress", kind: .started))
        #expect(display.showsPage(key: "todo", kind: .unstarted))
        #expect(display.showsPage(key: MineColumn.noBoardKey, kind: nil))
        #expect(!display.showsPage(key: "backlog", kind: .backlog))
        #expect(!display.showsPage(key: MineColumn.noStatusKey, kind: nil))
        #expect(!display.showsPage(key: MineColumn.doneKey, kind: .completed))
        // Your choice holds whatever the column means, and is kept with the rest of the display.
        let chosen = MineDisplay(pages: ["backlog": true, "in review": false])
        #expect(chosen.showsPage(key: "backlog", kind: .backlog))
        #expect(!chosen.showsPage(key: "in review", kind: .started))
        #expect(MineDisplay(stored: chosen.stored) == chosen)
        #expect(!chosen.optionsAreDefault)
    }

    @Test("A started issue nobody touched for a week or more is idle")
    func idle() {
        let rules = MyIssuesTests.rules(kinds: [1: .started, 2: .started, 3: .unstarted])
        #expect(rules.idleDays(of: MyIssuesTests.item(1, updatedHoursAgo: 24 * 8), now: Self.now) == 8)
        #expect(rules.idleDays(of: MyIssuesTests.item(2, updatedHoursAgo: 24 * 2), now: Self.now) == nil)
        // Only work that has started can stop.
        #expect(rules.idleDays(of: MyIssuesTests.item(3, updatedHoursAgo: 24 * 30), now: Self.now) == nil)
    }

    @Test("What older versions kept starts with the overview and its first pages; the layout is kept from then on")
    func storedDisplay() throws {
        let old = try #require(MineDisplay(stored: #"{"grouping":"project","order":"dueDate","descending":false}"#))
        #expect(old.layout == .overview)
        #expect(old.grouping == .project)
        #expect(old.order == .dueDate)
        #expect(old.pages.isEmpty)
        let list = MineDisplay(layout: .list, grouping: .priority)
        #expect(MineDisplay(stored: list.stored) == list)
        // The list on its own isn't a change to the groups or the order.
        #expect(MineDisplay(layout: .list).optionsAreDefault)
        #expect(!MineDisplay(layout: .list).isDefault)
        #expect(!list.optionsAreDefault)
    }

    @Test("In a project where nobody else has open issues, those assigned to nobody are yours")
    func soloProjects() {
        func item(_ number: Int, _ project: String?, _ assignees: [String], closed: Bool = false) -> Item {
            var item = MyIssuesTests.item(number, project: project, closed: closed)
            item.assignees = assignees.map { Person(id: "U-\($0)", login: $0) }
            return item
        }
        let items = [
            // Yours alone: one of yours, one of nobody's.
            item(1, "P1", ["me"]), item(2, "P1", []),
            // Shared: someone else has an open issue.
            item(3, "P2", []), item(4, "P2", ["other"]),
            // Nobody assigns: someone else had one, but it is closed.
            item(5, "P3", []), item(6, "P3", ["other"], closed: true),
            // Issues on no board belong to no project.
            item(7, nil, ["other"]),
        ]
        #expect(AppModel.soloProjectIds(items, login: "me") == ["P1", "P3"])
    }
}
