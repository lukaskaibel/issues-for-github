import SwiftUI

/// Planning: putting issues into milestones, making, changing and completing milestones, and epics.
extension AppModel {
    // MARK: Milestones of issues

    /// Puts issues into a milestone of their board, or takes them out of theirs with nil. A milestone exists per
    /// repository on GitHub, so where an issue's repository has none of that name yet, it is made there first, with
    /// the same date and description.
    func setMilestone(of items: [Item], to group: MilestoneGroup?) {
        perform(milestoneMutations(items, to: group), animated: true)
    }

    /// The changes that put `items` into `group`, or take them out of theirs.
    func milestoneMutations(_ items: [Item], to group: MilestoneGroup?) -> [Mutation] {
        var mutations: [Mutation] = []
        var made: [String: Milestone] = [:]
        var seen = Set<String>()
        for item in items where item.kind == .issue || item.kind == .pullRequest {
            guard let contentId = item.contentId, !item.isDetached, seen.insert(contentId).inserted else { continue }
            var target: Milestone?
            if let group {
                if let existing = group.milestone(inRepository: item.repoId) ?? item.repoId.flatMap({ made[$0] }) {
                    target = existing
                } else if let repoId = item.repoId, let repo = item.repo {
                    let template = group.milestones.first
                    let local = Milestone(
                        id: LocalID.make(), repoId: repoId, repo: repo, number: 0, title: group.title,
                        descr: template?.descr ?? "", dueOn: group.due?.string, state: "OPEN", closedAt: nil, url: nil
                    )
                    mutations.append(.createMilestone(.init(
                        milestoneId: local.id, repoId: repoId, repo: repo, title: local.title, dueOn: local.dueOn, descr: local.descr
                    )))
                    made[repoId] = local
                    target = local
                } else {
                    continue
                }
            }
            guard item.milestoneId != target?.id else { continue }
            mutations.append(.setMilestone(.init(
                contentId: contentId, isPullRequest: item.kind == .pullRequest, milestoneId: target?.id,
                milestoneTitle: target?.title, base: item.milestoneId
            )))
        }
        return mutations
    }

    private func perform(_ mutations: [Mutation], animated: Bool) {
        if animated {
            withAnimation(Theme.spring) { perform(mutations) }
        } else {
            perform(mutations)
        }
    }

    // MARK: Making and changing milestones

    /// The repository a board's new milestone is made in: the one most of its cards come from.
    func repositoryForNewMilestone(projectId: String) -> RepoRef? {
        let available = repos(projectId: projectId)
        guard let id = defaultRepoId(projectId: projectId) else { return available.first }
        return available.first { $0.id == id } ?? available.first
    }

