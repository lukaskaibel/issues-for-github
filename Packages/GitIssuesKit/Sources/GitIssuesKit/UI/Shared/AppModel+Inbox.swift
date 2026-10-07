import GRDB
import SwiftUI

/// The last archive or unsubscribe, kept for a few seconds so it can be taken back: GitHub can't bring a
/// notification back once it is done, so the change waits in the queue until the moment has passed.
struct InboxUndo: Identifiable, Equatable {
    var id = UUID()
    /// "Archived #14", "Unsubscribed from #9" …
    var message: String
    var threadIds: [String]
    var outboxIds: [Int64]
    /// Each entry's personal record before the change, to put back.
    var records: [String: PersonalStore.Record?]
    /// Each entry's unread state before the change.
    var unread: [String: Bool]
}

/// A request to open the snooze menu, from a key or a menu that can't open it themselves.
struct InboxSnoozeRequest: Equatable {
    var token = 0
    /// Straight to choosing a date and time.
    var pickDate = false
}

/// The Inbox: GitHub's notifications about issues and pull requests, with what happened on each, read and archived
/// on GitHub so every device and github.com agree. Snoozes and "marked unread" are personal and live in iCloud.
extension AppModel {
    // MARK: What shows

    /// Entries in a half of the Inbox, newest first: not archived, not snoozed.
    func inbox(_ bucket: InboxBucket) -> [InboxEntry] {
        let now = inboxClock
        return inboxEntries.filter { $0.bucket == bucket && isShown($0, now: now) }
    }

    /// The half on screen. Watching is offered only while it has something.
    var currentInboxBucket: InboxBucket {
        inboxBucket == .watching && !inbox(.watching).isEmpty ? .watching : .forYou
    }

    var visibleInbox: [InboxEntry] {
        inbox(currentInboxBucket)
    }

    /// Unread entries in For you: the number at the Inbox in the sidebar, on the tab and on the app icon.
    var inboxUnreadCount: Int {
        inbox(.forYou).filter(isUnread).count
    }

    #if os(macOS)
    /// What the Dock icon shows: the unread count, unless switched off in Settings.
    var dockBadge: String? {
        guard showsDockBadge, signedIn else { return nil }
        let count = inboxUnreadCount
        return count > 0 ? "\(count)" : nil
    }
    #endif

    private func isShown(_ entry: InboxEntry, now: Date) -> Bool {
        if entry.isArchived { return false }
        if let snooze = personal.snooze(entry.id), now < snooze.until, entry.updatedAt <= snooze.threadUpdatedAt { return false }
        return true
    }

    /// Unread on GitHub, marked unread here, or back from a snooze and not opened since.
    func isUnread(_ entry: InboxEntry) -> Bool {
        if entry.unread { return true }
        if let marked = personal.markedUnread(entry.id), entry.updatedAt <= marked { return true }
        if let snooze = personal.snooze(entry.id), inboxClock >= snooze.until, entry.updatedAt <= snooze.threadUpdatedAt { return true }
        return false
    }

    var inboxSelected: InboxEntry? {
        inboxSelectedId.flatMap { id in inboxEntries.first { $0.id == id } }
    }

    func inboxEntry(id: String) -> InboxEntry? {
        inboxEntries.first { $0.id == id }
    }

    /// What the Inbox shows of an entry: the row's line, with names as the people have set them.
    func inboxSummary(_ entry: InboxEntry) -> InboxSummary {
        entry.summary(viewer: viewer?.login)
    }

    /// The entries an action applies to: the picked ones when the entry is among them.
    func inboxTargets(for entry: InboxEntry) -> [InboxEntry] {
        guard inboxPicked.count > 1, inboxPicked.contains(entry.id) else { return [entry] }
        return visibleInbox.filter { inboxPicked.contains($0.id) }
    }

    // MARK: The issue behind an entry

    /// The card on a board, or, for an issue on none of them, the issue as a card of no project.
    func inboxItem(for entry: InboxEntry) -> Item? {
        if let contentId = entry.contentId, let card = boardItem(contentId: contentId) { return card }
        return Item(detached: entry)
    }

    /// An issue can be on several boards; the one on screen or opened last wins.
    private func boardItem(contentId: String) -> Item? {
        let cards = allItems.filter { $0.contentId == contentId }
        guard cards.count > 1 else { return cards.first }
        let preferred = currentProjectId ?? UserDefaults.standard.string(forKey: "selectedProject")
        return cards.first { $0.projectId == preferred } ?? cards.first
    }

