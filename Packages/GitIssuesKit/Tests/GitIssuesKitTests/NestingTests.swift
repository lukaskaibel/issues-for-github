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
