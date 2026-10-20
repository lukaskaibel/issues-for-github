import Foundation
import Testing
@testable import GitIssuesKit

/// Reading Markdown line by line, as GitHub writes it in issues and comments.
@Suite("Markdown parser")
struct MarkdownParserTests {
    private func kinds(_ text: String) -> [LineKind] {
        MarkdownParser.parse(text).lines.map(\.kind)
    }

    private func spans(_ text: String) -> [InlineSpan.Kind] {
        MarkdownParser.parse(text).lines.flatMap(\.spans).map(\.kind)
    }

    @Test func headingsListsAndQuotes() {
        let document = MarkdownParser.parse("# Title\n\n- one\n  - nested\n1. first\n- [x] done\n> quoted")
        guard case .heading(1, _) = document.lines[0].kind else { Issue.record("no heading"); return }
        #expect(document.lines[1].kind == .blank)
        guard case .listItem(let one) = document.lines[2].kind, case .listItem(let nested) = document.lines[3].kind,
              case .listItem(let first) = document.lines[4].kind, case .listItem(let task) = document.lines[5].kind else {
            Issue.record("no list items"); return
        }
        #expect(one.level == 0 && nested.level == 1)
        #expect(first.isOrdered)
        #expect(task.isTask && task.checked)
        guard case .quote(1, _) = document.lines[6].kind else { Issue.record("no quote"); return }
        #expect(document.checkboxes.count == 1)
    }

    @Test @MainActor func fencesKnowTheirLanguage() {
        let document = MarkdownParser.parse("```swift\nlet x = 1\n```\n\n```mermaid\nflowchart LR\n  A --> B\n```\n\n```math\nx^2\n```")
        #expect(document.blocks.map(\.kind) == [.code(language: "swift"), .mermaid, .math])
        let math = "```math\nx^2\n```"
        let parsed = MarkdownParser.parse(math)
        #expect(MarkdownStyler.mathSource(math as NSString, parsed, parsed.blocks[0]) == "x^2")
        #expect(MarkdownStyler.mathSource("$$\na + b\n$$" as NSString, MarkdownParser.parse("$$\na + b\n$$"), MarkdownParser.parse("$$\na + b\n$$").blocks[0]) == "a + b")
    }

    @Test func displayMathOnLinesOfItsOwnOrOne() {
        #expect(MarkdownParser.parse("$$\nx^2\n$$").blocks.map(\.kind) == [.math])
        #expect(MarkdownParser.parse("$$x^2$$").blocks.map(\.kind) == [.math])
        #expect(spans("costs $5 and $6") == [], "prices stay prices")
        #expect(spans("so $x^2$ grows") == [.math(tex: "x^2")])
    }

    @Test func tablesNeedADelimiterRow() {
        let document = MarkdownParser.parse("| a | b |\n|:--|--:|\n| 1 | 2 |\n\nafter")
        #expect(document.blocks.map(\.kind) == [.table(alignments: [.leading, .trailing])])
        #expect(document.lines[4].kind == .paragraph)
        #expect(MarkdownParser.parse("| a | b |\nno delimiter").blocks.isEmpty)
    }

    @Test func onlyGitHubsFiveAlertsAreAlerts() {
        for type in ["NOTE", "Tip", "important", "WARNING", "CAUTION"] {
            #expect(MarkdownParser.parse("> [!\(type)]\n> Text").blocks.map(\.kind) == [.callout(type: type.lowercased())])
        }
        #expect(MarkdownParser.parse("> [!info]\n> Text").blocks.map(\.kind) == [.quote], "Obsidian's other callouts stay quotes, as on GitHub")
        #expect(MarkdownParser.parse("> [!NOTE] With a title").blocks.map(\.kind) == [.quote], "GitHub's alerts have no title")
    }

    @Test func htmlCommentsAreBlocksUntilTheyClose() {
        let document = MarkdownParser.parse("<!-- Describe\nthe bug -->\nText\n<!-- one line -->")
        #expect(document.blocks.map(\.kind) == [.comment, .comment])
        #expect(document.lines.map(\.kind) == [.comment, .comment, .paragraph, .comment])
        // One left open runs to the end, as GitHub reads it.
        #expect(MarkdownParser.parse("Text\n<!-- open\nstill hidden").lines.map(\.kind) == [.paragraph, .comment, .comment])
    }

    @Test func inlineMarkdown() {
        #expect(spans("**bold** _it_ ~gone~ ~~gone~~ `code`") == [.strong, .emphasis, .strikethrough, .strikethrough, .code])
        #expect(spans("[GitHub](https://github.com) and https://example.com.") == [
            .link(destination: "https://github.com"), .autolink(url: "https://example.com"),
        ])
        #expect(spans("![shot](https://x.test/a.png)") == [.image(source: "https://x.test/a.png", alt: "shot", width: nil)])
        #expect(spans("a footnote[^1] and \\*not emphasis\\*") == [.footnoteReference(label: "1"), .escape, .escape])
        #expect(spans("say <kbd>⌘</kbd> <!-- hidden --> now") == [.html, .html, .comment])
    }

    @Test func imgTagsArePictures() {
        let text = #"<img width="1252" height="436" alt="Image" src="https://github.com/user-attachments/assets/abc" />"#
        #expect(spans(text) == [.image(source: "https://github.com/user-attachments/assets/abc", alt: "Image", width: 1252)])
        #expect(spans("<img alt='no source'>") == [.html])
    }

    @Test func notebooksOwnSyntaxStaysText() {
        #expect(spans("==not marked== and [[not a link]]").isEmpty)
    }

    @Test func linesKeepTheirPlaces() {
        let text = "Grüße 🎉\r\n- [ ] Größe prüfen"
        let document = MarkdownParser.parse(text)
        #expect(document.length == (text as NSString).length)
        #expect(document.lines[0].breakLength == 2)
        guard case .listItem(let item) = document.lines[1].kind, let box = item.checkbox else { Issue.record("no task"); return }
        #expect((text as NSString).substring(with: box) == "[ ]")
    }
}
