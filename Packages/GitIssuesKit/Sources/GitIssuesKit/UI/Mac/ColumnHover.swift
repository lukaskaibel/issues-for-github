#if os(macOS)
import Observation
import SwiftUI

/// What the pointer is on in a board column: a card and the part of it, or the header over an epic's issues and
/// whether on its arrow. Each card and header asks only about itself, so the pointer going from one card to the next
/// redraws those two and nothing else: the column keeps what it worked out for its other cards, however many it has.
@MainActor @Observable
final class ColumnHover {
    struct Card: Equatable {
        var id: String
        /// The clickable part under the pointer, drawn with a soft highlight.
        var part: PickerKind?
        /// Whether the pointer is on the arrow that folds the sub-issues under the card.
        var onFold = false
        /// Whether the pointer is on the card's number, whose tooltip names the repository. The card looks the same.
        var onNumber = false
    }

    struct Header: Equatable {
        /// The epic's content id.
        var epic: String
        var onFold = false
    }

    struct State: Equatable {
        var card: Card?
        var header: Header?
    }

    @ObservationIgnored private var state = State()

    /// Everything under the pointer, for the tooltip and for event handlers. A view that reads it in its body is
    /// redrawn on every change; cards and headers ask `[card:]` and `[header:]` instead.
    var current: State {
        access(keyPath: \.current)
        return state
    }

    /// The card's hover, nil when the pointer isn't on it.
    subscript(card id: String) -> Card? {
        access(keyPath: \.[card: id])
        return state.card?.id == id ? state.card : nil
    }

    /// The header's hover, nil when the pointer isn't on it.
    subscript(header epic: String) -> Header? {
        access(keyPath: \.[header: epic])
        return state.header?.epic == epic ? state.header : nil
    }

    func update(_ new: State) {
        // An observable's setter notifies even when nothing changed; the pointer mostly stays on the same part.
        guard new != state else { return }
        let old = state
        let cards = Set([old.card?.id, new.card?.id].compactMap { $0 }).filter { id in
            (old.card?.id == id ? old.card : nil) != (new.card?.id == id ? new.card : nil)
        }
        let headers = Set([old.header?.epic, new.header?.epic].compactMap { $0 }).filter { epic in
            (old.header?.epic == epic ? old.header : nil) != (new.header?.epic == epic ? new.header : nil)
        }
        let cardPaths = cards.map { \ColumnHover.[card: $0] }
        let headerPaths = headers.map { \ColumnHover.[header: $0] }
        withMutation(keyPath: \.current) {
            for path in cardPaths { _$observationRegistrar.willSet(self, keyPath: path) }
            for path in headerPaths { _$observationRegistrar.willSet(self, keyPath: path) }
            state = new
            for path in cardPaths { _$observationRegistrar.didSet(self, keyPath: path) }
            for path in headerPaths { _$observationRegistrar.didSet(self, keyPath: path) }
        }
    }
}
#endif
