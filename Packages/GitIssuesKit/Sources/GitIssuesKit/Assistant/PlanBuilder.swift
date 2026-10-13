import Foundation

/// Runs the assistant's tool calls: answers the reading tools from the board, and checks every proposal against the
/// board before it joins the plan. What already holds is dropped; what can't work is refused with the reason, so the
/// model can fix it in the next turn.
final class PlanBuilder {
    struct Outcome {
        var text: String
        var isError: Bool
        var finished = false
    }

    private enum Target {
        case existing(PlanIssue)
        /// A new issue of this plan, by its ref.
        case new(String)

        var display: String {
            switch self {
            case .existing(let issue): issue.reference
            case .new(let ref): "{{\(ref)}}"
            }
        }
    }

    let world: PlanWorld
    let facts: BoardFacts
    let input: PlanInput
    private(set) var operations: [PlanOperation] = []
    private(set) var dropped: [PlanNote] = []
    private(set) var skipped: [PlanNote] = []
    private(set) var summary = ""
    private(set) var finished = false
    /// Issues read in full in this run.
    private var read: Set<String> = []
    /// New issues by ref, and the id of the proposal that creates each.
    private var refs: [String: String] = [:]
    private var counter = 0
    private let foldedInput: String
    private let inputPairs: Set<String>

    init(world: PlanWorld, facts: BoardFacts, input: PlanInput) {
        self.world = world
        self.facts = facts
        self.input = input
        let words = Self.plainWords(input.text)
        foldedInput = " " + words.joined(separator: " ") + " "
        inputPairs = Set(zip(words, words.dropFirst()).map { "\($0) \($1)" })
    }

    func handle(_ call: LLMToolCall) async -> Outcome {
        if let problem = call.unreadable { return Outcome(text: PlanText.unreadableArguments(problem), isError: true) }
        let args = call.arguments
        do {
            switch call.name {
            case "search_issues": return await search(args)
            case "get_issues": return await getIssues(args)
            case "propose_new_issue": return try await proposeNewIssue(args)
            case "propose_comment": return try await proposeComment(args)
            case "propose_update": return try await proposeUpdate(args)
            case "propose_relation": return try await proposeRelation(args)
            case "propose_close": return try await proposeClose(args)
            case "propose_body_edit": return try await proposeBodyEdit(args)
            case "retract": return retract(args)
            case "finish": return finish(args)
            default: return Outcome(text: PlanText.unknownTool(call.name), isError: true)
            }
        } catch let refusal as Refusal {
            return Outcome(text: refusal.message, isError: true)
        } catch {
            return Outcome(text: error.localizedDescription, isError: true)
        }
    }

    private struct Refusal: Error {
        var message: String
    }

    // MARK: Reading

    private func search(_ args: JSONValue) async -> Outcome {
        let query = text(args, "query")
        let state = text(args, "state")
        let open: Bool? = state == "open" ? true : state == "closed" ? false : nil
        let results = await world.search(query, open: open, limit: args["limit"]?.int ?? 15)
        if results.isEmpty { return Outcome(text: PlanText.noResults(query), isError: false) }
        return Outcome(text: results.map { PlanText.searchLine($0.issue, snippet: $0.snippet) }.joined(separator: "\n"), isError: false)
    }

    private func getIssues(_ args: JSONValue) async -> Outcome {
        let numbers = (args["numbers"]?.array ?? []).compactMap(\.int)
        guard !numbers.isEmpty else { return Outcome(text: PlanText.missing("numbers"), isError: true) }
        guard numbers.count <= 8 else { return Outcome(text: PlanText.tooMany(numbers.count, max: 8), isError: true) }
        var parts: [String] = []
        var missing: [Int] = []
        for number in numbers {
            guard let issue = await world.issue(String(number)) else {
                missing.append(number)
                continue
            }
            do {
                let detail = try await world.detail(of: issue)
                read.insert(issue.key)
                parts.append(PlanText.detail(issue, detail, footer: input.footer))
            } catch {
                parts.append("#\(number): \(error.localizedDescription)")
            }
        }
        if !missing.isEmpty { parts.append(PlanText.notFound(missing)) }
        return Outcome(text: parts.joined(separator: "\n\n"), isError: parts.count == 1 && !missing.isEmpty)
    }

