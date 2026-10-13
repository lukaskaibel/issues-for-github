import Foundation

/// What the assistant needs to know about a repository to propose changes in it: labels with what they mean, issue
/// types, and who can be assigned.
public struct RepoFacts: Sendable {
    public struct Named: Sendable, Hashable {
        public var name: String
        public var description: String
    }

    public var nameWithOwner: String
    public var labels: [Named]
    public var issueTypes: [Named]
    /// Login and display name.
    public var people: [Named]
}

extension GitHubAPI {
    public func repoFacts(repoId: String) async throws -> RepoFacts {
        struct Response: Decodable {
            struct NamedDTO: Decodable {
                var name: String
                var description: String?
            }
            struct UserDTO: Decodable {
                var login: String
                var name: String?
            }
            struct Node: Decodable {
                var nameWithOwner: String?
                var labels: Nodes<NamedDTO>?
                var issueTypes: Nodes<NamedDTO>?
                var assignableUsers: Nodes<UserDTO>?
            }
            var node: Node?
        }
        let query = """
        query($id: ID!) {
          node(id: $id) { ... on Repository {
            nameWithOwner
            labels(first: 100, orderBy: {field: NAME, direction: ASC}) { nodes { name description } }
            issueTypes(first: 50) { nodes { name description } }
            assignableUsers(first: 100) { nodes { login name } }
          } }
        }
        """
        let response: Response = try await client.run(query, variables: ["id": repoId], allowPartial: true)
        let node = response.node
        return RepoFacts(
            nameWithOwner: node?.nameWithOwner ?? "",
            labels: (node?.labels?.items ?? []).map { RepoFacts.Named(name: $0.name, description: $0.description ?? "") },
            issueTypes: (node?.issueTypes?.items ?? []).map { RepoFacts.Named(name: $0.name, description: $0.description ?? "") },
            people: (node?.assignableUsers?.items ?? []).map { RepoFacts.Named(name: $0.login, description: $0.name ?? "") }
        )
    }
}
