import Foundation

/// A project's saved views and its own fields. GitHub's GraphQL API reads views, changes their name, layout, filter
/// and fields, and deletes them; a new view, with its grouping, columns and order, is made through the REST API.
extension GitHubAPI {
    /// The project's views, in the order of their tabs.
    public func views(projectId: String) async throws -> [ProjectView] {
        struct Response: Decodable {
            struct Node: Decodable { var views: Nodes<ViewDTO>? }
            var node: Node?
        }
        let query = """
        query($id: ID!) {
          node(id: $id) { ... on ProjectV2 {
            views(first: 50, orderBy: {field: POSITION, direction: ASC}) { nodes { ...ViewFields } }
          } }
        }
        \(GQL.viewFields)
        """
        let response: Response = try await client.run(query, variables: ["id": projectId], allowPartial: true)
        return (response.node?.views?.items ?? []).enumerated().compactMap { $1.view(projectId: projectId, position: $0) }
    }

    /// The items of a project a filter matches, as GitHub reads the filter: for filters with parts the app can't
    /// evaluate itself, such as text to search for.
    public func matchingItemIds(projectId: String, filter: String) async throws -> [String] {
        struct Response: Decodable {
            struct Node: Decodable {
                struct Items: Decodable {
                    struct Entry: Decodable { var id: String }
                    var pageInfo: PageInfo
                    var nodes: [Entry?]
                }
                var items: Items?
            }
            var node: Node?
        }
        let query = """
        query($id: ID!, $q: String!, $after: String) {
          node(id: $id) { ... on ProjectV2 {
            items(first: 100, after: $after, query: $q) { pageInfo { hasNextPage endCursor } nodes { id } }
          } }
        }
        """
        var ids: [String] = []
        var cursor: String?
        repeat {
            let response: Response = try await client.run(query, variables: ["id": projectId, "q": filter, "after": cursor], allowPartial: true)
            guard let items = response.node?.items else { break }
            ids += items.nodes.compactMap { $0?.id }
            cursor = items.pageInfo.hasNextPage ? items.pageInfo.endCursor : nil
        } while cursor != nil && ids.count < 5000
        return ids
    }

    /// Puts an item into an iteration, or takes it out of the one it is in with nil.
    public func setIterationValue(projectId: String, itemId: String, fieldId: String, iterationId: String?) async throws {
        guard let iterationId else {
            try await setFieldValue(projectId: projectId, itemId: itemId, fieldId: fieldId, optionId: nil)
            return
        }
        struct Ack: Decodable {}
        let query = """
        mutation($p: ID!, $i: ID!, $f: ID!, $v: String!) {
          updateProjectV2ItemFieldValue(input: {projectId: $p, itemId: $i, fieldId: $f, value: {iterationId: $v}}) { clientMutationId }
        }
        """
        let _: Ack = try await client.run(query, variables: ["p": projectId, "i": itemId, "f": fieldId, "v": iterationId])
    }

    /// What to change about a view; nil leaves a part as it is. Grouping, columns and order can't be changed once a
    /// view exists: GitHub's API takes them only when it is created.
    public struct ViewChange: Sendable, Equatable {
        public var name: String?
        public var layout: ViewLayout?
        public var filter: String?
        public var visibleFieldIds: [String]?

        public init(name: String? = nil, layout: ViewLayout? = nil, filter: String? = nil, visibleFieldIds: [String]? = nil) {
            self.name = name
            self.layout = layout
            self.filter = filter
            self.visibleFieldIds = visibleFieldIds
        }

        public var isEmpty: Bool { name == nil && layout == nil && filter == nil && visibleFieldIds == nil }
    }

    /// Changes a view and returns it as GitHub has it now.
    public func updateView(id: String, projectId: String, change: ViewChange) async throws -> ProjectView? {
        struct Response: Decodable {
            struct Payload: Decodable { var projectV2View: ViewDTO? }
            var updateProjectV2View: Payload?
        }
        var input: [String: Any] = ["viewId": id]
        if let name = change.name { input["name"] = name }
        if let layout = change.layout { input["layout"] = layout.rawValue }
        if let filter = change.filter { input["filter"] = filter }
        if let fields = change.visibleFieldIds { input["configuration"] = ["visibleFieldIds": fields] }
        let query = """
        mutation($input: UpdateProjectV2ViewInput!) {
          updateProjectV2View(input: $input) { projectV2View { ...ViewFields } }
        }
        \(GQL.viewFields)
        """
        let response: Response = try await client.run(query, variables: ["input": input])
        return response.updateProjectV2View?.projectV2View?.view(projectId: projectId, position: 0)
    }

    public func deleteView(id: String) async throws {
        struct Ack: Decodable {}
        let query = """
        mutation($id: ID!) { deleteProjectV2View(input: {viewId: $id}) { clientMutationId } }
        """
        let _: Ack = try await client.run(query, variables: ["id": id])
    }

    /// A new view as it should be made: what GitHub's REST API takes. Fields are given by their `databaseId`.
    public struct NewView: Sendable, Equatable {
        public var name: String
        public var layout: ViewLayout
        public var filter: String
        public var visibleFields: [Int]
        public var groupBy: Int?
        public var columnsBy: Int?
        public var sortBy: [(field: Int, descending: Bool)]

        public init(
            name: String, layout: ViewLayout, filter: String, visibleFields: [Int] = [], groupBy: Int? = nil,
            columnsBy: Int? = nil, sortBy: [(field: Int, descending: Bool)] = []
        ) {
            self.name = name
            self.layout = layout
            self.filter = filter
            self.visibleFields = visibleFields
            self.groupBy = groupBy
            self.columnsBy = columnsBy
            self.sortBy = sortBy
        }

        public static func == (a: NewView, b: NewView) -> Bool {
            a.name == b.name && a.layout == b.layout && a.filter == b.filter && a.visibleFields == b.visibleFields
                && a.groupBy == b.groupBy && a.columnsBy == b.columnsBy
                && a.sortBy.map(\.field) == b.sortBy.map(\.field) && a.sortBy.map(\.descending) == b.sortBy.map(\.descending)
        }

        /// The REST API's body.
        var body: [String: Any] {
            let layoutName = switch layout {
            case .board: "board"
            case .table: "table"
            case .roadmap: "roadmap"
            }
            var body: [String: Any] = ["name": name, "layout": layoutName]
            if !filter.isEmpty { body["filter"] = filter }
            if !visibleFields.isEmpty, layout != .roadmap { body["visible_fields"] = visibleFields }
            if let groupBy { body["group_by"] = [groupBy] }
            if let columnsBy, layout == .board { body["vertical_group_by"] = [columnsBy] }
            if !sortBy.isEmpty { body["sort_by"] = sortBy.map { [$0.field, $0.descending ? "desc" : "asc"] as [Any] } }
            return body
        }
    }

    /// Creates a view in a project and returns its number. Projects are found by their owner's login, a person's as
    /// much as an organisation's (GitHub's documentation asks for a person's account number there, which it answers
    /// with "Not Found").
    public func createView(ownerLogin: String, ownerIsOrg: Bool, projectNumber: Int, view: NewView) async throws -> Int {
        struct Created: Decodable { var number: Int }
        let owner = ownerIsOrg ? "orgs/\(ownerLogin)" : "users/\(ownerLogin)"
        let (data, _) = try await client.rest("POST", "\(owner)/projectsV2/\(projectNumber)/views", json: view.body)
        return try GraphQLClient.decoder.decode(Created.self, from: data).number
    }
}
