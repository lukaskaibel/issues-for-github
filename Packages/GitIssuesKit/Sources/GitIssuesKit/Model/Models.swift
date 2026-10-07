import Foundation
import GRDB

// MARK: - Value types embedded as JSON

public struct Person: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var login: String
    public var name: String?
    public var avatarUrl: String?

    public init(id: String, login: String, name: String? = nil, avatarUrl: String? = nil) {
        self.id = id
        self.login = login
        self.name = name
        self.avatarUrl = avatarUrl
    }
}

public struct LabelRef: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// Hex without the leading '#', as GitHub returns it.
    public var color: String

    public init(id: String, name: String, color: String) {
        self.id = id
        self.name = name
        self.color = color
    }
}

public enum ItemKind: String, Codable, Sendable {
    case issue = "ISSUE"
    case pullRequest = "PULL_REQUEST"
    case draft = "DRAFT_ISSUE"
    case redacted = "REDACTED"
}

public enum OptionKind: String, Codable, Sendable {
    case status
    case priority
}

// MARK: - Records

public struct Project: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    public static let databaseTableName = "project"

    public var id: String
    public var ownerLogin: String
    public var ownerIsOrg: Bool
    public var number: Int
    public var title: String
    public var url: String
    public var closed: Bool
    public var viewerCanUpdate: Bool
    /// `ProjectV2.updatedAt` as last seen on GitHub. Compared as a string to detect remote changes.
    public var remoteUpdatedAt: String?
    public var itemsTotal: Int?
    public var statusFieldId: String?
    public var priorityFieldId: String?
    public var lastSyncedAt: Date?
}

/// One option of a project's Status or Priority single-select field.
public struct FieldOption: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    public static let databaseTableName = "fieldOption"

    public var id: String
    public var fieldId: String
    public var projectId: String
    public var kind: OptionKind
    public var name: String
    /// GitHub's colour enum: GRAY, BLUE, GREEN, YELLOW, ORANGE, RED, PINK, PURPLE.
    public var color: String
    public var descr: String
    public var position: Int
}

/// A card: one item of a project together with the issue, pull request or draft behind it. An issue that is on
/// none of your boards is an item too, without a project, so lists, actions and the issue view treat it alike.
public struct Item: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    public static let databaseTableName = "item"

    public var id: String
    /// Nil for an issue that is on none of your boards.
    public var projectId: String?
    public var kind: ItemKind
    public var position: Double
    /// `ProjectV2Item.updatedAt` as last hydrated. Compared as a string during sweeps.
    public var remoteUpdatedAt: String?
    /// Set when a local change was applied; forces a re-hydrate on the next pull.
    public var dirty: Bool = false

    public var statusId: String?
    public var priorityId: String?

    public var contentId: String?
    public var number: Int?
    public var title: String
    public var body: String
    public var state: String
    public var stateReason: String?
    public var url: String?
    public var repoId: String?
    public var repo: String?
    public var authorLogin: String?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var closedAt: Date?
    public var parentId: String?
    public var parentNumber: Int?
    public var parentTitle: String?
    public var subTotal: Int = 0
    public var subCompleted: Int = 0
    public var commentCount: Int = 0
    public var assignees: [Person] = []
    public var labels: [LabelRef] = []
    /// Whether GitHub lets you delete this issue (it takes admin rights in the repository).
    public var viewerCanDelete: Bool = false

    public var isLocalOnly: Bool { id.hasPrefix(LocalID.prefix) }
    public var isOnBoard: Bool { projectId != nil }
    public var isClosed: Bool { state != "OPEN" }

    /// The id of an issue that is on none of your boards. Project items have ids of their own on GitHub; this
    /// one is made from the issue's, with a prefix so it never collides with the issue id itself.
    public static func idWithoutProject(_ contentId: String) -> String { withoutProjectPrefix + contentId }
    public static let withoutProjectPrefix = "issue:"

    /// Issues on no board have no order on GitHub; the most recently updated comes first, ahead of board cards.
    public static func positionWithoutProject(updatedAt: Date?) -> Double {
        -(updatedAt ?? Date()).timeIntervalSince1970
    }
    /// Title and description can be edited here: issues. Pull requests and issues seen only in the Inbox (which
    /// the app doesn't keep) are read-only.
    public var isEditableContent: Bool { kind == .issue && !isDetached }
    public var repoShortName: String? { repo?.split(separator: "/").last.map(String.init) }

    /// The branch name GitHub suggests for the issue: its number and title, such as "14-sign-in-with-device-flow".
    public var branchName: String? {
        guard let number else { return nil }
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        var slug = ""
        for character in folded {
            if character.isASCII, character.isLetter || character.isNumber {
                slug.append(character)
            } else if !slug.isEmpty, !slug.hasSuffix("-") {
                slug.append("-")
            }
        }
        slug = String(slug.prefix(60))
        while slug.hasSuffix("-") { slug.removeLast() }
        return slug.isEmpty ? "\(number)" : "\(number)-\(slug)"
    }

    /// "#12" for issues and pull requests, "Draft" otherwise.
    public var displayNumber: String {
        if let number { return "#\(number)" }
        return kind == .draft ? "Draft" : "New"
    }
}

public struct Comment: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    public static let databaseTableName = "comment"

    public var id: String
    public var issueId: String
    public var authorLogin: String?
    public var authorAvatarUrl: String?
    public var body: String
    public var createdAt: Date
    public var isLocalOnly: Bool { id.hasPrefix(LocalID.prefix) }
}

/// A sub-issue as shown in the parent's detail view. It may or may not also be an item of the project.
public struct SubIssue: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    public static let databaseTableName = "subIssue"

    public var id: String
    public var parentId: String
    public var number: Int
    public var title: String
    public var state: String
    public var stateReason: String?
    public var repo: String?
    public var url: String?
    public var position: Int
    public var assignees: [Person] = []

    public var isClosed: Bool { state != "OPEN" }
}

public struct RepoRef: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    public static let databaseTableName = "repo"

    public var id: String
    public var nameWithOwner: String
    public var projectId: String
    public var labels: [LabelRef] = []
    public var assignableUsers: [Person] = []
    public var metaLoadedAt: Date?

    public var shortName: String { nameWithOwner.split(separator: "/").last.map(String.init) ?? nameWithOwner }
    public var url: URL? { URL(string: "https://github.com/\(nameWithOwner)") }
}

public struct Viewer: Codable, Hashable, Sendable {
    public var id: String
    public var login: String
    public var name: String?
    public var avatarUrl: String?

    public var person: Person { Person(id: id, login: login, name: name, avatarUrl: avatarUrl) }
}

public enum LocalID {
    public static let prefix = "local-"
    public static func make() -> String { prefix + UUID().uuidString.lowercased() }
}
