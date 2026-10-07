import Foundation

// MARK: - Results handed to the sync engine

public struct RemoteOption: Sendable, Hashable {
    public var id: String?
    public var name: String
    public var color: String
    public var descr: String

    public init(id: String?, name: String, color: String, descr: String = "") {
        self.id = id
        self.name = name
        self.color = color
        self.descr = descr
    }
}

public struct RemoteSelectField: Sendable {
    public var id: String
    public var name: String
    public var options: [RemoteOption]
}

/// A project field that is not a single select, such as a Date field.
public struct RemoteField: Sendable, Hashable {
    public var id: String
    public var name: String
}

public struct RemoteProjectMeta: Sendable {
    public var id: String
    public var title: String
    public var updatedAt: String
    public var closed: Bool
    public var viewerCanUpdate: Bool
    public var itemsTotal: Int
    public var statusField: RemoteSelectField?
    public var priorityField: RemoteSelectField?
    /// The Date field that says when an issue is due, picked by its name (see `dueFieldNames`).
    public var dueField: RemoteField?
    public var repos: [(id: String, nameWithOwner: String)]

    /// Names of Date fields that mean "due", in order of preference. "Start date" never does.
    public static let dueFieldNames = ["due date", "due", "deadline", "target date", "due on", "end date"]
}

public struct SweepEntry: Sendable, Hashable {
    public var id: String
    public var updatedAt: String
}

public struct RemoteIssueDetail: Sendable {
    public var title: String
    public var body: String
    public var comments: [Comment]
    public var subIssues: [SubIssue]
    /// Issues this one is blocked by, and issues it blocks.
    public var links: [LinkedIssue] = []
}

public struct CreatedIssue: Sendable {
    public var contentId: String
    public var number: Int
    public var url: String
}

/// An issue read from its repository or a search, with the boards it is on.
public struct RemoteIssue: Sendable {
    /// The issue as an item without a project.
    public var item: Item
    public var projectIds: [String]
}

/// An issue as a light read lists it: where it lives and when it last changed. Which boards it is on costs GitHub
/// a lot to say for every issue, so that is asked only of the issues read in full.
public struct IssueRef: Sendable, Hashable {
    public var contentId: String
    public var repoId: String?
    public var updatedAt: String
    public var isClosed: Bool
    public var closedAt: Date?

    public var itemId: String { Item.idWithoutProject(contentId) }
}

/// Everything the app asks of GitHub. One method per round trip.
public final class GitHubAPI: Sendable {
    public let client: GraphQLClient

    public init(client: GraphQLClient) {
        self.client = client
    }

    // MARK: Reading

    public func viewerAndProjects() async throws -> (Viewer, [Project]) {
        struct Response: Decodable {
            struct ViewerDTO: Decodable {
                var id: String
                var login: String
                var name: String?
                var avatarUrl: String?
                var projectsV2: Nodes<ProjectDTO>
                var organizations: Nodes<Org>
            }
            struct Org: Decodable {
                var login: String
                var projectsV2: Nodes<ProjectDTO>?
            }
            var viewer: ViewerDTO
        }
        let query = """
        query {
          viewer {
            id login name avatarUrl
            projectsV2(first: 50) { nodes { ...P } }
            organizations(first: 50) { nodes { login projectsV2(first: 50) { nodes { ...P } } } }
          }
        }
        fragment P on ProjectV2 { id number title url closed viewerCanUpdate }
        """
        // Organisations that enforce SAML return errors for their part only; keep the rest.
        let response: Response = try await client.run(query, allowPartial: true)
        let v = response.viewer
        var projects = v.projectsV2.items.map { $0.project(owner: v.login, isOrg: false) }
        for org in v.organizations.items {
            projects += (org.projectsV2?.items ?? []).map { $0.project(owner: org.login, isOrg: true) }
        }
        return (Viewer(id: v.id, login: v.login, name: v.name, avatarUrl: v.avatarUrl), projects)
    }

