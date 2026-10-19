import Foundation

/// Inline Markdown inside one line: emphasis by CommonMark's delimiter rules, code spans, links, images, maths,
/// autolinks, footnote references, backslash escapes and the HTML GitHub allows (comments, `<img>`, other tags).
enum InlineParser {
    static func spans(in u: [UInt16], range: NSRange) -> [InlineSpan] {
        guard range.length > 0 else { return [] }
        var result = parse(u, range)
        result.sort { $0.range.location < $1.range.location || ($0.range.location == $1.range.location && $0.range.length > $1.range.length) }
        return result
    }

    private struct Delimiter {
        var character: UInt16
        var start: Int
        var length: Int
        let originalLength: Int
        let canOpen: Bool
        let canClose: Bool
    }

    private static func parse(_ u: [UInt16], _ range: NSRange) -> [InlineSpan] {
        var spans: [InlineSpan] = []
        var delimiters: [Delimiter] = []
        let end = range.upperBound
        var i = range.location

        while i < end {
            let c = u[i]
            switch c {
            case 92: // \ escape
                if i + 1 < end, isASCIIPunctuation(u[i + 1]) {
                    spans.append(InlineSpan(kind: .escape, range: NSRange(location: i, length: 2), markers: [NSRange(location: i, length: 1)], content: NSRange(location: i + 1, length: 1)))
                    i += 2
                    continue
                }
                i += 1

            case 96: // ` code span
                let run = runLength(u, i, end, 96)
                if let close = closingBackticks(u, from: i + run, end: end, length: run) {
                    spans.append(InlineSpan(
                        kind: .code,
                        range: NSRange(location: i, length: close + run - i),
                        markers: [NSRange(location: i, length: run), NSRange(location: close, length: run)],
                        content: NSRange(location: i + run, length: close - i - run)
                    ))
                    i = close + run
                } else {
                    i += run
                }

            case 36: // $ maths
                if let span = math(u, i, end) {
                    spans.append(span)
                    i = span.range.upperBound
                } else {
                    i += 1
                }

            case 33: // ! image
                if i + 1 < end, u[i + 1] == 91, let link = linkLike(u, i + 1, end) {
                    spans.append(InlineSpan(
                        kind: .image(source: link.destination, alt: string(u, link.text), width: nil),
                        range: NSRange(location: i, length: link.end - i),
                        markers: [NSRange(location: i, length: 2), NSRange(location: link.text.upperBound, length: link.end - link.text.upperBound)],
                        content: link.text
                    ))
                    i = link.end
                } else {
                    i += 1
                }

            case 91: // [ link, footnote reference
                if i + 1 < end, u[i + 1] == 94, let close = footnoteClose(u, i + 2, end) {
                    let label = NSRange(location: i + 2, length: close - i - 2)
                    spans.append(InlineSpan(
                        kind: .footnoteReference(label: string(u, label)),
                        range: NSRange(location: i, length: close + 1 - i),
                        markers: [NSRange(location: i, length: 2), NSRange(location: close, length: 1)],
                        content: label
                    ))
                    i = close + 1
                } else if let link = linkLike(u, i, end) {
                    spans.append(InlineSpan(
                        kind: .link(destination: link.destination),
                        range: NSRange(location: i, length: link.end - i),
                        markers: [NSRange(location: i, length: 1), NSRange(location: link.text.upperBound, length: link.end - link.text.upperBound)],
                        content: link.text
                    ))
                    spans.append(contentsOf: parse(u, link.text))
                    i = link.end
                } else {
                    i += 1
                }

            case 60: // < comment, autolink or HTML
                if let span = html(u, i, end) {
                    spans.append(span)
                    i = span.range.upperBound
                    continue
                }
                if let close = (i + 1..<end).first(where: { u[$0] == 62 || u[$0] == 32 || u[$0] == 60 }), u[close] == 62, close > i + 1 {
                    let text = string(u, NSRange(location: i + 1, length: close - i - 1))
                    if text.hasPrefix("http://") || text.hasPrefix("https://") || text.hasPrefix("mailto:") || (text.contains("@") && !text.contains("/")) {
                        spans.append(InlineSpan(
                            kind: .autolink(url: text.contains("@") && !text.hasPrefix("mailto:") ? "mailto:" + text : text),
                            range: NSRange(location: i, length: close + 1 - i),
                            markers: [NSRange(location: i, length: 1), NSRange(location: close, length: 1)],
                            content: NSRange(location: i + 1, length: close - i - 1)
                        ))
                        i = close + 1
                        continue
                    }
                }
                i += 1

            case 104: // h: a bare http(s) address
                if let urlEnd = bareURL(u, i, range) {
                    let content = NSRange(location: i, length: urlEnd - i)
                    spans.append(InlineSpan(kind: .autolink(url: string(u, content)), range: content, markers: [], content: content))
                    i = urlEnd
                } else {
                    i += 1
                }

            case 42, 95, 126: // * _ ~
                let run = runLength(u, i, end, c)
                let before: UInt16? = i > range.location ? u[i - 1] : nil
                let after: UInt16? = i + run < end ? u[i + run] : nil
                let flanks = flanking(before: before, after: after)
                var canOpen = flanks.left
                var canClose = flanks.right
                if c == 95 {
                    canOpen = flanks.left && (!flanks.right || isPunctuation(before))
                    canClose = flanks.right && (!flanks.left || isPunctuation(after))
                }
                // ~strike~ and ~~strike~~, as GitHub has both.
                if c != 126 || run <= 2 {
                    delimiters.append(Delimiter(character: c, start: i, length: run, originalLength: run, canOpen: canOpen, canClose: canClose))
                }
                i += run

            default:
                i += 1
            }
        }

        spans.append(contentsOf: emphasis(&delimiters))
        return spans
    }

