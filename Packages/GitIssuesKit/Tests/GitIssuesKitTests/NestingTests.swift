import Foundation
import Testing
@testable import GitIssuesKit

@Suite("Sub-issues hanging under their parent in a column or group")
struct NestingTests {
    /// An issue numbered `number`, a sub-issue of `parent` when given, in board order by its number.
    static func item(_ number: Int, parent: Int? = nil, position: Double? = nil) -> Item {
        Item(
            id: "item-\(number)", projectId: "P1", kind: .issue, position: position ?? Double(number) * 1024,
            statusId: "doing", contentId: "issue-\(number)", number: number, title: "Issue \(number)", body: "",
            state: "OPEN", parentId: parent.map { "issue-\($0)" }, parentNumber: parent
        )
    }

    private func numbers(_ items: [Item]) -> [Int] {
        items.compactMap(\.number)
    }

    @Test("A sub-issue hangs right under its parent when both are in the group")
    func nestsUnderParent() {
        let (items, nesting) = Nesting.arrange([Self.item(1), Self.item(2), Self.item(3, parent: 1)])
        #expect(numbers(items) == [1, 3, 2])
        #expect(nesting.depth(of: "item-3") == 1)
        #expect(nesting.depth(of: "item-1") == 0)
        #expect(nesting.nestedCounts == ["item-1": 1])
    }

    @Test("A sub-issue whose parent is elsewhere stands on its own")
    func standsAloneWithoutParent() {
        let (items, nesting) = Nesting.arrange([Self.item(2), Self.item(3, parent: 1)])
        #expect(numbers(items) == [2, 3])
        #expect(nesting.places.isEmpty)
        #expect(nesting.nestedCounts.isEmpty)
    }

    @Test("Sub-issues keep board order among themselves, and deeper ones hang deeper")
    func ordersSiblingsAndLevels() {
        let items = [
            Self.item(1), Self.item(5, parent: 1), Self.item(2), Self.item(4, parent: 1), Self.item(6, parent: 5),
        ]
        let (arranged, nesting) = Nesting.arrange(items)
        #expect(numbers(arranged) == [1, 5, 6, 4, 2])
        #expect(nesting.place(of: "item-5") == .init(depth: 1, continues: [true]))
        #expect(nesting.place(of: "item-6") == .init(depth: 2, continues: [true, false]))
        #expect(nesting.place(of: "item-4") == .init(depth: 1, continues: [false]))
        #expect(nesting.nestedCounts == ["item-1": 3, "item-5": 1])
        #expect(nesting.descendants(of: "item-1") == ["item-4", "item-5", "item-6"])
    }

    @Test("Folding a parent hides what hangs under it, at every level")
    func foldsAway() {
        let items = [Self.item(1), Self.item(5, parent: 1), Self.item(6, parent: 5), Self.item(2)]
        let (arranged, nesting) = Nesting.arrange(items, folded: ["issue-1"])
        #expect(numbers(arranged) == [1, 2])
        #expect(nesting.folded == ["item-1"])
        #expect(nesting.nestedCounts["item-1"] == 2)
        #expect(numbers(nesting.members) == [1, 5, 6, 2])
    }

    @Test("Folding an issue without sub-issues here changes nothing")
    func foldWithoutNested() {
        let (arranged, nesting) = Nesting.arrange([Self.item(1), Self.item(2)], folded: ["issue-1"])
        #expect(numbers(arranged) == [1, 2])
        #expect(nesting.folded.isEmpty)
    }

    @Test("Issues that name each other as parent still show, once each")
    func survivesLoops() {
        let (arranged, _) = Nesting.arrange([Self.item(1, parent: 2), Self.item(2, parent: 1), Self.item(3)])
        #expect(Set(numbers(arranged)) == [1, 2, 3])
        #expect(arranged.count == 3)
    }

    // MARK: Landing