    public func projectMeta(id: String) async throws -> RemoteProjectMeta {
        struct Response: Decodable {
            struct Node: Decodable {
                var id: String
                var title: String
                var updatedAt: String
                var closed: Bool
                var viewerCanUpdate: Bool
                var items: Count
                var fields: Nodes<FieldDTO>
                var repositories: Nodes<RepoDTO>?
            }
            var node: Node?
        }
        let query = """
        query($id: ID!) {
          node(id: $id) { ... on ProjectV2 {
            id title updatedAt closed viewerCanUpdate
            items { totalCount }
            fields(first: 50) { nodes { __typename
              ... on ProjectV2SingleSelectField { id name options { id name color description } }
              ... on ProjectV2Field { id name dataType } } }
            repositories(first: 50) { nodes { id nameWithOwner } }
          } }
        }
        """
        let response: Response = try await client.run(query, variables: ["id": id], allowPartial: true)
        guard let node = response.node else {
            throw APIError.graphql([GraphQLErrorItem(message: String(localized: .errorProjectNotFound), type: "NOT_FOUND")])
        }
        func field(named name: String) -> RemoteSelectField? {
            node.fields.items
                .first { $0.id != nil && $0.options != nil && $0.name?.caseInsensitiveCompare(name) == .orderedSame }
                .map { dto in
                    RemoteSelectField(id: dto.id!, name: dto.name!, options: (dto.options ?? []).map {
                        RemoteOption(id: $0.id, name: $0.name, color: $0.color, descr: $0.description ?? "")
                    })
                }
        }
        let dateFields = node.fields.items.filter { $0.dataType == "DATE" && $0.id != nil && $0.name != nil }
        let dueField = RemoteProjectMeta.dueFieldNames.lazy
            .compactMap { wanted in dateFields.first { $0.name!.lowercased() == wanted } }
            .first
            .map { RemoteField(id: $0.id!, name: $0.name!) }
        return RemoteProjectMeta(
            id: node.id,
            title: node.title,
            updatedAt: node.updatedAt,
            closed: node.closed,
            viewerCanUpdate: node.viewerCanUpdate,
            itemsTotal: node.items.totalCount,
            statusField: field(named: "Status"),
            priorityField: field(named: "Priority"),
            dueField: dueField,
            repos: (node.repositories?.items ?? []).map { ($0.id, $0.nameWithOwner) }
        )
    }

    /// Every item of the project in board order, with only what is needed to tell what changed.
    public func sweep(projectId: String) async throws -> [SweepEntry] {
        struct Response: Decodable {
            struct Node: Decodable {
                struct Items: Decodable {
                    struct Entry: Decodable {
                        var id: String
                        var updatedAt: String
                    }
                    var pageInfo: PageInfo
                    var nodes: [Entry?]
                }
                var items: Items
            }
            var node: Node?
        }
        let query = """
        query($id: ID!, $after: String) {
          node(id: $id) { ... on ProjectV2 {
            items(first: 100, after: $after, orderBy: {field: POSITION, direction: ASC}) {
              pageInfo { hasNextPage endCursor }
              nodes { id updatedAt }
            }
          } }
        }
        """
        var entries: [SweepEntry] = []
        var cursor: String?
        repeat {
            let response: Response = try await client.run(query, variables: ["id": projectId, "after": cursor], allowPartial: true)
            guard let items = response.node?.items else { break }
            entries += items.nodes.compactMap { $0 }.map { SweepEntry(id: $0.id, updatedAt: $0.updatedAt) }
            cursor = items.pageInfo.hasNextPage ? items.pageInfo.endCursor : nil
        } while cursor != nil
        return entries
    }

    /// Full card data for the given project items. `position` is left at 0 for the caller to fill in.
    public func hydrate(
        itemIds: [String], projectId: String, statusFieldId: String?, priorityFieldId: String?, dueFieldId: String?
    ) async throws -> [Item] {
        struct Response: Decodable {
            var nodes: [ItemDTO?]
        }
        let query = """
        query($ids: [ID!]!) {
          nodes(ids: $ids) { ... on ProjectV2Item { ...ItemFields } }
        }
        \(GQL.itemFields)
        """
        var result: [Item] = []
        for chunk in itemIds.chunked(into: 40) {
            let response: Response = try await client.run(query, variables: ["ids": chunk], allowPartial: true)
            result += response.nodes.compactMap { $0 }.compactMap {
                $0.item(projectId: projectId, statusFieldId: statusFieldId, priorityFieldId: priorityFieldId, dueFieldId: dueFieldId)
            }
        }
        return result
    }

    /// What a repository's issues are and where they are, without their text: enough to tell which are on none of
    /// your boards and which changed. `since` limits them to those updated since then.
    public func repositoryIssueRefs(repoId: String, states: [String]?, since: Date?) async throws -> [IssueRef] {
        struct Response: Decodable {
            struct Node: Decodable {
                struct Issues: Decodable {
                    var pageInfo: PageInfo
                    var nodes: [IssueRefDTO?]
                }
                var issues: Issues?
            }
            var node: Node?
        }
        let query = """
        query($id: ID!, $after: String, $states: [IssueState!], $since: DateTime) {
          node(id: $id) { ... on Repository {
            issues(first: 100, after: $after, states: $states, filterBy: {since: $since}, orderBy: {field: UPDATED_AT, direction: DESC}) {
              pageInfo { hasNextPage endCursor }
              nodes { ...IssueRefFields }
            }
          } }
        }
        \(GQL.issueRefFields)
        """
        var result: [IssueRef] = []
        var cursor: String?
        repeat {
            var variables: [String: Any?] = ["id": repoId, "after": cursor, "states": states]
            variables["since"] = since.map { ISO8601DateFormatter().string(from: $0) }
            let response: Response = try await client.run(query, variables: variables, allowPartial: true)
            guard let issues = response.node?.issues else { break }
            result += issues.nodes.compactMap { $0?.ref }
            cursor = issues.pageInfo.hasNextPage ? issues.pageInfo.endCursor : nil
        } while cursor != nil
        return result
    }