    // MARK: - Emphasis

    /// CommonMark's "process emphasis": pairs closers with the nearest fitting opener, inner delimiters first.
    private static func emphasis(_ delimiters: inout [Delimiter]) -> [InlineSpan] {
        var spans: [InlineSpan] = []
        var closerIndex = 0
        while closerIndex < delimiters.count {
            let closer = delimiters[closerIndex]
            guard closer.canClose, closer.length > 0 else { closerIndex += 1; continue }
            var openerIndex = closerIndex - 1
            var found: Int?
            while openerIndex >= 0 {
                let opener = delimiters[openerIndex]
                if opener.character == closer.character, opener.canOpen, opener.length > 0 {
                    if closer.character == 126 {
                        if opener.length == closer.length { found = openerIndex; break }
                    } else {
                        let ruleOfThree = (opener.canClose || closer.canOpen)
                            && (opener.originalLength + closer.originalLength) % 3 == 0
                            && !(opener.originalLength % 3 == 0 && closer.originalLength % 3 == 0)
                        if !ruleOfThree { found = openerIndex; break }
                    }
                }
                openerIndex -= 1
            }
            guard let opener = found else { closerIndex += 1; continue }

            let use: Int
            let kind: InlineSpan.Kind
            if closer.character == 126 {
                use = closer.length
                kind = .strikethrough
            } else {
                use = delimiters[opener].length >= 2 && closer.length >= 2 ? 2 : 1
                kind = use == 2 ? .strong : .emphasis
            }
            let openMarker = NSRange(location: delimiters[opener].start + delimiters[opener].length - use, length: use)
            let closeMarker = NSRange(location: closer.start, length: use)
            spans.append(InlineSpan(
                kind: kind,
                range: NSRange(location: openMarker.location, length: closeMarker.upperBound - openMarker.location),
                markers: [openMarker, closeMarker],
                content: NSRange(location: openMarker.upperBound, length: closeMarker.location - openMarker.upperBound)
            ))
            delimiters[opener].length -= use
            delimiters[closerIndex].start += use
            delimiters[closerIndex].length -= use
            // Delimiters between the two can no longer pair across them.
            if closerIndex - opener > 1 {
                delimiters.removeSubrange((opener + 1)..<closerIndex)
                closerIndex = opener + 1
            }
            if delimiters[opener].length == 0 {
                delimiters.remove(at: opener)
                closerIndex -= 1
            }
            if delimiters[closerIndex].length == 0 {
                delimiters.remove(at: closerIndex)
            }
        }
        return spans
    }

    private static func flanking(before: UInt16?, after: UInt16?) -> (left: Bool, right: Bool) {
        let afterSpace = after.map(isWhitespace) ?? true
        let beforeSpace = before.map(isWhitespace) ?? true
        let afterPunct = isPunctuation(after)
        let beforePunct = isPunctuation(before)
        let left = !afterSpace && (!afterPunct || beforeSpace || beforePunct)
        let right = !beforeSpace && (!beforePunct || afterSpace || afterPunct)
        return (left, right)
    }

    // MARK: - HTML