    // MARK: Proposals

    private func proposeNewIssue(_ args: JSONValue) async throws -> Outcome {
        let ref = text(args, "ref").trimmingCharacters(in: CharacterSet(charactersIn: "{} "))
        guard ref.wholeMatch(of: #/[A-Z]{1,3}[0-9]{0,2}/#) != nil else { throw Refusal(message: PlanText.badRef(ref)) }
        guard refs[ref] == nil else { throw Refusal(message: PlanText.refTaken(ref)) }
        let repo = try repository(text(args, "repo"))
        let title = text(args, "title")
        guard !title.isEmpty else { throw Refusal(message: PlanText.missing("title")) }
        let repoFacts = facts.repoFacts[repo]
        let type = try pick(text(args, "type"), from: repoFacts?.issueTypes.map(\.name) ?? [], what: .issueType)
        let status = try pick(text(args, "status"), from: facts.statuses, what: .status)
        let priority = try pick(text(args, "priority"), from: facts.priorities, what: .priority)
        let due = try day(text(args, "due"), allowNone: false)
        let labels = try labelNames(list(args, "labels"), repo: repo)
        let assignees = try logins(list(args, "assignees"), repo: repo)
        var warnings: [String] = []
        var parent: String?
        let parentText = text(args, "parent")
        if !parentText.isEmpty {
            let target = try await resolve(parentText, mustBeKnown: false)
            parent = target.display
            if case .new(let parentRef) = target, refs[parentRef] == nil { warnings.append(PlanText.unknownRefTarget(parentRef)) }
        }
        let body = text(args, "body")
        warnings += textRefWarnings(body)
        let quote = text(args, "quote")
        let match = quoteMatch(quote)
        if match == .missing { warnings.append(PlanText.quoteNotFound()) }

        // Was this issue made from the same text before, or does another issue cover it?
        let others = await world.allIssues()
        let ownWords = Self.titleWords(title)
        var similar: [(issue: PlanIssue, score: Double)] = []
        for issue in others {
            let score = Self.similarity(ownWords, Self.titleWords(issue.title))
            if issue.body.contains(input.footer), score >= 0.5 { throw Refusal(message: PlanText.writtenFromThisText(issue)) }
            if score >= 0.4 { similar.append((issue, score)) }
        }
        if !similar.isEmpty {
            warnings.append(PlanText.possibleDuplicates(similar.sorted { $0.score > $1.score }.prefix(3).map(\.issue)))
        }

        let operation = make(
            .create, issue: "{{\(ref)}}", repo: repo, args: args, warnings: warnings, quoteMatch: match,
            title: title, body: withFooter(body),
            newIssue: PlanOperation.NewIssue(
                type: type, status: status, priority: priority, due: due, labels: labels, assignees: assignees, parent: parent
            ),
            after: title
        )
        refs[ref] = operation.id
        operations.append(operation)
        return Outcome(text: PlanText.accepted([PlanText.describe(operation)], dropped: [], warnings: warnings), isError: false)
    }

    private func proposeComment(_ args: JSONValue) async throws -> Outcome {
        let target = try await resolve(text(args, "issue"), mustBeKnown: true)
        let body = text(args, "body")
        guard !body.isEmpty else { throw Refusal(message: PlanText.missing("body")) }
        var repo = facts.defaultRepo
        if case .existing(let issue) = target {
            try requireRead(issue)
            repo = issue.repo
            if let detail = await world.knownDetail(of: issue),
               let earlier = detail.comments.first(where: { $0.body.contains(input.footer) }) {
                throw Refusal(message: PlanText.alreadyCommented(issue.number, on: earlier.createdAt.formatted(.iso8601.year().month().day())))
            }
        }
        let quote = text(args, "quote")
        let match = quoteMatch(quote)
        var warnings = textRefWarnings(body)
        if match == .missing { warnings.append(PlanText.quoteNotFound()) }
        let operation = make(.comment, issue: target.display, repo: repo, args: args, warnings: warnings, quoteMatch: match, body: withFooter(body))
        operations.append(operation)
        return Outcome(text: PlanText.accepted([PlanText.describe(operation)], dropped: [], warnings: warnings), isError: false)
    }

    private func proposeUpdate(_ args: JSONValue) async throws -> Outcome {
        let target = try await resolve(text(args, "issue"), mustBeKnown: true)
        guard case .existing(let issue) = target else { throw Refusal(message: PlanText.useNewIssueFields()) }
        try requireRead(issue)
        let repoFacts = facts.repoFacts[issue.repo]
        let quote = text(args, "quote")
        let match = quoteMatch(quote)
        var warnings: [String] = []
        if match == .missing { warnings.append(PlanText.quoteNotFound()) }
        var proposed: [PlanOperation] = []
        var droppedNow: [String] = []
        var anything = false

        func field(_ kind: PlanOperation.Kind, _ name: String, current: String?, new: String?) {
            anything = true
            if (current ?? "none").caseInsensitiveCompare(new ?? "none") == .orderedSame {
                droppedNow.append(PlanText.alreadyIs(issue.number, name, current))
            } else {
                proposed.append(make(kind, issue: issue.reference, repo: issue.repo, args: args, warnings: warnings, quoteMatch: match, value: new ?? "none", before: current, after: new ?? "none"))
            }
        }

        if let status = try pick(text(args, "status"), from: facts.statuses, what: .status) {
            field(.setStatus, "status", current: issue.status, new: status)
        }
        if let priority = try pick(text(args, "priority"), from: facts.priorities, what: .priority) {
            field(.setPriority, "priority", current: issue.priority, new: priority)
        }
        let dueText = text(args, "due")
        if !dueText.isEmpty {
            field(.setDue, "due date", current: issue.due, new: try day(dueText, allowNone: true))
        }
        if let type = try pick(text(args, "type"), from: repoFacts?.issueTypes.map(\.name) ?? [], what: .issueType) {
            field(.setType, "type", current: issue.type, new: type)
        }
        let milestoneText = text(args, "milestone")
        if !milestoneText.isEmpty {
            let milestone = milestoneText.lowercased() == "none" ? nil : try pick(milestoneText, from: facts.milestones[issue.repo] ?? [], what: .milestone)
            field(.setMilestone, "milestone", current: issue.milestone, new: milestone)
        }

        func people(_ kind: PlanOperation.Kind, _ logins: [String], keep: (String) -> Bool) {
            guard !logins.isEmpty else { return }
            anything = true
            let wanted = logins.filter(keep)
            let skippedLogins = logins.filter { !keep($0) }
            if !skippedLogins.isEmpty { droppedNow.append(PlanText.alreadyHolds(issue.number, kind, skippedLogins)) }
            if !wanted.isEmpty {
                proposed.append(make(kind, issue: issue.reference, repo: issue.repo, args: args, warnings: warnings, quoteMatch: match, values: wanted))
            }
        }
        let assigned = Set(issue.assignees.map { $0.lowercased() })
        people(.assign, try logins(list(args, "add_assignees"), repo: issue.repo), keep: { !assigned.contains($0.lowercased()) })
        people(.unassign, list(args, "remove_assignees").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "@ ")) }, keep: { assigned.contains($0.lowercased()) })
        let labelled = Set(issue.labels.map { $0.lowercased() })
        people(.addLabels, try labelNames(list(args, "add_labels"), repo: issue.repo), keep: { !labelled.contains($0.lowercased()) })
        people(.removeLabels, list(args, "remove_labels"), keep: { labelled.contains($0.lowercased()) })

        guard anything else { throw Refusal(message: PlanText.nothingToChange()) }
        operations += proposed
        dropped += droppedNow.map { PlanNote(what: $0, why: text(args, "reason")) }
        return Outcome(text: PlanText.accepted(proposed.map(PlanText.describe), dropped: droppedNow, warnings: warnings), isError: false)
    }

    private func proposeRelation(_ args: JSONValue) async throws -> Outcome {
        let target = try await resolve(text(args, "issue"), mustBeKnown: true)
        let other = try await resolve(text(args, "other"), mustBeKnown: false)
        guard target.display != other.display else { throw Refusal(message: PlanText.relationToItself()) }
        let relation = text(args, "relation")
        let quote = text(args, "quote")
        let match = quoteMatch(quote)
        var warnings: [String] = []
        if match == .missing { warnings.append(PlanText.quoteNotFound()) }
        if case .new(let ref) = other, refs[ref] == nil { warnings.append(PlanText.unknownRefTarget(ref)) }
        var repo = facts.defaultRepo
        if case .existing(let issue) = target {
            try requireRead(issue)
            repo = issue.repo
            if relation == "sub_issue_of", case .existing(let parent) = other {
                if issue.parent == parent.number {
                    return drop(PlanText.alreadySubIssue(issue.number, of: parent.number), args)
                }
                if let current = issue.parent { warnings.append(PlanText.movesParent(from: current)) }
            }
            if relation == "blocked_by", case .existing(let blocker) = other,
               let detail = await world.knownDetail(of: issue), detail.blockedBy.contains(where: { $0.number == blocker.number }) {
                return drop(PlanText.alreadyBlocked(issue.number, by: blocker.number), args)
            }
        }
        let kind: PlanOperation.Kind = relation == "blocked_by" ? .blockedBy : .subIssueOf
        var before: String?
        if case .existing(let issue) = target, kind == .subIssueOf { before = issue.parent.map { "#\($0)" } }
        let operation = make(kind, issue: target.display, repo: repo, args: args, warnings: warnings, quoteMatch: match, value: other.display, before: before, after: other.display)
        operations.append(operation)
        return Outcome(text: PlanText.accepted([PlanText.describe(operation)], dropped: [], warnings: warnings), isError: false)
    }

    private func proposeClose(_ args: JSONValue) async throws -> Outcome {
        let target = try await resolve(text(args, "issue"), mustBeKnown: true)
        guard case .existing(let issue) = target else { throw Refusal(message: PlanText.useNewIssueFields()) }
        try requireRead(issue)
        if !issue.isOpen { return drop(PlanText.alreadyClosed(issue.number), args) }
        let match = quoteMatch(text(args, "quote"))
        guard match != .missing else { throw Refusal(message: PlanText.closeNeedsQuote()) }
        var reason = text(args, "close_reason")
        if reason == "duplicate" {
            let original = try await resolve(text(args, "duplicate_of"), mustBeKnown: true)
            reason += " of \(original.display)"
        }
        let operation = make(.close, issue: issue.reference, repo: issue.repo, args: args, warnings: [], quoteMatch: match, value: reason, before: "open", after: "closed")
        operations.append(operation)
        return Outcome(text: PlanText.accepted([PlanText.describe(operation)], dropped: [], warnings: []), isError: false)
    }

    private func proposeBodyEdit(_ args: JSONValue) async throws -> Outcome {
        let target = try await resolve(text(args, "issue"), mustBeKnown: true)
        guard case .existing(let issue) = target else { throw Refusal(message: PlanText.useNewIssueFields()) }
        try requireRead(issue)
        let edits = (args["edits"]?.array ?? []).map {
            PlanOperation.TextEdit(find: $0["find"]?.string ?? "", replace: $0["replace"]?.string ?? "")
        }
        guard !edits.isEmpty else { throw Refusal(message: PlanText.missing("edits")) }
        var body = issue.body
        for edit in edits {
            let count = body.components(separatedBy: edit.find).count - 1
            guard !edit.find.isEmpty, count > 0 else { throw Refusal(message: PlanText.editNotFound(edit.find)) }
            guard count == 1 else { throw Refusal(message: PlanText.editAmbiguous(edit.find)) }
            body = body.replacingOccurrences(of: edit.find, with: edit.replace)
        }
        let match = quoteMatch(text(args, "quote"))
        let warnings = match == .missing ? [PlanText.quoteNotFound()] : []
        var operation = make(.editBody, issue: issue.reference, repo: issue.repo, args: args, warnings: warnings, quoteMatch: match, body: body)
        operation.edits = edits
        operations.append(operation)
        return Outcome(text: PlanText.accepted([PlanText.describe(operation)], dropped: [], warnings: warnings), isError: false)
    }

    private func retract(_ args: JSONValue) -> Outcome {
        let ids = list(args, "ids")
        let known = ids.filter { id in operations.contains { $0.id == id } }
        operations.removeAll { known.contains($0.id) }
        refs = refs.filter { !known.contains($0.value) }
        return Outcome(text: PlanText.retracted(known, unknown: ids.filter { !known.contains($0) }), isError: known.isEmpty)
    }

    private func finish(_ args: JSONValue) -> Outcome {
        var used = Set<String>()
        for operation in operations {
            for field in [operation.issue, operation.value ?? "", operation.newIssue?.parent ?? "", operation.body ?? ""] {
                used.formUnion(Self.refs(in: field))
            }
        }
        let unresolved = used.subtracting(refs.keys).sorted()
        guard unresolved.isEmpty else { return Outcome(text: PlanText.unresolvedRefs(unresolved), isError: true) }
        summary = text(args, "summary")
        skipped = (args["skipped"]?.array ?? []).map { PlanNote(what: $0["point"]?.string ?? "", why: $0["why"]?.string ?? "") }
        finished = true
        return Outcome(text: PlanText.finished(operations.count), isError: false, finished: true)
    }

    // MARK: Checks

    private func resolve(_ reference: String, mustBeKnown: Bool) async throws -> Target {
        let trimmed = reference.trimmingCharacters(in: .whitespaces)
        if let match = trimmed.wholeMatch(of: #/\{\{([A-Z]{1,3}[0-9]{0,2})\}\}/#) {
            let ref = String(match.output.1)
            if mustBeKnown, refs[ref] == nil { throw Refusal(message: PlanText.unknownRefTarget(ref)) }
            return .new(ref)
        }
        // A bare ref ("A", "#A") means the new issue too, when there is one.
        let bare = String(trimmed.drop { $0 == "#" })
        if refs[bare] != nil { return .new(bare) }
        guard let issue = await world.issue(trimmed) else { throw Refusal(message: PlanText.noSuchIssue(trimmed.isEmpty ? "\"\"" : trimmed)) }
        return .existing(issue)
    }

    private func requireRead(_ issue: PlanIssue) throws {
        guard read.contains(issue.key) else { throw Refusal(message: PlanText.notRead(issue.number)) }
    }

    private func repository(_ value: String) throws -> String {
        if value.isEmpty { return facts.defaultRepo }
        guard let repo = facts.repos.first(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) else {
            throw Refusal(message: PlanText.unknown(.repository, value, options: facts.repos))
        }
        return repo
    }

    /// The option as the board spells it, nil for an empty value.
    private func pick(_ value: String, from options: [String], what: PlanText.Thing) throws -> String? {
        guard !value.isEmpty else { return nil }
        guard let option = options.first(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) else {
            throw Refusal(message: PlanText.unknown(what, value, options: options))
        }
        return option
    }

    private func day(_ value: String, allowNone: Bool) throws -> String? {
        if value.isEmpty { return nil }
        if allowNone, value.lowercased() == "none" { return nil }
        guard value.wholeMatch(of: #/\d{4}-\d{2}-\d{2}/#) != nil, CalendarDay(value) != nil else { throw Refusal(message: PlanText.badDate(value)) }
        return value
    }

    private func labelNames(_ names: [String], repo: String) throws -> [String] {
        let known = facts.repoFacts[repo]?.labels.map(\.name) ?? []
        var result: [String] = []
        for name in names {
            guard let label = known.first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else {
                throw Refusal(message: PlanText.unknown(.label, name, options: known))
            }
            result.append(label)
        }
        return result
    }

    private func logins(_ names: [String], repo: String) throws -> [String] {
        let people = facts.repoFacts[repo]?.people.map(\.name) ?? []
        let cleaned = names.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "@ ")) }
        let unknown = cleaned.filter { login in !people.contains { $0.caseInsensitiveCompare(login) == .orderedSame } }
        guard unknown.isEmpty else { throw Refusal(message: PlanText.notAssignable(unknown, people: people)) }
        return cleaned.map { login in people.first { $0.caseInsensitiveCompare(login) == .orderedSame } ?? login }
    }

    private func textRefWarnings(_ body: String) -> [String] {
        let unknown = Self.refs(in: body).filter { refs[$0] == nil }.sorted()
        return unknown.isEmpty ? [] : [PlanText.unknownRefInText(unknown)]
    }

    /// Whether the quote is in the text: word for word, nearly (pairs of words in the same order), or not.
    func quoteMatch(_ quote: String) -> PlanOperation.QuoteMatch {
        let words = Self.plainWords(quote)
        guard words.count >= 2 else { return .missing }
        if foldedInput.contains(" " + words.joined(separator: " ") + " ") { return .exact }
        let pairs = zip(words, words.dropFirst()).map { "\($0) \($1)" }
        let found = pairs.filter { inputPairs.contains($0) }.count
        return Double(found) / Double(pairs.count) >= 0.6 ? .approximate : .missing
    }

    // MARK: Building

    private func make(
        _ kind: PlanOperation.Kind, issue: String, repo: String, args: JSONValue, warnings: [String], quoteMatch: PlanOperation.QuoteMatch,
        value: String? = nil, values: [String]? = nil, title: String? = nil, body: String? = nil, newIssue: PlanOperation.NewIssue? = nil,
        before: String? = nil, after: String? = nil
    ) -> PlanOperation {
        counter += 1
        return PlanOperation(
            id: "op\(counter)", kind: kind, issue: issue, repo: repo, value: value, values: values, title: title, body: body,
            newIssue: newIssue, edits: nil, before: before, after: after, reason: text(args, "reason"), quote: text(args, "quote"),
            quoteMatch: quoteMatch, warnings: warnings
        )
    }

    private func drop(_ what: String, _ args: JSONValue) -> Outcome {
        dropped.append(PlanNote(what: what, why: text(args, "reason")))
        return Outcome(text: PlanText.accepted([], dropped: [what], warnings: []), isError: false)
    }

    private func withFooter(_ body: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? input.footer : "\(trimmed)\n\n\(input.footer)"
    }

    private func text(_ args: JSONValue, _ key: String) -> String {
        (args[key]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func list(_ args: JSONValue, _ key: String) -> [String] {
        (args[key]?.array ?? []).compactMap(\.string).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func refs(in text: String) -> Set<String> {
        Set(text.matches(of: #/\{\{([A-Z]{1,3}[0-9]{0,2})\}\}/#).map { String($0.output.1) })
    }

    /// Words without punctuation, folded, for comparing quotes with the text.
    static func plainWords(_ text: String) -> [String] {
        PlanWorld.fold(text).components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    private static let fillers: Set<String> = [
        "und", "der", "die", "das", "den", "dem", "des", "nicht", "mit", "fur", "von", "auf", "aus", "bei", "ein", "eine",
        "einer", "eines", "statt", "nach", "zum", "zur", "the", "and", "for", "with", "from", "not", "into", "when", "of",
    ]

    static func titleWords(_ title: String) -> Set<String> {
        Set(PlanWorld.words(title).filter { !fillers.contains($0) })
    }

    /// Shared words over all words of the two titles.
    static func similarity(_ lhs: Set<String>, _ rhs: Set<String>) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        let shared = lhs.intersection(rhs).count
        guard shared >= 2 else { return 0 }
        return Double(shared) / Double(lhs.union(rhs).count)
    }
}
