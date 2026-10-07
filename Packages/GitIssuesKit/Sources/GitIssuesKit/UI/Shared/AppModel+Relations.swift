import SwiftUI

/// How issues hang together on GitHub: parents and sub-issues, and issues that block each other.
extension AppModel {
    /// Issues can have a parent, sub-issues and blockers; pull requests and drafts can't, and issues seen only in
    /// the Inbox aren't kept here to change.
    func canRelate(_ item: Item) -> Bool {
        item.kind == .issue && item.contentId != nil && !item.isDetached
    }

    // MARK: Reading

    /// What the issue is blocked by, or what it blocks, as far as its detail was read.
    func links(of item: Item, _ relation: LinkedIssue.Relation) -> [LinkedIssue] {
        guard let contentId = item.contentId else { return [] }
        return links.filter { $0.issueId == contentId && $0.relation == relation }
    }

    /// Whether `issueId` is blocked by `blockerId`, from either issue's relations.
    func isBlocked(_ issueId: String, by blockerId: String) -> Bool {
        links.contains { link in
            (link.issueId == issueId && link.relation == .blockedBy && link.id == blockerId)
                || (link.issueId == blockerId && link.relation == .blocking && link.id == issueId)
        }
    }

    /// The issue's parent, its parent and so on, as far as this device knows them.
    func ancestors(of item: Item) -> Set<String> {
        var result = Set<String>()
        var next = item.parentId
        while let id = next, result.insert(id).inserted {
            next = self.item(contentId: id)?.parentId
        }
        return result
    }

    /// The issues themselves and everything under them: their sub-issues, theirs, and so on.
    func descendants(of ids: Set<String>) -> Set<String> {
        var children: [String: [String]] = [:]
        for item in allItems {
            if let parent = item.parentId, let id = item.contentId { children[parent, default: []].append(id) }
        }
        var result = ids
        var next = Array(ids)
        while let id = next.popLast() {
            for child in children[id] ?? [] where result.insert(child).inserted { next.append(child) }
        }
        return result
    }

    /// The issue's sub-issues: those its detail lists and those whose card names it.
    func subIssueIds(of item: Item) -> Set<String> {
        guard let contentId = item.contentId else { return [] }
        var ids = (try? db.reader.read { try String.fetchSet($0, sql: "SELECT id FROM subIssue WHERE parentId = ?", arguments: [contentId]) }) ?? []
        ids.formUnion(allItems.filter { $0.parentId == contentId }.compactMap(\.contentId))
        return ids
    }

    /// Issues to pick as a parent, a sub-issue or a blocker of `item`: every issue this device knows, each once.
    /// Those on the same board come first, then those of the same repository, then the rest; open before closed.
    func relatableIssues(near item: Item) -> [Item] {
        var copies: [String: Item] = [:]
        var order: [String] = []
        for candidate in allItems where candidate.kind == .issue {
            guard let contentId = candidate.contentId, contentId != item.contentId else { continue }
            if let kept = copies[contentId] {
                // An issue on two boards is listed once, as the copy on this issue's board.
                if kept.projectId != item.projectId, candidate.projectId == item.projectId { copies[contentId] = candidate }
            } else {
                copies[contentId] = candidate
                order.append(contentId)
            }
        }
        func rank(_ candidate: Item) -> Int {
            let place = item.projectId != nil && candidate.projectId == item.projectId ? 0 : candidate.repoId == item.repoId ? 1 : 2
            return (candidate.isClosed ? 3 : 0) + place
        }
        return order.enumerated()
            .compactMap { index, id in copies[id].map { (index, $0) } }
            .sorted { a, b in
                let ra = rank(a.1), rb = rank(b.1)
                return ra != rb ? ra < rb : a.0 < b.0
            }
            .map(\.1)
    }

    /// Reads an issue's sub-issues and relations from GitHub now, for a picker that shows them checked.
    func loadRelations(for item: Item) {
        guard canRelate(item), !item.isLocalOnly, let contentId = item.contentId else { return }
        let engine = self.engine
        Task { try? await engine.loadIssueDetail(contentId: contentId) }
    }

