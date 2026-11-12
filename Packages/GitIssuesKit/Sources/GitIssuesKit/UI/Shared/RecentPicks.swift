import Foundation

/// Changes made one after another are often alike: the next issue goes under the same parent or gets the same
/// label. Pickers remember what was chosen lately and offer it first, at the very top above a line, with the likeliest
/// lit, so the same choice again is one key. Status, priority and milestone pickers are short and have number keys,
/// so they stay as they are.
enum RecentPick: String {
    /// The issue others were put under, as their parent or their epic.
    case parent
    case blockedBy
    case blocking
    case assignee
    /// By name, since each repository has labels of its own.
    case label
}

extension AppModel {
    /// How many recent choices a picker offers first.
    static let recentShown = 3
    /// How many different choices are remembered.
    private static let recentKept = 8
    /// How many picks are remembered in all, repeats included.
    private static let picksKept = 24
    /// How much a pick still counts for each pick made after it. Between 0.62 and 0.7 a choice made twice in a row
    /// comes first, whatever was chosen before, and a single other choice made after such a run comes second, not
    /// first: going through issues that all get the same parent, the one that went elsewhere doesn't take its place.
    static let recentFade = 0.65
    /// One change to several issues at once is one pick, not one for each of them.
    private static let samePick: TimeInterval = 1
    private static var lastNoted: (kind: RecentPick, key: String, date: Date)?

    /// Remembers a choice.
    func noteRecent(_ kind: RecentPick, _ key: String?, at date: Date = .now) {
        guard let key, !key.isEmpty else { return }
        if let last = Self.lastNoted, last.kind == kind, last.key == key, abs(date.timeIntervalSince(last.date)) < Self.samePick {
            return
        }
        Self.lastNoted = (kind, key, date)
        recentPicks[kind.rawValue] = Self.noting(key, in: recentPicks[kind.rawValue] ?? [])
    }

    /// The choices made lately, likeliest first.
    func recentChoices(_ kind: RecentPick) -> [String] {
        Self.ranked(recentPicks[kind.rawValue] ?? [])
    }

    /// Picker rows with the ones chosen lately at the very top, likeliest first.
    func recentFirst(_ rows: [PickerItem], _ kind: RecentPick, key: (PickerItem) -> String = { $0.id }) -> [PickerItem] {
        let (recent, rest) = Self.splitRecent(rows, recent: recentChoices(kind), key: key) { !$0.selected && !$0.alwaysShown && !$0.creates }
        return recent.map { row in
            var row = row
            row.recent = true
            return row
        } + rest
    }

    /// The same for values that aren't picker rows, such as the people in a menu: the recent ones and the rest.
    /// `chosen` values stay with the rest.
    func splitRecent<Value>(_ values: [Value], _ kind: RecentPick, key: (Value) -> String, chosen: (Value) -> Bool) -> (recent: [Value], rest: [Value]) {
        Self.splitRecent(values, recent: recentChoices(kind), key: key) { !chosen($0) }
    }

    /// Adds a pick to the log of picks (latest first). Only so many different choices are kept: the least likely goes.
    /// Only so many picks are kept: the oldest pick of a choice that was made again later goes first, so a long run of
    /// one choice doesn't push the others out.
    static func noting(_ key: String, in log: [String]) -> [String] {
        var log = [key] + log
        while Set(log).count > recentKept, let least = ranked(log).last {
            log.removeAll { $0 == least }
        }
        while log.count > picksKept {
            if let repeated = log.indices.last(where: { log[..<$0].contains(log[$0]) }) {
                log.remove(at: repeated)
            } else {
                log.removeLast()
            }
        }
        return log
    }

    /// The choices in a log of picks (latest first), likeliest first: each pick counts `recentFade` times less for
    /// every pick made after it, and of two that count the same, the one chosen last comes first.
    static func ranked(_ log: [String]) -> [String] {
        var score: [String: Double] = [:]
        var order: [String] = []
        var weight = 1.0
        for key in log {
            if score[key] == nil { order.append(key) }
            score[key, default: 0] += weight
            weight *= recentFade
        }
        return order.enumerated()
            .sorted { a, b in
                let first = score[a.element] ?? 0, second = score[b.element] ?? 0
                return first != second ? first > second : a.offset < b.offset
            }
            .map(\.element)
    }

    /// At most three values come up, in the order of `recent`, and the rest stay in their order. Values that can't
    /// move, such as rows checked already, stay where they were: choosing them again would take them away, which
    /// isn't the change being repeated.
    static func splitRecent<Value>(
        _ values: [Value], recent: [String], key: (Value) -> String, movable: (Value) -> Bool
    ) -> (recent: [Value], rest: [Value]) {
        guard !recent.isEmpty else { return ([], values) }
        var rest = values
        var moved: [Value] = []
        for wanted in recent where moved.count < recentShown {
            guard let index = rest.firstIndex(where: { movable($0) && key($0) == wanted }) else { continue }
            moved.append(rest.remove(at: index))
        }
        return (moved, rest)
    }
}

extension AppModel {
    /// How long an issue you made counts as new for pickers that put issues under another.
    static let freshFor: TimeInterval = 24 * 60 * 60

    /// Of `candidates`, the open issues you made in the last day that are under no other issue yet, newest first, at
    /// most three: the likeliest to be put under a parent next.
    func freshIssues(_ candidates: [Item], now: Date = .now) -> [Item] {
        guard let login = viewer?.login else { return [] }
        return Array(candidates
            .filter { candidate in
                guard candidate.authorLogin == login, candidate.parentId == nil, !candidate.isClosed, !candidate.isEpic,
                      let created = candidate.createdAt else { return false }
                return now.timeIntervalSince(created) < Self.freshFor
            }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            .prefix(Self.recentShown))
    }
}
