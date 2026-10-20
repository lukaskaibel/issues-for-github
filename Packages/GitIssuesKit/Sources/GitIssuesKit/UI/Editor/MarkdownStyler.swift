#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// What the styler needs to know beyond the text.
struct StyleEnvironment {
    /// The block the caret is in: tables, maths and diagrams show their Markdown then.
    var activeBlock: Int?
    /// Whether the text can be edited. Text that is only read hides what GitHub hides (HTML comments) and has no
    /// controls for editing (a link's pencil).
    var isEditable = true
    var isDark = false
    /// A rendered preview's height, for diagrams and maths shown under their source while you edit them.
    var previewHeight: (MarkdownBlock) -> CGFloat = { _ in 0 }
}

/// Turns parsed Markdown into attributes: fonts, colours, line heights, which punctuation hides and which objects are
/// drawn in place of Markdown. It only ever sets attributes; the characters stay exactly as they are on GitHub.
@MainActor
enum MarkdownStyler {
    static var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: EditorStyle.body,
            .foregroundColor: EditorTheme.textBody,
            .paragraphStyle: EditorStyle.paragraph(),
            .baselineOffset: EditorStyle.baselineOffset(for: EditorStyle.body, lineHeight: EditorStyle.lineHeight),
        ]
    }

    /// One decoration per block, shared by all its lines, so the box behind a block is one run of text.
    private static var blockDecorations: [NSRange: Decoration] = [:]

    private static func decoration(for block: MarkdownBlock, _ kind: Decoration.Kind) -> Decoration {
        if let existing = blockDecorations[block.range], existing.kind == kind { return existing }
        let decoration = Decoration(kind)
        blockDecorations[block.range] = decoration
        return decoration
    }

    static func style(_ storage: NSTextStorage, document doc: MarkdownDocument, lines: [Int], environment env: StyleEnvironment) {
        let text = storage.string as NSString
        guard text.length == doc.length else { return }
        blockDecorations = [:]
        defer { blockDecorations = [:] }
        for index in lines where index < doc.lines.count {
            styleLine(storage, text: text, doc: doc, index: index, env: env)
        }
    }

    // MARK: - Lines

    private static func styleLine(_ s: NSTextStorage, text: NSString, doc: MarkdownDocument, index: Int, env: StyleEnvironment) {
        let line = doc.lines[index]
        let full = line.fullRange
        guard full.upperBound <= s.length else { return }
        s.setAttributes(baseAttributes, range: full)

        if let blockIndex = line.block {
            let block = doc.blocks[blockIndex]
            let active = env.activeBlock == blockIndex
            switch block.kind {
            case .code(let language):
                styleCode(s, text: text, doc: doc, line: line, index: index, block: block, language: language, env: env)
                return
            case .mermaid:
                let source = blockContent(text, doc, block)
                if active {
                    styleCode(s, text: text, doc: doc, line: line, index: index, block: block, language: "mermaid", env: env,
                              preview: env.previewHeight(block), previewKind: .diagram(source: source))
                } else if DiagramStore.cached(source, isDark: env.isDark) == .some(nil) {
                    // A diagram that can't be drawn shows as the code it is.
                    styleCode(s, text: text, doc: doc, line: line, index: index, block: block, language: "mermaid", env: env)
                } else {
                    styleSwapped(s, line: line, index: index, block: block, object: .mermaid(source: source))
                }
                return
            case .table(let alignments):
                if active {
                    styleTableSource(s, text: text, line: line, index: index, block: block)
                } else {
                    let lines = Array(doc.lines[block.lines])
                    styleSwapped(s, line: line, index: index, block: block, object: .table(TableModel(text: text, lines: lines, alignments: alignments)))
                }
                return
            case .math:
                let tex = mathSource(text, doc, block)
                if active {
                    styleCode(s, text: text, doc: doc, line: line, index: index, block: block, language: "tex", env: env,
                              preview: env.previewHeight(block), previewKind: .math(tex: tex))
                } else {
                    styleSwapped(s, line: line, index: index, block: block, object: .mathBlock(tex: tex))
                }
                return
            case .callout(let type):
                styleCallout(s, text: text, doc: doc, line: line, index: index, block: block, type: type, env: env)
                return
            case .comment:
                styleComment(s, text: text, line: line, env: env)
                return
            case .quote:
                break
            }
        }

        switch line.kind {
        case .blank:
            return
        case .heading(let level, let marker):
            let font = EditorStyle.headingFont(level)
            let height = EditorStyle.headingLineHeight(level)
            let before = index == 0 ? 0 : EditorStyle.headingSpacingBefore(level)
            s.addAttributes([
                .font: font,
                .foregroundColor: EditorTheme.text,
                .paragraphStyle: EditorStyle.paragraph(lineHeight: height, before: before, after: 4),
                .baselineOffset: EditorStyle.baselineOffset(for: font, lineHeight: height),
            ], range: full)
            s.addAttribute(.foregroundColor, value: EditorTheme.faint, range: marker)
            hide(s, marker, .untilRevealed)
        case .listItem(let item):
            styleListItem(s, text: text, line: line, item: item, env: env)
        case .quote(let depth, let prefix):
            let indent = CGFloat(depth) * EditorStyle.quoteIndent
            s.addAttributes([
                .paragraphStyle: EditorStyle.paragraph(after: 2, firstIndent: 0, indent: indent),
                .foregroundColor: EditorTheme.textSecondary,
            ], range: full)
            for i in prefix.location..<prefix.upperBound {
                if text.character(at: i) == 62 {
                    s.addAttribute(.markdownObject, value: EditorObject(.quoteBar, range: prefix, at: i), range: NSRange(location: i, length: 1))
                } else {
                    hide(s, NSRange(location: i, length: 1), .always)
                }
            }
        case .thematicBreak:
            s.addAttribute(.markdownObject, value: EditorObject(.horizontalRule, range: line.range, revealable: true), range: NSRange(location: line.range.location, length: 1))
            s.addAttribute(.foregroundColor, value: EditorTheme.faint, range: line.range)
            hide(s, NSRange(location: line.range.location + 1, length: line.range.length - 1), .untilRevealed)
            s.addAttribute(.paragraphStyle, value: EditorStyle.paragraph(before: 4, after: 6), range: full)
        case .footnoteDefinition(let label):
            let font = NSFont.systemFont(ofSize: (EditorStyle.bodySize * 0.88).rounded())
            s.addAttributes([.font: font, .foregroundColor: EditorTheme.textSecondary, .paragraphStyle: EditorStyle.paragraph(lineHeight: (font.pointSize * 1.5).rounded())], range: full)
            s.addAttributes([.foregroundColor: EditorTheme.faint], range: label)
        default:
            break
        }

        // A line that only holds a picture shows it as a block.
        if line.kind == .paragraph, let only = soleObjectSpan(text, line) {
            styleBlockObject(s, span: only, line: line, env: env)
            return
        }
        styleInlineSpans(s, text: text, line: line, env: env)
    }

    // MARK: - Lists

    private static func styleListItem(_ s: NSTextStorage, text: NSString, line: MarkdownLine, item: ListItem, env: StyleEnvironment) {
        let first = CGFloat(item.level) * EditorStyle.listIndent
        let full = line.fullRange
        hide(s, item.indentRange, .always)
        var prefixWidth = EditorStyle.listIndent
        switch item.marker {
        case .bullet:
            if item.checkbox == nil {
                s.addAttribute(.markdownObject, value: EditorObject(.bullet(level: item.level), range: item.prefix, at: item.markerRange.location), range: item.markerRange)
            } else {
                hide(s, item.markerRange, .always)
            }
            hide(s, NSRange(location: item.markerRange.upperBound, length: (item.checkbox?.location ?? item.prefix.upperBound) - item.markerRange.upperBound), .always)
        case .ordered:
            let marker = text.substring(with: NSRange(location: item.markerRange.location, length: item.prefix.upperBound - item.markerRange.location))
            let numberFont = NSFont.monospacedDigitSystemFont(ofSize: EditorStyle.bodySize, weight: .regular)
            s.addAttributes([.foregroundColor: EditorTheme.textTertiary, .font: numberFont], range: item.markerRange)
            if item.checkbox == nil {
                // The number and the space after it stay text; wrapped lines line up with the text after them.
                let spaces = NSRange(location: item.markerRange.upperBound, length: item.prefix.upperBound - item.markerRange.upperBound)
                if spaces.length > 1 { hide(s, NSRange(location: spaces.location + 1, length: spaces.length - 1), .always) }
                let shown = String(marker.prefix(item.markerRange.length + min(1, spaces.length)))
                prefixWidth = max(EditorStyle.listIndent, ceil((shown as NSString).size(withAttributes: [.font: numberFont]).width))
            } else {
                hide(s, NSRange(location: item.markerRange.location, length: (item.checkbox?.location ?? item.prefix.upperBound) - item.markerRange.location), .always)
            }
        }
        if let checkbox = item.checkbox {
            s.addAttribute(.markdownObject, value: EditorObject(.checkbox(checked: item.checked), range: item.prefix, at: checkbox.location), range: NSRange(location: checkbox.location, length: 1))
            hide(s, NSRange(location: checkbox.location + 1, length: item.prefix.upperBound - checkbox.location - 1), .always)
            prefixWidth = EditorStyle.checkboxWidth
            if item.checked {
                // Done: greyed out, as in Reminders, without striking it through.
                s.addAttribute(.foregroundColor, value: EditorTheme.textTertiary, range: line.content)
            }
        }
        s.addAttribute(.paragraphStyle, value: EditorStyle.paragraph(after: 3, firstIndent: first, indent: first + prefixWidth), range: full)
        styleInlineSpans(s, text: text, line: line, env: env)
    }

    // MARK: - Blocks

    private static func styleCode(
        _ s: NSTextStorage, text: NSString, doc: MarkdownDocument, line: MarkdownLine, index: Int, block: MarkdownBlock,
        language: String, env: StyleEnvironment, preview: CGFloat = 0, previewKind: Decoration.Preview? = nil
    ) {
        let full = line.fullRange
        let isFirst = index == block.lines.lowerBound
        let isLast = index == block.lines.upperBound
        let pad = EditorStyle.codePadding
        let style = EditorStyle.paragraph(
            lineHeight: EditorStyle.codeLineHeight,
            before: isFirst ? 6 : 0,
            after: isLast ? 10 + (preview > 0 ? preview + 12 : 0) : 0,
            firstIndent: pad, indent: pad, tail: -pad
        )
        s.addAttributes([
            .font: EditorStyle.mono,
            .foregroundColor: EditorTheme.textBody,
            .paragraphStyle: style,
            .baselineOffset: EditorStyle.baselineOffset(for: EditorStyle.mono, lineHeight: EditorStyle.codeLineHeight),
            // The preview belongs to the box, so the box goes round the closing fence too and the preview hangs below it.
            .markdownDecoration: decoration(for: block, .codeBlock(language: language, active: previewKind != nil || language == "tex", preview: previewKind)),
        ], range: full)
        switch line.kind {
        case .fence, .mathDelimiter:
            s.addAttribute(.foregroundColor, value: EditorTheme.faint, range: line.range)
            // Code blocks hide their fences until you edit them; the line keeps its height, so nothing moves.
            if case .code = block.kind { hide(s, line.range, .untilRevealed) }
            if case .mermaid = block.kind, previewKind == nil { hide(s, line.range, .untilRevealed) }
        case .code, .math:
            let highlighted = language == "tex" ? "" : language
            for (range, token) in highlights(text, doc, block, highlighted) {
                let clipped = NSIntersectionRange(range, line.range)
                guard clipped.length > 0 else { continue }
                s.addAttribute(.foregroundColor, value: CodeHighlighter.color(token), range: clipped)
                if token == .comment {
                    s.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: EditorStyle.codeSize, weight: .regular).withItalic, range: clipped)
                }
            }
        default:
            break
        }
    }

    private static func styleTableSource(_ s: NSTextStorage, text: NSString, line: MarkdownLine, index: Int, block: MarkdownBlock) {
        let isFirst = index == block.lines.lowerBound
        let isLast = index == block.lines.upperBound
        let pad = EditorStyle.codePadding
        let height = (EditorStyle.codeLineHeight * 1.15).rounded()
        s.addAttributes([
            .font: EditorStyle.mono,
            .paragraphStyle: EditorStyle.paragraph(lineHeight: height, before: isFirst ? 6 : 0, after: isLast ? 10 : 0, firstIndent: pad, indent: pad, tail: -pad),
            .baselineOffset: EditorStyle.baselineOffset(for: EditorStyle.mono, lineHeight: height),
            .markdownDecoration: decoration(for: block, .codeBlock(language: "", active: true)),
        ], range: line.fullRange)
        if line.kind == .tableDelimiter {
            s.addAttribute(.foregroundColor, value: EditorTheme.faint, range: line.range)
            return
        }
        if line.kind == .tableHeader { s.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: EditorStyle.codeSize, weight: .semibold), range: line.range) }
        for i in line.range.location..<line.range.upperBound where text.character(at: i) == 124 {
            s.addAttribute(.foregroundColor, value: EditorTheme.faint, range: NSRange(location: i, length: 1))
        }
    }

    /// A block drawn as a whole: the object on its first character, everything else hidden and its other lines
    /// folded away.
    private static func styleSwapped(_ s: NSTextStorage, line: MarkdownLine, index: Int, block: MarkdownBlock, object kind: EditorObject.Kind) {
        if index == block.lines.lowerBound {
            s.addAttribute(.paragraphStyle, value: EditorStyle.objectParagraph(), range: line.fullRange)
            if line.range.length > 0 {
                s.addAttribute(.markdownObject, value: EditorObject(kind, range: block.range), range: NSRange(location: line.range.location, length: 1))
                hide(s, NSRange(location: line.range.location + 1, length: line.range.length - 1), .always)
            }
        } else {
            collapse(s, line)
        }
    }

    /// A line that takes no room and shows nothing.
    private static func collapse(_ s: NSTextStorage, _ line: MarkdownLine) {
        s.addAttributes([.paragraphStyle: EditorStyle.collapsedParagraph, .font: EditorStyle.tiny], range: line.fullRange)
        hide(s, line.range, .always)
    }

    private static func styleCallout(
        _ s: NSTextStorage, text: NSString, doc: MarkdownDocument, line: MarkdownLine, index: Int, block: MarkdownBlock,
        type: String, env: StyleEnvironment
    ) {
        let isFirst = index == block.lines.lowerBound
        let isLast = index == block.lines.upperBound
        let pad = (14 * EditorStyle.scale).rounded()
        s.addAttributes([
            .paragraphStyle: EditorStyle.paragraph(before: isFirst ? 10 : 0, after: isLast ? 14 : 0, firstIndent: pad, indent: pad, tail: -pad),
            .markdownDecoration: decoration(for: block, .callout(type: type)),
        ], range: line.fullRange)
        guard case .quote(_, let prefix) = line.kind else { return }
        hide(s, prefix, .always)
        if isFirst {
            // "[!TIP]": the type becomes its symbol and its name, in the alert's colour.
            let marker = NSRange(location: line.content.location, length: line.range.upperBound - line.content.location)
            guard marker.length > 0 else { return }
            s.addAttribute(.markdownObject, value: EditorObject(.callout(type: type, label: CalloutStyle.title(type)), range: marker, revealable: env.isEditable),
                           range: NSRange(location: marker.location, length: 1))
            s.addAttribute(.foregroundColor, value: EditorTheme.faint, range: marker)
            hide(s, NSRange(location: marker.location + 1, length: marker.length - 1), env.isEditable ? .untilRevealed : .always)
            return
        }
        styleInlineSpans(s, text: text, line: line, env: env)
    }

    /// HTML comments, which GitHub doesn't show: faint while you can edit them, gone where the text is only read.
    private static func styleComment(_ s: NSTextStorage, text: NSString, line: MarkdownLine, env: StyleEnvironment) {
        guard env.isEditable else { return collapse(s, line) }
        s.addAttributes([.foregroundColor: EditorTheme.textTertiary, .font: EditorStyle.body.withItalic], range: line.range)
        let content = text.substring(with: line.range) as NSString
        for marker in ["<!--", "-->"] {
            var search = NSRange(location: 0, length: content.length)
            while true {
                let found = content.range(of: marker, options: [], range: search)
                guard found.location != NSNotFound else { break }
                let range = NSRange(location: line.range.location + found.location, length: found.length)
                s.addAttribute(.foregroundColor, value: EditorTheme.faint, range: range)
                hide(s, range, .untilRevealed)
                search = NSRange(location: found.upperBound, length: content.length - found.upperBound)
            }
        }
    }

    // MARK: - Inline

    private static func soleObjectSpan(_ text: NSString, _ line: MarkdownLine) -> InlineSpan? {
        let objects = line.spans.filter {
            if case .image = $0.kind { true } else { false }
        }
        guard objects.count == 1, let span = objects.first else { return nil }
        let before = text.substring(with: NSRange(location: line.range.location, length: span.range.location - line.range.location))
        let after = text.substring(with: NSRange(location: span.range.upperBound, length: line.range.upperBound - span.range.upperBound))
        guard before.allSatisfy(\.isWhitespace), after.allSatisfy(\.isWhitespace) else { return nil }
        return span
    }

    private static func styleBlockObject(_ s: NSTextStorage, span: InlineSpan, line: MarkdownLine, env: StyleEnvironment) {
        guard case .image(let source, _, let width) = span.kind else { return }
        let kind = EditorObject.Kind.image(url: imageURL(source), source: source, inline: false, width: width)
        s.addAttribute(.paragraphStyle, value: EditorStyle.objectParagraph(), range: line.fullRange)
        hide(s, NSRange(location: line.range.location, length: span.range.location - line.range.location), .always)
        s.addAttribute(.markdownObject, value: EditorObject(kind, range: span.range), range: NSRange(location: span.range.location, length: 1))
        hide(s, NSRange(location: span.range.location + 1, length: line.range.upperBound - span.range.location - 1), .always)
    }

    static func styleInlineSpans(_ s: NSTextStorage, text: NSString, line: MarkdownLine, env: StyleEnvironment) {
        for span in line.spans {
            switch span.kind {
            case .strong:
                restyleFont(s, span.content) { EditorStyle.font($0, bold: true) }
                markers(s, span)
            case .emphasis:
                restyleFont(s, span.content) { EditorStyle.font($0, italic: true) }
                markers(s, span)
            case .strikethrough:
                s.addAttributes([
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .strikethroughColor: EditorTheme.textTertiary,
                    .foregroundColor: EditorTheme.textTertiary,
                ], range: span.content)
                markers(s, span)
            case .code:
                restyleFont(s, span.range) { NSFont.monospacedSystemFont(ofSize: $0.pointSize * 0.88, weight: EditorStyle.weight(of: $0) > 0.2 ? .semibold : .regular) }
                s.addAttribute(.markdownDecoration, value: Decoration(.inlineCode), range: span.content)
                markers(s, span)
            case .link(let destination):
                // The text reads and edits like text; the address stays behind a pencil after it.
                s.addAttribute(.foregroundColor, value: EditorTheme.accent, range: span.content)
                #if os(macOS)
                s.addAttribute(.toolTip, value: destination, range: span.content)
                #endif
                s.addAttribute(.markdownLink, value: LinkTarget(destination), range: span.content)
                if let open = span.markers.first { hide(s, open, .always) }
                if span.markers.count > 1, let close = span.markers.last, close.length > 0 {
                    if env.isEditable {
                        s.addAttribute(.markdownObject, value: EditorObject(.linkEdit, range: span.range, at: close.location), range: NSRange(location: close.location, length: 1))
                        hide(s, NSRange(location: close.location + 1, length: close.length - 1), .always)
                    } else {
                        hide(s, close, .always)
                    }
                }
            case .autolink(let url):
                s.addAttributes([
                    .foregroundColor: EditorTheme.accent,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: EditorTheme.accent.withAlphaComponent(0.35),
                ], range: span.content)
                s.addAttribute(.markdownLink, value: LinkTarget(url), range: span.range)
                markers(s, span)
            case .image(let source, _, let width):
                s.addAttribute(.markdownObject, value: EditorObject(.image(url: imageURL(source), source: source, inline: true, width: width), range: span.range), range: NSRange(location: span.range.location, length: 1))
                hide(s, NSRange(location: span.range.location + 1, length: span.range.length - 1), .always)
            case .math(let tex):
                s.addAttribute(.markdownObject, value: EditorObject(.mathInline(tex: tex), range: span.range, revealable: env.isEditable), range: NSRange(location: span.range.location, length: 1))
                hide(s, NSRange(location: span.range.location + 1, length: span.range.length - 1), env.isEditable ? .untilRevealed : .always)
                restyleFont(s, span.range) { NSFont.monospacedSystemFont(ofSize: $0.pointSize * 0.88, weight: .regular) }
                s.addAttribute(.foregroundColor, value: EditorTheme.faint, range: span.markers.first ?? span.range)
                if let last = span.markers.last { s.addAttribute(.foregroundColor, value: EditorTheme.faint, range: last) }
            case .footnoteReference:
                s.addAttributes([.foregroundColor: EditorTheme.accent, .font: NSFont.systemFont(ofSize: (EditorStyle.bodySize * 0.75).rounded(), weight: .medium), .baselineOffset: (EditorStyle.bodySize * 0.6).rounded()], range: span.content)
                markers(s, span)
            case .escape:
                markers(s, span)
            case .comment:
                if env.isEditable {
                    s.addAttributes([.foregroundColor: EditorTheme.textTertiary], range: span.content)
                    restyleFont(s, span.content) { $0.withItalic }
                    markers(s, span)
                } else {
                    hide(s, span.range, .always)
                }
            case .html:
                s.addAttribute(.foregroundColor, value: EditorTheme.faint, range: span.range)
            }
        }
    }

    private static func markers(_ s: NSTextStorage, _ span: InlineSpan) {
        for marker in span.markers {
            s.addAttribute(.foregroundColor, value: EditorTheme.faint, range: marker)
            hide(s, marker, .untilRevealed)
        }
    }

    // MARK: - Helpers

    static func hide(_ s: NSTextStorage, _ range: NSRange, _ mode: HiddenMode) {
        guard range.length > 0, range.upperBound <= s.length else { return }
        s.addAttribute(.markdownHidden, value: mode.rawValue, range: range)
    }

    private static func restyleFont(_ s: NSTextStorage, _ range: NSRange, _ change: (NSFont) -> NSFont) {
        guard range.length > 0 else { return }
        s.enumerateAttribute(.font, in: range) { value, run, _ in
            if let font = value as? NSFont { s.addAttribute(.font, value: change(font), range: run) }
        }
    }

    /// Where a picture is, when it is on the web; GitHub has no other kind.
    static func imageURL(_ source: String) -> URL? {
        guard let url = URL(string: source.trimmingCharacters(in: .whitespaces)), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return nil }
        return url
    }

    /// The code between a block's fences, as it is copied.
    static func blockContent(_ text: NSString, _ doc: MarkdownDocument, _ block: MarkdownBlock) -> String {
        let inner = block.lines.dropFirst().filter { doc.lines[$0].kind == .code }
        return inner.map { text.substring(with: doc.lines[$0].range) }.joined(separator: "\n")
    }

    static func mathSource(_ text: NSString, _ doc: MarkdownDocument, _ block: MarkdownBlock) -> String {
        if block.lines.count == 1 {
            let line = text.substring(with: doc.lines[block.lines.lowerBound].range).trimmingCharacters(in: .whitespaces)
            return String(line.dropFirst(2).dropLast(2))
        }
        // `$$` around it, or a ```math fence.
        if doc.lines[block.lines.lowerBound].kind == .fence { return blockContent(text, doc, block) }
        return block.lines.filter { doc.lines[$0].kind == .math }.map { text.substring(with: doc.lines[$0].range) }.joined(separator: "\n")
    }

    static func diagramSource(_ text: NSString, _ doc: MarkdownDocument, _ block: MarkdownBlock) -> String {
        blockContent(text, doc, block)
    }

    private static var highlightCache: [String: [(NSRange, CodeHighlighter.Token)]] = [:]

    /// The code block's colours, worked out for the whole block at once (a comment can span lines) and kept until
    /// its text changes.
    private static func highlights(_ text: NSString, _ doc: MarkdownDocument, _ block: MarkdownBlock, _ language: String) -> [(NSRange, CodeHighlighter.Token)] {
        let codeLines = block.lines.filter { doc.lines[$0].kind == .code }
        guard let first = codeLines.first, let last = codeLines.last else { return [] }
        let range = NSRange(location: doc.lines[first].range.location, length: doc.lines[last].range.upperBound - doc.lines[first].range.location)
        let code = text.substring(with: range)
        let key = language + "\u{0}" + code
        if let cached = highlightCache[key] { return cached.map { ($0.0.shifted(by: range.location), $0.1) } }
        let tokens = CodeHighlighter.tokens(in: code, language: language)
        if highlightCache.count > 200 { highlightCache.removeAll() }
        highlightCache[key] = tokens
        return tokens.map { ($0.0.shifted(by: range.location), $0.1) }
    }
}
