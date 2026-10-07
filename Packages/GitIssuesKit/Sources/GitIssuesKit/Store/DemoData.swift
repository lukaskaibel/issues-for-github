import Foundation
import GRDB

/// The sample projects shown in "Explore with sample data": a small team building an app and its website.
/// Kept in memory, so nothing here ever reaches GitHub and a fresh copy appears each time.
public enum DemoData {
    static let viewer = Viewer(id: "demo-user-jordan", login: "jordan", name: "Jordan Lee", avatarUrl: nil)
    static let mira = Person(id: "demo-user-mira", login: "mira", name: "Mira Patel")
    static let theo = Person(id: "demo-user-theo", login: "theo", name: "Theo Novak")
    static let kai = Person(id: "demo-user-kai", login: "kai", name: "Kai Andersen")
    static var team: [Person] { [viewer.person, mira, theo, kai] }

    public static func database() throws -> AppDatabase {
        let db = try AppDatabase.inMemory()
        try db.writer.write { try seed($0) }
        return db
    }

    // MARK: Projects

    private struct ProjectSpec {
        var id: String
        var number: Int
        var title: String
        var repoId: String
        var repo: String
        var statuses: [(name: String, color: String)]
        var labels: [LabelRef]
        /// Whether the project has a Priority field; the website has none, so adding one can be tried.
        var hasPriority = true
        /// Whether it has a "Due date" field; on the website the first date adds one.
        var hasDueField = true
    }

    private static let appLabels = [
        LabelRef(id: "demo-label-auth", name: "auth", color: "E3A13B"),
        LabelRef(id: "demo-label-bug", name: "bug", color: "D73A4A"),
        LabelRef(id: "demo-label-feature", name: "feature", color: "B57CF0"),
        LabelRef(id: "demo-label-release", name: "release", color: "8B949E"),
        LabelRef(id: "demo-label-sync", name: "sync", color: "3FB27F"),
        LabelRef(id: "demo-label-ui", name: "ui", color: "7B83EB"),
    ]

    private static let siteLabels = [
        LabelRef(id: "demo-label-content", name: "content", color: "0E8A16"),
        LabelRef(id: "demo-label-design", name: "design", color: "C45FA6"),
        LabelRef(id: "demo-label-seo", name: "seo", color: "1D76DB"),
    ]

    private static let app = ProjectSpec(
        id: "demo-project-app", number: 1, title: "Git Issues", repoId: "demo-repo-app", repo: "acme/git-issues",
        statuses: [("Backlog", "GRAY"), ("Todo", "GRAY"), ("In Progress", "YELLOW"), ("In Review", "GREEN"), ("Done", "PURPLE")],
        labels: appLabels
    )

    private static let site = ProjectSpec(
        id: "demo-project-site", number: 2, title: "Website", repoId: "demo-repo-site", repo: "acme/website",
        statuses: [("Todo", "GRAY"), ("In Progress", "YELLOW"), ("Done", "PURPLE")],
        labels: siteLabels,
        hasPriority: false,
        hasDueField: false
    )

    // MARK: Issues

    private struct IssueSpec {
        var number: Int
        var title: String
        var status: String
        var priority: String?
        var labels: [String] = []
        var assignees: [Person] = []
        var body = ""
        var parent: Int?
        var hoursAgo: Double = 30
        /// Due this many days from today; negative is overdue.
        var due: Int?
    }