    /// 1 with sub-issues 3 and 4, then 2.
    private var group: (items: [Item], nesting: Nesting) {
        Nesting.arrange([Self.item(1), Self.item(2), Self.item(3, parent: 1), Self.item(4, parent: 1)])
    }

    @Test("An issue dropped between a parent and its sub-issues lands after them")
    func snapsPastGroup() {
        let (shown, nesting) = group
        let landing = nesting.landing(of: Self.item(9), at: 1, shown: shown)
        #expect(numbers(landing.peers) == [1, 2])
        #expect(landing.rank == 1)
        #expect(landing.slot == 3)
        #expect(landing.depth == 0)
    }

    @Test("A sub-issue dropped anywhere joins its parent's sub-issues")
    func joinsParent() {
        let (shown, nesting) = group
        let atEnd = nesting.landing(of: Self.item(9, parent: 1), at: shown.count, shown: shown)
        #expect(atEnd.parentId == "item-1")
        #expect(numbers(atEnd.peers) == [3, 4])
        #expect(atEnd.rank == 2)
        #expect(atEnd.slot == 3)
        #expect(atEnd.depth == 1)

        let between = nesting.landing(of: Self.item(9, parent: 1), at: 2, shown: shown)
        #expect(between.rank == 1)
        #expect(between.slot == 2)
    }

    @Test("Moving a sub-issue among its siblings")
    func reordersSiblings() {
        let (shown, nesting) = group
        let others = shown.filter { $0.id != "item-4" }
        let landing = nesting.landing(of: Self.item(4, parent: 1), at: 1, shown: others)
        #expect(numbers(landing.peers) == [3])
        #expect(landing.rank == 0)
        #expect(landing.slot == 1)
    }

    @Test("A parent moved in its group brings its sub-issues along")
    func parentBringsSubIssues() {
        let (shown, nesting) = group
        let others = shown.filter { !["item-1", "item-3", "item-4"].contains($0.id) }
        let landing = nesting.landing(of: Self.item(1), at: 1, shown: others)
        #expect(numbers(landing.peers) == [2])
        #expect(landing.rank == 1)
    }

    @Test("A parent dropped where its sub-issue stands alone takes it under itself")
    func adoptsSubIssue() {
        let (shown, nesting) = Nesting.arrange([Self.item(3, parent: 1), Self.item(2)])
        let landing = nesting.landing(of: Self.item(1), at: 2, shown: shown)
        #expect(numbers(landing.peers) == [2])
        #expect(landing.rank == 1)
    }

    @Test("A sub-issue dropped onto a folded parent counts its hidden siblings")
    func intoFoldedParent() {
        let (shown, nesting) = Nesting.arrange([Self.item(1), Self.item(3, parent: 1), Self.item(2)], folded: ["issue-1"])
        let landing = nesting.landing(of: Self.item(9, parent: 1), at: 2, shown: shown)
        #expect(numbers(landing.peers) == [3])
        #expect(landing.rank == 1)
        #expect(landing.slot == 1)
    }
}

@Suite("The issues of an epic standing together under its header in a column or group")
struct EpicGroupTests {
    /// Epics #40 and #41, which aren't on the board themselves.
    static let epics = [40, 41].map { (number: Int) in
        Item(
            id: "item-\(number)", projectId: "P1", kind: .issue, position: 0, contentId: "issue-\(number)", number: number,
            title: "Epic \(number)", body: "", state: "OPEN"
        )
    }

    static func item(_ number: Int, parent: Int? = nil) -> Item {
        NestingTests.item(number, parent: parent)
    }

    /// The epic over an issue: the first epic among its parents, as the app finds it.
    static func epic(of item: Item, among items: [Item]) -> Item? {
        var parent = item.parentId
        var seen = Set<String>()
        while let id = parent, seen.insert(id).inserted {
            if let epic = epics.first(where: { $0.contentId == id }) { return epic }
            parent = items.first { $0.contentId == id }?.parentId
        }
        return nil
    }

