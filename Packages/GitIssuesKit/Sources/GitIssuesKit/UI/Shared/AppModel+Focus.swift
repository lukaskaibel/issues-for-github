import SwiftUI

/// Which issue the keyboard, the pointer and the step buttons act on. The keys themselves are wired up
/// per platform.
extension AppModel {
    /// The issue shortcuts and palette commands apply to.
    var targetItem: Item? {
        if let openItem { return openItem }
        // While peeking, keys act on the issue in the peek, wherever the pointer is: it may be reading the panel.
        if let peekItem { return peekItem }
        // In the Inbox, the issue of the selected entry.
        if scope == .inbox { return inboxSelected.flatMap { inboxItem(for: $0) } }
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

    /// The issues the keyboard focus moves among, by column or by section: what takes the focus over from one that
    /// goes.
    var focusGroups: [[String]] {
        if openItem == nil, viewMode == .board, currentProjectId != nil { return columns.map { $0.items.map(\.id) } }
        return sections.filter { !isFolded($0) }.map { $0.items.map(\.id) }
    }

    /// The issue after `id` in its column or section that `keeps`, or else the one before it; with none left there,
    /// the first of the next column or section, or the last of the one before.
    static func neighbour(of id: String, in groups: [[String]], keeping keeps: (String) -> Bool) -> String? {
        guard let place = groups.firstIndex(where: { $0.contains(id) }), let index = groups[place].firstIndex(of: id) else { return nil }
        let group = groups[place]
        if let near = group[(index + 1)...].first(where: keeps) ?? group[..<index].last(where: keeps) { return near }
        return groups[(place + 1)...].joined().first(where: keeps) ?? Array(groups[..<place].joined()).last(where: keeps)
    }

    /// After the board or list changed under the keyboard focus (`groups` is how it was): an issue no longer shown,
    /// moved out of the view, folded away or in a hidden column, hands the focus to its neighbour, as a deleted one
    /// does.
    func keepFocusShown(from groups: [[String]]) {
        guard let focused = focusedItemId, openItemId == nil else { return }
        let shown = Set(orderedItems.map(\.id))
        guard !shown.contains(focused) else { return }
        // An issue GitHub has just created keeps the focus under its new id.
        if let new = status.idRemaps[focused], shown.contains(new) {
            focusedItemId = new
            return
        }
        focusedItemId = Self.neighbour(of: focused, in: groups) { shown.contains($0) }
    }

    /// Shows a new issue where it landed: its parent's sub-issues unfolded, and on the Mac its section of the list.
    func reveal(_ id: String) {
        guard let new = allItems.first(where: { $0.id == id }) else { return }
        if let parentId = new.parentId, let parent = item(contentId: parentId), isFolded(parent) { setFolded(parent, false) }
        #if os(macOS)
        // The list on screen; iPhone and iPad keep a list per screen, whose sections fold where they are.
        if viewMode == .list || currentProjectId == nil,
           let section = sections.first(where: { $0.nesting.members.contains { $0.id == id } }), isFolded(section) {
            withAnimation(Theme.spring) { toggleSection(section.id) }
        }
        #endif
    }

    func moveFocus(to id: String, scroll: Bool = true) {
        hoveredItemId = nil
        focusedItemId = id
        if scroll { focusScrollToken += 1 }
        followPeek(to: id)
    }

    /// Issues in the order they read on screen, for stepping with J/K and the arrow buttons. Folded list
    /// sections are skipped, since their issues aren't on screen.
    var orderedItems: [Item] {
        // The timelines have no keyboard focus of their own; their epics and issues open with a click.
        if openItem == nil, case .roadmap = scope, roadmapLayout == .timeline { return [] }
        #if os(macOS)
        if openItem == nil, let view = currentView, showsTimeline(view) { return [] }
        #endif
        if openItem == nil, viewMode == .board, currentProjectId != nil {
            return columns.flatMap(\.items)
        }
        return sections.filter { !isFolded($0) }.flatMap(\.items)
    }

    func position(of item: Item) -> (index: Int, count: Int)? {
        let items = stepOrder
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return nil }
        return (index, items.count)
    }

    /// The issues J and K go through, each once, though one can read twice (in the groups of both its assignees).
    /// With an issue open, those of the board or list it was opened from, folded sections included, in that order.
    private var stepOrder: [Item] {
        let items: [Item] = if openItem == nil {
            orderedItems
        } else if viewMode == .board, currentProjectId != nil, !columns.isEmpty {
            columns.flatMap(\.items)
        } else {
            sections.flatMap(\.items)
        }
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }

    /// Moves to the next or previous issue: opens it when an issue is open, otherwise moves the focus.
    func step(_ delta: Int) {
        let items = stepOrder
        guard !items.isEmpty else { return }
        let currentId = openItemId ?? cursorId
        let next: Item
        if let index = items.firstIndex(where: { $0.id == currentId }) {
            next = items[min(max(index + delta, 0), items.count - 1)]
        } else {
            // An open issue the board or list doesn't show, such as an epic or a blocker from another board, has no
            // next one there.
            guard openItem == nil else { return }
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
