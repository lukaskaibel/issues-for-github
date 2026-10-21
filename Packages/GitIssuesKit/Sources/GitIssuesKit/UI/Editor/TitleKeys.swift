import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension View {
    /// The title over a Markdown editor (`TitleLink`): Tab, ↓ on its last line and → at its end go on to the start of
    /// the text, as from one line to the next, and the text's ↑, ← and Delete come back to its end. Elsewhere in the
    /// title the keys do what they always do. `focus` puts the keyboard focus in it on iPhone and iPad; the Mac makes
    /// the text field behind it first responder itself, as SwiftUI's focus requests are sometimes dropped there.
    func titleOf(_ link: TitleLink?, focus: @escaping () -> Void) -> some View {
        onKeyPress(keys: [.tab, .downArrow, .rightArrow], phases: .down) { press in
            guard let link, press.modifiers.isDisjoint(with: [.shift, .control, .option, .command]),
                  TitleCaret.leaves(by: press.key, of: link) else { return .ignored }
            link.enterText()
            return .handled
        }
        #if os(macOS)
        .background(TitleAnchor(link: link))
        #else
        .onAppear {
            link?.enterTitle = {
                focus()
                TitleCaret.moveToEnd()
            }
        }
        #endif
    }
}

#if os(macOS)
/// Sits behind a title's text field, to find it and put the caret at its end.
private struct TitleAnchor: NSViewRepresentable {
    var link: TitleLink?

    func makeNSView(context: Context) -> AnchorView { AnchorView() }

    func updateNSView(_ view: AnchorView, context: Context) {
        link?.enterTitle = { [weak view] in view?.focusAtEnd() }
        link?.titleView = view
    }

    final class AnchorView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func focusAtEnd() {
            guard let window, let field = textField(in: window), window.makeFirstResponder(field) else { return }
            let editor = field.currentEditor()
            editor?.selectedRange = NSRange(location: (editor?.string as NSString?)?.length ?? 0, length: 0)
        }

        /// The editable text field whose frame contains this anchor's centre.
        private func textField(in window: NSWindow) -> NSTextField? {
            guard let content = window.contentView else { return nil }
            let center = convert(NSPoint(x: bounds.midX, y: bounds.midY), to: nil)
            var found: NSTextField?
            func search(_ view: NSView) {
                guard found == nil, !view.isHidden else { return }
                if let field = view as? NSTextField, field.isEditable, field.convert(field.bounds, to: nil).contains(center) {
                    found = field
                    return
                }
                view.subviews.forEach(search)
            }
            search(content)
            return found
        }
    }
}
#endif

/// Where the caret is in the title being typed in, which SwiftUI's text fields don't tell: read from the text view that
/// has the keyboard focus.
@MainActor
enum TitleCaret {
    /// Whether a key leaves the title for the text below it.
    static func leaves(by key: KeyEquivalent, of link: TitleLink) -> Bool {
        if key == .tab { return true }
        #if os(macOS)
        let field = focusedField(in: link.titleView?.window ?? NSApp.keyWindow)
        #else
        let field = focusedField
        #endif
        guard let field, field.selection.length == 0 else { return false }
        switch key {
        case .rightArrow: return field.selection.location == field.length
        case .downArrow: return field.isOnLastLine
        default: return false
        }
    }

    #if os(iOS)
    /// Puts the caret at the end of the title that just got the focus.
    static func moveToEnd() {
        // Once the field has taken the focus.
        DispatchQueue.main.async {
            guard let input = firstResponder as? (UIResponder & UITextInput) else { return }
            input.selectedTextRange = input.textRange(from: input.endOfDocument, to: input.endOfDocument)
        }
    }
    #endif

    private struct Field {
        var selection: NSRange
        var length: Int
        var isOnLastLine: Bool
    }

    #if os(macOS)
    /// The field editor of the text field being typed in.
    private static func focusedField(in window: NSWindow?) -> Field? {
        guard let editor = window?.firstResponder as? NSTextView, editor.isFieldEditor else { return nil }
        let length = (editor.string as NSString).length
        let selection = editor.selectedRange()
        var isOnLastLine = true
        if length > 0, let layout = editor.layoutManager, let container = editor.textContainer {
            layout.ensureLayout(for: container)
            let caret = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: min(selection.location, length - 1)), effectiveRange: nil)
            let last = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: length - 1), effectiveRange: nil)
            isOnLastLine = caret.minY >= last.minY - 0.5
        }
        return Field(selection: selection, length: length, isOnLastLine: isOnLastLine)
    }
    #else
    private static weak var found: UIResponder?

    /// The text field or view with the keyboard focus.
    fileprivate static var firstResponder: UIResponder? {
        found = nil
        UIApplication.shared.sendAction(#selector(UIResponder.giFindFirstResponder(_:)), to: nil, from: nil, for: nil)
        return found
    }

    fileprivate static func report(_ responder: UIResponder) {
        found = responder
    }

    private static var focusedField: Field? {
        guard let input = firstResponder as? (UIResponder & UITextInput), let range = input.selectedTextRange else { return nil }
        let start = input.offset(from: input.beginningOfDocument, to: range.start)
        let end = input.offset(from: input.beginningOfDocument, to: range.end)
        let length = input.offset(from: input.beginningOfDocument, to: input.endOfDocument)
        let isOnLastLine = input.caretRect(for: range.end).minY >= input.caretRect(for: input.endOfDocument).minY - 1
        return Field(selection: NSRange(location: start, length: end - start), length: length, isOnLastLine: isOnLastLine)
    }
    #endif
}

#if os(iOS)
extension UIResponder {
    /// Sent to the first responder, which tells `TitleCaret` it is.
    @objc func giFindFirstResponder(_ sender: Any?) {
        TitleCaret.report(self)
    }
}
#endif
