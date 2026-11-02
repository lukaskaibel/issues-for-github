import SwiftUI

/// How much room a part of My Issues' overview takes. On a wide Mac window, of four columns: small one, medium two,
/// and large all four, where a project shows as a lane. On iPhone and iPad, small ones stand two to a row.
enum MineWidgetSize: String, Codable, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: String(localized: .widgetSmall)
        case .medium: String(localized: .widgetMedium)
        case .large: String(localized: .widgetLarge)
        }
    }

    /// "S", "M", "L", on the Mac's size buttons.
    var letter: String {
        String(title.prefix(1))
    }
}

/// Parts of the overview that look across every project, beside the projects themselves.
enum MineSmartWidget: String, Codable, CaseIterable, Identifiable {
    /// What wants you now: overdue, due today, urgent and not started, started but idle, on no board.
    case needsYou
    /// Open issues due in the coming seven days.
    case dueThisWeek
    /// What you finished in the last seven days.
    case doneThisWeek

    /// The widget's id in an arrangement, apart from any project's.
    var id: String { "smart/" + rawValue }

    init?(id: String) {
        guard id.hasPrefix("smart/"), let widget = Self(rawValue: String(id.dropFirst(6))) else { return nil }
        self = widget
    }

    var title: String {
        switch self {
        case .needsYou: String(localized: .widgetNeedsYou)
        case .dueThisWeek: String(localized: .widgetDueThisWeek)
        case .doneThisWeek: String(localized: .widgetDoneThisWeek)
        }
    }

    var systemImage: String {
        switch self {
        case .needsYou: "exclamationmark.circle"
        case .dueThisWeek: "calendar"
        case .doneThisWeek: "checkmark.circle"
        }
    }
}

/// A part of the overview as arranged: a project's lane, by the lane's id, or a smart widget, with its size.
struct MineWidget: Codable, Hashable, Identifiable {
    var id: String
    var size: MineWidgetSize

    var smart: MineSmartWidget? { MineSmartWidget(id: id) }
}

/// How the overview is arranged: by itself, from what goes on in each project, or as you put it. Kept in iCloud, so
/// your Mac, iPhone and iPad show the same (`OverviewArrangementStore`).
struct MineArrangement: Codable, Equatable {
    /// Laid out from what goes on, until a widget is moved, resized or added.
    var automatic = true
    /// Once arranged by hand: the widgets in their order, with their sizes, also those of projects that have no
    /// issues of yours right now, so they come back where they were.
    var widgets: [MineWidget] = []
    /// Projects and Needs you taken out of the overview, by id. They stay out however it is arranged.
    var removed: [String] = []

    /// What a project's lane starts as: large while something is started there, medium with only things to do,
    /// small with neither, and for the issues on no board.
    static func size(of lane: MineLane) -> MineWidgetSize {
        if !lane.started.isEmpty { return .large }
        if lane.isQuiet || lane.projectId == nil { return .small }
        return .medium
    }

    /// The widgets as the overview shows them. Arranged by itself: projects with work started first, then what needs
    /// you, the projects with only things to do, and the small ones. Arranged by hand: in your order, with projects
    /// not placed yet at the end, sized by what goes on there. Projects without issues of yours, and those taken out,
    /// are left out.
    func placed(_ lanes: [MineLane], needsYou: Bool) -> [MineWidget] {
        let shown = lanes.filter { !removed.contains($0.id) }
        guard !automatic else {
            let sized = shown.map { MineWidget(id: $0.id, size: Self.size(of: $0)) }
            var result = sized.filter { $0.size == .large }
            if needsYou, !removed.contains(MineSmartWidget.needsYou.id) {
                result.append(MineWidget(id: MineSmartWidget.needsYou.id, size: .medium))
            }
            result += sized.filter { $0.size == .medium }
            result += sized.filter { $0.size == .small }
            return result
        }
        let laneIds = Set(shown.map(\.id))
        var result = widgets.filter { laneIds.contains($0.id) || $0.smart != nil }
        let placedIds = Set(widgets.map(\.id))
        result += shown.filter { !placedIds.contains($0.id) }.map { MineWidget(id: $0.id, size: Self.size(of: $0)) }
        return result
    }
}

/// An issue that wants you now, whatever its project, and why: the first reason that holds.
struct NeedsYouEntry: Identifiable, Equatable {
    enum Reason: Int, Comparable {
        /// Open, and its due date has passed.
        case overdue
        case dueToday
        /// Urgent, and not started yet.
        case urgent
        /// Started, but nothing has changed for a week or more.
        case idle
        /// Open on no board: it waits for a place on one.
        case onNoBoard