    /// Open issues assigned to you, in any repository you can see, without their text.
    public func assignedIssueRefs() async throws -> [IssueRef] {
        struct Response: Decodable {
            struct Search: Decodable {
                var pageInfo: PageInfo
                var nodes: [IssueRefDTO?]
            }
            var search: Search
        }
        let query = """
        query($after: String) {
          search(type: ISSUE, query: "is:issue is:open assignee:@me archived:false", first: 100, after: $after) {
            pageInfo { hasNextPage endCursor }
            nodes { ...IssueRefFields }
          }
        }
        \(GQL.issueRefFields)
        """
        var result: [IssueRef] = []
        var cursor: String?
        repeat {
            let response: Response = try await client.run(query, variables: ["after": cursor], allowPartial: true)
            result += response.search.nodes.compactMap { $0?.ref }
            cursor = response.search.pageInfo.hasNextPage ? response.search.pageInfo.endCursor : nil
        } while cursor != nil && result.count < 1000
        return result
    }

    /// Full data of the given issues, as items without a project.
    public func issues(ids: [String]) async throws -> [RemoteIssue] {
        struct Response: Decodable {
            var nodes: [IssueNodeDTO?]
        }
        let query = """
        query($ids: [ID!]!) {
          nodes(ids: $ids) { ... on Issue { ...IssueFields } }
        }
        \(GQL.issueFields)
        """
        var result: [RemoteIssue] = []
        for chunk in ids.chunked(into: 40) {
            let response: Response = try await client.run(query, variables: ["ids": chunk], allowPartial: true)
            result += response.nodes.compactMap { $0?.remote }
        }
        return result
    }

    public func issueDetail(contentId: String) async throws -> RemoteIssueDetail {
        struct Response: Decodable {
            struct Node: Decodable {
                struct CommentDTO: Decodable {
                    var id: String
                    var body: String
                    var createdAt: Date
                    var author: ActorDTO?
                }
                struct SubDTO: Decodable {
                    var id: String
                    var number: Int
                    var title: String
                    var state: String
                    var stateReason: String?
                    var url: String?
                    var repository: RepoDTO?
                    var assignees: Nodes<PersonDTO>?
                }
                var title: String?
                var body: String?
                var comments: Nodes<CommentDTO>?
                var subIssues: Nodes<SubDTO>?
                var blockedBy: Nodes<SubDTO>?
                var blocking: Nodes<SubDTO>?
            }
            var node: Node?
        }
        let query = """
        query($id: ID!) {
          node(id: $id) {
            ... on Issue {
              title body
              comments(first: 100) { nodes { id body createdAt author { login avatarUrl } } }
              subIssues(first: 100) { nodes { id number title state stateReason url
                repository { id nameWithOwner }
                assignees(first: 3) { nodes { id login name avatarUrl } } } }
              blockedBy(first: 50) { nodes { id number title state stateReason url repository { id nameWithOwner } } }
              blocking(first: 50) { nodes { id number title state stateReason url repository { id nameWithOwner } } }
            }
            ... on PullRequest {
              title body
              comments(first: 100) { nodes { id body createdAt author { login avatarUrl } } }
            }
          }
        }
        """
        let response: Response = try await client.run(query, variables: ["id": contentId])
        guard let node = response.node else {
            throw APIError.graphql([GraphQLErrorItem(message: String(localized: .errorIssueNotFound), type: "NOT_FOUND")])
        }
        let comments = (node.comments?.items ?? []).map {
            Comment(id: $0.id, issueId: contentId, authorLogin: $0.author?.login, authorAvatarUrl: $0.author?.avatarUrl, body: $0.body, createdAt: $0.createdAt)
        }
        let subs = (node.subIssues?.items ?? []).enumerated().map { index, sub in
            SubIssue(
                id: sub.id, parentId: contentId, number: sub.number, title: sub.title, state: sub.state,
                stateReason: sub.stateReason, repo: sub.repository?.nameWithOwner, url: sub.url, position: index,
                assignees: (sub.assignees?.items ?? []).map(\.person)
            )
        }
        var links: [LinkedIssue] = []
        for (relation, nodes) in [(LinkedIssue.Relation.blockedBy, node.blockedBy), (.blocking, node.blocking)] {
            links += (nodes?.items ?? []).enumerated().map { index, other in
                LinkedIssue(
                    id: other.id, issueId: contentId, relation: relation, number: other.number, title: other.title,
                    state: other.state, stateReason: other.stateReason, repo: other.repository?.nameWithOwner,
                    url: other.url, position: index
                )
            }
        }
        return RemoteIssueDetail(title: node.title ?? "", body: node.body ?? "", comments: comments, subIssues: subs, links: links)
    }

