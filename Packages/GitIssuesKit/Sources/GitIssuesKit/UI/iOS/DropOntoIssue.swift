#if os(iOS)
import SwiftUI

/// A card held over the middle of another card and let go there becomes that issue's sub-issue; held over a card's
/// top or bottom edge, or between cards, it goes to that place in the column as before. Only the parent changes: the
/// issue keeps its status, so a card dropped onto an issue in another column goes back to its own one, where it shows
/// whose sub-issue it is.
extension AppModel {
    /// Whether `child`, being dragged, can be dropped onto `parent` to become its sub-issue: both are issues GitHub
    /// knows as such (not drafts or pull requests), and `parent` is neither `child` itself, nor anything under it,
    /// nor already its parent.
    func canDropAsSubIssue(_ child: Item, onto parent: Item) -> Bool {
        guard canRelate(child), canRelate(parent), let childId = child.contentId, let parentId = parent.contentId,
              child.parentId != parentId else { return false }
        return !descendants(of: [childId]).contains(parentId)
    }

    /// Makes `child` a sub-issue of `parent` after a drop, as the Parent picker does, and says so, with a way to take
    /// it back: the drop is quick to do by mistake, and a card dropped onto an issue in another column goes back to its
    /// own column, so the change would otherwise be easy to miss.
    func dropAsSubIssue(_ child: Item, onto parent: Item) {
        guard canDropAsSubIssue(child, onto: parent), let summary = child.summary else { return }
        let before = child.parentId.flatMap { issue(contentId: $0) }
        setParent(of: [child], to: parent)
        let undo = Mutation.setParent(.init(
            child: summary, parentId: child.parentId, parentNumber: before?.number ?? child.parentNumber,
            parentTitle: before?.title ?? child.parentTitle, base: parent.contentId
        ))
        status.post(Notice(
            title: String(localized: .droppedAsSubIssue(issue: child.displayNumber, parent: parent.displayNumber)),
            message: parent.title,
            action: .undo([undo])
        ))
    }
}
#endif
