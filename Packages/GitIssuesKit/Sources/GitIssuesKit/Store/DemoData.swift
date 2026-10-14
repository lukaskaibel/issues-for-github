import Foundation
import GRDB

/// The sample projects shown in "Explore with sample data": a small team building an app and its website.
/// Kept in memory, so nothing here ever reaches GitHub and a fresh copy appears each time.
public enum DemoData {
    static let viewer = Viewer(id: "demo-user-jordan", login: "jordan", name: "Jordan Lee", avatarUrl: nil)
    static let mira = Person(id: "demo-user-mira", login: "mira", name: "Mira Patel")
    static let theo = Person(id: "demo-user-theo", login: "theo", name: "Theo Novak")
    static let kai = Person(id: "demo-user-kai", login: "kai", name: "Kai Andersen")
    /// Not on the team: files issues now and then.
    static let sam = Person(id: "demo-user-sam", login: "sam", name: "Sam Ortiz")
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
        LabelRef(id: "demo-label-epic", name: "epic", color: Item.epicLabelColor),
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
        /// Issues of the same project this one waits for.
        var blockedBy: [Int] = []
        /// The milestone it is planned for, by title.
        var milestone: String?
    }

    /// The app's weekly cycles, as GitHub's Iteration field has them: two done, this week's and the next two.
    private static let cycles: [(id: String, title: String, weeks: Int)] = [
        ("demo-cycle-2", "Cycle 2", -2), ("demo-cycle-3", "Cycle 3", -1), ("demo-cycle-4", "Cycle 4", 0),
        ("demo-cycle-5", "Cycle 5", 1), ("demo-cycle-6", "Cycle 6", 2),
    ]

    /// The cycle each of the app's issues is planned for, by number of weeks from this one.
    private static let cycleOfIssue: [Int: Int] = [
        9: 0, 8: 0, 13: 0, 28: 0, 15: 0, 17: 0, 25: 0, 7: 0, 6: 0,
        14: 1, 24: 1, 16: -1, 5: -1, 10: -1, 11: -1, 12: -1, 23: -1, 21: -2,
    ]

    /// The part of the app each issue is about: a single-select field of the app's project.
    private static let areas: [(name: String, color: String)] = [("Interface", "BLUE"), ("Sync", "GREEN"), ("Accounts", "ORANGE"), ("Release", "PURPLE")]
    private static func area(of issue: IssueSpec) -> String? {
        if issue.labels.contains("sync") { return "Sync" }
        if issue.labels.contains("auth") { return "Accounts" }
        if issue.labels.contains("release") { return "Release" }
        if issue.labels.contains("ui") || issue.labels.contains("bug") { return "Interface" }
        return nil
    }

    /// The app's milestones: one shipped, three ahead, due this many days from today.
    private static let appMilestones: [(number: Int, title: String, due: Int, descr: String, closed: Bool)] = [
        (1, "0.2", -12, "The board on iPhone and iPad, sign-in with GitHub.", true),
        (2, "0.3", 9, "Board polish: drag and drop, the offline queue and keyboard flow.", false),
        (3, "0.4", 30, "Sign-in and sync for teams: device flow, delta sync.", false),
        (4, "1.0", 58, "Ready for everyone: notarized builds and linked pull requests.", false),
    ]

    private static let appIssues: [IssueSpec] = [
        IssueSpec(number: 5, title: "Keyboard navigation across board and list", status: "In Review", priority: "Medium", labels: ["ui"], assignees: [viewer.person], body: "J and K move through issues, Return opens one and Escape goes back. Arrow keys switch columns on the board.", hoursAgo: 3, milestone: "0.3"),
        IssueSpec(number: 16, title: "Markdown editor for descriptions and comments", status: "In Review", priority: "Low", labels: ["ui"], assignees: [viewer.person, mira], body: """
            Style Markdown while typing: headings, **bold**, _italics_, `code` and lists. A description with a table, a checklist, code or a diagram is drawn the way GitHub draws it, and a click brings up the text.

            - [x] Headings, bold, italics and code
            - [x] Lists and quotes
            - [x] Tables and Mermaid diagrams
            - [ ] Images pasted from the clipboard

            | Element | While typing | Drawn |
            |---|---|---|
            | Table | Rows of pipes | A grid |
            | Checklist | `- [ ]` | Boxes that tick |
            | Diagram | Mermaid code | A picture |

            ```mermaid
            flowchart LR
                Drawn -->|click| Editor
                Editor -->|Escape| Drawn
                Drawn -->|tick a box| Saved[Saved to GitHub]
            ```
            """, hoursAgo: 5, milestone: "0.3"),
        IssueSpec(number: 6, title: "Delta sync for project items", status: "In Review", priority: "High", labels: ["sync"], assignees: [theo], body: "Only fetch items whose `updatedAt` changed since the last sweep.", parent: 41, hoursAgo: 8, due: 2, milestone: "0.4"),
        IssueSpec(number: 24, title: "Animate the column count when a card lands", status: "Todo", priority: nil, parent: 40, hoursAgo: 9, blockedBy: [9], milestone: "0.3"),
        IssueSpec(number: 7, title: "Sub-issue tree in issue detail", status: "In Progress", priority: "Medium", labels: ["ui"], assignees: [mira], hoursAgo: 4, milestone: "0.3"),
        IssueSpec(number: 8, title: "Offline change queue that replays on reconnect", status: "In Progress", priority: "High", labels: ["sync"], assignees: [viewer.person], body: "Every change is written locally first and queued. When the connection returns, the queue is sent in order.", parent: 41, hoursAgo: 2, due: 9, blockedBy: [6], milestone: "0.3"),
        IssueSpec(number: 9, title: "Drag cards between columns with spring physics", status: "In Progress", priority: "Urgent", labels: ["ui"], assignees: [viewer.person], body: """
            A card should lift under the pointer, tilt slightly while it moves, and settle into place with a spring. Neighbouring cards make room as the drag passes over them.

            - The drag starts after 4 pt of pointer movement, with no delay
            - Dropping writes the new status and position locally first, then queues the GitHub update
            - Escape cancels and animates the card back to where it came from

            ```swift
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { drop() }
            ```
            """, parent: 40, hoursAgo: 1, due: 0, milestone: "0.3"),
        IssueSpec(number: 13, title: "Cancel a drag with Escape", status: "In Progress", priority: "Medium", labels: ["ui"], assignees: [viewer.person], parent: 9, hoursAgo: 6, milestone: "0.3"),
        IssueSpec(number: 28, title: "Tilt the lifted card with the pointer's speed", status: "In Progress", priority: "Low", labels: ["ui"], assignees: [mira], parent: 9, hoursAgo: 0.6, milestone: "0.3"),
        IssueSpec(number: 15, title: "Conflict banner when text changed on GitHub", status: "In Progress", priority: "High", labels: ["sync"], assignees: [theo], parent: 41, hoursAgo: 7, milestone: "0.3"),
        IssueSpec(number: 17, title: "Command palette with fuzzy search", status: "Todo", priority: "High", labels: ["ui"], assignees: [viewer.person], hoursAgo: 20, due: 1, milestone: "0.3"),
        IssueSpec(number: 14, title: "Sign in with GitHub device flow", status: "Todo", priority: "Medium", labels: ["auth"], assignees: [viewer.person, kai], parent: 42, hoursAgo: 22, due: 3, milestone: "0.4"),
        IssueSpec(number: 25, title: "Crash when a label name contains an emoji", status: "Todo", priority: "Urgent", labels: ["bug"], assignees: [kai, viewer.person], body: "Steps to reproduce:\n\n1. Add a label named `🔥 hot`\n2. Open the labels picker\n3. The app quits", hoursAgo: 12, due: -2, milestone: "0.3"),
        IssueSpec(number: 18, title: "Notarized builds and automatic updates", status: "Backlog", priority: "Low", labels: ["release"], parent: 43, hoursAgo: 70, due: 24, blockedBy: [25], milestone: "1.0"),
        IssueSpec(number: 19, title: "Show linked pull requests and CI state", status: "Backlog", priority: "Low", labels: ["feature"], parent: 43, hoursAgo: 80, milestone: "1.0"),
        IssueSpec(number: 20, title: "Milestones as roadmap projects", status: "Backlog", priority: "Low", labels: ["feature"], parent: 44, hoursAgo: 90),
        IssueSpec(number: 21, title: "Inbox from GitHub notifications", status: "Done", priority: "High", labels: ["feature"], assignees: [viewer.person], hoursAgo: 30, milestone: "0.2"),
        IssueSpec(number: 22, title: "Cycles backed by the Iteration field", status: "Backlog", priority: "Low", labels: ["feature"], parent: 44, hoursAgo: 110),
        IssueSpec(number: 10, title: "Lift and tilt on drag start", status: "Done", priority: "Medium", labels: ["ui"], assignees: [viewer.person], parent: 9, hoursAgo: 26, milestone: "0.3"),
        IssueSpec(number: 11, title: "Neighbouring cards make room with springs", status: "Done", priority: "Medium", labels: ["ui"], assignees: [viewer.person], parent: 9, hoursAgo: 27, milestone: "0.3"),
        IssueSpec(number: 12, title: "Drop placeholder in the target column", status: "Done", priority: "Low", labels: ["ui"], assignees: [mira], parent: 9, hoursAgo: 28, milestone: "0.3"),
        IssueSpec(number: 23, title: "Auto-scroll the board when dragging near an edge", status: "Done", priority: "Low", labels: ["ui"], assignees: [viewer.person], parent: 9, hoursAgo: 29, milestone: "0.3"),
        IssueSpec(number: 4, title: "Local database with instant edits", status: "Done", priority: "High", labels: ["sync"], assignees: [theo], parent: 41, hoursAgo: 120, milestone: "0.2"),
        // Epics: planned on the roadmap, not shown on the board.
        IssueSpec(number: 40, title: "Drag and drop on the board", status: "In Progress", priority: "High", labels: ["epic"], body: "Cards that lift, tilt and settle like paper, and every way to move them: between columns, within one, with the keyboard.", hoursAgo: 6),
        IssueSpec(number: 41, title: "Offline-first sync", status: "In Progress", priority: "Urgent", labels: ["epic"], assignees: [theo], body: "Every change is saved here first and sent when GitHub can be reached, and what changed on GitHub meanwhile is merged in.", hoursAgo: 12),
        IssueSpec(number: 42, title: "Sign-in and accounts", status: "Todo", priority: "Medium", labels: ["epic"], assignees: [kai], body: "Sign in with the GitHub app's device flow on every device, and with a company's own GitHub.", hoursAgo: 40),
        IssueSpec(number: 43, title: "Ready for 1.0", status: "Backlog", priority: "Medium", labels: ["epic"], body: "What it takes to recommend the app to everyone.", hoursAgo: 72),
        IssueSpec(number: 44, title: "Cycles and planning", status: "Backlog", priority: "Low", labels: ["epic"], body: "Plan work in cycles, next to milestones and the roadmap.", hoursAgo: 120),
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
        IssueSpec(number: 26, title: "Support GitHub Enterprise Server", status: "", priority: nil, labels: ["feature"], body: "Sign in to a company's own GitHub, with its own address.", parent: 42, hoursAgo: 50, milestone: "1.0"),
    ]

    private static let comments: [Int: [(Person, String, Double)]] = [
        9: [
            (mira, "The settle feels good now. Could the tilt follow pointer velocity instead of using a fixed angle?", 0.8),
            (viewer.person, "Good idea, I'll try it with the velocity from the drag gesture and clamp it to 5°.", 0.5),
        ],
        8: [(theo, "Queued changes survive a relaunch now, the outbox is in the database.", 1.5)],
        14: [(kai, "The device code screen works on iPad now.", 22)],
        15: [(theo, "@jordan can you check the wording of the banner? It should say what happens to your text.", 2)],
        25: [(kai, "Reproduced on 0.1.0. The label picker measures the name with the wrong font.", 10)],
    ]

    // MARK: Seeding

    private static func milestoneId(_ title: String) -> String {
        "demo-milestone-\(title)"
    }

    private static func seed(_ db: Database) throws {
        try KV.setViewer(db, viewer)
        let now = Date()
        let today = CalendarDay.today()
        for milestone in appMilestones {
            try Milestone(
                id: milestoneId(milestone.title), repoId: app.repoId, repo: app.repo, number: milestone.number,
                title: milestone.title, descr: milestone.descr, dueOn: today.adding(days: milestone.due).string,
                state: milestone.closed ? "CLOSED" : "OPEN",
                closedAt: milestone.closed ? now.addingTimeInterval(TimeInterval(milestone.due + 1) * 86_400) : nil,
                url: "https://github.com/\(app.repo)/milestone/\(milestone.number)"
            ).insert(db)
        }
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
            try seedFieldsAndViews(db, spec: spec, today: today)

            for (index, issue) in issues.enumerated() {
                let closed = issue.status == "Done"
                let date = now.addingTimeInterval(-issue.hoursAgo * 3600)
                let parent = issue.parent.flatMap { number in issues.first { $0.number == number } }
                let children = issues.filter { $0.parent == issue.number }
                let blockers = issue.blockedBy.compactMap { number in issues.first { $0.number == number } }
                let blocked = issues.filter { $0.blockedBy.contains(issue.number) }
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
                    viewerCanDelete: true,
                    blockedByCount: blockers.filter { $0.status != "Done" }.count,
                    blockingCount: blocked.filter { $0.status != "Done" }.count,
                    milestoneId: issue.milestone.map(milestoneId), milestoneTitle: issue.milestone,
                    fieldValues: fieldValues(of: issue, in: spec)
                ).insert(db)
                for (relation, others) in [(LinkedIssue.Relation.blockedBy, blockers), (.blocking, blocked)] {
                    for (position, other) in others.enumerated() {
                        try LinkedIssue(
                            id: contentId(other.number), issueId: contentId(issue.number), relation: relation, number: other.number,
                            title: other.title, state: other.status == "Done" ? "CLOSED" : "OPEN",
                            stateReason: other.status == "Done" ? "COMPLETED" : nil, repo: spec.repo,
                            url: "https://github.com/\(spec.repo)/issues/\(other.number)", position: position
                        ).insert(db)
                    }
                }
                for (position, child) in children.enumerated() {
                    try SubIssue(
                        id: contentId(child.number), parentId: contentId(issue.number), number: child.number, title: child.title,
                        state: child.status == "Done" ? "CLOSED" : "OPEN", stateReason: child.status == "Done" ? "COMPLETED" : nil,
                        repo: spec.repo, url: "https://github.com/\(spec.repo)/issues/\(child.number)", position: position,
                        assignees: child.assignees, milestoneId: child.milestone.map(milestoneId), milestoneTitle: child.milestone
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
            let parent = issue.parent.flatMap { number in appIssues.first { $0.number == number } }
            try Item(
                id: Item.idWithoutProject(contentId(issue.number)), projectId: nil, kind: .issue,
                position: Item.positionWithoutProject(updatedAt: date),
                contentId: contentId(issue.number), number: issue.number, title: issue.title, body: issue.body,
                state: "OPEN", url: "https://github.com/\(app.repo)/issues/\(issue.number)", repoId: app.repoId, repo: app.repo,
                authorLogin: sam.login, createdAt: date, updatedAt: date,
                parentId: parent.map { contentId($0.number) }, parentNumber: parent?.number, parentTitle: parent?.title,
                assignees: issue.assignees,
                labels: app.labels.filter { issue.labels.contains($0.name) },
                viewerCanDelete: true,
                milestoneId: issue.milestone.map(milestoneId), milestoneTitle: issue.milestone
            ).insert(db)
            // On no board, but the sub-issue of an epic on one: the epic lists it.
            if let parent {
                let siblings = appIssues.filter { $0.parent == parent.number }.count
                try SubIssue(
                    id: contentId(issue.number), parentId: contentId(parent.number), number: issue.number, title: issue.title,
                    state: "OPEN", repo: app.repo, url: "https://github.com/\(app.repo)/issues/\(issue.number)", position: siblings,
                    assignees: issue.assignees, milestoneId: issue.milestone.map(milestoneId), milestoneTitle: issue.milestone
                ).insert(db)
                try db.execute(
                    sql: "UPDATE item SET subTotal = subTotal + 1 WHERE contentId = ?", arguments: [contentId(parent.number)]
                )
            }
        }
        try seedInbox(db, now: now)
    }

    // MARK: Fields and views

    private static func fieldValues(of issue: IssueSpec, in spec: ProjectSpec) -> [String: FieldValue] {
        guard spec.id == app.id else { return [:] }
        var values: [String: FieldValue] = [:]
        if let weeks = cycleOfIssue[issue.number], let cycle = cycles.first(where: { $0.weeks == weeks }) {
            values["\(spec.id)-iteration"] = FieldValue(iterationId: cycle.id)
        }
        if let area = area(of: issue) {
            values["\(spec.id)-area"] = FieldValue(optionId: "\(spec.id)-area-\(area.lowercased())")
        }
        return values
    }

    /// The fields GitHub lists for a project, and its saved views: for the app a board, this week's cycle, a list by
    /// area, open bugs and sync work, a release plan in GitHub's roadmap layout, the work by epic and by person; for
    /// the website a board and a list.
    private static func seedFieldsAndViews(_ db: Database, spec: ProjectSpec, today: CalendarDay) throws {
        var fields: [ProjectField] = []
        func add(_ suffix: String, _ name: String, _ type: String, options: [FieldChoice] = [], iterations: [IterationSpan] = []) {
            fields.append(ProjectField(
                id: "\(spec.id)-\(suffix)", projectId: spec.id, databaseId: 1000 + fields.count, name: name, dataType: type,
                position: fields.count, options: options, iterations: iterations
            ))
        }
        add("title", "Title", "TITLE")
        add("assignees", "Assignees", "ASSIGNEES")
        add("status", "Status", "SINGLE_SELECT", options: spec.statuses.map { FieldChoice(id: optionId(spec, $0.name), name: $0.name, color: $0.color) })
        add("labels", "Labels", "LABELS")
        add("milestone", "Milestone", "MILESTONE")
        add("parent", "Parent issue", "PARENT_ISSUE")
        add("progress", "Sub-issues progress", "SUB_ISSUES_PROGRESS")
        add("updated", "Updated", "UPDATED")
        if spec.hasPriority {
            add("priority", "Priority", "SINGLE_SELECT", options: Defaults.priorityOptions.map { FieldChoice(id: optionId(spec, $0.name), name: $0.name, color: $0.color) })
        }
        if spec.hasDueField { add("due", "Due date", "DATE") }
        let isApp = spec.id == app.id
        if isApp {
            // Weeks start on Monday, as GitHub's iterations do by default.
            let monday = today.adding(days: -((today.weekday() + 5) % 7))
            add("iteration", "Iteration", "ITERATION", iterations: cycles.map { cycle in
                IterationSpan(
                    id: cycle.id, title: cycle.title, startDate: monday.adding(days: cycle.weeks * 7).string, duration: 7,
                    completed: cycle.weeks < 0
                )
            })
            add("area", "Area", "SINGLE_SELECT", options: areas.map { FieldChoice(id: "\(spec.id)-area-\($0.name.lowercased())", name: $0.name, color: $0.color) })
        }
        for field in fields { try field.insert(db) }

        func id(_ suffix: String) -> String { "\(spec.id)-\(suffix)" }
        let shown = [id("title"), id("assignees"), id("status"), id("labels"), id("progress")]
        var views = [
            ProjectView(id: "\(spec.id)-view-board", projectId: spec.id, number: 1, name: "Board", layout: .board, filter: "", visibleFieldIds: shown, columnFieldId: id("status"), position: 0),
        ]
        if isApp {
            views += [
                ProjectView(id: "\(spec.id)-view-week", projectId: spec.id, number: 2, name: "This Week", layout: .board, filter: "iteration:@current", visibleFieldIds: shown, columnFieldId: id("status"), position: 1),
                ProjectView(id: "\(spec.id)-view-area", projectId: spec.id, number: 3, name: "By Area", layout: .table, filter: "is:open", visibleFieldIds: shown + [id("iteration")], groupByFieldId: id("area"), position: 2),
                ProjectView(id: "\(spec.id)-view-bugs", projectId: spec.id, number: 4, name: "Bugs and Sync", layout: .table, filter: "label:bug,sync is:open", visibleFieldIds: shown + [id("area")], sortBy: [ViewSort(fieldId: id("priority"), descending: false)], position: 3),
                ProjectView(id: "\(spec.id)-view-roadmap", projectId: spec.id, number: 5, name: "Release Plan", layout: .roadmap, filter: "has:milestone", groupByFieldId: id("milestone"), position: 4),
                ProjectView(id: "\(spec.id)-view-epics", projectId: spec.id, number: 6, name: "Epics", layout: .table, filter: "has:parent-issue", visibleFieldIds: shown, groupByFieldId: id("parent"), position: 5),
                ProjectView(id: "\(spec.id)-view-team", projectId: spec.id, number: 7, name: "Team", layout: .table, filter: "is:open", visibleFieldIds: shown, groupByFieldId: id("assignees"), position: 6),
            ]
        } else {
            views.append(ProjectView(id: "\(spec.id)-view-all", projectId: spec.id, number: 2, name: "All", layout: .table, filter: "", visibleFieldIds: shown, position: 1))
        }
        for view in views { try view.insert(db) }
    }

    // MARK: Inbox

    private static let brandLabels = [
        LabelRef(id: "demo-label-tokens", name: "tokens", color: "5B63D3"),
        LabelRef(id: "demo-label-ios", name: "ios", color: "1D76DB"),
    ]

    /// Labels and people of the sample repositories, for issues seen only in the Inbox.
    static func repoMeta(repoId: String) -> (labels: [LabelRef], users: [Person]) {
        switch repoId {
        case app.repoId: (appLabels, team)
        case site.repoId: (siteLabels, team)
        default: (brandLabels, team)
        }
    }

    /// The Inbox of the sample data: what Mira, Theo and Kai did that Jordan should know about, as GitHub would
    /// report it, and an issue Jordan's own account opened for them outside the app. Most of the issues are on the
    /// boards; #27, #38 and a new issue on the website are on none but in their repositories, and a pull request and
    /// an issue in a repository no board uses are only in the Inbox.
    private static func seedInbox(_ db: Database, now: Date) throws {
        func ago(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }
        func entry(
            _ id: String, reason: String, unread: Bool, hours: Double, readHoursAgo: Double? = nil,
            type: String = "Issue", repo: String, repoId: String, number: Int, title: String,
            state: String = "OPEN", stateReason: String? = nil, body: String = "", author: Person,
            assignees: [Person] = [], labels: [LabelRef] = [], activity: [InboxActivity]
        ) throws {
            var entry = InboxEntry(
                id: "demo-thread-\(id)", reason: reason, unread: unread, updatedAt: ago(hours),
                lastReadAt: readHoursAgo.map(ago), subjectType: type, title: title, repo: repo, number: number
            )
            entry.enrichedFor = entry.updatedAt
            let known = (repo == app.repo || repo == site.repo) && type == "Issue"
            entry.contentId = known ? contentId(number) : "demo-\(repo.replacingOccurrences(of: "/", with: "-"))-\(number)"
            entry.url = "https://github.com/\(repo)/\(type == "PullRequest" ? "pull" : "issues")/\(number)"
            entry.state = state
            entry.stateReason = stateReason
            entry.body = body
            entry.repoId = repoId
            entry.authorLogin = author.login
            entry.createdAt = activity.last?.at ?? entry.updatedAt
            entry.assignees = assignees
            entry.labels = labels
            entry.activity = activity
            entry.activityIsNew = unread
            entry.activitySince = unread ? entry.lastReadAt : nil
            try entry.insert(db)
        }
        let brand = "acme/brand"

        try entry(
            "25", reason: "assign", unread: true, hours: 0.2, readHoursAgo: 26, repo: app.repo, repoId: app.repoId, number: 25,
            title: "Crash when a label name contains an emoji", author: kai, activity: [
                InboxActivity(kind: .assigned, actor: kai, at: ago(0.2), detail: viewer.login),
                InboxActivity(kind: .statusChanged, actor: kai, at: ago(0.2), detail: "Todo", project: app.title),
                InboxActivity(kind: .commented, actor: kai, at: ago(10), text: comments[25]?.first?.1, commentId: "demo-comment-25-0"),
            ]
        )
        try entry(
            "8", reason: "comment", unread: true, hours: 1.5, readHoursAgo: 5, repo: app.repo, repoId: app.repoId, number: 8,
            title: "Offline change queue that replays on reconnect", author: viewer.person, activity: [
                InboxActivity(kind: .commented, actor: theo, at: ago(1.5), text: comments[8]?.first?.1, commentId: "demo-comment-8-0"),
            ]
        )
        try entry(
            "15", reason: "mention", unread: true, hours: 2, repo: app.repo, repoId: app.repoId, number: 15,
            title: "Conflict banner when text changed on GitHub", author: theo, activity: [
                InboxActivity(kind: .commented, actor: theo, at: ago(2), text: comments[15]?.first?.1, commentId: "demo-comment-15-0"),
            ]
        )
        try entry(
            "36", reason: "review_requested", unread: true, hours: 3, type: "PullRequest", repo: app.repo, repoId: app.repoId,
            number: 36, title: "Tilt cards with the pointer's velocity",
            body: "Follows up on #9: the tilt now follows the pointer's velocity, clamped to 5°, and settles back with the drop.",
            author: mira, assignees: [mira], labels: appLabels.filter { $0.name == "ui" }, activity: [
                InboxActivity(kind: .reviewRequested, actor: mira, at: ago(3), detail: viewer.login),
            ]
        )
        try entry(
            "27", reason: "assign", unread: true, hours: 4, readHoursAgo: 30, repo: app.repo, repoId: app.repoId, number: 27,
            title: "App quits when a project has no Status field",
            body: "Reported on 0.1.0: open a project without a Status field and the app quits right away.",
            author: sam, assignees: [viewer.person], labels: appLabels.filter { $0.name == "bug" }, activity: [
                InboxActivity(kind: .assigned, actor: theo, at: ago(4), detail: viewer.login),
            ]
        )
        try entry(
            "37", reason: "subscribed", unread: true, hours: 1, repo: site.repo, repoId: site.repoId, number: 37,
            title: "Footer links break on small screens",
            body: "On a phone the footer links wrap into each other. They should stack, one per line, below 480 pt.",
            author: kai, labels: siteLabels.filter { $0.name == "design" }, activity: [
                InboxActivity(kind: .opened, actor: kai, at: ago(1), text: "On a phone the footer links wrap into each other. They should stack, one per line, below 480 pt."),
            ]
        )
        try entry(
            "4", reason: "comment", unread: false, hours: 26, readHoursAgo: 20, repo: app.repo, repoId: app.repoId, number: 4,
            title: "Local database with instant edits", state: "CLOSED", stateReason: "COMPLETED", author: theo, activity: [
                InboxActivity(kind: .closed, actor: theo, at: ago(26), detail: "COMPLETED"),
            ]
        )
        try entry(
            "14", reason: "assign", unread: false, hours: 22, readHoursAgo: 21, repo: app.repo, repoId: app.repoId, number: 14,
            title: "Sign in with GitHub device flow", author: viewer.person, activity: [
                InboxActivity(kind: .commented, actor: kai, at: ago(22), text: comments[14]?.first?.1, commentId: "demo-comment-14-0"),
            ]
        )
        let tokensComment = "@jordan the iOS names should follow the Mac ones. Can you take a look?"
        try entry(
            "brand-4", reason: "mention", unread: false, hours: 96, readHoursAgo: 90, repo: brand, repoId: "demo-repo-brand", number: 4,
            title: "Rename the accent colour tokens",
            body: "The accent colour is called `tint` on iOS and `accent` on the Mac. One name for both makes the design files easier to follow.",
            author: mira, assignees: [mira], labels: brandLabels.filter { $0.name == "tokens" }, activity: [
                InboxActivity(kind: .commented, actor: mira, at: ago(96), text: tokensComment, commentId: "demo-comment-brand-4-0"),
            ]
        )
        // On no board, in a repository a board uses: the app reads it like the website's other issues.
        try Item(
            id: Item.idWithoutProject(contentId(37)), projectId: nil, kind: .issue,
            position: Item.positionWithoutProject(updatedAt: ago(1)),
            contentId: contentId(37), number: 37, title: "Footer links break on small screens",
            body: "On a phone the footer links wrap into each other. They should stack, one per line, below 480 pt.",
            state: "OPEN", url: "https://github.com/\(site.repo)/issues/37", repoId: site.repoId, repo: site.repo,
            authorLogin: kai.login, createdAt: ago(1), updatedAt: ago(1),
            labels: siteLabels.filter { $0.name == "design" }
        ).insert(db)
        try Comment(
            id: "demo-comment-brand-4-0", issueId: "demo-\(brand.replacingOccurrences(of: "/", with: "-"))-4",
            authorLogin: mira.login, authorAvatarUrl: nil, body: tokensComment, createdAt: ago(96)
        ).insert(db)

        // Opened and assigned with Jordan's own account by an agent on the command line: GitHub notifies nobody of
        // that, the app finds it itself. On no board, in a repository a board uses.
        let wake = Item(
            id: Item.idWithoutProject(contentId(38)), projectId: nil, kind: .issue,
            position: Item.positionWithoutProject(updatedAt: ago(0.6)),
            contentId: contentId(38), number: 38, title: "Sync waits for the next poll after the Mac wakes",
            body: "After the Mac wakes from sleep, the first sync starts only at the next poll, up to a minute later. "
                + "It should start right away, as it does when the app comes to the front.",
            state: "OPEN", url: "https://github.com/\(app.repo)/issues/38", repoId: app.repoId, repo: app.repo,
            authorLogin: viewer.login, createdAt: ago(0.6), updatedAt: ago(0.6),
            assignees: [viewer.person], labels: appLabels.filter { $0.name == "bug" || $0.name == "sync" }
        )
        try wake.insert(db)
        try InboxEntry(selfAssignment: RemoteSelfAssignment(
            eventId: "demo-event-38", at: ago(0.6), actor: viewer.person, repo: app.repo, number: 38,
            issue: RemoteInboxDetail(
                contentId: contentId(38), url: wake.url ?? "", title: wake.title, body: wake.body, state: "OPEN",
                stateReason: nil, repoId: app.repoId, authorLogin: viewer.login, createdAt: ago(0.6),
                assignees: wake.assignees, labels: wake.labels, activity: []
            )
        )).insert(db)

        var meta = InboxMeta()
        meta.access = .ok
        meta.others = ["Release": 1, "CheckSuite": 1]
        try meta.write(db)
    }

    private static func optionId(_ spec: ProjectSpec, _ name: String) -> String {
        "\(spec.id)-option-\(name.lowercased().replacingOccurrences(of: " ", with: "-"))"
    }

    private static func contentId(_ number: Int) -> String {
        "demo-issue-\(number)"
    }
}
