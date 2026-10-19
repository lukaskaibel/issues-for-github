import SwiftUI

/// How My Issues groups its issues. It mixes projects, so it groups by what means the same in all of them.
enum MineGrouping: String, Codable, CaseIterable, Identifiable {
    /// By the kind of status: in progress, todo, backlog, done, canceled.
    case status
    case project
    /// By the level of priority, whatever each project calls it.
    case priority
    case dueDate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .status: String(localized: .status)
        case .project: String(localized: .project)
        case .priority: String(localized: .priority)
        case .dueDate: String(localized: .dueDate)
        }
    }
}

/// What My Issues is ordered by within its groups.
enum MineOrder: String, Codable, CaseIterable, Identifiable {
    case priority
    case dueDate
    case updated
    case created
    /// As each issue's board has it.
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .priority: String(localized: .priority)
        case .dueDate: String(localized: .dueDate)
        case .updated: String(localized: .filterUpdated)
        case .created: String(localized: .created)
        case .manual: String(localized: .manualOrder)
        }
    }

    /// Changes come newest first; priorities most urgent first and due dates soonest first.
    var descendsByDefault: Bool {
        self == .updated || self == .created
    }
}

/// How you see My Issues. GitHub has no view behind it, so this is kept on the device, as your own display of a view
/// is.
struct MineDisplay: Codable, Equatable {
    var grouping: MineGrouping = .status
    var order: MineOrder = .priority
    var descending = false

    var isDefault: Bool { self == MineDisplay() }

