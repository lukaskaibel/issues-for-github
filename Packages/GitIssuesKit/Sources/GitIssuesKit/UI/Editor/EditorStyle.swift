#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension NSAttributedString.Key {
    /// Markdown punctuation that isn't drawn. `HiddenMode.untilRevealed` comes back next to the caret,
    /// `HiddenMode.always` never does.
    static let markdownHidden = NSAttributedString.Key("markdown.hidden")
    /// An `EditorObject` drawn in place of its character, on the first character of what it stands for.
    static let markdownObject = NSAttributedString.Key("markdown.object")
    /// A box drawn behind a run of text (code blocks, alerts, inline code).
    static let markdownDecoration = NSAttributedString.Key("markdown.decoration")
    /// Where a click goes.
    static let markdownLink = NSAttributedString.Key("markdown.link")
    /// How much of a Markdown mark shows while it folds in or out (`MarkdownRevealAnimator`): its opacity, 0 to 1.
    static let markdownFade = NSAttributedString.Key("markdown.fade")
}

enum HiddenMode: Int {
    case untilRevealed = 1
    case always = 2
}

/// Fonts, colours and spacing of Markdown in the app: the size of the app's text, 14 points on the Mac and the reader's
/// text size on iPhone and iPad, with everything else in proportion to it.
@MainActor
enum EditorStyle {
    #if os(macOS)
    static var bodySize: CGFloat { 14 }
    #else
    /// Follows the reader's text size, from 16 pt at the default size.
    static var bodySize: CGFloat { UIFontMetrics(forTextStyle: .body).scaledValue(for: 16) }
    #endif
    /// Spacing grows with the text: 1 at the Mac's 14 points.
    static var scale: CGFloat { bodySize / 14 }
    static var lineHeight: CGFloat { (bodySize * 1.6).rounded() }
    static var codeSize: CGFloat { (bodySize * 0.88).rounded() }
    static var codeLineHeight: CGFloat { (codeSize * 1.54).rounded(.down) }
    static var listIndent: CGFloat { (22 * scale).rounded() }
    /// A checkbox, big enough for a fingertip on iPhone and iPad and a little smaller next to the Mac's text.
    static var checkboxSide: CGFloat {
        #if os(iOS)
        (bodySize * 1.2).rounded()
        #else
        (bodySize * 1.1).rounded()
        #endif
    }
    /// The room a checkbox takes before its text.
    static var checkboxWidth: CGFloat { checkboxSide + (9 * scale).rounded() }
    static var quoteIndent: CGFloat { (17 * scale).rounded() }
    static var codePadding: CGFloat { (12 * scale).rounded() }

    static var body: NSFont { .systemFont(ofSize: bodySize) }
    static var mono: NSFont { .monospacedSystemFont(ofSize: codeSize, weight: .regular) }
    static var inlineMono: NSFont { .monospacedSystemFont(ofSize: (bodySize * 0.88).rounded(), weight: .regular) }
    static let tiny = NSFont.systemFont(ofSize: 0.5)

    static func face(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: size, weight: weight)
    }

    /// Headings keep their proportion to the text, and stay smaller than an issue's title.
    private static func headingScale(_ level: Int) -> CGFloat {
        switch level {
        case 1: 1.45
        case 2: 1.25
        case 3: 1.1
        default: 1
        }
    }

    static func headingFont(_ level: Int) -> NSFont {
        face((bodySize * headingScale(level)).rounded(), weight: level == 1 ? .bold : .semibold)
    }

    static func headingLineHeight(_ level: Int) -> CGFloat {
        (bodySize * headingScale(level) * 1.4).rounded()
    }

    static func headingSpacingBefore(_ level: Int) -> CGFloat {
        let points: CGFloat = switch level {
        case 1: 16
        case 2: 12
        case 3: 9
        default: 7
        }
        return (points * scale).rounded()
    }

    /// A text style's name where you pick it, in the Format panel: Title, Heading and Subheading larger and heavier
    /// than the text around them (`size`), though by less than in the text.
    static func styleSample(_ style: FormatCommand, size: CGFloat) -> NSFont {
        let level = switch style {
        case .title: 1
        case .heading: 2
        case .subheading: 3
        default: 0
        }
        guard level > 0 else { return face(size) }
        return face((size * (1 + (headingScale(level) - 1) * 0.75)).rounded(), weight: level == 1 ? .bold : .semibold)
    }

    /// Lines of a fixed height, with the text in the middle of the line rather than at its bottom.
    static func paragraph(
        lineHeight: CGFloat? = nil,
        before: CGFloat = 0,
        after: CGFloat = 2,
        firstIndent: CGFloat = 0,
        indent: CGFloat = 0,
        tail: CGFloat = 0
    ) -> NSMutableParagraphStyle {
        let lineHeight = lineHeight ?? Self.lineHeight
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        style.paragraphSpacingBefore = before
        style.paragraphSpacing = after
        style.firstLineHeadIndent = firstIndent
        style.headIndent = indent
        style.tailIndent = tail
        style.lineBreakMode = .byWordWrapping
        return style
    }

    /// For a line that only holds a picture or a rendered block: as tall as the thing in it.
    static func objectParagraph(before: CGFloat = 6, after: CGFloat = 8, indent: CGFloat = 0) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = before
        style.paragraphSpacing = after
        style.firstLineHeadIndent = indent
        style.headIndent = indent
        return style
    }

    /// A line folded away inside a block that is drawn as a whole.
    static let collapsedParagraph: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = 0.01
        style.maximumLineHeight = 0.01
        style.paragraphSpacing = 0
        style.paragraphSpacingBefore = 0
        return style
    }()

    /// Lifts text so it sits in the middle of a line taller than the font.
    static func baselineOffset(for font: NSFont, lineHeight: CGFloat) -> CGFloat {
        let natural = font.ascender - font.descender
        return max(0, (lineHeight - natural) / 2) - 1
    }

    /// The same font, bolder and/or slanted. Bold makes body text semibold and headings heavy.
    static func font(_ font: NSFont, bold: Bool = false, italic: Bool = false) -> NSFont {
        var result = font
        if bold {
            if font.isFixedPitch {
                result = .monospacedSystemFont(ofSize: font.pointSize, weight: .bold)
            } else {
                result = face(font.pointSize, weight: weight(of: font) >= NSFont.Weight.semibold.rawValue - 0.01 ? .heavy : .semibold)
            }
        }
        if italic {
            #if os(macOS)
            let traits = result.fontDescriptor.symbolicTraits.union(.italic)
            result = NSFont(descriptor: result.fontDescriptor.withSymbolicTraits(traits), size: result.pointSize) ?? result
            #else
            let traits = result.fontDescriptor.symbolicTraits.union(.traitItalic)
            if let descriptor = result.fontDescriptor.withSymbolicTraits(traits) { result = UIFont(descriptor: descriptor, size: result.pointSize) }
            #endif
        }
        return result
    }

    static func weight(of font: NSFont) -> CGFloat {
        let traits = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
        return (traits?[.weight] as? CGFloat) ?? 0
    }
}