    /// Current title and body, fetched right before sending a text edit to catch concurrent changes.
    public func issueText(contentId: String) async throws -> (title: String, body: String) {
        struct Response: Decodable {
            struct Node: Decodable {
                var title: String?
                var body: String?
            }
            var node: Node?
        }
        let query = """
        query($id: ID!) { node(id: $id) { ... on Issue { title body } ... on PullRequest { title body } } }
        """
        let response: Response = try await client.run(query, variables: ["id": contentId])
        guard let node = response.node, let title = node.title else {
            throw APIError.graphql([GraphQLErrorItem(message: String(localized: .errorIssueNotFound), type: "NOT_FOUND")])
        }
        return (title, node.body ?? "")
    }

    public func repoMeta(repoId: String) async throws -> (labels: [LabelRef], users: [Person]) {
        struct Response: Decodable {
            struct Node: Decodable {
                var labels: Nodes<LabelDTO>?
                var assignableUsers: Nodes<PersonDTO>?
            }
            var node: Node?
        }
        let query = """
        query($id: ID!) {
          node(id: $id) { ... on Repository {
            labels(first: 100, orderBy: {field: NAME, direction: ASC}) { nodes { id name color } }
            assignableUsers(first: 100) { nodes { id login name avatarUrl } }
          } }
        }
        """
        let response: Response = try await client.run(query, variables: ["id": repoId], allowPartial: true)
        return (
            (response.node?.labels?.items ?? []).map(\.label),
            (response.node?.assignableUsers?.items ?? []).map(\.person)
        )
    }

    // MARK: Writing

    private struct Ack: Decodable {}

    public func setFieldValue(projectId: String, itemId: String, fieldId: String, optionId: String?) async throws {
        if let optionId {
            let query = """
            mutation($p: ID!, $i: ID!, $f: ID!, $o: String!) {
              updateProjectV2ItemFieldValue(input: {projectId: $p, itemId: $i, fieldId: $f, value: {singleSelectOptionId: $o}}) { clientMutationId }
            }
            """
            let _: Ack = try await client.run(query, variables: ["p": projectId, "i": itemId, "f": fieldId, "o": optionId])
        } else {
            let query = """
            mutation($p: ID!, $i: ID!, $f: ID!) {
              clearProjectV2ItemFieldValue(input: {projectId: $p, itemId: $i, fieldId: $f}) { clientMutationId }
            }
            """
            let _: Ack = try await client.run(query, variables: ["p": projectId, "i": itemId, "f": fieldId])
        }
    }

    /// Sets a Date field to a day ("2026-10-09"), or clears it.
    public func setDateValue(projectId: String, itemId: String, fieldId: String, date: String?) async throws {
        guard let date else {
            try await setFieldValue(projectId: projectId, itemId: itemId, fieldId: fieldId, optionId: nil)
            return
        }
        let query = """
        mutation($p: ID!, $i: ID!, $f: ID!, $d: Date!) {
          updateProjectV2ItemFieldValue(input: {projectId: $p, itemId: $i, fieldId: $f, value: {date: $d}}) { clientMutationId }
        }
        """
        let _: Ack = try await client.run(query, variables: ["p": projectId, "i": itemId, "f": fieldId, "d": date])
    }

    public func moveItem(projectId: String, itemId: String, afterId: String?) async throws {
        let query = """
        mutation($p: ID!, $i: ID!, $a: ID) {
          updateProjectV2ItemPosition(input: {projectId: $p, itemId: $i, afterId: $a}) { clientMutationId }
        }
        """
        let _: Ack = try await client.run(query, variables: ["p": projectId, "i": itemId, "a": afterId])
    }

    public func updateIssue(contentId: String, title: String? = nil, body: String? = nil) async throws {
        let query = """
        mutation($id: ID!, $title: String, $body: String) {
          updateIssue(input: {id: $id, title: $title, body: $body}) { clientMutationId }
        }
        """
        let _: Ack = try await client.run(query, variables: ["id": contentId, "title": title, "body": body])
    }

    public func closeIssue(contentId: String, reason: String) async throws {
        let query = """
        mutation($id: ID!, $r: IssueClosedStateReason) {
          closeIssue(input: {issueId: $id, stateReason: $r}) { clientMutationId }
        }
        """
        let _: Ack = try await client.run(query, variables: ["id": contentId, "r": reason])
    }

