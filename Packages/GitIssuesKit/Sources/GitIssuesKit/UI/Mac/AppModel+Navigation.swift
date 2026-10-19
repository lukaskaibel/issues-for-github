#if os(macOS)
import AppKit
import SwiftUI

extension AppModel {
    // MARK: Mouse buttons and trackpad swipes

    func installNavigationMonitors() {
        // Buttons 3 and 4 are the "back" and "forward" side buttons on most mice.
        NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
            guard let self, event.buttonNumber == 3 || event.buttonNumber == 4 else { return event }
            let number = event.buttonNumber
            let handled = MainActor.assumeIsolated {
                guard self.signedIn else { return false }
                if number == 3 { self.goBack() } else { self.goForward() }
                return true
            }
            return handled ? nil : event
        }
        // Three-finger swipe, when "Swipe between pages" is set to three fingers.
        NSEvent.addLocalMonitorForEvents(matching: .swipe) { [weak self] event in
            guard let self, event.deltaX != 0 else { return event }
            let back = event.deltaX > 0
            let handled = MainActor.assumeIsolated {
                guard self.signedIn else { return false }
                if back { self.goBack() } else { self.goForward() }
                return true
            }
            return handled ? nil : event
        }
        // Right-click menus on SwiftUI areas (cards, sub-issues). The list's table shows its own.
        NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
            guard let self, ContextMenus.isContextClick(event) else { return event }
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard self.signedIn, self.overlay == nil, let window = event.window, window === self.mainWindow,
                      let content = window.contentView else { return false }
                let point = CGPoint(x: event.locationInWindow.x, y: content.bounds.height - event.locationInWindow.y)
                guard let menu = ContextMenus.shared.menu(at: point) else { return false }
                // In glass, at the pickers' size, as every right-click menu of the app.
                GlassMenu.show(menu, at: event, in: content, model: self)
                return true
            }
            return handled ? nil : event
        }
        // Two-finger swipe, as in Safari.
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            let handled = MainActor.assumeIsolated { self.trackSwipe(event) }
            return handled ? nil : event
        }
    }

    /// The events of a two-finger swipe so far, and how far the fingers have moved.
    struct PendingSwipe {
        var delta = CGSize.zero
        var events: [NSEvent] = []
    }

    /// How far a two-finger swipe goes sideways before it navigates, in points, and how much of that it may go up or
    /// down without becoming a scroll. Safari's numbers (WebKit's `minimumHorizontalSwipeDistance`).
    private static let swipeDistance: CGFloat = 15
    private static let swipeSlope: CGFloat = 0.5

    /// Starts following a two-finger swipe once it has gone clearly sideways, so a scroll that drifts a little to the
    /// side doesn't go back. Its first events are held back until then.
    private func trackSwipe(_ event: NSEvent) -> Bool {
        if event.phase == .began {
            pendingSwipe = nil
            guard signedIn, overlay == nil, swipeProgress == 0, event.hasPreciseScrollingDeltas,
                  NSEvent.isSwipeTrackingFromScrollEventsEnabled else { return false }
            pendingSwipe = PendingSwipe()
        }
        guard var pending = pendingSwipe else { return false }
        if event.phase == .ended || event.phase == .cancelled {
            releaseSwipe(pending)
            return false
        }
        pending.delta.width += event.scrollingDeltaX
        pending.delta.height += event.scrollingDeltaY
        pending.events.append(event)
        let wantsBack = pending.delta.width > 0
        let sideways = abs(pending.delta.width)
        if abs(pending.delta.height) > sideways * Self.swipeSlope || (sideways > 0 && !canSwipe(back: wantsBack)) {
            pending.events.removeLast()
            releaseSwipe(pending)
            return false
        }
        guard sideways >= Self.swipeDistance else {
            pendingSwipe = pending
            return true
        }
        pendingSwipe = nil
        event.trackSwipeEvent(
            options: [.lockDirection, .clampGestureAmount],
            dampenAmountThresholdMin: canGoForward ? -1 : 0,
            max: canGoBack ? 1 : 0
        ) { [weak self] amount, phase, isComplete, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch phase {
                case .began, .changed:
                    self.swipeProgress = Double(amount)
                case .ended, .cancelled:
                    // It goes if the arrow is full as the fingers lift. The system would also count a short quick
                    // flick, which is how a swipe went back without meaning to.
                    let progress = self.swipeProgress
                    if abs(progress) >= Self.swipeThreshold {
                        if progress > 0 { self.goBack() } else { self.goForward() }
                    }
                    withAnimation(Theme.quick) { self.swipeProgress = 0 }
                default:
                    // The system finishing its own animation; the arrow is already gone.
                    if isComplete, self.swipeProgress != 0 {
                        withAnimation(Theme.quick) { self.swipeProgress = 0 }
                    }
                }
            }
        }
        return true
    }

    /// How far a two-finger swipe has to go, in the system's swipe amount, for letting go to go back or forward. The
    /// arrow is full from there.
    static let swipeThreshold = 0.5

    private func canSwipe(back: Bool) -> Bool {
        guard back ? canGoBack : canGoForward else { return false }
        // On the board a sideways swipe scrolls the columns; it only navigates once the board is at its edge.
        if openItem == nil, viewMode == .board, currentProjectId != nil {
            return back ? boardDrag.scrollX <= 0.5 : boardDrag.scrollX >= boardDrag.maxScrollX - 0.5
        }
        return true
    }

    /// A held-back swipe turned out to be a scroll: its events go to the view under the pointer after all, in order,
    /// before the one that decided it.
    private func releaseSwipe(_ pending: PendingSwipe) {
        pendingSwipe = nil
        for held in pending.events {
            held.window?.sendEvent(held)
        }
    }
}
#endif
