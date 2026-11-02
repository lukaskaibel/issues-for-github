import SwiftUI

/// How My Issues shows: an overview of what you are doing and what comes next in each project, or one list of
/// everything, grouped and ordered as you choose.
enum MineLayout: String, Codable, CaseIterable, Identifiable {
    case overview
    case list

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: String(localized: .overview)
        case .list: String(localized: .list)
        }
    }
}

/// A project in My Issues' overview, or the issues on no board: what you are doing there, what comes next, and how
/// much waits for later.
struct MineLane: Identifiable, Equatable {
    /// How many issues Up next shows until the rest is unfolded: the most pressing ones.
    static let nextShown = 3

    /// The same as the group of the list by project, "project/<id>", or the group of issues on no board.
    var id: String
    /// Nil for the issues on no board.
    var projectId: String?
    var title: String
    /// Started (in progress, in review and the like), in My Issues' order.
    var started: [Item]
    /// To do, in My Issues' order. On no board, every open issue: they wait for a place on one.
    var next: [Item]
    /// In the backlog, or on the board without a status.
    var later: Int
    /// Finished in the last seven days, the latest first.
    var done: [Item] = []
    /// Open issues whose due date has passed.
    var overdue: Int

    var doneThisWeek: Int { done.count }
    var open: Int { started.count + next.count + later }
    /// Nothing started and nothing to do: the project takes no more than a line.
    var isQuiet: Bool { started.isEmpty && next.isEmpty }

    /// Up next as it shows: the first few, or every one once unfolded.
    func shownNext(unfolded: Bool) -> [Item] {
        unfolded ? next : Array(next.prefix(Self.nextShown))
    }

    /// How many more there are to do than show.
    func moreNext(unfolded: Bool) -> Int {
        unfolded ? 0 : max(0, next.count - Self.nextShown)
    }

    /// What a small widget of the lane lists: the first two, started before what is next.
    var smallRows: [Item] {
        Array((started + next).prefix(2))
    }
}

extension MineRules {
    /// A started issue that nobody has touched for this many days shows how long it has been waiting.
    static let idleAfterDays = 7

    /// When an issue last changed, in the issue itself or on its board.
    static func lastChange(of item: Item) -> Date? {
        [item.updatedAt, item.remoteUpdatedAt.flatMap(ProjectFilter.Term.date)].compactMap { $0 }.max()
    }

    /// How many days a started issue has gone without any change, once that is a week or more: work that has
    /// stopped, which the overview says.
    func idleDays(of item: Item, now: Date) -> Int? {
        guard kind(of: item) == .started, let last = Self.lastChange(of: item) else { return nil }
        let days = Int(now.timeIntervalSince(last) / 86_400)
        return days >= Self.idleAfterDays ? days : nil
    }

    /// My Issues' overview: a lane for each of `projects` you have issues in, in that order, then one for the issues
    /// on no board that are still open. A project's issues go by what their status means: started, to do, later
    /// (backlog or no status) and done; done ones only count when they were finished this week.
    func lanes(_ items: [Item], projects: [(id: String, title: String)], by display: MineDisplay, now: Date) -> [MineLane] {
        let today = context.today
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        func finished(_ item: Item) -> Date? {
            item.closedAt ?? Self.lastChange(of: item)
        }
        func finishedThisWeek(_ item: Item) -> Bool {
            finished(item).map { $0 >= weekAgo } ?? false
        }
        func latestFirst(_ items: [Item]) -> [Item] {
            items.sorted { (finished($0) ?? .distantPast) > (finished($1) ?? .distantPast) }
        }
        func isOverdue(_ item: Item) -> Bool {
            item.due.map { $0 < today } ?? false
        }

        var result: [MineLane] = []
        let byProject = Dictionary(grouping: items.filter(\.isOnBoard)) { $0.projectId ?? "" }
        for project in projects {
            guard let members = byProject[project.id] else { continue }
            var started: [Item] = []
            var next: [Item] = []
            var later = 0
            var done: [Item] = []
            var overdue = 0
            for item in members {
                switch kind(of: item) {
                case .started: started.append(item)
                case .unstarted: next.append(item)
                case .backlog: later += 1
                // On the board without a status: open waits for later, closed is done.
                case nil where !item.isClosed: later += 1
                case .completed, nil:
                    if finishedThisWeek(item) { done.append(item) }
                    continue
                case .canceled: continue
                }
                if isOverdue(item) { overdue += 1 }
            }
            guard !started.isEmpty || !next.isEmpty || later > 0 || !done.isEmpty else { continue }
            result.append(MineLane(
                id: "project/\(project.id)", projectId: project.id, title: project.title,
                started: sorted(started, by: display), next: sorted(next, by: display),
                later: later, done: latestFirst(done), overdue: overdue
            ))
        }

        let loose = items.filter { !$0.isOnBoard }
        let open = loose.filter { !$0.isClosed }
        if !open.isEmpty {
            result.append(MineLane(
                id: ListSection.noProjectId, projectId: nil, title: String(localized: .noProject),
                started: [], next: sorted(open, by: display), later: 0,
                done: latestFirst(loose.filter { $0.isClosed && kind(of: $0) == .completed && finishedThisWeek($0) }),
                overdue: open.filter(isOverdue).count
            ))
        }
        return result
    }
}

