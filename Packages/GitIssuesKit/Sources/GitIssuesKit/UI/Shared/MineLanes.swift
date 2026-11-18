import SwiftUI

/// How My Issues shows: an overview with a card per project, or one list of everything, grouped and ordered as you
/// choose.
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

/// A page of a project's card in My Issues' overview: a column of the project's board with issues of yours in it, or
/// what you finished this week, or the open issues on no board.
struct MineColumn: Identifiable, Equatable {
    /// What the page is known by across projects, so that one choice in Display holds for every board that has a
    /// column of that name: the name in lower case, or one of the keys below.
    var key: String
    var title: String
    /// What the column means; nil for cards on the board without a status, and for the issues on no board.
    var kind: StatusCategory?
    /// The board's status, for the page's icon and for issues dropped on it; nil for the pages of their own.
    var optionId: String?
    var items: [Item]

    var id: String { key }

    static let doneKey = "~done"
    static let noStatusKey = "~nostatus"
    static let noBoardKey = "~noboard"

    static func key(forColumn name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Whether a page shows until you choose otherwise in Display: what is started and what is to do, and the issues
    /// on no board, which wait for a place on one. The backlog, cards without a status and what you finished this week
    /// wait until you ask for them.
    static func shownByDefault(key: String, kind: StatusCategory?) -> Bool {
        key == noBoardKey || kind == .started || kind == .unstarted
    }
}

/// A card of the overview: a project, or the issues on no board, with a page for each column that holds issues of
/// yours.
struct MineLane: Identifiable, Equatable {
    /// The same as the group of the list by project, "project/<id>", or the group of issues on no board.
    var id: String
    /// Nil for the issues on no board.
    var projectId: String?
    var title: String
    /// The board's columns with open issues of yours: those in progress, those to do, then the backlog, each in the
    /// board's order; cards without a status after them, then what you finished this week. For the issues on no board: those still open, then those finished this week.
    var columns: [MineColumn]

    /// Started: in progress, in review and the like.
    var started: [Item] { columns.filter { $0.kind == .started }.flatMap(\.items) }
    /// What is to do, and the open issues on no board, which wait for a place on one.
    var next: [Item] { columns.filter { $0.kind == .unstarted || $0.key == MineColumn.noBoardKey }.flatMap(\.items) }
    /// Open, in any column.
    var open: [Item] { columns.filter { $0.key != MineColumn.doneKey }.flatMap(\.items) }
    var done: [Item] { columns.first { $0.key == MineColumn.doneKey }?.items ?? [] }

    /// Nothing started and nothing to do.
    var isQuiet: Bool { started.isEmpty && next.isEmpty }
}

/// A column of the board as My Issues needs to know it: the status, its name and where it stands.
struct MineColumnRef: Equatable {
    var optionId: String
    var name: String
    var position: Int
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
    /// on no board. A project's open issues go to the column of the board they are in, what is started coming first;
    /// those finished this week to a page of their own, after the columns; canceled ones and those finished before this week are left out. A column
    /// that means done holds no open issues of its own: an open issue in it counts as finished when it got there.
    func lanes(
        _ items: [Item], projects: [(id: String, title: String)], by display: MineDisplay, now: Date,
        doneTitle: String = String(localized: .widgetDoneThisWeek), noStatusTitle: String = String(localized: .noStatus),
        noBoardTitle: String = String(localized: .needsYouOnNoBoard), noProjectTitle: String = String(localized: .noProject)
    ) -> [MineLane] {
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
        func doneColumn(_ items: [Item]) -> [MineColumn] {
            items.isEmpty ? [] : [MineColumn(key: MineColumn.doneKey, title: doneTitle, kind: .completed, optionId: nil, items: latestFirst(items))]
        }

        var result: [MineLane] = []
        let byProject = Dictionary(grouping: items.filter(\.isOnBoard)) { $0.projectId ?? "" }
        for project in projects {
            guard let members = byProject[project.id] else { continue }
            var inColumns: [String: (ref: MineColumnRef, kind: StatusCategory?, items: [Item])] = [:]
            var noStatus: [Item] = []
            var done: [Item] = []
            for item in members {
                let kind = kind(of: item)
                switch kind {
                case .canceled:
                    continue
                case .completed:
                    if finishedThisWeek(item) { done.append(item) }
                case nil where item.isClosed:
                    if item.stateReason != "NOT_PLANNED", finishedThisWeek(item) { done.append(item) }
                case nil:
                    noStatus.append(item)
                default:
                    guard let ref = self.columns[item.id] else {
                        noStatus.append(item)
                        continue
                    }
                    inColumns[ref.optionId, default: (ref, kind, [])].items.append(item)
                }
            }
            // What you are working on first, then what is to do, then the backlog: in each, as the board has them.
            func rank(_ kind: StatusCategory?) -> Int {
                switch kind {
                case .started: 0
                case .unstarted: 1
                default: 2
                }
            }
            var pages = inColumns.values.sorted {
                (rank($0.kind), $0.ref.position) < (rank($1.kind), $1.ref.position)
            }.map { column in
                MineColumn(
                    key: MineColumn.key(forColumn: column.ref.name), title: column.ref.name, kind: column.kind,
                    optionId: column.ref.optionId, items: sorted(column.items, by: display)
                )
            }
            if !noStatus.isEmpty {
                pages.append(MineColumn(key: MineColumn.noStatusKey, title: noStatusTitle, kind: nil, optionId: nil, items: sorted(noStatus, by: display)))
            }
            pages += doneColumn(done)
            guard !pages.isEmpty else { continue }
            result.append(MineLane(id: "project/\(project.id)", projectId: project.id, title: project.title, columns: pages))
        }

        let loose = items.filter { !$0.isOnBoard }
        let open = loose.filter { !$0.isClosed }
        if !open.isEmpty {
            var pages = [MineColumn(key: MineColumn.noBoardKey, title: noBoardTitle, kind: nil, optionId: nil, items: sorted(open, by: display))]
            pages += doneColumn(loose.filter { $0.isClosed && kind(of: $0) == .completed && finishedThisWeek($0) })
            result.append(MineLane(id: ListSection.noProjectId, projectId: nil, title: noProjectTitle, columns: pages))
        }
        return result
    }
}

extension MineDisplay {
    /// Whether the overview's cards show a page: as you chose in Display, else as it starts out.
    func showsPage(key: String, kind: StatusCategory?) -> Bool {
        pages[key] ?? MineColumn.shownByDefault(key: key, kind: kind)
    }

