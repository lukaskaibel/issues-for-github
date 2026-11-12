#if os(iOS)
import SwiftUI

/// A card or row held over the middle of another issue and let go there becomes that issue's sub-issue; held over a
/// card's or row's top or bottom edge, or between cards, it goes to that place as before. What may go under what, and
/// the notice that undoes it, are the Mac's (`AppModel+DropNesting.swift`): only the parent changes, so the issue keeps
/// its status, and a card dropped onto an issue in another column goes back to its own one, where it names its parent.
/// This is what the board and the list share for it.
enum DropOntoIssue {
    /// How far into a card or row from its top and bottom the finger places the dragged issue above or below it
    /// rather than under it: a quarter of it, at least enough to hit with a finger, and at most so much that the middle
    /// stays easy to hit on a short card.
    static func edge(of height: CGFloat) -> CGFloat {
        min(max(height * 0.25, 14), 26)
    }

    /// Makes the dropped issue (the drag's item id) a sub-issue of the one (`parentId`, an item id) it was let go over.
    /// A parent whose sub-issues are folded into it where it shows (`shown`) opens, so that one hanging under it there
    /// doesn't vanish into it. False when the drag carried nothing that can go there.
    @MainActor @discardableResult
    static func nest(_ id: String?, under parentId: String, shown: Nesting, model: AppModel) -> Bool {
        guard let id, DraggedGroup(id) == nil, let child = model.item(id: id), let parent = model.item(id: parentId),
              model.canNest([child], under: parent) else { return false }
        if shown.folded.contains(parent.id) { model.setFolded(parent, false) }
        model.nest([child], under: parent)
        return true
    }

    /// What a dragged issue is outside the app: its link on GitHub, or its number and title.
    static func text(_ item: Item) -> String {
        item.url ?? "\(item.displayNumber) \(item.title)"
    }
}
#endif
