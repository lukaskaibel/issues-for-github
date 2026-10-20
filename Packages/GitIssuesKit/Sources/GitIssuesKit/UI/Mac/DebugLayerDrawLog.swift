#if os(macOS)
#if DEBUG
import AppKit
import ObjectiveC
import QuartzCore

/// Which layers drew their contents, for the step-by-step series of `boardsweep` and `menusweep`: each text SwiftUI
/// draws (a `CGDrawingLayer`) and each Canvas or shape RenderBox draws (an `RBLayer`), with its size, where it is in the
/// window and how long it took; "+" marks a layer not seen drawing before. A drawn layer that shows nothing new is a step
/// spent for nothing, and on screen it also waits for the window server to let go of the layer's last picture.
///
/// From the first sweep on, both classes' drawing methods are replaced with ones that call the original and, while a
/// sweep runs, note the layer. They are SwiftUI's own classes: a later macOS may name them differently, and the log
/// then stays empty.
@MainActor
enum LayerDrawLog {
    /// Whether drawn layers are noted, while a sweep runs.
    nonisolated(unsafe) static var recording = false
    nonisolated(unsafe) private static var entries: [String] = []
    nonisolated(unsafe) private static var seen: Set<ObjectIdentifier> = []
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        for name in classNames(where: { $0.hasSuffix("CGDrawingLayer") || $0 == "RBLayer" }) {
            guard let cls = objc_lookUpClass(name) else { continue }
            let rb = name == "RBLayer"
            let selector = NSSelectorFromString(rb ? "display" : "drawInContext:")
            // Only a class's own method: replacing one it inherits would note every layer of its superclass.
            guard let method = ownMethod(selector, of: cls) else { continue }
            let original = method_getImplementation(method)
            if rb {
                typealias Display = @convention(c) (AnyObject, Selector) -> Void
                let display = unsafeBitCast(original, to: Display.self)
                let block: @convention(block) (CALayer) -> Void = { layer in
                    let began = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
                    display(layer, selector)
                    note("RB", layer, since: began)
                }
                method_setImplementation(method, imp_implementationWithBlock(block))
            } else {
                typealias Draw = @convention(c) (AnyObject, Selector, CGContext) -> Void
                let draw = unsafeBitCast(original, to: Draw.self)
                let block: @convention(block) (CALayer, CGContext) -> Void = { layer, context in
                    let began = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
                    draw(layer, selector, context)
                    note("CG", layer, since: began)
                }
                method_setImplementation(method, imp_implementationWithBlock(block))
            }
        }
    }

    /// The layers drawn since the last call, as "CG 104x30@806,416 0.18ms; …".
    static func take() -> String {
        defer { entries = [] }
        return entries.joined(separator: "; ")
    }

    /// Names only: asking the runtime for every class itself trips over classes that aren't NSObjects.
    private static func classNames(where matches: (String) -> Bool) -> [String] {
        var names: [String] = []
        var imageCount: UInt32 = 0
        let images = objc_copyImageNames(&imageCount)
        defer { free(images) }
        for image in 0..<Int(imageCount) {
            var count: UInt32 = 0
            guard let list = objc_copyClassNamesForImage(images[image], &count) else { continue }
            defer { free(list) }
            names += (0..<Int(count)).map { String(cString: list[$0]) }.filter(matches)
        }
        return names
    }

    private static func ownMethod(_ selector: Selector, of cls: AnyClass) -> Method? {
        var count: UInt32 = 0
        guard let methods = class_copyMethodList(cls, &count) else { return nil }
        defer { free(methods) }
        return (0..<Int(count)).map { methods[$0] }.first { method_getName($0) == selector }
    }

    nonisolated private static func note(_ kind: String, _ layer: CALayer, since began: UInt64) {
        guard recording else { return }
        let milliseconds = Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - began) / 1e6
        var root = layer
        while let parent = root.superlayer { root = parent }
        let frame = layer.convert(layer.bounds, to: root)
        let new = seen.insert(ObjectIdentifier(layer)).inserted
        entries.append(String(format: "%@%@ %.0fx%.0f@%.0f,%.0f %.2fms", kind, new ? "+" : "", frame.width, frame.height,
                              frame.minX, frame.minY, milliseconds))
    }
}
#endif
#endif
