import Foundation
import GRDB

// MARK: - Fields

/// What an item has in one of its project's own fields: an option, an iteration, a text, a number or a day.
public struct FieldValue: Codable, Hashable, Sendable {
    public var optionId: String?
    public var iterationId: String?
    public var text: String?
    public var number: Double?
    /// "2026-10-09".
    public var date: String?

    public init(optionId: String? = nil, iterationId: String? = nil, text: String? = nil, number: Double? = nil, date: String? = nil) {
        self.optionId = optionId
        self.iterationId = iterationId
        self.text = text
        self.number = number
        self.date = date
    }

    public var isEmpty: Bool { optionId == nil && iterationId == nil && text == nil && number == nil && date == nil }
}

/// One choice of a single-select field, such as "Quick Wins: Konto & Chat" of a field "Workstream".
public struct FieldChoice: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// GitHub's colour enum: GRAY, BLUE, GREEN, YELLOW, ORANGE, RED, PINK, PURPLE.
    public var color: String
    public var descr: String

    public init(id: String, name: String, color: String, descr: String = "") {
        self.id = id
        self.name = name
        self.color = color
        self.descr = descr
    }
}

/// One iteration of an Iteration field, such as a week: GitHub's cycles.
public struct IterationSpan: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    /// The first day, "2026-10-12".
    public var startDate: String
    /// In days.
    public var duration: Int
    /// GitHub lists iterations whose time is over separately from the current and coming ones.
    public var completed: Bool

    public init(id: String, title: String, startDate: String, duration: Int, completed: Bool) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.duration = duration
        self.completed = completed
    }

    public var start: CalendarDay? { CalendarDay(startDate) }
    /// The last day it covers.
    public var end: CalendarDay? { start?.adding(days: max(duration, 1) - 1) }

    public func contains(_ day: CalendarDay) -> Bool {
        guard let start, let end else { return false }
        return start <= day && day <= end
    }
}

/// A field of a project as GitHub lists it: one the project added (Status, "Workstream", "Iteration", a date) or one
/// every project has (Title, Assignees, Labels, Milestone, Parent issue…). Views name their columns, groups and
/// order by these.
public struct ProjectField: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    public static let databaseTableName = "projectField"

    public var id: String
    public var projectId: String
    /// GitHub's number for the field, which its REST API takes when a view is created.
    public var databaseId: Int?
    public var name: String
    /// GitHub's ProjectV2FieldType: SINGLE_SELECT, ITERATION, DATE, TEXT, NUMBER, ASSIGNEES, LABELS, MILESTONE,
    /// REPOSITORY, PARENT_ISSUE, ISSUE_TYPE, TITLE and so on.
    public var dataType: String
    public var position: Int
    /// A single-select field's choices, in their order.
    public var options: [FieldChoice] = []
    /// An Iteration field's iterations, by start.
    public var iterations: [IterationSpan] = []

    public init(
        id: String, projectId: String, databaseId: Int?, name: String, dataType: String, position: Int,
        options: [FieldChoice] = [], iterations: [IterationSpan] = []
    ) {
        self.id = id
        self.projectId = projectId
        self.databaseId = databaseId
        self.name = name
        self.dataType = dataType
        self.position = position
        self.options = options
        self.iterations = iterations
    }

    public var kind: ProjectFieldKind { ProjectFieldKind(dataType: dataType) }

    /// How the field is named in a filter: its name in lower case with dashes for spaces ("due-date").
    public var filterKey: String { Self.filterKey(name) }

    public static func filterKey(_ name: String) -> String {
        name.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: "-")
    }

    /// The iteration a day falls in.
    public func iteration(on day: CalendarDay) -> IterationSpan? {
        iterations.first { $0.contains(day) }
    }

    /// Iterations by start, the earliest first.
    public var orderedIterations: [IterationSpan] {
        iterations.sorted { ($0.start ?? CalendarDay(year: 1, month: 1, day: 1)) < ($1.start ?? CalendarDay(year: 1, month: 1, day: 1)) }
    }

    /// The iteration `offset` iterations away from the one running on `day` (0: that one), as GitHub's
    /// `@current`, `@next` and `@previous` count. Between iterations, the next one counts as current.
    public func iteration(offset: Int, from day: CalendarDay) -> IterationSpan? {
        let ordered = orderedIterations
        guard !ordered.isEmpty else { return nil }
        let current = ordered.firstIndex { $0.contains(day) }
            ?? ordered.firstIndex { ($0.start ?? day) > day }
            ?? ordered.count
        let index = current + offset
        return ordered.indices.contains(index) ? ordered[index] : nil
    }
}

