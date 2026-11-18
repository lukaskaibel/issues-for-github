import SwiftUI

/// The card of the overview that looks across every project, beside the projects' own.
enum MineSmartCard: String, CaseIterable, Identifiable {
    /// What wants you now: overdue, due today, urgent and not started, started but idle, on no board.
    case needsYou

    /// The card's id in an arrangement, apart from any project's.
    var id: String { "smart/" + rawValue }

    init?(id: String) {
        guard id.hasPrefix("smart/"), let card = Self(rawValue: String(id.dropFirst(6))) else { return nil }
        self = card
    }

    var title: String {
        switch self {
        case .needsYou: String(localized: .widgetNeedsYou)
        }
    }
}

/// How the overview's cards are arranged: by themselves, from what goes on in each project, or as you put them. Kept
/// in iCloud, so your Mac, iPhone and iPad show the same (`OverviewArrangementStore`).
struct MineArrangement: Equatable {
    /// Arranged from what goes on, until a card is moved or added.
    var automatic = true
    /// Once arranged by hand: the cards in their order, also those of projects that have no issues of yours right now,
    /// so they come back where they were.
    var order: [String] = []
    /// Projects and Needs you taken out of the overview, by id. They stay out however it is arranged.
    var removed: [String] = []

    /// Where a project's card goes while the overview arranges itself: projects with work started first, then those
    /// with only things to do, then quiet ones, and the issues on no board last.
    static func rank(of lane: MineLane) -> Int {
        if lane.projectId == nil { return 3 }
        if !lane.started.isEmpty { return 0 }
        return lane.next.isEmpty ? 2 : 1
    }

    /// The cards as the overview shows them, by id. Arranged by itself: what needs you first, then the projects by
    /// what goes on in them. Arranged by hand: in your order, with cards not placed yet at the end. Projects without
    /// issues of yours, and those taken out, are left out.
    func placed(_ lanes: [MineLane], needsYou: Bool) -> [String] {
        let shown = lanes.filter { !removed.contains($0.id) }
        let ranked = shown.enumerated().sorted { a, b in
            (Self.rank(of: a.element), a.offset) < (Self.rank(of: b.element), b.offset)
        }.map(\.element.id)
        let needsYouId = MineSmartCard.needsYou.id
        guard !automatic else {
            return (needsYou && !removed.contains(needsYouId) ? [needsYouId] : []) + ranked
        }
        let laneIds = Set(ranked)
        var result = order.filter { laneIds.contains($0) || ($0 == needsYouId && !removed.contains($0)) }
        let placedIds = Set(order)
        result += ranked.filter { !placedIds.contains($0) }
        return result
    }
}

extension MineArrangement: Codable {
    /// The arrangement as iCloud keeps it, in the shape the first overview wrote, whose cards had sizes: a device that
    /// still runs that version reads it as well.
    private struct Placed: Codable {
        var id: String
        var size = "medium"
    }

    private enum CodingKeys: String, CodingKey {
        case automatic, widgets, removed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        automatic = try container.decodeIfPresent(Bool.self, forKey: .automatic) ?? true
        order = try container.decodeIfPresent([Placed].self, forKey: .widgets)?.map(\.id) ?? []
        removed = try container.decodeIfPresent([String].self, forKey: .removed) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(automatic, forKey: .automatic)
        try container.encode(order.map { Placed(id: $0) }, forKey: .widgets)
        try container.encode(removed, forKey: .removed)
    }
}

/// An issue that wants you now, whatever its project, and why: the first reason that holds.
struct NeedsYouEntry: Identifiable, Equatable {
    enum Reason: Int, Comparable, CaseIterable {
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

        /// The page's key, kept on the device like a project card's page.
        var key: String {
            switch self {
            case .overdue: "overdue"
            case .dueToday: "today"
            case .urgent: "urgent"
            case .idle: "idle"
            case .onNoBoard: "noboard"
            }
        }

        var title: String {
            switch self {
            case .overdue: String(localized: .filterOverdue)
            case .dueToday: String(localized: .dueToday)
            case .urgent: String(localized: .priorityLevelUrgent)
            case .idle: String(localized: .needsYouIdle)
            case .onNoBoard: String(localized: .needsYouOnNoBoard)
            }
        }

        var systemImage: String {
            switch self {
            case .overdue, .dueToday: "calendar"
            case .urgent: "exclamationmark.square"
            case .idle: "clock"
            case .onNoBoard: "tray"
            }
        }

