#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import GitIssuesKit

@Suite("Sideways scrolling and navigation on the Mac")
@MainActor
struct NavigationSwipeTests {
    @Test("Forward works at the actual right edge with a sidebar inset", arguments: [CGFloat(0), 210, 240, 340])
    func insetRightEdge(leadingInset: CGFloat) {
        let geometry = ScrollGeometry(
            contentOffset: CGPoint(x: 472 - leadingInset, y: 0),
            contentSize: CGSize(width: 1512, height: 728),
            contentInsets: EdgeInsets(top: 0, leading: leadingInset, bottom: 0, trailing: 0),
            containerSize: CGSize(width: 1040, height: 728)
        )
        let values = BoardView.scrollMetrics(geometry)
        let policy = HistorySwipePolicy(canGoBack: true, canGoForward: true, surface: .board(offset: values[2], maximum: values[1]))
        #expect(policy.allowsForward)
        #expect(!policy.allowsBack)
    }

    @Test("A negative raw offset is not the left edge until it reaches the sidebar inset")
    func insetMiddleAndLeftEdge() {
        var geometry = ScrollGeometry(
            contentOffset: CGPoint(x: -120, y: 0),
            contentSize: CGSize(width: 1512, height: 728),
            contentInsets: EdgeInsets(top: 0, leading: 240, bottom: 0, trailing: 0),
            containerSize: CGSize(width: 1040, height: 728)
        )
        var values = BoardView.scrollMetrics(geometry)
        let middle = HistorySwipePolicy(canGoBack: true, canGoForward: true, surface: .board(offset: values[2], maximum: values[1]))
        #expect(!middle.allowsBack)
        #expect(!middle.allowsForward)
        geometry.contentOffset.x = -240
        values = BoardView.scrollMetrics(geometry)
        let left = HistorySwipePolicy(canGoBack: true, canGoForward: true, surface: .board(offset: values[2], maximum: values[1]))
        #expect(left.allowsBack)
        #expect(!left.allowsForward)
        #expect(!middle.allowsBack)
    }

    @Test("A completed navigation clears the arrow and ignores later animation callbacks", arguments: [0.8, -0.8])
    func finishedSwipe(amount: Double) {
        var swipe = AppModel.TrackedSwipe()
        #expect(swipe.update(amount: amount, phase: .changed, isComplete: false) == nil)
        #expect(swipe.progress == amount)
        #expect(swipe.update(amount: amount, phase: .ended, isComplete: false) == (amount > 0))
        #expect(swipe.finished)
        #expect(swipe.progress == 0)
        #expect(swipe.update(amount: amount, phase: .changed, isComplete: false) == nil)
        #expect(swipe.update(amount: amount, phase: .ended, isComplete: true) == nil)
        #expect(swipe.progress == 0)
    }

    @Test("Completion clears the arrow even when the callback's phase is changed")
    func completionDuringChange() {
        var swipe = AppModel.TrackedSwipe()
        _ = swipe.update(amount: 0.8, phase: .changed, isComplete: false)
        #expect(swipe.update(amount: 1, phase: .changed, isComplete: true) == nil)
        #expect(swipe.finished)
        #expect(swipe.progress == 0)
    }

    @Test("A slow lift clears a full arrow and navigates once", arguments: [0.8, -0.8])
    func slowLift(amount: Double) {
        var swipe = AppModel.TrackedSwipe()
        _ = swipe.update(amount: amount, phase: .changed, isComplete: false)
        #expect(swipe.update(amount: amount, phase: [.changed, .cancelled], isComplete: false) == (amount > 0))
        #expect(swipe.finished)
        #expect(swipe.progress == 0)
        #expect(swipe.update(amount: amount, phase: .ended, isComplete: true) == nil)
    }

    @Test("A release with combined phase flags clears the arrow and navigates once")
    func combinedEndPhase() {
        var swipe = AppModel.TrackedSwipe()
        _ = swipe.update(amount: 0.8, phase: .changed, isComplete: false)
        #expect(swipe.update(amount: 1, phase: [.changed, .ended], isComplete: true) == true)
        #expect(swipe.finished)
        #expect(swipe.progress == 0)
    }

    @Test("A short swipe clears its arrow without navigating", arguments: [NSEvent.Phase.ended, .cancelled])
    func shortSwipe(phase: NSEvent.Phase) {
        var swipe = AppModel.TrackedSwipe()
        _ = swipe.update(amount: 0.2, phase: .changed, isComplete: false)
        #expect(swipe.update(amount: 1, phase: phase, isComplete: false) == nil)
        #expect(swipe.finished)
        #expect(swipe.progress == 0)
    }
}
#endif
