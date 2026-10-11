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
        case .forYou: String(localized: .inboxForYou)
        case .watching: String(localized: .inboxWatching)
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
        guard let number else { return String(localized: isPullRequest ? .inboxNumberPullRequest : .inboxNumberIssue) }
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
        if isSelfAssigned { return selfAssignedSummary }
        let me = viewer?.lowercased()
        func isMe(_ login: String?) -> Bool { me != nil && login?.lowercased() == me }
        guard let event = headline(viewer: viewer) else { return fallbackSummary }
        let who = event.actor.map(Self.name) ?? String(localized: .someone)
        func summary(_ lead: LocalizedStringResource, excerpt: String? = nil, sign: InboxSummary.Sign) -> InboxSummary {
            InboxSummary(actor: event.actor, lead: String(localized: lead), excerpt: excerpt, sign: sign)
        }
        switch event.kind {
        case .assigned:
            let lead: LocalizedStringResource = if isMe(event.detail) {
                .inboxAssignedYou(who: who)
            } else if let person = event.detail {
                .inboxAssignedPerson(who: who, person: person)
            } else {
                .inboxAssignedSomeone(who: who)
            }
            return summary(lead, sign: .assigned)
        case .unassigned:
            let lead: LocalizedStringResource = if isMe(event.detail) {
                .inboxUnassignedYou(who: who)
            } else if let person = event.detail {
                .inboxUnassignedPerson(who: who, person: person)
            } else {
                .inboxUnassignedSomeone(who: who)
            }
            return summary(lead, sign: .activity)
        case .mentioned:
            return summary(.inboxMentionedYou(who: who), excerpt: event.text, sign: .mentioned)
        case .commented:
            if reason == "mention", Self.mentions(event.text, login: viewer) {
                return summary(.inboxMentionedYouQuote(who: who), excerpt: event.text, sign: .mentioned)
            }
            if reason == "team_mention", let team = Self.teamMention(in: event.text) {
                return summary(.inboxMentionedTeamQuote(who: who, team: team), excerpt: event.text, sign: .mentioned)
            }
            let commenters = Self.uniqueActors(activity.filter { $0.kind == .commented })
            if commenters.count > 1 {
                return summary(.inboxOthersCommented(who: who, count: commenters.count - 1), sign: .comments)
            }
            return summary(.inboxCommentQuote(who: who), excerpt: event.text, sign: .commented)
        case .opened:
            if Self.mentions(event.text, login: viewer) {
                return summary(.inboxMentionedYouQuote(who: who), excerpt: event.text, sign: .mentioned)
            }
            let lead: LocalizedStringResource = bucket == .watching
                ? .inboxOpenedItInRepository(who: who, repository: repo)
                : .inboxOpenedIt(who: who)
            return summary(lead, sign: .opened)
        case .closed:
            switch event.detail {
            case "NOT_PLANNED":
                return summary(.inboxClosedAsNotPlanned(who: who), sign: .notPlanned)
            case "DUPLICATE":
                return summary(.inboxClosedAsDuplicate(who: who), sign: .notPlanned)
            default:
                return isPullRequest
                    ? summary(.inboxClosedPullRequest(who: who), sign: .notPlanned)
                    : summary(.inboxClosedAsCompleted(who: who), sign: .completed)
            }
        case .reopened:
            return summary(.inboxReopenedIt(who: who), sign: .reopened)
        case .merged:
            return summary(.inboxMergedIt(who: who), sign: .merged)
        case .reviewRequested:
            let lead: LocalizedStringResource = if isMe(event.detail) {
                .inboxRequestedYourReview(who: who)
            } else if let person = event.detail {
                .inboxRequestedReviewFrom(who: who, person: person)
            } else {
                .inboxRequestedReviewFromSomeone(who: who)
            }
            return summary(lead, sign: .reviewRequested)
        case .reviewed:
            switch event.detail {
            case "APPROVED": return summary(.inboxApprovedIt(who: who), sign: .approved)
            case "CHANGES_REQUESTED": return summary(.inboxRequestedChanges(who: who), excerpt: event.text, sign: .changesRequested)
            default: return summary(event.text == nil ? .inboxReviewedIt(who: who) : .inboxReviewedItQuote(who: who), excerpt: event.text, sign: .commented)
            }
        case .statusChanged:
            let lead: LocalizedStringResource = switch (event.detail, event.project) {
            case (let status?, let project?): .inboxMovedToInProject(who: who, status: status, project: project)
            case (let status?, nil): .inboxMovedTo(who: who, status: status)
            case (nil, let project?): .inboxMovedToAnotherStatusInProject(who: who, project: project)
            case (nil, nil): .inboxMovedToAnotherStatus(who: who)
            }
            return summary(lead, sign: .statusChanged)
        }
    }

    /// Before the issue has been read, or when nothing new is left to show, GitHub's reason says enough.
    private var fallbackSummary: InboxSummary {
        func summary(_ lead: LocalizedStringResource, sign: InboxSummary.Sign) -> InboxSummary {
            InboxSummary(lead: String(localized: lead), sign: sign)
        }
        return switch reason {
        case "assign": summary(.inboxYouWereAssigned, sign: .assigned)
        case "mention": summary(.inboxYouWereMentioned, sign: .mentioned)
        case "team_mention": summary(.inboxYourTeamWasMentioned, sign: .mentioned)
        case "review_requested": summary(.inboxYourReviewWasRequested, sign: .reviewRequested)
        case "state_change":
            state == "MERGED" ? summary(.inboxMerged, sign: .merged)
                : state == "CLOSED" ? summary(.inboxClosed, sign: stateReason == "NOT_PLANNED" ? .notPlanned : .completed)
                : summary(.inboxReopened, sign: .reopened)
        default: summary(missing ? .inboxNoLongerAvailable : .inboxNewActivity, sign: .activity)
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
        guard let day = dueDay else { return InboxSummary(lead: String(localized: .inboxDueLead), sign: .due) }
        guard reason == Self.overdueReason else { return InboxSummary(lead: String(localized: .dueToday), sign: .due) }
        let lead = day.days(from: .today()) == -1
            ? String(localized: .overdueSinceYesterday) : String(localized: .overdueSinceDay(day: day.mediumLabel()))
        return InboxSummary(lead: lead, sign: .overdue)
    }

    /// Entries the app makes itself, which GitHub knows nothing about: read and archived are kept with the user's
    /// other Inbox records, there is nothing to unsubscribe from, and nothing about them is sent to GitHub.
    public var isAppMade: Bool { isDue || isSelfAssigned }
}

