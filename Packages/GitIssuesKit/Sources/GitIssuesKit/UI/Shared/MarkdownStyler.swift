import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Styles Markdown text in place without changing a character. Every line of body text is exactly as tall as any
/// other, whatever it holds (bold, code, an emoji or nothing at all), so lines never move while you type; only a
/// heading is taller.
@MainActor
enum MarkdownStyler {
    #if os(macOS)
    static var fontSize: CGFloat { 14 }
    #else
    /// Follows the reader's text size, from 16 pt at the default size.
    static var fontSize: CGFloat { UIFontMetrics(forTextStyle: .body).scaledValue(for: 16) }
    #endif
    /// Everything else is sized relative to the body text.
    static var scale: CGFloat { fontSize / 14 }
    static var lineHeight: CGFloat { (22 * scale).rounded() }

    static var font: PlatformFont { PlatformFont.systemFont(ofSize: fontSize) }

    static var paragraphStyle: NSParagraphStyle { paragraphStyle(for: font) }

    /// Lines exactly as tall as a line of `font`, whatever else is in them.
    static func paragraphStyle(for font: PlatformFont) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        #if os(macOS)
        let height = ceil(measurer.defaultLineHeight(for: font))
        #else
        let height = ceil(font.lineHeight)
        #endif
        style.minimumLineHeight = height
        style.maximumLineHeight = height
        style.lineSpacing = 4 * scale
        style.paragraphSpacing = 4 * scale
        return style
    }

    #if os(macOS)
    private static let measurer = NSLayoutManager()
    #endif

    static var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: PlatformColor(Theme.textBody),
            .paragraphStyle: paragraphStyle,
        ]
    }

    /// The colour the Markdown punctuation fades back to.
    static var mutedColor: PlatformColor { PlatformColor(Theme.textTertiary) }

    static func headingFont(level: Int) -> PlatformFont {
        let size: CGFloat = [20, 17, 15.5, 14.5, 14, 14][min(max(level, 1), 6) - 1] * scale
        return PlatformFont.systemFont(ofSize: size, weight: .semibold)
    }

    private static var mono: PlatformFont { PlatformFont.monospacedSystemFont(ofSize: fontSize - 1.5 * scale, weight: .regular) }

    static func style(_ storage: NSTextStorage?, insideEdit: Bool = false) {
        guard let storage else { return }
        let mono = self.mono
        let string = storage.string
        let text = string as NSString
        let all = NSRange(location: 0, length: text.length)
        let muted = mutedColor
        let strong = PlatformColor(Theme.text)
        let accent = PlatformColor(Theme.accent)

        if !insideEdit { storage.beginEditing() }
        defer { if !insideEdit { storage.endEditing() } }
        storage.setAttributes(baseAttributes, range: all)

        func each(_ expression: NSRegularExpression, _ body: (NSTextCheckingResult) -> Void) {
            expression.enumerateMatches(in: string, range: all) { match, _, _ in
                if let match { body(match) }
            }
        }
        func font(_ range: NSRange, _ transform: (PlatformFont) -> PlatformFont) {
            storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
                let current = (value as? PlatformFont) ?? self.font
                storage.addAttribute(.font, value: transform(current), range: subrange)
            }
        }

        each(MarkdownSyntax.heading) { match in
            let font = headingFont(level: match.range(at: 1).length)
            storage.addAttribute(.font, value: font, range: match.range)
            storage.addAttribute(.paragraphStyle, value: paragraphStyle(for: font), range: match.range)
            storage.addAttribute(.foregroundColor, value: strong, range: match.range(at: 2))
            storage.addAttribute(.foregroundColor, value: muted, range: match.range(at: 1))
        }
        each(MarkdownSyntax.quote) { match in
            storage.addAttribute(.foregroundColor, value: PlatformColor(Theme.textSecondary), range: match.range(at: 2))
            storage.addAttribute(.foregroundColor, value: muted, range: match.range(at: 1))
        }
        each(MarkdownSyntax.listMarker) { match in
            storage.addAttribute(.foregroundColor, value: muted, range: match.range)
        }
        each(MarkdownSyntax.rule) { match in
            storage.addAttribute(.foregroundColor, value: muted, range: match.range)
        }
        for span in MarkdownSyntax.spans(in: text, all, fences: MarkdownSyntax.fences(in: text)) {
            switch span.style {
            case .bold:
                font(span.content) { $0.withWeight(.semibold) }
                storage.addAttribute(.foregroundColor, value: strong, range: span.content)
            case .italic:
                font(span.content) { $0.italicized() }
            case .strikethrough:
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: span.content)
            case .code:
                // Below, last: nothing inside it is Markdown.
                continue
            }
            storage.addAttribute(.foregroundColor, value: muted, range: span.opening)
            storage.addAttribute(.foregroundColor, value: muted, range: span.closing)
        }
        each(MarkdownSyntax.html) { match in
            storage.addAttribute(.foregroundColor, value: muted, range: match.range)
        }
        each(MarkdownSyntax.url) { match in
            let target = text.substring(with: match.range)
            if let target = URL(string: target) { storage.addAttribute(.link, value: target, range: match.range) }
        }
        each(MarkdownSyntax.link) { match in
            storage.addAttribute(.foregroundColor, value: muted, range: match.range)
            let isImage = match.range(at: 1).length > 0
            guard !isImage else { return }
            let target = text.substring(with: match.range(at: 3))
            storage.addAttribute(.foregroundColor, value: accent, range: match.range(at: 2))
            if let target = URL(string: target) { storage.addAttribute(.link, value: target, range: match.range(at: 2)) }
            storage.removeAttribute(.link, range: match.range(at: 3))
        }
        // Code last: nothing inside it is Markdown.
        each(MarkdownSyntax.inlineCode) { match in
            clearMarkdown(storage, match.range)
            storage.addAttribute(.font, value: mono, range: match.range)
            storage.addAttribute(.backgroundColor, value: PlatformColor(Theme.control), range: match.range)
        }
        each(MarkdownSyntax.fence) { match in
            clearMarkdown(storage, match.range)
            storage.addAttribute(.font, value: mono, range: match.range)
            let block = text.substring(with: match.range) as NSString
            // The ``` lines fade back; the code itself stays readable.
            let firstLine = block.lineRange(for: NSRange(location: 0, length: 0))
            storage.addAttribute(.foregroundColor, value: muted, range: NSRange(location: match.range.location, length: firstLine.length))
            let lastLine = block.lineRange(for: NSRange(location: max(block.length - 1, 0), length: 0))
            if lastLine.location > 0, block.substring(with: lastLine).hasPrefix("```") {
                storage.addAttribute(.foregroundColor, value: muted, range: NSRange(location: match.range.location + lastLine.location, length: lastLine.length))
            }
        }
    }

    private static func clearMarkdown(_ storage: NSTextStorage, _ range: NSRange) {
        storage.setAttributes(baseAttributes, range: range)
    }
}
