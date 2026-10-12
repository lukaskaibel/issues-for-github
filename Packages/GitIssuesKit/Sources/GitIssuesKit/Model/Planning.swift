import Foundation

// Milestones, epics and the roadmap they make. GitHub has milestones, but no epics: teams mark an issue as one with a
// label named "epic" or, in organisations, the issue type "Epic", and hang the work under it as sub-issues. The
// roadmap needs no dates of its own: an epic is due when the milestones of its sub-issues are.

extension Item {
    /// An issue that groups others as its sub-issues, as Linear's projects do. It is planned on the roadmap rather
    /// than worked on from a board.
    public var isEpic: Bool {
        kind == .issue && (issueType.map(Self.isEpicType) == true || labels.contains { Self.isEpicLabel($0.name) })
    }

    /// The label that makes an issue an epic: "epic", also as "type: epic" or "kind/epic", in any case.
    public static func isEpicLabel(_ name: String) -> Bool {
        let folded = name.trimmingCharacters(in: .whitespaces).lowercased()
        return folded == epicLabelName || ["type: epic", "type:epic", "type/epic", "kind/epic", "kind: epic"].contains(folded)
    }

    public static func isEpicType(_ name: String) -> Bool {
        name.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(epicLabelName) == .orderedSame
    }

    /// The label the app adds to make an issue an epic, and its colour, when the repository has none yet.
    public static let epicLabelName = "epic"
    public static let epicLabelColor = "5319E7"
}

/// A milestone as a board shows it. A board can take issues from several repositories, and each has milestones of
/// its own; teams keep them in step by name, so milestones of the same title are one here.
public struct MilestoneGroup: Identifiable, Hashable, Sendable {
    public var title: String
    /// One per repository, open ones first.
    public var milestones: [Milestone]

    public var id: String { title }
    public var isOpen: Bool { milestones.contains(where: \.isOpen) }
    public var ids: Set<String> { Set(milestones.map(\.id)) }

    /// The day it is due: the earliest of its open milestones, or of all of them once they are closed.
    public var due: CalendarDay? {
        let open = milestones.filter(\.isOpen).compactMap(\.due)
        return open.min() ?? milestones.compactMap(\.due).min()
    }

    public var descr: String {
        milestones.map(\.descr).first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
    }

    public var url: String? { milestones.first?.url }

    public func milestone(inRepository repoId: String?) -> Milestone? {
        milestones.first { $0.repoId == repoId }
    }

    /// Milestones grouped by title, in the order a roadmap reads them: open ones by the day they are due, those
    /// without a day after them, then closed ones, the most recent first.
    public static func groups(_ milestones: [Milestone]) -> [MilestoneGroup] {
        var byTitle: [String: [Milestone]] = [:]
        var order: [String] = []
        for milestone in milestones {
            if byTitle[milestone.title] == nil { order.append(milestone.title) }
            byTitle[milestone.title, default: []].append(milestone)
        }
        let groups = order.map { title in
            MilestoneGroup(title: title, milestones: byTitle[title]!.sorted { $0.isOpen && !$1.isOpen })
        }
        return groups.sorted(by: Self.precedes)
    }

    static func precedes(_ a: MilestoneGroup, _ b: MilestoneGroup) -> Bool {
        if a.isOpen != b.isOpen { return a.isOpen }
        switch (a.due, b.due) {
        case let (x?, y?) where x != y: return a.isOpen ? x < y : x > y
        case (.some, nil): return true
        case (nil, .some): return false
        default: return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }
}

/// A board's epics laid out over its open milestones, for the roadmap's timeline and list. Each milestone has a
/// stretch of time that ends on the day it is due; an epic covers the stretches of the milestones it and its
/// sub-issues are in.
public struct Roadmap: Equatable, Sendable {
    /// An open milestone's stretch of time. Milestones without a date follow the dated ones, a few weeks each.
    public struct Window: Equatable, Sendable, Identifiable {
        public var group: MilestoneGroup
        public var start: CalendarDay
        public var end: CalendarDay
        /// Whether the milestone has no due date, so its stretch is only a place in the order.
        public var undated: Bool
        public var id: String { group.id }
    }