/// What a project field holds, as far as the app tells them apart.
public enum ProjectFieldKind: Equatable, Sendable {
    case title
    case assignees
    case labels
    case milestone
    case repository
    case parentIssue
    case issueType
    case subIssuesProgress
    case linkedPullRequests
    case reviewers
    case singleSelect
    case iteration
    case date
    case text
    case number
    case created
    case updated
    case closed
    case other

    init(dataType: String) {
        switch dataType {
        case "TITLE": self = .title
        case "ASSIGNEES": self = .assignees
        case "LABELS": self = .labels
        case "MILESTONE": self = .milestone
        case "REPOSITORY": self = .repository
        case "PARENT_ISSUE": self = .parentIssue
        case "ISSUE_TYPE": self = .issueType
        case "SUB_ISSUES_PROGRESS": self = .subIssuesProgress
        case "LINKED_PULL_REQUESTS": self = .linkedPullRequests
        case "REVIEWERS": self = .reviewers
        case "SINGLE_SELECT": self = .singleSelect
        case "ITERATION": self = .iteration
        case "DATE": self = .date
        case "TEXT": self = .text
        case "NUMBER": self = .number
        case "CREATED": self = .created
        case "UPDATED": self = .updated
        case "CLOSED": self = .closed
        default: self = .other
        }
    }

    /// The project's own fields, whose values live on the project item rather than on the issue.
    public var isProjectValue: Bool {
        switch self {
        case .singleSelect, .iteration, .date, .text, .number: true
        default: false
        }
    }
}

// MARK: - Views

/// How a view lays out its issues on GitHub.
public enum ViewLayout: String, Codable, Sendable, CaseIterable {
    case board = "BOARD_LAYOUT"
    case table = "TABLE_LAYOUT"
    case roadmap = "ROADMAP_LAYOUT"
}

/// One step of a view's order: a field, up or down.
public struct ViewSort: Codable, Hashable, Sendable {
    public var fieldId: String
    public var descending: Bool

    public init(fieldId: String, descending: Bool) {
        self.fieldId = fieldId
        self.descending = descending
    }
}

/// A view saved in a GitHub project, such as "Diese Woche" or "Arbeitspakete": a filter with a layout, the fields
/// it shows, how it groups and orders them. Everyone in the project sees the same ones.
public struct ProjectView: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    public static let databaseTableName = "projectView"

    /// The node id; a local id while a new view is being created.
    public var id: String
    public var projectId: String
    /// Its number in the project, which its link on GitHub ends with.
    public var number: Int
    public var name: String
    public var layout: ViewLayout
    /// GitHub's filter text, such as `label:Meeting-Todo is:open`; "" shows everything.
    public var filter: String
    /// The fields it shows, in order.
    public var visibleFieldIds: [String] = []
    /// The field a table or roadmap groups by.
    public var groupByFieldId: String?
    /// The field a board has its columns by.
    public var columnFieldId: String?
    public var sortBy: [ViewSort] = []
    /// Its place among the project's views.
    public var position: Int
    public var updatedAt: String?
    /// Items GitHub says the filter matches, for filters with parts the app can't read itself; nil otherwise.
    public var matches: [String]?
    /// The filter `matches` were asked for.
    public var matchesFilter: String?

    public init(
        id: String, projectId: String, number: Int, name: String, layout: ViewLayout, filter: String,
        visibleFieldIds: [String] = [], groupByFieldId: String? = nil, columnFieldId: String? = nil,
        sortBy: [ViewSort] = [], position: Int, updatedAt: String? = nil, matches: [String]? = nil, matchesFilter: String? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.number = number
        self.name = name
        self.layout = layout
        self.filter = filter
        self.visibleFieldIds = visibleFieldIds
        self.groupByFieldId = groupByFieldId
        self.columnFieldId = columnFieldId
        self.sortBy = sortBy
        self.position = position
        self.updatedAt = updatedAt
        self.matches = matches
        self.matchesFilter = matchesFilter
    }

    public var isLocalOnly: Bool { id.hasPrefix(LocalID.prefix) }

    /// The view's page on GitHub.
    public func url(projectURL: String) -> URL? {
        URL(string: "\(projectURL)/views/\(number)")
    }
}