    private static let appIssues: [IssueSpec] = [
        IssueSpec(number: 5, title: "Keyboard navigation across board and list", status: "In Review", priority: "Medium", labels: ["ui"], assignees: [viewer.person], body: "J and K move through issues, Return opens one and Escape goes back. Arrow keys switch columns on the board.", hoursAgo: 3),
        IssueSpec(number: 16, title: "Markdown editor for descriptions and comments", status: "In Review", priority: "Low", labels: ["ui"], assignees: [viewer.person, mira], body: "Style Markdown while typing: headings, **bold**, _italics_, `code` and lists.", hoursAgo: 5),
        IssueSpec(number: 6, title: "Delta sync for project items", status: "In Review", priority: "High", labels: ["sync"], assignees: [theo], body: "Only fetch items whose `updatedAt` changed since the last sweep.", hoursAgo: 8, due: 2),
        IssueSpec(number: 24, title: "Animate the column count when a card lands", status: "In Review", priority: nil, hoursAgo: 9),
        IssueSpec(number: 7, title: "Sub-issue tree in issue detail", status: "In Progress", priority: "Medium", labels: ["ui"], assignees: [mira], hoursAgo: 4),
        IssueSpec(number: 8, title: "Offline change queue that replays on reconnect", status: "In Progress", priority: "High", labels: ["sync"], assignees: [viewer.person], body: "Every change is written locally first and queued. When the connection returns, the queue is sent in order.", hoursAgo: 2, due: 9),
        IssueSpec(number: 9, title: "Drag cards between columns with spring physics", status: "In Progress", priority: "Urgent", labels: ["ui"], assignees: [viewer.person], body: """
            A card should lift under the pointer, tilt slightly while it moves, and settle into place with a spring. Neighbouring cards make room as the drag passes over them.

            - The drag starts after 4 pt of pointer movement, with no delay
            - Dropping writes the new status and position locally first, then queues the GitHub update
            - Escape cancels and animates the card back to where it came from

            ```swift
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { drop() }
            ```
            """, hoursAgo: 1, due: 0),
        IssueSpec(number: 13, title: "Cancel a drag with Escape", status: "In Progress", priority: "Medium", labels: ["ui"], assignees: [viewer.person], parent: 9, hoursAgo: 6),
        IssueSpec(number: 15, title: "Conflict banner when text changed on GitHub", status: "In Progress", priority: "High", labels: ["sync"], assignees: [theo], hoursAgo: 7),
        IssueSpec(number: 17, title: "Command palette with fuzzy search", status: "Todo", priority: "High", labels: ["ui"], assignees: [viewer.person], hoursAgo: 20, due: 1),
        IssueSpec(number: 14, title: "Sign in with GitHub device flow", status: "Todo", priority: "Medium", labels: ["auth"], assignees: [viewer.person, kai], hoursAgo: 22, due: 3),
        IssueSpec(number: 25, title: "Crash when a label name contains an emoji", status: "Todo", priority: "Urgent", labels: ["bug"], assignees: [kai], body: "Steps to reproduce:\n\n1. Add a label named `🔥 hot`\n2. Open the labels picker\n3. The app quits", hoursAgo: 12, due: -2),
        IssueSpec(number: 18, title: "Notarized builds and automatic updates", status: "Backlog", priority: "Low", labels: ["release"], hoursAgo: 70, due: 24),
        IssueSpec(number: 19, title: "Show linked pull requests and CI state", status: "Backlog", priority: "Low", labels: ["feature"], hoursAgo: 80),
        IssueSpec(number: 20, title: "Milestones as roadmap projects", status: "Backlog", priority: "Low", labels: ["feature"], hoursAgo: 90),
        IssueSpec(number: 21, title: "Inbox from GitHub notifications", status: "Backlog", priority: nil, labels: ["feature"], hoursAgo: 100),
        IssueSpec(number: 22, title: "Cycles backed by the Iteration field", status: "Backlog", priority: "Low", labels: ["feature"], hoursAgo: 110),
        IssueSpec(number: 10, title: "Lift and tilt on drag start", status: "Done", priority: "Medium", labels: ["ui"], assignees: [viewer.person], parent: 9, hoursAgo: 26),
        IssueSpec(number: 11, title: "Neighbouring cards make room with springs", status: "Done", priority: "Medium", labels: ["ui"], assignees: [viewer.person], parent: 9, hoursAgo: 27),
        IssueSpec(number: 12, title: "Drop placeholder in the target column", status: "Done", priority: "Low", labels: ["ui"], assignees: [mira], parent: 9, hoursAgo: 28),
        IssueSpec(number: 23, title: "Auto-scroll the board when dragging near an edge", status: "Done", priority: "Low", labels: ["ui"], assignees: [viewer.person], parent: 9, hoursAgo: 29),
        IssueSpec(number: 4, title: "Local database with instant edits", status: "Done", priority: "High", labels: ["sync"], assignees: [theo], hoursAgo: 120),
    ]