    /// Deletes an issue for good. GitHub only allows it with admin rights in the repository.
    public func deleteIssue(contentId: String) async throws {
        let query = """
        mutation($id: ID!) { deleteIssue(input: {issueId: $id}) { clientMutationId } }
        """
        let _: Ack = try await client.run(query, variables: ["id": contentId])
    }

    /// Removes an item from a project. For a draft issue, that deletes it.
    public func deleteProjectItem(projectId: String, itemId: String) async throws {
        let query = """
        mutation($p: ID!, $i: ID!) { deleteProjectV2Item(input: {projectId: $p, itemId: $i}) { deletedItemId } }
        """
        let _: Ack = try await client.run(query, variables: ["p": projectId, "i": itemId])
    }

    public func reopenIssue(contentId: String) async throws {
        let query = """
        mutation($id: ID!) { reopenIssue(input: {issueId: $id}) { clientMutationId } }
        """
        let _: Ack = try await client.run(query, variables: ["id": contentId])
    }

    public func editAssignees(contentId: String, add: [String], remove: [String]) async throws {
        if !add.isEmpty {
            let query = """
            mutation($id: ID!, $ids: [ID!]!) { addAssigneesToAssignable(input: {assignableId: $id, assigneeIds: $ids}) { clientMutationId } }
            """
            let _: Ack = try await client.run(query, variables: ["id": contentId, "ids": add])
        }
        if !remove.isEmpty {
            let query = """
            mutation($id: ID!, $ids: [ID!]!) { removeAssigneesFromAssignable(input: {assignableId: $id, assigneeIds: $ids}) { clientMutationId } }
            """
            let _: Ack = try await client.run(query, variables: ["id": contentId, "ids": remove])
        }
    }

    public func editLabels(contentId: String, add: [String], remove: [String]) async throws {
        if !add.isEmpty {
            let query = """
            mutation($id: ID!, $ids: [ID!]!) { addLabelsToLabelable(input: {labelableId: $id, labelIds: $ids}) { clientMutationId } }
            """
            let _: Ack = try await client.run(query, variables: ["id": contentId, "ids": add])
        }
        if !remove.isEmpty {
            let query = """
            mutation($id: ID!, $ids: [ID!]!) { removeLabelsFromLabelable(input: {labelableId: $id, labelIds: $ids}) { clientMutationId } }
            """
            let _: Ack = try await client.run(query, variables: ["id": contentId, "ids": remove])
        }
    }

    /// Makes `childId` a sub-issue of `parentId`, taking it out of the parent it had.
    public func addSubIssue(parentId: String, childId: String) async throws {
        let query = """
        mutation($p: ID!, $c: ID!) { addSubIssue(input: {issueId: $p, subIssueId: $c, replaceParent: true}) { clientMutationId } }
        """
        let _: Ack = try await client.run(query, variables: ["p": parentId, "c": childId])
    }

    public func removeSubIssue(parentId: String, childId: String) async throws {
        let query = """
        mutation($p: ID!, $c: ID!) { removeSubIssue(input: {issueId: $p, subIssueId: $c}) { clientMutationId } }
        """
        let _: Ack = try await client.run(query, variables: ["p": parentId, "c": childId])
    }

    /// Marks `issueId` as blocked by `blockerId`, or no longer.
    public func setBlockedBy(issueId: String, blockerId: String, blocked: Bool) async throws {
        let name = blocked ? "addBlockedBy" : "removeBlockedBy"
        let query = """
        mutation($i: ID!, $b: ID!) { \(name)(input: {issueId: $i, blockingIssueId: $b}) { clientMutationId } }
        """
        let _: Ack = try await client.run(query, variables: ["i": issueId, "b": blockerId])
    }

    /// Returns the new comment's id.
    public func addComment(contentId: String, body: String) async throws -> String {
        struct Response: Decodable {
            struct Payload: Decodable {
                struct Edge: Decodable {
                    struct Node: Decodable { var id: String }
                    var node: Node?
                }
                var commentEdge: Edge?
            }
            var addComment: Payload?
        }
        let query = """
        mutation($id: ID!, $body: String!) {
          addComment(input: {subjectId: $id, body: $body}) { commentEdge { node { id } } }
        }
        """
        let response: Response = try await client.run(query, variables: ["id": contentId, "body": body])
        return response.addComment?.commentEdge?.node?.id ?? LocalID.make()
    }

