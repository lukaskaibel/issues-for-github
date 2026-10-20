#if os(macOS)
import AppKit

extension AppModel {
    /// A click on an issue with ⌘ or Shift held changes the selection instead of opening it.
    /// Returns whether the click was used that way.
    func handleSelectionClick(on item: Item) -> Bool {
        let modifiers = NSEvent.modifierFlags.intersection([.command, .shift])
        if modifiers.contains(.shift) {
            extendSelection(to: item)
        } else if modifiers.contains(.command) {
            toggleSelection(item)
        } else {
            return false
        }
        moveFocus(to: item.id, scroll: false)
        return true
    }

    /// The same on a sub-issue on an issue's page, among `order`, the sub-issues as listed there. One that is on
    /// GitHub only can't be changed with the others, so the click does nothing to it.
    func handleSubIssueClick(on item: Item?, in order: [String]) -> Bool {
        let modifiers = NSEvent.modifierFlags.intersection([.command, .shift])
        guard !modifiers.isEmpty else { return false }
        guard let item else { return true }
        if modifiers.contains(.shift) {
            extendSubIssuePick(to: item, in: order)
        } else {
            toggleSubIssuePick(item)
        }
        return true
    }
}
#endif
