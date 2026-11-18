#if os(macOS)
import AppKit

/// One press on the trackpad, from the button going down: whether it turns into a deep press, the second stage of a
/// Force Touch trackpad. Only the step into that stage counts, once per press, and only while the pointer stays put, so
/// that a card being dragged with a heavy finger doesn't open anything.
struct DeepPress {
    static let allowedMovement: CGFloat = 4

    private var start: CGPoint?
    private var stage = 1
    /// This press opened the peek, so its release is no click. Holds until the next press.
    private(set) var openedPeek = false

    /// `counts` is false for a press that can't become a peek, as one outside the main window or with a modifier.
    mutating func begin(at point: CGPoint, counts: Bool) {
        start = counts ? point : nil
        stage = 1
        openedPeek = false
    }

    mutating func end() {
        start = nil
    }

    /// Whether this change of stage is the step into a deep press.
    mutating func update(stage newStage: Int, at point: CGPoint) -> Bool {
        guard let start else { return false }
        guard hypot(point.x - start.x, point.y - start.y) <= Self.allowedMovement else {
            self.start = nil
            return false
        }
        defer { stage = newStage }
        return newStage >= 2 && stage < 2
    }

    mutating func didOpenPeek() {
        openedPeek = true
        start = nil
    }
}

extension AppModel {
    /// Presses seen by the app's event monitor: all but those on a row of the list while it follows them itself.
    func followPress(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            deepPress.begin(at: NSEvent.mouseLocation,
                            counts: event.window === mainWindow && modifiers.isDisjoint(with: [.command, .shift, .option, .control]))
        case .leftMouseUp:
            deepPress.end()
        case .pressure:
            pressureChanged(to: event.stage, over: hoveredItemId.flatMap { id in scopedItems.first { $0.id == id } })
        default:
            break
        }
    }

    /// Opens the peek on the issue if this is the step into a deep press. The Inbox shows its issue beside the list
    /// already, and over a dialog, an open issue or a peek there is nothing to look at.
    @discardableResult
    func pressureChanged(to stage: Int, over item: Item?) -> Bool {
        guard deepPress.update(stage: stage, at: NSEvent.mouseLocation), let item, overlay == nil, openItem == nil,
              peekItemId == nil, scope != .inbox, !isDragging, !boardDrag.isDragging else { return false }
        deepPress.didOpenPeek()
        peek(at: item)
        return true
    }
}
#endif
