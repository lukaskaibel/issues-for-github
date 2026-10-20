#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Something drawn in place of Markdown: a checkbox, a picture, a rendered table. It sits on the first character of
/// the Markdown it stands for; that character is laid out as an empty box the object's size and the rest of the
/// Markdown is hidden, so the source stays in the text exactly as it is on GitHub.
final class EditorObject: NSObject {
    enum Kind {
        case bullet(level: Int)
        case checkbox(checked: Bool)
        case quoteBar
        /// A picture from the web, at `width` points when the HTML asks for that.
        case image(url: URL?, source: String, inline: Bool, width: CGFloat?)
        case horizontalRule
        case table(TableModel)
        case mermaid(source: String)
        case mathBlock(tex: String)
        case mathInline(tex: String)
        case callout(type: String, label: String)
        /// After a link's text: a pencil that edits where it goes.
        case linkEdit
    }

    let kind: Kind
    /// How far before the object's character the Markdown it stands for starts, and how long it is. Relative, so
    /// the object stays right when text before it moves it along.
    let offset: Int
    let length: Int
    /// Shown as its Markdown when the caret is next to it (maths, a rule, an alert's type).
    let revealable: Bool

    /// `range` is where the Markdown is now; `at` is the character the object goes on.
    init(_ kind: Kind, range: NSRange, at index: Int? = nil, revealable: Bool = false) {
        self.kind = kind
        self.offset = (index ?? range.location) - range.location
        self.length = range.length
        self.revealable = revealable
    }

    /// The Markdown the object stands for, given the character it is on.
    func range(at index: Int) -> NSRange {
        NSRange(location: index - offset, length: length)
    }

    /// Takes a line of its own and the whole width of the text.
    var isBlock: Bool {
        switch kind {
        case .image(_, _, let inline, _): !inline
        case .horizontalRule, .table, .mermaid, .mathBlock: true
        default: false
        }
    }
}

/// A box drawn behind text. One instance covers all the text it goes around, so where it starts and ends is the
/// run of characters that carry this very instance; that moves along with the text when text before it changes.
final class Decoration: NSObject {
    enum Kind: Equatable {
        case codeBlock(language: String, active: Bool, preview: Preview? = nil)
        case callout(type: String)
        case inlineCode
    }

    /// What a diagram or formula being edited looks like, drawn under the box with its source.
    enum Preview: Equatable {
        case diagram(source: String)
        case math(tex: String)
    }

    let kind: Kind

    init(_ kind: Kind) {
        self.kind = kind
    }
}

/// Where a click on a link goes. Like a decoration, one instance covers the whole link.
final class LinkTarget: NSObject {
    let url: String

    init(_ url: String) {
        self.url = url
    }
}

extension NSAttributedString {
    /// The run of characters around `index` that carry this very object for `key`.
    func extent(of key: NSAttributedString.Key, at index: Int) -> (value: AnyObject, range: NSRange)? {
        guard index >= 0, index < length else { return nil }
        var range = NSRange()
        guard let value = attribute(key, at: index, longestEffectiveRange: &range, in: NSRange(location: 0, length: length)) as AnyObject? else { return nil }
        return (value, range)
    }
}
