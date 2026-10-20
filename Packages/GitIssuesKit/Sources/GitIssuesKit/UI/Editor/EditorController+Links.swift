#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SwiftUI

/// A link's address is never part of the text you see: the pencil after it opens a popover (an alert on iPhone and
/// iPad) to change it, open it or take the link off.
extension EditorController {
    /// `range` is the whole link, `[text](address)`, as it is now. A new link's text is selected afterwards when
    /// `selectsText`, to type over it.
    func editLink(at range: NSRange, isNew: Bool = false, selectsText: Bool = false) {
        guard let link = linkSpan(at: range.location) else { return }
        let address = nsText.substring(with: destinationRange(of: link))
        let location = range.location
        let finish: (LinkEditorModel.Outcome) -> Void = { [weak self] outcome in
            self?.finishEditingLink(at: location, outcome: outcome, isNew: isNew, selectsText: selectsText)
        }
        #if os(macOS)
        let model = LinkEditorModel(address: address.removingPercentEncoding ?? address, isNew: isNew)
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        var finished = false
        model.finish = { [weak popover] outcome in
            guard !finished else { return }
            finished = true
            popover?.performClose(nil)
            finish(outcome)
        }
        popover.contentViewController = NSHostingController(rootView: LinkEditor(model: model))
        let anchor = layoutManager.rect(forObjectAt: link.markers.last?.location ?? link.range.location, origin: textView.textContainerOrigin)
            ?? textView.firstRect(forCharacterRange: link.content, actualRange: nil)
        popover.show(relativeTo: anchor.insetBy(dx: -2, dy: -2), of: textView, preferredEdge: .maxY)
        // Closing by clicking elsewhere keeps what was typed.
        NotificationCenter.default.addObserver(forName: NSPopover.willCloseNotification, object: popover, queue: .main) { _ in
            MainActor.assumeIsolated { model.finish(.save(model.address)) }
        }
        #else
        guard let presenter = textView.window?.rootViewController?.topmostPresented else { return }
        let alert = UIAlertController(title: String(localized: isNew ? .addLinkTitle : .editLinkTitle), message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = address.removingPercentEncoding ?? address
            field.placeholder = "https://"
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.clearButtonMode = .whileEditing
        }
        let entered = { [weak alert] in alert?.textFields?.first?.text ?? "" }
        if !isNew {
            alert.addAction(UIAlertAction(title: String(localized: .openLink), style: .default) { _ in finish(.open(entered())) })
            alert.addAction(UIAlertAction(title: String(localized: .removeLink), style: .destructive) { _ in finish(.remove) })
        }
        alert.addAction(UIAlertAction(title: String(localized: .cancel), style: .cancel) { _ in finish(.save(isNew ? "" : address)) })
        let done = UIAlertAction(title: String(localized: .done), style: .default) { _ in finish(.save(entered())) }
        alert.addAction(done)
        alert.preferredAction = done
        presenter.present(alert, animated: true)
        #endif
    }

    func linkSpan(at location: Int) -> InlineSpan? {
        guard !document.lines.isEmpty, location < storage.length else { return nil }
        return document.lines[document.lineIndex(containing: location)].spans.first {
            if case .link = $0.kind { return $0.range.location == location }
            return false
        }
    }

    /// Between `](` and `)`.
    func destinationRange(of link: InlineSpan) -> NSRange {
        let close = link.markers.last ?? NSRange(location: link.range.upperBound, length: 0)
        return NSRange(location: close.location + 2, length: max(0, close.length - 3))
    }

    func finishEditingLink(at location: Int, outcome: LinkEditorModel.Outcome, isNew: Bool, selectsText: Bool = false) {
        guard let link = linkSpan(at: location) else { return }
        let text = nsText.substring(with: link.content)
        switch outcome {
        case .save(let address):
            let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty, isNew {
                // No address for a new link: the word put in for it goes again, a selected text stays as it was.
                let kept = selectsText ? "" : text
                replace(link.range, with: kept, select: NSRange(location: link.range.location + (kept as NSString).length, length: 0))
            } else {
                if trimmed != nsText.substring(with: destinationRange(of: link)) {
                    let encoded = trimmed.replacingOccurrences(of: " ", with: "%20")
                    replace(destinationRange(of: link), with: encoded, select: NSRange(location: link.content.upperBound, length: 0))
                }
                if selectsText, let updated = linkSpan(at: location) {
                    selectsExactly = true
                    setSelection(updated.content)
                    selectsExactly = false
                }
            }
        case .open(let address):
            if let url = URL(string: address.trimmingCharacters(in: .whitespaces)), url.scheme != nil { Platform.open(url) }
        case .remove:
            replace(link.range, with: text, select: NSRange(location: link.range.location + (text as NSString).length, length: 0))
        }
        makeTextFirstResponder()
    }
}

@MainActor
@Observable
final class LinkEditorModel {
    enum Outcome {
        case save(String)
        case open(String)
        case remove
    }

    var address: String
    let isNew: Bool
    var finish: (Outcome) -> Void = { _ in }

    init(address: String, isNew: Bool) {
        self.address = address
        self.isNew = isNew
    }
}

#if os(macOS)
/// The popover: the address, and buttons to open it or take the link off.
private struct LinkEditor: View {
    @Bindable var model: LinkEditorModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(.linkAddress, text: $model.address, prompt: Text(verbatim: "https://"))
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { model.finish(.save(model.address)) }
                .frame(width: 300)
            HStack {
                if !model.isNew {
                    Button(.removeLink, role: .destructive) { model.finish(.remove) }
                }
                Spacer()
                Button(.openLink) { model.finish(.open(model.address)) }
                    .disabled(URL(string: model.address)?.scheme == nil)
                Button(.done) { model.finish(.save(model.address)) }
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
        }
        .padding(14)
        .onAppear { focused = true }
    }
}
#else
extension UIViewController {
    /// The view controller on top, which can present another.
    var topmostPresented: UIViewController {
        var top = self
        while let presented = top.presentedViewController, !presented.isBeingDismissed { top = presented }
        return top
    }
}
#endif
