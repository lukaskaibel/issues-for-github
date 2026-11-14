import Foundation

/// An issue the app knows only from another one's page, as one of its sub-issues or an issue it is blocked by or
/// blocks, made into an issue of its own for that page's rows: they are drawn as every other row of issues is, with
/// what is known of it. Such an issue is on none of your boards and can't be changed from the row, only opened on
/// GitHub, and closed or opened again.
extension Item {
    static let standInPrefix = "standin:"

    /// Whether this is such an issue rather than one the app has.
    var isStandIn: Bool { id.hasPrefix(Item.standInPrefix) }

    /// A sub-issue: its number, title and state, its people and milestone, how far its own sub-issues are, and how
    /// many open issues it waits for as far as this device knows.
    init(standingInFor sub: SubIssue, blockedBy: Int) {
        self.init(
            id: Item.standInPrefix + sub.id, kind: .issue, position: Double(sub.position), contentId: sub.id,
            number: sub.number > 0 ? sub.number : nil, title: sub.title, body: "", state: sub.state,
            stateReason: sub.stateReason, url: sub.url, repo: sub.repo, createdAt: sub.createdAt,
            subTotal: sub.subTotal ?? 0, subCompleted: sub.subCompleted ?? 0, assignees: sub.assignees,
            blockedByCount: blockedBy, milestoneId: sub.milestoneId, milestoneTitle: sub.milestoneTitle
        )
    }

    /// An issue another one is blocked by or blocks.
    init(standingInFor link: LinkedIssue) {
        self.init(
            id: Item.standInPrefix + link.id, kind: .issue, position: Double(link.position), contentId: link.id,
            number: link.number > 0 ? link.number : nil, title: link.title, body: "", state: link.state,
            stateReason: link.stateReason, url: link.url, repo: link.repo
        )
    }
}

extension AppModel {
    /// The issue a sub-issue's row shows: the one the app has, else one made from what the parent's page knows.
    func rowItem(for sub: SubIssue) -> Item {
        item(contentId: sub.id) ?? Item(standingInFor: sub, blockedBy: openBlockers[sub.id]?.count ?? 0)
    }

    /// The same for an issue another one is blocked by or blocks.
    func rowItem(for link: LinkedIssue) -> Item {
        item(contentId: link.id) ?? Item(standingInFor: link)
    }
}

extension AppModel {
    /// Saves a description written on an issue's page, on every platform: into the latest copy of the issue, since the
    /// page may have been drawn before the last sync, also under the id GitHub gave an issue made here while it was
    /// being written; and only when it changed, so untouched text stays exactly as GitHub stores it, line endings
    /// included.
    func saveDescription(of item: Item, _ text: String) {
        guard let current = self.item(id: status.idRemaps[item.id] ?? item.id) else { return }
        guard text != Diff3.normalize(current.body) else { return }
        setBody(current, to: text)
    }
}

extension OutboxEntry {
    /// What the banner over an issue says about a change of its title or description that GitHub has changed too.
    var conflictMessage: LocalizedStringResource {
        if case .setTitle = mutation { return .conflictTitleEditedOnGitHub }
        return .conflictDescriptionEditedOnGitHub
    }

    /// GitHub's version of that text, shown beside one's own.
    var theirText: String? {
        switch mutation {
        case .setTitle(let m), .setBody(let m): m.theirs
        default: nil
        }
    }
}
