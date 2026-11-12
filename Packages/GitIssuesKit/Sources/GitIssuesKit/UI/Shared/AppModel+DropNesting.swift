import SwiftUI

/// Dropping issues onto another issue makes them its sub-issues: on the Mac's lists, boards and My Issues, and on
/// iPhone and iPad. What may go under what follows what GitHub takes, so a drop isn't offered where GitHub would
/// refuse it. Nesting changes nothing else: the dropped issues keep their status and their place on their boards.
extension AppModel {
    /// GitHub takes at most this many sub-issues under one issue…
    nonisolated static let subIssueLimit = 100
    /// …and nests sub-issues at most this many levels deep, the issue at the top counting as the first.
    nonisolated static let subIssueLevels = 8

    /// Those of `dragged` that a drop onto `target` makes its sub-issues: issues (not pull requests or drafts) on
    /// boards you can change, other than `target` itself, not one of the issues above it (it would go under itself),
    /// and not under it already. None when `target` can't take them all: GitHub keeps at most 100 sub-issues under an
    /// issue and nests them at most eight levels deep.
    func nestable(_ dragged: [Item], under target: Item) -> [Item] {
        guard canRelate(target), canChangeRelations(of: target), let parentId = target.contentId else { return [] }
        let above = ancestors(of: target)
        var seen = Set<String>()
        let children = dragged.filter { child in
            guard canRelate(child), canChangeRelations(of: child), let id = child.contentId, seen.insert(id).inserted else { return false }
            return id != parentId && child.parentId != parentId && !above.contains(id)
        }
        guard !children.isEmpty, target.subTotal + children.count <= Self.subIssueLimit else { return [] }
        // The target's level, counted from the top, and how many levels each child brings along under it.
        let level = above.count + 1
        let spans = levelsSpanned(by: children.compactMap(\.contentId))
        guard spans.values.allSatisfy({ level + $0 <= Self.subIssueLevels }) else { return [] }
        return children
    }

    /// Whether an issue can be picked up to go under another one: an issue (not a pull request or draft) on a board you
    /// can change, or on none. Lists that keep their order, such as My Issues, lift only such issues.
    func canNestSomewhere(_ item: Item) -> Bool {
        canRelate(item) && canChangeRelations(of: item)
    }

    /// Whether dropping `dragged` onto `target` would make any of them its sub-issue.
    func canNest(_ dragged: [Item], under target: Item) -> Bool {
        !nestable(dragged, under: target).isEmpty
    }

    /// Makes the issues dropped onto `target` its sub-issues, as picking it as their parent does, and says so with a
    /// way to take it back. They keep their status and their place on their boards: a sub-issue often stands
    /// elsewhere than its parent, and a drop that also moved it would do two things where it shows one.
    func nest(_ dragged: [Item], under target: Item) {
        let children = nestable(dragged, under: target)
        guard !children.isEmpty, let parentId = target.contentId else { return }
        // Back under the parent each had, or under none; GitHub has the new parent once these are sent.
        let undo: [Mutation] = children.compactMap { child in
            child.summary.map { summary in
                .setParent(.init(
                    child: summary, parentId: child.parentId, parentNumber: child.parentNumber, parentTitle: child.parentTitle,
                    base: parentId
                ))
            }
        }
        setParent(of: children, to: target)
        status.post(Notice(
            title: String(localized: .issuesNestedUnder(count: children.count, number: target.displayNumber)),
            message: target.title,
            action: .undo(undo)
        ))
    }

    /// Whether you may change an issue's parent or sub-issues here: on a board you can only read you can't, as you
    /// can't move its cards. An issue on none of your boards GitHub decides about.
    func canChangeRelations(of item: Item) -> Bool {
        guard let projectId = item.projectId else { return true }
        return projects.first { $0.id == projectId }?.viewerCanUpdate == true
    }

    /// How many levels each of the issues spans with what hangs under it, by node id: 1 for one without sub-issues.
    private func levelsSpanned(by ids: [String]) -> [String: Int] {
        var children: [String: [String]] = [:]
        for item in allItems {
            if let id = item.contentId, let parent = item.parentId, parent != id { children[parent, default: []].append(id) }
        }
        var known: [String: Int] = [:]
        func levels(_ id: String, _ path: Set<String>) -> Int {
            if let levels = known[id] { return levels }
            // A loop in stale data counts no further.
            let below = (children[id] ?? []).filter { !path.contains($0) }.map { levels($0, path.union([$0])) }.max() ?? 0
            known[id] = below + 1
            return below + 1
        }
        return Dictionary(ids.map { ($0, levels($0, [$0])) }, uniquingKeysWith: max)
    }
}