    private static let siteIssues: [IssueSpec] = [
        IssueSpec(number: 31, title: "Pricing page with a monthly and yearly toggle", status: "In Progress", priority: "High", labels: ["design"], assignees: [viewer.person], body: "Show both prices side by side; yearly saves two months.", hoursAgo: 2),
        IssueSpec(number: 32, title: "Screenshots for the iPhone and iPad launch", status: "In Progress", priority: "Medium", labels: ["content"], assignees: [mira], hoursAgo: 5),
        IssueSpec(number: 33, title: "Write the release notes for 0.2", status: "Todo", priority: "Medium", labels: ["content"], assignees: [viewer.person], hoursAgo: 11),
        IssueSpec(number: 34, title: "Open Graph images for every page", status: "Todo", priority: "Low", labels: ["seo"], hoursAgo: 30),
        IssueSpec(number: 35, title: "Dark mode for the docs", status: "Done", priority: "Medium", labels: ["design"], assignees: [kai], hoursAgo: 60),
    ]

    /// Issues filed straight in the app's repository, on no board yet: they show under "No project".
    private static let appIssuesWithoutProject: [IssueSpec] = [
        IssueSpec(number: 27, title: "App quits when a project has no Status field", status: "", priority: nil, labels: ["bug"], assignees: [viewer.person], body: "Reported on 0.1.0: open a project without a Status field and the app quits right away.", hoursAgo: 4),
        IssueSpec(number: 26, title: "Support GitHub Enterprise Server", status: "", priority: nil, labels: ["feature"], body: "Sign in to a company's own GitHub, with its own address.", hoursAgo: 50),
    ]

    private static let comments: [Int: [(Person, String, Double)]] = [
        9: [
            (mira, "The settle feels good now. Could the tilt follow pointer velocity instead of using a fixed angle?", 0.8),
            (viewer.person, "Good idea, I'll try it with the velocity from the drag gesture and clamp it to 5°.", 0.5),
        ],
        8: [(theo, "Queued changes survive a relaunch now, the outbox is in the database.", 1.5)],
        25: [(kai, "Reproduced on 0.1.0. The label picker measures the name with the wrong font.", 10)],
    ]

    // MARK: Seeding

