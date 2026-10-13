import Foundation

// Everything the assistant says to the language model: its instructions, the tools, the board as text and the
// answers to its tool calls. None of it is shown in the app, so it stays English and out of the String Catalog
// (LocalizationTests skips this file).

/// What the person using the app has set up for the texts the assistant writes.
public struct PlanStyle: Sendable {
    public var style: String
    public var sensitive: String
    /// Names in the text and the GitHub logins they stand for, as the user set them up.
    public var people: [String: String]

    public init(style: String = PlanStyle.defaultStyle, sensitive: String = PlanStyle.defaultSensitive, people: [String: String] = [:]) {
        self.style = style
        self.sensitive = sensitive
        self.people = people
    }

    public static let defaultStyle = "Factual. No thanks, no pleasantries, no filler."
    public static let defaultSensitive = "money, funding and negotiation strategy, salaries, personal matters about people, anything said in confidence"
}

enum PlanText {
    // MARK: Instructions

    static func system(style: PlanStyle, input: PlanInput, viewer: String) -> String {
        let weekday = CalendarDay(input.date).map { $0.date().formatted(Date.FormatStyle(locale: Locale(identifier: "en_US")).weekday(.wide)) } ?? ""
        var people = "The person using this app is \(viewer); \"I\" in a dictation means them."
        if !style.people.isEmpty {
            people += " Names the user has mapped: " + style.people.sorted { $0.key < $1.key }.map { "\($0.key) = \($0.value)" }.joined(separator: ", ") + "."
        }
        return """
        You help keep a GitHub project's issues up to date. You get a text (meeting notes, a transcript, a dictation) \
        and the project's current issues, and you propose the changes the text calls for: new issues, comments, status, \
        assignees, labels, due dates, types, priorities, sub-issues, blockers, closing. You never change anything \
        yourself. A person reviews every proposal and accepts or rejects it; only then does the app apply it.

        ## How to work
        1. Go through the whole text and note every decision, action item, status update, new problem and open \
        question that concerns the project's work.
        2. Find the issues each point concerns. The open issues are listed in the first message. search_issues also \
        finds closed issues (a point may already be settled or done) and words inside issue texts. Issue numbers \
        spoken in the text ("the 120") are hints to check, not certainties.
        3. Read every issue you want to change or comment on with get_issues first, several per call: its text, latest \
        comments, fields, parent, sub-issues and blockers. The app refuses proposals for issues you haven't read.
        4. Decide per point: change or comment on an existing issue, create a new one, or nothing. Propose with the \
        propose_* tools. Make several tool calls per turn when they don't depend on each other.
        5. When every point is handled, call finish once and list the points you deliberately left alone.

        ## Good proposals
        - Prefer existing issues. Create an issue only when no open or closed issue covers the point. Group several new \
        points on one topic under one new parent issue. Put small follow-ups as a checklist ("- [ ] …") into an issue's \
        text rather than making separate issues.
        - A comment records what the text adds to an issue: decisions, new facts, who does what by when, open \
        questions. Not a summary of the whole meeting, and nothing the issue already says.
        - Change a field only when the text says so or clearly implies it: someone takes it over → assignee, "blocked \
        until …" → a blocked status, "by Friday" → due date.
        - Close an issue only on an explicit decision in the text that it is done, obsolete or a duplicate.
        - Don't propose what already holds. The app checks every proposal against the current state and drops what is \
        already so.
        - Every proposal carries a short reason and a quote: a passage copied word for word from the text (a sentence or \
        part of one, no "…" inside).
        - Tool results tell you what was accepted, dropped or rejected. Fix rejected proposals and carry on.

        ## People
        Assign only logins from the list of assignable people. Map a name in the text to a login only when it is clear \
        (the person's name matches); otherwise don't assign, and name the person in the text instead. \(people)

        ## Dates
        Work out absolute dates from the text's date: it is from \(input.date), a \(weekday).

        ## Texts written to GitHub
        - Write in the language the project's issues are written in.
        - Style: \(style.style)
        - Start with the matter itself. Link issues as #123. Refer to a new issue of this plan by its ref in double \
        braces, {{A}}; the app puts in the number once the issue exists.
        - No footer or signature: the app appends "\(input.footer)" to every comment and new issue.
        - The project is readable by the whole team. Leave out \(style.sensitive). If a point is only about such things, \
        list it under skipped in finish without repeating its content.

        ## New issues
        Give each new issue a ref: A, B, C … Use {{A}} as issue, parent or other in later proposals and in texts.
        """
    }