        var color: Color {
            switch self {
            case .overdue: Theme.overdue
            case .dueToday, .urgent: Theme.urgent
            case .idle: Theme.textSecondary
            case .onNoBoard: Theme.accent
            }
        }
    }

    var item: Item
    var reason: Reason
    /// Overdue: for how many days; idle: how long.
    var days = 0

    var id: String { item.id }
}

/// A page of the Needs you card: the issues that want you for one reason.
struct NeedsYouPage: Identifiable, Equatable {
    var reason: NeedsYouEntry.Reason
    var entries: [NeedsYouEntry]

    var id: String { reason.key }
    var key: String { reason.key }
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
}

extension AppModel {
    // MARK: Cards

    var mineArrangement: MineArrangement {
        overviewArrangement.arrangement
    }

    /// The overview's cards, by id, in the order they show.
    var overviewCards: [String] {
        mineArrangement.placed(mineLanes, needsYou: !needsYou.isEmpty)
    }

    func lane(_ id: String) -> MineLane? {
        mineLanes.first { $0.id == id }
    }

    /// The card's name: the project's, or Needs you.
    func cardTitle(_ id: String) -> String {
        MineSmartCard(id: id)?.title ?? lane(id)?.title ?? projects.first { "project/\($0.id)" == id }?.title ?? id
    }

    /// What needs you now, across every project of the overview.
    var needsYou: [NeedsYouEntry] {
        _ = dataVersion
        if let cached = needsYouCache { return cached }
        let entries = mineRules.needsYou(mineLanes, now: Date())
        needsYouCache = entries
        return entries
    }

    /// The pages of the Needs you card: a page for each reason something needs you, most pressing first.
    var needsYouPages: [NeedsYouPage] {
        let byReason = Dictionary(grouping: needsYou, by: \.reason)
        return NeedsYouEntry.Reason.allCases.compactMap { reason in
            byReason[reason].map { NeedsYouPage(reason: reason, entries: $0) }
        }
    }

    var currentNeedsYouPage: NeedsYouPage? {
        let pages = needsYouPages
        return pages.first { $0.key == overviewPages[MineSmartCard.needsYou.id] } ?? pages.first
    }

    /// What can be added to the overview again: projects taken out that have issues of yours, and Needs you.
    var addableCards: [String] {
        let shown = Set(overviewCards)
        return mineLanes.map(\.id).filter { mineArrangement.removed.contains($0) }
            + MineSmartCard.allCases.map(\.id).filter { !shown.contains($0) && mineArrangement.removed.contains($0) }
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
        arrangement.order = automatic ? [] : overviewCards
        arrangement.automatic = automatic
        overviewArrangement.set(arrangement)
        rebuild()
    }

    /// A change by hand: what shows becomes your arrangement first, if the overview was arranging itself.
    private func arrangeByHand(_ change: (inout MineArrangement) -> Void) {
        var arrangement = mineArrangement
        let shown = overviewCards
        if arrangement.automatic {
            arrangement.automatic = false
            arrangement.order = shown
        } else {
            // Cards shown that had no place yet keep the one they show in.
            let placed = Set(arrangement.order)
            arrangement.order += shown.filter { !placed.contains($0) }
        }
        change(&arrangement)
        overviewArrangement.set(arrangement)
        rebuild()
    }

    /// Puts a card at `index` among those shown: the cards from there on move along.
    func moveCard(_ id: String, toShownIndex index: Int) {
        let shown = overviewCards.filter { $0 != id }
        guard overviewCards.firstIndex(of: id) != index else { return }
        arrangeByHand { arrangement in
            arrangement.order.removeAll { $0 == id }
            let target = index < shown.count ? arrangement.order.firstIndex(of: shown[index]) ?? arrangement.order.count : arrangement.order.count
            arrangement.order.insert(id, at: target)
        }
    }

    /// Takes a card out. It stays out until added again, also while the overview arranges itself.
    func removeCard(_ id: String) {
        var arrangement = mineArrangement
        if !arrangement.removed.contains(id) { arrangement.removed.append(id) }
        arrangement.order.removeAll { $0 == id }
        overviewArrangement.set(arrangement)
        rebuild()
    }

    /// Adds a card back: where the overview puts it while it arranges itself, else at the end.
    func addCard(_ id: String) {
        var arrangement = mineArrangement
        arrangement.removed.removeAll { $0 == id }
        if !arrangement.automatic, !arrangement.order.contains(id) { arrangement.order.append(id) }
        overviewArrangement.set(arrangement)
        rebuild()
    }
}
