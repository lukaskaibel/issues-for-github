import Foundation

// MARK: - Results handed to the sync engine

/// One GitHub notification thread, as the REST API lists it.
public struct RemoteThread: Sendable, Hashable {
    public var id: String
    public var reason: String
    public var unread: Bool
    public var updatedAt: Date
    public var lastReadAt: Date?
    /// "Issue", "PullRequest", "Release", "CheckSuite", "Discussion", …
    public var subjectType: String
    public var title: String
    public var repo: String
    public var number: Int?

    public var isIssueOrPullRequest: Bool { subjectType == "Issue" || subjectType == "PullRequest" }
}

public enum NotificationList: Sendable {
    /// Nothing changed since the last time (GitHub answered 304, which costs nothing against the rate limit).
    case notModified(pollInterval: TimeInterval?)
    case threads([RemoteThread], lastModified: String?, pollInterval: TimeInterval?)
}

/// What the Inbox reads from an issue or pull request: enough to show it without a board, and what happened
/// on it since the user last read the notification.
public struct RemoteInboxDetail: Sendable {
    public var contentId: String
    public var url: String
    public var title: String
    public var body: String
    /// OPEN, CLOSED or MERGED.
    public var state: String
    public var stateReason: String?
    public var repoId: String?
    public var authorLogin: String?
    public var createdAt: Date?
    public var assignees: [Person]
    public var labels: [LabelRef]
    /// Newest first.
    public var activity: [InboxActivity]
}

/// Which issue to read for an Inbox entry, and from when on its timeline counts as new.
public struct InboxDetailRequest: Sendable, Hashable {
    public var threadId: String
    public var repo: String
    public var number: Int
    public var since: Date?

    public init(threadId: String, repo: String, number: Int, since: Date?) {
        self.threadId = threadId
        self.repo = repo
        self.number = number
        self.since = since
    }
}

public enum InboxDetailResult: Sendable {
    case found(RemoteInboxDetail)
    /// GitHub doesn't know it (any more), or won't show it.
    case missing
}

// MARK: - Notifications

extension GitHubAPI {
    /// The user's notifications, newest first, read ones included: what GitHub's own inbox shows. With
    /// `ifModifiedSince`, GitHub answers "nothing new" without counting it against the rate limit.
    public func notifications(ifModifiedSince: String?, pages: Int = 4) async throws -> NotificationList {
        var threads: [RemoteThread] = []
        var lastModified: String?
        var interval: TimeInterval?
        for page in 1...max(pages, 1) {
            var headers: [String: String] = [:]
            if page == 1, let ifModifiedSince { headers["If-Modified-Since"] = ifModifiedSince }
            let (data, response) = try await client.rest("GET", "notifications", query: [
                URLQueryItem(name: "all", value: "true"),
                URLQueryItem(name: "per_page", value: "50"),
                URLQueryItem(name: "page", value: String(page)),
            ], headers: headers)
            if page == 1 {
                interval = response.value(forHTTPHeaderField: "X-Poll-Interval").flatMap(TimeInterval.init)
                if response.statusCode == 304 { return .notModified(pollInterval: interval) }
                lastModified = response.value(forHTTPHeaderField: "Last-Modified")
            }
            threads += try Self.threads(fromJSON: data)
            let hasNext = response.value(forHTTPHeaderField: "Link")?.contains("rel=\"next\"") ?? false
            if !hasNext { break }
        }
        return .threads(threads, lastModified: lastModified, pollInterval: interval)
    }

    /// Marks a thread read, on GitHub and therefore everywhere.
    public func markThreadRead(_ threadId: String) async throws {
        _ = try await client.rest("PATCH", "notifications/threads/\(threadId)")
    }

    /// GitHub's "Done": the thread leaves the inbox until something new happens on it.
    public func markThreadDone(_ threadId: String) async throws {
        _ = try await client.rest("DELETE", "notifications/threads/\(threadId)")
    }

    /// Stops notifications for the thread until the user is mentioned or comments again.
    public func unsubscribeThread(_ threadId: String) async throws {
        _ = try await client.rest("DELETE", "notifications/threads/\(threadId)/subscription")
    }

    // MARK: Reading the issues behind them