    /// `<!-- … -->`, `<img …>` or another tag, starting at the `<`.
    private static func html(_ u: [UInt16], _ i: Int, _ end: Int) -> InlineSpan? {
        // A comment, up to `-->` on the same line.
        if i + 3 < end, u[i + 1] == 33, u[i + 2] == 45, u[i + 3] == 45 {
            var k = i + 4
            while k + 2 < end {
                if u[k] == 45, u[k + 1] == 45, u[k + 2] == 62 {
                    return InlineSpan(kind: .comment, range: NSRange(location: i, length: k + 3 - i),
                                      markers: [NSRange(location: i, length: 4), NSRange(location: k, length: 3)],
                                      content: NSRange(location: i + 4, length: k - i - 4))
                }
                k += 1
            }
            return nil
        }
        // A tag: `<name`, `</name`, with attributes up to `>`, quotes respected.
        var k = i + 1
        if k < end, u[k] == 47 { k += 1 }
        guard k < end, isLetter(u[k]) else { return nil }
        let nameStart = k
        while k < end, isLetter(u[k]) || (48...57).contains(u[k]) || u[k] == 45 { k += 1 }
        let name = string(u, NSRange(location: nameStart, length: k - nameStart)).lowercased()
        guard k < end, u[k] == 62 || u[k] == 32 || u[k] == 47 || u[k] == 9 else { return nil }
        var quote: UInt16?
        while k < end {
            if let open = quote {
                if u[k] == open { quote = nil }
            } else if u[k] == 34 || u[k] == 39 {
                quote = u[k]
            } else if u[k] == 62 {
                break
            } else if u[k] == 60 {
                return nil
            }
            k += 1
        }
        guard k < end, u[k] == 62 else { return nil }
        let range = NSRange(location: i, length: k + 1 - i)
        if name == "img", u[i + 1] != 47, let source = attributes(in: string(u, range))["src"], !source.isEmpty {
            let attributes = attributes(in: string(u, range))
            let width = attributes["width"].flatMap { Double($0.trimmingCharacters(in: CharacterSet(charactersIn: "px"))) }.map { CGFloat($0) }
            return InlineSpan(kind: .image(source: source, alt: attributes["alt"] ?? "", width: width), range: range,
                              markers: [range], content: NSRange(location: range.upperBound, length: 0))
        }
        return InlineSpan(kind: .html, range: range, markers: [], content: range)
    }

    /// The attributes of a tag, `name="value"`, `name='value'` or `name=value`, by lowercased name.
    static func attributes(in tag: String) -> [String: String] {
        var result: [String: String] = [:]
        let pattern = #/([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))/#
        for match in tag.matches(of: pattern) {
            let value = match.output.2 ?? match.output.3 ?? match.output.4 ?? ""
            result[match.output.1.lowercased()] = String(value)
        }
        return result
    }

    // MARK: - Pieces

    private static func runLength(_ u: [UInt16], _ start: Int, _ end: Int, _ c: UInt16) -> Int {
        var i = start
        while i < end, u[i] == c { i += 1 }
        return i - start
    }

    private static func closingBackticks(_ u: [UInt16], from: Int, end: Int, length: Int) -> Int? {
        var i = from
        while i < end {
            if u[i] == 96 {
                let run = runLength(u, i, end, 96)
                if run == length { return i }
                i += run
            } else {
                i += 1
            }
        }
        return nil
    }

    private static func footnoteClose(_ u: [UInt16], _ from: Int, _ end: Int) -> Int? {
        var i = from
        while i < end {
            if u[i] == 93 { return i > from ? i : nil }
            if u[i] == 32 || u[i] == 91 { return nil }
            i += 1
        }
        return nil
    }

    private static func math(_ u: [UInt16], _ i: Int, _ end: Int) -> InlineSpan? {
        if i > 0, u[i - 1] == 92 { return nil }
        // $$…$$ inside a line.
        if i + 1 < end, u[i + 1] == 36 {
            var k = i + 2
            while k + 1 < end {
                if u[k] == 36, u[k + 1] == 36, k > i + 2 {
                    let content = NSRange(location: i + 2, length: k - i - 2)
                    return InlineSpan(kind: .math(tex: string(u, content)), range: NSRange(location: i, length: k + 2 - i),
                                      markers: [NSRange(location: i, length: 2), NSRange(location: k, length: 2)], content: content)
                }
                k += 1
            }
            return nil
        }
        // $…$: no space just inside the dollars and no digit right after the closing one, so prices stay prices.
        guard i + 1 < end, !isWhitespace(u[i + 1]) else { return nil }
        var k = i + 1
        while k < end {
            if u[k] == 92 { k += 2; continue }
            if u[k] == 36 {
                if !isWhitespace(u[k - 1]), k + 1 >= end || !(u[k + 1] >= 48 && u[k + 1] <= 57), k > i + 1 {
                    let content = NSRange(location: i + 1, length: k - i - 1)
                    return InlineSpan(kind: .math(tex: string(u, content)), range: NSRange(location: i, length: k + 1 - i),
                                      markers: [NSRange(location: i, length: 1), NSRange(location: k, length: 1)], content: content)
                }
                return nil
            }
            k += 1
        }
        return nil
    }

