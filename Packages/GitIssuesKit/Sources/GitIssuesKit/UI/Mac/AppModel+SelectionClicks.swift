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
}
#endif
