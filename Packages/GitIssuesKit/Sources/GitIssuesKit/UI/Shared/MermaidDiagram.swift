import BeautifulMermaid
import SwiftUI

/// A Mermaid diagram from a ```` ```mermaid ```` block, drawn natively in the app's colours. One it can't read,
/// or of a kind it doesn't draw, shows as the code it is.
struct MermaidDiagram<Fallback: View>: View {
    var source: String
    @ViewBuilder var fallback: () -> Fallback
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @State private var drawing: DiagramDrawing?

    var body: some View {
        let key = DiagramDrawing.Key(source: source, isDark: colorScheme == .dark, fontSize: MarkdownStyler.fontSize - 1, scale: displayScale)
        let current = drawing?.key == key ? drawing : DiagramDrawing.cache[key]
        Group {
            if let current {
                if let image = current.image {
                    // At the size of the text around it; a diagram wider than the column scrolls, as code does.
                    ScrollView(.horizontal) {
                        Image(image, scale: key.scale, label: Text(.diagram))
                    }
                    .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                } else {
                    fallback()
                }
            } else {
                Color.clear.frame(height: 80)
            }
        }
        .task(id: key) {
            guard current == nil else { return }
            drawing = await DiagramDrawing.draw(key)
        }
    }
}

struct DiagramDrawing: Sendable {
    struct Key: Hashable, Sendable {
        var source: String
        var isDark: Bool
        var fontSize: CGFloat
        var scale: CGFloat
    }

    var key: Key
    /// Nil when the diagram couldn't be drawn.
    var image: CGImage?

    /// Drawn diagrams, so scrolling back or switching issues doesn't draw them again.
    @MainActor static var cache: [Key: DiagramDrawing] = [:]

    @MainActor
    static func draw(_ key: Key) async -> DiagramDrawing {
        let colors = Colors(isDark: key.isDark)
        let drawing = await Task.detached(priority: .userInitiated) {
            DiagramDrawing(key: key, image: render(key, colors))
        }.value
        if cache.count > 64 { cache.removeAll() }
        cache[key] = drawing
        return drawing
    }

    /// The app's colours for one appearance, worked out on the main thread.
    private struct Colors: @unchecked Sendable {
        var background, foreground, line, accent, surface, border: CGColor

        @MainActor
        init(isDark: Bool) {
            func resolve(_ color: Color) -> CGColor { PlatformColor(color).resolved(dark: isDark) }
            background = resolve(Theme.panel)
            foreground = resolve(Theme.textBody)
            line = resolve(Theme.textTertiary)
            accent = resolve(Theme.accent)
            surface = resolve(Theme.card)
            border = resolve(Theme.cardHoverBorder)
        }
    }

    private static func render(_ key: Key, _ colors: Colors) -> CGImage? {
        func color(_ cgColor: CGColor) -> PlatformColor {
            #if os(macOS)
            NSColor(cgColor: cgColor) ?? .textColor
            #else
            UIColor(cgColor: cgColor)
            #endif
        }
        let theme = DiagramTheme(
            background: color(colors.background),
            foreground: color(colors.foreground),
            line: color(colors.line),
            accent: color(colors.accent),
            surface: color(colors.surface),
            border: color(colors.border),
            font: .systemFont(ofSize: key.fontSize),
            transparent: true
        )
        guard let image = try? MermaidRenderer.renderImage(source: key.source, theme: theme, scale: key.scale) else { return nil }
        #if os(macOS)
        // BeautifulMermaid 1.0.4 lays diagrams out top down but draws its Mac images into a bitmap that counts
        // from the bottom, so they come out upside down.
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil).flatMap { trimmed($0, flipped: true) }
        #else
        return image.cgImage.flatMap { trimmed($0, flipped: false) }
        #endif
    }

    /// The image without the empty margin around the diagram, so it lines up with the text.
    private static func trimmed(_ image: CGImage, flipped: Bool) -> CGImage? {
        let width = image.width, height = image.height
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let data = context.data else { return nil }
        if flipped {
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // Rows in memory run from the top, as the crop rectangle counts them.
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
