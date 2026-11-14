import CoreGraphics
import Foundation

/// Whether a card held over another issue lights that issue up to go under it. Not as it passes over the issue on its
/// way somewhere else: only once the pointer, or the finger, has rested in the middle of the issue for a moment, or
/// moved there slowly, as a folder in the Finder springs open only for a file held over it. Until then the card goes in
/// front of the issue or after it, as it would anywhere else. The Mac's board and the iPhone's and iPad's go by it.
struct NestDwell: Equatable {
    /// How long the pointer stays in the middle of an issue before the issue lights up.
    static let delay: TimeInterval = 0.2
    /// How far the pointer may move while it waits. Further, and the wait starts again from there: going over an issue
    /// faster than about 75 points a second never lights it up.
    static let wander: CGFloat = 15

    /// The issue (an id) the pointer waits over.
    private(set) var candidate: String?
    /// Where the pointer was when the wait started, and when.
    private var anchor = CGPoint.zero
    private var since: TimeInterval = 0
    /// The issue lit up, which stays lit while the pointer stays in its middle, however it moves there.
    private(set) var lit: String?

    /// Takes where the pointer is (`point`, at `time` in seconds) and the issue whose middle it is in, if that issue can
    /// take the lifted ones; returns the issue lit up now, if any.
    mutating func update(over id: String?, at point: CGPoint, time: TimeInterval) -> String? {
        guard let id else {
            self = NestDwell()
            return nil
        }
        if lit == id { return id }
        if candidate != id || hypot(point.x - anchor.x, point.y - anchor.y) > Self.wander {
            self = NestDwell(candidate: id, anchor: point, since: time)
            return nil
        }
        guard time >= since + Self.delay else { return nil }
        lit = id
        return id
    }

    /// When to look again, with the pointer resting, for the issue it waits over to light up: a pointer at rest sends
    /// no more moves.
    var due: TimeInterval? {
        candidate != nil && lit == nil ? since + Self.delay : nil
    }
}
