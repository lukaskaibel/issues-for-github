import Foundation
import GRDB

/// An issue as the assistant sees it: the card's fields by name rather than by id.
public struct PlanIssue: Sendable {
    public var contentId: String
    public var number: Int
    public var repo: String
    public var title: String
    public var body: String
    public var isOpen: Bool
    public var stateReason: String?
    public var status: String?
    public var priority: String?
    public var due: String?
    public var type: String?
    public var milestone: String?
    public var labels: [String]
    public var assignees: [String]
    public var parent: Int?
    public var parentTitle: String?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var closedAt: Date?
    public var commentCount: Int
    public var onBoard: Bool
    /// Issues of the board's main repository are "#12"; others carry their repository.
    public var isInDefaultRepo = true

    public var key: String { "\(repo)#\(number)" }
    public var reference: String { isInDefaultRepo ? "#\(number)" : "\(repo)#\(number)" }
}

/// What only a full read of an issue says: its comments, sub-issues and blockers.
public struct PlanDetail: Sendable {
    public struct Link: Sendable {
        public var number: Int
        public var title: String
        public var isOpen: Bool
    }

    public var comments: [Comment]
    public var subIssues: [Link]
    public var blockedBy: [Link]
    public var blocking: [Link]
}

/// The board's vocabulary: which statuses, priorities, types, labels and people exist.
public struct BoardFacts: Sendable {
    public var projectTitle: String
    public var projectOwner: String
    public var projectNumber: Int
    /// Repositories of the board, the one with the most issues first.
    public var repos: [String]
    public var statuses: [String]
    public var priorities: [String]
    public var hasDueField: Bool
    public var repoFacts: [String: RepoFacts]
    /// Open milestone titles per repository.
    public var milestones: [String: [String]]
    public var viewer: String
    public var viewerName: String?

    public var defaultRepo: String { repos.first ?? "" }
}

/// How the board looked at an earlier moment, to replay a text against the state it was written in: issues created
/// later and comments written later are hidden, and listed fields are set back.
public struct PlanSnapshot: Sendable, Decodable {
    public var asOf: Date?
    /// Per issue number, fields as they were: "status", "priority", "due", "type", "milestone" (string or null),
    /// "assignees", "labels" (arrays), "parent" (number or null), "open" (bool).
    public var issues: [String: [String: JSONValue]]

    public init(asOf: Date? = nil, issues: [String: [String: JSONValue]] = [:]) {
        self.asOf = asOf
        self.issues = issues
    }

    public static let now = PlanSnapshot()
}

