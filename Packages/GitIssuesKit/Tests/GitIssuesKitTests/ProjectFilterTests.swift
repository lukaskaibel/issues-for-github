import Foundation
import Testing
@testable import GitIssuesKit

@Suite("A view's filter in GitHub's words")
struct ProjectFilterTests {
    static let today = CalendarDay(year: 2026, month: 10, day: 14)

    static let status = ProjectField(
        id: "F-status", projectId: "P1", databaseId: 1, name: "Status", dataType: "SINGLE_SELECT", position: 2,
        options: [
            FieldChoice(id: "s-todo", name: "Todo", color: "BLUE"),
            FieldChoice(id: "s-progress", name: "In Progress", color: "YELLOW"),
            FieldChoice(id: "s-done", name: "Done", color: "GREEN"),
            FieldChoice(id: "s-backlog", name: "Backlog", color: "GRAY"),
        ]
    )
    static let workstream = ProjectField(
        id: "F-ws", projectId: "P1", databaseId: 2, name: "Workstream", dataType: "SINGLE_SELECT", position: 3,
        options: [
            FieldChoice(id: "w-quick", name: "Quick Wins: Konto & Chat", color: "BLUE"),
            FieldChoice(id: "w-rag", name: "RAG-Weiterentwicklung → Agentik (AP2.1)", color: "BLUE"),
        ]
    )
    static let iteration = ProjectField(
        id: "F-it", projectId: "P1", databaseId: 3, name: "Iteration", dataType: "ITERATION", position: 4,
        iterations: [
            IterationSpan(id: "c15", title: "Cycle 15 · KW 40", startDate: "2026-09-28", duration: 7, completed: true),
            IterationSpan(id: "c16", title: "Cycle 16 · KW 41", startDate: "2026-10-05", duration: 7, completed: true),
            IterationSpan(id: "c17", title: "Cycle 17 · KW 42", startDate: "2026-10-12", duration: 7, completed: false),
            IterationSpan(id: "c18", title: "Cycle 18 · KW 43", startDate: "2026-10-19", duration: 7, completed: false),
        ]
    )
    static let due = ProjectField(id: "F-due", projectId: "P1", databaseId: 4, name: "Due date", dataType: "DATE", position: 5)
    static let points = ProjectField(id: "F-points", projectId: "P1", databaseId: 5, name: "Points", dataType: "NUMBER", position: 6)
    static let builtIn = [
        ProjectField(id: "F-title", projectId: "P1", databaseId: 10, name: "Title", dataType: "TITLE", position: 0),
        ProjectField(id: "F-assignees", projectId: "P1", databaseId: 11, name: "Assignees", dataType: "ASSIGNEES", position: 1),
        ProjectField(id: "F-labels", projectId: "P1", databaseId: 12, name: "Labels", dataType: "LABELS", position: 7),
        ProjectField(id: "F-milestone", projectId: "P1", databaseId: 13, name: "Milestone", dataType: "MILESTONE", position: 8),
        ProjectField(id: "F-parent", projectId: "P1", databaseId: 14, name: "Parent issue", dataType: "PARENT_ISSUE", position: 9),
    ]

    static var context: FilterContext {
        let fields = builtIn + [status, workstream, iteration, due, points]
        return FilterContext(
            viewerLogin: "lukaskaibel", today: today, fields: fields,
            statusFieldId: status.id, priorityFieldId: nil, dueFieldId: due.id,
            optionName: { fieldId, optionId in fields.first { $0.id == fieldId }?.options.first { $0.id == optionId }?.name },
            parentReference: { item in item.parentNumber.map { "CIATA-io/pia-l4ra-umbrella#\($0)" } }
        )
    }

    static func item(
        _ number: Int, status: String? = "s-todo", labels: [String] = [], assignees: [String] = [], closed: Bool = false,
        milestone: String? = nil, iteration: String? = nil, workstream: String? = nil, due: String? = nil, points: Double? = nil,
        parent: Int? = nil, title: String = "An issue", updated: CalendarDay? = nil
    ) -> Item {
        var item = Item(
            id: "item-\(number)", projectId: "P1", kind: .issue, position: Double(number), statusId: status, dueDate: due,
            contentId: "I\(number)", number: number, title: title, body: "", state: closed ? "CLOSED" : "OPEN",
            stateReason: closed ? "COMPLETED" : nil, repo: "CIATA-io/pia-l4ra-umbrella",
            updatedAt: (updated ?? today).date(),
            parentId: parent.map { "I\($0)" }, parentNumber: parent,
            assignees: assignees.map { Person(id: "U-\($0)", login: $0) },
            labels: labels.map { LabelRef(id: "L-\($0)", name: $0, color: "ffffff") },
            milestoneId: milestone.map { "M-\($0)" }, milestoneTitle: milestone
        )
        if let iteration { item.fieldValues["F-it"] = FieldValue(iterationId: iteration) }
        if let workstream { item.fieldValues["F-ws"] = FieldValue(optionId: workstream) }
        if let points { item.fieldValues["F-points"] = FieldValue(number: points) }
        return item
    }