    /// As the settings keep it: JSON in a string, which reads and writes back like the app's other settings (the
    /// README's picture script puts it back after its run).
    var stored: String {
        (try? JSONEncoder().encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    init(grouping: MineGrouping = .status, order: MineOrder = .priority, descending: Bool = false) {
        self.grouping = grouping
        self.order = order
        self.descending = descending
    }

    init?(stored: String?) {
        guard let data = stored?.data(using: .utf8), let display = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        self = display
    }
}

/// What a filter is about: a project, whose views GitHub keeps, or My Issues, which mixes every project.
enum FilterScope: Hashable {
    case project(String)
    case myIssues

    var projectId: String? {
        if case .project(let id) = self { id } else { nil }
    }
}

/// My Issues' filter and order, kept apart from the app's data so they can be checked on their own. What they need
/// to know of an issue besides the issue itself, what its status means and how urgent it is, comes worked out by the
/// issue's id. Status, priority and the due date are compared by what they mean, so "In Review" in one project and
/// "Doing" in another are both in progress, and "P0" and "Urgent" are both urgent.
struct MineRules {
    var context: FilterContext
    var kinds: [String: StatusCategory] = [:]
    var priorities: [String: PriorityLevel] = [:]

    /// What the issue's status means; nil for open issues on no board and cards without a status.
    func kind(of item: Item) -> StatusCategory? { kinds[item.id] }
    func priority(of item: Item) -> PriorityLevel { priorities[item.id] ?? .none }

    // MARK: Filter

    /// Whether an issue passes every term of the filter. A term My Issues doesn't know passes.
    func matches(_ item: Item, _ filter: ProjectFilter) -> Bool {
        filter.terms.allSatisfy { term in
            guard let result = evaluate(term, item) else { return true }
            return result != term.negated
        }
    }

    /// Whether an issue matches a term before its `-` is applied; nil when My Issues doesn't know the term.
    func evaluate(_ term: ProjectFilter.Term, _ item: Item) -> Bool? {
        guard let key = term.key else { return nil }
        let wanted = term.values.map { $0.lowercased() }
        switch key {
        case "project":
            guard let projectId = item.projectId?.lowercased() else { return false }
            return wanted.contains(projectId)
        case "status":
            guard let kind = kind(of: item) else { return false }
            return wanted.contains(Self.statusWord(kind))
        case "priority":
            let level = priority(of: item)
            return level != .none && wanted.contains(Self.priorityWord(level))
        case "due":
            guard let day = item.due else { return false }
            return term.values.contains { DateBound.parse($0, today: context.today)?.contains(day) ?? false }
        case "has", "no":
            let has = wanted.allSatisfy { self.has($0, item) }
            return key == "has" ? has : wanted.allSatisfy { !self.has($0, item) }
        case "label", "labels", "milestone", "updated", "is":
            return term.evaluate(item, context)
        default:
            return nil
        }
    }

    private func has(_ key: String, _ item: Item) -> Bool {
        switch key {
        case "project": item.isOnBoard
        case "status": kind(of: item) != nil
        case "priority": priority(of: item) != .none
        case "due": item.due != nil
        default: ProjectFilter.Term.has(key, item, context)
        }
    }

    /// Whether My Issues' chips can show a term: one of its own properties, with values it knows.
    static func understands(_ term: ProjectFilter.Term, today: CalendarDay) -> Bool {
        guard let key = term.key else { return false }
        let values = term.values.map { $0.lowercased() }
        switch key {
        case "project", "label", "labels", "milestone": return true
        case "status": return values.allSatisfy { value in StatusCategory.allKinds.contains { statusWord($0) == value } }
        case "priority": return values.allSatisfy { value in PriorityLevel.allCases.contains { $0 != .none && priorityWord($0) == value } }
        case "due", "updated": return values.allSatisfy { DateBound.parse($0, today: today) != nil }
        case "is": return values.allSatisfy { ["open", "closed"].contains($0) }
        case "has", "no": return values.allSatisfy { ["project", "status", "priority", "due", "label", "labels", "milestone"].contains($0) }
        default: return false
        }
    }

    /// The word the filter keeps for a kind of status.
    static func statusWord(_ kind: StatusCategory) -> String {
        switch kind {
        case .backlog: "backlog"
        case .unstarted: "todo"
        case .started: "started"
        case .completed: "done"
        case .canceled: "canceled"
        }
    }

    static func priorityWord(_ level: PriorityLevel) -> String {
        switch level {
        case .urgent: "urgent"
        case .high: "high"
        case .medium: "medium"
        case .low: "low"
        case .none: "none"
        }
    }

    // MARK: Order

    /// Issues in My Issues' order. Those without a value come last either way, as in a view; ties go by priority,
    /// then by due date, then by the latest change.
    func sorted(_ items: [Item], by display: MineDisplay) -> [Item] {
        guard display.order != .manual else { return items }
        func priority(_ item: Item) -> Double? {
            let level = self.priority(of: item)
            return level == .none ? nil : Double(PriorityLevel.urgent.rawValue - level.rawValue)
        }
        func due(_ item: Item) -> Double? {
            item.due.map { $0.date().timeIntervalSince1970 }
        }
        func updated(_ item: Item) -> Double? {
            [item.updatedAt, item.remoteUpdatedAt.flatMap(ProjectFilter.Term.date)].compactMap { $0 }.max()?.timeIntervalSince1970
        }
        func created(_ item: Item) -> Double? {
            item.createdAt?.timeIntervalSince1970
        }
        // Each step: the value, and whether larger comes first.
        let steps: [(value: (Item) -> Double?, descending: Bool)] = switch display.order {
        case .priority: [(priority, display.descending), (due, false), (updated, true)]
        case .dueDate: [(due, display.descending), (priority, false), (updated, true)]
        case .updated: [(updated, display.descending)]
        case .created: [(created, display.descending)]
        case .manual: []
        }
        // Each issue's values once, not again for every comparison.
        let values = items.map { item in steps.map { $0.value(item) } }
        return items.enumerated().sorted { a, b in
            for (index, step) in steps.enumerated() {
                switch (values[a.offset][index], values[b.offset][index]) {
                case (nil, nil): continue
                case (nil, _): return false
                case (_, nil): return true
                case (let x?, let y?):
                    if x == y { continue }
                    return step.descending ? x > y : x < y
                }
            }
            return a.offset < b.offset
        }.map(\.element)
    }

    // MARK: Due dates

    /// The groups of My Issues by due date: open issues by when they are due, done ones together at the end, as a
    /// date that has passed means nothing for them any more.
    enum DueGroup: CaseIterable {
        case overdue, today, nextWeek, later, none, done
    }

    static func dueGroup(of item: Item, done: Bool, today: CalendarDay) -> DueGroup {
        if done { return .done }
        guard let day = item.due else { return .none }
        if day < today { return .overdue }
        if day == today { return .today }
        return day.days(from: today) <= 7 ? .nextWeek : .later
    }
}

extension AppModel {
    // MARK: Issues

    /// Everything assigned to you, on a board or not, open or closed, before My Issues' filter. Epics are planned on
    /// the roadmap.
    var assignedItems: [Item] {
        guard let login = viewer?.login else { return [] }
        return allItems.filter { item in !item.isEpic && item.assignees.contains { $0.login == login } }
    }

    /// What My Issues lists: assigned to you, through its filter, in its order.
    func mineItems() -> [Item] {
        let filter = mineFilter
        let rules = mineRules
        let shown = filter.isEmpty ? assignedItems : assignedItems.filter { rules.matches($0, filter) }
        return rules.sorted(shown, by: mineDisplay)
    }

    /// My Issues' rules with what they need to know of the issues assigned to you, worked out once per change of the
    /// data. My Issues mixes projects, so its filter knows no project's fields.
    var mineRules: MineRules {
        if let cached = mineRulesCache { return cached }
        var rules = MineRules(context: FilterContext(
            viewerLogin: viewer?.login, today: .today(), fields: [], statusFieldId: nil, priorityFieldId: nil,
            dueFieldId: nil, optionName: { _, _ in nil }, parentReference: { _ in nil }
        ))
        for item in assignedItems {
            rules.kinds[item.id] = kindOfStatus(of: item)
            rules.priorities[item.id] = priorityLevel(of: item)
        }
        mineRulesCache = rules
        return rules
    }

    // MARK: Filter

    var mineFilter: ProjectFilter {
        ProjectFilter(mineFilterText)
    }

    func setMineFilter(_ filter: ProjectFilter) {
        let text = filter.text
        guard text != mineFilterText else { return }
        mineFilterText = text
        rebuild()
    }

    /// What an issue's status means: from its column on a board, else from whether it is closed. Open issues on no
    /// board and cards without a status have none.
    func kindOfStatus(of item: Item) -> StatusCategory? {
        guard item.isOnBoard else {
            guard item.isClosed else { return nil }
            return item.stateReason == "NOT_PLANNED" ? .canceled : .completed
        }
        return statusOption(of: item)?.statusCategory
    }

    static func statusTitle(_ kind: StatusCategory) -> String {
        switch kind {
        case .started: String(localized: .statusGroupInProgress)
        case .unstarted: String(localized: .statusGroupTodo)
        case .backlog: String(localized: .statusGroupBacklog)
        case .completed: String(localized: .statusGroupDone)
        case .canceled: String(localized: .statusGroupCanceled)
        }
    }

    static func statusGlyph(_ kind: StatusCategory) -> StatusGlyph {
        switch kind {
        case .started: StatusGlyph(category: .started, progress: 0.5, color: Theme.started)
        case .unstarted: StatusGlyph(category: .unstarted, progress: 0, color: Theme.textBody)
        case .backlog: .none
        case .completed: StatusGlyph(category: .completed, progress: 1, color: Theme.accent)
        case .canceled: StatusGlyph(category: .canceled, progress: 0, color: Theme.textTertiary)
        }
    }

    static func priorityTitle(_ level: PriorityLevel) -> String {
        switch level {
        case .urgent: String(localized: .priorityLevelUrgent)
        case .high: String(localized: .priorityLevelHigh)
        case .medium: String(localized: .priorityLevelMedium)
        case .low: String(localized: .priorityLevelLow)
        case .none: String(localized: .noPriority)
        }
    }

    // MARK: Display

    func setMineDisplay(_ change: (inout MineDisplay) -> Void) {
        var display = mineDisplay
        change(&display)
        guard display != mineDisplay else { return }
        mineDisplay = display
        rebuild()
    }

    /// Another order, in its own direction: changes newest first, the rest most urgent or soonest first.
    func setMineOrder(_ order: MineOrder) {
        setMineDisplay { display in
            guard display.order != order else { return }
            display.order = order
            display.descending = order.descendsByDefault
        }
    }

    func resetMineDisplay() {
        setMineDisplay { $0 = MineDisplay() }
    }

    // MARK: Groups

    /// My Issues' list, grouped as chosen. Outside the groups by status, issues that are done or canceled wait at
    /// the end of their group.
    func mineSections(_ items: [Item]) -> [ListSection] {
        switch mineDisplay.grouping {
        case .status: return groupedByKindOfStatus(items)
        case .project: return groupedByProject(items)
        case .priority: return groupedByPriority(items)
        case .dueDate: return groupedByDueDate(items)
        }
    }

    /// A group of My Issues: its issues with those that are done last, sub-issues under their parent.
    private func mineSection(id: String, title: String, icon: SectionIcon, items: [Item]) -> ListSection {
        let open = items.filter { !isDone($0) }
        let done = items.filter { isDone($0) }
        let (shown, nesting) = Nesting.arrange(open + done, folded: foldedParents)
        return ListSection(id: id, title: title, glyph: .none, option: nil, kind: .mine, groupIcon: icon, items: shown, nesting: nesting)
    }

    /// Issues on no board first, as they wait for someone to put them on one, then the projects in the sidebar's
    /// order.
    private func groupedByProject(_ items: [Item]) -> [ListSection] {
        var result: [ListSection] = []
        let loose = items.filter { !$0.isOnBoard }
        if !loose.isEmpty {
            // The same id as the group by status, so folding it holds for both.
            result.append(mineSection(id: ListSection.noProjectId, title: String(localized: .noProject), icon: .status(.noProject), items: loose))
        }
        let byProject = Dictionary(grouping: items.filter(\.isOnBoard)) { $0.projectId ?? "" }
        for project in projects.sorted(by: { !$0.closed && $1.closed }) {
            guard let members = byProject[project.id], !members.isEmpty else { continue }
            result.append(mineSection(id: "project/\(project.id)", title: project.title, icon: .project(projectLooks.look(project.id)), items: members))
        }
        return result
    }

    private func groupedByPriority(_ items: [Item]) -> [ListSection] {
        let byLevel = Dictionary(grouping: items) { priorityLevel(of: $0) }
        return PriorityLevel.allCases.reversed().compactMap { level -> ListSection? in
            guard let members = byLevel[level], !members.isEmpty else { return nil }
            return mineSection(
                id: "priority/\(MineRules.priorityWord(level))", title: Self.priorityTitle(level),
                icon: level == .none ? .plain : .priority(level), items: members
            )
        }
    }

    /// Open issues by when they are due; done ones together at the end.
    private func groupedByDueDate(_ items: [Item]) -> [ListSection] {
        let today = mineRules.context.today
        let grouped = Dictionary(grouping: items) { MineRules.dueGroup(of: $0, done: isDone($0), today: today) }
        return MineRules.DueGroup.allCases.compactMap { group in
            guard let members = grouped[group], !members.isEmpty else { return nil }
            // The ids stay the same in every language: folded sections and their order are kept by them.
            let (id, title, icon): (String, String, SectionIcon) = switch group {
            case .overdue: ("due/overdue", String(localized: .filterOverdue), .due(.overdue))
            case .today: ("due/today", String(localized: .today), .due(.today))
            case .nextWeek: ("due/week", String(localized: .dueGroupNextWeek), .due(.upcoming))
            case .later: ("due/later", String(localized: .later), .due(.upcoming))
            case .none: ("due/none", String(localized: .noDueDate), .plain)
            case .done: ("Done", String(localized: .statusGroupDone), .status(Self.statusGlyph(.completed)))
            }
            return mineSection(id: id, title: title, icon: icon, items: members)
        }
    }

    // MARK: Filter menu

    /// What My Issues can be filtered by: what means the same in every project.
    func mineFilterProperties() -> [FilterProperty] {
        let items = assignedItems
        var result = [
            FilterProperty(id: "project", title: String(localized: .project), icon: .project(.standard)),
            FilterProperty(id: "status", title: String(localized: .status), icon: .status(Self.statusGlyph(.unstarted))),
            FilterProperty(id: "priority", title: String(localized: .priority), icon: .priority(.high)),
            FilterProperty(id: "label", title: String(localized: .filterLabel), icon: .symbol("tag")),
        ]
        if items.contains(where: { $0.milestoneTitle != nil }) {
            result.append(FilterProperty(id: "milestone", title: String(localized: .milestone), icon: .milestone(.upcoming)))
        }
        result.append(FilterProperty(id: "due", title: String(localized: .dueDate), icon: .symbol("calendar"), takesSeveral: false, namedWithValues: true))
        result.append(FilterProperty(id: "updated", title: String(localized: .filterUpdated), icon: .symbol("clock"), takesSeveral: false, namedWithValues: true))
        result.append(FilterProperty(id: "is", title: String(localized: .filterOpenOrClosed), icon: .symbol("circle.circle"), takesSeveral: false))
        return result
    }

    /// The values the filter menu offers for a property of My Issues, with how many of your issues each finds.
    func mineFilterValues(_ property: FilterProperty) -> [FilterValue] {
        let items = assignedItems
        let rules = mineRules
        var result: [FilterValue] = []
        func add(_ key: String, _ value: String, _ title: String, subtitle: String? = nil, icon: FilterIcon) {
            let filter = ProjectFilter(terms: [ProjectFilter.Term(key: key, values: [value])])
            let count = items.filter { rules.matches($0, filter) }.count
            result.append(FilterValue(key: key, value: value, title: title, subtitle: subtitle, icon: icon, count: count))
        }
        switch property.id {
        case "project":
            let mine = Set(items.compactMap(\.projectId))
            for project in projects where !project.closed || mine.contains(project.id) {
                add("project", project.id, project.title, icon: .project(projectLooks.look(project.id)))
            }
            add("no", "project", String(localized: .noProject), icon: .status(.noProject))
        case "status":
            for kind in [StatusCategory.started, .unstarted, .backlog, .completed, .canceled] {
                add("status", MineRules.statusWord(kind), Self.statusTitle(kind), icon: .status(Self.statusGlyph(kind)))
            }
            add("no", "status", String(localized: .noStatus), icon: .status(.none))
        case "priority":
            for level in [PriorityLevel.urgent, .high, .medium, .low] {
                add("priority", MineRules.priorityWord(level), Self.priorityTitle(level), icon: .priority(level))
            }
            add("no", "priority", String(localized: .noPriority), icon: .priority(.none))
        case "label":
            var labels: [String: LabelRef] = [:]
            for item in items { for label in item.labels where labels[label.name.lowercased()] == nil { labels[label.name.lowercased()] = label } }
            for label in labels.values.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
                add("label", label.name, label.name, icon: .label(label.color))
            }
            add("no", "label", String(localized: .filterNoLabel), icon: .symbol("tag.slash"))
        case "milestone":
            let today = CalendarDay.today()
            let groups = Dictionary(items.compactMap { item in item.milestoneTitle.map { ($0, milestoneGroup(of: item)) } }, uniquingKeysWith: { $0 ?? $1 })
            // Those due soonest first, then the rest by name.
            let titles = groups.keys.sorted { a, b in
                switch (groups[a]??.due, groups[b]??.due) {
                case (let x?, let y?) where x != y: x < y
                case (_?, nil): true
                case (nil, _?): false
                default: a.localizedStandardCompare(b) == .orderedAscending
                }
            }
            for title in titles {
                let group = groups[title] ?? nil
                add("milestone", title, title, subtitle: group?.due?.shortLabel(today: today),
                    icon: .milestone(group.map { mark(of: $0, projectId: nil, today: today) } ?? .upcoming))
            }
            add("no", "milestone", String(localized: .noMilestone), icon: .milestone(.none))
        case "due":
            add("due", "<@today", String(localized: .filterOverdue), icon: .symbol("calendar"))
            add("due", "@today", String(localized: .today), icon: .symbol("calendar"))
            add("due", "@today..@today+7d", String(localized: .filterNextWeek), icon: .symbol("calendar"))
            add("has", "due", String(localized: .filterHasDate), icon: .symbol("calendar"))
            add("no", "due", String(localized: .noDueDate), icon: .symbol("calendar.badge.minus"))
        case "updated":
            add("updated", "@today", String(localized: .today), icon: .symbol("clock"))
            add("updated", ">@today-7d", String(localized: .filterLastWeek), icon: .symbol("clock"))
            add("updated", ">@today-30d", String(localized: .filterLastMonth), icon: .symbol("clock"))
            add("updated", "<@today-30d", String(localized: .filterLongerAgo), icon: .symbol("clock"))
        case "is":
            add("is", "open", String(localized: .filterOpen), icon: .symbol("circle"))
            add("is", "closed", String(localized: .filterClosed), icon: .symbol("checkmark.circle"))
        default:
            break
        }
        return result
    }

    /// How a value of My Issues' filter reads: a project's title, a kind of status, a level of priority.
    func mineValueTitle(_ value: String, key: String) -> String? {
        switch key {
        case "project":
            return projects.first { $0.id.caseInsensitiveCompare(value) == .orderedSame }?.title ?? String(localized: .unknownProject)
        case "status":
            return StatusCategory.allKinds.first { MineRules.statusWord($0) == value.lowercased() }.map(Self.statusTitle)
        case "priority":
            return PriorityLevel.allCases.first { MineRules.priorityWord($0) == value.lowercased() }.map(Self.priorityTitle)
        default:
            return nil
        }
    }
}

extension StatusCategory {
    /// Every kind, in the order My Issues lists them.
    static let allKinds: [StatusCategory] = [.started, .unstarted, .backlog, .completed, .canceled]
}
