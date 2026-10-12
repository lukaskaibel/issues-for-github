import Foundation

/// Milestones, issue types and the label that makes an epic. GitHub's GraphQL API reads milestones but can't create
/// or change them, and it can't create labels; those go through the REST API.
extension GitHubAPI {
    // MARK: Milestones

    /// Every milestone of a repository, open and closed.
    public func milestones(repoId: String) async throws -> [Milestone] {
        struct Response: Decodable {
            struct Node: Decodable {
                struct Milestones: Decodable {
                    struct Entry: Decodable {
                        var id: String
                        var number: Int
                        var title: String
                        var description: String?
                        var dueOn: String?
                        var state: String
                        var closedAt: Date?
                        var url: String?
                    }
                    var pageInfo: PageInfo
                    var nodes: [Entry?]
                }
                var nameWithOwner: String?
                var milestones: Milestones?
            }
            var node: Node?
        }
        let query = """
        query($id: ID!, $after: String) {
          node(id: $id) { ... on Repository {
            nameWithOwner
            milestones(first: 100, after: $after, orderBy: {field: NUMBER, direction: ASC}) {
              pageInfo { hasNextPage endCursor }
              nodes { id number title description dueOn state closedAt url }
            }
          } }
        }
        """
        var result: [Milestone] = []
        var cursor: String?
        repeat {
            let response: Response = try await client.run(query, variables: ["id": repoId, "after": cursor], allowPartial: true)
            guard let node = response.node, let page = node.milestones else { break }
            result += page.nodes.compactMap { $0 }.map { entry in
                Milestone(
                    id: entry.id, repoId: repoId, repo: node.nameWithOwner ?? "", number: entry.number, title: entry.title,
                    descr: entry.description ?? "", dueOn: Self.day(fromDueOn: entry.dueOn), state: entry.state,
                    closedAt: entry.closedAt, url: entry.url
                )
            }
            cursor = page.pageInfo.hasNextPage ? page.pageInfo.endCursor : nil
        } while cursor != nil
        return result
    }

    /// GitHub keeps a milestone's due date as a moment, midnight UTC of the day; the day is all that counts.
    static func day(fromDueOn value: String?) -> String? {
        guard let value, value.count >= 10 else { return nil }
        return CalendarDay(String(value.prefix(10)))?.string
    }

    /// The moment to send for a due day. GitHub reads it in Pacific time, so noon UTC is the same day there and here.
    static func dueOn(fromDay day: String) -> String {
        "\(day)T12:00:00Z"
    }

    /// Gives an issue or pull request a milestone, or takes it away with nil.
    public func setMilestone(contentId: String, isPullRequest: Bool, milestoneId: String?) async throws {
        struct Ack: Decodable {}
        let mutation = isPullRequest
            ? "updatePullRequest(input: {pullRequestId: $id, milestoneId: $m}) { clientMutationId }"
            : "updateIssue(input: {id: $id, milestoneId: $m}) { clientMutationId }"
        let query = "mutation($id: ID!, $m: ID) { \(mutation) }"
        let _: Ack = try await client.run(query, variables: ["id": contentId, "m": milestoneId])
    }

    private struct RESTMilestone: Decodable {
        var node_id: String
        var number: Int
        var title: String
        var description: String?
        var due_on: String?
        var state: String
        var closed_at: Date?
        var html_url: String?
    }

    private func milestone(from data: Data, repoId: String, repo: String) throws -> Milestone {
        let rest = try GraphQLClient.decoder.decode(RESTMilestone.self, from: data)
        return Milestone(
            id: rest.node_id, repoId: repoId, repo: repo, number: rest.number, title: rest.title,
            descr: rest.description ?? "", dueOn: Self.day(fromDueOn: rest.due_on), state: rest.state.uppercased(),
            closedAt: rest.closed_at, url: rest.html_url
        )
    }

