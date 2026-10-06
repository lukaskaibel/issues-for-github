import SwiftUI

/// Which issue the keyboard, the pointer and the step buttons act on. The keys themselves are wired up
/// per platform.
extension AppModel {
    /// The issue shortcuts and palette commands apply to.
    var targetItem: Item? {
        if let openItem { return openItem }
        // While peeking, keys act on the issue in the peek, wherever the pointer is: it may be reading the panel.
        if let peekItem { return peekItem }
        guard let id = hoveredItemId ?? focusedItemId else { return nil }
        return scopedItems.first { $0.id == id }
    }

    enum PointerEvent {
        case entered
        case left
    }

    /// Cards and rows report the pointer here. The pointer takes over from the keyboard focus, and
    /// nothing observable changes unless there was a keyboard focus to clear.
    func pointer(_ event: PointerEvent, _ id: String) {
        switch event {
        case .entered:
            guard !isDragging else { return }
            hoveredItemId = id
            if focusedItemId != nil { focusedItemId = nil }
        case .left:
            if hoveredItemId == id { hoveredItemId = nil }
        }
    }

    /// The issue keyboard navigation starts from: the one in the peek, else the keyboard focus, else the pointer.
    var cursorId: String? { peekItem?.id ?? focusedItemId ?? hoveredItemId }

    func moveFocus(to id: String, scroll: Bool = true) {
        hoveredItemId = nil
        focusedItemId = id
        if scroll { focusScrollToken += 1 }
        followPeek(to: id)
    }

    /// Issues in the order they read on screen, for stepping with J/K and the arrow buttons. Folded list
    /// sections are skipped, since their issues aren't on screen.
    var orderedItems: [Item] {
        if openItem == nil, viewMode == .board, currentProjectId != nil {
            return columns.flatMap(\.items)
        }
        return sections.filter { !isSectionCollapsed($0.id) }.flatMap(\.items)
    }

    func position(of item: Item) -> (index: Int, count: Int)? {
        let items = sections.flatMap(\.items)
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return nil }
        return (index, items.count)
    }

    /// Moves to the next or previous issue: opens it when an issue is open, otherwise moves the focus.
    func step(_ delta: Int) {
        let items = openItem != nil ? sections.flatMap(\.items) : orderedItems
        guard !items.isEmpty else { return }
        let currentId = openItemId ?? cursorId
        let next: Item
        if let index = items.firstIndex(where: { $0.id == currentId }) {
            next = items[min(max(index + delta, 0), items.count - 1)]
        } else {
            next = delta > 0 ? items[0] : items[items.count - 1]
        }
        if openItem != nil {
            // Stepping through issues doesn't pile up history: Back still leaves for the board or list.
            open(next, replacingHistory: true)
        } else {
            moveFocus(to: next.id)
        }
    }
}