    /// The entry for the issue behind an Inbox-only card.
    func detachedItem(id: String) -> Item? {
        guard id.hasPrefix(Item.detachedPrefix) else { return nil }
        let contentId = String(id.dropFirst(Item.detachedPrefix.count))
        // Added to a board since: from now on it's that card.
        if let card = boardItem(contentId: contentId) { return card }
        return inboxEntries.first { $0.contentId == contentId }.flatMap { Item(detached: $0) }
    }

    /// Labels and people for an issue on no board, read from its repository once.
    func loadDetachedRepoMeta(_ item: Item) {
        guard item.isDetached, let repoId = item.repoId, detachedRepoMeta[repoId] == nil else { return }
        // A repository that is on some board has its labels and people already.
        if let known = repos.first(where: { $0.id == repoId && $0.metaLoadedAt != nil }) {
            detachedRepoMeta[repoId] = (known.labels, known.assignableUsers)
            return
        }
        let engine = self.engine
        Task {
            if let meta = try? await engine.repoMeta(repoId: repoId) {
                detachedRepoMeta[repoId] = (meta.labels, meta.users)
            }
        }
    }

    // MARK: Opening

    /// Pull to refresh in the Inbox: asks GitHub now and returns when the round is done.
    func refreshInboxAndWait() async {
        await engine.refreshInbox()
        await engine.syncNow()
    }

    /// The Inbox came on screen: ask GitHub for what's new right away.
    func inboxAppeared() {
        let engine = self.engine
        Task { await engine.refreshInbox() }
        if inboxSelectedId == nil || inboxSelected.map({ !visibleInbox.contains($0) }) ?? true {
            inboxSelectedId = nil
        }
        scheduleInboxWake()
    }

    /// Shows the entry's issue beside the list, and counts it as read, as GitHub and Linear do.
    func selectInboxEntry(_ entry: InboxEntry?) {
        inboxSelectedId = entry?.id
        guard let entry else { return }
        markRead([entry])
        if let item = inboxItem(for: entry) {
            loadDetachedRepoMeta(item)
            if !item.isDetached { loadRepoMeta(projectId: item.projectId) }
        }
    }

    /// J and K, and the arrow keys: the next or previous entry, which opens beside the list.
    func stepInbox(_ delta: Int) {
        let entries = visibleInbox
        guard !entries.isEmpty else { return }
        let next: InboxEntry
        if let index = entries.firstIndex(where: { $0.id == inboxSelectedId }) {
            next = entries[min(max(index + delta, 0), entries.count - 1)]
        } else {
            next = delta > 0 ? entries[0] : entries[entries.count - 1]
        }
        inboxPicked = []
        inboxPickAnchor = next.id
        selectInboxEntry(next)
        focusScrollToken += 1
    }

    /// J and K with an issue open full size from the Inbox: the next notification's issue, full size too, or back to
    /// the Inbox when that one isn't on a board.
    func stepInboxOpen(_ delta: Int, from item: Item) {
        let entries = visibleInbox
        guard let index = entries.firstIndex(where: { $0.id == inboxSelectedId }) ?? entries.firstIndex(where: { $0.contentId == item.contentId }) else { return }
        let target = min(max(index + delta, 0), entries.count - 1)
        guard target != index else { return }
        let next = entries[target]
        selectInboxEntry(next)
        if let card = inboxItem(for: next), !card.isDetached {
            open(card, replacingHistory: true)
        } else {
            closeDetail()
        }
    }

    /// After an entry left the list (archived, snoozed), the one that took its place, as Mail does.
    private func selectNeighbour(after removed: Set<String>, in before: [InboxEntry]) {
        guard let selected = inboxSelectedId, removed.contains(selected),
              let index = before.firstIndex(where: { $0.id == selected }) else { return }
        let remaining = before.filter { !removed.contains($0.id) }
        guard !remaining.isEmpty else {
            inboxSelectedId = nil
            return
        }
        // Shown beside the list means read, as in Mail.
        selectInboxEntry(remaining[min(index, remaining.count - 1)])
    }

    // MARK: Picking several (Mac and iPad)

    /// ⌘-click: adds the entry to the picked ones or takes it out.
    func toggleInboxPick(_ entry: InboxEntry) {
        if inboxPicked.isEmpty, let selected = inboxSelectedId, selected != entry.id { inboxPicked.insert(selected) }
        if inboxPicked.contains(entry.id) { inboxPicked.remove(entry.id) } else { inboxPicked.insert(entry.id) }
        inboxPickAnchor = entry.id
    }