    func showsPage(_ column: MineColumn) -> Bool {
        showsPage(key: column.key, kind: column.kind)
    }
}

extension AppModel {
    /// Everything that is yours, on a board or not, open or closed, before My Issues' filter: what is assigned to you,
    /// and in a project where nobody else has open issues, what is assigned to nobody, since there it can only be
    /// yours. Epics are planned on the roadmap.
    var myItems: [Item] {
        _ = dataVersion
        if let cached = myItemsCache { return cached }
        guard let login = viewer?.login else { return [] }
        let solo = Self.soloProjectIds(allItems, login: login)
        let items = allItems.filter { item in
            guard !item.isEpic else { return false }
            if item.assignees.isEmpty { return item.projectId.map(solo.contains) ?? false }
            return item.assignees.contains { $0.login == login }
        }
        myItemsCache = items
        return items
    }

    /// The projects in which no open issue is assigned to anyone but `login`: those you work on alone, where people
    /// don't assign issues to themselves.
    nonisolated static func soloProjectIds(_ items: [Item], login: String) -> Set<String> {
        var shared = Set<String>()
        var all = Set<String>()
        for item in items where !item.isClosed {
            guard let projectId = item.projectId else { continue }
            all.insert(projectId)
            if item.assignees.contains(where: { $0.login != login }) { shared.insert(projectId) }
        }
        return all.subtracting(shared)
    }

    /// My Issues' overview: a lane for each project in the sidebar's order (hidden ones left out) that has issues of
    /// yours, through My Issues' filter, then the open issues on no board.
    var mineLanes: [MineLane] {
        _ = dataVersion
        if let cached = mineLanesCache { return cached }
        let filter = mineFilter
        let rules = mineRules
        let items = filter.isEmpty ? myItems : myItems.filter { rules.matches($0, filter) }
        let lanes = rules.lanes(items, projects: shownProjects.map { (id: $0.id, title: $0.title) }, by: mineDisplay, now: Date())
        mineLanesCache = lanes
        return lanes
    }

    // MARK: Pages

    /// A card's pages: the columns Display shows.
    func shownColumns(of lane: MineLane) -> [MineColumn] {
        lane.columns.filter(mineDisplay.showsPage)
    }

    /// The page a card shows: the one you turned to, while it has issues and Display shows it, else its first.
    func currentColumn(of lane: MineLane) -> MineColumn? {
        let shown = shownColumns(of: lane)
        return shown.first { $0.key == overviewPages[lane.id] } ?? shown.first
    }

