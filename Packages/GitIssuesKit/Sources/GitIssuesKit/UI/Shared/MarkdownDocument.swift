import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// Markdown read the way GitHub and MarkdownUI read it, for what styling the text in place can't do: it finds
/// the tables, checklists, code and diagrams that only make sense drawn, where each checkbox sits so a click can tick
/// it, and the HTML comments GitHub hides.
struct MarkdownDocument {
    /// A checkbox, with the place of its mark (the space or x between the brackets) in the text's UTF-8 bytes.
    struct Checkbox: Equatable {
        var offset: Int
        var isChecked: Bool
    }

    let text: String
    private(set) var checkboxes: [Checkbox] = []
    private(set) var hasTable = false
    private(set) var hasCode = false
    private(set) var hasDiagram = false
    /// The HTML comments, as ranges of UTF-8 bytes.
    private var comments: [Range<Int>] = []

    /// Whether the text is better drawn than shown as styled Markdown.
    var isRich: Bool { hasTable || hasCode || !checkboxes.isEmpty }

    /// The link scheme that tags a checkbox with its number in `rendered(taggingCheckboxes:)`.
    static let checkboxScheme = "gi-checkbox"

    init(_ text: String) {
        self.text = text
        read()
    }

    /// The text with one checkbox ticked or unticked.
    func toggling(_ number: Int) -> String {
        guard checkboxes.indices.contains(number) else { return text }
        let checkbox = checkboxes[number]
        var bytes = Array(text.utf8)
        bytes[checkbox.offset] = checkbox.isChecked ? UInt8(ascii: " ") : UInt8(ascii: "x")
        return String(decoding: bytes, as: UTF8.self)
    }