    static func arrange(_ items: [Item], folded: Set<String> = [], foldedEpics: Set<String> = []) -> (items: [Item], nesting: Nesting) {
        Nesting.arrange(items, folded: folded, epic: { epic(of: $0, among: items) }, foldedEpics: foldedEpics)
    }

    private func numbers(_ items: [Item]) -> [Int] {
        items.compactMap(\.number)
    }

    private func rows(_ nesting: Nesting) -> [String] {
        nesting.rows.map { row in
            switch row {
            case .item(let item): "\(item.number ?? 0)"
            case .epic(let group): "E\(group.epic.number ?? 0)×\(group.count)"
            }
        }
    }

    @Test("Two issues of an epic stand together under its header, where the first of them stands")
    func groupsAnEpicsIssues() {
        let (shown, nesting) = Self.arrange([Self.item(1), Self.item(2, parent: 40), Self.item(3), Self.item(4, parent: 40)])
        #expect(rows(nesting) == ["1", "E40×2", "2", "4", "3"])
        #expect(numbers(shown) == [1, 2, 4, 3])
        #expect(nesting.place(of: "item-2") == Nesting.Place(depth: 1, continues: [true]))
        #expect(nesting.place(of: "item-4") == Nesting.Place(depth: 1, continues: [false]))
        #expect(nesting.depth(of: "item-3") == 0)
        #expect(nesting.groupOf["item-2"] == "issue-40")
        // Under the epic's header, an issue doesn't name the epic again.
        #expect(!nesting.namesParent(of: Self.item(2, parent: 40)))
    }

    @Test("A single issue of an epic stands alone and names the epic")
    func leavesASingleIssueAlone() {
        let (_, nesting) = Self.arrange([Self.item(1, parent: 40), Self.item(2), Self.item(3, parent: 41), Self.item(4, parent: 41)])
        #expect(rows(nesting) == ["1", "2", "E41×2", "3", "4"])
        #expect(nesting.groupOf["item-1"] == nil)
        #expect(nesting.epicOf["item-1"] == "issue-40")
        #expect(nesting.namesParent(of: Self.item(1, parent: 40)))
    }

    @Test("Sub-issues in an epic's group hang one level further in, and count for the epic")
    func nestsSubIssuesInAGroup() {
        let (_, nesting) = Self.arrange([Self.item(9, parent: 40), Self.item(13, parent: 9), Self.item(7), Self.item(28, parent: 9)])
        #expect(rows(nesting) == ["E40×3", "9", "13", "28", "7"])
        #expect(nesting.place(of: "item-9") == Nesting.Place(depth: 1, continues: [false]))
        #expect(nesting.place(of: "item-13") == Nesting.Place(depth: 2, continues: [false, true]))
        #expect(nesting.place(of: "item-28") == Nesting.Place(depth: 2, continues: [false, false]))
        #expect(nesting.nestedCounts["item-9"] == 2)
    }

    @Test("A sub-issue whose parent stands elsewhere names its parent, also in the epic's group")
    func namesAParentElsewhere() {
        // #9 is an issue of #40 in another column: #13 is in the epic too, and stands with #5.
        let items = [Self.item(5, parent: 40), Self.item(13, parent: 9)]
        let grouped = Nesting.arrange(items, epic: { item in
            item.number == 13 || item.number == 5 ? Self.epics[0] : nil
        })
        #expect(rows(grouped.nesting) == ["E40×2", "5", "13"])
        #expect(grouped.nesting.namesParent(of: Self.item(13, parent: 9)))
    }

    @Test("Folding an epic's group leaves its header, which still counts them")
    func foldsAGroup() {
        let (shown, nesting) = Self.arrange(
            [Self.item(1), Self.item(2, parent: 40), Self.item(3, parent: 40)], foldedEpics: ["issue-40"]
        )
        #expect(rows(nesting) == ["1", "E40×2"])
        #expect(numbers(shown) == [1])
        #expect(nesting.members.count == 3)
        #expect(nesting.groups.first?.folded == true)
    }