    /// Reads the issues and pull requests behind notifications, 20 per request: their content, and their timeline
    /// since each one was last read. `viewer` is left out of the activity: your own actions aren't news to you.
    public func inboxDetails(_ requests: [InboxDetailRequest], viewer: String?) async throws -> [String: InboxDetailResult] {
        var result: [String: InboxDetailResult] = [:]
        for chunk in requests.chunked(into: 20) {
            // One "since" for the whole request; each issue's own is applied when its timeline is read.
            let sinces = chunk.map(\.since)
            let since = sinces.contains(nil) ? nil : sinces.compactMap { $0 }.min()
            var variables: [String: Any?] = ["since": since.map { Self.iso8601.string(from: $0) }]
            var selections: [String] = []
            var declarations = ["$since: DateTime"]
            for (index, request) in chunk.enumerated() {
                let parts = request.repo.split(separator: "/", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                variables["o\(index)"] = parts[0]
                variables["n\(index)"] = parts[1]
                variables["k\(index)"] = request.number
                declarations += ["$o\(index): String!", "$n\(index): String!", "$k\(index): Int!"]
                selections.append("e\(index): repository(owner: $o\(index), name: $n\(index)) { id issueOrPullRequest(number: $k\(index)) { ...I ...P } }")
            }
            guard !selections.isEmpty else { continue }
            let query = """
            query(\(declarations.joined(separator: ", "))) {
              \(selections.joined(separator: "\n  "))
            }
            \(Self.inboxFragments)
            """
            let response: [String: InboxRepoDTO?] = try await client.run(query, variables: variables, allowPartial: true)
            for (index, request) in chunk.enumerated() {
                guard let repo = response["e\(index)"] ?? nil, let subject = repo.issueOrPullRequest else {
                    result[request.threadId] = .missing
                    continue
                }
                result[request.threadId] = .found(subject.detail(repoId: repo.id, since: request.since, viewer: viewer))
            }
        }
        return result
    }

    /// Reads one page of GitHub's list of notification threads.
    static func threads(fromJSON data: Data) throws -> [RemoteThread] {
        try GraphQLClient.decoder.decode([ThreadDTO].self, from: data).map(\.thread)
    }

    /// Reads one issue or pull request as the Inbox's query returns it.
    static func inboxDetail(fromJSON data: Data, repoId: String, since: Date?, viewer: String?) throws -> RemoteInboxDetail {
        try GraphQLClient.decoder.decode(SubjectDTO.self, from: data).detail(repoId: repoId, since: since, viewer: viewer)
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let inboxFragments = """
    fragment Who on Actor { login avatarUrl ... on User { name } }
    fragment I on Issue {
      __typename id url title body state stateReason createdAt
      author { ...Who }
      repository { id }
      assignees(first: 10) { nodes { id login name avatarUrl } }
      labels(first: 20) { nodes { id name color } }
      timelineItems(last: 30, since: $since, itemTypes: [ISSUE_COMMENT, ASSIGNED_EVENT, UNASSIGNED_EVENT, CLOSED_EVENT, REOPENED_EVENT, PROJECT_V2_ITEM_STATUS_CHANGED_EVENT]) {
        nodes {
          __typename
          ... on IssueComment { id createdAt bodyText author { ...Who } }
          ... on AssignedEvent { createdAt actor { ...Who } assignee { ...Assignee } }
          ... on UnassignedEvent { createdAt actor { ...Who } assignee { ...Assignee } }
          ... on ClosedEvent { createdAt stateReason actor { ...Who } }
          ... on ReopenedEvent { createdAt actor { ...Who } }
          ... on ProjectV2ItemStatusChangedEvent { createdAt status project { title } actor { ...Who } }
        }
      }
    }
    fragment P on PullRequest {
      __typename id url title body state createdAt
      author { ...Who }
      repository { id }
      assignees(first: 10) { nodes { id login name avatarUrl } }
      labels(first: 20) { nodes { id name color } }
      timelineItems(last: 30, since: $since, itemTypes: [ISSUE_COMMENT, ASSIGNED_EVENT, UNASSIGNED_EVENT, CLOSED_EVENT, REOPENED_EVENT, MERGED_EVENT, REVIEW_REQUESTED_EVENT, PULL_REQUEST_REVIEW, PROJECT_V2_ITEM_STATUS_CHANGED_EVENT]) {
        nodes {
          __typename
          ... on IssueComment { id createdAt bodyText author { ...Who } }
          ... on AssignedEvent { createdAt actor { ...Who } assignee { ...Assignee } }
          ... on UnassignedEvent { createdAt actor { ...Who } assignee { ...Assignee } }
          ... on ClosedEvent { createdAt actor { ...Who } }
          ... on ReopenedEvent { createdAt actor { ...Who } }
          ... on MergedEvent { createdAt actor { ...Who } }
          ... on ReviewRequestedEvent { createdAt actor { ...Who } requestedReviewer { ... on User { login } ... on Team { name } ... on Bot { login } ... on Mannequin { login } } }
          ... on PullRequestReview { id createdAt state bodyText author { ...Who } }
          ... on ProjectV2ItemStatusChangedEvent { createdAt status project { title } actor { ...Who } }
        }
      }
    }
    fragment Assignee on Assignee { ... on User { login } ... on Bot { login } ... on Mannequin { login } ... on Organization { login } }
    """
}

// MARK: - Wire types

private struct ThreadDTO: Decodable {
    struct Subject: Decodable {
        var title: String
        var url: String?
        var type: String
    }
    struct Repository: Decodable {
        var full_name: String
    }
    var id: String
    var reason: String
    var unread: Bool
    var updated_at: Date
    var last_read_at: Date?
    var subject: Subject
    var repository: Repository

    var thread: RemoteThread {
        // ".../repos/owner/name/issues/12" or ".../pulls/12": the number is the last part.
        let number = subject.url.flatMap { $0.split(separator: "/").last.flatMap { Int($0) } }
        return RemoteThread(
            id: id, reason: reason, unread: unread, updatedAt: updated_at, lastReadAt: last_read_at,
            subjectType: subject.type, title: subject.title, repo: repository.full_name, number: number
        )
    }
}

private struct InboxRepoDTO: Decodable {
    var id: String
    var issueOrPullRequest: SubjectDTO?
}

private struct WhoDTO: Decodable {
    var login: String?
    var avatarUrl: String?
    var name: String?

    var person: Person? {
        login.map { Person(id: "login:\($0)", login: $0, name: name, avatarUrl: avatarUrl) }
    }
}

private struct SubjectDTO: Decodable {
    struct RepoID: Decodable { var id: String }
    var __typename: String
    var id: String
    var url: String
    var title: String
    var body: String?
    var state: String
    var stateReason: String?
    var createdAt: Date?
    var author: WhoDTO?
    var repository: RepoID?
    var assignees: Nodes<PersonDTO>?
    var labels: Nodes<LabelDTO>?
    var timelineItems: Nodes<EventDTO>?

    func detail(repoId: String, since: Date?, viewer: String?) -> RemoteInboxDetail {
        let me = viewer?.lowercased()
        var activity = (timelineItems?.items ?? []).compactMap(\.activity)
        // The issue itself counts as news when it was opened after you last looked.
        if let createdAt, since.map({ createdAt > $0 }) ?? true {
            activity.append(InboxActivity(kind: .opened, actor: author?.person, at: createdAt, text: Self.excerpt(body)))
        }
        activity = activity
            .filter { since == nil || $0.at > since! }
            .filter { me == nil || $0.actor?.login.lowercased() != me }
            .sorted { $0.at > $1.at }
        return RemoteInboxDetail(
            contentId: id, url: url, title: title, body: body ?? "", state: state, stateReason: stateReason,
            repoId: repository?.id ?? repoId, authorLogin: author?.login, createdAt: createdAt,
            assignees: (assignees?.items ?? []).map(\.person), labels: (labels?.items ?? []).map(\.label),
            activity: activity
        )
    }

    /// A comment or description as a short line: plain text, whitespace folded.
    static func excerpt(_ text: String?) -> String? {
        guard let text else { return nil }
        let folded = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !folded.isEmpty else { return nil }
        return folded.count > 280 ? String(folded.prefix(280)) + "…" : folded
    }
}

private struct EventDTO: Decodable {
    struct Target: Decodable {
        var login: String?
        var name: String?
    }
    struct ProjectRef: Decodable { var title: String }
    var __typename: String
    var id: String?
    var createdAt: Date?
    var bodyText: String?
    var author: WhoDTO?
    var actor: WhoDTO?
    var assignee: Target?
    var requestedReviewer: Target?
    var stateReason: String?
    var state: String?
    var status: String?
    var project: ProjectRef?

    var activity: InboxActivity? {
        guard let at = createdAt else { return nil }
        switch __typename {
        case "IssueComment":
            return InboxActivity(kind: .commented, actor: author?.person, at: at, text: SubjectDTO.excerpt(bodyText), commentId: id)
        case "AssignedEvent":
            return InboxActivity(kind: .assigned, actor: actor?.person, at: at, detail: assignee?.login)
        case "UnassignedEvent":
            return InboxActivity(kind: .unassigned, actor: actor?.person, at: at, detail: assignee?.login)
        case "ClosedEvent":
            return InboxActivity(kind: .closed, actor: actor?.person, at: at, detail: stateReason)
        case "ReopenedEvent":
            return InboxActivity(kind: .reopened, actor: actor?.person, at: at)
        case "MergedEvent":
            return InboxActivity(kind: .merged, actor: actor?.person, at: at)
        case "ReviewRequestedEvent":
            return InboxActivity(kind: .reviewRequested, actor: actor?.person, at: at, detail: requestedReviewer?.login ?? requestedReviewer?.name)
        case "PullRequestReview":
            // A review still being written isn't news yet.
            guard state != "PENDING" else { return nil }
            return InboxActivity(kind: .reviewed, actor: author?.person, at: at, text: SubjectDTO.excerpt(bodyText), detail: state, commentId: id)
        case "ProjectV2ItemStatusChangedEvent":
            guard let status, !status.isEmpty else { return nil }
            return InboxActivity(kind: .statusChanged, actor: actor?.person, at: at, detail: status, project: project?.title)
        default:
            return nil
        }
    }
}