    private static func seed(_ db: Database) throws {
        try KV.setViewer(db, viewer)
        let now = Date()
        let today = CalendarDay.today()
        for (spec, issues) in [(app, appIssues), (site, siteIssues)] {
            try Project(
                id: spec.id, ownerLogin: "acme", ownerIsOrg: true, number: spec.number, title: spec.title,
                url: "https://github.com/orgs/acme/projects/\(spec.number)", closed: false, viewerCanUpdate: true,
                remoteUpdatedAt: nil, itemsTotal: issues.count,
                statusFieldId: "\(spec.id)-status", priorityFieldId: spec.hasPriority ? "\(spec.id)-priority" : nil,
                dueFieldId: spec.hasDueField ? "\(spec.id)-due" : nil, lastSyncedAt: now
            ).insert(db)
            for (index, status) in spec.statuses.enumerated() {
                try FieldOption(
                    id: optionId(spec, status.name), fieldId: "\(spec.id)-status", projectId: spec.id, kind: .status,
                    name: status.name, color: status.color, descr: "", position: index
                ).insert(db)
            }
            for (index, priority) in Defaults.priorityOptions.enumerated() where spec.hasPriority {
                try FieldOption(
                    id: optionId(spec, priority.name), fieldId: "\(spec.id)-priority", projectId: spec.id, kind: .priority,
                    name: priority.name, color: priority.color, descr: "", position: index
                ).insert(db)
            }
            try RepoRef(
                id: spec.repoId, nameWithOwner: spec.repo, projectId: spec.id,
                labels: spec.labels, assignableUsers: team, metaLoadedAt: now
            ).insert(db)

            for (index, issue) in issues.enumerated() {
                let closed = issue.status == "Done"
                let date = now.addingTimeInterval(-issue.hoursAgo * 3600)
                let parent = issue.parent.flatMap { number in issues.first { $0.number == number } }
                let children = issues.filter { $0.parent == issue.number }
                try Item(
                    id: "demo-item-\(issue.number)", projectId: spec.id, kind: .issue, position: Double(index + 1) * 1024,
                    statusId: optionId(spec, issue.status), priorityId: spec.hasPriority ? issue.priority.map { optionId(spec, $0) } : nil,
                    dueDate: spec.hasDueField ? issue.due.map { today.adding(days: $0).string } : nil,
                    contentId: contentId(issue.number), number: issue.number, title: issue.title, body: issue.body,
                    state: closed ? "CLOSED" : "OPEN", stateReason: closed ? "COMPLETED" : nil,
                    url: "https://github.com/\(spec.repo)/issues/\(issue.number)", repoId: spec.repoId, repo: spec.repo,
                    authorLogin: (issue.assignees.first ?? viewer.person).login,
                    createdAt: date.addingTimeInterval(-86_400 * 3), updatedAt: date, closedAt: closed ? date : nil,
                    parentId: parent.map { contentId($0.number) }, parentNumber: parent?.number, parentTitle: parent?.title,
                    subTotal: children.count, subCompleted: children.filter { $0.status == "Done" }.count,
                    commentCount: comments[issue.number]?.count ?? 0,
                    assignees: issue.assignees,
                    labels: spec.labels.filter { issue.labels.contains($0.name) },
                    viewerCanDelete: true
                ).insert(db)
                for (position, child) in children.enumerated() {
                    try SubIssue(
                        id: contentId(child.number), parentId: contentId(issue.number), number: child.number, title: child.title,
                        state: child.status == "Done" ? "CLOSED" : "OPEN", stateReason: child.status == "Done" ? "COMPLETED" : nil,
                        repo: spec.repo, url: "https://github.com/\(spec.repo)/issues/\(child.number)", position: position,
                        assignees: child.assignees
                    ).insert(db)
                }
                for (position, comment) in (comments[issue.number] ?? []).enumerated() {
                    try Comment(
                        id: "demo-comment-\(issue.number)-\(position)", issueId: contentId(issue.number),
                        authorLogin: comment.0.login, authorAvatarUrl: nil, body: comment.1,
                        createdAt: now.addingTimeInterval(-comment.2 * 3600)
                    ).insert(db)
                }
            }
        }
        for issue in appIssuesWithoutProject {
            let date = now.addingTimeInterval(-issue.hoursAgo * 3600)
            try Item(
                id: Item.idWithoutProject(contentId(issue.number)), projectId: nil, kind: .issue,
                position: Item.positionWithoutProject(updatedAt: date),
                contentId: contentId(issue.number), number: issue.number, title: issue.title, body: issue.body,
                state: "OPEN", url: "https://github.com/\(app.repo)/issues/\(issue.number)", repoId: app.repoId, repo: app.repo,
                authorLogin: "sam", createdAt: date, updatedAt: date,
                assignees: issue.assignees,
                labels: app.labels.filter { issue.labels.contains($0.name) },
                viewerCanDelete: true
            ).insert(db)
        }
    }

    private static func optionId(_ spec: ProjectSpec, _ name: String) -> String {
        "\(spec.id)-option-\(name.lowercased().replacingOccurrences(of: " ", with: "-"))"
    }

    private static func contentId(_ number: Int) -> String {
        "demo-issue-\(number)"
    }
}
