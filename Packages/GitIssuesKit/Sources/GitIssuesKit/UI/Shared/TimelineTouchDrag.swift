#if os(iOS)
import SwiftUI
import UIKit

/// Hold a bar before moving its dates, so ordinary swipes scroll even when they start on a bar.
struct TimelineTouchDrag: UIGestureRecognizerRepresentable {
    var space: Namespace.ID
    var changed: (CGPoint, CGFloat) -> Void
    /// True when UIKit cancels or rejects the drag; false when the finger is released normally.
    var ended: (_ cancelled: Bool) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = 0.3
        recognizer.allowableMovement = 8
        recognizer.numberOfTouchesRequired = 1
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        let point = context.converter.location(in: .named(space))
        switch recognizer.state {
        case .began:
            context.coordinator.start = point
            changed(point, 0)
        case .changed:
            if let start = context.coordinator.start { changed(start, point.x - start.x) }
        case .ended:
            if let start = context.coordinator.start { changed(start, point.x - start.x) }
            context.coordinator.start = nil
            ended(false)
        case .cancelled, .failed:
            context.coordinator.start = nil
            ended(true)
        default:
            break
        }
    }

    final class Coordinator {
        var start: CGPoint?
    }
}
#endif