    static func context(facts: BoardFacts, open: [PlanIssue], input: PlanInput) -> String {
        var lines: [String] = []
        lines.append("# Project")
        lines.append("\"\(facts.projectTitle)\", project #\(facts.projectNumber) of \(facts.projectOwner). Repositories: \(facts.repos.joined(separator: ", ")) (the first is the default).")
        lines.append("Statuses: \(facts.statuses.joined(separator: ", "))")
        lines.append("Priorities: \(facts.priorities.isEmpty ? "none (the project has no priority field)" : facts.priorities.joined(separator: ", "))")
        lines.append("Due dates: \(facts.hasDueField ? "yes" : "yes (the app adds the field when needed)")")
        for repo in facts.repos {
            guard let repoFacts = facts.repoFacts[repo] else { continue }
            func named(_ list: [RepoFacts.Named]) -> String {
                list.isEmpty ? "none" : list.map { $0.description.isEmpty ? $0.name : "\($0.name) (\($0.description))" }.joined(separator: "; ")
            }
            lines.append("Issue types in \(repo): \(named(repoFacts.issueTypes))")
            lines.append("Labels in \(repo): \(named(repoFacts.labels))")
            let milestones = facts.milestones[repo] ?? []
            lines.append("Open milestones in \(repo): \(milestones.isEmpty ? "none" : milestones.joined(separator: "; "))")
            let people = repoFacts.people.map { person -> String in
                var text = person.description.isEmpty ? person.name : "\(person.name) (\(person.description))"
                if person.name == facts.viewer { text += " = the user" }
                return text
            }
            lines.append("Assignable people in \(repo): \(people.joined(separator: ", "))")
        }
        lines.append("")
        lines.append("# Open issues (\(open.count))")
        lines.append("Each line: #number title | status | type | assignees | labels | parent | due | priority (empty parts left out)")
        lines += open.map(indexLine)
        lines.append("")
        lines.append("# The text: \"\(input.title)\", \(input.date)")
        lines.append("<text>")
        lines.append(input.text)
        lines.append("</text>")
        lines.append("")
        lines.append("Work through the text now as described.")
        return lines.joined(separator: "\n")
    }

    static func indexLine(_ issue: PlanIssue) -> String {
        var parts = ["\(issue.reference) \(issue.title)"]
        if let status = issue.status { parts.append(status) }
        if let type = issue.type { parts.append(type) }
        if !issue.assignees.isEmpty { parts.append(issue.assignees.map { "@\($0)" }.joined(separator: " ")) }
        if !issue.labels.isEmpty { parts.append("[\(issue.labels.joined(separator: ", "))]") }
        if let parent = issue.parent { parts.append("parent #\(parent)") }
        if let due = issue.due { parts.append("due \(due)") }
        if let priority = issue.priority { parts.append("priority \(priority)") }
        return parts.joined(separator: " | ")
    }

    static func searchLine(_ issue: PlanIssue, snippet: String?) -> String {
        var line = "\(issue.isOpen ? "open" : "closed\(issue.stateReason.map { " (\($0.lowercased()))" } ?? "")") " + indexLine(issue)
        if let snippet { line += "\n    …\(snippet)…" }
        return line
    }

    static func noResults(_ query: String) -> String {
        "No issue matches \"\(query)\". Try other or fewer words, or state \"all\"."
    }

