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

    /// Navigation is decided at the start of a gesture; reaching an edge later must not turn a scroll into Back.
    @MainActor
    struct PendingSwipe {
        var delta = CGSize.zero
        var events: [NSEvent] = []
        let canGoBack: Bool
        let canGoForward: Bool

        init(canGoBack: Bool, canGoForward: Bool, board: BoardDrag? = nil) {
            if let board, board.maxScrollX > 0.5 {
                self.canGoBack = canGoBack && board.scrollX <= 0.5
                self.canGoForward = canGoForward && board.scrollX >= board.maxScrollX - 0.5
            } else {
                self.canGoBack = canGoBack
                self.canGoForward = canGoForward
            }
        }

        func canSwipe(back: Bool) -> Bool { back ? canGoBack : canGoForward }
    }

    @MainActor
    struct TrackedSwipe {
        private(set) var progress: Double = 0
        private(set) var finished = false

        /// Returns a navigation direction only once, when the fingers lift after reaching the threshold.
        mutating func update(amount: Double, phase: NSEvent.Phase, isComplete: Bool) -> Bool? {
            guard !finished else { return nil }
            if phase.contains(.ended) || phase.contains(.cancelled) || isComplete {
                let back: Bool? = phase.contains(.ended) && !phase.contains(.cancelled) && abs(progress) >= AppModel.swipeThreshold
                    ? progress > 0 : nil
                progress = 0
                finished = true
                return back
            }
            if phase.contains(.began) || phase.contains(.changed) { progress = amount }
            return nil
        }
    }

    /// How far a two-finger swipe goes sideways before it navigates, in points, and how much of that it may go up or
    /// down without becoming a scroll. Safari's numbers (WebKit's `minimumHorizontalSwipeDistance`).
    private static let swipeDistance: CGFloat = 15
    private static let swipeSlope: CGFloat = 0.5

    /// Starts following a two-finger swipe once it has gone clearly sideways, so a scroll that drifts a little to the
    /// side doesn't go back. Its first events are held back until then.
    private func trackSwipe(_ event: NSEvent) -> Bool {
        // Momentum has no physical gesture phase and must never start or advance navigation.
        guard !event.phase.isEmpty else { return false }
        if event.phase.contains(.began) {
            pendingSwipe = nil
            guard signedIn, overlay == nil, swipeProgress == 0, event.hasPreciseScrollingDeltas,
                  NSEvent.isSwipeTrackingFromScrollEventsEnabled else { return false }
            let board = openItem == nil && viewMode == .board && currentProjectId != nil ? boardDrag : nil
            pendingSwipe = PendingSwipe(canGoBack: canGoBack, canGoForward: canGoForward, board: board)
        }
        guard var pending = pendingSwipe else { return false }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            releaseSwipe(pending)
            return false
        }
        pending.delta.width += event.scrollingDeltaX
        pending.delta.height += event.scrollingDeltaY
        pending.events.append(event)
        let wantsBack = pending.delta.width > 0
        let sideways = abs(pending.delta.width)
        if abs(pending.delta.height) > sideways * Self.swipeSlope || (sideways > 0 && !pending.canSwipe(back: wantsBack)) {
            pending.events.removeLast()
            releaseSwipe(pending)
            return false
        }
        guard sideways >= Self.swipeDistance else {
            pendingSwipe = pending
            return true
        }
        pendingSwipe = nil
        var swipe = TrackedSwipe()
        event.trackSwipeEvent(
            options: [.lockDirection, .clampGestureAmount],
            dampenAmountThresholdMin: pending.canGoForward ? -1 : 0,
            max: pending.canGoBack ? 1 : 0
        ) { [weak self] amount, phase, isComplete, stop in
            MainActor.assumeIsolated {
                guard let self else { stop.pointee = true; return }
                let back = swipe.update(amount: Double(amount), phase: phase, isComplete: isComplete)
                if swipe.finished {
                    // Our own fade finishes the arrow; AppKit's remaining animation must not bring it back.
                    stop.pointee = true
                    withAnimation(Theme.quick) { self.swipeProgress = 0 }
                } else {
                    self.swipeProgress = swipe.progress
                }
                if let back {
                    if back { self.goBack() } else { self.goForward() }
                }
            }
        }
        return true
    }

    /// How far a two-finger swipe has to go, in the system's swipe amount, for letting go to go back or forward. The
    /// arrow is full from there.
    static let swipeThreshold = 0.5

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
