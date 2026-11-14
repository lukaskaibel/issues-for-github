import CoreGraphics
import Foundation
import Testing
@testable import GitIssuesKit

/// A card held over another issue lights it up to go under it only once the pointer rests in its middle, or moves
/// there slowly, for a moment: passing over it on the way somewhere else lights up nothing.
@Suite("Waiting over an issue before it lights up to take a dragged one")
struct NestDwellTests {
    /// One pointer sample: where, when, and the issue whose middle it is in.
    struct Sample {
        var point: CGPoint
        var time: TimeInterval
        var over: String?
    }

    /// What lit up at each sample.
    private func play(_ samples: [Sample], into dwell: inout NestDwell) -> [String?] {
        samples.map { dwell.update(over: $0.over, at: $0.point, time: $0.time) }
    }

    /// The pointer path the debug remote's `drag` command plays and a hand roughly makes: 36 steps at 60 a second,
    /// slow at first, fast in the middle and slowing down to a stop.
    private func easedPath(from start: CGPoint, to end: CGPoint, over: (CGPoint) -> String?) -> [Sample] {
        (0...36).map { step in
            let t = Double(step) / 36
            let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
            let point = CGPoint(x: start.x + (end.x - start.x) * eased, y: start.y + (end.y - start.y) * eased)
            return Sample(point: point, time: Double(step) / 60, over: over(point))
        }
    }

    @Test("Resting over the middle of an issue lights it up after a moment, and not before")
    func resting() {
        var dwell = NestDwell()
        let point = CGPoint(x: 100, y: 200)
        #expect(dwell.update(over: "9", at: point, time: 10) == nil)
        #expect(dwell.due == 10 + NestDwell.delay)
        #expect(dwell.update(over: "9", at: point, time: 10.1) == nil)
        #expect(dwell.update(over: "9", at: point, time: 10.19) == nil)
        #expect(dwell.update(over: "9", at: point, time: 10.21) == "9")
        #expect(dwell.lit == "9")
        // Lit, there is nothing left to wait for.
        #expect(dwell.due == nil)
    }

    @Test("A card passing over an issue at an ordinary pace lights nothing up")
    func passing() {
        // 10 points a frame, 600 a second, through a 40 point high middle.
        var dwell = NestDwell()
        let samples = (0...30).map { frame in
            let y = 100 + CGFloat(frame) * 10
            return Sample(point: CGPoint(x: 150, y: y), time: Double(frame) / 60, over: (180...220).contains(y) ? "16" : nil)
        }
        #expect(play(samples, into: &dwell).allSatisfy { $0 == nil })
    }

    @Test("A drag slowing down to a stop just past an issue lights nothing up on its way")
    func slowingDownPast() {
        // The README's drag: a card rising from one column to a place between two cards in the next. On its way it goes
        // through the middle of the lower card (#16, 300 to 375, its middle 319 to 356) shortly before it stops just
        // under that card's top, slowing down all the while.
        var dwell = NestDwell()
        let samples = easedPath(from: CGPoint(x: 420, y: 700), to: CGPoint(x: 700, y: 306)) { point in
            point.x >= 600 && (319...356).contains(point.y) ? "16" : nil
        }
        #expect(samples.contains { $0.over == "16" })
        #expect(play(samples, into: &dwell).allSatisfy { $0 == nil })
    }

    @Test("A drag slowing down to a stop in the middle of an issue lights it up once it has stopped")
    func stoppingOnIt() throws {
        var dwell = NestDwell()
        let samples = easedPath(from: CGPoint(x: 420, y: 700), to: CGPoint(x: 700, y: 330)) { point in
            point.x >= 600 && (319...356).contains(point.y) ? "16" : nil
        }
        #expect(play(samples, into: &dwell).allSatisfy { $0 == nil })
        // At rest, no more moves come: the board looks again when it is due.
        let due = try #require(dwell.due)
        #expect(due <= samples.last!.time + NestDwell.delay)
        #expect(dwell.update(over: "16", at: samples.last!.point, time: due) == "16")
    }

    @Test("Moving slowly in the middle of an issue lights it up")
    func movingSlowly() {
        // 40 points a second.
        var dwell = NestDwell()
        let samples = (0...20).map { frame in
            Sample(point: CGPoint(x: 150, y: 190 + CGFloat(frame) * 40 / 60), time: Double(frame) / 60, over: "9")
        }
        let lit = play(samples, into: &dwell)
        #expect(lit.prefix(12).allSatisfy { $0 == nil })
        #expect(lit.last == "9")
    }

    @Test("A hand trembling a little while it rests doesn't make it wait again")
    func trembling() {
        var dwell = NestDwell()
        let samples = (0...10).map { (frame: Int) -> Sample in
            let dx: CGFloat = frame % 2 == 0 ? 3 : -3
            let dy: CGFloat = frame % 3 == 0 ? 2 : -2
            return Sample(point: CGPoint(x: 150 + dx, y: 200 + dy), time: Double(frame) / 60, over: "9")
        }
        #expect(play(samples, into: &dwell).allSatisfy { $0 == nil })
        #expect(dwell.update(over: "9", at: CGPoint(x: 152, y: 201), time: 0.21) == "9")
    }

    @Test("Moving on further than a little starts the wait again from there")
    func wandering() {
        var dwell = NestDwell()
        #expect(dwell.update(over: "9", at: CGPoint(x: 100, y: 200), time: 0) == nil)
        #expect(dwell.update(over: "9", at: CGPoint(x: 100, y: 220), time: 0.15) == nil)
        #expect(dwell.update(over: "9", at: CGPoint(x: 100, y: 220), time: 0.25) == nil)
        #expect(dwell.update(over: "9", at: CGPoint(x: 100, y: 220), time: 0.36) == "9")
    }

    @Test("Leaving the middle, or going on to another issue, starts the wait again")
    func leaving() {
        var dwell = NestDwell()
        let point = CGPoint(x: 100, y: 200)
        #expect(dwell.update(over: "9", at: point, time: 0) == nil)
        #expect(dwell.update(over: nil, at: point, time: 0.15) == nil)
        #expect(dwell.due == nil)
        #expect(dwell.update(over: "9", at: point, time: 0.16) == nil)
        #expect(dwell.update(over: "9", at: point, time: 0.3) == nil)
        #expect(dwell.update(over: "16", at: point, time: 0.31) == nil)
        #expect(dwell.update(over: "16", at: point, time: 0.45) == nil)
        #expect(dwell.update(over: "16", at: point, time: 0.52) == "16")
    }

    @Test("Once lit, an issue stays lit while the pointer is in its middle, however it moves there, until it leaves")
    func stayingLit() {
        var dwell = NestDwell()
        #expect(dwell.update(over: "9", at: CGPoint(x: 100, y: 200), time: 0) == nil)
        #expect(dwell.update(over: "9", at: CGPoint(x: 100, y: 200), time: 0.21) == "9")
        #expect(dwell.update(over: "9", at: CGPoint(x: 160, y: 230), time: 0.215) == "9")
        #expect(dwell.update(over: "9", at: CGPoint(x: 40, y: 180), time: 0.22) == "9")
        #expect(dwell.update(over: nil, at: CGPoint(x: 40, y: 150), time: 0.23) == nil)
        #expect(dwell.lit == nil)
        #expect(dwell.update(over: "9", at: CGPoint(x: 40, y: 180), time: 0.24) == nil)
    }
}
