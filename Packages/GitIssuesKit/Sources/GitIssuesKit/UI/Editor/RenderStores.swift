#if os(macOS)
import AppKit
#else
import UIKit
#endif
import BeautifulMermaid
import ImageIO
import SwiftMath

/// Pictures in Markdown, which on GitHub are on the web: downloaded once, kept for the session, and decoded in the
/// background at the size they are shown. Until a picture is there it takes a placeholder's room.
@MainActor
final class ImageStore {
    static let shared = ImageStore()

    private enum State {
        case loading([() -> Void])
        case loaded(data: Data, size: CGSize)
        case failed
    }

    private struct Key: Hashable {
        var url: URL
        var width: Int
    }

    private var states: [URL: State] = [:]
    private var images: [Key: NSImage] = [:]
    private var decoding: Set<Key> = []
    /// Pictures still on their way, or still being decoded.
    var isBusy: Bool {
        !decoding.isEmpty || states.values.contains { if case .loading = $0 { true } else { false } }
    }

    /// The picture's size in points, upright, once it has arrived; nil while it is on its way (`ready` is called when
    /// it is there) or when it couldn't be loaded.
    func size(of url: URL, ready: @escaping () -> Void) -> CGSize? {
        switch states[url] {
        case .loaded(_, let size):
            return size
        case .failed:
            return nil
        case .loading(var waiting):
            waiting.append(ready)
            states[url] = .loading(waiting)
            return nil
        case nil:
            states[url] = .loading([ready])
            load(url)
            return nil
        }
    }

    /// The picture's size if it has arrived, without asking for it.
    func knownSize(of url: URL) -> CGSize? {
        if case .loaded(_, let size) = states[url] { size } else { nil }
    }

    /// Whether the picture couldn't be loaded, so its placeholder says so.
    func hasFailed(_ url: URL) -> Bool {
        if case .failed = states[url] { true } else { false }
    }

    private func load(_ url: URL) {
        Task {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            let data = try? await URLSession.shared.data(for: request).0
            let size = data.flatMap { Self.pictureSize(of: $0) }
            guard case .loading(let waiting) = states[url] else { return }
            if let data, let size {
                states[url] = .loaded(data: data, size: size)
            } else {
                states[url] = .failed
            }
            waiting.forEach { $0() }
        }
    }

    nonisolated private static func pictureSize(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat, width > 0, height > 0 else { return nil }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let dpi = properties[kCGImagePropertyDPIWidth] as? CGFloat ?? 72
        // Screenshots from a Retina screen say so; most pictures on GitHub don't, and are shown a pixel a point.
        let scale = dpi >= 144 ? 2.0 : 1.0
        var size = CGSize(width: width / scale, height: height / scale)
        if orientation >= 5 { size = CGSize(width: size.height, height: size.width) }
        return size
    }

    /// The picture drawn `width` points wide, if it has been decoded; otherwise it starts decoding and calls `ready`.
    func image(for url: URL, width: CGFloat, ready: @escaping () -> Void) -> NSImage? {
        guard case .loaded(let data, _) = states[url] else { return nil }
        let scale = Screen.scale
        let pixels = Int((width * scale / 64).rounded(.up) * 64)
        let key = Key(url: url, width: pixels)
        if let image = images[key] { return image }
        // A decoded picture of another size does until this one is ready.
        let fallback = images.first { $0.key.url == url }?.value
        guard !decoding.contains(key) else { return fallback }
        decoding.insert(key)
        Task.detached(priority: .userInitiated) {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels,
            ]
            var cgImage: CGImage?
            if let source = CGImageSourceCreateWithData(data as CFData, nil) {
                cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            }
            let decoded = cgImage
            await MainActor.run {
                self.decoding.remove(key)
                if let decoded {
                    if self.images.count > 120 { self.images.removeAll() }
                    self.images[key] = NSImage.make(decoded, scale: scale)
                    ready()
                }
            }
        }
        return fallback
    }
}

