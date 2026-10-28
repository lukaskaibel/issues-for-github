#if os(macOS)
import AppKit
import Testing
@testable import GitIssuesKit

@Suite("Horizontal scrolling and history swipes")
struct HistorySwipePolicyTests {
    @Test("A timeline keeps horizontal pans for scrolling, even when history is available", arguments: [false, true], [false, true])
    func timelineDoesNotNavigate(canGoBack: Bool, canGoForward: Bool) {
        let policy = HistorySwipePolicy(canGoBack: canGoBack, canGoForward: canGoForward, surface: .timeline)

        #expect(!policy.canTrack)
        #expect(!policy.allowsBack)
        #expect(!policy.allowsForward)
        #expect(!policy.allows(back: true))
        #expect(!policy.allows(back: false))
    }

    @Test("A page only offers directions present in its history", arguments: [false, true], [false, true])
    func pageUsesAvailableHistory(canGoBack: Bool, canGoForward: Bool) {
        let policy = HistorySwipePolicy(canGoBack: canGoBack, canGoForward: canGoForward, surface: .page)

        #expect(policy.allowsBack == canGoBack)
        #expect(policy.allowsForward == canGoForward)
        #expect(policy.allows(back: true) == canGoBack)
        #expect(policy.allows(back: false) == canGoForward)
        #expect(policy.canTrack == (canGoBack || canGoForward))
    }

    @Test("Board columns scroll internally; only an outward swipe at an edge can navigate", arguments: [CGFloat(0), CGFloat(200), CGFloat(400)])
    func boardKeepsItsEdgeBehavior(offset: CGFloat) {
        let policy = HistorySwipePolicy(canGoBack: true, canGoForward: true, surface: .board(offset: offset, maximum: 400))

        #expect(policy.allowsBack == (offset == 0))
        #expect(policy.allowsForward == (offset == 400))
        #expect(policy.canTrack == (offset != 200))
    }

    @Test("A board that fits in the viewport retains both available history directions")
    func boardWithoutOverflowIsAtBothEdges() {
        let policy = HistorySwipePolicy(canGoBack: true, canGoForward: true, surface: .board(offset: 0, maximum: 0))

        #expect(policy.allowsBack)
        #expect(policy.allowsForward)
    }

    @Test("A pan that starts between board edges cannot become navigation as it reaches an edge or reverses")
    func gestureKeepsItsInitialPolicy() {
        var offset: CGFloat = 200
        let pan = HistorySwipePolicy(canGoBack: true, canGoForward: true, surface: .board(offset: offset, maximum: 400))

        offset = 400
        #expect(!pan.allows(back: false))
        offset = 0
        #expect(!pan.allows(back: true))
        #expect(!pan.canTrack)

        let nextGesture = HistorySwipePolicy(canGoBack: true, canGoForward: true, surface: .board(offset: offset, maximum: 400))
        #expect(nextGesture.allowsBack)
        #expect(!nextGesture.allowsForward)
    }

    @Test("An edge swipe keeps its original direction permissions while the viewport moves")
    func edgeGestureDoesNotSwapDirections() {
        let beganAtLeft = HistorySwipePolicy(canGoBack: true, canGoForward: true, surface: .board(offset: 0, maximum: 400))
        let nextGestureAtRight = HistorySwipePolicy(canGoBack: true, canGoForward: true, surface: .board(offset: 400, maximum: 400))

        #expect(beganAtLeft.allows(back: true))
        #expect(!beganAtLeft.allows(back: false))
        #expect(!nextGestureAtRight.allows(back: true))
        #expect(nextGestureAtRight.allows(back: false))
    }

    @Test("Modified wheel gestures remain available for zoom and native scrolling", arguments: [
        NSEvent.ModifierFlags.command, .shift, .option, .control, [.command, .shift],
    ], [false, true])
    func modifiedWheelDoesNotNavigate(modifiers: NSEvent.ModifierFlags, boardEdge: Bool) {
        let surface: HistorySwipePolicy.Surface = boardEdge ? .board(offset: 0, maximum: 400) : .page
        let policy = HistorySwipePolicy(canGoBack: true, canGoForward: true, surface: surface, modifiers: modifiers)

        #expect(!policy.canTrack)
        #expect(!policy.allowsBack)
        #expect(!policy.allowsForward)
    }

    @Test("A popover or another window handles its own gestures")
    func anotherWindowDoesNotNavigateTheMainPage() {
        let policy = HistorySwipePolicy(canGoBack: true, canGoForward: true, surface: .page, inMainWindow: false)

        #expect(!policy.canTrack)
        #expect(!policy.allowsBack)
        #expect(!policy.allowsForward)
    }

    @Test("Dragging an issue cannot also start history navigation")
    func draggingDoesNotNavigate() {
        let policy = HistorySwipePolicy(canGoBack: true, canGoForward: true, surface: .page, isDragging: true)

        #expect(!policy.canTrack)
        #expect(!policy.allowsBack)
        #expect(!policy.allowsForward)
    }

    @Test("Letting go only commits a swipe once its arrow reaches the threshold", arguments: [0.49, 0.5, 0.9, -0.49, -0.5, -0.9])
    func releaseRequiresEnoughProgress(progress: Double) {
        #expect(HistorySwipePolicy.commits(progress: progress, phase: .ended) == (abs(progress) >= 0.5))
    }

    @Test("Cancelling a swipe never navigates, even after crossing the threshold", arguments: [0.5, 0.9, -0.5, -0.9])
    func cancelledSwipeDoesNotCommit(progress: Double) {
        #expect(!HistorySwipePolicy.commits(progress: progress, phase: .cancelled))
    }

    @Test("Progress updates and momentum do not commit navigation before the fingers lift", arguments: [NSEvent.Phase(), .began, .changed, .stationary, .mayBegin])
    func nonterminalPhaseDoesNotCommit(phase: NSEvent.Phase) {
        #expect(!HistorySwipePolicy.commits(progress: 1, phase: phase))
    }
}
#endif
