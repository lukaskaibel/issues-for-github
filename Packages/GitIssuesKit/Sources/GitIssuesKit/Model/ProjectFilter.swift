import Foundation

/// A view's filter in GitHub's own words, such as `label:AP1,AP2 -status:Done iteration:@current`: read into terms
/// the app shows as chips, written back the same way, and checked against the issues on this device.
///
/// Terms are combined with AND; the values of one term with OR; a leading `-` turns a term around. Terms the app
/// doesn't understand, such as words to search for, are kept as written: for those GitHub is asked which items match.
public struct ProjectFilter: Equatable, Sendable {
    public var terms: [Term]

    public init(_ text: String) {
        terms = Self.tokens(text).map(Term.init(token:))
    }

    public init(terms: [Term]) {
        self.terms = terms
    }

    /// The filter as GitHub reads it.
    public var text: String {
        terms.map(\.raw).joined(separator: " ")
    }

    public var isEmpty: Bool { terms.isEmpty }

    /// One condition: `label:bug,ui`, `-status:Done`, `has:assignee` or a word to search for.
    public struct Term: Equatable, Sendable {
        public var negated: Bool
        /// The qualifier in lower case, such as "label" or "due-date"; nil for words to search for.
        public var key: String?
        /// Its values without quotes, such as ["AP1", "AP2"], [">=2026-10-01"] or ["@current"].
        public var values: [String]
        /// As written, which is kept as long as the term isn't changed.
        public var raw: String

        public init(negated: Bool = false, key: String?, values: [String]) {
            self.negated = negated
            self.key = key?.lowercased()
            self.values = values
            self.raw = ""
            raw = written
        }

        init(token: String) {
            var body = Substring(token)
            var negated = false
            if body.count > 1, body.hasPrefix("-") {
                negated = true
                body = body.dropFirst()
            }
            if let colon = ProjectFilter.firstUnquoted(":", in: body), colon != body.startIndex,
               !body[..<colon].contains(where: { $0 == "\"" || $0 == "'" }) {
                let key = body[..<colon].lowercased()
                let rest = body[body.index(after: colon)...]
                self.negated = negated
                self.key = key
                self.values = ProjectFilter.splitUnquoted(rest).map(ProjectFilter.unquote)
            } else {
                self.negated = negated
                self.key = nil
                self.values = [ProjectFilter.unquote(body)]
            }
            raw = token
        }

        /// The term written out, with quotes where a value needs them.
        public var written: String {
            let sign = negated ? "-" : ""
            guard let key else { return sign + ProjectFilter.quote(values.first ?? "") }
            return "\(sign)\(key):\(values.map(ProjectFilter.quote).joined(separator: ","))"
        }

        /// The term after a change, written out again.
        public func changed(_ change: (inout Term) -> Void) -> Term {
            var copy = self
            change(&copy)
            copy.raw = copy.written
            return copy
        }
    }

    // MARK: Editing

