import Foundation
import Testing
@testable import GitIssuesKit

/// Dropping issues onto another issue to make them its sub-issues: what may go under what, as GitHub takes it.
@Suite("Dropping an issue onto another one")
struct DropNestingTests {
    /// An issue numbered `number`, a sub-issue of `parent` when given.
    static func item(_ number: Int, parent: Int? = nil, kind: ItemKind = .issue, project: String? = "P1", subTotal: Int = 0) -> Item {
        var item = NestingTests.item(number, parent: parent)
        item.kind = kind
        item.projectId = project
        item.subTotal = subTotal
        if kind == .draft { item.contentId = nil }
        return item
    }

    private func nestable(_ dragged: [Item], under target: Item, among items: [Item], readOnly: Set<String> = []) -> [Int] {
        AppModel.nestable(dragged, under: target, among: items) { item in
            item.kind == .issue && item.contentId != nil && !readOnly.contains(item.projectId ?? "")
        }.compactMap(\.number)
    }

    @Test("An issue goes under another one, also one on no board")
    func plainIssue() {
        let one = Self.item(1), two = Self.item(2), loose = Self.item(3, project: nil)
        let all = [one, two, loose]
        #expect(nestable([two], under: one, among: all) == [2])
        #expect(nestable([loose], under: one, among: all) == [3])
        #expect(nestable([one], under: loose, among: all) == [1])
    }

    @Test("Not under itself, nor under one of its own sub-issues at any level, nor where it is already")
    func noLoops() {
        let one = Self.item(1), two = Self.item(2, parent: 1), three = Self.item(3, parent: 2)
        let all = [one, two, three]
        #expect(nestable([one], under: one, among: all).isEmpty)
        #expect(nestable([one], under: two, among: all).isEmpty)
        #expect(nestable([one], under: three, among: all).isEmpty)
        #expect(nestable([two], under: one, among: all).isEmpty)
        // One level up is a move to another parent, which GitHub takes.
        #expect(nestable([three], under: one, among: all) == [3])
    }

    @Test("The same issue on two boards counts once, and as itself")
    func sameIssueTwice() {
        let one = Self.item(1)
        var copy = Self.item(1)
        copy.id = "item-1-on-P2"
        copy.projectId = "P2"
        let two = Self.item(2)
        #expect(nestable([copy], under: one, among: [one, copy, two]).isEmpty)
        #expect(nestable([two, two], under: one, among: [one, copy, two]) == [2])
    }

    @Test("Pull requests and drafts don't go under issues, and issues don't go under them")
    func onlyIssues() {
        let one = Self.item(1), pull = Self.item(2, kind: .pullRequest), draft = Self.item(3, kind: .draft)
        let all = [one, pull, draft]
        #expect(nestable([pull, draft], under: one, among: all).isEmpty)
        #expect(nestable([one], under: pull, among: all).isEmpty)
        #expect(nestable([one], under: draft, among: all).isEmpty)
    }

    @Test("Of several picked issues, those that can go under it do")
    func severalPicked() {
        let one = Self.item(1), two = Self.item(2, parent: 1), three = Self.item(3), pull = Self.item(4, kind: .pullRequest)
        let all = [one, two, three, pull]
        #expect(nestable([one, two, three, pull], under: two, among: all) == [3])
        #expect(nestable([two, three], under: one, among: all) == [3])
    }

    @Test("Nothing changes on a board you can only read")
    func readOnly() {
        let one = Self.item(1), two = Self.item(2), other = Self.item(3, project: "P2")
        let all = [one, two, other]
        #expect(nestable([two], under: one, among: all, readOnly: ["P1"]).isEmpty)
        #expect(nestable([other], under: one, among: all, readOnly: ["P1"]).isEmpty)
        #expect(nestable([two], under: other, among: all, readOnly: ["P1"]).isEmpty)
        #expect(nestable([two], under: other, among: all, readOnly: ["P3"]) == [2])
    }

    @Test("GitHub keeps at most 100 sub-issues under one issue")
    func hundredSubIssues() {
        let full = Self.item(1, subTotal: 100), almost = Self.item(2, subTotal: 99)
        let three = Self.item(3), four = Self.item(4)
        let all = [full, almost, three, four]
        #expect(nestable([three], under: full, among: all).isEmpty)
        #expect(nestable([three], under: almost, among: all) == [3])
        #expect(nestable([three, four], under: almost, among: all).isEmpty)
    }

    @Test("GitHub nests sub-issues at most eight levels deep, counting what the dropped issue brings along")
    func eightLevels() {
        // #1 at the top, #2 under it and so on down to #7 on the seventh level.
        let chain = (1...7).map { Self.item($0, parent: $0 > 1 ? $0 - 1 : nil) }
        let loose = Self.item(20)
        // #21 with #22 under it: two levels.
        let pair = [Self.item(21), Self.item(22, parent: 21)]
        let all = chain + [loose] + pair
        #expect(nestable([loose], under: chain[6], among: all) == [20])
        #expect(nestable([pair[0]], under: chain[6], among: all).isEmpty)
        #expect(nestable([pair[0]], under: chain[5], among: all) == [21])
    }
}
