import Foundation

/// The GitHub issue stays the same when a project card disappears or receives its server ID.
struct IssueReference: Hashable, Sendable {
    var itemId: String
    var contentId: String?
    var projectId: String?

    init(_ item: Item) {
        itemId = item.id
        contentId = item.contentId
        projectId = item.projectId
    }

    /// Editors belong to the issue, rather than to a project card that may be removed or acknowledged.
    func viewID(remaps: [String: String]) -> String {
        let identity = contentId ?? itemId
        return remaps.keys.filter { $0.hasPrefix(LocalID.prefix) && remaps[$0] == identity }.min() ?? identity
    }

    /// An acknowledgement can arrive before the database observation that contains its replacement card.
    static func observedRemaps(_ remaps: [String: String], in items: [Item]) -> [String: String] {
        let ids = Set(items.map(\.id))
        return remaps.filter { ids.contains($0.value) }
    }

    func remapping(_ remaps: [String: String]) -> Self {
        var reference = self
        reference.itemId = remaps[itemId] ?? itemId
        reference.contentId = contentId.map { remaps[$0] ?? $0 }
        return reference
    }

    func resolve(in items: [Item], projects: [Project], inbox: [InboxEntry] = []) -> Item? {
        if let exact = items.first(where: { $0.id == itemId }) { return exact }
        guard let contentId else { return nil }
        let copies = items.filter { $0.contentId == contentId }
        if let sameProject = copies.first(where: { $0.projectId == projectId }) { return sameProject }
        let open = Set(projects.filter { !$0.closed }.map(\.id))
        if let kept = copies.first(where: { $0.projectId.map(open.contains) == true })
            ?? copies.first(where: { $0.projectId == nil }) { return kept }
        // Only references opened from an Inbox-only issue may fall back to its notification. Ordinary deleted
        // cards must not reappear just because an old notification for the same issue remains in the Inbox.
        guard itemId.hasPrefix(Item.detachedPrefix) else { return nil }
        return inbox.first { $0.contentId == contentId }.flatMap { Item(detached: $0) }
    }

    static func replacements(from previous: [Item], to items: [Item], projects: [Project], remaps: [String: String] = [:]) -> [String: String] {
        let ids = Set(items.map(\.id))
        let removed = previous.filter { !ids.contains($0.id) && $0.contentId != nil }
        guard !removed.isEmpty else { return [:] }
        let copies = Dictionary(grouping: items.compactMap { item in item.contentId.map { ($0, item) } }, by: \.0)
        var replacements: [String: String] = [:]
        for old in removed {
            let reference = IssueReference(old).remapping(remaps)
            guard let contentId = reference.contentId,
                  let replacement = reference.resolve(in: copies[contentId, default: []].map(\.1), projects: projects) else { continue }
            replacements[old.id] = replacement.id
            // Creation acknowledgement can reach navigation before the matching item snapshot. Follow that
            // intermediate server card too when its membership has already been removed by a later local edit.
            if reference.itemId != old.id, !ids.contains(reference.itemId) { replacements[reference.itemId] = replacement.id }
        }
        return replacements
    }
}

extension AppModel {
    func item(referencedBy reference: IssueReference) -> Item? {
        let inbox = inboxEntries + selfAssignedEntries
        return reference.remapping(status.idRemaps).resolve(in: allItems, projects: projects, inbox: inbox)
            ?? reference.resolve(in: allItems, projects: projects, inbox: inbox)
    }

    func item(targetedBy target: ProjectFieldTarget) -> Item? {
        target.remapping(status.idRemaps).resolve(in: allItems) ?? target.resolve(in: allItems)
    }
}

/// A field editor must stay on its own project even if the issue also belongs to other projects.
struct ProjectFieldTarget: Hashable, Sendable, Identifiable {
    var issue: IssueReference
    var fieldId: String
    var id: String { "\(issue.contentId ?? issue.itemId):\(issue.projectId ?? "-"):\(fieldId)" }

    init(item: Item, fieldId: String) {
        issue = IssueReference(item)
        self.fieldId = fieldId
    }

    func remapping(_ remaps: [String: String]) -> Self {
        var target = self
        target.issue = issue.remapping(remaps)
        return target
    }

    func resolve(in items: [Item]) -> Item? {
        items.first { item in
            item.projectId == issue.projectId && (issue.contentId.map { item.contentId == $0 } ?? (item.id == issue.itemId))
        }
    }
}
