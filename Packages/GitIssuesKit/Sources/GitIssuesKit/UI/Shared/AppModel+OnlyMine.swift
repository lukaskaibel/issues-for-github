import SwiftUI

/// "Only My Issues" (⇧⌘M, the person button in the toolbar): every page of a board's issues shows only yours, by the
/// rule My Issues goes by (`isMine`), wherever you go, until you turn it off. It narrows what a page shows and nothing
/// else: views stay as they are on GitHub, and counts of what a board or milestone holds count everything.
extension AppModel {
    /// Whether "Only My Issues" narrows a scope: a board and its views, All Issues, a milestone and the roadmap. My
    /// Issues is yours already, and the Inbox is about notifications.
    nonisolated static func onlyMineApplies(to scope: Scope) -> Bool {
        switch scope {
        case .project, .allIssues, .milestone, .roadmap: true
        case .myIssues, .inbox: false
        }
    }

    /// Whether the page on screen shows only your issues.
    var narrowsToMine: Bool {
        onlyMine && scope.map(Self.onlyMineApplies) == true
    }

    /// The ids of everything yours (`isMine`), epics too.
    var mineIds: Set<String> {
        _ = dataVersion
        if let cached = mineIdsCache { return cached }
        guard let login = viewer?.login else { return [] }
        let solo = Self.soloProjectIds(allItems, login: login)
        let ids = Set(allItems.lazy.filter { Self.isMine($0, login: login, solo: solo) }.map(\.id))
        mineIdsCache = ids
        return ids
    }

    /// The epics the roadmap keeps with "Only My Issues" on: those that are yours or hold an issue of yours, and the
    /// epics above them, so an epic shown under another still has it.
    var mineEpicIds: Set<String> {
        _ = dataVersion
        if let cached = mineEpicIdsCache { return cached }
        let mine = mineIds
        var result = Set<String>()
        for item in allItems where mine.contains(item.id) {
            var next: Item? = item.isEpic ? item : epic(of: item)
            while let found = next, result.insert(found.id).inserted {
                next = epic(of: found)
            }
        }
        mineEpicIdsCache = result
        return result
    }

    /// A page's issues as "Only My Issues" leaves them: yours, and those you took yourself off while on the page, which
    /// stay until you go elsewhere, as Mail keeps a message you read in its Unread filter.
    func keepingMine(_ items: [Item], in scope: Scope) -> [Item] {
        guard onlyMine, Self.onlyMineApplies(to: scope) else { return items }
        let mine: Set<String> = if case .roadmap = scope { mineEpicIds } else { mineIds }
        return items.filter { mine.contains($0.id) || keptMineIds.contains($0.id) }
    }

    /// The roadmap as it shows: with "Only My Issues" on, the epics that hold something of yours (`mineEpicIds`).
    func shownRoadmap(projectId: String) -> Roadmap {
        var roadmap = roadmap(projectId: projectId)
        guard onlyMine else { return roadmap }
        let mine = mineEpicIds
        let kept = keptMineIds
        roadmap.rows = roadmap.rows.filter { mine.contains($0.epic.id) || kept.contains($0.epic.id) }
        roadmap.later = roadmap.later.filter { mine.contains($0.epic.id) || kept.contains($0.epic.id) }
        return roadmap
    }

    /// Whether "Only My Issues" leaves a page empty that has issues of others: the page then says so, with a way to
    /// show them, rather than that it has none.
    func onlyMineHidesEverything(in scope: Scope) -> Bool {
        guard onlyMine, Self.onlyMineApplies(to: scope) else { return false }
        _ = dataVersion
        if let cached = onlyMineHidesCache[scope] { return cached }
        let hides: Bool
        if case .roadmap(let projectId) = scope {
            let shown = shownRoadmap(projectId: projectId)
            let all = roadmap(projectId: projectId)
            hides = shown.rows.isEmpty && shown.later.isEmpty && !(all.rows.isEmpty && all.later.isEmpty)
        } else {
            hides = items(in: scope).isEmpty && !everyItem(in: scope).isEmpty
        }
        onlyMineHidesCache[scope] = hides
        return hides
    }

    /// Whether the page on screen shows fewer issues than it has: Only My Issues, or a filter of its view or of My
    /// Issues. The filter button is filled in the accent colour while it does, as Mail's.
    var pageIsNarrowed: Bool {
        scope.map(isNarrowed) ?? false
    }

    /// Whether a page shows fewer issues than it has (`pageIsNarrowed`), for the iPhone's and iPad's screens, each of
    /// which has its own page.
    func isNarrowed(_ scope: Scope) -> Bool {
        if onlyMine, Self.onlyMineApplies(to: scope) { return true }
        switch scope {
        case .myIssues: return !mineFilter.isEmpty
        case .project(let id): return currentView(projectId: id).map { !filter(of: $0).isEmpty } ?? false
        default: return false
        }
    }

    /// Whether the page's filter or display was changed here and not saved to the view, or My Issues' display isn't
    /// as it comes: the filter button carries a dot, as Display's did.
    var pageChangedForYou: Bool {
        if scope == .myIssues { return !mineDisplay.optionsAreDefault }
        guard let view = currentView else { return false }
        return filterChanged(view) || displayDiffers(view)
    }

    /// Whether the filter button has anything to offer on the page on screen: every page of issues, not the Inbox.
    var hasFilterPanel: Bool {
        guard let scope, scope != .inbox else { return false }
        return scope == .myIssues || viewer != nil || currentView != nil
    }

    /// Lets the issues kept on a page go, for iPhone and iPad, whose screens keep no page of their own in the model.
    func forgetKeptMine() {
        guard !keptMineIds.isEmpty else { return }
        keptMineIds = []
        rebuild()
    }

    /// When you take yourself off an issue with "Only My Issues" on, it stays where it is until you go elsewhere.
    func keepIfLeavingMine(_ item: Item, unassigning person: Person) {
        guard onlyMine, person.id == viewer?.person.id else { return }
        keptMineIds.insert(item.id)
    }
}