    /// Turns a card to another page. Kept on this device.
    func showPage(_ key: String, of cardId: String) {
        guard overviewPages[cardId] != key else { return }
        overviewPages[cardId] = key
        rebuild()
    }

    /// Every page a card can have, across the overview, for Display: the columns of your projects' boards by name, in
    /// the order of what they mean (started, to do, backlog), then cards without a status and what you finished this
    /// week.
    var overviewPageChoices: [(key: String, title: String, kind: StatusCategory?)] {
        var seen = Set<String>()
        var result: [(key: String, title: String, kind: StatusCategory?, rank: Int, order: Int)] = []
        for lane in mineLanes where lane.projectId != nil {
            for column in lane.columns where !seen.contains(column.key) {
                seen.insert(column.key)
                let rank: Int = switch column.kind {
                case .started: 0
                case .unstarted: 1
                case .backlog: 2
                case nil: 3
                case .completed, .canceled: 4
                }
                result.append((column.key, column.title, column.kind, rank, result.count))
            }
        }
        return result.sorted { ($0.rank, $0.order) < ($1.rank, $1.order) }.map { ($0.key, $0.title, $0.kind) }
    }

    /// Shows a page in every card that has it, or hides it.
    func setShowsPage(_ key: String, kind: StatusCategory?, _ shows: Bool) {
        setMineDisplay { display in
            if shows == MineColumn.shownByDefault(key: key, kind: kind) {
                display.pages[key] = nil
            } else {
                display.pages[key] = shows
            }
        }
    }

    /// The overview as list sections, one per card in the order they show, each with the issues its page shows: what
    /// the keyboard steps through, row by row.
    func overviewSections() -> [ListSection] {
        let lanes = Dictionary(mineLanes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let rows = max(1, overviewRowsPerPage)
        return overviewCards.compactMap { id -> ListSection? in
            let items: [Item]
            let title: String
            let icon: SectionIcon
            if MineSmartCard(id: id) == .needsYou {
                guard let page = currentNeedsYouPage else { return nil }
                items = page.entries.map(\.item)
                title = String(localized: .widgetNeedsYou)
                icon = .plain
            } else if let lane = lanes[id], let column = currentColumn(of: lane) {
                items = column.items
                title = lane.title
                icon = lane.projectId.map { .project(projectLooks.look($0)) } ?? .status(.noProject)
            } else {
                return nil
            }
            let shown = Array(items.prefix(items.count > rows ? rows - 1 : rows))
            guard !shown.isEmpty else { return nil }
            var nesting = Nesting()
            nesting.members = shown
            nesting.rows = shown.map { .item($0) }
            return ListSection(id: id, title: title, glyph: .none, option: nil, kind: .mine, groupIcon: icon, items: shown, nesting: nesting)
        }
    }

    /// How many issues a page has room for now; the keyboard's steps follow.
    func setOverviewRowsPerPage(_ rows: Int) {
        guard rows != overviewRowsPerPage, rows > 0 else { return }
        overviewRowsPerPage = rows
        rebuild()
    }

    /// Turns the page of the card the keyboard is in, and moves the focus to the first issue there.
    func turnFocusedPage(_ delta: Int) -> Bool {
        guard scope == .myIssues, mineDisplay.layout == .overview, openItem == nil, let focused = cursorId else { return false }
        guard let section = sections.first(where: { section in section.items.contains { $0.id == focused } }) else { return false }
        if MineSmartCard(id: section.id) == .needsYou {
            let pages = needsYouPages
            guard let index = pages.firstIndex(where: { $0.reason == currentNeedsYouPage?.reason }) else { return false }
            let target = pages[min(max(index + delta, 0), pages.count - 1)]
            showPage(target.key, of: section.id)
        } else {
            guard let lane = mineLanes.first(where: { $0.id == section.id }) else { return false }
            let shown = shownColumns(of: lane)
            guard let index = shown.firstIndex(where: { $0.key == currentColumn(of: lane)?.key }) else { return false }
            showPage(shown[min(max(index + delta, 0), shown.count - 1)].key, of: section.id)
        }
        if let first = sections.first(where: { $0.id == section.id })?.items.first { moveFocus(to: first.id) }
        return true
    }

    /// How long a started issue of yours has waited without a change, once that is a week or more.
    func idleDays(of item: Item) -> Int? {
        mineRules.idleDays(of: item, now: Date())
    }

    /// Where an issue dropped on a card's page goes: the status of that column.
    func status(of column: MineColumn, projectId: String?) -> FieldOption? {
        guard let id = column.optionId else { return nil }
        return statusOptions(projectId: projectId).first { $0.id == id }
    }
}