    static func detail(_ issue: PlanIssue, _ detail: PlanDetail, footer: String) -> String {
        func links(_ list: [PlanDetail.Link]) -> String {
            list.isEmpty ? "none" : list.map { "#\($0.number) \($0.title) (\($0.isOpen ? "open" : "closed"))" }.joined(separator: "; ")
        }
        var lines = ["## \(issue.reference) \(issue.title)"]
        let state = issue.isOpen ? "open" : "closed\(issue.stateReason.map { " as \($0.lowercased())" } ?? "")"
        lines.append([
            state, "repository \(issue.repo)", issue.onBoard ? "on the board" : "not on the board",
            "status \(issue.status ?? "none")", "priority \(issue.priority ?? "none")", "type \(issue.type ?? "none")",
            "due \(issue.due ?? "none")", "milestone \(issue.milestone ?? "none")",
            "labels \(issue.labels.isEmpty ? "none" : issue.labels.joined(separator: ", "))",
            "assignees \(issue.assignees.isEmpty ? "none" : issue.assignees.map { "@\($0)" }.joined(separator: " "))",
        ].joined(separator: " · "))
        lines.append("parent: \(issue.parent.map { "#\($0) \(issue.parentTitle ?? "")" } ?? "none")")
        lines.append("sub-issues: \(links(detail.subIssues))")
        lines.append("blocked by: \(links(detail.blockedBy))")
        lines.append("blocking: \(links(detail.blocking))")
        if let created = issue.createdAt { lines.append("created \(created.formatted(.iso8601.year().month().day()))") }
        lines.append("### Text")
        lines.append(issue.body.isEmpty ? "(empty)" : clip(issue.body, 3500))
        let shown = detail.comments.suffix(6)
        lines.append("### Comments (\(shown.count == detail.comments.count ? "\(shown.count)" : "latest \(shown.count) of \(detail.comments.count)"))")
        for comment in shown {
            let mark = comment.body.contains(footer) ? " [written from this same text]" : ""
            lines.append("- @\(comment.authorLogin ?? "ghost"), \(comment.createdAt.formatted(.iso8601.year().month().day()))\(mark): \(clip(comment.body, 1000))")
        }
        return lines.joined(separator: "\n")
    }

    private static func clip(_ text: String, _ limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(limit)) + " […cut]"
    }

    // MARK: Answers to tool calls

    static func unknownTool(_ name: String) -> String { "There is no tool \"\(name)\"." }
    static func unreadableArguments(_ detail: String) -> String { "The arguments weren't valid JSON: \(detail)" }
    static func missing(_ field: String) -> String { "\"\(field)\" is required and can't be empty." }
    static func tooMany(_ count: Int, max: Int) -> String { "At most \(max) per call; you asked for \(count)." }
    static func noSuchIssue(_ reference: String) -> String {
        "There is no issue \(reference) (or it is hidden). Use search_issues to find the right one."
    }
    static func notRead(_ number: Int) -> String {
        "Read #\(number) with get_issues before proposing changes to it."
    }
    static func notFound(_ numbers: [Int]) -> String {
        "Not found: \(numbers.map { "#\($0)" }.joined(separator: ", "))."
    }
    static func badRef(_ ref: String) -> String {
        "\"\(ref)\" isn't a valid ref. Use capital letters, such as A, B or AB."
    }
    static func refTaken(_ ref: String) -> String { "The ref \(ref) is already used. Pick another one." }
    enum Thing {
        case status, priority, issueType, milestone, label, repository

        var word: String {
            switch self {
            case .status: "Status"
            case .priority: "Priority"
            case .issueType: "Issue type"
            case .milestone: "Milestone"
            case .label: "Label"
            case .repository: "Repository"
            }
        }
    }

