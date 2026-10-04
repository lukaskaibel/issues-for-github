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
                NSMenu.popUpContextMenu(menu, with: event, for: content)
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

    /// Starts following a horizontal two-finger swipe if it should navigate rather than scroll.
    private func trackSwipe(_ event: NSEvent) -> Bool {
        guard signedIn, overlay == nil, swipeProgress == 0,
              NSEvent.isSwipeTrackingFromScrollEventsEnabled,
              event.phase == .began,
              abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return false }
        let wantsBack = event.scrollingDeltaX > 0
        guard wantsBack ? canGoBack : canGoForward else { return false }
        // On the board a sideways swipe scrolls the columns; it only navigates once the board is at its edge.
        if openItem == nil, viewMode == .board, currentProjectId != nil {
            let atEdge = wantsBack ? boardDrag.scrollX <= 0.5 : boardDrag.scrollX >= boardDrag.maxScrollX - 0.5
            if !atEdge { return false }
        }
        event.trackSwipeEvent(
            options: [.lockDirection, .clampGestureAmount],
            dampenAmountThresholdMin: canGoForward ? -1 : 0,
            max: canGoBack ? 1 : 0
        ) { [weak self] amount, phase, isComplete, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if phase == .ended {
                    if amount > 0 { self.goBack() } else if amount < 0 { self.goForward() }
                }
                if isComplete || phase == .ended || phase == .cancelled {
                    withAnimation(Theme.quick) { self.swipeProgress = 0 }
                } else {
                    self.swipeProgress = Double(amount)
                }
            }
        }
        return true
    }
}
#endif
