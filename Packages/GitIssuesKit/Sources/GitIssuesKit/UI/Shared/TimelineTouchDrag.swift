#if os(iOS)
import SwiftUI
import UIKit

/// A bar accepts a horizontal drag while a vertical swipe continues to scroll the timeline's rows.
struct TimelineTouchDrag: UIGestureRecognizerRepresentable {
    var space: Namespace.ID
    var changed: (CGPoint, CGFloat) -> Void
    /// True when UIKit cancels or rejects the drag; false when the finger is released normally.
    var ended: (_ cancelled: Bool) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.minimumNumberOfTouches = 1
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let translation = context.converter.translation(in: .named(space)) ?? .zero
        switch recognizer.state {
        case .began:
            let point = context.converter.location(in: .named(space))
            let start = CGPoint(x: point.x - translation.x, y: point.y - translation.y)
            context.coordinator.start = start
            changed(start, translation.x)
        case .changed:
            if let start = context.coordinator.start { changed(start, translation.x) }
        case .ended:
            if let start = context.coordinator.start { changed(start, translation.x) }
            context.coordinator.start = nil
            ended(false)
        case .cancelled, .failed:
            context.coordinator.start = nil
            ended(true)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var start: CGPoint?

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }
    }
}
#endif