    /// Shift-click: everything from the last click to this one.
    func extendInboxPick(to entry: InboxEntry) {
        let order = visibleInbox.map(\.id)
        let anchor = inboxPickAnchor ?? inboxSelectedId ?? entry.id
        guard let from = order.firstIndex(of: anchor), let to = order.firstIndex(of: entry.id) else { return }
        inboxPicked = Set(order[min(from, to)...max(from, to)])
    }

    // MARK: Reading

    func markRead(_ entries: [InboxEntry]) {
        var mutations: [Mutation] = []
        for entry in entries {
            personal.setMarkedUnread(entry.id, nil)
            if let snooze = personal.snooze(entry.id), inboxClock >= snooze.until { personal.setSnooze(entry.id, nil) }
            if entry.unread {
                mutations.append(.markThreadRead(.init(threadId: entry.id, updatedAt: entry.updatedAt, label: entry.label)))
            }
        }
        perform(mutations)
    }

    /// U: read or unread, following the first one. GitHub can't mark a notification unread, so that part is
    /// personal and kept in iCloud.
    func toggleRead(_ entries: [InboxEntry]) {
        guard let first = entries.first else { return }
        if isUnread(first) {
            markRead(entries)
        } else {
            for entry in entries { personal.setMarkedUnread(entry.id, entry.updatedAt) }
        }
    }

    /// ⌥U: everything in the half on screen.
    func markAllRead() {
        markRead(visibleInbox.filter(isUnread))
    }

    // MARK: Archiving

    /// E or ⌫: out of the Inbox, here and on GitHub, until something new happens. Can be undone for a few seconds.
    func archive(_ entries: [InboxEntry]) {
        guard !entries.isEmpty else { return }
        let message = entries.count == 1 ? "Archived \(entries[0].displayNumber(withRepo: false))" : "Archived \(entries.count) notifications"
        change(entries, message: message) { entry in
            [.archiveThread(.init(threadId: entry.id, updatedAt: entry.updatedAt, label: entry.label))]
        }
    }

    /// ⇧⌫: every read entry in the half on screen.
    func archiveAllRead() {
        archive(visibleInbox.filter { !isUnread($0) })
    }

    /// ⇧S: no more notifications about it until someone mentions you or you comment, and out of the Inbox.
    func unsubscribe(_ entries: [InboxEntry]) {
        guard !entries.isEmpty else { return }
        let message = entries.count == 1 ? "Unsubscribed from \(entries[0].displayNumber(withRepo: false))" : "Unsubscribed from \(entries.count) issues"
        change(entries, message: message) { entry in
            let change = Mutation.ThreadChange(threadId: entry.id, updatedAt: entry.updatedAt, label: entry.label)
            return [.unsubscribeThread(change), .archiveThread(change)]
        }
    }

    private func change(_ entries: [InboxEntry], message: String, mutations: (InboxEntry) -> [Mutation]) {
        let before = visibleInbox
        let ids = entries.map(\.id)
        var records: [String: PersonalStore.Record?] = [:]
        var unread: [String: Bool] = [:]
        for entry in entries {
            records[entry.id] = personal.records[entry.id]
            unread[entry.id] = entry.unread
            personal.clear(entry.id)
        }
        let lastId = outbox.last?.id ?? 0
        withAnimation(Theme.spring) { perform(entries.flatMap(mutations)) }
        // Only these go back with Undo; reading the entry that moves up into the selection stays.
        let added = outbox.compactMap(\.id).filter { $0 > lastId }
        withAnimation(Theme.spring) {
            inboxPicked = []
            selectNeighbour(after: Set(ids), in: before)
        }
        inboxUndo = InboxUndo(message: message, threadIds: ids, outboxIds: added, records: records, unread: unread)
        let engine = self.engine
        let undoId = inboxUndo?.id
        Task {
            // Send once the moment to undo has passed, and let the message go.
            try? await Task.sleep(for: .seconds(SyncEngine.undoWindow + 0.2))
            if inboxUndo?.id == undoId { withAnimation(Theme.overlay) { inboxUndo = nil } }
            await engine.kick()
        }
    }