// MARK: - Issues you were assigned to with your own account

extension InboxEntry {
    /// The app's reason for an assignment your own account made outside the app: with `gh`, a script or an agent
    /// signed in as you, or on github.com. GitHub doesn't notify anyone of what their own account does, so the app
    /// looks for these assignments itself (`SyncEngine.pullSelfAssigned`).
    static let selfAssignReason = "self_assign"

    public var isSelfAssigned: Bool { reason == Self.selfAssignReason }

    /// One entry per assignment, "self_assign:<GitHub's id of the assignment>".
    static func selfAssignedId(eventId: String) -> String {
        "\(selfAssignReason):\(eventId)"
    }

    /// The issue was opened in the same go, as `gh issue create --assignee @me` does.
    var isNewIssueAssigned: Bool {
        createdAt.map { abs(updatedAt.timeIntervalSince($0)) <= 120 } ?? false
    }

    fileprivate var selfAssignedSummary: InboxSummary {
        InboxSummary(
            actor: activity.first?.actor,
            lead: String(localized: isNewIssueAssigned ? .inboxNewIssueAssignedToYou : .inboxYouWereAssigned),
            sign: .assigned
        )
    }

    /// How much earlier than the app's record of it an assignment the app made may be dated (clocks differ), and how
    /// much later (the change waits in the queue while offline).
    static let assignedHereBefore: TimeInterval = 120
    static let assignedHereAfter: TimeInterval = 7 * 86_400

    /// The assignments among `entries` that this app made, on this device or another of yours: each time it assigned
    /// you to an issue accounts for the first assignment of that issue from then on. To GitHub they look the same as
    /// the ones made with `gh`; only the app knows which were its own.
    static func assignedInApp(_ entries: [InboxEntry], noted: (String) -> [Date]) -> Set<String> {
        var own = Set<String>()
        let byIssue = Dictionary(grouping: entries.filter { $0.isSelfAssigned && $0.contentId != nil }) { $0.contentId ?? "" }
        for (contentId, assignments) in byIssue {
            var unclaimed = assignments.sorted { $0.updatedAt < $1.updatedAt }
            for date in noted(contentId).sorted() {
                let range = date.addingTimeInterval(-assignedHereBefore)...date.addingTimeInterval(assignedHereAfter)
                guard let index = unclaimed.firstIndex(where: { range.contains($0.updatedAt) }) else { continue }
                own.insert(unclaimed.remove(at: index).id)
            }
        }
        return own
    }

    /// An assignment read from GitHub, with what the Inbox shows of its issue.
    init(selfAssignment found: RemoteSelfAssignment) {
        let issue = found.issue
        self.init(
            id: Self.selfAssignedId(eventId: found.eventId), reason: Self.selfAssignReason, unread: true,
            updatedAt: found.at, subjectType: "Issue", title: issue.title, repo: found.repo, number: found.number
        )
        enrichedFor = found.at
        refresh(from: issue)
        activity = [InboxActivity(kind: .assigned, actor: found.actor, at: found.at, detail: found.actor?.login)]
        // The assignment itself is the news, however long ago it was read.
        activityIsNew = true
    }

    /// The issue as it is now, read again while it keeps changing.
    mutating func refresh(from issue: RemoteInboxDetail) {
        title = issue.title
        contentId = issue.contentId
        url = issue.url
        state = issue.state
        stateReason = issue.stateReason
        body = issue.body
        repoId = issue.repoId
        authorLogin = issue.authorLogin
        createdAt = issue.createdAt
        assignees = issue.assignees
        labels = issue.labels
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
    /// When this device first looked for assignments made with your own account: earlier ones aren't news, and may
    /// have been made in the app before it kept track of its own.
    public var selfAssignedFrom: Date?
    /// When it last looked; the next look starts a little before.
    public var selfAssignedChecked: Date?

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