        static func < (a: Reason, b: Reason) -> Bool { a.rawValue < b.rawValue }
    }

    var item: Item
    var reason: Reason
    /// Overdue: for how many days; idle: how long.
    var days = 0

    var id: String { item.id }
}

extension MineRules {
    /// What needs you across the overview's lanes, most pressing first: overdue, due today, urgent and not started,
    /// idle, on no board. An issue shows once, with the first of these that holds; within a reason the longest overdue
    /// or idle comes first, the rest as the lanes have them.
    func needsYou(_ lanes: [MineLane], now: Date) -> [NeedsYouEntry] {
        let today = context.today
        var result: [NeedsYouEntry] = []
        for lane in lanes {
            for item in lane.started + lane.next {
                if let due = item.due, due < today {
                    result.append(NeedsYouEntry(item: item, reason: .overdue, days: today.days(from: due)))
                } else if item.due == today {
                    result.append(NeedsYouEntry(item: item, reason: .dueToday))
                } else if kind(of: item) == .unstarted, priority(of: item) == .urgent {
                    result.append(NeedsYouEntry(item: item, reason: .urgent))
                } else if let days = idleDays(of: item, now: now) {
                    result.append(NeedsYouEntry(item: item, reason: .idle, days: days))
                } else if lane.projectId == nil {
                    result.append(NeedsYouEntry(item: item, reason: .onNoBoard))
                }
            }
        }
        return result.enumerated().sorted { a, b in
            if a.element.reason != b.element.reason { return a.element.reason < b.element.reason }
            if a.element.days != b.element.days { return a.element.days > b.element.days }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// The lanes' open issues due today or in the next seven days, soonest first.
    func dueThisWeek(_ lanes: [MineLane]) -> [Item] {
        let today = context.today
        return lanes.flatMap { $0.started + $0.next }
            .filter { item in item.due.map { $0 >= today && $0.days(from: today) <= 7 } ?? false }
            .enumerated()
            .sorted { a, b in
                let (x, y) = (a.element.due ?? today, b.element.due ?? today)
                return x != y ? x < y : a.offset < b.offset
            }
            .map(\.element)
    }
}

extension AppModel {
    // MARK: Widgets

    var mineArrangement: MineArrangement {
        overviewArrangement.arrangement
    }

    /// The overview's widgets, in the order they show.
    var overviewWidgets: [MineWidget] {
        mineArrangement.placed(mineLanes, needsYou: !needsYou.isEmpty)
    }

    func lane(_ id: String) -> MineLane? {
        mineLanes.first { $0.id == id }
    }

    /// The widget's name: the project's, or the smart widget's.
    func widgetTitle(_ id: String) -> String {
        MineSmartWidget(id: id)?.title ?? lane(id)?.title ?? projects.first { "project/\($0.id)" == id }?.title ?? id
    }

    /// What needs you now, across every project of the overview.
    var needsYou: [NeedsYouEntry] {
        _ = dataVersion
        if let cached = needsYouCache { return cached }
        let entries = mineRules.needsYou(mineLanes, now: Date())
        needsYouCache = entries
        return entries
    }

    var dueThisWeek: [Item] {
        mineRules.dueThisWeek(mineLanes)
    }

    /// Everything finished this week, the latest first.
    var doneThisWeek: [Item] {
        mineLanes.flatMap(\.done).sorted {
            ($0.closedAt ?? MineRules.lastChange(of: $0) ?? .distantPast) > ($1.closedAt ?? MineRules.lastChange(of: $1) ?? .distantPast)
        }
    }

    /// What can be added to the overview: projects taken out (that have issues of yours), and the smart widgets not
    /// shown.
    var addableWidgets: [MineWidget] {
        let shown = Set(overviewWidgets.map(\.id))
        let projects = mineLanes.filter { mineArrangement.removed.contains($0.id) }
            .map { MineWidget(id: $0.id, size: MineArrangement.size(of: $0)) }
        let smart = MineSmartWidget.allCases.filter { !shown.contains($0.id) }.map { MineWidget(id: $0.id, size: .medium) }
        return projects + smart
    }

    // MARK: Arranging

    /// Another device's arrangement changes the order the keyboard steps through, too.
    func followArrangement() {
        overviewArrangement.onChange = { [weak self] in self?.rebuild() }
    }

    /// Arranged by itself, from what goes on in each project, or as you left it.
    func setArrangesAutomatically(_ automatic: Bool) {
        var arrangement = mineArrangement
        guard arrangement.automatic != automatic else { return }
        if automatic {
            arrangement.widgets = []
            // Smart widgets you added go; what you took out stays out.
        } else {
            arrangement.widgets = overviewWidgets
        }
        arrangement.automatic = automatic
        overviewArrangement.set(arrangement)
        rebuild()
    }

    /// A change by hand: what shows becomes your arrangement first, if the overview was arranging itself.
    private func arrangeByHand(_ change: (inout MineArrangement) -> Void) {
        var arrangement = mineArrangement
        let shown = overviewWidgets
        if arrangement.automatic {
            arrangement.automatic = false
            arrangement.widgets = shown
        } else {
            // Projects shown that had no place yet keep the one they show in.
            let placed = Set(arrangement.widgets.map(\.id))
            arrangement.widgets += shown.filter { !placed.contains($0.id) }
        }
        change(&arrangement)
        overviewArrangement.set(arrangement)
        rebuild()
    }

    /// Puts a widget where another one is, which moves along: before it when coming from below, after it from above,
    /// as a dragged widget passes over the others.
    func moveWidget(_ id: String, onto target: String) {
        guard id != target else { return }
        arrangeByHand { arrangement in
            guard let from = arrangement.widgets.firstIndex(where: { $0.id == id }),
                  let to = arrangement.widgets.firstIndex(where: { $0.id == target }) else { return }
            let widget = arrangement.widgets.remove(at: from)
            arrangement.widgets.insert(widget, at: to)
        }
    }

    /// Moves a widget to `index` among those shown, as the iPhone's Customize list does.
    func moveWidget(_ id: String, toShownIndex index: Int) {
        let shown = overviewWidgets.map(\.id).filter { $0 != id }
        if index < shown.count {
            moveWidget(id, before: shown[index])
        } else {
            arrangeByHand { arrangement in
                guard let from = arrangement.widgets.firstIndex(where: { $0.id == id }) else { return }
                arrangement.widgets.append(arrangement.widgets.remove(at: from))
            }
        }
    }

    private func moveWidget(_ id: String, before target: String) {
        arrangeByHand { arrangement in
            guard let from = arrangement.widgets.firstIndex(where: { $0.id == id }) else { return }
            let widget = arrangement.widgets.remove(at: from)
            let to = arrangement.widgets.firstIndex { $0.id == target } ?? arrangement.widgets.count
            arrangement.widgets.insert(widget, at: to)
        }
    }

    func setWidgetSize(_ id: String, _ size: MineWidgetSize) {
        guard overviewWidgets.first(where: { $0.id == id })?.size != size else { return }
        arrangeByHand { arrangement in
            if let index = arrangement.widgets.firstIndex(where: { $0.id == id }) { arrangement.widgets[index].size = size }
        }
    }

    /// Takes a widget out. A project, or Needs you, stays out until added again, also while the overview arranges
    /// itself.
    func removeWidget(_ id: String) {
        let lasting = MineSmartWidget(id: id).map { $0 == .needsYou } ?? true
        if mineArrangement.automatic, lasting {
            var arrangement = mineArrangement
            if !arrangement.removed.contains(id) { arrangement.removed.append(id) }
            overviewArrangement.set(arrangement)
            rebuild()
            return
        }
        arrangeByHand { arrangement in
            arrangement.widgets.removeAll { $0.id == id }
            if lasting, !arrangement.removed.contains(id) { arrangement.removed.append(id) }
        }
    }

    /// Adds a widget at the end. A project, or Needs you while something needs you, comes back where the overview
    /// puts it while it arranges itself; the other smart widgets need a place of their own.
    func addWidget(_ widget: MineWidget) {
        var arrangement = mineArrangement
        arrangement.removed.removeAll { $0 == widget.id }
        let comesBack = widget.smart.map { $0 == .needsYou && !needsYou.isEmpty } ?? true
        if arrangement.automatic, comesBack {
            overviewArrangement.set(arrangement)
            rebuild()
            return
        }
        overviewArrangement.set(arrangement)
        arrangeByHand { arrangement in
            if !arrangement.widgets.contains(where: { $0.id == widget.id }) { arrangement.widgets.append(widget) }
        }
    }
}
