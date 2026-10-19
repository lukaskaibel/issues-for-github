import Foundation

/// Markdown read line by line, the way the editor needs it: every line knows what it is, which characters are Markdown
/// punctuation and which are the text you read. Ranges count UTF-16 code units, as `NSString` does.
struct MarkdownDocument {
    var lines: [MarkdownLine]
    var blocks: [MarkdownBlock]
    var length: Int

    /// The line that holds a character (or the caret at that index).
    func lineIndex(containing location: Int) -> Int {
        guard !lines.isEmpty else { return 0 }
        var low = 0, high = lines.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lines[mid].range.location <= location { low = mid } else { high = mid - 1 }
        }
        return low
    }

    func line(containing location: Int) -> MarkdownLine? {
        lines.isEmpty ? nil : lines[lineIndex(containing: location)]
    }

    func block(containing location: Int) -> MarkdownBlock? {
        guard let index = line(containing: location)?.block else { return nil }
        return blocks[index]
    }

    /// The checkboxes of the task lists, in order.
    var checkboxes: [(line: Int, item: ListItem)] {
        lines.indices.compactMap { index in
            if case .listItem(let item) = lines[index].kind, item.isTask { return (index, item) }
            return nil
        }
    }
}

struct MarkdownLine: Equatable {
    /// The line without its line break.
    var range: NSRange
    /// The line break after it: 0 on the last line, 1 for `\n`, 2 for `\r\n`.
    var breakLength: Int
    var kind: LineKind
    /// The block it belongs to, for lines that only make sense together (code, tables, math, quotes).
    var block: Int?
    /// The text after the line's own punctuation (`- `, `> `, `## `), where inline Markdown is read.
    var content: NSRange
    var spans: [InlineSpan]
    /// A hash of the line's characters, line break included, to tell cheaply whether it changed.
    var textHash: Int = 0

    var fullRange: NSRange { NSRange(location: range.location, length: range.length + breakLength) }
}

enum LineKind: Hashable {
    case blank
    case paragraph
    case heading(level: Int, marker: NSRange)
    case listItem(ListItem)
    case quote(depth: Int, prefix: NSRange)
    case thematicBreak
    case fence
    case code
    case mathDelimiter
    case math
    case tableHeader
    case tableDelimiter
    case tableRow
    /// Part of an HTML comment, which GitHub doesn't show.
    case comment
    case footnoteDefinition(label: NSRange)

    var isListItem: Bool { if case .listItem = self { true } else { false } }
}

struct ListItem: Hashable {
    enum Marker: Hashable {
        case bullet(Character)
        case ordered(Int, Character)
    }

    /// Spaces before the marker; a tab counts as four.
    var indent: Int
    /// How deep the item sits in its list, from 0.
    var level: Int
    var indentRange: NSRange
    var marker: Marker
    var markerRange: NSRange
    /// Everything before the item's text: indent, marker, spaces, checkbox.
    var prefix: NSRange
    /// `[ ]` or `[x]` of a task.
    var checkbox: NSRange?
    var checked: Bool

    var isTask: Bool { checkbox != nil }
    var isOrdered: Bool { if case .ordered = marker { true } else { false } }
}

struct MarkdownBlock: Equatable {
    enum Kind: Hashable {
        case code(language: String)
        case mermaid
        case table(alignments: [TableAlignment])
        /// `$$ … $$` or a ```` ```math ```` block.
        case math
        case quote
        case callout(type: String)
        case comment
    }

    var kind: Kind
    /// Indices of its first and last line.
    var lines: ClosedRange<Int>
    /// From the start of its first line to the end of its last, without the last line break.
    var range: NSRange

    /// Blocks whose look changes as a whole when the caret goes in: they show their Markdown then.
    var isSwappable: Bool {
        switch kind {
        case .table, .math, .mermaid: true
        default: false
        }
    }
}

enum TableAlignment: Hashable, Sendable {
    case leading, center, trailing
}

struct InlineSpan: Equatable {
    enum Kind: Equatable {
        case strong
        case emphasis
        case strikethrough
        case code
        case link(destination: String)
        /// `![alt](source)`, or an HTML `<img>` with the width it asks for.
        case image(source: String, alt: String, width: CGFloat?)
        case math(tex: String)
        case autolink(url: String)
        case footnoteReference(label: String)
        case escape
        /// `<!-- … -->` inside a line.
        case comment
        /// Any other HTML tag, which GitHub may draw but the editor shows as it is.
        case html
    }

    var kind: Kind
    /// All of it, punctuation included.
    var range: NSRange
    /// The punctuation, hidden unless the caret is in or next to the span.
    var markers: [NSRange]
    /// What you read.
    var content: NSRange

    /// Spans that are one thing on screen: the caret goes around them and a selection takes all or nothing.
    var isAtomic: Bool {
        switch kind {
        case .image: true
        default: false
        }
    }

    func shifted(by offset: Int) -> InlineSpan {
        InlineSpan(
            kind: kind,
            range: range.shifted(by: offset),
            markers: markers.map { $0.shifted(by: offset) },
            content: content.shifted(by: offset)
        )
    }
}

extension NSRange {
    func shifted(by offset: Int) -> NSRange { NSRange(location: location + offset, length: length) }

    /// Whether a caret at `location` touches the range: inside it or at either end.
    func touches(_ location: Int) -> Bool { location >= self.location && location <= upperBound }

    func strictlyContains(_ location: Int) -> Bool { location > self.location && location < upperBound }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        index >= 0 && index < count ? self[index] : nil
    }
}