    /// Makes a milestone and returns it as it shows until GitHub has made it.
    @discardableResult
    func createMilestone(projectId: String, title: String, due: CalendarDay?, descr: String) -> MilestoneGroup? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let repo = repositoryForNewMilestone(projectId: projectId) else { return nil }
        if let existing = milestoneGroup(projectId: projectId, title: trimmed), existing.isOpen { return existing }
        let id = LocalID.make()
        perform([.createMilestone(.init(
            milestoneId: id, repoId: repo.id, repo: repo.nameWithOwner, title: trimmed, dueOn: due?.string, descr: descr
        ))])
        return milestoneGroup(projectId: projectId, title: trimmed)
    }

    /// Changes every milestone of the group: GitHub keeps them per repository, the app shows them as one.
    func updateMilestone(_ group: MilestoneGroup, _ change: GitHubAPI.MilestoneChange) {
        perform(group.milestones.map { .updateMilestone(.init(milestoneId: $0.id, change: change)) })
    }

    /// Renames, redates or redescribes a milestone, following it on screen when its title changes.
    func editMilestone(_ group: MilestoneGroup, projectId: String, title: String, due: CalendarDay?, descr: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var change = GitHubAPI.MilestoneChange()
        if !trimmed.isEmpty, trimmed != group.title { change.title = trimmed }
        if due != group.due { change.dueOn = due?.string ?? "" }
        if descr != group.descr { change.descr = descr }
        guard change != GitHubAPI.MilestoneChange() else { return }
        // Before the change, which already updates what is on screen.
        if let title = change.title { milestoneMove = MilestoneMove(projectId: projectId, from: group.title, to: title) }
        updateMilestone(group, change)
        if let title = change.title, scope == .milestone(projectId: projectId, title: group.title) {
            select(.milestone(projectId: projectId, title: title))
        }
    }

    func setDue(_ group: MilestoneGroup, to day: CalendarDay?) {
        guard day != group.due else { return }
        updateMilestone(group, .init(dueOn: day?.string ?? ""))
    }

    /// The open milestone after this one, where its unfinished issues can go.
    func milestone(after group: MilestoneGroup, projectId: String) -> MilestoneGroup? {
        let open = openMilestoneGroups(projectId: projectId)
        guard let index = open.firstIndex(where: { $0.title == group.title }) else { return open.first }
        return open.indices.contains(index + 1) ? open[index + 1] : nil
    }

    /// The issues of a milestone on a board that aren't done, its epics included.
    func unfinished(projectId: String, milestone title: String) -> [Item] {
        allItems.filter { $0.projectId == projectId && milestoneTitle(of: $0) == title && !isDone($0) }
    }

    /// Closes a milestone, as Linear completes a release. What isn't done moves on to `next`, or stays.
    func completeMilestone(_ group: MilestoneGroup, projectId: String, moveTo next: MilestoneGroup?) {
        var mutations: [Mutation] = []
        // Undoing opens the milestone again and brings back what moved on.
        var undo: [Mutation] = group.milestones.filter(\.isOpen).map { .updateMilestone(.init(milestoneId: $0.id, change: .init(state: "OPEN"))) }
        if let next {
            let issues = unfinished(projectId: projectId, milestone: group.title)
            let moves = milestoneMutations(issues, to: next)
            mutations += moves
            undo += issues.compactMap { item -> Mutation? in
                guard let contentId = item.contentId, moves.contains(where: { $0.contentId == contentId }) else { return nil }
                return .setMilestone(.init(
                    contentId: contentId, isPullRequest: item.kind == .pullRequest, milestoneId: item.milestoneId,
                    milestoneTitle: milestoneTitle(of: item), base: nil
                ))
            }
        }
        mutations += group.milestones.filter(\.isOpen).map { .updateMilestone(.init(milestoneId: $0.id, change: .init(state: "CLOSED"))) }
        // Before the change, which already updates what is on screen.
        milestoneMove = MilestoneMove(projectId: projectId, from: group.title, to: next?.title)
        perform(mutations, animated: true)
        if scope == .milestone(projectId: projectId, title: group.title) {
            select(next.map { .milestone(projectId: projectId, title: $0.title) } ?? .project(projectId))
        }

        status.post(Notice(
            title: String(localized: .milestoneCompletedNotice(milestone: group.title)),
            message: next.map { String(localized: .unfinishedMovedTo(milestone: $0.title)) } ?? "",
            action: .undo(undo)
        ))
    }

    func reopenMilestone(_ group: MilestoneGroup) {
        updateMilestone(group, .init(state: "OPEN"))
    }

    // MARK: Epics

    /// Whether the issue can be made an epic or an ordinary issue again: issues you can change, not pull requests.
    func canMakeEpic(_ item: Item) -> Bool {
        canRelate(item) && item.repoId != nil && item.repo != nil
    }

    /// Makes issues epics, or ordinary issues again.
    func setEpic(_ items: [Item], _ isEpic: Bool) {
        var seen = Set<String>()
        let mutations = items.compactMap { item -> Mutation? in
            guard canMakeEpic(item), item.isEpic != isEpic, let contentId = item.contentId, seen.insert(contentId).inserted,
                  let repoId = item.repoId, let repo = item.repo else { return nil }
            return .setEpic(.init(contentId: contentId, repoId: repoId, repo: repo, isEpic: isEpic, label: epicLabel(repoId: repoId)))
        }
        perform(mutations, animated: true)
    }

    /// The label that makes an epic in a repository: its own if it has one, else the one the app will make.
    func epicLabel(repoId: String) -> LabelRef {
        labels(projectId: nil, repoId: repoId).first { Item.isEpicLabel($0.name) }
            ?? LabelRef(id: LocalID.prefix + "epic-label-\(repoId)", name: Item.epicLabelName, color: Item.epicLabelColor)
    }

    /// The issues an epic's milestone applies to: the epic and everything under it that isn't done.
    func plannedWithEpic(_ epic: Item) -> [Item] {
        guard let contentId = epic.contentId else { return [epic] }
        let below = descendants(of: [contentId]).subtracting([contentId])
        var seen = Set<String>()
        let issues = allItems.filter { item in
            guard let id = item.contentId, below.contains(id), !isDone(item) else { return false }
            return seen.insert(id).inserted
        }
        return [epic] + issues
    }

    /// Moves an epic and its unfinished issues into a milestone, or out of every milestone with nil. A message
    /// says how many moved, with a way to take it back.
    func moveEpic(_ epic: Item, to group: MilestoneGroup?, projectId: String) {
        let issues = plannedWithEpic(epic)
        let mutations = milestoneMutations(issues, to: group)
        guard !mutations.isEmpty else { return }
        // Back to where each issue was: the milestones it had, which exist already.
        let undo = issues.compactMap { item -> Mutation? in
            guard let contentId = item.contentId, item.milestoneId != nil || mutations.contains(where: { $0.contentId == contentId }) else { return nil }
            return .setMilestone(.init(
                contentId: contentId, isPullRequest: item.kind == .pullRequest, milestoneId: item.milestoneId,
                milestoneTitle: milestoneTitle(of: item), base: nil
            ))
        }
        perform(mutations, animated: true)
        let moved = mutations.filter { if case .setMilestone = $0 { true } else { false } }.count
        status.post(Notice(
            title: String(localized: group.map { .epicMovedToMilestone(milestone: $0.title) } ?? .epicMovedToNoMilestone),
            message: String(localized: .issuesMovedCount(count: moved)),
            action: .undo(undo)
        ))
    }

    /// Changes that start epics because `mutations` start work on one of their issues: an epic in the backlog or to
    /// do moves to its board's first column of work in progress. Only changes made here do this, as with parents.
    func epicStarts(after mutations: [Mutation]) -> (mutations: [Mutation], epics: [Item]) {
        guard startsEpics else { return ([], []) }
        var result: [Mutation] = []
        var started: [Item] = []
        var handled = Set<String>()
        for case .setField(let change) in mutations where change.kind == .status {
            guard let item = allItems.first(where: { $0.id == change.itemId }), !item.isEpic,
                  let option = options.first(where: { $0.id == change.optionId && $0.projectId == change.projectId && $0.kind == .status }),
                  option.statusCategory == .started,
                  let epic = epic(of: item), let epicId = epic.contentId, handled.insert(epicId).inserted else { continue }
            var changed = false
            for copy in allItems where copy.contentId == epicId && copy.isOnBoard {
                let category = statusOption(of: copy)?.statusCategory
                guard category == nil || category == .backlog || category == .unstarted,
                      let target = statusOptions(projectId: copy.projectId).first(where: { $0.statusCategory == .started }) else { continue }
                result += statusMutations(copy, target)
                changed = true
            }
            if changed { started.append(epic) }
        }
        return (result, started)
    }
}