    public func createIssue(
        repoId: String, title: String, body: String, assigneeIds: [String], labelIds: [String], parentContentId: String?
    ) async throws -> CreatedIssue {
        struct Response: Decodable {
            struct Payload: Decodable {
                struct IssueDTO: Decodable {
                    var id: String
                    var number: Int
                    var url: String
                }
                var issue: IssueDTO?
            }
            var createIssue: Payload?
        }
        let query = """
        mutation($repo: ID!, $title: String!, $body: String, $assignees: [ID!], $labels: [ID!], $parent: ID) {
          createIssue(input: {repositoryId: $repo, title: $title, body: $body, assigneeIds: $assignees, labelIds: $labels, parentIssueId: $parent}) {
            issue { id number url }
          }
        }
        """
        let response: Response = try await client.run(query, variables: [
            "repo": repoId, "title": title, "body": body,
            "assignees": assigneeIds, "labels": labelIds, "parent": parentContentId,
        ])
        guard let issue = response.createIssue?.issue else {
            throw APIError.decoding("createIssue returned no issue.")
        }
        return CreatedIssue(contentId: issue.id, number: issue.number, url: issue.url)
    }

    /// Adds an issue to a project and returns the project item's id. Safe to repeat.
    public func addToProject(projectId: String, contentId: String) async throws -> String {
        struct Response: Decodable {
            struct Payload: Decodable {
                struct ItemRef: Decodable { var id: String }
                var item: ItemRef?
            }
            var addProjectV2ItemById: Payload?
        }
        let query = """
        mutation($p: ID!, $c: ID!) { addProjectV2ItemById(input: {projectId: $p, contentId: $c}) { item { id } } }
        """
        let response: Response = try await client.run(query, variables: ["p": projectId, "c": contentId])
        guard let id = response.addProjectV2ItemById?.item?.id else {
            throw APIError.decoding("addProjectV2ItemById returned no item.")
        }
        return id
    }

    /// Replaces the options of a single-select field. Options that carry an `id` keep it, so cards keep their value.
    public func updateFieldOptions(fieldId: String, options: [RemoteOption]) async throws -> [RemoteOption] {
        struct Response: Decodable {
            struct Payload: Decodable {
                var projectV2Field: FieldDTO?
            }
            var updateProjectV2Field: Payload?
        }
        let query = """
        mutation($f: ID!, $options: [ProjectV2SingleSelectFieldOptionInput!]) {
          updateProjectV2Field(input: {fieldId: $f, singleSelectOptions: $options}) {
            projectV2Field { ... on ProjectV2SingleSelectField { id name options { id name color description } } }
          }
        }
        """
        let payload: [[String: Any]] = options.map { option in
            var entry: [String: Any] = ["name": option.name, "color": option.color, "description": option.descr]
            if let id = option.id { entry["id"] = id }
            return entry
        }
        let response: Response = try await client.run(query, variables: ["f": fieldId, "options": payload])
        return (response.updateProjectV2Field?.projectV2Field?.options ?? []).map {
            RemoteOption(id: $0.id, name: $0.name, color: $0.color, descr: $0.description ?? "")
        }
    }

    /// Adds a single-select field (used to add Priority to a project that has none) and returns it.
    public func createSelectField(projectId: String, name: String, options: [RemoteOption]) async throws -> RemoteSelectField {
        struct Response: Decodable {
            struct Payload: Decodable {
                var projectV2Field: FieldDTO?
            }
            var createProjectV2Field: Payload?
        }
        let query = """
        mutation($p: ID!, $name: String!, $options: [ProjectV2SingleSelectFieldOptionInput!]) {
          createProjectV2Field(input: {projectId: $p, dataType: SINGLE_SELECT, name: $name, singleSelectOptions: $options}) {
            projectV2Field { ... on ProjectV2SingleSelectField { id name options { id name color description } } }
          }
        }
        """
        let payload: [[String: Any]] = options.map { ["name": $0.name, "color": $0.color, "description": $0.descr] }
        let response: Response = try await client.run(query, variables: ["p": projectId, "name": name, "options": payload])
        guard let field = response.createProjectV2Field?.projectV2Field, let id = field.id else {
            throw APIError.decoding("createProjectV2Field returned no field.")
        }
        return RemoteSelectField(id: id, name: field.name ?? name, options: (field.options ?? []).map {
            RemoteOption(id: $0.id, name: $0.name, color: $0.color, descr: $0.description ?? "")
        })
    }
}

extension GitHubAPI {
    /// Adds a Date field (used to add "Due date" to a project that has none) and returns it.
    public func createDateField(projectId: String, name: String) async throws -> RemoteField {
        struct Response: Decodable {
            struct Payload: Decodable {
                var projectV2Field: FieldDTO?
            }
            var createProjectV2Field: Payload?
        }
        let query = """
        mutation($p: ID!, $name: String!) {
          createProjectV2Field(input: {projectId: $p, dataType: DATE, name: $name}) {
            projectV2Field { ... on ProjectV2Field { id name } }
          }
        }
        """
        let response: Response = try await client.run(query, variables: ["p": projectId, "name": name])
        guard let field = response.createProjectV2Field?.projectV2Field, let id = field.id else {
            throw APIError.decoding("createProjectV2Field returned no field.")
        }
        return RemoteField(id: id, name: field.name ?? name)
    }
}

