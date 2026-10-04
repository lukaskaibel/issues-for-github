import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Styles Markdown text in place without changing a character.
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

    static var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4 * scale
        style.paragraphSpacing = 4 * scale
        return style
    }

    static var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: PlatformFont.systemFont(ofSize: fontSize),
            .foregroundColor: PlatformColor(Theme.textBody),
            .paragraphStyle: paragraphStyle,
        ]
    }

    private static var mono: PlatformFont { PlatformFont.monospacedSystemFont(ofSize: fontSize - 1.5 * scale, weight: .regular) }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // The patterns are fixed and tested, so a failure here is a programming error.
        try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    }

    private static let blankLine = regex(#"^\n"#)
    private static let heading = regex(#"^(#{1,6})[ \t]+(.+)$"#)
    private static let quote = regex(#"^(>[ \t]?)(.*)$"#)
    private static let listMarker = regex(#"^[ \t]*([-*+]|\d+[.)])[ \t]+(\[[ xX]\][ \t]+)?"#)
    private static let rule = regex(#"^[ \t]*([-*_])([ \t]*\1){2,}[ \t]*$"#)
    private static let bold = regex(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    private static let italic = regex(#"(?<![*\w])([*_])(?=[^\s*_])(.+?)(?<=[^\s*_])\1(?![*\w])"#)
    private static let strike = regex(#"~~(?=\S)(.+?)(?<=\S)~~"#)
    private static let link = regex(#"(!?)\[([^\]\n]+)\]\(([^)\s]+)[^)\n]*\)"#)
    private static let url = regex(#"(?<![(<\w])https?://[^\s<>()\]]+"#)
    private static let html = regex(#"</?[a-zA-Z][^>\n]*>"#)
    private static let inlineCode = regex(#"`[^`\n]+`"#)
    private static let fence = regex(#"^```[^\n]*\n[\s\S]*?(?:^```[ \t]*$|\z)"#)

    static func style(_ storage: NSTextStorage?, insideEdit: Bool = false) {
        guard let storage else { return }
        let mono = self.mono
        let string = storage.string
        let all = NSRange(location: 0, length: (string as NSString).length)
        let muted = PlatformColor(Theme.textTertiary)
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
                let current = (value as? PlatformFont) ?? PlatformFont.systemFont(ofSize: fontSize)
                storage.addAttribute(.font, value: transform(current), range: subrange)
            }
        }

        each(blankLine) { match in
            storage.addAttribute(.font, value: PlatformFont.systemFont(ofSize: 7 * scale), range: match.range)
        }
        each(heading) { match in
            let level = match.range(at: 1).length
            let size: CGFloat = [20, 17, 15.5, 14.5, 14, 14][min(level, 6) - 1] * scale
            storage.addAttribute(.font, value: PlatformFont.systemFont(ofSize: size, weight: .semibold), range: match.range)
            storage.addAttribute(.foregroundColor, value: strong, range: match.range(at: 2))
            storage.addAttribute(.foregroundColor, value: muted, range: match.range(at: 1))
        }
        each(quote) { match in
            storage.addAttribute(.foregroundColor, value: PlatformColor(Theme.textSecondary), range: match.range(at: 2))
            storage.addAttribute(.foregroundColor, value: muted, range: match.range(at: 1))
        }
        each(listMarker) { match in
            storage.addAttribute(.foregroundColor, value: muted, range: match.range)
        }
        each(rule) { match in
            storage.addAttribute(.foregroundColor, value: muted, range: match.range)
        }
        each(bold) { match in
            font(match.range(at: 2)) { PlatformFont.systemFont(ofSize: $0.pointSize, weight: .semibold) }
            storage.addAttribute(.foregroundColor, value: strong, range: match.range(at: 2))
            dim(storage, match.range, keeping: match.range(at: 2), color: muted)
        }
        each(italic) { match in
            font(match.range(at: 2)) { $0.italicized() }
            dim(storage, match.range, keeping: match.range(at: 2), color: muted)
        }
        each(strike) { match in
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: match.range(at: 1))
            dim(storage, match.range, keeping: match.range(at: 1), color: muted)
        }
        each(html) { match in
            storage.addAttribute(.foregroundColor, value: muted, range: match.range)
        }
        each(url) { match in
            let text = (string as NSString).substring(with: match.range)
            if let target = URL(string: text) { storage.addAttribute(.link, value: target, range: match.range) }
        }
        each(link) { match in
            storage.addAttribute(.foregroundColor, value: muted, range: match.range)
            let isImage = match.range(at: 1).length > 0
            guard !isImage else { return }
            let target = (string as NSString).substring(with: match.range(at: 3))
            storage.addAttribute(.foregroundColor, value: accent, range: match.range(at: 2))
            if let target = URL(string: target) { storage.addAttribute(.link, value: target, range: match.range(at: 2)) }
            storage.removeAttribute(.link, range: match.range(at: 3))
        }
        // Code last: nothing inside it is Markdown.
        each(inlineCode) { match in
            clearMarkdown(storage, match.range)
            storage.addAttribute(.font, value: mono, range: match.range)
            storage.addAttribute(.backgroundColor, value: PlatformColor(Theme.control), range: match.range)
        }
        each(fence) { match in
            clearMarkdown(storage, match.range)
            storage.addAttribute(.font, value: mono, range: match.range)
            let text = (string as NSString).substring(with: match.range) as NSString
            // The ``` lines fade back; the code itself stays readable.
            let firstLine = text.lineRange(for: NSRange(location: 0, length: 0))
            storage.addAttribute(.foregroundColor, value: muted, range: NSRange(location: match.range.location, length: firstLine.length))
            let lastLine = text.lineRange(for: NSRange(location: max(text.length - 1, 0), length: 0))
            if lastLine.location > 0, text.substring(with: lastLine).hasPrefix("```") {
                storage.addAttribute(.foregroundColor, value: muted, range: NSRange(location: match.range.location + lastLine.location, length: lastLine.length))
            }
        }
    }

    /// Fades the Markdown punctuation around a styled span.
    private static func dim(_ storage: NSTextStorage, _ whole: NSRange, keeping inner: NSRange, color: PlatformColor) {
        let before = NSRange(location: whole.location, length: inner.location - whole.location)
        let after = NSRange(location: NSMaxRange(inner), length: NSMaxRange(whole) - NSMaxRange(inner))
        storage.addAttribute(.foregroundColor, value: color, range: before)
        storage.addAttribute(.foregroundColor, value: color, range: after)
    }

    private static func clearMarkdown(_ storage: NSTextStorage, _ range: NSRange) {
        storage.setAttributes(baseAttributes, range: range)
    }
}
