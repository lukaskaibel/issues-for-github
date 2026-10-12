import Foundation

// MARK: - Results handed to the sync engine

/// One entry of a repository's issue events: what happened to which issue, and when.
public struct RemoteIssueEvent: Sendable, Hashable {
    public var id: Int
    /// GitHub's name for it, such as "parent_issue_added" or "closed".
    public var event: String
    public var createdAt: Date
    /// The issue's node id.
    public var contentId: String?
}

public enum IssueEventList: Sendable {
    /// Nothing happened since the ETag that was given (GitHub answered 304, which costs nothing against the rate limit).
    case notModified
    /// Newest first.
    case events([RemoteIssueEvent], etag: String?, hasNext: Bool)
}

// MARK: - Issue events

extension GitHubAPI {
    /// What happened to a repository's issues lately, newest first. With `ifNoneMatch` on the first page, GitHub
    /// answers "nothing new" without counting it against the rate limit. GraphQL lists events only issue by issue.
    public func issueEvents(repo nameWithOwner: String, page: Int = 1, ifNoneMatch: String? = nil) async throws -> IssueEventList {
        var headers: [String: String] = [:]
        if let ifNoneMatch { headers["If-None-Match"] = ifNoneMatch }
        let (data, response) = try await client.rest("GET", "repos/\(nameWithOwner)/issues/events", query: [
            URLQueryItem(name: "per_page", value: String(Self.issueEventsPerPage)),
            URLQueryItem(name: "page", value: String(page)),
        ], headers: headers)
        if response.statusCode == 304 { return .notModified }
        let hasNext = response.value(forHTTPHeaderField: "Link")?.contains("rel=\"next\"") ?? false
        return .events(try Self.issueEvents(fromJSON: data), etag: response.value(forHTTPHeaderField: "ETag"), hasNext: hasNext)
    }

    /// Each event carries its whole issue, so pages are kept small: most looks find a few events at most.
    static let issueEventsPerPage = 20

    static func issueEvents(fromJSON data: Data) throws -> [RemoteIssueEvent] {
        try GraphQLClient.decoder.decode([IssueEventDTO?].self, from: data).compactMap { $0?.remote }
    }
}

private struct IssueEventDTO: Decodable {
    struct Issue: Decodable {
        var node_id: String?
    }
    var id: Int
    var event: String
    var created_at: Date
    var issue: Issue?

    var remote: RemoteIssueEvent {
        RemoteIssueEvent(id: id, event: event, createdAt: created_at, contentId: issue?.node_id)
    }
}
