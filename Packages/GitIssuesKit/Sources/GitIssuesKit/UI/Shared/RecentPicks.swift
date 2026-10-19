import Foundation

/// Changes made one after another are often alike: the next issue goes under the same parent or gets the same
/// label. Pickers remember what was chosen lately and offer it first, above a line, so the same choice again is
/// one key. Status, priority and milestone pickers are short and have number keys, so they stay as they are.
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
    private static let recentKept = 8

    /// Remembers a choice, most recent first.
    func noteRecent(_ kind: RecentPick, _ key: String?) {
        guard let key, !key.isEmpty else { return }
        let keys = Self.noting(key, in: recentPicks[kind.rawValue] ?? [])
        guard keys != recentPicks[kind.rawValue] else { return }
        recentPicks[kind.rawValue] = keys
    }

    /// Picker rows with the ones chosen lately moved up behind the first `after` rows (such as "Remove from #9" and
    /// the current parent), most recent first.
    func recentFirst(_ rows: [PickerItem], _ kind: RecentPick, after: Int = 0, key: (PickerItem) -> String = { $0.id }) -> [PickerItem] {
        Self.recentFirst(rows, recent: recentPicks[kind.rawValue] ?? [], after: after, key: key)
    }

    static func noting(_ key: String, in keys: [String]) -> [String] {
        Array(([key] + keys.filter { $0 != key }).prefix(recentKept))
    }

    /// At most three rows come up. Rows that are checked already stay where they were: choosing them again would
    /// take them away, which isn't the change being repeated.
    static func recentFirst(_ rows: [PickerItem], recent: [String], after: Int = 0, key: (PickerItem) -> String = { $0.id }) -> [PickerItem] {
        guard !recent.isEmpty else { return rows }
        let lead = Array(rows.prefix(after))
        var rest = Array(rows.dropFirst(after))
        var moved: [PickerItem] = []
        for wanted in recent where moved.count < recentShown {
            guard let index = rest.firstIndex(where: { !$0.selected && !$0.alwaysShown && key($0) == wanted }) else { continue }
            var row = rest.remove(at: index)
            row.recent = true
            moved.append(row)
        }
        return lead + moved + rest
    }
}