    /// Adds a value: to the term that already asks for this field, as one more it may be ("is any of"), or as a
    /// new term.
    public func adding(key: String, value: String) -> ProjectFilter {
        var copy = self
        let key = key.lowercased()
        if Self.takesSeveral(key), let index = terms.firstIndex(where: { $0.key == key && !$0.negated }) {
            guard !terms[index].values.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) else { return self }
            copy.terms[index] = terms[index].changed { $0.values.append(value) }
        } else {
            copy.terms.append(Term(key: key, values: [value]))
        }
        return copy
    }

    /// Whether a qualifier can list several values as alternatives. Presence and state can't.
    static func takesSeveral(_ key: String) -> Bool {
        !["is", "has", "no", "reason"].contains(key)
    }

    public func replacing(_ index: Int, with term: Term) -> ProjectFilter {
        guard terms.indices.contains(index) else { return self }
        var copy = self
        copy.terms[index] = term
        return copy
    }

    public func removing(_ index: Int) -> ProjectFilter {
        guard terms.indices.contains(index) else { return self }
        var copy = self
        copy.terms.remove(at: index)
        return copy
    }

    // MARK: Reading the text

    /// Splits at spaces outside quotes.
    static func tokens(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        for character in text {
            if let open = quote {
                current.append(character)
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
                current.append(character)
            } else if character.isWhitespace {
                if !current.isEmpty { tokens.append(current) }
                current = ""
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    static func firstUnquoted(_ target: Character, in text: Substring) -> Substring.Index? {
        var quote: Character?
        for index in text.indices {
            let character = text[index]
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == target {
                return index
            }
        }
        return nil
    }

    /// Splits a term's values at commas outside quotes.
    static func splitUnquoted(_ text: Substring) -> [Substring] {
        var parts: [Substring] = []
        var start = text.startIndex
        var quote: Character?
        for index in text.indices {
            let character = text[index]
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "," {
                parts.append(text[start..<index])
                start = text.index(after: index)
            }
        }
        parts.append(text[start...])
        return parts.filter { !$0.isEmpty }
    }

    /// Takes the quotes off a value, also those around part of it (`>="Iteration 2"`).
    static func unquote(_ text: Substring) -> String {
        String(text.filter { $0 != "\"" && $0 != "'" })
    }

    static func quote(_ value: String) -> String {
        let needs = value.isEmpty || value.contains { $0.isWhitespace || $0 == "," || $0 == ":" || $0 == "\"" || $0 == "'" }
        guard needs else { return value }
        // A comparison keeps its sign outside the quotes, as GitHub writes it.
        var sign = ""
        var rest = Substring(value)
        for prefix in [">=", "<=", ">", "<"] where rest.hasPrefix(prefix) {
            sign = prefix
            rest = rest.dropFirst(prefix.count)
            break
        }
        let mark = rest.contains("\"") ? "'" : "\""
        return "\(sign)\(mark)\(rest)\(mark)"
    }
}

// MARK: - Checking issues

/// What a filter needs to know besides the issue itself.
public struct FilterContext {
    public var viewerLogin: String?
    public var today: CalendarDay
    /// The project's fields, by the name a filter uses for them ("status", "due-date", "workstream").
    public var fieldsByKey: [String: ProjectField]
    public var statusFieldId: String?
    public var priorityFieldId: String?
    public var dueFieldId: String?
    /// The name of an option of a single-select field.
    public var optionName: (_ fieldId: String, _ optionId: String) -> String?
    /// The parent as GitHub writes it in a filter: "owner/repo#12".
    public var parentReference: (Item) -> String?

    public init(
        viewerLogin: String?, today: CalendarDay, fields: [ProjectField], statusFieldId: String?, priorityFieldId: String?,
        dueFieldId: String?, optionName: @escaping (String, String) -> String?, parentReference: @escaping (Item) -> String?
    ) {
        self.viewerLogin = viewerLogin
        self.today = today
        var byKey: [String: ProjectField] = [:]
        for field in fields where byKey[field.filterKey] == nil { byKey[field.filterKey] = field }
        fieldsByKey = byKey
        self.statusFieldId = statusFieldId
        self.priorityFieldId = priorityFieldId
        self.dueFieldId = dueFieldId
        self.optionName = optionName
        self.parentReference = parentReference
    }

    /// What an item has in a project field, wherever the app keeps it.
    public func value(of field: ProjectField, in item: Item) -> FieldValue? {
        if field.id == statusFieldId { return item.statusId.map { FieldValue(optionId: $0) } }
        if field.id == priorityFieldId { return item.priorityId.map { FieldValue(optionId: $0) } }
        if field.id == dueFieldId { return item.dueDate.map { FieldValue(date: $0) } }
        return item.fieldValues[field.id]
    }
}

extension ProjectFilter {
    /// Whether some terms can only be answered by GitHub.
    public func needsServer(_ context: FilterContext) -> Bool {
        terms.contains { !$0.isUnderstood(context) }
    }

    /// Whether an item passes every term the app understands. Terms it doesn't understand pass; GitHub's answer
    /// covers them (see `needsServer`).
    public func matches(_ item: Item, _ context: FilterContext) -> Bool {
        terms.allSatisfy { term in
            guard let result = term.evaluate(item, context) else { return true }
            return result != term.negated
        }
    }
}

extension ProjectFilter.Term {
    func isUnderstood(_ context: FilterContext) -> Bool {
        guard let key else { return false }
        switch key {
        case "is":
            return values.allSatisfy { ["open", "closed", "issue", "pr", "draft", "merged"].contains($0.lowercased()) }
        case "assignee", "assignees", "label", "labels", "milestone", "repo", "repository", "type", "parent-issue", "title":
            return true
        case "reason":
            return values.allSatisfy { ["completed", "not planned", "reopened"].contains($0.lowercased()) }
        case "has", "no":
            return values.allSatisfy { Self.presenceKnown($0.lowercased(), context) }
        case "updated", "created", "closed":
            return values.allSatisfy { DateBound.parse($0, today: context.today) != nil }
        default:
            guard let field = context.fieldsByKey[key] else { return false }
            switch field.kind {
            case .singleSelect, .text: return true
            case .iteration: return values.allSatisfy { IterationBound.isValid($0) }
            case .date: return values.allSatisfy { DateBound.parse($0, today: context.today) != nil }
            case .number: return values.allSatisfy { NumberBound.parse($0) != nil }
            default: return false
            }
        }
    }

    static func presenceKnown(_ key: String, _ context: FilterContext) -> Bool {
        switch key {
        case "assignee", "assignees", "label", "labels", "milestone", "parent-issue", "type", "issue-type": return true
        default:
            guard let field = context.fieldsByKey[key] else { return false }
            switch field.kind {
            case .singleSelect, .iteration, .date, .text, .number, .assignees, .labels, .milestone, .parentIssue, .issueType: return true
            default: return false
            }
        }
    }

    /// Whether the item matches the term before its `-` is applied; nil when the app can't tell.
    func evaluate(_ item: Item, _ context: FilterContext) -> Bool? {
        guard isUnderstood(context), let key else { return nil }
        let wanted = values
        switch key {
        case "is":
            return wanted.allSatisfy { value in
                switch value.lowercased() {
                case "open": !item.isClosed
                case "closed": item.isClosed
                case "issue": item.kind == .issue
                case "pr": item.kind == .pullRequest
                case "draft": item.kind == .draft
                case "merged": item.kind == .pullRequest && item.state == "MERGED"
                default: false
                }
            }
        case "assignee", "assignees":
            let logins = item.assignees.map(\.login)
            return wanted.contains { value in
                let login = value == "@me" ? (context.viewerLogin ?? value) : value
                return logins.contains { Glob.matches(login, $0) }
            }
        case "label", "labels":
            return wanted.contains { value in item.labels.contains { Glob.matches(value, $0.name) } }
        case "milestone":
            guard let title = item.milestoneTitle else { return false }
            return wanted.contains { Glob.matches($0, title) }
        case "repo", "repository":
            guard let repo = item.repo else { return false }
            return wanted.contains { $0.caseInsensitiveCompare(repo) == .orderedSame }
        case "type":
            guard let type = item.issueType else { return false }
            return wanted.contains { Glob.matches($0, type) }
        case "parent-issue":
            guard let reference = context.parentReference(item) else { return false }
            return wanted.contains { $0.caseInsensitiveCompare(reference) == .orderedSame }
        case "title":
            return wanted.contains { Glob.matches($0, item.title) }
        case "reason":
            let reason = item.stateReason ?? ""
            return wanted.contains { value in
                switch value.lowercased() {
                case "completed": item.isClosed && reason == "COMPLETED"
                case "not planned": item.isClosed && reason == "NOT_PLANNED"
                case "reopened": reason == "REOPENED"
                default: false
                }
            }
        case "has", "no":
            let has = wanted.allSatisfy { Self.has($0.lowercased(), item, context) }
            return key == "has" ? has : wanted.allSatisfy { !Self.has($0.lowercased(), item, context) }
        case "updated", "created", "closed":
            let date: Date? = switch key {
            // GitHub counts a change to the card, such as its status, as much as one to the issue.
            case "updated": [item.updatedAt, item.remoteUpdatedAt.flatMap(Self.date)].compactMap { $0 }.max()
            case "created": item.createdAt
            default: item.closedAt
            }
            guard let date else { return false }
            let day = CalendarDay(date)
            return wanted.contains { DateBound.parse($0, today: context.today)?.contains(day) ?? false }
        default:
            guard let field = context.fieldsByKey[key] else { return nil }
            let value = context.value(of: field, in: item)
            switch field.kind {
            case .singleSelect:
                guard let optionId = value?.optionId, let name = context.optionName(field.id, optionId) else { return false }
                return wanted.contains { Glob.matches($0, name) }
            case .text:
                guard let text = value?.text else { return false }
                return wanted.contains { Glob.matches($0, text) }
            case .iteration:
                guard let id = value?.iterationId else { return false }
                return wanted.contains { IterationBound.matches($0, iterationId: id, field: field, today: context.today) }
            case .date:
                guard let day = value?.date.flatMap(CalendarDay.init) else { return false }
                return wanted.contains { DateBound.parse($0, today: context.today)?.contains(day) ?? false }
            case .number:
                guard let number = value?.number else { return false }
                return wanted.contains { NumberBound.parse($0)?.contains(number) ?? false }
            default:
                return nil
            }
        }
    }

    /// A moment as GitHub writes it, "2026-10-14T09:12:00Z", perhaps with fractions of a second. Read by hand: it
    /// runs for every card when a view is ordered or filtered by Updated, where a date formatter took most of a
    /// second for a board of 400.
    static func date(_ text: String) -> Date? {
        let b = Array(text.utf8)
        guard b.count >= 20, b[4] == 0x2D, b[7] == 0x2D, b[10] == 0x54, b[13] == 0x3A, b[16] == 0x3A, b.last == 0x5A else {
            return try? Date(text, strategy: .iso8601)
        }
        func number(_ range: Range<Int>) -> Int? {
            var value = 0
            for index in range {
                let digit = Int(b[index]) - 0x30
                guard (0...9).contains(digit) else { return nil }
                value = value * 10 + digit
            }
            return value
        }
        guard let year = number(0..<4), let month = number(5..<7), let day = number(8..<10),
              let hour = number(11..<13), let minute = number(14..<16), let second = number(17..<19),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        var fraction = 0.0
        if b.count > 20 {
            guard b[19] == 0x2E, let digits = number(20..<(b.count - 1)) else { return nil }
            fraction = Double(digits) / pow(10, Double(b.count - 21))
        }
        // Days since 1970 from the civil date (Howard Hinnant's algorithm).
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        let days = era * 146_097 + dayOfEra - 719_468
        return Date(timeIntervalSince1970: Double(days * 86_400 + hour * 3_600 + minute * 60 + second) + fraction)
    }

    static func has(_ key: String, _ item: Item, _ context: FilterContext) -> Bool {
        switch key {
        case "assignee", "assignees": return !item.assignees.isEmpty
        case "label", "labels": return !item.labels.isEmpty
        case "milestone": return item.milestoneId != nil || item.milestoneTitle != nil
        case "parent-issue": return item.parentId != nil
        case "type", "issue-type": return item.issueType != nil
        default:
            guard let field = context.fieldsByKey[key] else { return false }
            switch field.kind {
            case .assignees: return !item.assignees.isEmpty
            case .labels: return !item.labels.isEmpty
            case .milestone: return item.milestoneId != nil
            case .parentIssue: return item.parentId != nil
            case .issueType: return item.issueType != nil
            default: return !(context.value(of: field, in: item)?.isEmpty ?? true)
            }
        }
    }
}

// MARK: - Values

/// `*` stands for anything, as in GitHub's `label:*bug*`; otherwise a value matches when it is the same, without
/// regard to case.
enum Glob {
    static func matches(_ pattern: String, _ text: String) -> Bool {
        guard pattern.contains("*") else { return pattern.caseInsensitiveCompare(text) == .orderedSame }
        let parts = pattern.lowercased().split(separator: "*", omittingEmptySubsequences: false).map(String.init)
        var rest = Substring(text.lowercased())
        for (index, part) in parts.enumerated() where !part.isEmpty {
            if index == 0 {
                guard rest.hasPrefix(part) else { return false }
                rest = rest.dropFirst(part.count)
            } else if index == parts.count - 1 {
                return rest.hasSuffix(part)
            } else {
                guard let range = rest.range(of: part) else { return false }
                rest = rest[range.upperBound...]
            }
        }
        return true
    }
}

/// Splits a value into a comparison and what it compares with: `>=2026-10-01` gives (">=", "2026-10-01").
private func comparison(_ value: String) -> (op: String, rest: String) {
    for op in [">=", "<=", ">", "<"] where value.hasPrefix(op) {
        return (op, String(value.dropFirst(op.count)))
    }
    return ("", value)
}

/// A day or a stretch of days a date filter asks for: `2026-10-01`, `@today-7d`, `>@today-1w`, `a..b`.
struct DateBound {
    var lower: CalendarDay?
    var upper: CalendarDay?

    func contains(_ day: CalendarDay) -> Bool {
        if let lower, day < lower { return false }
        if let upper, upper < day { return false }
        return true
    }

    static func parse(_ value: String, today: CalendarDay) -> DateBound? {
        let (op, rest) = comparison(value)
        if op.isEmpty, let range = rest.range(of: "..") {
            let from = String(rest[..<range.lowerBound])
            let to = String(rest[range.upperBound...])
            let lower = from == "*" ? nil : day(from, today: today)
            let upper = to == "*" ? nil : day(to, today: today)
            if (from != "*" && lower == nil) || (to != "*" && upper == nil) { return nil }
            return DateBound(lower: lower, upper: upper)
        }
        guard let day = day(rest, today: today) else { return nil }
        switch op {
        case ">": return DateBound(lower: day.adding(days: 1), upper: nil)
        case ">=": return DateBound(lower: day, upper: nil)
        case "<": return DateBound(lower: nil, upper: day.adding(days: -1))
        case "<=": return DateBound(lower: nil, upper: day)
        default: return DateBound(lower: day, upper: day)
        }
    }

    /// "2026-10-01", "@today", "@today-7d", "@today+1w", "@today-1m", "@today+2y" (days when no unit is given).
    static func day(_ text: String, today: CalendarDay) -> CalendarDay? {
        if let day = CalendarDay(text) { return day }
        let lower = text.lowercased()
        guard lower.hasPrefix("@today") else { return nil }
        let rest = lower.dropFirst("@today".count)
        if rest.isEmpty { return today }
        guard let sign = rest.first, sign == "+" || sign == "-" else { return nil }
        var digits = rest.dropFirst()
        var unit: Character = "d"
        if let last = digits.last, last.isLetter {
            unit = last
            digits = digits.dropLast()
        }
        guard let amount = Int(digits) else { return nil }
        let signed = sign == "-" ? -amount : amount
        switch unit {
        case "d": return today.adding(days: signed)
        case "w": return today.adding(days: signed * 7)
        case "m": return today.adding(months: signed)
        case "y": return today.adding(months: signed * 12)
        default: return nil
        }
    }
}

/// A number or a range of numbers: `5`, `>=3`, `1..3`, `*..10`.
struct NumberBound {
    var lower: Double?
    var upper: Double?
    var lowerOpen = false
    var upperOpen = false

    func contains(_ number: Double) -> Bool {
        if let lower, lowerOpen ? number <= lower : number < lower { return false }
        if let upper, upperOpen ? number >= upper : number > upper { return false }
        return true
    }

    static func parse(_ value: String) -> NumberBound? {
        let (op, rest) = comparison(value)
        if op.isEmpty, let range = rest.range(of: "..") {
            let from = String(rest[..<range.lowerBound])
            let to = String(rest[range.upperBound...])
            let lower = from == "*" ? nil : Double(from)
            let upper = to == "*" ? nil : Double(to)
            if (from != "*" && lower == nil) || (to != "*" && upper == nil) { return nil }
            return NumberBound(lower: lower, upper: upper)
        }
        guard let number = Double(rest) else { return nil }
        switch op {
        case ">": return NumberBound(lower: number, upper: nil, lowerOpen: true)
        case ">=": return NumberBound(lower: number, upper: nil)
        case "<": return NumberBound(lower: nil, upper: number, upperOpen: true)
        case "<=": return NumberBound(lower: nil, upper: number)
        default: return NumberBound(lower: number, upper: number)
        }
    }
}

/// Iterations a filter asks for: `@current`, `@next`, `@previous`, `@current+2`, an iteration's title, a comparison
/// (`<@current`) or a range (`@current..@current+3`).
enum IterationBound {
    static func isValid(_ value: String) -> Bool {
        let (_, rest) = comparison(value)
        if let range = rest.range(of: "..") {
            return [String(rest[..<range.lowerBound]), String(rest[range.upperBound...])].allSatisfy { $0 == "*" || !$0.isEmpty }
        }
        return !rest.isEmpty
    }

    /// The iteration a part of a value names: its index among the field's iterations by start.
    static func index(_ text: String, field: ProjectField, today: CalendarDay) -> Int? {
        let ordered = field.orderedIterations
        let lower = text.lowercased()
        if lower.hasPrefix("@") {
            var offset = 0
            var base = Substring(lower)
            if let sign = base.firstIndex(where: { $0 == "+" || $0 == "-" }) {
                guard let amount = Int(base[base.index(after: sign)...]) else { return nil }
                offset = base[sign] == "-" ? -amount : amount
                base = base[..<sign]
            }
            switch base {
            case "@current": break
            case "@next": offset += 1
            case "@previous": offset -= 1
            default: return nil
            }
            guard let iteration = field.iteration(offset: offset, from: today) else {
                // Further out than the iterations GitHub has: before the first or after the last.
                let current = ordered.firstIndex { $0.contains(today) } ?? ordered.firstIndex { ($0.start ?? today) > today } ?? ordered.count
                return current + offset
            }
            return ordered.firstIndex(of: iteration)
        }
        return ordered.firstIndex { $0.title.caseInsensitiveCompare(text) == .orderedSame }
    }

    static func matches(_ value: String, iterationId: String, field: ProjectField, today: CalendarDay) -> Bool {
        let ordered = field.orderedIterations
        guard let own = ordered.firstIndex(where: { $0.id == iterationId }) else { return false }
        let (op, rest) = comparison(value)
        if op.isEmpty, let range = rest.range(of: "..") {
            let from = String(rest[..<range.lowerBound])
            let to = String(rest[range.upperBound...])
            let lower = from == "*" ? Int.min : index(from, field: field, today: today)
            let upper = to == "*" ? Int.max : index(to, field: field, today: today)
            guard let lower, let upper else { return false }
            return lower <= own && own <= upper
        }
        guard let target = index(rest, field: field, today: today) else { return false }
        switch op {
        case ">": return own > target
        case ">=": return own >= target
        case "<": return own < target
        case "<=": return own <= target
        default: return own == target
        }
    }
}