    static func unknown(_ what: Thing, _ value: String, options: [String]) -> String {
        "\(what.word) \"\(value)\" doesn't exist. Choose one of: \(options.isEmpty ? "(none exist)" : options.joined(separator: ", "))."
    }
    static func alreadyIs(_ number: Int, _ field: String, _ value: String?) -> String {
        "#\(number) \(field) is already \(value ?? "none")"
    }
    static func alreadyHolds(_ number: Int, _ kind: PlanOperation.Kind, _ names: [String]) -> String {
        let state = switch kind {
        case .assign: "already assigned"
        case .unassign: "not assigned"
        case .addLabels: "already labelled"
        default: "doesn't have the label"
        }
        return "#\(number) \(state): \(names.joined(separator: ", "))"
    }
    static func alreadySubIssue(_ number: Int, of parent: Int) -> String { "#\(number) is already a sub-issue of #\(parent)" }
    static func alreadyBlocked(_ number: Int, by blocker: Int) -> String { "#\(number) is already blocked by #\(blocker)" }
    static func alreadyClosed(_ number: Int) -> String { "#\(number) is already closed" }
    static func notAssignable(_ logins: [String], people: [String]) -> String {
        "Not assignable: \(logins.joined(separator: ", ")). Assignable: \(people.joined(separator: ", ")). If the person isn't among them, don't assign."
    }
    static func badDate(_ value: String) -> String { "\"\(value)\" isn't a day like 2026-10-19 (or \"none\" to clear it)." }
    static func nothingToChange() -> String { "Nothing to change: all fields were empty." }
    static func useNewIssueFields() -> String {
        "That issue is new in this plan: set its fields in propose_new_issue, or retract it and propose it again."
    }
    static func accepted(_ operations: [String], dropped: [String], warnings: [String]) -> String {
        var lines: [String] = []
        if !operations.isEmpty { lines.append("Accepted: " + operations.joined(separator: "; ")) }
        if !dropped.isEmpty { lines.append("Dropped, already so: " + dropped.joined(separator: "; ")) }
        if operations.isEmpty, !dropped.isEmpty { lines.append("Nothing to propose here.") }
        lines += warnings.map { "Note: \($0)" }
        return lines.joined(separator: "\n")
    }
    static func alreadyCommented(_ number: Int, on date: String) -> String {
        "#\(number) already has a comment written from this same text (\(date)). Don't comment again."
    }
    static func writtenFromThisText(_ issue: PlanIssue) -> String {
        "#\(issue.number) \"\(issue.title)\" was already created from this same text. Use it instead of creating another issue."
    }
    static func possibleDuplicates(_ issues: [PlanIssue]) -> String {
        "possible duplicate of " + issues.map { "#\($0.number) \"\($0.title)\" (\($0.isOpen ? "open" : "closed"))" }.joined(separator: ", ")
            + ". If one covers the point, retract this and use it."
    }
    static func quoteNotFound() -> String {
        "the quote isn't word for word in the text. Copy a passage exactly."
    }
    static func closeNeedsQuote() -> String {
        "Closing needs a quote copied word for word from the text that shows the decision. This one isn't in the text."
    }
    static func unknownRefInText(_ refs: [String]) -> String {
        "the text refers to \(refs.map { "{{\($0)}}" }.joined(separator: ", ")), which no proposed new issue has (yet)."
    }
    static func unknownRefTarget(_ ref: String) -> String {
        "{{\(ref)}} isn't a new issue of this plan (yet). Propose it with propose_new_issue first."
    }
    static func relationToItself() -> String { "An issue can't be related to itself." }
    static func movesParent(from parent: Int) -> String { "this moves the issue out of its current parent #\(parent)." }
    static func editNotFound(_ find: String) -> String { "Not in the issue's text: \"\(find)\". Copy the passage exactly." }
    static func editAmbiguous(_ find: String) -> String { "\"\(find)\" occurs more than once; include more of the line." }
    static func retracted(_ ids: [String], unknown: [String]) -> String {
        var text = ids.isEmpty ? "" : "Retracted: \(ids.joined(separator: ", "))."
        if !unknown.isEmpty { text += " Unknown: \(unknown.joined(separator: ", "))." }
        return text.trimmingCharacters(in: .whitespaces)
    }
    static func unresolvedRefs(_ refs: [String]) -> String {
        "Before finishing: \(refs.map { "{{\($0)}}" }.joined(separator: ", ")) are used but no new issue has that ref. Propose them or fix the references, then call finish again."
    }
    static func finished(_ count: Int) -> String { "Done: \(count) proposals go to review." }
    static func nudge() -> String {
        "Continue with the tools. When every point of the text is handled, call finish."
    }
    static func finishNow() -> String {
        "The time or token budget is used up. Call finish now with what you have proposed; list unhandled points under skipped."
    }
    static func cutOff() -> String {
        "Your last answer was cut off. Make fewer or shorter tool calls per turn."
    }

    // MARK: How changes read, for the operation lists

