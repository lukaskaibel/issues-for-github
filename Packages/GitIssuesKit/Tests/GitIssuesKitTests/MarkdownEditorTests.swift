#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import GitIssuesKit

/// The editor and the model in step: a description is saved after a pause and when you leave it, a draft follows every
/// keystroke, and text from GitHub comes in only while you aren't typing.
@MainActor
final class MarkdownEditorTests: XCTestCase {
    private var window: NSWindow!
    private var saved: [String] = []
    private var drafts: [String] = []

    override func setUp() {
        _ = NSApplication.shared
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        saved = []
        drafts = []
    }

    override func tearDown() {
        window.orderOut(nil)
    }

    private func coordinator(_ configuration: MarkdownEditor) -> MarkdownEditorCoordinator {
        let coordinator = MarkdownEditorCoordinator(configuration: configuration, checkboxes: MarkdownCheckboxes())
        coordinator.editor.textView.frame = NSRect(x: 0, y: 0, width: 600, height: 300)
        window.contentView?.addSubview(coordinator.editor.textView)
        return coordinator
    }

    private func settle(_ seconds: TimeInterval = 0.05) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func type(_ text: String, into coordinator: MarkdownEditorCoordinator) {
        let view = coordinator.editor.textView
        window.makeFirstResponder(view)
        view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
        for character in text { view.insertText(String(character), replacementRange: view.selectedRange()) }
        settle()
    }

    func testADescriptionIsSavedAfterAPauseAndWhenLeft() {
        let editor = coordinator(MarkdownEditor(text: "Hello", onSave: { [unowned self] in saved.append($0) }))
        type(" world", into: editor)
        XCTAssertEqual(saved, [], "not while typing")
        settleRunLoop(until: { !saved.isEmpty })
        XCTAssertEqual(saved, ["Hello world"], "after a pause")
        type("!", into: editor)
        window.makeFirstResponder(nil)
        settle()
        XCTAssertEqual(saved, ["Hello world", "Hello world!"], "and at once when the text is left")
    }

    func testTextFromGitHubWaitsWhileYouType() {
        let editor = coordinator(MarkdownEditor(text: "Hello", onSave: { [unowned self] in saved.append($0) }))
        type(" there", into: editor)
        editor.update(MarkdownEditor(text: "Changed on GitHub", onSave: { [unowned self] in saved.append($0) }))
        XCTAssertEqual(editor.editor.text, "Hello there", "what you type isn't replaced")
        window.makeFirstResponder(nil)
        settle()
        XCTAssertEqual(saved, ["Hello there"])
        // The model now has what was saved, and later another change from GitHub.
        editor.update(MarkdownEditor(text: "Hello there", onSave: { [unowned self] in saved.append($0) }))
        editor.update(MarkdownEditor(text: "Hello there, again", onSave: { [unowned self] in saved.append($0) }))
        XCTAssertEqual(editor.editor.text, "Hello there, again")
        XCTAssertEqual(saved, ["Hello there"], "a change from GitHub isn't saved back")
    }

    func testADraftFollowsEveryKeyAndIsClearedFromOutside() {
        var draft = ""
        let editor = coordinator(MarkdownEditor(text: draft, onChange: { [unowned self] in drafts.append($0) }))
        type("Ship it", into: editor)
        XCTAssertEqual(drafts.last, "Ship it")
        XCTAssertEqual(drafts.count, 7)
        draft = ""
        // Sent: the model clears the draft while the field still has the focus.
        editor.update(MarkdownEditor(text: draft, onChange: { [unowned self] in drafts.append($0) }))
        XCTAssertEqual(editor.editor.text, "")
    }

    func testTheFormatMenuFollowsTheTextBeingTypedIn() {
        let first = coordinator(MarkdownEditor(text: "One", onSave: { _ in }))
        let second = coordinator(MarkdownEditor(text: "Two", onSave: { _ in }))
        let focus = MarkdownFocus.shared
        window.makeFirstResponder(first.editor.textView)
        XCTAssertTrue(focus.isEditing)
        XCTAssertIdentical(focus.textView, first.editor.textView)
        window.makeFirstResponder(second.editor.textView)
        XCTAssertIdentical(focus.textView, second.editor.textView)
        // The first one telling late that it was left changes nothing.
        first.editor.focusChanged(to: false)
        XCTAssertIdentical(focus.textView, second.editor.textView)
        XCTAssertTrue(focus.isEditing)
        second.editor.textView.setSelectedRange(NSRange(location: 3, length: 0))
        NSApp.sendAction(#selector(MarkdownTextView.makeHeading(_:)), to: focus.textView, from: nil)
        XCTAssertEqual(second.editor.text, "## Two")
        window.makeFirstResponder(nil)
        XCTAssertFalse(focus.isEditing)
        XCTAssertNil(focus.textView)
    }

    func testATickedBoxInTextThatIsOnlyReadIsSavedAtOnce() {
        let editor = coordinator(MarkdownEditor(text: "- [ ] Task", isEditable: false, allowsChecking: true, onSave: { [unowned self] in saved.append($0) }))
        editor.editor.toggleCheckbox(line: 0)
        settle()
        XCTAssertEqual(saved, ["- [x] Task"])
    }

    func testCheckboxesAreThereForVoiceOver() {
        let checkboxes = MarkdownCheckboxes()
        let editor = MarkdownEditorCoordinator(configuration: MarkdownEditor(text: "Intro\n- [x] Done **well**\n- [ ] Open", onSave: { _ in }), checkboxes: checkboxes)
        editor.editor.textView.frame = NSRect(x: 0, y: 0, width: 600, height: 300)
        window.contentView?.addSubview(editor.editor.textView)
        settleRunLoop(until: { checkboxes.places.count == 2 })
        XCTAssertEqual(checkboxes.places.map(\.label), ["Done well", "Open"])
        XCTAssertEqual(checkboxes.places.map(\.isChecked), [true, false])
        XCTAssertTrue(checkboxes.areTickable)
        checkboxes.toggle(checkboxes.places[1].line)
        XCTAssertEqual(editor.editor.text, "Intro\n- [x] Done **well**\n- [x] Open")
    }
}
#endif
