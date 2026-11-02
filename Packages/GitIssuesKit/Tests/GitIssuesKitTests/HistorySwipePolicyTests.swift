#if os(macOS)
import AppKit
import Testing
@testable import GitIssuesKit

@Suite("Horizontal scrolling and history swipes")
struct HistorySwipePolicyTests {
    @Test("A timeline edge only offers directions present in its history", arguments: [false, true], [false, true])
    func timelineUsesAvailableHistory(canGoBack: Bool, canGoForward: Bool) {
        let policy = HistorySwipePolicy(canGoBack: canGoBack, canGoForward: canGoForward, surface: .timeline(offset: 0, maximum: 0))

        #expect(policy.allowsBack == canGoBack)
        #expect(policy.allowsForward == canGoForward)
        #expect(policy.canTrack == (canGoBack || canGoForward))
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

    @Test("Boards and timelines scroll internally; only an outward swipe at an edge can navigate", arguments: [CGFloat(0), CGFloat(200), CGFloat(400)], [false, true])
    func scrollableKeepsItsEdgeBehavior(offset: CGFloat, timeline: Bool) {
        let surface: HistorySwipePolicy.Surface = timeline ? .timeline(offset: offset, maximum: 400) : .board(offset: offset, maximum: 400)
        let policy = HistorySwipePolicy(canGoBack: true, canGoForward: true, surface: surface)

        #expect(policy.allowsBack == (offset == 0))
        #expect(policy.allowsForward == (offset == 400))
        #expect(policy.canTrack == (offset != 200))
    }

    @Test("A board or timeline that fits in the viewport retains both available history directions", arguments: [false, true])
    func scrollableWithoutOverflowIsAtBothEdges(timeline: Bool) {
        let surface: HistorySwipePolicy.Surface = timeline ? .timeline(offset: 0, maximum: 0) : .board(offset: 0, maximum: 0)
        let policy = HistorySwipePolicy(canGoBack: true, canGoForward: true, surface: surface)

        #expect(policy.allowsBack)
        #expect(policy.allowsForward)
    }

    @Test("A pan that starts between scroll edges cannot become navigation as it reaches an edge or reverses", arguments: [false, true])
    func gestureKeepsItsInitialPolicy(timeline: Bool) {
        var offset: CGFloat = 200
        func policy() -> HistorySwipePolicy {
            let surface: HistorySwipePolicy.Surface = timeline ? .timeline(offset: offset, maximum: 400) : .board(offset: offset, maximum: 400)
            return HistorySwipePolicy(canGoBack: true, canGoForward: true, surface: surface)
        }
        let pan = policy()

        offset = 400
        #expect(!pan.allows(back: false))
        offset = 0
        #expect(!pan.allows(back: true))
        #expect(!pan.canTrack)

        let nextGesture = policy()
        #expect(nextGesture.allowsBack)
        #expect(!nextGesture.allowsForward)
    }

    @Test("An edge swipe keeps its original direction permissions while the viewport moves", arguments: [false, true])
    func edgeGestureDoesNotSwapDirections(timeline: Bool) {
        let left: HistorySwipePolicy.Surface = timeline ? .timeline(offset: 0, maximum: 400) : .board(offset: 0, maximum: 400)
        let right: HistorySwipePolicy.Surface = timeline ? .timeline(offset: 400, maximum: 400) : .board(offset: 400, maximum: 400)
        let beganAtLeft = HistorySwipePolicy(canGoBack: true, canGoForward: true, surface: left)
        let nextGestureAtRight = HistorySwipePolicy(canGoBack: true, canGoForward: true, surface: right)

        #expect(beganAtLeft.allows(back: true))
        #expect(!beganAtLeft.allows(back: false))
        #expect(!nextGestureAtRight.allows(back: true))
        #expect(nextGestureAtRight.allows(back: false))
    }

    @Test("Modified wheel gestures remain available for zoom and native scrolling", arguments: [
        NSEvent.ModifierFlags.command, .shift, .option, .control, [.command, .shift],
    ], [HistorySwipePolicy.Surface.page, .board(offset: 0, maximum: 400), .timeline(offset: 0, maximum: 400)])
    func modifiedWheelDoesNotNavigate(modifiers: NSEvent.ModifierFlags, surface: HistorySwipePolicy.Surface) {
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

    @Test("A full arrow commits at lift even when AppKit rejects a slow swipe", arguments: [0.49, 0.5, 0.9, -0.49, -0.5, -0.9], [NSEvent.Phase.ended, .cancelled])
    func releaseRequiresEnoughProgress(progress: Double, phase: NSEvent.Phase) {
        #expect(HistorySwipePolicy.commits(progress: progress, phase: phase) == (abs(progress) >= 0.5))
    }

    @Test("Progress updates and momentum do not commit navigation before the fingers lift", arguments: [NSEvent.Phase(), .began, .changed, .stationary, .mayBegin])
    func nonterminalPhaseDoesNotCommit(phase: NSEvent.Phase) {
        #expect(!HistorySwipePolicy.commits(progress: 1, phase: phase))
    }
}
#endif