    static func describe(_ operation: PlanOperation) -> String {
        let target = "\(operation.id) \(operation.issue)"
        return switch operation.kind {
        case .create: "\(target) new issue \"\(operation.title ?? "")\""
        case .comment: "\(target) comment"
        case .setStatus: "\(target) status \(operation.before ?? "none") → \(operation.after ?? "")"
        case .setPriority: "\(target) priority \(operation.before ?? "none") → \(operation.after ?? "")"
        case .setDue: "\(target) due \(operation.before ?? "none") → \(operation.after ?? "")"
        case .setType: "\(target) type \(operation.before ?? "none") → \(operation.after ?? "")"
        case .setMilestone: "\(target) milestone \(operation.before ?? "none") → \(operation.after ?? "")"
        case .assign: "\(target) assign \(operation.values?.joined(separator: ", ") ?? "")"
        case .unassign: "\(target) unassign \(operation.values?.joined(separator: ", ") ?? "")"
        case .addLabels: "\(target) add labels \(operation.values?.joined(separator: ", ") ?? "")"
        case .removeLabels: "\(target) remove labels \(operation.values?.joined(separator: ", ") ?? "")"
        case .subIssueOf: "\(target) sub-issue of \(operation.value ?? "")"
        case .blockedBy: "\(target) blocked by \(operation.value ?? "")"
        case .close: "\(target) close as \(operation.value ?? "")"
        case .editBody: "\(target) edit text (\(operation.edits?.count ?? 0) changes)"
        }
    }

    // MARK: Tools

    static let tools: [LLMToolSpec] = [
        LLMToolSpec(
            name: "search_issues",
            description: """
            Finds issues of the project by words in their title, text or (already read) comments, including closed \
            issues and issues that aren't on the board. Results show state, fields and a snippet. A number ("400" or \
            "#400") looks up that issue.
            """,
            parameters: object([
                ("query", string("Words to look for, e.g. \"offline queue\". Issues matching more words rank first.")),
                ("state", ["type": "string", "enum": ["open", "closed", "all"], "description": "Which issues to search."]),
                ("limit", ["type": "integer", "description": "At most this many results, 1 to 30."]),
            ])
        ),
        LLMToolSpec(
            name: "get_issues",
            description: """
            Reads issues in full: fields, parent, sub-issues, blockers, text and latest comments. Read every issue \
            before proposing changes to it. Up to 8 per call.
            """,
            parameters: object([
                ("numbers", ["type": "array", "items": ["type": "integer"], "description": "Issue numbers, e.g. [494, 537]."]),
            ])
        ),
        LLMToolSpec(
            name: "propose_new_issue",
            description: """
            Proposes a new issue. Give it a ref (A, B, …) so other proposals and texts can point to it as {{A}}. Leave \
            a field empty ("" or []) to leave it unset. Search first: create an issue only when none covers the point.
            """,
            parameters: object([
                ("ref", string("A, B, C …, unique in this plan.")),
                ("repo", string("owner/name, or \"\" for the project's default repository.")),
                ("title", string("Short and specific, in the project's language.")),
                ("body", string("The issue's text in Markdown. No footer; the app adds it.")),
                ("type", string("An issue type of the repository, or \"\".")),
                ("status", string("A status of the project, or \"\" for none.")),
                ("priority", string("A priority of the project, or \"\".")),
                ("due", string("The day it is due, 2026-10-19, or \"\".")),
                ("labels", strings("Existing labels of the repository.")),
                ("assignees", strings("Logins of assignable people.")),
                ("parent", string("The parent issue: \"#123\", \"{{B}}\" for another new issue, or \"\".")),
                ("reason", string("Why, in one sentence.")),
                ("quote", string("A passage of the text, word for word, that shows the point.")),
            ])
        ),
        LLMToolSpec(
            name: "propose_comment",
            description: "Proposes a comment on an issue you have read: what the text adds to it.",
            parameters: object([
                ("issue", string("\"#123\" or \"{{A}}\".")),
                ("body", string("The comment in Markdown. No footer; the app adds it.")),
                ("reason", string("Why, in one sentence.")),
                ("quote", string("A passage of the text, word for word.")),
            ])
        ),
        LLMToolSpec(
            name: "propose_update",
            description: """
            Proposes changes to an existing issue's fields. Empty strings and lists mean "leave as it is". The app drops \
            what already holds and tells you.
            """,
            parameters: object([
                ("issue", string("\"#123\".")),
                ("status", string("New status, or \"\".")),
                ("priority", string("New priority, or \"\".")),
                ("due", string("New due day 2026-10-19, \"none\" to clear, or \"\".")),
                ("type", string("New issue type, or \"\".")),
                ("milestone", string("Open milestone title, \"none\" to clear, or \"\".")),
                ("add_assignees", strings("Logins to assign.")),
                ("remove_assignees", strings("Logins to unassign.")),
                ("add_labels", strings("Labels to add.")),
                ("remove_labels", strings("Labels to remove.")),
                ("reason", string("Why, in one sentence.")),
                ("quote", string("A passage of the text, word for word.")),
            ])
        ),
        LLMToolSpec(
            name: "propose_relation",
            description: """
            Proposes a relation: "sub_issue_of" makes issue a sub-issue of other (moving it out of a parent it has); \
            "blocked_by" marks issue as blocked by other.
            """,
            parameters: object([
                ("issue", string("\"#123\" or \"{{A}}\".")),
                ("relation", ["type": "string", "enum": ["sub_issue_of", "blocked_by"], "description": "The kind of relation."]),
                ("other", string("\"#456\" or \"{{B}}\".")),
                ("reason", string("Why, in one sentence.")),
                ("quote", string("A passage of the text, word for word.")),
            ])
        ),
        LLMToolSpec(
            name: "propose_close",
            description: "Proposes closing an issue. Only on an explicit decision in the text; the quote must show it.",
            parameters: object([
                ("issue", string("\"#123\".")),
                ("close_reason", ["type": "string", "enum": ["completed", "not_planned", "duplicate"], "description": "Why it is closed."]),
                ("duplicate_of", string("\"#456\" when it is a duplicate, else \"\".")),
                ("reason", string("Why, in one sentence.")),
                ("quote", string("The decision, word for word from the text.")),
            ])
        ),
        LLMToolSpec(
            name: "propose_body_edit",
            description: """
            Proposes edits to an issue's text, e.g. ticking a checklist item: "- [ ] Release notes" → "- [x] Release notes". Each find \
            must occur exactly once in the current text.
            """,
            parameters: object([
                ("issue", string("\"#123\".")),
                ("edits", [
                    "type": "array",
                    "items": object([("find", string("Exact passage of the current text.")), ("replace", string("What replaces it."))]),
                    "description": "The edits, applied in order.",
                ]),
                ("reason", string("Why, in one sentence.")),
                ("quote", string("A passage of the text, word for word.")),
            ])
        ),
        LLMToolSpec(
            name: "retract",
            description: "Withdraws proposals you no longer want, by their ids (op3, op7 …).",
            parameters: object([
                ("ids", strings("Proposal ids.")),
                ("why", string("Why, in one sentence.")),
            ])
        ),
        LLMToolSpec(
            name: "finish",
            description: "Ends the work once every point of the text is handled. Call it once, at the end.",
            parameters: object([
                ("summary", string("Two or three sentences on what you proposed.")),
                ("skipped", [
                    "type": "array",
                    "items": object([("point", string("The point, briefly.")), ("why", string("Why nothing is proposed for it."))]),
                    "description": "Points of the text you deliberately left alone: already done, no issue needed, confidential …",
                ]),
            ])
        ),
    ]

