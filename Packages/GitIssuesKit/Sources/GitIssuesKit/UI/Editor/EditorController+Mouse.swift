#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Clicks on the things drawn in place of Markdown: a checkbox ticks, a link opens, a picture is selected like a
/// character, a table or diagram opens for editing right where you clicked.
extension EditorController {
    enum Hit {
        case checkbox(line: Int)
        case link(URL)
        case picture(range: NSRange, url: URL?)
        case block(index: Int, caret: Int)
        case editLink(range: NSRange)
    }

    func hitTest(_ point: NSPoint) -> Hit? {
        guard storage.length > 0 else { return nil }
        let origin = textOrigin
        let local = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        let glyph = layoutManager.glyphIndex(for: local, in: container)
        guard glyph < layoutManager.numberOfGlyphs else { return nil }
        let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
        guard rect.insetBy(dx: -1, dy: -2).contains(local) else { return nil }
        let index = layoutManager.characterIndexForGlyph(at: glyph)

        if layoutManager.propertyForGlyph(at: glyph) == .controlCharacter, let object = layoutManager.object(at: index) {
            let range = object.range(at: index)
            switch object.kind {
            case .checkbox:
                guard isEditable || allowsChecking else { return nil }
                return .checkbox(line: document.lineIndex(containing: index))
            case .image(let url, _, _, _):
                return .picture(range: range, url: url)
            case .table(let model):
                guard isEditable, let blockIndex = document.line(containing: index)?.block else { return nil }
                let objectRect = rect.offsetBy(dx: origin.x, dy: origin.y)
                var caret = document.blocks[blockIndex].range.location
                if let cell = model.cell(at: point, in: objectRect), let ranges = model.cellRanges[safe: cell.row] {
                    caret = ranges[safe: cell.column]?.upperBound ?? ranges.last?.upperBound ?? caret
                }
                return .block(index: blockIndex, caret: caret)
            case .mermaid, .mathBlock:
                guard isEditable, let blockIndex = document.line(containing: index)?.block else { return nil }
                let block = document.blocks[blockIndex]
                let line = block.lines.count > 1 ? document.lines[block.lines.lowerBound + 1] : document.lines[block.lines.lowerBound]
                return .block(index: blockIndex, caret: line.range.upperBound)
            case .linkEdit:
                guard isEditable else { return nil }
                return .editLink(range: range)
            default:
                return nil
            }
        }
        // A link you are editing (its Markdown showing) takes clicks as text.
        if let link = storage.attribute(.markdownLink, at: index, effectiveRange: nil) as? LinkTarget, !isRevealed(index),
           let url = URL(string: link.url.trimmingCharacters(in: .whitespaces)), url.scheme != nil {
            return .link(url)
        }
        return nil
    }

    /// Puts the caret into a table or diagram where it was clicked, keeping the line with the caret under the pointer
    /// as the block opens up.
    func openBlock(caret: Int, at point: NSPoint) {
        let pointer = screenY(point.y)
        makeTextFirstResponder()
        setSelection(NSRange(location: caret, length: 0))
        updateReveal()
        layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: min(storage.length, caret + 1)))
        let line = yPosition(of: caret) + EditorStyle.codeLineHeight / 2
        let delta = screenY(line) - pointer
        if abs(delta) > 0.5 { scrollPage(by: delta) }
    }

    #if os(macOS)
    /// Handles the click itself when it lands on something that isn't text; returns false to let AppKit place the
    /// caret or start a selection.
    func handleMouseDown(_ event: NSEvent) -> Bool {
        guard event.type == .leftMouseDown else { return false }
        let point = textView.convert(event.locationInWindow, from: nil)
        if !event.modifierFlags.intersection([.shift, .command, .option, .control]).isEmpty { return false }
        guard let hit = hitTest(point) else { return false }
        switch hit {
        case .checkbox(let line):
            toggleCheckbox(line: line)
            return true
        case .link(let url):
            openLink(url)
            return true
        case .picture(let range, let url):
            // A double-click opens the picture where it is on the web.
            if event.clickCount >= 2, let url {
                openLink(url)
                return true
            }
            guard isEditable else { return false }
            textView.window?.makeFirstResponder(textView)
            setSelection(range)
            return true
        case .editLink(let range):
            editLink(at: range)
            return true
        case .block(_, let caret):
            openBlock(caret: caret, at: point)
            return true
        }
    }

    func updateCursor(for event: NSEvent) {
        let point = textView.convert(event.locationInWindow, from: nil)
        if !textView.copyButton.isHidden, textView.copyButton.frame.contains(point) { return NSCursor.arrow.set() }
        switch hitTest(point) {
        case .checkbox, .link, .editLink: NSCursor.pointingHand.set()
        case .picture, .block: NSCursor.arrow.set()
        case nil: break
        }
    }

    func contextMenu(for event: NSEvent, base: NSMenu?) -> NSMenu? {
        let point = textView.convert(event.locationInWindow, from: nil)
        if let base { addCopyCode(to: base, at: point) }
        return base
    }
    #endif
}

#if os(macOS)
extension MarkdownTextView {
    // Formatting, sent by the Format menu to whatever text view has the focus.
    @objc func toggleBoldface(_ sender: Any?) { controller?.toggle(.bold) }
    @objc func toggleItalics(_ sender: Any?) { controller?.toggle(.italic) }
    @objc func toggleInlineCode(_ sender: Any?) { controller?.toggle(.code) }
    @objc func toggleStrikethrough(_ sender: Any?) { controller?.toggle(.strikethrough) }
    @objc func makeTitle(_ sender: Any?) { controller?.setLineFormat(.heading(1)) }
    @objc func makeHeading(_ sender: Any?) { controller?.setLineFormat(.heading(2)) }
    @objc func makeSubheading(_ sender: Any?) { controller?.setLineFormat(.heading(3)) }
    @objc func makeBody(_ sender: Any?) { controller?.setLineFormat(.body) }
    @objc func makeBulletedList(_ sender: Any?) { controller?.setLineFormat(.bullets) }
    @objc func makeNumberedList(_ sender: Any?) { controller?.setLineFormat(.numbered) }
    @objc func makeChecklist(_ sender: Any?) { controller?.setLineFormat(.checklist) }
    @objc func makeQuote(_ sender: Any?) { controller?.setLineFormat(.quote) }
    @objc func markChecked(_ sender: Any?) { controller?.toggleChecked() }
    @objc func addLink(_ sender: Any?) { controller?.insertLink() }
    @objc func indentLines(_ sender: Any?) { controller?.indent(by: 1) }
    @objc func outdentLines(_ sender: Any?) { controller?.indent(by: -1) }
}
#endif