extension AppModel {
    /// My Issues' overview: a lane for each project in the sidebar's order (hidden ones left out) that has issues
    /// of yours, through My Issues' filter, then the open issues on no board.
    var mineLanes: [MineLane] {
        _ = dataVersion
        if let cached = mineLanesCache { return cached }
        let filter = mineFilter
        let rules = mineRules
        let items = filter.isEmpty ? assignedItems : assignedItems.filter { rules.matches($0, filter) }
        let lanes = rules.lanes(items, projects: shownProjects.map { (id: $0.id, title: $0.title) }, by: mineDisplay, now: Date())
        mineLanesCache = lanes
        return lanes
    }

    /// Lanes whose Up next shows everything, not just the first few. Kept on this device.
    func showsAllNext(_ lane: MineLane) -> Bool {
        _ = collapseVersion
        return UserDefaults.standard.stringArray(forKey: Self.unfoldedLanesKey)?.contains(lane.id) ?? false
    }

    /// Shows the rest of what is next in a lane, or only the first few again. An issue in focus that folds away hands
    /// the focus on, as `rebuild` does.
    func toggleAllNext(_ lane: MineLane) {
        var unfolded = Set(UserDefaults.standard.stringArray(forKey: Self.unfoldedLanesKey) ?? [])
        if unfolded.contains(lane.id) { unfolded.remove(lane.id) } else { unfolded.insert(lane.id) }
        UserDefaults.standard.set(Array(unfolded), forKey: Self.unfoldedLanesKey)
        collapseVersion += 1
        rebuild()
    }

    private static let unfoldedLanesKey = "mine.unfoldedLanes"

    /// The overview as list sections, one per project widget in the order they show: what the keyboard steps
    /// through, row by row. A large or medium widget shows its started issues and the first of what is next, a small
    /// one its first two.
    func overviewSections() -> [ListSection] {
        let lanes = Dictionary(mineLanes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return overviewWidgets.compactMap { widget -> ListSection? in
            guard let lane = lanes[widget.id] else { return nil }
            let items = widget.size == .small ? lane.smallRows : lane.started + lane.shownNext(unfolded: showsAllNext(lane))
            guard !items.isEmpty else { return nil }
            var nesting = Nesting()
            nesting.members = items
            nesting.rows = items.map { .item($0) }
            let icon: SectionIcon = lane.projectId.map { .project(projectLooks.look($0)) } ?? .status(.noProject)
            return ListSection(id: lane.id, title: lane.title, glyph: .none, option: nil, kind: .mine, groupIcon: icon, items: items, nesting: nesting)
        }
    }

    /// How long a started issue of yours has waited without a change, once that is a week or more.
    func idleDays(of item: Item) -> Int? {
        mineRules.idleDays(of: item, now: Date())
    }

    /// The first status of a project's board that means `kind`: where an issue goes that is dropped on In progress or
    /// Up next of the overview.
    func firstStatus(_ kind: StatusCategory, projectId: String?) -> FieldOption? {
        statusOptions(projectId: projectId).first { $0.statusCategory == kind }
    }
}
