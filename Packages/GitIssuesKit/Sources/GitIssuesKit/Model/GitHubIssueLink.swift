import Foundation

/// A link to one issue on github.com, such as `https://github.com/octo/app/issues/42`, also with a comment's anchor or
/// a query behind it. Pull requests count too: they share their numbers with the issues of their repository, and GitHub
/// answers `/issues/7` with pull request 7. Anything deeper, like a pull request's files, is a page of its own.
struct GitHubIssueLink: Equatable {
    var repo: String
    var number: Int

    init?(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host?.lowercased(), host == "github.com" || host == "www.github.com" else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count == 4, parts[2] == "issues" || parts[2] == "pull",
              let number = Int(parts[3]), number > 0 else { return nil }
        repo = parts[0] + "/" + parts[1]
        self.number = number
    }

    /// GitHub takes a repository's name in any case, so a link may spell it differently from the issue.
    func leads(to item: Item) -> Bool {
        item.number == number && item.repo?.caseInsensitiveCompare(repo) == .orderedSame
    }

    /// The issue among `items` that a link on `page` leads to. A link to the page's own issue finds nothing: there is
    /// nowhere to go in the app, while GitHub can still show the comment it may point at.
    func issue(in items: [Item], from page: Item) -> Item? {
        guard let issue = items.first(where: leads(to:)), issue.contentId != page.contentId else { return nil }
        return issue
    }
}
