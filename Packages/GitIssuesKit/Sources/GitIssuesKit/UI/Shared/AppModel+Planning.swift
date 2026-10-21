import GRDB
import SwiftUI

/// What milestones, epics and roadmaps derive from the data, worked out once per change of it: drawing a card asks
/// for its milestone and epic, and a board has hundreds of cards. Its readers read `dataVersion` first: a view that
/// got its answer from the cache would otherwise have read nothing observed, and not follow later changes.
struct PlanningCache {
    var milestonesById: [String: Milestone]?
    var groupsByProject: [String: [MilestoneGroup]] = [:]
    var groupsByRepository: [String: [MilestoneGroup]] = [:]
    var issuesByContentId: [String: Item]?
    var epicOf: [String: Item?] = [:]
    var roadmaps: [String: Roadmap] = [:]
    var epicsByProject: [String: [Item]] = [:]
    var subIssuesByParent: [String: [SubIssue]]?
    var childrenByParent: [String: [Item]]?
}

// MARK: - Reading milestones

extension AppModel {
    func milestone(id: String) -> Milestone? {
        _ = dataVersion
        if planningCache.milestonesById == nil {
            planningCache.milestonesById = Dictionary(milestones.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
        return planningCache.milestonesById?[id]
    }

    /// The title of an issue's milestone, also of one this device hasn't read.
    func milestoneTitle(of item: Item) -> String? {
        guard let id = item.milestoneId else { return nil }
        return milestone(id: id)?.title ?? item.milestoneTitle
    }

    /// A board's milestones, open and closed, in roadmap order. Milestones of the same title in its repositories are one.
    func milestoneGroups(projectId: String?) -> [MilestoneGroup] {
        guard let projectId else { return [] }
        _ = dataVersion
        if let cached = planningCache.groupsByProject[projectId] { return cached }
        let repoIds = Set(repos(projectId: projectId).map(\.id))
        let groups = MilestoneGroup.groups(milestones.filter { repoIds.contains($0.repoId) })
        planningCache.groupsByProject[projectId] = groups
        return groups
    }

    /// The milestones of one repository, for an issue on no board.
    func milestoneGroups(repoId: String?) -> [MilestoneGroup] {
        guard let repoId else { return [] }
        _ = dataVersion
        if let cached = planningCache.groupsByRepository[repoId] { return cached }
        let groups = MilestoneGroup.groups(milestones.filter { $0.repoId == repoId })
        planningCache.groupsByRepository[repoId] = groups
        return groups
    }

    func openMilestoneGroups(projectId: String?) -> [MilestoneGroup] {
        milestoneGroups(projectId: projectId).filter(\.isOpen)
    }

    func milestoneGroup(projectId: String, title: String) -> MilestoneGroup? {
        milestoneGroups(projectId: projectId).first { $0.title == title }
    }

    /// The milestones an issue can go into: its board's, or its repository's when it is on none.
    func milestoneGroups(for item: Item) -> [MilestoneGroup] {
        item.projectId.map { milestoneGroups(projectId: $0) } ?? milestoneGroups(repoId: item.repoId)
    }

    /// The milestone an issue is in, as a group of its board.
    func milestoneGroup(of item: Item) -> MilestoneGroup? {
        guard let title = milestoneTitle(of: item) else { return nil }
        return milestoneGroups(for: item).first { $0.title == title }
    }

    /// The milestones the sidebar shows under a board: the next two open ones.
    func sidebarMilestones(projectId: String) -> [MilestoneGroup] {
        Array(openMilestoneGroups(projectId: projectId).prefix(2))
    }

    /// The milestone the board works towards: its first open one, as Linear marks it.
    func isCurrentMilestone(_ group: MilestoneGroup, projectId: String?) -> Bool {
        openMilestoneGroups(projectId: projectId).first?.title == group.title
    }

    /// Whether a board has anything to plan: milestones or epics. Its sidebar entry then opens to them.
    func hasPlanning(projectId: String) -> Bool {
        !openMilestoneGroups(projectId: projectId).isEmpty || !epics(projectId: projectId).isEmpty
    }

    // MARK: Reading epics

    /// An issue by its node id: its card on a board, or else as an issue on no board.
    func issue(contentId: String) -> Item? {
        _ = dataVersion
        if planningCache.issuesByContentId == nil {
            var index: [String: Item] = [:]
            for item in allItems {
                guard let id = item.contentId else { continue }
                if let kept = index[id], kept.isOnBoard { continue }
                index[id] = item
            }
            planningCache.issuesByContentId = index
        }
        return planningCache.issuesByContentId?[contentId]
    }

    /// The epic an issue belongs to: its parent, or the parent's parent, and so on, the nearest that is an epic.
    func epic(of item: Item) -> Item? {
        guard let contentId = item.contentId else { return nil }
        _ = dataVersion
        if let cached = planningCache.epicOf[contentId] { return cached }
        var found: Item?
        var seen: Set<String> = [contentId]
        var next = item.parentId
        while let id = next, seen.insert(id).inserted, let parent = issue(contentId: id) {
            if parent.isEpic {
                found = parent
                break
            }
            next = parent.parentId
        }
        planningCache.epicOf[contentId] = found
        return found
    }

    /// Whether the issue's board has epics to put it into.
    func hasEpics(_ item: Item) -> Bool {
        item.projectId.map { !epics(projectId: $0).isEmpty } ?? false
    }

    /// A board's epics in board order: those on it, and those its issues hang under even where the epic is on no board.
    func epics(projectId: String) -> [Item] {
        _ = dataVersion
        if let cached = planningCache.epicsByProject[projectId] { return cached }
        var result = allItems.filter { $0.projectId == projectId && $0.isEpic }
        var seen = Set(result.compactMap(\.contentId))
        for item in allItems where item.projectId == projectId && !item.isEpic {
            if let epic = epic(of: item), let id = epic.contentId, seen.insert(id).inserted { result.append(epic) }
        }
        planningCache.epicsByProject[projectId] = result
        return result
    }

    /// The sub-issues of an issue: those on boards and those its detail lists, each once.
    func children(of contentId: String) -> [Roadmap.Child] {
        _ = dataVersion
        if planningCache.subIssuesByParent == nil {
            let all = (try? db.reader.read { try SubIssue.fetchAll($0) }) ?? []
            planningCache.subIssuesByParent = Dictionary(grouping: all, by: \.parentId)
        }
        if planningCache.childrenByParent == nil {
            planningCache.childrenByParent = Dictionary(grouping: allItems.filter { $0.parentId != nil }, by: { $0.parentId! })
        }
        var result: [String: Roadmap.Child] = [:]
        for sub in planningCache.subIssuesByParent?[contentId] ?? [] {
            let title = sub.milestoneId.flatMap { milestone(id: $0)?.title } ?? sub.milestoneTitle
            result[sub.id] = Roadmap.Child(contentId: sub.id, parentId: contentId, milestone: title, done: sub.isClosed)
        }
        for item in planningCache.childrenByParent?[contentId] ?? [] {
            guard let id = item.contentId else { continue }
            if let known = result[id], !item.isOnBoard, known.milestone != nil { continue }
            result[id] = Roadmap.Child(
                contentId: id, parentId: contentId, milestone: milestoneTitle(of: item), done: isDone(item), isEpic: item.isEpic
            )
        }
        return Array(result.values).sorted { $0.contentId < $1.contentId }
    }

    /// A board's epics over its open milestones.
    func roadmap(projectId: String) -> Roadmap {
        _ = dataVersion
        if let cached = planningCache.roadmaps[projectId] { return cached }
        let epics = epics(projectId: projectId)
        var children: [Roadmap.Child] = []
        var seen = Set<String>()
        var queue = epics.compactMap(\.contentId)
        // Down every level: an epic's span includes the milestones of its sub-issues' sub-issues.
        while let id = queue.popLast() {
            guard seen.insert(id).inserted else { continue }
            let kids = self.children(of: id)
            children += kids
            queue += kids.map(\.contentId)
        }
        var own: [String: String] = [:]
        for epic in epics {
            if let id = epic.contentId, let title = milestoneTitle(of: epic) { own[id] = title }
        }
        let done = Set(epics.filter { isDone($0) }.compactMap(\.contentId))
        let roadmap = Roadmap.make(
            groups: milestoneGroups(projectId: projectId), epics: epics, children: children,
            milestoneOfEpic: own, doneEpics: done
        )
        planningCache.roadmaps[projectId] = roadmap
        return roadmap
    }

    // MARK: Lists

    /// A milestone's issues by epic, in the order of the epics on the board, and those of no epic last.
    func groupedByEpic(_ items: [Item]) -> [ListSection] {
        var byEpic: [String: [Item]] = [:]
        var order: [Item] = []
        var loose: [Item] = []
        for item in items {
            guard let epic = epic(of: item), let id = epic.contentId else {
                loose.append(item)
                continue
            }
            if byEpic[id] == nil { order.append(epic) }
            byEpic[id, default: []].append(item)
        }
        let position = Dictionary(allItems.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        order.sort { (position[$0.id] ?? .max) < (position[$1.id] ?? .max) }
        var result = order.map { epic -> ListSection in
            let id = epic.contentId ?? epic.id
            let (shown, nesting) = Nesting.arrange(byEpic[id] ?? [], folded: foldedParents)
            return ListSection(
                id: "epic:\(id)", title: epic.title, glyph: .none, option: nil, kind: .epic(contentId: id),
                detail: epic.displayNumber, items: shown, nesting: nesting
            )
        }
        if !loose.isEmpty {
            let (shown, nesting) = Nesting.arrange(loose, folded: foldedParents)
            result.append(ListSection(
                id: "no-epic", title: String(localized: .noEpic), glyph: .none, option: nil, kind: .epic(contentId: nil),
                items: shown, nesting: nesting
            ))
        }
        return result
    }

    /// The roadmap as a list: each epic under the open milestone that comes next for it, and those planned for none
    /// last, under "Later". Every open milestone shows, one without epics yet too: it is part of the plan, and a place
    /// to drop an epic.
    func epicsByMilestone(projectId: String) -> [ListSection] {
        let roadmap = roadmap(projectId: projectId)
        let byId = Dictionary((roadmap.rows + roadmap.later).map { ($0.epic.id, $0) }, uniquingKeysWith: { first, _ in first })
        let groups = roadmap.windows.map(\.group)
        var result: [ListSection] = []
        let today = CalendarDay.today()
        for group in groups {
            let epics = roadmap.rows.filter { $0.next == group.title }.map(\.epic)
            let (shown, nesting) = Nesting.arrange(epics, folded: foldedParents)
            result.append(ListSection(
                id: "milestone:\(group.title)", title: group.title, glyph: .none, option: nil, kind: .milestone(title: group.title),
                detail: group.due.map { $0.shortLabel(today: today) }, items: shown, nesting: nesting
            ))
        }
        let later = roadmap.later.map(\.epic).filter { byId[$0.id] != nil }
        if !later.isEmpty {
            let (shown, nesting) = Nesting.arrange(later, folded: foldedParents)
            result.append(ListSection(
                id: "no-milestone", title: String(localized: .later), glyph: .none, option: nil, kind: .milestone(title: nil),
                items: shown, nesting: nesting
            ))
        }
        return result
    }

    // MARK: Progress

    /// A milestone's issues on a board, done and in all.
    func progress(projectId: String, milestone title: String) -> Roadmap.Count {
        let items = items(in: .milestone(projectId: projectId, title: title))
        return Roadmap.Count(done: items.filter { isDone($0) }.count, total: items.count)
    }
}

extension AppModel {
    /// Whether an issue or pull request can be put into a milestone: one GitHub has, of a repository.
    func canHaveMilestone(_ item: Item) -> Bool {
        (item.kind == .issue || item.kind == .pullRequest) && item.contentId != nil && !item.isDetached && item.repoId != nil
    }

    /// The milestones an epic's issues are in, first to last: "5.3.2 → 5.7".
    func milestoneSpan(of epic: Item) -> String? {
        guard let projectId = epic.projectId else { return nil }
        let roadmap = roadmap(projectId: projectId)
        guard let row = (roadmap.rows + roadmap.later).first(where: { $0.epic.id == epic.id }),
              let first = row.runs.first?.lowerBound, let last = row.runs.last?.upperBound else { return nil }
        let start = roadmap.windows[first].group.title
        let end = roadmap.windows[last].group.title
        return start == end ? start : "\(start) → \(end)"
    }

    /// An epic's sub-issues by milestone, in the board's order of milestones, those in none last. A sub-issue on a
    /// board says its milestone itself; the others as the epic's detail read them.
    func subIssuesByMilestone(of epic: Item, _ subs: [SubIssue]) -> [(group: MilestoneGroup?, title: String?, subs: [SubIssue])] {
        let groups = milestoneGroups(for: epic)
        var byTitle: [String: [SubIssue]] = [:]
        var loose: [SubIssue] = []
        for sub in subs {
            let title = issue(contentId: sub.id).flatMap { milestoneTitle(of: $0) }
                ?? sub.milestoneId.flatMap { milestone(id: $0)?.title } ?? sub.milestoneTitle
            if let title { byTitle[title, default: []].append(sub) } else { loose.append(sub) }
        }
        var result: [(group: MilestoneGroup?, title: String?, subs: [SubIssue])] = []
        for group in groups.sorted(by: MilestoneGroup.precedes) where byTitle[group.title] != nil {
            result.append((group, group.title, byTitle.removeValue(forKey: group.title) ?? []))
        }
        // Milestones of another board or repository.
        for (title, subs) in byTitle.sorted(by: { $0.key.localizedStandardCompare($1.key) == .orderedAscending }) {
            result.append((nil, title, subs))
        }
        if !loose.isEmpty { result.append((nil, nil, loose)) }
        return result
    }
}