/// LaTeX drawn with SwiftMath, as GitHub draws `$…$` and `$$…$$`.
@MainActor
enum MathStore {
    struct Rendered {
        var image: NSImage
        var ascent: CGFloat
        var descent: CGFloat
    }

    private static var cache: [String: Rendered?] = [:]

    static func render(_ tex: String, display: Bool, size: CGFloat, color: NSColor) -> Rendered? {
        #if os(macOS)
        let resolved = color.usingColorSpace(.sRGB) ?? color
        #else
        let resolved = color
        #endif
        let rgba = resolved.rgba
        let key = "\(display)|\(size)|\(rgba.red),\(rgba.green),\(rgba.blue)|\(tex)"
        if let cached = cache[key] { return cached }
        var math = MathImage(latex: tex, fontSize: size, textColor: resolved, labelMode: display ? .display : .text, textAlignment: .left)
        let (error, image, info) = math.asImage()
        let rendered: Rendered? = if error == nil, let image, image.size.width > 0 {
            Rendered(image: image, ascent: info?.ascent ?? image.size.height, descent: info?.descent ?? 0)
        } else {
            nil
        }
        if cache.count > 300 { cache.removeAll() }
        cache[key] = rendered
        return rendered
    }
}

/// Mermaid diagrams drawn natively, in the app's colours.
@MainActor
enum DiagramStore {
    private struct Key: Hashable {
        var source: String
        var isDark: Bool
        var scale: CGFloat
    }

    private static var cache: [Key: NSImage?] = [:]
    private static var pending: [Key: [() -> Void]] = [:]
    /// Diagrams still being drawn.
    static var isBusy: Bool { !pending.isEmpty }

    /// What is known of a diagram without drawing it: nil while it hasn't been drawn, `.some(nil)` when it can't be.
    static func cached(_ source: String, isDark: Bool) -> NSImage?? {
        cache[Key(source: source, isDark: isDark, scale: Screen.scale)]
    }

    /// The diagram, if it is drawn; otherwise nil, and `ready` is called once it is. A diagram that can't be drawn
    /// gives `.some(nil)`.
    static func diagram(_ source: String, isDark: Bool, ready: @escaping () -> Void) -> NSImage?? {
        let scale = Screen.scale
        let key = Key(source: source, isDark: isDark, scale: scale)
        if let cached = cache[key] { return .some(cached) }
        if var waiting = pending[key] {
            waiting.append(ready)
            pending[key] = waiting
            return nil
        }
        pending[key] = [ready]
        let theme = DiagramTheme(
            background: EditorTheme.panel.resolvedColor(dark: isDark),
            foreground: EditorTheme.textBody.resolvedColor(dark: isDark),
            line: EditorTheme.textTertiary.resolvedColor(dark: isDark),
            accent: EditorTheme.accent.resolvedColor(dark: isDark),
            surface: EditorTheme.card.resolvedColor(dark: isDark),
            border: NSColor(Theme.cardHoverBorder).resolvedColor(dark: isDark),
            font: .systemFont(ofSize: (EditorStyle.bodySize - 1).rounded()),
            transparent: true
        )
        Task.detached(priority: .userInitiated) {
            var result: NSImage?
            if let image = try? MermaidRenderer.renderImage(source: source, theme: theme, scale: scale),
               let cgImage = image.pixels,
               let trimmed = trimmed(cgImage) {
                result = NSImage.make(trimmed, scale: scale)
            }
            let drawn = result
            await MainActor.run {
                let waiting = pending.removeValue(forKey: key) ?? []
                if cache.count > 64 { cache.removeAll() }
                cache[key] = drawn
                waiting.forEach { $0() }
            }
        }
        return nil
    }

    /// Turned the right way up (BeautifulMermaid 1.0.4 draws Mac images from the bottom; its UIKit ones are upright)
    /// and without the empty margin around the diagram.
    nonisolated private static func trimmed(_ image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let data = context.data else { return nil }
        #if os(macOS)
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        #endif
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = y * width * 4
            for x in 0..<width where pixels[row + x * 4 + 3] > 0 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return context.makeImage()?.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
    }
}
