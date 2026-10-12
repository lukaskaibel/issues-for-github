import Foundation
import GRDB

/// Milestones of the repositories your boards use, and sending what makes an issue an epic.
extension SyncEngine {
    /// The repositories of your open boards: those of the board on screen every minute, the rest every ten.
    func pullMilestones() async throws {
        guard !isDemo else { return }
        let rows = try await db.reader.read { db in
            try Row.fetchAll(db, sql: "SELECT DISTINCT r.id AS repoId, r.projectId AS projectId FROM repo r JOIN project p ON p.id = r.projectId WHERE p.closed = 0")
                .map { (repoId: $0["repoId"] as String, projectId: $0["projectId"] as String) }
        }
        let active = activeProject
        var due: [(repoId: String, onScreen: Bool)] = []
        var seen = Set<String>()
        for (repoId, projectId) in rows {
            let onScreen = projectId == active
            if seen.insert(repoId).inserted {
                due.append((repoId, onScreen))
            } else if onScreen, let index = due.firstIndex(where: { $0.repoId == repoId }) {
                due[index].onScreen = true
            }
        }
        let now = Date()
        for (repoId, onScreen) in due {
            let interval: TimeInterval = onScreen ? 60 : 600
            if let last = lastMilestonePull[repoId], now.timeIntervalSince(last) < interval { continue }
            do {
                try await pullMilestones(repoId: repoId)
            } catch let error as APIError where !error.isTransient {
                // A repository we cannot read should not stop everything else from syncing.
                lastMilestonePull[repoId] = now
            }
        }
    }

    /// Reads a repository's milestones and writes them, only when something changed.
    public func pullMilestones(repoId: String) async throws {
        guard !isDemo else { return }
        let fetched = try await api.milestones(repoId: repoId)
        try await db.writer.write { db in
            try Self.writeMilestones(db, fetched, repoId: repoId)
        }
        lastMilestonePull[repoId] = Date()
    }

    /// Replaces a repository's milestones with what GitHub has. Milestones still being made here stay.
    static func writeMilestones(_ db: Database, _ fetched: [Milestone], repoId: String) throws {
        let existing = try Milestone
            .filter(Column("repoId") == repoId && !Column("id").like(LocalID.prefix + "%"))
            .order(Column("id"))
            .fetchAll(db)
        guard existing != fetched.sorted(by: { $0.id < $1.id }) else { return }
        try Milestone
            .filter(Column("repoId") == repoId && !Column("id").like(LocalID.prefix + "%"))
            .deleteAll(db)
        for milestone in fetched { try milestone.save(db) }
        // An issue's milestone may have been renamed.
        try db.execute(sql: """
            UPDATE item SET milestoneTitle = (SELECT title FROM milestone m WHERE m.id = item.milestoneId)
            WHERE milestoneId IN (SELECT id FROM milestone WHERE repoId = ?)
            """, arguments: [repoId])
        try Outbox.rebase(db)
    }

    /// Makes an issue an epic with its organisation's "Epic" type where there is one, else with the label "epic",
    /// made in the repository if it has none; or takes both away.
    func sendEpic(_ m: Mutation.SetEpic) async throws {
        if m.isEpic {
            if let type = try await api.epicIssueType(repoId: m.repoId) {
                try await api.setIssueType(contentId: m.contentId, typeId: type)
            } else {
                let label = try await api.epicLabel(repoId: m.repoId, repo: m.repo)
                try await api.editLabels(contentId: m.contentId, add: [label.id], remove: [])
            }
        } else {
            let marks = try await api.epicMarks(contentId: m.contentId)
            if !marks.labelIds.isEmpty {
                try await api.editLabels(contentId: m.contentId, add: [], remove: marks.labelIds)
            }
            if marks.typeIsEpic {
                try await api.setIssueType(contentId: m.contentId, typeId: nil)
            }
        }
    }
}

extension GitHubAPI {
    /// What makes an issue an epic on GitHub: its labels that say so, and whether its type does.
    func epicMarks(contentId: String) async throws -> (labelIds: [String], typeIsEpic: Bool) {
        struct Response: Decodable {
            struct Node: Decodable {
                var labels: Nodes<LabelDTO>?
                var issueType: IssueTypeDTO?
            }
            var node: Node?
        }
        let query = """
        query($id: ID!) { node(id: $id) { ... on Issue { labels(first: 50) { nodes { id name color } } issueType { id name } } } }
        """
        let response: Response = try await client.run(query, variables: ["id": contentId])
        let labels = (response.node?.labels?.items ?? []).filter { Item.isEpicLabel($0.name) }.map(\.id)
        return (labels, response.node?.issueType.map { Item.isEpicType($0.name) } ?? false)
    }
}
