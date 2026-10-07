import MarkdownUI
import Testing
@testable import GitIssuesKit

@Suite("Reading Markdown for drawing")
struct MarkdownDocumentTests {
    @Test func plainTextIsNotRich() {
        let document = MarkdownDocument("# Title\n\nSome **bold** text with `code`.\n\n- one\n- two\n\n> quoted")
        #expect(!document.isRich)
    }

    @Test func tablesChecklistsCodeAndDiagramsAreRich() {
        #expect(MarkdownDocument("| a | b |\n|---|---|\n| 1 | 2 |").hasTable)
        #expect(MarkdownDocument("- [ ] todo").isRich)
        #expect(MarkdownDocument("Run:\n\n```swift\nlet x = 1\n```").hasCode)
        #expect(MarkdownDocument("Indented:\n\n    let x = 1").hasCode)
        #expect(!MarkdownDocument("```swift\nlet x = 1\n```").hasDiagram)
        #expect(MarkdownDocument("```mermaid\nflowchart LR\n  A --> B\n```").hasDiagram)
        #expect(MarkdownDocument("``` Mermaid title\ngraph TD\n```").hasDiagram)
    }

    @Test func markdownInsideCodeIsCode() {
        let document = MarkdownDocument("```md\n| a | b |\n|---|---|\n- [ ] todo\n```")
        #expect(document.hasCode)
        #expect(!document.hasTable)
        #expect(document.checkboxes.isEmpty)
    }

    @Test func checkboxesAreFoundInOrder() {
        let text = "Intro\n\n- [ ] one\n- [x] two\n  - [X] nested\n1. [ ] numbered"
        let document = MarkdownDocument(text)
        #expect(document.checkboxes.map(\.isChecked) == [false, true, true, false])
    }

    @Test func checkboxesInQuotesAreText() {
        // cmark-gfm, and so MarkdownUI, reads them as text, so they can't be clicked either.
        #expect(MarkdownDocument("> - [ ] quoted").checkboxes.isEmpty)
    }

    @Test func togglingChangesOnlyTheMark() {
        let text = "- [ ] one\n- [x] two ü\n  - [ ] nested"
        let document = MarkdownDocument(text)
        #expect(document.toggling(0) == "- [x] one\n- [x] two ü\n  - [ ] nested")
        #expect(document.toggling(1) == "- [ ] one\n- [ ] two ü\n  - [ ] nested")
        #expect(document.toggling(2) == "- [ ] one\n- [x] two ü\n  - [x] nested")
        #expect(document.toggling(3) == text)
    }

    @Test func togglingWorksAfterMultibyteText() {
        let text = "Grüße 🎉\n\n- [ ] Größe prüfen"
        #expect(MarkdownDocument(text).toggling(0) == "Grüße 🎉\n\n- [x] Größe prüfen")
    }

    @Test func taggedCheckboxesStillParseAsChecklists() {
        let document = MarkdownDocument("- [ ] one\n- [x]   two\n- [ ]\tthree")
        let rendered = document.rendered(taggingCheckboxes: true)
        #expect(rendered == "- [ ] [](gi-checkbox:0)one\n- [x]   [](gi-checkbox:1)two\n- [ ]\t[](gi-checkbox:2)three")
        #expect(MarkdownDocument(rendered).checkboxes.count == 3)
    }

    @Test func itemsGiveBackTheirCheckboxNumber() {
        // How MarkdownUI hands a list item's content to its style.
        let item = MarkdownContent("[](gi-checkbox:12)Fix **the** thing\n\n- [ ] [](gi-checkbox:13)nested").renderMarkdown()
        #expect(MarkdownDocument.checkboxNumber(inItem: item) == 12)
        #expect(MarkdownDocument.checkboxNumber(inItem: "Not a checkbox [](gi-checkbox:3)") == nil)
    }

    @Test func htmlCommentsAreLeftOut() {
        let text = """
            <!-- Describe the bug -->
            The app quits.

            <!--
            Steps, please.
            -->
            Text <!-- inline --> after.

            `<!-- code -->`

            ```html
            <!-- kept -->
            ```
            """
        let rendered = MarkdownDocument(text).rendered(taggingCheckboxes: false)
        #expect(rendered == """

            The app quits.


            Text  after.

            `<!-- code -->`

            ```html
            <!-- kept -->
            ```
            """)
    }

    @Test func commentNextToACheckbox() {
        let document = MarkdownDocument("- [ ] <!-- why -->ship it")
        #expect(document.rendered(taggingCheckboxes: true) == "- [ ] [](gi-checkbox:0)ship it")
    }
}
