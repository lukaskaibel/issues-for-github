import Foundation
import GRDB

/// Which half of the Inbox an entry is in. For you: things that involve you (you were assigned, mentioned, asked
/// for a review, opened or commented on the issue, or subscribed to it yourself). Watching: activity in
/// repositories you watch, which can be a lot and shouldn't bury the rest.
public enum InboxBucket: String, Codable, Sendable, CaseIterable {
    case forYou
    case watching

    /// GitHub's reason for a notification decides the bucket. Only watching a repository puts it in Watching.
    public init(reason: String) {
        self = reason == "subscribed" ? .watching : .forYou
    }

    public var title: String {
        switch self {
        case .forYou: "For you"
        case .watching: "Watching"
        }
    }
}

/// Something that happened on an issue or pull request, as read from its timeline on GitHub.
public struct InboxActivity: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case commented
        case assigned
        case unassigned
        case mentioned
        case opened
        case closed
        case reopened
        case merged
        case reviewRequested
        case reviewed
        case statusChanged
    }

    public var kind: Kind
    public var actor: Person?
    public var at: Date
    /// The comment or review as plain text, without Markdown, for a comment, a mention or a review.
    public var text: String?
    /// The person the event was about (assigned, review requested), the close reason (COMPLETED, NOT_PLANNED,
    /// DUPLICATE), the review's state (APPROVED, CHANGES_REQUESTED, COMMENTED) or the new status.
    public var detail: String?
    /// The project a status change happened in.
    public var project: String?
    /// The comment's node id, so the issue view can point at it.
    public var commentId: String?

    public init(kind: Kind, actor: Person?, at: Date, text: String? = nil, detail: String? = nil, project: String? = nil, commentId: String? = nil) {
        self.kind = kind
        self.actor = actor
        self.at = at
        self.text = text
        self.detail = detail
        self.project = project
        self.commentId = commentId
    }
}

/// One entry of the Inbox: a GitHub notification thread about an issue or pull request, with what was read from
/// the issue itself (who did what since you last read it). Read and archived are GitHub's, so they are the same on
/// github.com, in GitHub Mobile and on the user's other devices.
public struct InboxEntry: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    public static let databaseTableName = "inboxEntry"

    /// GitHub's notification thread id.
    public var id: String
    /// Why GitHub notified: assign, mention, team_mention, review_requested, author, comment, manual, subscribed,
    /// state_change, …
    public var reason: String
    public var unread: Bool
    /// The thread's last activity, as GitHub reports it.
    public var updatedAt: Date
    public var lastReadAt: Date?
    /// "Issue" or "PullRequest".
    public var subjectType: String
    public var title: String
    /// owner/name
    public var repo: String
    public var number: Int?
    /// Set when the entry was archived here: the thread's `updatedAt` at that moment. It stays hidden until GitHub
    /// reports newer activity.
    public var archivedFor: Date?

    // Read from the issue or pull request itself.
    /// The `updatedAt` the fields below were read for; when the thread moves on, they are read again.
    public var enrichedFor: Date?
    /// GitHub couldn't find the issue: it was deleted or transferred, or access to it is gone.
    public var missing: Bool = false
    public var contentId: String?
    public var url: String?
    /// OPEN, CLOSED or MERGED.
    public var state: String?
    public var stateReason: String?
    public var body: String = ""
    public var repoId: String?
    public var authorLogin: String?
    public var createdAt: Date?
    public var assignees: [Person] = []
    public var labels: [LabelRef] = []
    /// What happened on it, newest first, without your own actions: since you last read it while the entry is
    /// unread, or else the latest.
    public var activity: [InboxActivity] = []
    /// Whether `activity` is news: it was read while the entry was unread.
    public var activityIsNew: Bool = false
    /// When you last read it before that activity; nil when you never had.
    public var activitySince: Date?

    public init(
        id: String, reason: String, unread: Bool, updatedAt: Date, lastReadAt: Date? = nil,
        subjectType: String, title: String, repo: String, number: Int?
    ) {
        self.id = id
        self.reason = reason
        self.unread = unread
        self.updatedAt = updatedAt
        self.lastReadAt = lastReadAt
        self.subjectType = subjectType
        self.title = title
        self.repo = repo
        self.number = number
    }

    public var bucket: InboxBucket { InboxBucket(reason: reason) }
    public var isPullRequest: Bool { subjectType == "PullRequest" }
    public var isArchived: Bool { archivedFor.map { updatedAt <= $0 } ?? false }
    public var repoShortName: String { repo.split(separator: "/").last.map(String.init) ?? repo }

    /// The issue's page on github.com. Known before the issue itself has been read.
    public var webURL: URL? {
        if let url, let parsed = URL(string: url) { return parsed }
        guard let number else { return URL(string: "https://github.com/\(repo)") }
        return URL(string: "https://github.com/\(repo)/\(isPullRequest ? "pull" : "issues")/\(number)")
    }

    /// "#12", or "website#12" when the issue isn't on any of your boards and its repository says where it lives.
    public func displayNumber(withRepo: Bool) -> String {
        guard let number else { return isPullRequest ? "PR" : "Issue" }
        return withRepo ? "\(repoShortName)#\(number)" : "#\(number)"
    }

    /// "#12 Title", for messages and the queue of changes.
    public var label: String {
        number.map { "#\($0) \(title)" } ?? title
    }

    /// Comments that are new since you last read the issue.
    public var newCommentIds: Set<String> {
        activityIsNew ? Set(activity.compactMap(\.commentId)) : []
    }
}

