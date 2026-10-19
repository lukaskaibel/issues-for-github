import Foundation

/// A text view that types Markdown by the rules of `MarkdownEditing`: the Mac's and the iPhone's and iPad's editors
/// give their text and selection, apply the result as one undoable edit, and get the buttons and keys on top.
@MainActor
protocol MarkdownTextInput: AnyObject {
    var markdownState: MarkdownEditing.State { get }
    /// Puts the new text in as one undoable edit and selects what the rule selected.
    func apply(_ state: MarkdownEditing.State)
    /// What the last press of a style unwrapped, for the next press to style it again.
    var unwrapped: MarkdownUnwrapped? { get set }
}

struct MarkdownUnwrapped {
    var style: MarkdownSyntax.Style
    var range: NSRange
    var text: String
}

extension MarkdownTextInput {
    /// Runs a rule; false when it leaves the keystroke to the text view.
    @discardableResult
    func perform(_ rule: (MarkdownEditing.State) -> MarkdownEditing.State?) -> Bool {
        let state = markdownState
        guard let result = rule(state) else { return false }
        if result != state { apply(result) }
        return true
    }

    func toggle(_ style: MarkdownSyntax.Style) {
        let state = markdownState
        let restoring = unwrapped.flatMap { $0.style == style && $0.text == state.text ? $0.range : nil }
        let result = MarkdownEditing.toggle(style, in: state, restoring: restoring)
        apply(result.state)
        unwrapped = result.unwrapped.map { MarkdownUnwrapped(style: style, range: $0, text: result.state.text) }
    }

    func toggle(_ block: MarkdownEditing.Block) {
        apply(MarkdownEditing.toggle(block, in: markdownState))
    }
}