// MARK: - Wire types

enum GQL {
    /// An issue on its own, with the boards it is on, for issues read from a repository or a search.
    static let issueFields = """
    fragment IssueFields on Issue {
      __typename id number title body state stateReason url createdAt updatedAt closedAt
      author { login } repository { id nameWithOwner }
      assignees(first: 10) { nodes { id login name avatarUrl } }
      labels(first: 20) { nodes { id name color } }
      parent { id number title }
      viewerCanDelete
      subIssuesSummary { total completed }
      issueDependenciesSummary { blockedBy blocking }
      comments { totalCount }
      projectItems(first: 20) { nodes { project { id } } }
    }
    """

    static let issueRefFields = """
    fragment IssueRefFields on Issue {
      id updatedAt state closedAt repository { id }
    }
    """

    static let itemFields = """
    fragment ItemFields on ProjectV2Item {
      id updatedAt type
      fieldValues(first: 30) { nodes { __typename
        ... on ProjectV2ItemFieldSingleSelectValue { optionId field { ... on ProjectV2SingleSelectField { id } } }
        ... on ProjectV2ItemFieldDateValue { date field { ... on ProjectV2Field { id } } } } }
      content { __typename
        ... on Issue { id number title body state stateReason url createdAt updatedAt closedAt
          author { login } repository { id nameWithOwner }
          assignees(first: 10) { nodes { id login name avatarUrl } }
          labels(first: 20) { nodes { id name color } }
          parent { id number title }
          viewerCanDelete
          subIssuesSummary { total completed }
          issueDependenciesSummary { blockedBy blocking }
          comments { totalCount } }
        ... on PullRequest { id number title body state url createdAt updatedAt closedAt
          author { login } repository { id nameWithOwner }
          assignees(first: 10) { nodes { id login name avatarUrl } }
          labels(first: 20) { nodes { id name color } }
          comments { totalCount } }
        ... on DraftIssue { id title body createdAt updatedAt
          creator { login }
          assignees(first: 10) { nodes { id login name avatarUrl } } }
      }
    }
    """
}

struct Nodes<T: Decodable>: Decodable {
    var nodes: [T?]?
    var items: [T] { (nodes ?? []).compactMap { $0 } }
}

struct PageInfo: Decodable {
    var hasNextPage: Bool
    var endCursor: String?
}

struct Count: Decodable {
    var totalCount: Int
}

struct ActorDTO: Decodable {
    var login: String
    var avatarUrl: String?
}

struct RepoDTO: Decodable {
    var id: String
    var nameWithOwner: String
}

struct PersonDTO: Decodable {
    var id: String
    var login: String
    var name: String?
    var avatarUrl: String?
    var person: Person { Person(id: id, login: login, name: name, avatarUrl: avatarUrl) }
}

struct LabelDTO: Decodable {
    var id: String
    var name: String
    var color: String
    var label: LabelRef { LabelRef(id: id, name: name, color: color) }
}

struct FieldDTO: Decodable {
    struct OptionDTO: Decodable {
        var id: String
        var name: String
        var color: String
        var description: String?
    }
    var id: String?
    var name: String?
    var options: [OptionDTO]?
    /// DATE, TEXT, NUMBER and so on, for fields that are not single selects.
    var dataType: String?
}

struct ProjectDTO: Decodable {
    var id: String
    var number: Int
    var title: String
    var url: String
    var closed: Bool
    var viewerCanUpdate: Bool

    func project(owner: String, isOrg: Bool) -> Project {
        Project(
            id: id, ownerLogin: owner, ownerIsOrg: isOrg, number: number, title: title, url: url,
            closed: closed, viewerCanUpdate: viewerCanUpdate
        )
    }
}

struct ItemDTO: Decodable {
    struct FieldValue: Decodable {
        struct FieldRef: Decodable { var id: String? }
        var optionId: String?
        /// "2026-10-09", for a Date field.
        var date: String?
        var field: FieldRef?
    }
    struct Content: Decodable {
        struct Parent: Decodable {
            var id: String
            var number: Int
            var title: String
        }
        struct SubSummary: Decodable {
            var total: Int
            var completed: Int
        }
        struct DependencySummary: Decodable {
            var blockedBy: Int
            var blocking: Int
        }
        var __typename: String
        var id: String?
        var number: Int?
        var title: String?
        var body: String?
        var state: String?
        var stateReason: String?
        var url: String?
        var createdAt: Date?
        var updatedAt: Date?
        var closedAt: Date?
        var author: ActorDTO?
        var creator: ActorDTO?
        var repository: RepoDTO?
        var assignees: Nodes<PersonDTO>?
        var labels: Nodes<LabelDTO>?
        var parent: Parent?
        var subIssuesSummary: SubSummary?
        var issueDependenciesSummary: DependencySummary?
        var comments: Count?
        var viewerCanDelete: Bool?
    }

