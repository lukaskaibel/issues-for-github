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

    /// The group of epic `number`'s issues, as dragging its header moves it.
    static func epicGroup(_ number: Int) -> Nesting.Group {
        Nesting.Group(kind: .epic, head: epics.first { $0.number == number }!, count: 2, folded: false)
    }

    private func rows(_ nesting: Nesting) -> [String] {
        nesting.rows.map { row in
            switch row {
            case .item(let item): "\(item.number ?? 0)"
            case .group(let group): "\(group.kind == .epic ? "E" : "P")\(group.head.number ?? 0)×\(group.count)"
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
    // MARK: Moving an epic's issues together

    /// The ids of the issues numbered so.
    private func ids(_ numbers: Int...) -> Set<String> {
        Set(numbers.map { "item-\($0)" })
    }

    @Test("An epic's issues moved within their column go together, in front of or after what stands alone")
    func movesAGroupInItsColumn() {
        let (shown, nesting) = column
        let moving = ids(2, 4)
        let others = shown.filter { !moving.contains($0.id) }
        #expect(nesting.rows(without: moving).map(\.id) == ["item-1", "item-3"])

        let top = nesting.landing(ofGroup: Self.epicGroup(40), moving: moving, at: 0, shown: others)
        #expect(top.epic == nil)
        #expect(numbers(top.peers) == [1, 3])
        #expect(top.rank == 0)
        #expect(top.depth == 0)
        #expect(top.row == 0)

        let end = nesting.landing(ofGroup: Self.epicGroup(40), moving: moving, at: 2, shown: others)
        #expect(end.rank == 2)
        #expect(end.slot == 2)
        #expect(end.row == 2)
    }

    @Test("An epic's issues dropped in the middle of another epic's group go past the whole group")
    func passesAnotherGroup() {
        let (shown, nesting) = Self.arrange([Self.item(5, parent: 41), Self.item(6, parent: 41), Self.item(7)])
        #expect(rows(nesting) == ["E41×2", "5", "6", "7"])
        let landing = nesting.landing(ofGroup: Self.epicGroup(40), moving: ids(2, 4), at: 1, shown: shown)
        #expect(landing.epic == nil)
        // Its peers: the group of #41, by #5, and #7.
        #expect(numbers(landing.peers) == [5, 7])
        #expect(landing.rank == 1)
        #expect(landing.depth == 0)
        // Rows: header, 5, 6, [here], 7.
        #expect(landing.row == 3)
    }

    @Test("An epic's issues dropped where the epic has an issue already join it")
    func joinsTheEpicsIssue() {
        let (shown, nesting) = Self.arrange([Self.item(8), Self.item(9, parent: 40), Self.item(10)])
        let landing = nesting.landing(ofGroup: Self.epicGroup(40), moving: ids(2, 4), at: 3, shown: shown)
        #expect(landing.epic == "issue-40")
        #expect(numbers(landing.peers) == [9])
        #expect(landing.rank == 1)
        // Right after #9, before #10.
        #expect(landing.slot == 2)
        #expect(landing.row == 2)
    }

    @Test("An epic's issues dropped on the epic's group in another column join it, one level in")
    func joinsTheEpicsGroup() {
        let (shown, nesting) = Self.arrange([Self.item(10), Self.item(11, parent: 40), Self.item(12, parent: 40)])
        #expect(rows(nesting) == ["10", "E40×2", "11", "12"])
        let landing = nesting.landing(ofGroup: Self.epicGroup(40), moving: ids(2, 4), at: 0, shown: shown)
        #expect(landing.epic == "issue-40")
        #expect(numbers(landing.peers) == [11, 12])
        #expect(landing.rank == 0)
        #expect(landing.depth == 1)
        // Under the header, in front of #11.
        #expect(landing.row == 2)
    }

    @Test("A folded group moves as a whole, header and all")
    func movesAFoldedGroup() {
        let (shown, nesting) = Self.arrange(
            [Self.item(1), Self.item(2, parent: 40), Self.item(3, parent: 40), Self.item(5)], foldedEpics: ["issue-40"]
        )
        let moving = ids(2, 3)
        #expect(nesting.rows(without: moving).map(\.id) == ["item-1", "item-5"])
        let landing = nesting.landing(ofGroup: Self.epicGroup(40), moving: moving, at: 2, shown: shown)
        #expect(landing.rank == 2)
        #expect(landing.row == 2)
    }

    @Test("Where a dragged issue takes the last of its epic's issues along, the epic's header goes too")
    func headerLeavesWithItsLastIssues() {
        let (shown, nesting) = Self.arrange([Self.item(1), Self.item(9, parent: 40), Self.item(13, parent: 9)])
        #expect(rows(nesting) == ["1", "E40×2", "9", "13"])
        // #9 brings #13 along: nothing of the epic stays.
        #expect(nesting.rows(without: ids(9, 13)).map(\.id) == ["item-1"])
        let others = shown.filter { !ids(9, 13).contains($0.id) }
        let landing = nesting.landing(of: Self.item(9, parent: 40), at: 0, shown: others)
        #expect(landing.row == 0)
    }

    // MARK: Moving picked issues together

    @Test("Picked issues of no one epic dropped in the middle of an epic's group go past the whole group")
    func pickedPassAGroup() {
        let (shown, nesting) = column
        let landing = nesting.landing(ofPicked: ids(7, 8), epic: nil, parents: ["issue-7", "issue-8"], at: 2, shown: shown)
        #expect(landing.epic == nil)
        // Their peers: #1, the group of #40 (by #2) and #3.
        #expect(numbers(landing.peers) == [1, 2, 3])
        #expect(landing.rank == 2)
        #expect(landing.depth == 0)
        // Rows: 1, header, 2, 4, [here], 3.
        #expect(landing.row == 4)
    }

    @Test("Picked issues of one epic dropped on the epic's group join it, one level in")
    func pickedJoinTheirEpic() {
        let (shown, nesting) = column
        let landing = nesting.landing(ofPicked: ids(7, 8), epic: "issue-40", parents: [], at: 2, shown: shown)
        #expect(landing.epic == "issue-40")
        #expect(numbers(landing.peers) == [2, 4])
        #expect(landing.rank == 1)
        #expect(landing.depth == 1)
    }

    @Test("Picked issues moved within their column leave their places, and what they bring along goes too")
    func pickedLeaveTheirPlaces() {
        // #1 with sub-issue #5, then #2 and #3; #1 and #3 are picked, and #5 comes along under #1.
        let (shown, nesting) = Self.arrange([Self.item(1), Self.item(2), Self.item(3), Self.item(5, parent: 1)])
        let moving = ids(1, 3, 5)
        let others = shown.filter { !moving.contains($0.id) }
        #expect(nesting.rows(without: moving).map(\.id) == ["item-2"])
        let landing = nesting.landing(ofPicked: moving, epic: nil, parents: ["issue-1", "issue-3"], at: 1, shown: others)
        #expect(numbers(landing.peers) == [2])
        #expect(landing.rank == 1)
        #expect(landing.row == 1)
    }

    @Test("An issue a picked one is the parent of isn't among their peers: it will hang under it")
    func pickedAdoptTheirSubIssues() {
        // #6 is a sub-issue of #9, which comes from another column with #8.
        let (shown, nesting) = Self.arrange([Self.item(1), Self.item(6, parent: 9), Self.item(2)])
        let landing = nesting.landing(ofPicked: ids(8, 9), epic: nil, parents: ["issue-8", "issue-9"], at: 3, shown: shown)
        #expect(numbers(landing.peers) == [1, 2])
        #expect(landing.rank == 2)
    }
}

@Suite("Sub-issues of a parent elsewhere standing together under a quiet header of the parent")
struct ParentGroupTests {
    static func item(_ number: Int, parent: Int? = nil) -> Item {
        NestingTests.item(number, parent: parent)
    }

    /// What the header names: the parent as the app has it, here made from what its sub-issue knows.
    static let grouping = Nesting.ParentGrouping(head: { item in
        item.parentNumber.map { Item(id: "item-\($0)", kind: .issue, position: 0, number: $0, title: "Issue \($0)", body: "", state: "OPEN") }
    })

    static func arrange(_ items: [Item], folded: Set<String> = [], parents: Bool = true) -> (items: [Item], nesting: Nesting) {
        var grouping = grouping
        grouping.folded = folded
        return Nesting.arrange(items, parents: parents ? grouping : nil)
    }

    private func numbers(_ items: [Item]) -> [Int] {
        items.compactMap(\.number)
    }

    private func rows(_ nesting: Nesting) -> [String] {
        nesting.rows.map { row in
            switch row {
            case .item(let item): "\(item.number ?? 0)"
            case .group(let group): "\(group.kind == .epic ? "E" : "P")\(group.head.number ?? 0)×\(group.count)"
            }
        }
    }

    private func ids(_ numbers: Int...) -> Set<String> {
        Set(numbers.map { "item-\($0)" })
    }

    private static func parentGroup(_ number: Int) -> Nesting.Group {
        let head = Item(id: "item-\(number)", kind: .issue, position: 0, contentId: "issue-\(number)", number: number, title: "", body: "", state: "OPEN")
        return Nesting.Group(kind: .parent, head: head, count: 2, folded: false)
    }

    @Test("Two sub-issues of a parent elsewhere stand together under its header, where the first of them stands")
    func groupsSiblings() {
        let (shown, nesting) = Self.arrange([Self.item(1), Self.item(13, parent: 9), Self.item(2), Self.item(28, parent: 9)])
        #expect(rows(nesting) == ["1", "P9×2", "13", "28", "2"])
        #expect(numbers(shown) == [1, 13, 28, 2])
        #expect(nesting.place(of: "item-13") == Nesting.Place(depth: 1, continues: [true]))
        #expect(nesting.place(of: "item-28") == Nesting.Place(depth: 1, continues: [false]))
        #expect(nesting.parentGroupOf["item-13"] == "issue-9")
        #expect(nesting.groups.first?.contentId == "issue-9")
        // Under the parent's header, an issue doesn't name the parent again.
        #expect(!nesting.namesParent(of: Self.item(13, parent: 9)))
        #expect(nesting.members(of: Self.parentGroup(9)).map(\.id) == ["item-13", "item-28"])
    }

    @Test("A single sub-issue of a parent elsewhere stands alone and names its parent")
    func leavesASingleSubIssueAlone() {
        let (_, nesting) = Self.arrange([Self.item(1), Self.item(13, parent: 9), Self.item(2)])
        #expect(rows(nesting) == ["1", "13", "2"])
        #expect(nesting.namesParent(of: Self.item(13, parent: 9)))
    }

    @Test("Switched off, sub-issues of a parent elsewhere stand where they are, each naming its parent")
    func staysApartWhenOff() {
        let (_, nesting) = Self.arrange([Self.item(1), Self.item(13, parent: 9), Self.item(2), Self.item(28, parent: 9)], parents: false)
        #expect(rows(nesting) == ["1", "13", "2", "28"])
        #expect(nesting.namesParent(of: Self.item(28, parent: 9)))
    }

    @Test("Sub-issues of a parent in the group hang under its card, not under a header")
    func hangsUnderAParentHere() {
        let (_, nesting) = Self.arrange([Self.item(9), Self.item(13, parent: 9), Self.item(28, parent: 9)])
        #expect(rows(nesting) == ["9", "13", "28"])
        #expect(nesting.groups.isEmpty)
    }

    @Test("A sub-issue's own sub-issues hang under it inside the group, and count for the header")
    func nestsInsideTheGroup() {
        let (_, nesting) = Self.arrange([Self.item(13, parent: 9), Self.item(40, parent: 13), Self.item(28, parent: 9)])
        #expect(rows(nesting) == ["P9×3", "13", "40", "28"])
        #expect(nesting.place(of: "item-40") == Nesting.Place(depth: 2, continues: [true, false]))
        #expect(nesting.parentGroupOf["item-40"] == "issue-9")
    }

    @Test("Folding a parent's group leaves its header, which still counts them")
    func foldsAGroup() {
        let (shown, nesting) = Self.arrange([Self.item(1), Self.item(13, parent: 9), Self.item(28, parent: 9), Self.item(2)], folded: ["issue-9"])
        #expect(rows(nesting) == ["1", "P9×2", "2"])
        #expect(numbers(shown) == [1, 2])
        #expect(nesting.members.count == 4)
        #expect(nesting.groups.first?.folded == true)
    }

    @Test("Inside an epic's group, a parent's header hangs one level in, with its sub-issues under it")
    func nestsInAnEpic() {
        let epic = EpicGroupTests.epics[0]
        let items = [Self.item(5, parent: 40), Self.item(13, parent: 9), Self.item(28, parent: 9), Self.item(7)]
        // #9 is an issue of epic #40 in another column.
        let (_, nesting) = Nesting.arrange(items, epic: { $0.number == 7 ? nil : epic }, parents: Self.grouping)
        #expect(rows(nesting) == ["E40×3", "5", "P9×2", "13", "28", "7"])
        #expect(nesting.place(of: "item-5") == Nesting.Place(depth: 1, continues: [true]))
        #expect(nesting.place(of: Nesting.Group.id(parent: "issue-9")) == Nesting.Place(depth: 1, continues: [false]))
        #expect(nesting.place(of: "item-13") == Nesting.Place(depth: 2, continues: [false, true]))
        #expect(nesting.place(of: "item-28") == Nesting.Place(depth: 2, continues: [false, false]))
        #expect(nesting.groupOf["item-13"] == "issue-40")
        #expect(nesting.parentGroupOf["item-13"] == "issue-9")
    }

    @Test("Sub-issues of an epic itself stand under the epic's header only")
    func leavesEpicsToTheirHeader() {
        let items = [Self.item(2, parent: 40), Self.item(4, parent: 40)]
        let (_, nesting) = Nesting.arrange(items, epic: { _ in EpicGroupTests.epics[0] }, parents: Self.grouping)
        #expect(rows(nesting) == ["E40×2", "2", "4"])
    }

    // MARK: Dropping

    /// #1, the header of #9 over #13 and #28, and #2.
    private var column: (items: [Item], nesting: Nesting) {
        Self.arrange([Self.item(1), Self.item(13, parent: 9), Self.item(28, parent: 9), Self.item(2)])
    }

    @Test("A sub-issue dropped anywhere in a column joins the other sub-issues of its parent there")
    func joinsItsSiblings() {
        let (shown, nesting) = column
        let top = nesting.landing(of: Self.item(30, parent: 9), at: 0, shown: shown)
        #expect(top.parentGroup == "issue-9")
        #expect(numbers(top.peers) == [13, 28])
        #expect(top.rank == 0)
        #expect(top.depth == 1)
        // Rows: 1, header, [here], 13, 28, 2.
        #expect(top.row == 2)

        let end = nesting.landing(of: Self.item(30, parent: 9), at: shown.count, shown: shown)
        #expect(end.rank == 2)
        #expect(end.slot == 3)
        // Rows: 1, header, 13, 28, [here], 2.
        #expect(end.row == 4)
    }

    @Test("Another issue dropped among the sub-issues under a parent's header goes past the whole group")
    func passesAGroup() {
        let (shown, nesting) = column
        let landing = nesting.landing(of: Self.item(7), at: 2, shown: shown)
        #expect(landing.parentGroup == nil)
        // Its peers: #1, the group (by #13) and #2.
        #expect(numbers(landing.peers) == [1, 13, 2])
        #expect(landing.rank == 2)
        #expect(landing.depth == 0)
        #expect(landing.row == 4)
    }

    @Test("A sub-issue moved within its group stays in it")
    func staysInItsGroup() {
        let (shown, nesting) = column
        let moving = Self.item(28, parent: 9)
        let others = shown.filter { $0.id != moving.id }
        let landing = nesting.landing(of: moving, at: 0, shown: others)
        #expect(landing.parentGroup == "issue-9")
        #expect(numbers(landing.peers) == [13])
        #expect(landing.rank == 0)
    }

    @Test("A parent's sub-issues lifted by their header hang under the parent where it stands")
    func groupJoinsItsParent() {
        let (shown, nesting) = Self.arrange([Self.item(9), Self.item(5)])
        let landing = nesting.landing(ofGroup: Self.parentGroup(9), moving: ids(13, 28), at: 2, shown: shown)
        #expect(landing.parentId == "item-9")
        #expect(landing.depth == 1)
        #expect(landing.slot == 1)
        #expect(landing.row == 1)
    }

    @Test("A parent's sub-issues lifted by their header join its other sub-issues in another column")
    func groupJoinsItsSiblings() {
        let (shown, nesting) = Self.arrange([Self.item(1), Self.item(30, parent: 9), Self.item(31, parent: 9), Self.item(2)])
        let landing = nesting.landing(ofGroup: Self.parentGroup(9), moving: ids(13, 28), at: 0, shown: shown)
        #expect(landing.parentGroup == "issue-9")
        #expect(numbers(landing.peers) == [30, 31])
        #expect(landing.depth == 1)
    }

    @Test("Where the last of a parent's sub-issues leave, its header goes too")
    func headerLeavesWithItsIssues() {
        let (_, nesting) = column
        #expect(nesting.rows(without: ids(13, 28)).map(\.id) == ["item-1", "item-2"])
        #expect(nesting.rows(without: ids(13)).map(\.id) == ["item-1", Nesting.Group.id(parent: "issue-9"), "item-28", "item-2"])
    }
}

extension ParentGroupTests {
    @Test("Picked sub-issues of one parent elsewhere join its other sub-issues where those stand together")
    func pickedJoinTheirSiblings() {
        let (shown, nesting) = Self.arrange([Self.item(1), Self.item(13, parent: 9), Self.item(28, parent: 9), Self.item(2)])
        let moving: Set<String> = ["item-30", "item-31"]
        let landing = nesting.landing(ofPicked: moving, epic: nil, parent: "issue-9", parents: ["issue-30", "issue-31"], at: 0, shown: shown)
        #expect(landing.parentGroup == "issue-9")
        #expect(landing.peers.compactMap(\.number) == [13, 28])
        #expect(landing.depth == 1)
        // Picked issues of different parents go past the group as before.
        let mixed = nesting.landing(ofPicked: moving, epic: nil, parents: ["issue-30", "issue-31"], at: 2, shown: shown)
        #expect(mixed.parentGroup == nil)
        #expect(mixed.depth == 0)
    }
}
