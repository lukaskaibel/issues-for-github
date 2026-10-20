#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Copy and paste as Markdown: a copy takes its Markdown whole (a heading's #s, a link's address), and an address
/// pasted over selected text links that text. Pictures can't be pasted, since GitHub has no way to upload them
/// from an app.
extension EditorController {
    /// What copying the selection puts on the pasteboard: its Markdown. Nil when nothing is selected.
    func clipping(cut: Bool) -> (range: NSRange, markdown: String)? {
        var range = expandSelection(selection)
        // A whole heading copies as a heading: its hidden #s come along.
        if !cut, range.length > 0, !document.lines.isEmpty {
            let line = document.lines[document.lineIndex(containing: range.location)]
            if case .heading(_, let marker) = line.kind, range.location == marker.upperBound, range.upperBound >= line.range.upperBound {
                range = NSRange(location: marker.location, length: range.upperBound - marker.location)
            }
        }
        guard range.length > 0 else { return nil }
        return (range, nsText.substring(with: range))
    }

    /// Copies the selection as Markdown. Returns false when there is nothing selected.
    @discardableResult
    func copySelection(cut: Bool) -> Bool {
        guard let clipping = clipping(cut: cut) else { return false }
        Platform.copy(clipping.markdown)
        if cut, isEditable { replace(clipping.range, with: "", select: NSRange(location: clipping.range.location, length: 0)) }
        return true
    }

    /// Pastes plain text over the selection. Returns false when there is no text to paste.
    @discardableResult
    func pasteText() -> Bool {
        #if os(macOS)
        guard let string = NSPasteboard.general.string(forType: .string) else { return false }
        #else
        guard let string = UIPasteboard.general.string else { return false }
        #endif
        pasteText(string, at: selection)
        return true
    }

    /// Plain text, with its line breaks made Unix ones.
    func pasteText(_ string: String, at target: NSRange) {
        let normalized = string.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        // A link pasted over selected text links that text.
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        if target.length > 0, !trimmed.contains(" "), let url = URL(string: trimmed), let scheme = url.scheme, ["http", "https", "mailto"].contains(scheme),
           !nsText.substring(with: target).contains("\n") {
            let label = nsText.substring(with: target)
            let link = "[\(label)](\(trimmed))"
            replace(target, with: link, select: NSRange(location: target.location + (link as NSString).length, length: 0))
            return
        }
        replace(target, with: normalized, select: NSRange(location: target.location + (normalized as NSString).length, length: 0))
    }
}
