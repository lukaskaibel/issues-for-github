import Foundation
import GRDB

// Milestones and epics. A milestone belongs to a repository, and its issues name it; an epic is an issue with the
// label (or issue type) that says so.

extension Mutation {
    /// Gives an issue or pull request a milestone, or takes it away.
    public struct SetMilestone: Codable, Sendable, Equatable {
        public var contentId: String
        public var isPullRequest: Bool
        /// The new milestone; nil takes the issue out of the one it has.
        public var milestoneId: String?
        public var milestoneTitle: String?
        /// The milestone before the first of the still-unsent changes to it, which is the one GitHub knows.
        public var base: String?
    }

    /// Makes a milestone in a repository. Changes that put issues into it wait until GitHub has made it.
    public struct CreateMilestone: Codable, Sendable, Equatable {
        /// A local id until GitHub has made it, then GitHub's.
        public var milestoneId: String
        public var repoId: String
        /// "owner/name".
        public var repo: String
        public var title: String
        public var dueOn: String?
        public var descr: String
        /// Filled in once GitHub has made it, so a retry never makes it twice.
        public var createdId: String?
        public var createdNumber: Int?
        public var createdUrl: String?
    }

    /// Changes a milestone's title, description or due date, or closes or reopens it.
    public struct UpdateMilestone: Codable, Sendable, Equatable {
        public var milestoneId: String
        public var change: GitHubAPI.MilestoneChange
    }

    /// Makes an issue an epic, or an ordinary issue again.
    public struct SetEpic: Codable, Sendable, Equatable {
        public var contentId: String
        public var repoId: String
        /// "owner/name", where the label is made if the repository has none.
        public var repo: String
        public var isEpic: Bool
        /// The label shown until GitHub has the real one: the repository's own when it is known.
        public var label: LabelRef
    }
}

extension Mutation.SetMilestone {
    func apply(_ db: Database) throws {
        try db.execute(
            sql: "UPDATE item SET milestoneId = ?, milestoneTitle = ?, dirty = 1 WHERE contentId = ?",
            arguments: [milestoneId, milestoneTitle, contentId]
        )
        try db.execute(
            sql: "UPDATE subIssue SET milestoneId = ?, milestoneTitle = ? WHERE id = ?",
            arguments: [milestoneId, milestoneTitle, contentId]
        )
    }
}

extension Mutation.CreateMilestone {
    func apply(_ db: Database) throws {
        if try !Milestone.exists(db, key: milestoneId) {
            try Milestone(
                id: milestoneId, repoId: repoId, repo: repo, number: createdNumber ?? 0, title: title, descr: descr,
                dueOn: dueOn, state: "OPEN", closedAt: nil, url: createdUrl
            ).insert(db)
        } else if let createdNumber {
            try db.execute(
                sql: "UPDATE milestone SET number = ?, url = COALESCE(?, url) WHERE id = ?",
                arguments: [createdNumber, createdUrl, milestoneId]
            )
        }
    }
}

extension Mutation.UpdateMilestone {
    func apply(_ db: Database) throws {
        if let title = change.title {
            try db.execute(sql: "UPDATE milestone SET title = ? WHERE id = ?", arguments: [title, milestoneId])
            try db.execute(sql: "UPDATE item SET milestoneTitle = ? WHERE milestoneId = ?", arguments: [title, milestoneId])
            try db.execute(sql: "UPDATE subIssue SET milestoneTitle = ? WHERE milestoneId = ?", arguments: [title, milestoneId])
        }
        if let descr = change.descr {
            try db.execute(sql: "UPDATE milestone SET descr = ? WHERE id = ?", arguments: [descr, milestoneId])
        }
        if let dueOn = change.dueOn {
            try db.execute(sql: "UPDATE milestone SET dueOn = ? WHERE id = ?", arguments: [dueOn.isEmpty ? nil : dueOn, milestoneId])
        }
        if let state = change.state {
            try db.execute(
                sql: "UPDATE milestone SET state = ?, closedAt = CASE WHEN ? = 'CLOSED' THEN COALESCE(closedAt, ?) ELSE NULL END WHERE id = ?",
                arguments: [state, state, Date(), milestoneId]
            )
        }
    }
}

extension Mutation.SetEpic {
    func apply(_ db: Database) throws {
        for var item in try Item.filter(Column("contentId") == contentId).fetchAll(db) {
            if isEpic {
                if !item.isEpic {
                    item.labels.append(label)
                    item.labels.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                }
            } else {
                item.labels.removeAll { Item.isEpicLabel($0.name) }
                if item.issueType.map(Item.isEpicType) == true { item.issueType = nil }
            }
            item.dirty = true
            try item.update(db)
        }
    }
}