    // MARK: Dropping

    /// #1 on its own, the group of #40 with #2 and #4, and #3 on its own.
    private var column: (items: [Item], nesting: Nesting) {
        Self.arrange([Self.item(1), Self.item(2, parent: 40), Self.item(3), Self.item(4, parent: 40)])
    }

    @Test("Dropped between two issues of an epic's group, an issue joins the epic")
    func joinsAGroup() {
        let (shown, nesting) = column
        let landing = nesting.landing(of: Self.item(9), at: 2, shown: shown)
        #expect(landing.epic == "issue-40")
        #expect(numbers(landing.peers) == [2, 4])
        #expect(landing.rank == 1)
        #expect(landing.depth == 1)
        #expect(landing.slot == 2)
        // Rows: 1, header, 2, [here], 4, 3.
        #expect(landing.row == 3)
    }

    @Test("Dropped just above or below a group, an issue of no epic stays outside it")
    func staysOutsideAGroup() {
        let (shown, nesting) = column
        let above = nesting.landing(of: Self.item(9), at: 1, shown: shown)
        #expect(above.epic == nil)
        #expect(above.depth == 0)
        // Its peers: #1, the group (by #2, its first issue on the board) and #3.
        #expect(numbers(above.peers) == [1, 2, 3])
        #expect(above.rank == 1)
        #expect(above.row == 1)

        let below = nesting.landing(of: Self.item(9), at: 3, shown: shown)
        #expect(below.epic == nil)
        #expect(below.rank == 2)
        #expect(below.slot == 3)
        // Rows: 1, header, 2, 4, [here], 3.
        #expect(below.row == 4)
    }

    @Test("An issue of an epic moved anywhere stays with the epic's other issues")
    func staysInItsGroup() {
        let (shown, nesting) = column
        let moving = Self.item(4, parent: 40)
        let others = shown.filter { $0.id != moving.id }
        let landing = nesting.landing(of: moving, at: others.count, shown: others)
        #expect(landing.epic == "issue-40")
        #expect(numbers(landing.peers) == [2])
        #expect(landing.rank == 1)
        #expect(landing.depth == 1)

        let toTop = nesting.landing(of: moving, at: 0, shown: others)
        #expect(toTop.epic == "issue-40")
        #expect(toTop.rank == 0)
    }

    @Test("An issue under another issue can't join an epic by a drop")
    func keepsAnotherParent() {
        let (shown, nesting) = column
        let landing = nesting.landing(of: Self.item(9, parent: 8), at: 2, shown: shown)
        #expect(landing.epic == nil)
        #expect(landing.depth == 0)
        // It goes past the whole group instead.
        #expect(landing.rank == 2)
    }

    @Test("An issue of an epic dropped next to the epic's only issue in a column joins it there")
    func formsAGroup() {
        let (shown, nesting) = Self.arrange([Self.item(1), Self.item(2, parent: 41), Self.item(3)])
        let landing = nesting.landing(of: Self.item(9, parent: 41), at: 0, shown: shown, epic: "issue-41")
        #expect(landing.epic == "issue-41")
        #expect(numbers(landing.peers) == [2])
        #expect(landing.rank == 0)
    }

    @Test("Dropped below a folded group, an issue lands after it")
    func passesAFoldedGroup() {
        let (shown, nesting) = Self.arrange(
            [Self.item(1), Self.item(2, parent: 40), Self.item(3, parent: 40), Self.item(5)], foldedEpics: ["issue-40"]
        )
        #expect(numbers(shown) == [1, 5])
        let landing = nesting.landing(of: Self.item(9), at: 1, shown: shown)
        #expect(landing.epic == nil)
        #expect(landing.rank == 2)
        #expect(landing.row == 2)
    }
}
