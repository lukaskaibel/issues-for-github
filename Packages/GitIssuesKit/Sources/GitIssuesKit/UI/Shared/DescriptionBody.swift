import SwiftUI

/// An issue description. Plain text is the editor itself, so a click puts the caret right where it lands. Text
/// with a table, a checklist, a code block or a Mermaid diagram is drawn the way GitHub draws it instead, since
/// none of those read well as Markdown; its checkboxes tick with a click. A click anywhere else on it brings up the editor, and
/// when you leave the editor it is drawn again.
struct DescriptionBody<Editor: View>: View {
    var text: String
    var isEditable: Bool
    var onSave: (String) -> Void
    /// Whether the editor is being typed in.
    @Binding var editing: Bool
    /// The editor; `true` when it comes up from a click on the drawn text and should take the keyboard focus.
    @ViewBuilder var editor: (_ takesFocus: Bool) -> Editor
    @State private var showsEditor = false

    var body: some View {
        let text = Diff3.normalize(self.text)
        if !showsEditor, !editing, MarkdownDocument(text).isRich {
            MarkdownText(text: text, fontSize: MarkdownStyler.fontSize, isSelectable: false, onChange: isEditable ? onSave : nil)
                .contentShape(Rectangle())
                .onTapGesture {
                    if isEditable { showsEditor = true }
                }
                #if os(macOS)
                .pointerStyle(isEditable ? .horizontalText : nil)
                #endif
                .accessibilityElement(children: .contain)
                .accessibilityLabel(.description)
                .accessibilityIdentifier("issue-description")
                .accessibilityAction(named: Text(.editDescriptionAction)) {
                    if isEditable { showsEditor = true }
                }
        } else {
            editor(showsEditor)
                .onChange(of: editing) { _, editing in
                    if !editing { showsEditor = false }
                }
        }
    }
}
