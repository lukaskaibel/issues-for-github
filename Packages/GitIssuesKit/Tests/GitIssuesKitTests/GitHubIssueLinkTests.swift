import Foundation
import Testing
@testable import GitIssuesKit

@Suite("Links to issues in texts")
struct GitHubIssueLinkTests {
    private func link(_ address: String) -> GitHubIssueLink? {
        URL(string: address).flatMap(GitHubIssueLink.init)
    }

    private func issue(_ number: Int, repo: String = "octo/app", id: String? = nil, projectId: String? = "P1") -> Item {
        Item(
            id: id ?? "item-\(number)", projectId: projectId, kind: .issue, position: 0, contentId: "issue-\(number)",
            number: number, title: "Issue \(number)", body: "", state: "OPEN", repo: repo
        )
    }

    @Test("An issue's address, with or without what can follow it")
    func recognizesIssues() {
        let expected = link("https://github.com/octo/app/issues/42")
        #expect(expected?.repo == "octo/app")
        #expect(expected?.number == 42)
        for address in [
            "https://github.com/octo/app/issues/42/",
            "https://github.com/octo/app/issues/42#issuecomment-1",
            "https://github.com/octo/app/issues/42?notification_referrer_id=1",
            "https://www.github.com/octo/app/issues/42",
            "http://GitHub.com/octo/app/issues/42",
            "https://github.com/octo/app/pull/42",
        ] {
            #expect(link(address) == expected, "\(address)")
        }
    }

    @Test("Other pages stay links to the web")
    func leavesOtherPages() {
        for address in [
            "https://github.com/octo/app",
            "https://github.com/octo/app/issues",
            "https://github.com/octo/app/issues/new",
            "https://github.com/octo/app/issues/0",
            "https://github.com/octo/app/pull/42/files",
            "https://github.com/octo/app/discussions/42",
            "https://github.com/orgs/octo/projects/42",
            "https://example.com/octo/app/issues/42",
            "https://gist.github.com/octo/app/issues/42",
            "mailto:octo@example.com",
        ] {
            #expect(link(address) == nil, "\(address)")
        }
    }

    @Test("Finds the issue by repository and number, in any spelling of the repository")
    func findsTheIssue() throws {
        let page = issue(1)
        let items = [page, issue(2, repo: "octo/other"), issue(2)]
        let found = try #require(link("https://github.com/Octo/APP/issues/2")).issue(in: items, from: page)
        #expect(found?.id == "item-2")
        #expect(found?.repo == "octo/app")
        #expect(try #require(link("https://github.com/octo/app/issues/3")).issue(in: items, from: page) == nil)
    }

    @Test("A link to the issue being read finds nothing, on whichever board it is")
    func leavesThePageItself() throws {
        let page = issue(1)
        let sameOnAnotherBoard = issue(1, id: "other-board", projectId: "P2")
        let target = try #require(link("https://github.com/octo/app/issues/1#issuecomment-9"))
        #expect(target.issue(in: [sameOnAnotherBoard, page], from: page) == nil)
    }

    @Test("The editor hands its links to the page, and keeps them from the browser when the page takes them")
    @MainActor
    func editorAsksThePage() throws {
        let coordinator = MarkdownEditorCoordinator(
            configuration: MarkdownEditor(text: "", isEditable: false), checkboxes: MarkdownCheckboxes()
        )
        var asked: [URL] = []
        coordinator.openIssueLink = OpenIssueLinkAction(pageId: "item-1") { asked.append($0); return true }
        let url = try #require(URL(string: "https://github.com/octo/app/issues/2"))
        coordinator.editor.openLink(url)
        #expect(asked == [url])
    }
}
