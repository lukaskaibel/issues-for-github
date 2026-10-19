import CoreText
import QuartzCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Restyles the Markdown of an editor as it is typed in, easing from the old look to the new one instead of
/// snapping: bold text thickens, a heading grows, marks fade back, a new list marker fades in. Weight and size
/// change continuously along the system font's variation axes, so the text passes through every weight in between.
@MainActor
final class MarkdownStyleAnimator: NSObject {
    /// How a run of text looks.
    struct Look {
        var font: PlatformFont?
        var color: PlatformColor?

        init(_ attributes: [NSAttributedString.Key: Any]) {
            font = attributes[.font] as? PlatformFont
            color = attributes[.foregroundColor] as? PlatformColor
        }

        init(font: PlatformFont?, color: PlatformColor?) {
            self.font = font
            self.color = color
        }
    }

    private struct Run {
        var range: NSRange
        var from: Look
        var to: Look
    }

    /// The view the text is in, for its appearance and its display's frames.
    weak var view: PlatformView?
    /// Called on every frame, for a view that sizes itself to its text.
    var onFrame: () -> Void = {}

    private weak var storage: NSTextStorage?
    private var runs: [Run] = []
    private var started: CFTimeInterval = 0
    private var displayLink: CADisplayLink?
    private var fallback: Timer?
    /// How the characters an edit by the typing rules keeps looked, by where they are after it.
    private var kept: [(range: NSRange, look: Look)] = []

    static var isEnabled: Bool {
        #if os(macOS)
        !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #else
        !UIAccessibility.isReduceMotionEnabled
        #endif
    }

    /// Before the typing rules replace `range` with `replacement`: remembers how the characters that stay looked,
    /// since the edit as a whole would count as new text.
    func keep(_ storage: NSTextStorage, replacing range: NSRange, with replacement: String) {
        let old = Array((storage.string as NSString).substring(with: range).utf16)
        let new = Array(replacement.utf16)
        kept = Self.matches(old, new).compactMap { pair in
            let look = Look(storage.attributes(at: range.location + pair.old, effectiveRange: nil))
            return (NSRange(location: range.location + pair.new, length: 1), look)
        }
    }

    /// Styles the text right after an edit (from `didProcessEditing`), and starts easing every character whose
    /// look changed from how it looked to how it looks now.
    ///
    /// Not from `willProcessEditing`: what changes there counts as part of the edit, and the Mac's text view puts the
    /// caret at the end of the edit, so styling the text after the caret would throw the caret to its end.
    func restyle(_ storage: NSTextStorage, edited: NSRange) {
        let animates = Self.isEnabled && view?.window != nil
        let before = animates ? looks(in: storage, outside: edited) : []
        stop()
        defer { kept = [] }
        storage.beginEditing()
        MarkdownStyler.style(storage, insideEdit: true)
        // The edit's own fixing (an emoji's font, for one) ran before the styling, which undid it.
        storage.fixAttributes(in: NSRange(location: 0, length: storage.length))
        if animates {
            runs = changes(from: before, in: storage, edited: edited)
            apply(0, to: storage)
        }
        storage.endEditing()
        guard !runs.isEmpty else { return }
        self.storage = storage
        started = CACurrentMediaTime()
        #if os(macOS)
        displayLink = view?.displayLink(target: self, selector: #selector(tick))
        #else
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        #endif
        displayLink?.add(to: .main, forMode: .common)
        // A display link only runs while the view is on screen; the text never stays half way.
        let fallback = Timer(timeInterval: Theme.textStyleDuration + 0.1, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish() }
        }
        RunLoop.main.add(fallback, forMode: .common)
        self.fallback = fallback
    }

