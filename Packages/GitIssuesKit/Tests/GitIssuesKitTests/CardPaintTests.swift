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
            blockedByCount: 2, milestoneTitle: "0.3"
        )
        let blocker = LinkedIssue(id: "issue-5", issueId: "issue-13", relation: .blockedBy, number: 5, title: "Keyboard navigation",
                                  state: "OPEN", position: 0)
        return CardModel(
            item: item, priority: .high, showsPriority: true,
            due: DueBadge(day: CalendarDay(year: 2026, month: 10, day: 21), label: "Tomorrow", tone: .upcoming),
            blocker: BlockerMark(blockers: [blocker], count: 2), nested: 2, showsParent: true, milestone: "0.3",
            milestoneMark: .current, chips: [FieldChip(fieldId: "cycle", text: "Cycle 4", icon: .iteration)]
        )
    }()

    /// The card in each look it can have, one under the other, as pixels.
    private func picture(dark: Bool) -> Data {
        struct Look: Hashable { var highlighted = false, selected = false, lifted = false, fold = false; var part: PickerKind? }
        let looks = [Look(), Look(highlighted: true), Look(selected: true), Look(lifted: true), Look(highlighted: true, fold: true)]
            + [PickerKind.priority, .labels, .subIssues, .assignees, .dueDate, .milestone, .blockedBy, .parent].map { Look(highlighted: true, part: $0) }
        let renderer = ImageRenderer(content:
            VStack(spacing: 6) {
                ForEach(looks, id: \.self) { look in
                    CardView(card: Self.card, width: 300, highlighted: look.highlighted, selected: look.selected, lifted: look.lifted,
                             hoveredPart: look.part, hoveringFold: look.fold)
                }
            }
            .padding(10)
            .background(Theme.lane)
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