    /// Creates a milestone in a repository ("owner/name") and returns it as GitHub made it.
    public func createMilestone(repoId: String, repo: String, title: String, dueOn: String?, descr: String) async throws -> Milestone {
        var body: [String: Any] = ["title": title, "description": descr]
        if let dueOn { body["due_on"] = Self.dueOn(fromDay: dueOn) }
        let (data, _) = try await client.rest("POST", "repos/\(repo)/milestones", json: body)
        return try milestone(from: data, repoId: repoId, repo: repo)
    }

    /// What to change about a milestone; nil leaves a value as it is.
    public struct MilestoneChange: Codable, Sendable, Equatable {
        public var title: String?
        public var descr: String?
        /// A day, or "" to take the date away.
        public var dueOn: String?
        /// OPEN or CLOSED.
        public var state: String?

        public init(title: String? = nil, descr: String? = nil, dueOn: String? = nil, state: String? = nil) {
            self.title = title
            self.descr = descr
            self.dueOn = dueOn
            self.state = state
        }
    }

    public func updateMilestone(repoId: String, repo: String, number: Int, change: MilestoneChange) async throws -> Milestone {
        var body: [String: Any] = [:]
        if let title = change.title { body["title"] = title }
        if let descr = change.descr { body["description"] = descr }
        if let dueOn = change.dueOn {
            if dueOn.isEmpty { body["due_on"] = NSNull() } else { body["due_on"] = Self.dueOn(fromDay: dueOn) }
        }
        if let state = change.state { body["state"] = state.lowercased() }
        let (data, _) = try await client.rest("PATCH", "repos/\(repo)/milestones/\(number)", json: body)
        return try milestone(from: data, repoId: repoId, repo: repo)
    }

    // MARK: Epics

    /// The issue type named "Epic" in an issue's repository, where its organisation has one.
    public func epicIssueType(repoId: String) async throws -> String? {
        struct Response: Decodable {
            struct Node: Decodable {
                var issueTypes: Nodes<IssueTypeDTO>?
            }
            var node: Node?
        }
        let query = """
        query($id: ID!) { node(id: $id) { ... on Repository { issueTypes(first: 50) { nodes { id name } } } } }
        """
        let response: Response = try await client.run(query, variables: ["id": repoId], allowPartial: true)
        return response.node?.issueTypes?.items.first { Item.isEpicType($0.name) }?.id
    }

    public func setIssueType(contentId: String, typeId: String?) async throws {
        struct Ack: Decodable {}
        let query = """
        mutation($id: ID!, $t: ID) { updateIssueIssueType(input: {issueId: $id, issueTypeId: $t}) { clientMutationId } }
        """
        let _: Ack = try await client.run(query, variables: ["id": contentId, "t": typeId])
    }

    /// The repository's label that makes an issue an epic, made if it has none.
    public func epicLabel(repoId: String, repo: String) async throws -> LabelRef {
        struct Response: Decodable {
            struct Node: Decodable {
                var labels: Nodes<LabelDTO>?
            }
            var node: Node?
        }
        let query = """
        query($id: ID!) { node(id: $id) { ... on Repository { labels(first: 20, query: "epic") { nodes { id name color } } } } }
        """
        let response: Response = try await client.run(query, variables: ["id": repoId], allowPartial: true)
        let found = (response.node?.labels?.items ?? []).map(\.label)
        if let label = found.first(where: { $0.name.caseInsensitiveCompare(Item.epicLabelName) == .orderedSame })
            ?? found.first(where: { Item.isEpicLabel($0.name) }) {
            return label
        }
        struct RESTLabel: Decodable {
            var node_id: String
            var name: String
            var color: String
        }
        let (data, _) = try await client.rest("POST", "repos/\(repo)/labels", json: [
            "name": Item.epicLabelName, "color": Item.epicLabelColor,
        ])
        let made = try GraphQLClient.decoder.decode(RESTLabel.self, from: data)
        return LabelRef(id: made.node_id, name: made.name, color: made.color)
    }
}