// MARK: - What a row says

/// The one line an Inbox row shows under the title, and the small sign on the avatar.
public struct InboxSummary: Equatable, Sendable {
    public enum Sign: String, Sendable {
        case assigned, mentioned, commented, comments, reviewRequested, approved, changesRequested
        case completed, notPlanned, reopened, merged, opened, statusChanged, activity
        /// An issue of yours that is due today, or was due and is still open.
        case due, overdue
    }

    public var actor: Person?
    /// "Kai Andersen assigned you", "Mira Patel:" …
    public var lead: String
    /// The comment or mention itself, after the lead.
    public var excerpt: String?
    public var sign: Sign
}

extension InboxEntry {
    /// The event a row leads with: the one GitHub notified about if it is among the new ones (you were assigned,
    /// mentioned, asked for a review), else the newest.
    func headline(viewer: String?) -> InboxActivity? {
        let me = viewer?.lowercased()
        func isMe(_ login: String?) -> Bool { me != nil && login?.lowercased() == me }
        let reasonEvent: InboxActivity? = switch reason {
        case "assign":
            activity.first { $0.kind == .assigned && isMe($0.detail) }
        case "mention":
            activity.first { $0.kind == .mentioned || ($0.kind == .commented && Self.mentions($0.text, login: viewer)) }
        case "team_mention":
            activity.first { $0.kind == .commented && Self.teamMention(in: $0.text) != nil }
        case "review_requested":
            activity.first { $0.kind == .reviewRequested && isMe($0.detail) }
        default:
            nil
        }
        return reasonEvent ?? activity.first
    }