    /// One epic on the roadmap.
    public struct Row: Equatable, Sendable, Identifiable {
        public var epic: Item
        /// 1 for an epic that is a sub-issue of another epic shown, which it hangs under.
        public var depth: Int
        /// Runs of neighbouring windows the epic covers, as index ranges into `windows`.
        public var runs: [ClosedRange<Int>]
        /// Its sub-issues, done and in all, as a whole and per milestone (by title).
        public var done: Int
        public var total: Int
        public var perMilestone: [String: Count]
        /// The open milestone that comes first for it, by title; nil for epics planned for no open milestone.
        public var next: String?
        public var id: String { epic.id }

        public var isPlanned: Bool { !runs.isEmpty }
    }

    public struct Count: Equatable, Sendable {
        public var done: Int
        public var total: Int
    }

    /// A sub-issue as the roadmap counts it: done or not, and in which milestone.
    public struct Child: Equatable, Sendable {
        public var contentId: String
        public var parentId: String
        public var milestone: String?
        public var done: Bool
        public var isEpic = false
    }

    public var windows: [Window]
    public var rows: [Row]
    /// Epics in no open milestone.
    public var later: [Row]

    public static let undatedLength = 28
    static let leadIn = 21

    /// - Parameters:
    ///   - groups: The board's milestones, open and closed (see `MilestoneGroup.groups`).
    ///   - epics: The board's epics, in board order.
    ///   - children: Every sub-issue known, of epics and of their sub-issues, with its milestone's title.
    ///   - milestoneOfEpic: Each epic's own milestone, by its node id.
    ///   - doneEpics: Epics that are finished; they show only while a milestone they cover is open.
    public static func make(
        groups: [MilestoneGroup], epics: [Item], children: [Child], milestoneOfEpic: [String: String],
        doneEpics: Set<String> = [], today: CalendarDay = .today()
    ) -> Roadmap {
        let windows = layOut(groups, today: today)
        let index = Dictionary(windows.enumerated().map { ($1.group.title, $0) }, uniquingKeysWith: { first, _ in first })

        var kids: [String: [Child]] = [:]
        for child in children { kids[child.parentId, default: []].append(child) }
        let epicIds = Set(epics.compactMap(\.contentId))

        /// Milestones of an epic's whole tree, sub-epics included: those of the work still open, and of all of it.
        func milestones(under id: String, seen: inout Set<String>) -> (open: Set<String>, all: Set<String>) {
            guard seen.insert(id).inserted else { return ([], []) }
            var open = Set<String>()
            var all = Set<String>()
            for child in kids[id] ?? [] {
                if let title = child.milestone {
                    all.insert(title)
                    if !child.done { open.insert(title) }
                }
                let below = milestones(under: child.contentId, seen: &seen)
                open.formUnion(below.open)
                all.formUnion(below.all)
            }
            return (open, all)
        }

        var made: [Row] = []
        for epic in epics {
            guard let id = epic.contentId else { continue }
            var seen = Set<String>()
            let found = milestones(under: id, seen: &seen)
            // An epic runs where its work is still to do; once all of it is done, where it was done.
            var titles = found.open.isEmpty ? found.all : found.open
            if let own = milestoneOfEpic[id] { titles.insert(own) }
            let covered = titles.compactMap { index[$0] }.sorted()
            if doneEpics.contains(id), covered.isEmpty { continue }

            var perMilestone: [String: Count] = [:]
            let direct = kids[id] ?? []
            for child in direct {
                let key = child.milestone ?? ""
                var count = perMilestone[key] ?? Count(done: 0, total: 0)
                count.total += 1
                if child.done { count.done += 1 }
                perMilestone[key] = count
            }
            let done = direct.isEmpty ? epic.subCompleted : direct.filter(\.done).count
            let total = direct.isEmpty ? epic.subTotal : direct.count
            made.append(Row(
                epic: epic, depth: 0, runs: runs(covered), done: done, total: total, perMilestone: perMilestone,
                next: covered.first.map { windows[$0].group.title }
            ))
        }

        // Planned epics by the first stretch they cover, then the last; an epic of another epic shown hangs under it.
        let position = Dictionary(epics.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        func order(_ a: Row, _ b: Row) -> Bool {
            let fa = a.runs.first?.lowerBound ?? .max, fb = b.runs.first?.lowerBound ?? .max
            if fa != fb { return fa < fb }
            let la = a.runs.last?.upperBound ?? .max, lb = b.runs.last?.upperBound ?? .max
            if la != lb { return la < lb }
            return (position[a.epic.id] ?? 0) < (position[b.epic.id] ?? 0)
        }
        func nest(_ rows: [Row]) -> [Row] {
            let shown = Set(rows.compactMap(\.epic.contentId))
            var under: [String: [Row]] = [:]
            var top: [Row] = []
            for row in rows {
                if let parent = row.epic.parentId, shown.contains(parent), epicIds.contains(parent), parent != row.epic.contentId {
                    under[parent, default: []].append(row)
                } else {
                    top.append(row)
                }
            }
            var result: [Row] = []
            var placed = Set<String>()
            func place(_ row: Row, depth: Int) {
                guard placed.insert(row.epic.id).inserted else { return }
                var row = row
                row.depth = depth
                result.append(row)
                for child in (under[row.epic.contentId ?? ""] ?? []).sorted(by: order) { place(child, depth: min(depth + 1, 1)) }
            }
            for row in top.sorted(by: order) { place(row, depth: 0) }
            // Epics in a loop of parents, which stale data might show.
            for row in rows.sorted(by: order) { place(row, depth: 0) }
            return result
        }
        return Roadmap(
            windows: windows,
            rows: nest(made.filter(\.isPlanned)),
            later: nest(made.filter { !$0.isPlanned })
        )
    }

    /// Open milestones as stretches of time: each starts the day after the one before is due. The first starts
    /// where the last closed milestone ended, or a few weeks before it is due.
    static func layOut(_ groups: [MilestoneGroup], today: CalendarDay) -> [Window] {
        let open = groups.filter(\.isOpen)
        let dated = open.filter { $0.due != nil }.sorted { $0.due! < $1.due! }
        let undated = open.filter { $0.due == nil }
        var windows: [Window] = []
        let firstDue = dated.first?.due ?? today
        let lastClosed = groups.filter { !$0.isOpen }.compactMap(\.due).filter { $0 < firstDue }.max()
        var start = lastClosed.map { $0.adding(days: 1) } ?? min(today, firstDue.adding(days: -leadIn))
        for group in dated {
            let end = group.due!
            windows.append(Window(group: group, start: min(start, end), end: end, undated: false))
            start = end.adding(days: 1)
        }
        if dated.isEmpty { start = today }
        for group in undated {
            let end = start.adding(days: undatedLength - 1)
            windows.append(Window(group: group, start: start, end: end, undated: true))
            start = end.adding(days: 1)
        }
        return windows
    }

    /// Sorted window indices as runs of neighbours: [0, 3, 4] → [0...0, 3...4].
    static func runs(_ indices: [Int]) -> [ClosedRange<Int>] {
        var result: [ClosedRange<Int>] = []
        for index in indices {
            if let last = result.last, last.upperBound + 1 == index {
                result[result.count - 1] = last.lowerBound...index
            } else if result.last?.contains(index) != true {
                result.append(index...index)
            }
        }
        return result
    }

    /// The first and last day the timeline shows: a little before the first stretch and after the last.
    public var span: ClosedRange<CalendarDay>? {
        guard let first = windows.first, let last = windows.last else { return nil }
        return first.start.adding(days: -6)...last.end.adding(days: 14)
    }
}
