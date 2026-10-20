import Foundation
import Observation

/// What the caret is in, as the bar above the keyboard shows it on its left: the styles it is in, the checkbox of its
/// line, whether its list item can move in or out, and the link it is on.
@MainActor
@Observable
final class CaretContext {
    var context = MarkdownEditing.Context()
}

/// The typing rules of `MarkdownEditing` applied to the editor: each takes the text and the selection and gives back
/// new ones, which go in as one undoable edit, with the characters that stay easing from their old look.
extension EditorController: MarkdownTextInput {
    var markdownState: MarkdownEditing.State {
        MarkdownEditing.State(text, selection: selection)
    }

    func apply(_ state: MarkdownEditing.State) {
        let (range, replacement) = MarkdownEditing.difference(from: text, to: state.text)
        // The rule's selection exactly, not grown to take in the marks around it.
        selectsExactly = true
        defer { selectsExactly = false }
        if range.length > 0 || !replacement.isEmpty {
            styleAnimator.keep(storage, replacing: range, with: replacement)
            replace(range, with: replacement, select: state.selection)
        } else {
            setSelection(state.selection)
        }
    }

    /// While a word is still being composed (Japanese, Chinese), keys belong to the input method.
    var isComposing: Bool {
        #if os(macOS)
        textView.hasMarkedText()
        #else
        textView.markedTextRange != nil
        #endif
    }

    /// Brings the bar's buttons for where the caret is up to date.
    func updateCaretContext() {
        #if os(iOS)
        let context = isFocused && isEditable ? MarkdownEditing.context(in: markdownState) : MarkdownEditing.Context()
        if caretContext.context != context { caretContext.context = context }
        #endif
    }
}
