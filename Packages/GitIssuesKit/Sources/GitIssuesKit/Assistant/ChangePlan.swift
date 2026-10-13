import Foundation

/// Changes to a project's issues, proposed by the assistant from a text and reviewed one by one before anything is
/// sent. Every change is small enough to accept or reject on its own.
public struct ChangePlan: Codable, Sendable {
    public var input: PlanInput
    public var provider: String
    public var model: String
    public var operations: [PlanOperation]
    /// Changes the assistant proposed that already hold, so there was nothing to do.
    public var dropped: [PlanNote]
    /// Points of the text the assistant deliberately left alone, and why.
    public var skipped: [PlanNote]
    public var summary: String
    /// False when the run stopped (limits, errors) before the assistant said it was done.
    public var finished: Bool
    public var stats: PlanStats
}

/// The text to work from, and what the app adds to every text it writes on GitHub.
public struct PlanInput: Codable, Sendable {
    public var title: String
    /// The day the text is from, "2026-10-12".
    public var date: String
    public var text: String
    /// Appended to every comment and new issue, such as "_From the weekly sync of 13 Oct 2026._". It also tells
    /// what was already taken over from the same text.
    public var footer: String

    public init(title: String, date: String, text: String, footer: String) {
        self.title = title
        self.date = date
        self.text = text
        self.footer = footer
    }
}

public struct PlanNote: Codable, Sendable, Hashable {
    public var what: String
    public var why: String
}

public struct PlanStats: Codable, Sendable {
    public var rounds = 0
    public var toolCalls: [String: Int] = [:]
    /// Calls the app refused (unknown label, issue not read first, …), which the model then had to fix.
    public var rejected = 0
    public var usage = LLMUsage()
    /// The most one request read.
    public var largestPrompt = 0
    public var seconds = 0.0
    public var stopReason = ""
}

public struct PlanOperation: Codable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case create
        case comment
        case setStatus
        case setPriority
        case setDue
        case setType
        case setMilestone
        case assign
        case unassign
        case addLabels
        case removeLabels
        case subIssueOf
        case blockedBy
        case close
        case editBody
    }

    public enum QuoteMatch: String, Codable, Sendable {
        case exact
        case approximate
        case missing
    }

    public struct TextEdit: Codable, Sendable, Hashable {
        public var find: String
        public var replace: String
    }

    /// What a new issue starts with.
    public struct NewIssue: Codable, Sendable {
        public var type: String?
        public var status: String?
        public var priority: String?
        public var due: String?
        public var labels: [String]
        public var assignees: [String]
        /// "#123", or "{{B}}" for another new issue.
        public var parent: String?
    }

    public var id: String
    public var kind: Kind
    /// "#494", or "{{A}}" for an issue this plan creates.
    public var issue: String
    /// "owner/name".
    public var repo: String
    /// The new status, priority, due day ("none" clears it), type, milestone, close reason, or the other issue of a
    /// relation.
    public var value: String?
    /// The logins or labels added or removed.
    public var values: [String]?
    public var title: String?
    /// A new issue's or comment's text, footer included.
    public var body: String?
    public var newIssue: NewIssue?
    public var edits: [TextEdit]?
    /// How it is now and how it would be, for the review ("Todo" → "Blocked").
    public var before: String?
    public var after: String?
    public var reason: String
    public var quote: String
    public var quoteMatch: QuoteMatch
    public var warnings: [String]
}