    /// Ends the animation where it is; the next styling sets the final look.
    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        fallback?.invalidate()
        fallback = nil
        runs = []
    }

    @objc private func tick() {
        let progress = min(1, (CACurrentMediaTime() - started) / Theme.textStyleDuration)
        guard progress < 1, let storage else { return finish() }
        storage.beginEditing()
        apply(1 - pow(1 - progress, 3), to: storage)
        storage.endEditing()
        onFrame()
    }

    private func finish() {
        guard !runs.isEmpty else { return stop() }
        if let storage {
            storage.beginEditing()
            apply(1, to: storage)
            storage.endEditing()
        }
        stop()
        onFrame()
    }

    // MARK: Looks

    /// How the text looks now, outside the part just typed or replaced, plus what the typing rules kept inside it.
    private func looks(in storage: NSTextStorage, outside edited: NSRange) -> [(range: NSRange, look: Look)] {
        var looks: [(range: NSRange, look: Look)] = []
        let parts = [NSRange(location: 0, length: edited.location),
                     NSRange(location: NSMaxRange(edited), length: storage.length - NSMaxRange(edited))]
        for part in parts where part.length > 0 {
            storage.enumerateAttributes(in: part) { attributes, range, _ in
                looks.append((range, Look(attributes)))
            }
        }
        return looks + kept.filter { NSMaxRange($0.range) <= storage.length }
    }

    /// Where the newly styled text looks different from before. New characters fade in when they are Markdown
    /// marks typed a few at a time; a whole new text just appears.
    private func changes(from before: [(range: NSRange, look: Look)], in storage: NSTextStorage, edited: NSRange) -> [Run] {
        var runs: [Run] = []
        for (range, old) in before {
            storage.enumerateAttributes(in: range) { attributes, subrange, _ in
                let new = Look(attributes)
                if !sameFont(old.font, new.font) || !sameColor(old.color, new.color) {
                    runs.append(Run(range: subrange, from: old, to: new))
                }
            }
        }
        let keptLocations = Set(kept.map(\.range.location))
        guard edited.length > 0, edited.length - keptLocations.count <= 12 else { return runs }
        let muted = MarkdownStyler.mutedColor
        storage.enumerateAttributes(in: edited) { attributes, range, _ in
            let new = Look(attributes)
            guard sameColor(new.color, muted) else { return }
            for location in range.location ..< NSMaxRange(range) where !keptLocations.contains(location) {
                runs.append(Run(range: NSRange(location: location, length: 1), from: Look(font: new.font, color: muted.withAlphaComponent(0)), to: new))
            }
        }
        return runs
    }

    private func apply(_ progress: CGFloat, to storage: NSTextStorage) {
        for run in runs where NSMaxRange(run.range) <= storage.length {
            if progress >= 1 {
                if let font = run.to.font { storage.addAttribute(.font, value: font, range: run.range) }
                if let color = run.to.color { storage.addAttribute(.foregroundColor, value: color, range: run.range) }
                storage.removeAttribute(.obliqueness, range: run.range)
                continue
            }
            if let from = run.from.font, let to = run.to.font {
                let (font, obliqueness) = Self.font(between: from, and: to, at: progress)
                storage.addAttribute(.font, value: font, range: run.range)
                if obliqueness != 0 { storage.addAttribute(.obliqueness, value: obliqueness, range: run.range) }
            }
            if let color = color(between: run.from.color, and: run.to.color, at: progress) {
                storage.addAttribute(.foregroundColor, value: color, range: run.range)
            }
        }
    }

    // MARK: Fonts

    private static let weightAxis = NSNumber(value: 0x7767_6874) // 'wght'
    /// What SF's italics slant by, in the obliqueness an upright font is given while it turns italic.
    private static let italicSlant: CGFloat = 0.2

    private static func weight(of font: PlatformFont) -> CGFloat {
        let variation = CTFontCopyVariation(font) as? [NSNumber: NSNumber]
        return CGFloat(variation?[weightAxis]?.doubleValue ?? 400)
    }

    /// A font between two system fonts: size and weight in between, and italics as a growing slant. Code and
    /// other fonts switch at once.
    private static func font(between from: PlatformFont, and to: PlatformFont, at progress: CGFloat) -> (PlatformFont, CGFloat) {
        guard !from.isMonospaced, !to.isMonospaced else { return (to, 0) }
        let size = from.pointSize + (to.pointSize - from.pointSize) * progress
        let weight = Self.weight(of: from) + (Self.weight(of: to) - Self.weight(of: from)) * progress
        if from.isItalic == to.isItalic {
            return (systemFont(size: size, weight: weight, italic: to.isItalic), 0)
        }
        let slant = to.isItalic ? progress : 1 - progress
        return (systemFont(size: size, weight: weight, italic: false), slant * italicSlant)
    }

    private static func systemFont(size: CGFloat, weight: CGFloat, italic: Bool) -> PlatformFont {
        let base = italic ? PlatformFont.systemFont(ofSize: size).italicized() : PlatformFont.systemFont(ofSize: size)
        // The optical size the system picked for this size stays; only the weight moves.
        var variation = (CTFontCopyVariation(base) as? [NSNumber: NSNumber]) ?? [:]
        variation[weightAxis] = NSNumber(value: Double(weight))
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(base), [kCTFontVariationAttribute: variation] as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil) as PlatformFont
    }

    private func sameFont(_ a: PlatformFont?, _ b: PlatformFont?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return a.pointSize == b.pointSize && a.fontName == b.fontName && Self.weight(of: a) == Self.weight(of: b)
    }

    // MARK: Colours

    private func components(_ color: PlatformColor?) -> [CGFloat]? {
        guard let color else { return nil }
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        #if os(macOS)
        var resolved: NSColor?
        (view?.effectiveAppearance ?? NSApp.effectiveAppearance).performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB)
        }
        guard let resolved else { return nil }
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #else
        let resolved = view.map { color.resolvedColor(with: $0.traitCollection) } ?? color
        guard resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        #endif
        return [red, green, blue, alpha]
    }

    private func sameColor(_ a: PlatformColor?, _ b: PlatformColor?) -> Bool {
        guard let first = components(a), let second = components(b) else { return a == nil && b == nil }
        return zip(first, second).allSatisfy { abs($0 - $1) < 0.004 }
    }

    private func color(between from: PlatformColor?, and to: PlatformColor?, at progress: CGFloat) -> PlatformColor? {
        guard let first = components(from), let second = components(to) else { return to }
        let mixed = zip(first, second).map { $0 + ($1 - $0) * progress }
        return PlatformColor(red: mixed[0], green: mixed[1], blue: mixed[2], alpha: mixed[3])
    }

    // MARK: Matching

    /// The characters two texts share, in order (a longest common subsequence), as pairs of offsets.
    static func matches(_ old: [UInt16], _ new: [UInt16]) -> [(old: Int, new: Int)] {
        // An edit by the typing rules touches a line or two; anything bigger isn't worth the work.
        guard !old.isEmpty, !new.isEmpty, old.count * new.count <= 250_000 else { return [] }
        let width = new.count + 1
        var lengths = [Int32](repeating: 0, count: (old.count + 1) * width)
        for i in stride(from: old.count - 1, through: 0, by: -1) {
            for j in stride(from: new.count - 1, through: 0, by: -1) {
                lengths[i * width + j] = old[i] == new[j]
                    ? lengths[(i + 1) * width + j + 1] + 1
                    : max(lengths[(i + 1) * width + j], lengths[i * width + j + 1])
            }
        }
        var pairs: [(old: Int, new: Int)] = []
        var i = 0
        var j = 0
        while i < old.count, j < new.count {
            if old[i] == new[j] {
                pairs.append((i, j))
                i += 1
                j += 1
            } else if lengths[(i + 1) * width + j] >= lengths[i * width + j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return pairs
    }
}
