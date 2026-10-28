#if os(macOS)
import SwiftUI
import Testing
@testable import GitIssuesKit

@Suite("Sideways scrolling and navigation on the Mac")
@MainActor
struct NavigationSwipeTests {
    @Test("A board that fits the window allows navigation immediately", arguments: [true, false])
    func fittingBoard(back: Bool) {
        let board = BoardDrag()
        let swipe = AppModel.PendingSwipe(canGoBack: true, canGoForward: true, board: board)
        #expect(swipe.canSwipe(back: back))
    }

    @Test("An idle board allows Back only at the left edge and Forward only at the right edge")
    func edges() {
        let board = BoardDrag()
        board.maxScrollX = 600
        let left = AppModel.PendingSwipe(canGoBack: true, canGoForward: true, board: board)
        #expect(left.canSwipe(back: true))
        #expect(!left.canSwipe(back: false))
        board.scrollX = 600
        let right = AppModel.PendingSwipe(canGoBack: true, canGoForward: true, board: board)
        #expect(!right.canSwipe(back: true))
        #expect(right.canSwipe(back: false))
    }

    @Test("The middle of a board scrolls in both directions", arguments: [true, false])
    func middle(back: Bool) {
        let board = BoardDrag()
        board.maxScrollX = 600
        board.scrollX = 300
        let swipe = AppModel.PendingSwipe(canGoBack: true, canGoForward: true, board: board)
        #expect(!swipe.canSwipe(back: back))
    }

    @Test("Reaching an edge cannot navigate until a new gesture begins", arguments: [true, false])
    func newGestureAtEdge(back: Bool) {
        let board = BoardDrag()
        board.maxScrollX = 600
        board.scrollX = 300
        let scrolling = AppModel.PendingSwipe(canGoBack: true, canGoForward: true, board: board)
        board.scrollX = back ? 0 : 600
        #expect(!scrolling.canSwipe(back: back))
        let next = AppModel.PendingSwipe(canGoBack: true, canGoForward: true, board: board)
        #expect(next.canSwipe(back: back))
    }

    @Test("Lists and issue pages allow navigation in either direction", arguments: [true, false])
    func otherPages(back: Bool) {
        let swipe = AppModel.PendingSwipe(canGoBack: true, canGoForward: true)
        #expect(swipe.canSwipe(back: back))
    }

    @Test("A gesture still needs history in its requested direction")
    func history() {
        let backOnly = AppModel.PendingSwipe(canGoBack: true, canGoForward: false)
        #expect(backOnly.canSwipe(back: true))
        #expect(!backOnly.canSwipe(back: false))
        let forwardOnly = AppModel.PendingSwipe(canGoBack: false, canGoForward: true)
        #expect(!forwardOnly.canSwipe(back: true))
        #expect(forwardOnly.canSwipe(back: false))
    }

    @Test("Forward works at the actual right edge with a sidebar inset", arguments: [CGFloat(0), 210, 240, 340])
    func insetRightEdge(leadingInset: CGFloat) {
        let geometry = ScrollGeometry(
            contentOffset: CGPoint(x: 472 - leadingInset, y: 0),
            contentSize: CGSize(width: 1512, height: 728),
            contentInsets: EdgeInsets(top: 0, leading: leadingInset, bottom: 0, trailing: 0),
            containerSize: CGSize(width: 1040, height: 728)
        )
        let values = BoardView.scrollMetrics(geometry)
        let board = BoardDrag()
        board.scrollX = values[2]
        board.maxScrollX = values[1]
        let swipe = AppModel.PendingSwipe(canGoBack: true, canGoForward: true, board: board)
        #expect(swipe.canSwipe(back: false))
        #expect(!swipe.canSwipe(back: true))
    }

    @Test("A negative raw offset is not the left edge until it reaches the sidebar inset")
    func insetMiddleAndLeftEdge() {
        var geometry = ScrollGeometry(
            contentOffset: CGPoint(x: -120, y: 0),
            contentSize: CGSize(width: 1512, height: 728),
            contentInsets: EdgeInsets(top: 0, leading: 240, bottom: 0, trailing: 0),
            containerSize: CGSize(width: 1040, height: 728)
        )
        let board = BoardDrag()
        var values = BoardView.scrollMetrics(geometry)
        board.scrollX = values[2]
        board.maxScrollX = values[1]
        let middle = AppModel.PendingSwipe(canGoBack: true, canGoForward: true, board: board)
        #expect(!middle.canSwipe(back: true))
        #expect(!middle.canSwipe(back: false))
        geometry.contentOffset.x = -240
        values = BoardView.scrollMetrics(geometry)
        board.scrollX = values[2]
        let left = AppModel.PendingSwipe(canGoBack: true, canGoForward: true, board: board)
        #expect(left.canSwipe(back: true))
        #expect(!left.canSwipe(back: false))
        #expect(!middle.canSwipe(back: true))
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

    @Test("Cancellation clears a full arrow without navigating", arguments: [0.8, -0.8])
    func cancelledSwipe(amount: Double) {
        var swipe = AppModel.TrackedSwipe()
        _ = swipe.update(amount: amount, phase: .changed, isComplete: false)
        #expect(swipe.update(amount: amount, phase: [.changed, .cancelled], isComplete: false) == nil)
        #expect(swipe.finished)
        #expect(swipe.progress == 0)
    }

    @Test("A release with combined phase flags clears the arrow and navigates once")
    func combinedEndPhase() {
        var swipe = AppModel.TrackedSwipe()
        _ = swipe.update(amount: 0.8, phase: .changed, isComplete: false)
        #expect(swipe.update(amount: 1, phase: [.changed, .ended], isComplete: true) == true)
        #expect(swipe.finished)
        #expect(swipe.progress == 0)
    }

    @Test("A short swipe clears its arrow without navigating")
    func shortSwipe() {
        var swipe = AppModel.TrackedSwipe()
        _ = swipe.update(amount: 0.2, phase: .changed, isComplete: false)
        #expect(swipe.update(amount: 1, phase: .ended, isComplete: false) == nil)
        #expect(swipe.finished)
        #expect(swipe.progress == 0)
    }
}
#endif