    /// What the row says: who did what, and the comment or mention it was about.
    public func summary(viewer: String?) -> InboxSummary {
        if isDue { return dueSummary }
        let me = viewer?.lowercased()
        func isMe(_ login: String?) -> Bool { me != nil && login?.lowercased() == me }
        guard let event = headline(viewer: viewer) else { return fallbackSummary }
        let who = event.actor.map(Self.name) ?? "Someone"
        switch event.kind {
        case .assigned:
            let whom = isMe(event.detail) ? "you" : (event.detail ?? "someone")
            return InboxSummary(actor: event.actor, lead: "\(who) assigned \(whom)", sign: .assigned)
        case .unassigned:
            let whom = isMe(event.detail) ? "you" : (event.detail ?? "someone")
            return InboxSummary(actor: event.actor, lead: "\(who) unassigned \(whom)", sign: .activity)
        case .mentioned:
            return InboxSummary(actor: event.actor, lead: "\(who) mentioned you", excerpt: event.text, sign: .mentioned)
        case .commented:
            if reason == "mention", Self.mentions(event.text, login: viewer) {
                return InboxSummary(actor: event.actor, lead: "\(who) mentioned you:", excerpt: event.text, sign: .mentioned)
            }
            if reason == "team_mention", let team = Self.teamMention(in: event.text) {
                return InboxSummary(actor: event.actor, lead: "\(who) mentioned \(team):", excerpt: event.text, sign: .mentioned)
            }
            let commenters = Self.uniqueActors(activity.filter { $0.kind == .commented })
            if commenters.count > 1 {
                let others = commenters.count - 1
                return InboxSummary(actor: event.actor, lead: "\(who) and \(others) other\(others == 1 ? "" : "s") commented", sign: .comments)
            }
            return InboxSummary(actor: event.actor, lead: "\(who):", excerpt: event.text, sign: .commented)
        case .opened:
            if Self.mentions(event.text, login: viewer) {
                return InboxSummary(actor: event.actor, lead: "\(who) mentioned you:", excerpt: event.text, sign: .mentioned)
            }
            let place = bucket == .watching ? " in \(repo)" : ""
            return InboxSummary(actor: event.actor, lead: "\(who) opened it\(place)", sign: .opened)
        case .closed:
            switch event.detail {
            case "NOT_PLANNED":
                return InboxSummary(actor: event.actor, lead: "\(who) closed it as not planned", sign: .notPlanned)
            case "DUPLICATE":
                return InboxSummary(actor: event.actor, lead: "\(who) closed it as a duplicate", sign: .notPlanned)
            default:
                return InboxSummary(actor: event.actor, lead: isPullRequest ? "\(who) closed it" : "\(who) closed it as completed", sign: isPullRequest ? .notPlanned : .completed)
            }
        case .reopened:
            return InboxSummary(actor: event.actor, lead: "\(who) reopened it", sign: .reopened)
        case .merged:
            return InboxSummary(actor: event.actor, lead: "\(who) merged it", sign: .merged)
        case .reviewRequested:
            let whom = isMe(event.detail) ? "your review" : "a review from \(event.detail ?? "someone")"
            return InboxSummary(actor: event.actor, lead: "\(who) requested \(whom)", sign: .reviewRequested)
        case .reviewed:
            switch event.detail {
            case "APPROVED": return InboxSummary(actor: event.actor, lead: "\(who) approved it", sign: .approved)
            case "CHANGES_REQUESTED": return InboxSummary(actor: event.actor, lead: "\(who) requested changes", excerpt: event.text, sign: .changesRequested)
            default: return InboxSummary(actor: event.actor, lead: event.text == nil ? "\(who) reviewed it" : "\(who) reviewed it:", excerpt: event.text, sign: .commented)
            }
        case .statusChanged:
            let place = event.project.map { " in \($0)" } ?? ""
            return InboxSummary(actor: event.actor, lead: "\(who) moved it to \(event.detail ?? "another status")\(place)", sign: .statusChanged)
        }
    }

    /// Before the issue has been read, or when nothing new is left to show, GitHub's reason says enough.
    private var fallbackSummary: InboxSummary {
        switch reason {
        case "assign": InboxSummary(lead: "You were assigned", sign: .assigned)
        case "mention": InboxSummary(lead: "You were mentioned", sign: .mentioned)
        case "team_mention": InboxSummary(lead: "Your team was mentioned", sign: .mentioned)
        case "review_requested": InboxSummary(lead: "Your review was requested", sign: .reviewRequested)
        case "state_change":
            state == "MERGED" ? InboxSummary(lead: "Merged", sign: .merged)
                : state == "CLOSED" ? InboxSummary(lead: "Closed", sign: stateReason == "NOT_PLANNED" ? .notPlanned : .completed)
                : InboxSummary(lead: "Reopened", sign: .reopened)
        default: InboxSummary(lead: missing ? "No longer available" : "New activity", sign: .activity)
        }
    }

    /// A person as the Inbox shows them: their name, or their login when they have none.
    static func name(_ person: Person) -> String {
        if let name = person.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty { return name }
        return person.login
    }

    private static func uniqueActors(_ events: [InboxActivity]) -> [String] {
        var seen = Set<String>()
        return events.compactMap { $0.actor?.login }.filter { seen.insert($0.lowercased()).inserted }
    }

    /// Whether the text mentions `@login` as a word of its own.
    static func mentions(_ text: String?, login: String?) -> Bool {
        guard let text, let login, !login.isEmpty else { return false }
        let pattern = "(^|[^A-Za-z0-9_/-])@" + NSRegularExpression.escapedPattern(for: login) + "(?![A-Za-z0-9_-])"
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// The first `@org/team` mentioned in the text.
    static func teamMention(in text: String?) -> String? {
        guard let text, let range = text.range(of: "@[A-Za-z0-9-]+/[A-Za-z0-9_.-]+", options: .regularExpression) else { return nil }
        return String(text[range])
    }
}

// MARK: - Issues that are due

extension InboxEntry {
    /// GitHub's reasons are words such as "assign"; these two are the app's own, for issues that are due.
    static let dueReason = "due"
    static let overdueReason = "overdue"

    /// An entry the app makes itself from an issue's due date, which GitHub knows nothing about: read, archived and
    /// snoozed are kept with the user's other Inbox records, and nothing about it is sent to GitHub.
    public var isDue: Bool { reason == Self.dueReason || reason == Self.overdueReason }

