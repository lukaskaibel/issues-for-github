import Foundation
@testable import GitIssuesKit

/// A stand-in for GitHub that answers what a pull asks, from one board and one repository a test sets up. Each fake
/// has a token of its own, which tells their requests apart while tests run side by side.
final class FakeGitHub: @unchecked Sendable {
    struct Issue {
        var contentId: String
        var number: Int
        /// The card's id, for an issue on the board.
        var itemId: String?
        var parent: String?
        var title: String?
        var updatedAt = "2026-10-01T10:00:00Z"
        var closed = false
        /// The issues that block it, and how many more GitHub counts but won't show (in repositories you can't see).
        var blockedBy: [String] = []
        var hiddenBlockers = 0
    }

    struct FieldWrite {
        let query: String
        let variables: [String: Any]

        var isClear: Bool { query.contains("clearProjectV2ItemFieldValue(") }
    }

    static let projectId = "P1"
    static let repoId = "R1"
    static let repo = "octo/one"

    private let lock = NSLock()
    private var issues: [Issue] = []
    private var projectUpdatedAt = "2026-10-01T10:00:00Z"
    /// Cards the next light read leaves out, as GitHub does for a moment after adding them.
    private var listedLate: Set<String> = []
    private var events: [[String: Any]] = []
    private var eventClock = Date()
    private var log: [String] = []
    private var fieldWriteLog: [FieldWrite] = []
    private var nextFieldWriteAccepted: (() -> Void)?
    /// The board's saved views and fields besides Status, as GraphQL lists them, for tests of views.
    var views: [[String: Any]] = []
    var extraFields: [[String: Any]] = []
    /// Field values of cards besides Status, by card id.
    var cardValues: [String: [[String: Any]]] = [:]
    /// Which cards a filter matches, as GitHub would say.
    var matching: (String) -> [String] = { _ in [] }
    /// The repository's labels, as GitHub lists them, and whether it refuses to make more, as for someone who can't.
    var labels: [[String: Any]] = []
    var refusesLabels = false
    let token = UUID().uuidString

    init(_ issues: [Issue]) {
        self.issues = issues
        Self.registry.withLock { $0[token] = self }
    }

    deinit {
        Self.registry.withLock { $0[token] = nil }
    }