/// Settings for epics: whether they start with their first issue.
struct EpicSettingsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Section {
            Toggle(.startEpicsSetting, isOn: $model.startsEpics)
        } header: {
            Text(.epics)
        } footer: {
            Text(.startEpicsFooter)
        }
    }
}

// MARK: - Dropping into planned groups

extension AppModel {
    /// Whether an issue can be dropped into a milestone's group by epic, or an epic into a roadmap's group by milestone.
    func canDropPlanned(_ item: Item, into kind: ListSection.Kind) -> Bool {
        switch kind {
        case .status:
            return true
        case .epic(let contentId):
            guard canRelate(item), !item.isEpic else { return false }
            let current = epic(of: item)?.contentId
            guard current != contentId else { return false }
            // Out of an epic only from right under it: an issue under another issue keeps that parent.
            if contentId == nil { return item.parentId != nil && item.parentId == current }
            return true
        case .milestone(let title):
            guard item.isEpic, let projectId = scopeProjectId else { return false }
            let row = (roadmap(projectId: projectId).rows + roadmap(projectId: projectId).later).first { $0.epic.id == item.id }
            return row?.next != title
        case .group(let key):
            return canDrop(item, into: key)
        case .mine:
            return false
        }
    }

    /// Drops an issue into an epic's group (it becomes a sub-issue of the epic), or an epic into a milestone's group
    /// on the roadmap (it and its unfinished issues go into that milestone).
    @discardableResult
    func dropPlanned(_ item: Item, into kind: ListSection.Kind, scope: Scope?) -> Bool {
        guard canDropPlanned(item, into: kind) else { return false }
        switch kind {
        case .status:
            return false
        case .epic(let contentId):
            setParent(of: [item], to: contentId.flatMap { issue(contentId: $0) })
            return true
        case .milestone(let title):
            guard let projectId = scope?.projectId else { return false }
            moveEpic(item, to: title.flatMap { milestoneGroup(projectId: projectId, title: $0) }, projectId: projectId)
            return true
        case .group(let key):
            let mutations = groupMutations(item, into: key)
            guard !mutations.isEmpty else { return false }
            withAnimation(Theme.spring) { perform(mutations) }
            return true
        case .mine:
            return false
        }
    }

    /// Drops several picked issues into such a group: those of them that can go there.
    @discardableResult
    func dropPlanned(_ items: [Item], into kind: ListSection.Kind, scope: Scope?) -> Bool {
        let items = items.filter { canDropPlanned($0, into: kind) }
        guard !items.isEmpty else { return false }
        switch kind {
        case .epic(let contentId):
            setParent(of: items, to: contentId.flatMap { issue(contentId: $0) })
            return true
        case .group(let key):
            let mutations = items.flatMap { groupMutations($0, into: key) }
            guard !mutations.isEmpty else { return false }
            withAnimation(Theme.spring) { perform(mutations) }
            return true
        case .status, .milestone, .mine:
            return items.map { dropPlanned($0, into: kind, scope: scope) }.contains(true)
        }
    }

    /// The + of a group: a new issue in that status, in that epic (and the milestone on screen), or a new epic in
    /// that milestone.
    func addIssue(in kind: ListSection.Kind, optionId: String?, sectionId: String? = nil) {
        switch kind {
        case .status:
            // The "No status" section makes an issue without one, as that column on the board does.
            overlay = .newIssue(statusId: optionId ?? (sectionId == BoardColumn.noStatusId ? sectionId : nil), parentItemId: nil)
        case .epic(let contentId):
            overlay = .newIssue(statusId: nil, parentItemId: contentId.flatMap { issue(contentId: $0)?.id })
        case .milestone(let title):
            newIssuePlan = NewIssuePlan(milestoneTitle: title, isEpic: true)
            overlay = .newIssue(statusId: nil, parentItemId: nil)
        case .group(let key):
            addIssue(in: key)
        case .mine:
            break
        }
    }
}
