#if os(macOS)
import AppKit
import XCTest
@testable import GitIssuesKit

/// Pictures of the editor, for looking at: run with `EDITOR_SNAPSHOTS=<folder>` and they are written there. Without
/// it, the tests only check that everything is drawn once diagrams and formulas are ready.
@MainActor
final class EditorSnapshotTests: XCTestCase {
    static let sample = """
        ## Markdown that reads as GitHub draws it

        Write **bold**, _italics_, ~~strikethrough~~, `code` and [links](https://github.com). The Markdown shows only \
        next to the caret.

        > [!TIP]
        > Click into a table, a diagram or a formula to edit its source.

        - [x] Headings, lists and quotes
        - [ ] Tables and diagrams
          - [ ] Nested items
        1. First
        2. Second

        | Element | Shown as |
        | --- | :---: |
        | Table | A grid |
        | Diagram | A picture |

        ```mermaid
        flowchart LR
            Write --> Read
            Read -->|click| Write
        ```

        The area is $\\pi r^2$, and:

        $$
        \\int_0^1 x^2 \\, dx = \\frac{1}{3}
        $$

        ```swift
        // Settles with a spring.
        withAnimation(.spring(response: 0.3)) { drop() }
        ```

        <!-- A note for whoever edits this -->
        ---
        A footnote[^1].

        [^1]: The end.
        """

    private func render(_ name: String, editable: Bool = true, dark: Bool = false, caret: String? = nil) -> EditorHarness {
        let h = EditorHarness(Self.sample, editable: editable, width: 640, height: 1600, dark: dark)
        h.caret(caret.map { h.range(of: $0).location } ?? h.text.utf16.count)
        let deadline = Date().addingTimeInterval(10)
        while DiagramStore.isBusy, Date() < deadline { h.settle(0.1) }
        h.layOut()
        h.settle(0.2)
        h.snapshot(name)
        return h
    }

    func testEverythingIsDrawn() {
        let h = render("editor-light")
        XCTAssertFalse(DiagramStore.isBusy)
        for marker in ["| Element", "```mermaid", "$\\pi", "$$", "> [!TIP]", "- [x]", "---\n"] {
            let index = h.range(of: marker).location
            XCTAssertNotEqual(index, NSNotFound, marker)
            XCTAssertFalse(h.isVisible(index + (marker.hasPrefix("- [") ? 2 : 0)), "\(marker) is drawn, not shown as Markdown")
        }
        guard case .mermaid? = h.object(at: h.range(of: "```mermaid").location)?.kind else { return XCTFail("the diagram isn't drawn") }
        if case .some(.some(let image)) = DiagramStore.cached(MarkdownStyler.diagramSource(h.editor.nsText, h.editor.document, h.editor.document.block(containing: h.range(of: "```mermaid").location)!), isDark: false) {
            XCTAssertGreaterThan(image.size.width, 100)
        } else {
            XCTFail("the diagram was not drawn")
        }
    }

    func testPicturesOfTheOtherStates() {
        _ = render("editor-dark", dark: true)
        _ = render("editor-read-only", editable: false)
        _ = render("editor-table-open", caret: "A grid")
        _ = render("editor-diagram-open", caret: "Write --> Read")
        _ = render("editor-bold-caret", caret: "bold")
    }
}
#endif
