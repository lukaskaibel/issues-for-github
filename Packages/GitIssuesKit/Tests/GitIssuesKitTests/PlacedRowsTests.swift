#if os(macOS)
import Testing
@testable import GitIssuesKit

/// A board column on the Mac places its rows from heights known in advance (`RowPlan`) and gives a view only to the
/// rows on screen and near it (`RowWindow`): a row that scrolls in takes over the view of one of its kind that
/// scrolled out, and a row that comes in any other way gets a view of its own.
@MainActor
@Suite("Board columns placing their rows from known heights")
struct PlacedRowsTests {
    /// Ten rows 100 points tall, 8 apart: row n from 108n to 108n + 100.
    private static let plan = RowPlan(heights: Array(repeating: 100, count: 10), gap: 8, bottom: 40)
    private static let ids = (0..<10).map { "row-\($0)" }

    @Test("Rows are placed one under another with the gap between them and room under the last")
    func placing() {
        let plan = RowPlan(heights: [100, 30, 50], gap: 8, bottom: 40)
        #expect(plan.tops == [0, 108, 146])
        #expect(plan.height == 236)
        #expect(RowPlan(heights: [], gap: 8, bottom: 40).height == 40)
    }

    @Test("The rows in a stretch are those reaching into it, not those that only touch its edges")
    func rowsInAStretch() {
        let plan = Self.plan
        #expect(plan.rows(in: 0...100) == 0..<1)
        #expect(plan.rows(in: 0...108) == 0..<1)
        #expect(plan.rows(in: 0...109) == 0..<2)
        #expect(plan.rows(in: 100...108) == 1..<1)
        #expect(plan.rows(in: 99...300) == 0..<3)
        #expect(plan.rows(in: 2000...3000).isEmpty)
        #expect(plan.rows(in: -500 ... -10).isEmpty)
    }

    @Test("The rows starting in a stretch are those whose top is in it")
    func rowsStartingInAStretch() {
        let plan = Self.plan
        #expect(plan.rows(startingIn: 0..<600) == 0..<6)
        #expect(plan.rows(startingIn: 600..<1200) == 6..<10)
        #expect(plan.rows(startingIn: 1..<108) == 1..<1)
        #expect(plan.rows(startingIn: 108..<109) == 1..<2)
        #expect(plan.rows(startingIn: 1200..<1800).isEmpty)
    }

    /// The row each view shows.
    private func shown(_ window: RowWindow) -> [String?] {
        (0..<window.slotCount).map { window[slot: $0] }
    }

    @Test("Only the rows on screen and near it have a view")
    func onlyRowsNearTheScreen() {
        let window = RowWindow()
        window.scrolled(to: 0...300)
        window.update(ids: Self.ids, kinds: Array(repeating: 0, count: 10), plan: Self.plan)
        // On screen down to 300, and rows reaching into the 200 points under it.
        #expect(Set(shown(window).compactMap { $0 }) == Set(Self.ids[0..<5]))
    }

    @Test("A row that scrolls in takes over the view of one of its kind that scrolled out")
    func scrollingReusesViews() {
        let window = RowWindow()
        let kinds = [0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
        window.scrolled(to: 0...300)
        window.update(ids: Self.ids, kinds: kinds, plan: Self.plan)
        let before = shown(window)
        let slotOfRow1 = before.firstIndex(of: "row-1")
        // Rows 0 to 2, cards, go out of reach at the top; cards 5 to 8 and header 9 come in at the bottom. Three
        // cards take over the views of the cards that went out; the fourth card and the header get new ones.
        window.scrolled(to: 540...840)
        let after = shown(window)
        #expect(after.count == before.count + 2)
        #expect(Set(after.compactMap { $0 }) == Set(Self.ids[3..<10]))
        #expect(slotOfRow1.map { after[$0] }.flatMap { $0 }.map { kinds[Self.ids.firstIndex(of: $0)!] } == 0)
        // Row 4, a header, keeps its view; no card took a header's view or the other way round.
        #expect(after.firstIndex(of: "row-4") == before.firstIndex(of: "row-4"))
        for (slot, id) in after.enumerated() where slot < before.count {
            guard let id, let old = before[slot] else { continue }
            #expect(kinds[Self.ids.firstIndex(of: id)!] == kinds[Self.ids.firstIndex(of: old)!])
        }
    }

    @Test("A row that comes in when the rows change gets a view of its own")
    func changesGiveNewViews() {
        let window = RowWindow()
        let kinds = Array(repeating: 0, count: 11)
        window.scrolled(to: 0...300)
        window.update(ids: Self.ids, kinds: Array(kinds.prefix(10)), plan: Self.plan)
        let before = shown(window)
        // A slot row goes in at the top: every row moves down one place and row 4 goes out of reach.
        let ids = ["slot"] + Self.ids
        window.update(ids: ids, kinds: kinds, plan: RowPlan(heights: Array(repeating: 100, count: 11), gap: 8, bottom: 40))
        let after = shown(window)
        let slot = after.firstIndex(of: "slot")
        #expect(slot != nil)
        #expect(slot.map { $0 >= before.count || before[$0] == nil } == true)
        // The rows that stay keep their views.
        for id in Self.ids[0..<4] { #expect(after.firstIndex(of: id) == before.firstIndex(of: id)) }
        #expect(!after.contains("row-4"))
    }
}
#endif