    // MARK: Changing

    /// Makes issues sub-issues of `parent`, or takes them out of their parent with nil. An issue that has another
    /// parent moves, as on GitHub; an issue can't go under itself or under one of its own sub-issues.
    func setParent(of children: [Item], to parent: Item?) {
        guard parent.map(canRelate) ?? true else { return }
        let parentId = parent?.contentId
        let above = parent.map { ancestors(of: $0) } ?? []
        var seen = Set<String>()
        let mutations = children.compactMap { child -> Mutation? in
            guard canRelate(child), let summary = child.summary, seen.insert(summary.contentId).inserted,
                  child.parentId != parentId, summary.contentId != parentId, !above.contains(summary.contentId) else { return nil }
            return .setParent(.init(
                child: summary, parentId: parentId, parentNumber: parent?.number, parentTitle: parent?.title, base: child.parentId
            ))
        }
        withAnimation(Theme.spring) { perform(mutations) }
    }

    /// Takes a sub-issue out of its parent, also one that is on none of your boards.
    func removeFromParent(_ sub: SubIssue) {
        if let item = item(contentId: sub.id) {
            setParent(of: [item], to: nil)
            return
        }
        withAnimation(Theme.spring) {
            perform([.setParent(.init(child: sub.summary, parentId: nil, base: sub.parentId))])
        }
    }

    /// Marks issues as blocked by `blocker`, or takes that away when all of them are blocked by it already.
    func toggleBlocked(_ issues: [Item], by blocker: Item) {
        guard canRelate(blocker), let other = blocker.summary else { return }
        let pairs = issues.filter(canRelate).compactMap { issue in
            issue.contentId == other.contentId ? nil : issue.summary.map { (blocked: $0, blocker: other) }
        }
        let all = pairs.allSatisfy { isBlocked($0.blocked.contentId, by: $0.blocker.contentId) }
        setBlocked(pairs, !all)
    }

    /// Marks `blocked` as blocked by each of `issues`, or takes that away when it is blocked by all of them already.
    func toggleBlocking(_ issues: [Item], blocks blocked: Item) {
        guard canRelate(blocked), let other = blocked.summary else { return }
        let pairs = issues.filter(canRelate).compactMap { issue in
            issue.contentId == other.contentId ? nil : issue.summary.map { (blocked: other, blocker: $0) }
        }
        let all = pairs.allSatisfy { isBlocked($0.blocked.contentId, by: $0.blocker.contentId) }
        setBlocked(pairs, !all)
    }

    /// Takes a relation away, from the issue whose relations list it.
    func removeLink(_ link: LinkedIssue, of item: Item) {
        guard let summary = item.summary else { return }
        let pair = link.relation == .blockedBy ? (blocked: summary, blocker: link.summary) : (blocked: link.summary, blocker: summary)
        setBlocked([pair], false)
    }

    private func setBlocked(_ pairs: [(blocked: IssueSummary, blocker: IssueSummary)], _ isBlocked: Bool) {
        let mutations = pairs.compactMap { pair -> Mutation? in
            let current = self.isBlocked(pair.blocked.contentId, by: pair.blocker.contentId)
            guard current != isBlocked else { return nil }
            return .setBlocking(.init(blocked: pair.blocked, blocker: pair.blocker, isBlocked: isBlocked, base: current))
        }
        withAnimation(Theme.spring) { perform(mutations) }
    }
}

extension SubIssue {
    var summary: IssueSummary {
        IssueSummary(
            contentId: id, number: number > 0 ? number : nil, title: title, state: state, stateReason: stateReason,
            repo: repo, url: url, assignees: assignees
        )
    }
}

extension LinkedIssue {
    var summary: IssueSummary {
        IssueSummary(
            contentId: id, number: number > 0 ? number : nil, title: title, state: state, stateReason: stateReason,
            repo: repo, url: url
        )
    }

    var displayNumber: String { number > 0 ? "#\(number)" : "New" }
}