    /// The text to draw. HTML comments are left out, as on GitHub. Tagged, each checkbox's item starts with an
    /// empty link to its number, which draws as nothing and lets a click on the box find its way back here.
    func rendered(taggingCheckboxes: Bool) -> String {
        var edits: [(range: Range<Int>, replacement: [UInt8])] = comments.map { ($0, []) }
        if taggingCheckboxes {
            let bytes = Array(text.utf8)
            for (number, checkbox) in checkboxes.enumerated() {
                let tag = Array("[](\(Self.checkboxScheme):\(number))".utf8)
                // After the space that has to follow the box, so the item's text doesn't start with one.
                var position = checkbox.offset + 2
                while position < bytes.count, bytes[position] == UInt8(ascii: " ") || bytes[position] == UInt8(ascii: "\t") {
                    position += 1
                }
                edits.append((position..<position, tag))
            }
        }
        guard !edits.isEmpty else { return text }
        // From the end, so every edit still finds its place; at the same place a removal goes before an insertion.
        edits.sort { ($0.range.lowerBound, $0.range.upperBound) > ($1.range.lowerBound, $1.range.upperBound) }
        var bytes = Array(text.utf8)
        for edit in edits {
            bytes.replaceSubrange(edit.range, with: edit.replacement)
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Whether a fenced code block holds a Mermaid diagram, from its info string (```` ```mermaid ````).
    static func isDiagram(fenceInfo: String?) -> Bool {
        fenceInfo?.split(whereSeparator: \.isWhitespace).first?.lowercased() == "mermaid"
    }

    /// The number of the checkbox a list item starts with, from the item's Markdown.
    static func checkboxNumber(inItem markdown: String) -> Int? {
        let prefix = "[](\(checkboxScheme):"
        guard markdown.hasPrefix(prefix) else { return nil }
        return Int(markdown.dropFirst(prefix.count).prefix { $0.isNumber })
    }

    // MARK: - Reading

    private mutating func read() {
        cmark_gfm_core_extensions_ensure_registered()
        guard let parser = cmark_parser_new(CMARK_OPT_DEFAULT) else { return }
        defer { cmark_parser_free(parser) }
        // The same extensions as MarkdownUI, so both find the same things.
        for name in ["autolink", "strikethrough", "tagfilter", "tasklist", "table"] {
            if let syntaxExtension = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, syntaxExtension)
            }
        }
        let bytes = Array(text.utf8)
        cmark_parser_feed(parser, text, bytes.count)
        guard let document = cmark_parser_finish(parser) else { return }
        defer { cmark_node_free(document) }

        let lines = Lines(bytes)
        // Inline comments are found by their text, after the one before.
        var searchFrom = 0
        let iterator = cmark_iter_new(document)
        defer { cmark_iter_free(iterator) }
        while true {
            let event = cmark_iter_next(iterator)
            if event == CMARK_EVENT_DONE { break }
            guard event == CMARK_EVENT_ENTER, let node = cmark_iter_get_node(iterator) else { continue }
            switch String(cString: cmark_node_get_type_string(node)) {
            case "table":
                hasTable = true
            case "tasklist":
                guard let start = lines.offset(line: cmark_node_get_start_line(node), column: cmark_node_get_start_column(node)),
                      let offset = Self.markOffset(in: bytes, from: start) else { continue }
                checkboxes.append(Checkbox(offset: offset, isChecked: cmark_gfm_extensions_get_tasklist_item_checked(node)))
            case "code_block":
                hasCode = true
                if Self.isDiagram(fenceInfo: cmark_node_get_fence_info(node).map { String(cString: $0) }) { hasDiagram = true }
            case "html_block":
                // cmark's end line for HTML blocks falls one short, so the block's own lines say where it ends.
                let literal = cmark_node_get_literal(node).map { String(cString: $0) } ?? ""
                let first = cmark_node_get_start_line(node)
                let count = Int32(literal.utf8.count { $0 == UInt8(ascii: "\n") } + (literal.hasSuffix("\n") ? 0 : 1))
                guard let range = lines.range(from: first, to: first + max(count, 1) - 1) else { continue }
                comments += Self.comments(in: bytes, range)
            case "html_inline":
                guard let literal = cmark_node_get_literal(node).map({ Array(String(cString: $0).utf8) }),
                      literal.starts(with: Self.commentOpen),
                      let block = Self.enclosingBlock(of: node),
                      let range = lines.range(from: cmark_node_get_start_line(block), to: cmark_node_get_end_line(block)),
                      let found = Self.find(literal, in: bytes, max(range.lowerBound, searchFrom)..<range.upperBound)
                else { continue }
                comments.append(found)
                searchFrom = found.upperBound
            default:
                break
            }
        }
    }

    private static let commentOpen = Array("<!--".utf8)
    private static let commentClose = Array("-->".utf8)

    /// The mark of the checkbox in a task list item that starts at `start`.
    private static func markOffset(in bytes: [UInt8], from start: Int) -> Int? {
        var index = start
        while index + 2 < bytes.count, bytes[index] != UInt8(ascii: "\n") {
            if bytes[index] == UInt8(ascii: "["), bytes[index + 2] == UInt8(ascii: "]"),
               [UInt8(ascii: " "), UInt8(ascii: "x"), UInt8(ascii: "X")].contains(bytes[index + 1]) {
                return index + 1
            }
            index += 1
        }
        return nil
    }

    /// The HTML comments in an HTML block. One left open runs to the end of the block, as GitHub reads it.
    private static func comments(in bytes: [UInt8], _ range: Range<Int>) -> [Range<Int>] {
        var found: [Range<Int>] = []
        var from = range.lowerBound
        while let open = find(commentOpen, in: bytes, from..<range.upperBound) {
            let close = find(commentClose, in: bytes, open.upperBound..<range.upperBound)
            let end = close?.upperBound ?? range.upperBound
            found.append(open.lowerBound..<end)
            from = end
        }
        return found
    }

    /// The nearest block around an inline node, which is the one with a place in the text.
    private static func enclosingBlock(of node: UnsafeMutablePointer<cmark_node>) -> UnsafeMutablePointer<cmark_node>? {
        var current = cmark_node_parent(node)
        while let candidate = current, cmark_node_get_start_line(candidate) == 0 {
            current = cmark_node_parent(candidate)
        }
        return current
    }

    private static func find(_ needle: [UInt8], in bytes: [UInt8], _ range: Range<Int>) -> Range<Int>? {
        guard !needle.isEmpty, range.count >= needle.count else { return nil }
        var index = range.lowerBound
        while index + needle.count <= range.upperBound {
            if bytes[index] == needle[0], bytes[index..<index + needle.count].elementsEqual(needle) {
                return index..<index + needle.count
            }
            index += 1
        }
        return nil
    }

    /// Where lines start, to turn cmark's lines and columns (1-based, columns in bytes) into offsets.
    private struct Lines {
        var starts: [Int]
        var count: Int

        init(_ bytes: [UInt8]) {
            starts = [0] + bytes.indices.filter { bytes[$0] == UInt8(ascii: "\n") }.map { $0 + 1 }
            count = bytes.count
        }

        func offset(line: Int32, column: Int32) -> Int? {
            guard line >= 1, Int(line) <= starts.count, column >= 1 else { return nil }
            return min(starts[Int(line) - 1] + Int(column) - 1, count)
        }

        /// Whole lines, without the last line break.
        func range(from first: Int32, to last: Int32) -> Range<Int>? {
            guard first >= 1, last >= first, Int(last) <= starts.count else { return nil }
            let end = Int(last) < starts.count ? starts[Int(last)] - 1 : count
            return starts[Int(first) - 1]..<max(end, starts[Int(first) - 1])
        }
    }
}
