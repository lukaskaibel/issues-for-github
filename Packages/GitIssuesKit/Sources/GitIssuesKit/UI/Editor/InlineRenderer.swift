#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Inline Markdown turned into the text you read, without its punctuation: for table cells, where nothing is edited.
@MainActor
enum InlineRenderer {
    static func render(_ text: String, font: NSFont, color: NSColor) -> NSAttributedString {
        let units = Array(text.utf16)
        let result = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        let spans = InlineParser.spans(in: units, range: NSRange(location: 0, length: units.count))
        var removed: [NSRange] = []
        for span in spans {
            removed.append(contentsOf: span.markers)
            switch span.kind {
            case .strong:
                restyleFont(result, span.content) { EditorStyle.font($0, bold: true) }
            case .emphasis:
                restyleFont(result, span.content) { EditorStyle.font($0, italic: true) }
            case .strikethrough:
                result.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: EditorTheme.textTertiary], range: span.content)
            case .code:
                result.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: font.pointSize * 0.9, weight: .regular), .backgroundColor: EditorTheme.inlineCode], range: span.content)
            case .link, .autolink, .image:
                result.addAttribute(.foregroundColor, value: EditorTheme.accent, range: span.content)
            case .math(let tex):
                result.replaceCharacters(in: span.content, with: tex)
            case .footnoteReference:
                result.addAttributes([.foregroundColor: EditorTheme.accent, .baselineOffset: 4, .font: NSFont.systemFont(ofSize: font.pointSize * 0.75)], range: span.content)
            case .comment:
                removed.append(span.range)
            case .html:
                result.addAttribute(.foregroundColor, value: EditorTheme.faint, range: span.range)
            case .escape:
                break
            }
        }
        // From the end, and each stretch once, so every removal still finds its place.
        var last = Int.max
        for range in removed.sorted(by: { $0.location > $1.location }) where range.upperBound <= result.length {
            let clipped = NSRange(location: range.location, length: min(range.length, max(0, last - range.location)))
            guard clipped.length > 0 else { continue }
            result.deleteCharacters(in: clipped)
            last = clipped.location
        }
        return result
    }

    private static func restyleFont(_ string: NSMutableAttributedString, _ range: NSRange, _ change: (NSFont) -> NSFont) {
        string.enumerateAttribute(.font, in: range) { value, run, _ in
            if let font = value as? NSFont { string.addAttribute(.font, value: change(font), range: run) }
        }
    }
}