    // Absent when the node id did not resolve to a project item.
    var id: String?
    var updatedAt: String?
    var type: String?
    var fieldValues: Nodes<FieldValue>?
    var content: Content?

    func item(projectId: String, statusFieldId: String?, priorityFieldId: String?, dueFieldId: String?) -> Item? {
        guard let id, let type, let kind = ItemKind(rawValue: type), kind != .redacted, let content else { return nil }
        func option(for fieldId: String?) -> String? {
            guard let fieldId else { return nil }
            return fieldValues?.items.first { $0.field?.id == fieldId }?.optionId
        }
        let dueDate = dueFieldId.flatMap { fieldId in
            fieldValues?.items.first { $0.field?.id == fieldId }?.date.flatMap(CalendarDay.init)?.string
        }
        return content.item(
            id: id, projectId: projectId, kind: kind, position: 0, remoteUpdatedAt: updatedAt,
            statusId: option(for: statusFieldId), priorityId: option(for: priorityFieldId), dueDate: dueDate
        )
    }
}

extension ItemDTO.Content {
    func item(
        id: String, projectId: String?, kind: ItemKind, position: Double, remoteUpdatedAt: String?,
        statusId: String?, priorityId: String?, dueDate: String? = nil
    ) -> Item {
        let content = self
        return Item(
            id: id,
            projectId: projectId,
            kind: kind,
            position: position,
            remoteUpdatedAt: remoteUpdatedAt,
            dirty: false,
            statusId: statusId,
            priorityId: priorityId,
            dueDate: dueDate,
            contentId: content.id,
            number: content.number,
            title: content.title ?? "",
            body: content.body ?? "",
            state: content.state ?? "OPEN",
            stateReason: content.stateReason,
            url: content.url,
            repoId: content.repository?.id,
            repo: content.repository?.nameWithOwner,
            authorLogin: content.author?.login ?? content.creator?.login,
            createdAt: content.createdAt,
            updatedAt: content.updatedAt,
            closedAt: content.closedAt,
            parentId: content.parent?.id,
            parentNumber: content.parent?.number,
            parentTitle: content.parent?.title,
            subTotal: content.subIssuesSummary?.total ?? 0,
            subCompleted: content.subIssuesSummary?.completed ?? 0,
            commentCount: content.comments?.totalCount ?? 0,
            assignees: (content.assignees?.items ?? []).map(\.person),
            labels: (content.labels?.items ?? []).map(\.label),
            viewerCanDelete: content.viewerCanDelete ?? false,
            blockedByCount: content.issueDependenciesSummary?.blockedBy ?? 0,
            blockingCount: content.issueDependenciesSummary?.blocking ?? 0
        )
    }
}

struct IssueRefDTO: Decodable {
    struct RepoRefDTO: Decodable { var id: String }
    var id: String?
    var updatedAt: String?
    var state: String?
    var closedAt: Date?
    var repository: RepoRefDTO?

    var ref: IssueRef? {
        guard let id, let updatedAt else { return nil }
        return IssueRef(contentId: id, repoId: repository?.id, updatedAt: updatedAt, isClosed: state != "OPEN", closedAt: closedAt)
    }
}

/// An issue read on its own: the same fields as a card's content, plus the boards it is on.
struct IssueNodeDTO: Decodable {
    struct ProjectItem: Decodable {
        struct ProjectRef: Decodable { var id: String }
        var project: ProjectRef?
    }
    private enum Keys: String, CodingKey { case projectItems, updatedAt }

    var content: ItemDTO.Content
    var projectIds: [String]
    /// As GitHub wrote it, to compare with a light read's.
    var updatedAt: String?

    init(from decoder: Decoder) throws {
        content = try ItemDTO.Content(from: decoder)
        let container = try decoder.container(keyedBy: Keys.self)
        let items = try container.decodeIfPresent(Nodes<ProjectItem>.self, forKey: .projectItems)
        projectIds = (items?.items ?? []).compactMap(\.project?.id)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    var remote: RemoteIssue? {
        guard content.__typename == "Issue", let contentId = content.id else { return nil }
        let item = content.item(
            id: Item.idWithoutProject(contentId), projectId: nil, kind: .issue,
            position: Item.positionWithoutProject(updatedAt: content.updatedAt),
            remoteUpdatedAt: updatedAt,
            statusId: nil, priorityId: nil
        )
        return RemoteIssue(item: item, projectIds: projectIds)
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
