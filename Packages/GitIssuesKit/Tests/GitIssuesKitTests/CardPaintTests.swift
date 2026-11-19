#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import GitIssuesKit

/// Board cards keep their texts and colours from one paint to the next (`CardPaintCache`). Whatever changes how a card
/// looks has to be part of what they are kept by, or a card would show another card's text or the other appearance's
/// colours.
@MainActor
@Suite("Board cards painted with texts and colours kept from earlier paints", .serialized)
struct CardPaintTests {
    /// A card with something in every place: a fold arrow, the parent, assignees, priority, a blocker, more labels
    /// than fit, sub-issues, a due date, a milestone and a field.
    private static let card: CardModel = {
        let item = Item(
            id: "item-13", projectId: "P1", kind: .issue, position: 1024, statusId: "doing", contentId: "issue-13", number: 13,
            title: "Cancel a drag with Escape, and the card goes back where it was", body: "", state: "OPEN", repo: "acme/issues",
            parentId: "issue-9", parentNumber: 9, parentTitle: "Drag cards between columns", subTotal: 6, subCompleted: 4,
            assignees: [Person(id: "u1", login: "mira"), Person(id: "u2", login: "theo")],
            labels: [LabelRef(id: "l1", name: "ui", color: "8F96F2"), LabelRef(id: "l2", name: "bug", color: "D73A4A"),
                     LabelRef(id: "l3", name: "sync", color: "4CB782")],
            blockedByCount: 2, milestoneTitle: "0.3", issueType: "Bug", issueTypeColor: "RED"
        )
        let blocker = LinkedIssue(id: "issue-5", issueId: "issue-13", relation: .blockedBy, number: 5, title: "Keyboard navigation",
                                  state: "OPEN", position: 0)
        return CardModel(
            item: item, priority: .high, showsPriority: true,
            due: DueBadge(day: CalendarDay(year: 2026, month: 10, day: 21), label: "Tomorrow", tone: .upcoming),
            blocker: BlockerMark(blockers: [blocker], count: 2), nested: 2, showsParent: true, milestone: "0.3",
            milestoneMark: .current, changesType: true, chips: [FieldChip(fieldId: "cycle", text: "Cycle 4", icon: .iteration)]
        )
    }()

    private static func card(folded: Bool, subIssues: Int? = nil) -> CardModel {
        var card = card
        card.folded = folded
        if let subIssues {
            // Sub-issues in other columns only, which it stands on a card for each of.
            card.item.subTotal = subIssues
            card.nested = nil
        }
        return card
    }

    /// The card in each look it can have, one under the other, as pixels.
    private func picture(dark: Bool) -> Data {
        struct Look: Hashable { var highlighted = false, selected = false, peeked = false, lifted = false, fold = false; var part: PickerKind? }
        let looks = [Look(), Look(highlighted: true), Look(selected: true), Look(peeked: true), Look(selected: true, peeked: true),
                     Look(lifted: true), Look(highlighted: true, fold: true)]
            + [PickerKind.priority, .issueType, .labels, .subIssues, .assignees, .dueDate, .milestone, .blockedBy, .parent].map { Look(highlighted: true, part: $0) }
        let renderer = ImageRenderer(content:
            VStack(spacing: 6) {
                ForEach(looks, id: \.self) { look in
                    CardView(card: Self.card, width: 300, highlighted: look.highlighted, selected: look.selected, peeked: look.peeked, lifted: look.lifted,
                             hoveredPart: look.part, hoveringFold: look.fold)
                }
            }
            .padding(10)
            .background(Theme.board)
            .environment(\.colorScheme, dark ? .dark : .light)
        )
        renderer.scale = 2
        guard let image = renderer.cgImage, let data = image.dataProvider?.data else { return Data() }
        return data as Data
    }

    /// The first pictures a process draws can come out a shade apart from the ones after them.
    private func warmUp() {
        for dark in [false, true, false, true] { _ = picture(dark: dark) }
    }