    /// ⌘Z or the Undo button: puts the entries back, as long as nothing has been sent.
    func undoInbox() {
        guard let undo = inboxUndo else { return }
        inboxUndo = nil
        do {
            try db.writer.write { db in
                for id in undo.outboxIds {
                    try db.execute(sql: "DELETE FROM outbox WHERE id = ? AND state = ?", arguments: [id, OutboxState.pending.rawValue])
                }
                for threadId in undo.threadIds {
                    try db.execute(
                        sql: "UPDATE inboxEntry SET archivedFor = NULL, unread = ? WHERE id = ?",
                        arguments: [undo.unread[threadId] ?? false, threadId]
                    )
                }
            }
        } catch {
            return
        }
        for (threadId, record) in undo.records {
            personal.restore(threadId, record)
        }
        withAnimation(Theme.spring) { reloadNow() }
        if let first = undo.threadIds.first { inboxSelectedId = first }
    }

    // MARK: Snoozing

    /// H: gone from the Inbox on all devices until `until`, or until something new happens; then it's back, unread.
    func snooze(_ entries: [InboxEntry], until: Date) {
        guard !entries.isEmpty else { return }
        let before = visibleInbox
        withAnimation(Theme.spring) {
            for entry in entries {
                personal.setSnooze(entry.id, .init(until: until, threadUpdatedAt: entry.updatedAt))
                personal.setMarkedUnread(entry.id, nil)
            }
            inboxPicked = []
            selectNeighbour(after: Set(entries.map(\.id)), in: before)
        }
        scheduleInboxWake()
        let when = until.formatted(Calendar.current.isDateInToday(until) ? .dateTime.hour().minute() : .dateTime.weekday(.wide).hour().minute())
        let what = entries.count == 1 ? entries[0].displayNumber(withRepo: false) : "\(entries.count) notifications"
        status.post(Notice(title: "Snoozed \(what)", message: "Back \(Calendar.current.isDateInToday(until) ? "at" : "on") \(when), or sooner if something happens."))
    }

    /// Moves the Inbox's clock on: every minute, so "12m" becomes "13m", and right when a snoozed entry is due, so
    /// it comes back without waiting for a sync.
    func scheduleInboxWake() {
        inboxWake?.cancel()
        let minute = Date().addingTimeInterval(60)
        let next = personal.nextWake.map { min($0, minute) } ?? minute
        inboxWake = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(next.timeIntervalSinceNow, 0) + 0.2))
            guard !Task.isCancelled, let self else { return }
            self.inboxClock = Date()
            self.scheduleInboxWake()
        }
    }

    // MARK: Putting it on a board

    /// Adds an issue seen only in the Inbox to a project, as a card without a status. It can then be moved and
    /// changed like any other card.
    func addToProject(_ entry: InboxEntry, projectId: String) {
        guard let contentId = entry.contentId else { return }
        perform([.addToProject(.init(itemId: LocalID.make(), contentId: contentId, projectId: projectId, label: entry.label))])
    }

    /// Projects an issue can be added to: open ones you can edit.
    var projectsAcceptingIssues: [Project] {
        openProjects.filter(\.viewerCanUpdate)
    }
}

/// Choices for snoozing, as in Linear.
enum SnoozeChoice: CaseIterable, Identifiable {
    case laterToday
    case tomorrow
    case nextWeek

    var id: Self { self }

    var title: String {
        switch self {
        case .laterToday: "Later Today"
        case .tomorrow: "Tomorrow"
        case .nextWeek: "Next Week"
        }
    }

    /// Later today is three hours on, but no later than 18:00 if that is still ahead; tomorrow and next week start at
    /// 9:00.
    func date(from now: Date = Date(), calendar: Calendar = .current) -> Date {
        func at(_ hour: Int, on day: Date) -> Date {
            calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        }
        switch self {
        case .laterToday:
            let evening = at(18, on: now)
            let soon = now.addingTimeInterval(3 * 3600)
            return evening > now.addingTimeInterval(3600) ? min(evening, soon) : soon
        case .tomorrow:
            return at(9, on: calendar.date(byAdding: .day, value: 1, to: now) ?? now)
        case .nextWeek:
            let monday = calendar.nextDate(after: now, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime) ?? now
            return at(9, on: monday)
        }
    }

    /// "18:00", "Thu 9:00", "Mon 9:00", shown beside the choice.
    func hint(from now: Date = Date()) -> String {
        let date = date(from: now)
        if Calendar.current.isDateInToday(date) { return date.formatted(.dateTime.hour().minute()) }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}
