#if os(macOS)
import Observation
import Testing
@testable import GitIssuesKit

@MainActor
@Suite("The pointer on a board column, which redraws only the cards and headers it leaves and enters")
struct ColumnHoverTests {
    private final class Redrawn: @unchecked Sendable {
        var views: [String] = []
    }

    private let cards = (1...40).map { "card-\($0)" }
    private let headers = ["epic-1", "epic-2"]

    /// The cards and headers that `change` would redraw, each watched the way SwiftUI watches its body.
    private func redrawn(_ hover: ColumnHover, by change: () -> Void) -> [String] {
        let redrawn = Redrawn()
        for card in cards {
            withObservationTracking { _ = hover[card: card] } onChange: { redrawn.views.append(card) }
        }
        for header in headers {
            withObservationTracking { _ = hover[header: header] } onChange: { redrawn.views.append(header) }
        }
        change()
        return redrawn.views.sorted()
    }

    @Test func goingFromOneCardToTheNextRedrawsThoseTwo() {
        let hover = ColumnHover()
        hover.update(.init(card: .init(id: "card-3")))
        #expect(redrawn(hover) { hover.update(.init(card: .init(id: "card-4"))) } == ["card-3", "card-4"])
        #expect(hover[card: "card-4"] != nil)
        #expect(hover[card: "card-3"] == nil)
    }

    @Test func movingOverTheCardsPartsRedrawsOnlyThatCard() {
        let hover = ColumnHover()
        hover.update(.init(card: .init(id: "card-7")))
        #expect(redrawn(hover) { hover.update(.init(card: .init(id: "card-7", part: .labels))) } == ["card-7"])
        #expect(redrawn(hover) { hover.update(.init(card: .init(id: "card-7", onFold: true))) } == ["card-7"])
        #expect(hover[card: "card-7"]?.onFold == true)
    }

    @Test func staysQuietWhileThePointerStaysOnTheSamePart() {
        let hover = ColumnHover()
        hover.update(.init(card: .init(id: "card-2", part: .priority)))
        #expect(redrawn(hover) { hover.update(.init(card: .init(id: "card-2", part: .priority))) } == [])
    }

    @Test func goingFromACardOntoAnEpicsHeaderRedrawsBoth() {
        let hover = ColumnHover()
        hover.update(.init(card: .init(id: "card-9")))
        #expect(redrawn(hover) { hover.update(.init(header: .init(epic: "epic-2"))) } == ["card-9", "epic-2"])
        #expect(redrawn(hover) { hover.update(.init(header: .init(epic: "epic-2", onFold: true))) } == ["epic-2"])
        #expect(redrawn(hover) { hover.update(.init()) } == ["epic-2"])
    }

    @Test func theTooltipFollowsEveryChange() {
        let hover = ColumnHover()
        let redrawn = Redrawn()
        withObservationTracking { _ = hover.current } onChange: { redrawn.views.append("tooltip") }
        hover.update(.init(card: .init(id: "card-1", part: .assignees)))
        #expect(redrawn.views == ["tooltip"])
        #expect(hover.current.card?.part == .assignees)
    }
}
#endif