    private static func object(_ properties: [(String, JSONValue)]) -> JSONValue {
        [
            "type": "object",
            "properties": .object(Dictionary(uniqueKeysWithValues: properties)),
            "required": .array(properties.map { .string($0.0) }),
            "additionalProperties": false,
        ]
    }

    private static func string(_ description: String) -> JSONValue {
        ["type": "string", "description": .string(description)]
    }

    private static func strings(_ description: String) -> JSONValue {
        ["type": "array", "items": ["type": "string"], "description": .string(description)]
    }
}

extension LLMError: LocalizedError {
    // Shown by the command-line tool for now; these move into the String Catalog with the feature's window.
    public var errorDescription: String? {
        switch self {
        case .missingKey(let provider): "No API key for \(provider.rawValue)."
        case .invalidKey(let provider): "\(provider.rawValue) rejected the API key."
        case .rateLimited(let provider): "\(provider.rawValue): too many requests."
        case .overloaded(let provider): "\(provider.rawValue) is overloaded."
        case .refused(let reason): "The model declined (\(reason))."
        case .truncated: "The answer was cut off."
        case .server(let provider, let status, let message): "\(provider.rawValue) answered \(status): \(message)"
        case .unreachable(let provider, let message): "\(provider.rawValue) can't be reached: \(message)"
        case .badResponse(let message): "Unusable answer: \(message)"
        case .noModels(let provider): "\(provider.rawValue) offers no suitable model."
        }
    }
}