    var api: GitHubAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FakeGitHubProtocol.self]
        return GitHubAPI(client: GraphQLClient(tokenSource: FixedToken(value: token), session: URLSession(configuration: config)))
    }

    /// What was asked since the last call, in order: "meta", "sweep", "cards", "events", "events: not modified",
    /// "repository", "issues".
    func requests() -> [String] {
        lock.withLock {
            defer { log = [] }
            return log
        }
    }

    /// The actual GraphQL payloads sent to change card fields, retained independently of the request log.
    func fieldWrites() -> [FieldWrite] {
        lock.withLock { fieldWriteLog }
    }

    /// Runs once after a field write reaches GitHub but before its response, outside the fake's lock.
    func afterNextFieldWrite(_ action: @escaping () -> Void) {
        lock.withLock { nextFieldWriteAccepted = action }
    }

    /// A date stored on GitHub, without any of the local outbox's optimistic values.
    func dateValue(itemId: String, fieldId: String) -> String? {
        lock.withLock {
            cardValues[itemId]?.first { ($0["field"] as? [String: Any])?["id"] as? String == fieldId }?["date"] as? String
        }
    }

    /// Something happened to an issue: listed among the repository's events, and nothing else.
    func event(_ name: String, on contentId: String) {
        lock.withLock {
            eventClock.addTimeInterval(1)
            events.insert([
                "id": 1000 + events.count, "event": name, "created_at": ISO8601DateFormatter().string(from: eventClock),
                "issue": ["node_id": contentId],
            ], at: 0)
        }
    }

    /// Makes one issue a sub-issue of another, as GitHub does: the two issues, their cards and the board keep their
    /// updatedAt; only the events say so.
    func setParent(of child: String, to parent: String) {
        lock.withLock {
            guard let index = issues.firstIndex(where: { $0.contentId == child }) else { return }
            issues[index].parent = parent
        }
        event("parent_issue_added", on: child)
        event("sub_issue_added", on: parent)
    }

    /// Adds an issue that is on no board, such as a sub-issue of a sub-issue.
    func addIssue(_ issue: Issue) {
        lock.withLock { issues.append(issue) }
    }

    /// Closes an issue or opens it again.
    func setClosed(_ contentId: String, _ closed: Bool) {
        lock.withLock {
            guard let index = issues.firstIndex(where: { $0.contentId == contentId }) else { return }
            issues[index].closed = closed
        }
    }

    /// Marks one issue as blocked by another, as GitHub does: only the events say so, and the issue's own count.
    func block(_ contentId: String, by blocker: String) {
        lock.withLock {
            guard let index = issues.firstIndex(where: { $0.contentId == contentId }) else { return }
            issues[index].blockedBy.append(blocker)
        }
        event("blocked_by_added", on: contentId)
        event("blocking_added", on: blocker)
    }

    /// Takes a blocker away.
    func unblock(_ contentId: String, from blocker: String) {
        lock.withLock {
            guard let index = issues.firstIndex(where: { $0.contentId == contentId }) else { return }
            issues[index].blockedBy.removeAll { $0 == blocker }
        }
        event("blocked_by_removed", on: contentId)
        event("blocking_removed", on: blocker)
    }

    /// Renames an issue the way GitHub does at times: the issue changes, but neither its card nor the board says so.
    func rename(_ contentId: String, to title: String) {
        lock.withLock {
            guard let index = issues.firstIndex(where: { $0.contentId == contentId }) else { return }
            issues[index].title = title
        }
        event("renamed", on: contentId)
    }

    /// Puts a new card on the board. With `listedLate`, the next light read doesn't list it yet, though the board
    /// already says it changed.
    func addCard(_ issue: Issue, listedLate: Bool = false) {
        lock.withLock {
            var issue = issue
            issue.updatedAt = "2026-10-01T10:05:00Z"
            issues.append(issue)
            projectUpdatedAt = issue.updatedAt
            if listedLate, let itemId = issue.itemId { self.listedLate.insert(itemId) }
        }
    }

    // MARK: Answers

    fileprivate func answer(_ request: URLRequest) -> (status: Int, headers: [String: String], body: Data) {
        var accepted: (() -> Void)?
        let response: (status: Int, headers: [String: String], body: Data) = lock.withLock {
            if request.url?.path == "/repos/\(Self.repo)/issues/events" {
                let etag = "W/\"\(events.count)\""
                if request.value(forHTTPHeaderField: "If-None-Match") == etag {
                    log.append("events: not modified")
                    return (304, [:], Data())
                }
                log.append("events")
                return (200, ["ETag": etag], try! JSONSerialization.data(withJSONObject: events))
            }
            let payload = (try? JSONSerialization.jsonObject(with: request.bodyData)) as? [String: Any] ?? [:]
            if request.url?.path == "/repos/\(Self.repo)/labels", request.httpMethod == "POST" {
                return makeLabel(payload)
            }
            let query = payload["query"] as? String ?? ""
            let variables = payload["variables"] as? [String: Any] ?? [:]
            let data: Any
            if query.contains("label(name: $name)") {
                let name = variables["name"] as? String ?? ""
                log.append("label \(name)")
                data = ["node": ["label": label(named: name).map { $0 as Any } ?? NSNull()]]
            } else if query.contains("addLabelsToLabelable(") {
                log.append("add labels \((variables["ids"] as? [String] ?? []).joined(separator: ", "))")
                data = ["addLabelsToLabelable": ["clientMutationId": NSNull()]]
            } else if query.contains("updateProjectV2ItemFieldValue(") || query.contains("clearProjectV2ItemFieldValue(") {
                fieldWriteLog.append(FieldWrite(query: query, variables: variables))
                guard variables["p"] as? String == Self.projectId,
                      let itemId = variables["i"] as? String,
                      let index = issues.firstIndex(where: { $0.itemId == itemId }),
                      let fieldId = variables["f"] as? String else {
                    return (500, [:], Data("Unknown project, card or field in field write".utf8))
                }
                let clear = query.contains("clearProjectV2ItemFieldValue(")
                var value: [String: Any] = ["field": ["id": fieldId]]
                if clear {
                    log.append("clear field \(fieldId)")
                } else if query.contains("date: $d"), let date = variables["d"] as? String {
                    value["date"] = date
                    log.append("set field \(fieldId)")
                } else if query.contains("iterationId: $v"), let iteration = variables["v"] as? String {
                    value["iterationId"] = iteration
                    log.append("set field \(fieldId)")
                } else if query.contains("singleSelectOptionId: $o"), let option = variables["o"] as? String {
                    value["optionId"] = option
                    log.append("set field \(fieldId)")
                } else {
                    return (500, [:], Data("Unsupported project field write: \(query)".utf8))
                }
                cardValues[itemId, default: []].removeAll { ($0["field"] as? [String: Any])?["id"] as? String == fieldId }
                if !clear { cardValues[itemId, default: []].append(value) }
                issues[index].updatedAt = "2026-10-02T10:00:00Z"
                projectUpdatedAt = issues[index].updatedAt
                accepted = nextFieldWriteAccepted
                nextFieldWriteAccepted = nil
                data = [clear ? "clearProjectV2ItemFieldValue" : "updateProjectV2ItemFieldValue": ["clientMutationId": NSNull()]]
            } else if query.contains("items { totalCount }") {
                log.append("meta")
                data = ["node": meta()]
            } else if query.contains("query: $q") {
                let filter = variables["q"] as? String ?? ""
                log.append("matching: \(filter)")
                data = ["node": ["items": [
                    "pageInfo": ["hasNextPage": false, "endCursor": NSNull()],
                    "nodes": matching(filter).map { ["id": $0] },
                ]]]
            } else if query.contains("updateProjectV2View(") {
                let input = variables["input"] as? [String: Any] ?? [:]
                let id = input["viewId"] as? String ?? ""
                log.append("update view \(id)")
                guard let index = views.firstIndex(where: { $0["id"] as? String == id }) else { return (200, [:], Data("{\"data\":null,\"errors\":[{\"message\":\"Not found\",\"type\":\"NOT_FOUND\"}]}".utf8)) }
                if let name = input["name"] { views[index]["name"] = name }
                if let filter = input["filter"] { views[index]["filter"] = filter }
                if let layout = input["layout"] { views[index]["layout"] = layout }
                views[index]["updatedAt"] = "2026-10-02T10:00:00Z"
                data = ["updateProjectV2View": ["projectV2View": views[index]]]
            } else if query.contains("deleteProjectV2View(") {
                let id = variables["id"] as? String ?? ""
                log.append("delete view \(id)")
                views.removeAll { $0["id"] as? String == id }
                data = ["deleteProjectV2View": ["clientMutationId": NSNull()]]
            } else if query.contains("orderBy: {field: POSITION") {
                log.append("sweep")
                let listed = onBoard.filter { !listedLate.contains($0.itemId!) }
                listedLate = []
                data = ["node": ["items": [
                    "pageInfo": ["hasNextPage": false, "endCursor": NSNull()],
                    "nodes": listed.map { ["id": $0.itemId!, "updatedAt": $0.updatedAt, "content": ["viewerCanDelete": true]] },
                ]]]
            } else if query.contains("... on ProjectV2Item") {
                log.append("cards")
                let ids = variables["ids"] as? [String] ?? []
                data = ["nodes": ids.map { id -> Any in issues.first { $0.itemId == id }.map(card) ?? NSNull() }]
            } else if query.contains("... on Repository") {
                log.append("repository")
                let states = variables["states"] as? [String]
                data = ["node": ["issues": [
                    "pageInfo": ["hasNextPage": false, "endCursor": NSNull()],
                    "nodes": (states == nil || states!.contains("OPEN") ? issues : []).map {
                        ["id": $0.contentId, "updatedAt": $0.updatedAt, "state": "OPEN", "closedAt": NSNull(),
                         "repository": ["id": Self.repoId], "viewerCanDelete": true]
                    },
                ]]]
            } else if query.contains("subIssues(first: 100) { nodes { ...SubIssueFields } }"), !query.contains("comments(") {
                let id = variables["id"] as? String ?? ""
                log.append("sub-issues \(id)")
                data = ["node": ["subIssues": ["nodes": issues.filter { $0.parent == id }.map(subIssue)]]]
            } else if query.contains("... on Issue { ...IssueFields }") {
                log.append("issues")
                let ids = variables["ids"] as? [String] ?? []
                data = ["nodes": ids.map { id -> Any in issues.first { $0.contentId == id }.map(issueNode) ?? NSNull() }]
            } else if query.contains("subIssues(first: 100)") {
                let id = variables["id"] as? String ?? ""
                log.append("detail")
                data = ["node": issues.first { $0.contentId == id }.map { detail($0) as Any } ?? NSNull()]
            } else if query.contains("blockedBy(first: 20)") {
                log.append("blockers")
                let ids = variables["ids"] as? [String] ?? []
                data = ["nodes": ids.map { id -> Any in
                    issues.first { $0.contentId == id }.map { ["id": $0.contentId, "blockedBy": ["nodes": blockers(of: $0)]] as Any } ?? NSNull()
                }]
            } else {
                return (500, [:], Data("Not part of the fake: \(query)".utf8))
            }
            return (200, [:], try! JSONSerialization.data(withJSONObject: ["data": data]))
        }
        accepted?()
        return response
    }

    private var onBoard: [Issue] { issues.filter { $0.itemId != nil } }

    private func label(named name: String) -> [String: Any]? {
        labels.first { ($0["name"] as? String)?.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// GitHub's REST answer to making a label: the label, or why not.
    private func makeLabel(_ payload: [String: Any]) -> (status: Int, headers: [String: String], body: Data) {
        let name = payload["name"] as? String ?? ""
        log.append("create label \(name)")
        if refusesLabels { return (403, [:], Data("{\"message\":\"Must have admin rights to Repository.\"}".utf8)) }
        if label(named: name) != nil { return (422, [:], Data("{\"message\":\"Validation Failed\"}".utf8)) }
        let made: [String: Any] = ["id": "LA_\(labels.count + 1)", "name": name, "color": payload["color"] as? String ?? "ededed"]
        labels.append(made)
        let body: [String: Any] = ["node_id": made["id"]!, "name": name, "color": made["color"]!]
        return (201, [:], try! JSONSerialization.data(withJSONObject: body))
    }

    private func meta() -> [String: Any] {
        [
            "id": Self.projectId, "title": "Board", "updatedAt": projectUpdatedAt, "closed": false, "viewerCanUpdate": true,
            "items": ["totalCount": onBoard.count],
            "fields": ["nodes": [[
                "__typename": "ProjectV2SingleSelectField", "id": "F-status", "name": "Status", "dataType": "SINGLE_SELECT",
                "databaseId": 1,
                "options": [["id": "todo", "name": "Todo", "color": "GRAY", "description": ""]],
            ]] + extraFields],
            "repositories": ["nodes": [["id": Self.repoId, "nameWithOwner": Self.repo]]],
            "views": ["nodes": views],
        ]
    }

    private func content(_ issue: Issue) -> [String: Any] {
        let parent = issue.parent.flatMap { id in issues.first { $0.contentId == id } }
        return [
            "__typename": "Issue", "id": issue.contentId, "number": issue.number, "title": issue.title ?? "Issue \(issue.number)", "body": "",
            "state": "OPEN", "stateReason": NSNull(), "url": "https://github.com/\(Self.repo)/issues/\(issue.number)",
            "createdAt": "2026-10-01T09:00:00Z", "updatedAt": issue.updatedAt, "closedAt": NSNull(),
            "author": ["login": "octo"], "repository": ["id": Self.repoId, "nameWithOwner": Self.repo],
            "assignees": ["nodes": []], "labels": ["nodes": []],
            "parent": parent.map { ["id": $0.contentId, "number": $0.number, "title": "Issue \($0.number)"] as [String: Any] } ?? NSNull(),
            "viewerCanDelete": true,
            "subIssuesSummary": ["total": issues.filter { $0.parent == issue.contentId }.count, "completed": 0],
            "issueDependenciesSummary": [
                "blockedBy": issue.blockedBy.count + issue.hiddenBlockers,
                "blocking": issues.filter { $0.blockedBy.contains(issue.contentId) }.count,
            ],
            "comments": ["totalCount": 0],
        ]
    }

    private func subIssue(_ issue: Issue) -> [String: Any] {
        let children = issues.filter { $0.parent == issue.contentId }
        return [
            "id": issue.contentId, "number": issue.number, "title": issue.title ?? "Issue \(issue.number)",
            "state": issue.closed ? "CLOSED" : "OPEN", "stateReason": issue.closed ? "COMPLETED" : NSNull(),
            "url": "https://github.com/\(Self.repo)/issues/\(issue.number)",
            "repository": ["id": Self.repoId, "nameWithOwner": Self.repo], "assignees": ["nodes": []], "milestone": NSNull(),
            "subIssuesSummary": ["total": children.count, "completed": children.filter(\.closed).count],
            "blockedBy": ["nodes": blockers(of: issue)],
        ]
    }

    private func card(_ issue: Issue) -> [String: Any] {
        [
            "id": issue.itemId!, "updatedAt": issue.updatedAt, "type": "ISSUE",
            "fieldValues": ["nodes": [["optionId": "todo", "field": ["id": "F-status"]]] + (cardValues[issue.itemId!] ?? [])],
            "content": content(issue),
        ]
    }

    /// Another issue as an issue's relations list it.
    private func link(_ issue: Issue) -> [String: Any] {
        [
            "id": issue.contentId, "number": issue.number, "title": issue.title ?? "Issue \(issue.number)", "state": "OPEN",
            "stateReason": NSNull(), "url": "https://github.com/\(Self.repo)/issues/\(issue.number)",
            "repository": ["id": Self.repoId, "nameWithOwner": Self.repo],
        ]
    }

    private func blockers(of issue: Issue) -> [[String: Any]] {
        issue.blockedBy.compactMap { id in issues.first { $0.contentId == id }.map(link) }
    }

    /// An issue as its page reads it: no comments, its sub-issues with what blocks them, and its own relations.
    private func detail(_ issue: Issue) -> [String: Any] {
        [
            "title": issue.title ?? "Issue \(issue.number)", "body": "", "comments": ["nodes": []],
            "subIssues": ["nodes": issues.filter { $0.parent == issue.contentId }.map(subIssue)],
            "blockedBy": ["nodes": blockers(of: issue)],
            "blocking": ["nodes": issues.filter { $0.blockedBy.contains(issue.contentId) }.map(link)],
        ]
    }

    private func issueNode(_ issue: Issue) -> [String: Any] {
        var node = content(issue)
        node["projectItems"] = ["nodes": issue.itemId == nil ? [] : [["project": ["id": Self.projectId]]]]
        return node
    }

    fileprivate static let registry = Registry()

    final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var fakes: [String: FakeGitHub] = [:]
        func withLock<T>(_ body: (inout [String: FakeGitHub]) -> T) -> T {
            lock.withLock { body(&fakes) }
        }
    }
}

private struct FixedToken: TokenSource {
    var value: String
    func token() async throws -> String { value }
}

final class FakeGitHubProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let token = request.value(forHTTPHeaderField: "Authorization")?.replacingOccurrences(of: "bearer ", with: "") ?? ""
        let (status, headers, body) = FakeGitHub.registry.withLock { $0[token] }?.answer(request) ?? (401, [:], Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension URLRequest {
    /// A URLProtocol gets the body as a stream.
    var bodyData: Data {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
