#if os(macOS)
import CoreGraphics
import Testing
@testable import GitIssuesKit

@Suite("A deep press on the trackpad: once per press, and only with the pointer at rest")
struct DeepPressTests {
    private let point = CGPoint(x: 100, y: 100)

    private func pressed(counts: Bool = true) -> DeepPress {
        var press = DeepPress()
        press.begin(at: point, counts: counts)
        return press
    }

    @Test func onlyTheStepIntoTheSecondStageCounts() {
        var press = pressed()
        let result1 = press.update(stage: 1, at: point)
        #expect(!result1)
        let result2 = press.update(stage: 2, at: point)
        #expect(result2)
        let result3 = press.update(stage: 2, at: point)
        #expect(!result3)
    }

    @Test func aHeavyFingerMayMoveALittleButADragIsNoDeepPress() {
        var still = pressed()
        let result4 = still.update(stage: 2, at: CGPoint(x: 103, y: 101))
        #expect(result4)

        var dragged = pressed()
        let result5 = dragged.update(stage: 1, at: CGPoint(x: 120, y: 100))
        #expect(!result5)
        // Coming back doesn't bring it back: this press has become a drag.
        let result6 = dragged.update(stage: 2, at: point)
        #expect(!result6)
    }

    @Test func aPressThatCannotPeekOrHasEndedDoesNothing() {
        var other = pressed(counts: false)
        let result7 = other.update(stage: 2, at: point)
        #expect(!result7)

        var ended = pressed()
        ended.end()
        let result8 = ended.update(stage: 2, at: point)
        #expect(!result8)
    }

    @Test func theReleaseAfterAPeekIsNoClickUntilTheNextPress() {
        var press = pressed()
        let result9 = press.update(stage: 2, at: point)
        #expect(result9)
        press.didOpenPeek()
        press.end()
        #expect(press.openedPeek)
        press.begin(at: point, counts: true)
        #expect(!press.openedPeek)
    }
}
#endif