    /// The day a due entry is about.
    public var dueDay: CalendarDay? {
        guard isDue, let last = id.split(separator: ":").last else { return nil }
        return CalendarDay(String(last))
    }

    /// The entry for an issue due on `day`: "due:<issue>:<day>" from the reminder on that day, and
    /// "overdue:<issue>:<day>" from the reminder the morning after. It is dated with the reminder, so it sorts in
    /// with the notifications.
    init(due item: Item, day: CalendarDay, overdue: Bool, at moment: Date) {
        let reason = overdue ? Self.overdueReason : Self.dueReason
        self.init(
            id: "\(reason):\(item.contentId ?? item.id):\(day.string)", reason: reason, unread: true, updatedAt: moment,
            subjectType: item.kind == .pullRequest ? "PullRequest" : "Issue", title: item.title, repo: item.repo ?? "",
            number: item.number
        )
        enrichedFor = moment
        contentId = item.contentId
        url = item.url
        state = item.state
        stateReason = item.stateReason
        body = item.body
        repoId = item.repoId
        authorLogin = item.authorLogin
        createdAt = item.createdAt
        assignees = item.assignees
        labels = item.labels
    }

    /// "Due today", or "Overdue since yesterday" and "Overdue since Mon, 5 Oct".
    fileprivate var dueSummary: InboxSummary {
        guard let day = dueDay else { return InboxSummary(lead: "Due", sign: .due) }
        guard reason == Self.overdueReason else { return InboxSummary(lead: "Due today", sign: .due) }
        let since = day.days(from: .today()) == -1 ? "yesterday" : day.mediumLabel()
        return InboxSummary(lead: "Overdue since \(since)", sign: .overdue)
    }
}

// MARK: - Everything that isn't an entry

/// What the Inbox knows besides its entries: whether it can read GitHub's notifications at all, and how many there
/// are that aren't about issues or pull requests (releases, CI runs, discussions), which stay on GitHub.
public struct InboxMeta: Codable, Equatable, Sendable {
    public enum Access: String, Codable, Sendable {
        /// Never fetched yet.
        case unknown
        case ok
        /// GitHub refused: a fine-grained token, or a token without the repo or notifications scope.
        case denied
    }

    public var access: Access = .unknown
    /// Notifications of other kinds, by GitHub's subject type ("Release", "CheckSuite", "Discussion", …).
    public var others: [String: Int] = [:]
    /// GitHub's Last-Modified for the list, to ask "anything new?" for free.
    public var lastModified: String?

    public init() {}

    public var otherCount: Int { others.values.reduce(0, +) }

    static let key = "inbox"

    static func read(_ db: Database) throws -> InboxMeta {
        guard let json = try KV.string(db, key) else { return InboxMeta() }
        return (try? JSONDecoder().decode(InboxMeta.self, from: Data(json.utf8))) ?? InboxMeta()
    }

    func write(_ db: Database) throws {
        try KV.set(db, Self.key, String(decoding: try JSONEncoder().encode(self), as: UTF8.self))
    }
}

extension Item {
    /// An issue only the Inbox knows: on none of your boards, and in a repository the app doesn't read (one you
    /// only watch, say). It is made from the notification each time and not kept, so its title and description are
    /// read-only here; putting it on a board keeps it from then on.
    public var isDetached: Bool { id.hasPrefix(Self.detachedPrefix) }

    static let detachedPrefix = "detached-"

    /// An Inbox-only issue as one the app keeps, on no board, so that it can be put on one.
    var keptWithoutProject: Item {
        guard isDetached, let contentId else { return self }
        var item = self
        item.id = Item.idWithoutProject(contentId)
        return item
    }

    /// The Inbox entry's issue as an item on no board.
    init?(detached entry: InboxEntry) {
        guard let contentId = entry.contentId, !entry.missing else { return nil }
        self.init(
            id: Self.detachedPrefix + contentId,
            projectId: nil,
            kind: entry.isPullRequest ? .pullRequest : .issue,
            position: Item.positionWithoutProject(updatedAt: entry.updatedAt),
            contentId: contentId,
            number: entry.number,
            title: entry.title,
            body: entry.body,
            state: entry.state ?? "OPEN",
            stateReason: entry.stateReason,
            url: entry.webURL?.absoluteString,
            repoId: entry.repoId,
            repo: entry.repo,
            authorLogin: entry.authorLogin,
            createdAt: entry.createdAt,
            updatedAt: entry.updatedAt,
            assignees: entry.assignees,
            labels: entry.labels
        )
    }
}