/// Everything the assistant reads about a board, from the local database and, for comments and relations, GitHub.
/// The local data is read once when a run starts, so the run sees one consistent board.
public actor PlanWorld {
    public nonisolated let facts: BoardFacts
    private var issues: [String: PlanIssue]
    private let api: GitHubAPI?
    private let snapshot: PlanSnapshot
    private var details: [String: PlanDetail] = [:]

    init(facts: BoardFacts, issues: [PlanIssue], api: GitHubAPI?, snapshot: PlanSnapshot) {
        self.facts = facts
        self.api = api
        self.snapshot = snapshot
        var visible: [String: PlanIssue] = [:]
        for var issue in issues {
            if let asOf = snapshot.asOf, let created = issue.createdAt, created > asOf { continue }
            issue.isInDefaultRepo = issue.repo == facts.defaultRepo
            Self.applyOverrides(issue.isInDefaultRepo ? snapshot.issues[String(issue.number)] : snapshot.issues[issue.key], to: &issue, asOf: snapshot.asOf)
            visible[issue.key] = issue
        }
        self.issues = visible
    }

    /// Reads the board from the local database, and what the database doesn't keep (labels with descriptions, issue
    /// types, assignable people) from GitHub.
    public static func load(db: AppDatabase, api: GitHubAPI, projectId: String, snapshot: PlanSnapshot = .now) async throws -> PlanWorld {
        let (project, options, items, repoRows) = try await db.reader.read { db in
            (
                try Project.fetchOne(db, key: projectId),
                try FieldOption.filter(Column("projectId") == projectId).order(Column("position")).fetchAll(db),
                try Item.fetchAll(db),
                try RepoRef.filter(Column("projectId") == projectId).fetchAll(db)
            )
        }
        guard let project else { throw LLMError.badResponse("project \(projectId) isn't in the database") }
        let names = Dictionary(options.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let boardRepos = Set(repoRows.map(\.nameWithOwner))
        let milestones = try await db.reader.read { db in try Milestone.fetchAll(db) }
        let milestoneTitles = Dictionary(milestones.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })

        var byKey: [String: PlanIssue] = [:]
        for item in items where item.kind == .issue {
            guard let number = item.number, let repo = item.repo, let contentId = item.contentId else { continue }
            let onBoard = item.projectId == projectId
            guard onBoard || (item.projectId == nil && boardRepos.contains(repo)) else { continue }
            let issue = PlanIssue(
                contentId: contentId, number: number, repo: repo, title: item.title, body: item.body,
                isOpen: !item.isClosed, stateReason: item.stateReason,
                status: onBoard ? item.statusId.flatMap { names[$0] } : nil,
                priority: onBoard ? item.priorityId.flatMap { names[$0] } : nil,
                due: onBoard ? item.dueDate : nil, type: item.issueType,
                milestone: item.milestoneTitle ?? item.milestoneId.flatMap { milestoneTitles[$0] },
                labels: item.labels.map(\.name), assignees: item.assignees.map(\.login),
                parent: item.parentNumber, parentTitle: item.parentTitle,
                createdAt: item.createdAt, updatedAt: item.updatedAt, closedAt: item.closedAt,
                commentCount: item.commentCount, onBoard: onBoard
            )
            // A board card wins over the same issue read from its repository.
            if byKey[issue.key]?.onBoard != true { byKey[issue.key] = issue }
        }

        var facts: [String: RepoFacts] = [:]
        var openMilestones: [String: [String]] = [:]
        for row in repoRows {
            facts[row.nameWithOwner] = try await api.repoFacts(repoId: row.id)
            openMilestones[row.nameWithOwner] = try await api.milestones(repoId: row.id).filter(\.isOpen).map(\.title)
        }
        let counts = Dictionary(grouping: byKey.values, by: \.repo).mapValues(\.count)
        let viewer = db.viewer()
        let board = BoardFacts(
            projectTitle: project.title, projectOwner: project.ownerLogin, projectNumber: project.number,
            repos: boardRepos.sorted { (counts[$0] ?? 0, $1) > (counts[$1] ?? 0, $0) },
            statuses: options.filter { $0.kind == .status }.map(\.name),
            priorities: options.filter { $0.kind == .priority }.map(\.name),
            hasDueField: project.dueFieldId != nil,
            repoFacts: facts, milestones: openMilestones,
            viewer: viewer?.login ?? "", viewerName: viewer?.name
        )
        return PlanWorld(facts: board, issues: Array(byKey.values), api: api, snapshot: snapshot)
    }

    // MARK: Reading

    /// "#12", "12" or "owner/name#12"; a number alone means the board's main repository, then any other.
    public func issue(_ reference: String) -> PlanIssue? {
        let trimmed = reference.trimmingCharacters(in: .whitespaces)
        if let hash = trimmed.firstIndex(of: "#"), hash != trimmed.startIndex {
            return issues[trimmed]
        }
        guard let number = Int(trimmed.drop { $0 == "#" }) else { return nil }
        for repo in facts.repos {
            if let issue = issues["\(repo)#\(number)"] { return issue }
        }
        return issues.values.first { $0.number == number }
    }

    public func allIssues() -> [PlanIssue] {
        issues.values.sorted { $0.number < $1.number }
    }

    /// Issues whose title, text or (already read) comments contain the words, best matches first.
    public func search(_ query: String, open: Bool?, limit: Int) -> [(issue: PlanIssue, snippet: String?)] {
        let terms = Self.words(query)
        if let number = Int(query.trimmingCharacters(in: .whitespaces).drop { $0 == "#" }), let hit = issue(String(number)) {
            return [(hit, nil)]
        }
        guard !terms.isEmpty else { return [] }
        var scored: [(issue: PlanIssue, score: Int, snippet: String?)] = []
        for issue in issues.values {
            if let open, issue.isOpen != open { continue }
            let title = Self.fold(issue.title)
            let body = Self.fold(issue.body)
            let comments = details[issue.key].map { Self.fold($0.comments.map(\.body).joined(separator: "\n")) } ?? ""
            var score = 0
            var snippet: String?
            for term in terms {
                if title.contains(term) { score += 3 }
                if let range = body.range(of: term) {
                    score += 1
                    if snippet == nil { snippet = Self.excerpt(issue.body, around: range, in: body) }
                } else if comments.contains(term) {
                    score += 1
                }
            }
            if score > 0 { scored.append((issue, score, snippet)) }
        }
        return scored
            .sorted { ($0.score, $0.issue.isOpen ? 1 : 0, $0.issue.number) > ($1.score, $1.issue.isOpen ? 1 : 0, $1.issue.number) }
            .prefix(max(1, min(limit, 30)))
            .map { ($0.issue, $0.snippet) }
    }

    /// Comments, sub-issues and blockers, read from GitHub once per run.
    public func detail(of issue: PlanIssue) async throws -> PlanDetail {
        if let known = details[issue.key] { return known }
        guard let api else { return PlanDetail(comments: [], subIssues: [], blockedBy: [], blocking: []) }
        let remote = try await api.issueDetail(contentId: issue.contentId)
        let asOf = snapshot.asOf
        func visible(_ number: Int, repo: String?) -> Bool {
            guard asOf != nil else { return true }
            return self.issue("\(repo ?? facts.defaultRepo)#\(number)") != nil
        }
        let detail = PlanDetail(
            comments: remote.comments.filter { comment in asOf.map { comment.createdAt <= $0 } ?? true },
            subIssues: remote.subIssues.filter { visible($0.number, repo: $0.repo) }
                .map { .init(number: $0.number, title: $0.title, isOpen: !$0.isClosed) },
            blockedBy: remote.links.filter { $0.relation == .blockedBy && visible($0.number, repo: $0.repo) }
                .map { .init(number: $0.number, title: $0.title, isOpen: !$0.isClosed) },
            blocking: remote.links.filter { $0.relation == .blocking && visible($0.number, repo: $0.repo) }
                .map { .init(number: $0.number, title: $0.title, isOpen: !$0.isClosed) }
        )
        details[issue.key] = detail
        return detail
    }

    /// The detail read before, if any.
    public func knownDetail(of issue: PlanIssue) -> PlanDetail? {
        details[issue.key]
    }

    /// Sets what a full read would return, for tests that run without GitHub.
    func seed(_ detail: PlanDetail, for issue: PlanIssue) {
        details[issue.key] = detail
    }

    // MARK: Text matching

    /// Lower case, without accents, so "Löschkonzept" matches "loschkonzept".
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Words worth searching for: three letters or more, or a number.
    static func words(_ text: String) -> [String] {
        fold(text)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 || Int($0) != nil }
    }

    private static func excerpt(_ original: String, around range: Range<String.Index>, in folded: String) -> String {
        // Folding keeps the length for the languages the boards are written in; fall back to the start otherwise.
        guard original.count == folded.count else { return String(original.prefix(160)) }
        let offset = folded.distance(from: folded.startIndex, to: range.lowerBound)
        let start = original.index(original.startIndex, offsetBy: max(0, offset - 70))
        let end = original.index(start, offsetBy: min(180, original.distance(from: start, to: original.endIndex)))
        return String(original[start..<end]).replacingOccurrences(of: "\n", with: " ")
    }

    private static func applyOverrides(_ fields: [String: JSONValue]?, to issue: inout PlanIssue, asOf: Date?) {
        if let asOf, let closed = issue.closedAt, closed > asOf {
            issue.isOpen = true
            issue.stateReason = nil
        }
        guard let fields else { return }
        for (field, value) in fields {
            switch field {
            case "status": issue.status = value.string
            case "priority": issue.priority = value.string
            case "due": issue.due = value.string
            case "type": issue.type = value.string
            case "milestone": issue.milestone = value.string
            case "assignees": issue.assignees = (value.array ?? []).compactMap(\.string)
            case "labels": issue.labels = (value.array ?? []).compactMap(\.string)
            case "parent": issue.parent = value.int
            case "open": issue.isOpen = value.bool ?? issue.isOpen
            default: break
            }
        }
    }
}