    /// The same picture, give or take the shade of anti-aliasing two paints of one text can differ by right after a
    /// build; another card's text or the other appearance's colours are far further apart.
    private func alike(_ a: Data, _ b: Data) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { abs(Int($0) - Int($1)) <= 2 }
    }

    @Test("A card's type stands first of its tags, and opens its own picker")
    func typeComesFirst() {
        let renderer = ImageRenderer(content: CardView(card: Self.card, width: 300).environment(\.colorScheme, .light))
        renderer.scale = 1
        #expect(renderer.cgImage != nil)
        let parts = CardRegionStore.shared.parts(Self.card.item.id)
        let type = parts.first { $0.kind == .issueType }?.rect
        let labels = parts.first { $0.kind == .labels }?.rect
        #expect(type != nil && labels != nil)
        if let type, let labels { #expect(type.maxX < labels.minX) }
    }

    @Test("A card painted with kept texts and colours looks as one painted from nothing")
    func keptLooksAsFresh() {
        warmUp()
        for dark in [false, true] {
            CardPaintCache.shared.removeAll()
            let fresh = picture(dark: dark)
            let kept = picture(dark: dark)
            #expect(!fresh.isEmpty)
            #expect(alike(kept, fresh))
        }
    }

    /// One card, as pixels.
    private func picture(of card: CardView, dark: Bool) -> Data {
        let renderer = ImageRenderer(content: card.padding(10).background(Theme.board).environment(\.colorScheme, dark ? .dark : .light))
        renderer.scale = 2
        guard let image = renderer.cgImage, let data = image.dataProvider?.data else { return Data() }
        return data as Data
    }

    @Test("The card in the peek stands out from a plain, a hovered and a picked one, and a lifted card leaves the mark behind")
    func peekedCard() {
        warmUp()
        for dark in [false, true] {
            let peeked = picture(of: CardView(card: Self.card, width: 300, peeked: true), dark: dark)
            #expect(!peeked.isEmpty)
            for other in [CardView(card: Self.card, width: 300), CardView(card: Self.card, width: 300, highlighted: true),
                          CardView(card: Self.card, width: 300, selected: true)] {
                #expect(!alike(peeked, picture(of: other, dark: dark)))
            }
            // Picked as well, it keeps the picked tint under the ring.
            #expect(!alike(picture(of: CardView(card: Self.card, width: 300, selected: true, peeked: true), dark: dark), peeked))
            #expect(alike(picture(of: CardView(card: Self.card, width: 300, peeked: true, lifted: true), dark: dark),
                          picture(of: CardView(card: Self.card, width: 300, lifted: true), dark: dark)))
        }
    }

    /// Board cells in every arrangement a column has: on their own, hanging under a parent at each level (the last of
    /// its parent's or not), deeper than the board indents, with sub-issues folded into them, and standing on one, two
    /// and three cards for sub-issues elsewhere; drawn by the card, and as the views the card's painting replaced drew
    /// them.
    private func cells(dark: Bool, painted: Bool) -> Data {
        struct Cell { var place = Nesting.Place(); var folded = false; var subIssues: Int? }
        let cells = [
            Cell(), Cell(folded: true), Cell(subIssues: 1), Cell(subIssues: 2), Cell(subIssues: 9),
            Cell(place: Nesting.Place(depth: 1, continues: [true])), Cell(place: Nesting.Place(depth: 1, continues: [false])),
            Cell(place: Nesting.Place(depth: 2, continues: [true, true])), Cell(place: Nesting.Place(depth: 2, continues: [false, false])),
            Cell(place: Nesting.Place(depth: 5, continues: [true, false, true, false, false])),
            Cell(place: Nesting.Place(depth: 1, continues: [true]), folded: true),
            Cell(place: Nesting.Place(depth: 3, continues: [false, true, false]), folded: true),
        ]
        let renderer = ImageRenderer(content:
            VStack(alignment: .leading, spacing: CardTreeLines.boardGap) {
                ForEach(cells.indices, id: \.self) { index in
                    let cell = cells[index]
                    let indent = CGFloat(min(cell.place.depth, CardTreeLines.deepest)) * CardTreeLines.indent
                    let card = Self.card(folded: cell.folded, subIssues: cell.subIssues)
                    Group {
                        if painted {
                            CardView(card: card, width: 300 - indent, stack: card.stack, tree: cell.place.depth > 0 ? cell.place : nil)
                                .padding(.bottom, CardStackEdge.height(card.stack))
                                .padding(.leading, indent)
                        } else {
                            CardView(card: card, width: 300 - indent)
                                .background(alignment: .top) { if card.stack > 0 { CardStackEdge(layers: card.stack) } }
                                .padding(.bottom, CardStackEdge.height(card.stack))
                                .padding(.leading, indent)
                                .background(alignment: .topLeading) {
                                    if cell.place.depth > 0 { CardTreeLines(place: cell.place, gap: CardTreeLines.boardGap) }
                                }
                        }
                    }
                }
                // The slot a lifted card would land in.
                if painted {
                    CardView(card: Self.card, width: 284, slotHeight: 96)
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.accent.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Theme.accent.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        )
                        .frame(width: 284, height: 96)
                }
            }
            .padding(10)
            .background(Theme.board)
            .environment(\.colorScheme, dark ? .dark : .light)
        )
        renderer.scale = 2
        guard let image = renderer.cgImage, let data = image.dataProvider?.data else { return Data() }
        return data as Data
    }

    @Test("A card stands on a card for each sub-issue up to three while they don't hang under it, each further back peeking out less")
    func stackFollowsSubIssues() {
        for (total, layers) in [(0, 0), (1, 1), (2, 2), (3, 3), (12, 3)] {
            #expect(Self.card(folded: false, subIssues: total).stack == layers)
        }
        // Hanging under it in its column, its sub-issues are in sight; folded into it, it stands on them again.
        #expect(Self.card(folded: false).stack == 0)
        #expect(Self.card(folded: true).stack == 3)
        let pile = CardStackEdge.placed(3)
        #expect(pile.map(\.depth) == [1, 2, 3])
        let peeks = zip(pile.map(\.below), [0] + pile.map(\.below)).map { $0 - $1 }
        #expect(peeks == peeks.sorted(by: >) && Set(peeks).count == 3)
        #expect(zip(pile, pile.dropFirst()).allSatisfy { $1.inset > $0.inset })
        #expect(CardStackEdge.height(0) == 0 && CardStackEdge.height(1) < CardStackEdge.height(2) && CardStackEdge.height(2) < CardStackEdge.height(3))
    }

    @Test("A board card paints its slot, the cards it stands on and the lines from its parent as the views they replaced")
    func boardCellLooksAsBefore() {
        warmUp()
        for dark in [false, true] {
            let painted = cells(dark: dark, painted: true)
            let views = cells(dark: dark, painted: false)
            #expect(!painted.isEmpty)
            // Painted in one pass, a card's anti-aliased corners fall on the edge under it straight away instead of
            // through a picture of their own, and this renderer rounds them a few 255ths apart; a line or an edge out
            // of place is tens of 255ths off.
            #expect(painted.count == views.count && zip(painted, views).allSatisfy { abs(Int($0) - Int($1)) <= 8 })
        }
    }

    @Test("After the other appearance, a card is painted in its own appearance's colours")
    func appearanceKeepsItsOwn() {
        warmUp()
        CardPaintCache.shared.removeAll()
        let light = picture(dark: false)
        let darkAfterLight = picture(dark: true)
        CardPaintCache.shared.removeAll()
        let dark = picture(dark: true)
        #expect(alike(darkAfterLight, dark))
        #expect(!alike(light, dark))
    }
}
#endif