    func matches(_ filter: String, _ item: Item) -> Bool {
        ProjectFilter(filter).matches(item, Self.context)
    }

    // MARK: Reading and writing

    @Test("Terms, values and quotes are read as GitHub writes them")
    func reads() {
        let filter = ProjectFilter(#"label:DSGVO,MDR,"EU AI Act",Audit -status:Done milestone:"V2 – Compliance & Quick Wins" chat"#)
        #expect(filter.terms.count == 4)
        #expect(filter.terms[0].key == "label")
        #expect(filter.terms[0].values == ["DSGVO", "MDR", "EU AI Act", "Audit"])
        #expect(filter.terms[1].negated)
        #expect(filter.terms[1].values == ["Done"])
        #expect(filter.terms[2].values == ["V2 – Compliance & Quick Wins"])
        #expect(filter.terms[3].key == nil)
        #expect(filter.terms[3].values == ["chat"])
    }

    @Test("A filter is written back as it was, and changed terms are written in GitHub's way")
    func writesBack() {
        let text = #"label:DSGVO,"EU AI Act"  is:open   -label:epic"#
        let filter = ProjectFilter(text)
        #expect(filter.text == #"label:DSGVO,"EU AI Act" is:open -label:epic"#)
        let added = filter.adding(key: "label", value: "A11y")
        #expect(added.text == #"label:DSGVO,"EU AI Act",A11y is:open -label:epic"#)
        let assigned = added.adding(key: "assignee", value: "@me")
        #expect(assigned.text.hasSuffix("assignee:@me"))
        let workstream = ProjectFilter("").adding(key: "workstream", value: "Quick Wins: Konto & Chat")
        #expect(workstream.text == #"workstream:"Quick Wins: Konto & Chat""#)
        #expect(ProjectFilter(workstream.text) == workstream)
        let negated = ProjectFilter("status:Done").replacing(0, with: ProjectFilter("status:Done").terms[0].changed { $0.negated = true })
        #expect(negated.text == "-status:Done")
    }

    @Test("A value already in the term isn't added twice, and is: never lists alternatives")
    func addsOnce() {
        let filter = ProjectFilter("label:ui").adding(key: "label", value: "UI")
        #expect(filter.text == "label:ui")
        #expect(ProjectFilter("is:open").adding(key: "is", value: "issue").text == "is:open is:issue")
    }

    // MARK: Checking issues

    @Test("Labels: any of the values, none of them with a minus, and both when the term is repeated")
    func labels() {
        let ap2 = Self.item(1, labels: ["AP2", "EU AI Act"])
        let other = Self.item(2, labels: ["UX"])
        #expect(matches("label:AP1,AP2,AP3,AP4,AP5,AP6,AP7", ap2))
        #expect(!matches("label:AP1,AP2,AP3,AP4,AP5,AP6,AP7", other))
        #expect(matches(#"label:DSGVO,MDR,"EU AI Act",Audit,A11y,TMG"#, ap2))
        #expect(!matches("-label:epic,AP2", ap2))
        #expect(matches("-label:epic", ap2))
        #expect(matches("label:ap2 label:\"eu ai act\"", ap2))
        #expect(!matches("label:AP1 label:AP2", ap2))
        #expect(matches("label:*AI*", ap2))
    }

    @Test("Status and other single selects by the name of their option, in any case")
    func singleSelects() {
        let done = Self.item(1, status: "s-done", workstream: "w-quick")
        #expect(matches("status:done", done))
        #expect(!matches("-status:Done", done))
        #expect(matches("status:Backlog,Done", done))
        #expect(matches(#"workstream:"Quick Wins: Konto & Chat""#, done))
        #expect(!matches("workstream:Faithfulness-Score", done))
        #expect(matches("has:workstream", done))
        #expect(matches("no:workstream", Self.item(2)))
    }

    @Test("Open, closed, assignees with @me, milestones and parents")
    func issueFacts() {
        let mine = Self.item(1, assignees: ["lukaskaibel"], milestone: "V2 – Compliance & Quick Wins", parent: 217)
        let closed = Self.item(2, closed: true)
        #expect(matches("label:Meeting-Todo is:open", Self.item(3, labels: ["Meeting-Todo"])))
        #expect(!matches("label:Meeting-Todo is:open", Self.item(4, labels: ["Meeting-Todo"], closed: true)))
        #expect(matches("is:closed reason:completed", closed))
        #expect(matches("assignee:@me", mine))
        #expect(!matches("assignee:@me", closed))
        #expect(matches("no:assignee", closed))
        #expect(matches(#"milestone:"V2 – Compliance & Quick Wins""#, mine))
        #expect(matches("has:milestone", mine))
        #expect(!matches("has:milestone", closed))
        #expect(matches("parent-issue:CIATA-io/pia-l4ra-umbrella#217", mine))
        #expect(!matches("parent-issue:CIATA-io/pia-l4ra-umbrella#218", mine))
    }

    @Test("Iterations by title, @current, @next, @previous, offsets, comparisons and ranges")
    func iterations() {
        let current = Self.item(1, iteration: "c17")
        let last = Self.item(2, iteration: "c16")
        let earlier = Self.item(3, iteration: "c15")
        let none = Self.item(4)
        #expect(matches("iteration:@current", current))
        #expect(!matches("iteration:@current", last))
        #expect(!matches("iteration:@current", none))
        #expect(matches("-iteration:@current", none))
        #expect(matches("iteration:@previous", last))
        #expect(matches("iteration:@current-2", earlier))
        #expect(matches("iteration:@next", Self.item(5, iteration: "c18")))
        #expect(matches(#"iteration:"Cycle 15 · KW 40""#, earlier))
        #expect(matches("iteration:<@current", last))
        #expect(!matches("iteration:<@current", current))
        #expect(matches("iteration:@previous..@current", current))
        #expect(matches("iteration:@previous..@current", last))
        #expect(!matches("iteration:@previous..@current", earlier))
    }

    @Test("GitHub's moments are read by hand as the system reads them")
    func moments() {
        let system = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for text in ["2026-10-14T09:12:00Z", "1999-12-31T23:59:59Z", "2024-02-29T00:00:01Z", "1970-01-01T00:00:00Z", "2100-03-01T12:30:45Z"] {
            #expect(ProjectFilter.Term.date(text) == system.date(from: text), "\(text)")
        }
        for text in ["2026-10-14T09:12:00.5Z", "2026-10-14T09:12:00.123Z"] {
            let mine = ProjectFilter.Term.date(text)?.timeIntervalSince1970 ?? 0
            let theirs = fractional.date(from: text)?.timeIntervalSince1970 ?? 1
            #expect(abs(mine - theirs) < 0.001, "\(text)")
        }
        #expect(ProjectFilter.Term.date("2026-10-14T09:12:00+02:00") == system.date(from: "2026-10-14T09:12:00+02:00"))
        #expect(ProjectFilter.Term.date("not a date") == nil)
        #expect(ProjectFilter.Term.date("2026-13-14T09:12:00Z") == nil)
    }

    @Test("Dates: days, @today with offsets, comparisons and ranges")
    func dates() {
        let overdue = Self.item(1, due: "2026-10-13")
        let later = Self.item(2, due: "2026-10-30")
        #expect(matches("due-date:<@today", overdue))
        #expect(!matches("due-date:<@today", later))
        #expect(matches("due-date:>=2026-10-14", later))
        #expect(matches("due-date:@today..@today+30d", later))
        #expect(matches("has:due-date", overdue))
        #expect(matches("no:due-date", Self.item(3)))
        #expect(matches("updated:>@today-7d", Self.item(4, updated: Self.today.adding(days: -2))))
        #expect(!matches("updated:>@today-7d", Self.item(5, updated: Self.today.adding(days: -20))))
        #expect(matches("updated:>@today-1w", Self.item(6, updated: Self.today.adding(days: -3))))
    }

    @Test("Numbers: equal, comparisons and ranges with a wildcard")
    func numbers() {
        let three = Self.item(1, points: 3)
        #expect(matches("points:3", three))
        #expect(matches("points:>2", three))
        #expect(!matches("points:>3", three))
        #expect(matches("points:*..5", three))
        #expect(matches("points:1..3", three))
    }

    @Test("Words to search for and unknown qualifiers are left to GitHub")
    func asksGitHub() {
        let context = Self.context
        #expect(!ProjectFilter("label:AP1,AP2 iteration:@current is:open").needsServer(context))
        #expect(ProjectFilter("label:AP1 chat").needsServer(context))
        #expect(ProjectFilter("sub-issues-progress:100").needsServer(context))
        #expect(ProjectFilter("reviewers:octocat").needsServer(context))
        // What the app can check still narrows the list; the rest passes until GitHub says.
        #expect(matches("label:AP1 chat", Self.item(1, labels: ["AP1"])))
        #expect(!matches("label:AP1 chat", Self.item(2, labels: ["AP2"])))
    }

    @Test("Every filter of the views in PIA, LOGIT and Issues for GitHub is read and understood")
    func realViews() {
        let filters = [
            "", "iteration:@current", #"milestone:"V2 – Compliance & Quick Wins""#, "has:milestone",
            "label:AP1,AP2,AP3,AP4,AP5,AP6,AP7", #"label:DSGVO,MDR,"EU AI Act",Audit,A11y,TMG"#, "label:Meeting-Todo is:open",
            #"milestone:"0.4.0" -label:epic"#, #"milestone:"0.3.0","0.4.0" -label:epic"#, "label:epic is:open",
            "status:Backlog is:open -label:epic", "status:Inbox", #"milestone:"5.3.2","5.4","5.5","5.6","5.7" -label:epic"#,
            "-status:Done", "-status:done",
        ]
        let context = Self.context
        for text in filters {
            let filter = ProjectFilter(text)
            #expect(filter.text == text, "\(text)")
            #expect(!filter.needsServer(context), "\(text)")
        }
    }
}