    private struct LinkParts {
        var text: NSRange
        var destination: String
        var end: Int
    }

    /// `[text](destination "title")` starting at the `[`.
    private static func linkLike(_ u: [UInt16], _ open: Int, _ end: Int) -> LinkParts? {
        var depth = 0
        var i = open
        var closeBracket: Int?
        while i < end {
            let c = u[i]
            if c == 92 { i += 2; continue }
            if c == 96 {
                let run = runLength(u, i, end, 96)
                if let close = closingBackticks(u, from: i + run, end: end, length: run) { i = close + run; continue }
                i += run
                continue
            }
            if c == 91 { depth += 1 }
            if c == 93 {
                depth -= 1
                if depth == 0 { closeBracket = i; break }
            }
            i += 1
        }
        guard let close = closeBracket, close + 1 < end, u[close + 1] == 40 else { return nil }
        var j = close + 2
        var parens = 1
        var angle = false
        while j < end {
            let c = u[j]
            if c == 92 { j += 2; continue }
            if c == 60 { angle = true }
            if c == 62 { angle = false }
            if !angle {
                if c == 40 { parens += 1 }
                if c == 41 {
                    parens -= 1
                    if parens == 0 { break }
                }
            }
            j += 1
        }
        guard j < end, u[j] == 41 else { return nil }
        var inside = string(u, NSRange(location: close + 2, length: j - close - 2)).trimmingCharacters(in: .whitespaces)
        if inside.hasPrefix("<"), let closeAngle = inside.firstIndex(of: ">") {
            inside = String(inside[inside.index(after: inside.startIndex)..<closeAngle])
        } else if let space = inside.firstIndex(where: { $0 == " " || $0 == "\t" }) {
            inside = String(inside[..<space])
        }
        return LinkParts(text: NSRange(location: open + 1, length: close - open - 1), destination: inside, end: j + 1)
    }

    private static func bareURL(_ u: [UInt16], _ i: Int, _ range: NSRange) -> Int? {
        let end = range.upperBound
        if i > range.location, isAlphanumeric(u[i - 1]) { return nil }
        let https: [UInt16] = Array("https://".utf16)
        let http: [UInt16] = Array("http://".utf16)
        let prefix: Int
        if i + https.count <= end, Array(u[i..<i + https.count]) == https {
            prefix = https.count
        } else if i + http.count <= end, Array(u[i..<i + http.count]) == http {
            prefix = http.count
        } else {
            return nil
        }
        var j = i + prefix
        while j < end, !isWhitespace(u[j]), u[j] != 60 { j += 1 }
        // Punctuation that ends a sentence isn't part of the address, nor is a closing parenthesis without an
        // opening one in the address.
        while j > i + prefix {
            let last = u[j - 1]
            if [46, 44, 59, 58, 33, 63, 34, 39, 42, 95].contains(last) { j -= 1; continue }
            if last == 41 {
                let slice = u[i..<j]
                if slice.filter({ $0 == 40 }).count < slice.filter({ $0 == 41 }).count { j -= 1; continue }
            }
            break
        }
        return j > i + prefix ? j : nil
    }

    // MARK: - Characters

    static func string(_ u: [UInt16], _ range: NSRange) -> String {
        String(decoding: u[range.location..<range.upperBound], as: UTF16.self)
    }

    private static func isWhitespace(_ c: UInt16) -> Bool {
        c == 32 || c == 9 || c == 10 || c == 13 || c == 0xA0 || c == 0x2028 || c == 0x3000
    }

    private static func isASCIIPunctuation(_ c: UInt16) -> Bool {
        (33...47).contains(c) || (58...64).contains(c) || (91...96).contains(c) || (123...126).contains(c)
    }

    private static func isPunctuation(_ c: UInt16?) -> Bool {
        guard let c else { return false }
        if c < 128 { return isASCIIPunctuation(c) }
        guard let scalar = UnicodeScalar(c) else { return false }
        return CharacterSet.punctuationCharacters.contains(scalar) || CharacterSet.symbols.contains(scalar)
    }

    private static func isLetter(_ c: UInt16) -> Bool {
        (65...90).contains(c) || (97...122).contains(c)
    }

    private static func isAlphanumeric(_ c: UInt16) -> Bool {
        (48...57).contains(c) || (65...90).contains(c) || (97...122).contains(c)
    }
}
