import Foundation
import GRDB

/// Keeps the local database and GitHub in step: pulls what changed, sends queued changes, and reconciles
/// the two when both sides moved. Pulls and pushes never overlap, so a stale read cannot undo a fresh write.
public actor SyncEngine {
    let db: AppDatabase
    let api: GitHubAPI
    public nonisolated let status: SyncStatus

    private var activeProjectId: String?
    private var activeRepoId: String?
    private var watchedIssueId: String?
    private var pollInterval: TimeInterval = 15

    private var lastPull: [String: Date] = [:]
    private var lastDetailPull: Date?
    private var lastProjectListPull: Date?
    private var forceSweep: Set<String> = []
    /// Issues of repositories, read for the ones that are on none of your boards.
    private var lastRepoPull: [String: Date] = [:]
    private var lastFullRepoPull: [String: Date] = [:]
    private var lastAssignedPull: Date?
    /// Items GitHub lists but will not show us (no access); remembered so they are not re-requested forever.
    private var unhydratable: [String: String] = [:]
    private var wasOffline = true
    /// When GitHub's notifications are asked for next, at the pace GitHub asks for (X-Poll-Interval).
    var nextInboxPull = Date.distantPast
    /// When assignments made with your own account were last looked for.
    var selfAssignedChecked: Date?

    private var loop: Task<Void, Never>?
    private var sleeper: Task<Void, Never>?
    private var kicked = false
    /// Sync rounds completed so far, and callers waiting for a round to finish.
    private var rounds = 0
    private var inRound = false
    private var waiters: [(round: Int, continuation: CheckedContinuation<Void, Never>)] = []
    /// Works on the built-in sample data: nothing is sent anywhere, changes are confirmed locally.
    public nonisolated let isDemo: Bool

    public init(db: AppDatabase, api: GitHubAPI, status: SyncStatus, demo: Bool = false) {
        self.db = db
        self.api = api
        self.status = status
        self.isDemo = demo
    }

    // MARK: Control

    public func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.round()
                await self.idle()
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
        sleeper?.cancel()
        let pending = waiters
        waiters = []
        for waiter in pending { waiter.continuation.resume() }
    }

    private func round() async {
        inRound = true
        if isDemo { await demoCycle() } else { await cycle() }
        inRound = false
        rounds += 1
        let done = waiters.filter { $0.round <= rounds }
        waiters.removeAll { $0.round <= rounds }
        for waiter in done { waiter.continuation.resume() }
    }

    /// Runs a sync round as soon as possible and returns when it is done (pull to refresh, background refresh).
    /// Rounds never overlap: this waits for the loop rather than running one of its own.
    public func syncNow() async {
        guard loop != nil else {
            await round()
            return
        }
        // A round already under way may have missed what prompted this call, so wait for the next one.
        let target = rounds + (inRound ? 2 : 1)
        await withCheckedContinuation { continuation in
            waiters.append((target, continuation))
            kick()
        }
    }

    /// Asks for a sync cycle now instead of at the next poll.
    public func kick() {
        kicked = true
        sleeper?.cancel()
    }

    public func setActiveProject(_ id: String?) {
        guard activeProjectId != id else { return }
        activeProjectId = id
        kick()
    }

    /// The repository on screen, whose issues are kept as fresh as the board on screen.
    public func setActiveRepository(_ id: String?) {
        guard activeRepoId != id else { return }
        activeRepoId = id
        if id != nil { kick() }
    }

    public func setWatchedIssue(_ contentId: String?) {
        guard watchedIssueId != contentId else { return }
        watchedIssueId = contentId
        lastDetailPull = nil
        if contentId != nil { kick() }
    }

    /// Stops refreshing an issue that left the screen, unless another one has been watched since.
    public func unwatchIssue(_ contentId: String) {
        if watchedIssueId == contentId { watchedIssueId = nil }
    }

    public func setPollInterval(_ seconds: TimeInterval) {
        pollInterval = seconds
    }

    public func forceRefresh() {
        if let activeProjectId { forceSweep.insert(activeProjectId) }
        lastPull = [:]
        lastProjectListPull = nil
        lastRepoPull = [:]
        lastFullRepoPull = [:]
        lastAssignedPull = nil
        kick()
    }

    /// Sends everything that is queued, without waiting for the next cycle. Leaving the app ends the chance to undo,
    /// so archived Inbox entries go out too.
    public func pushPending() async throws {
        guard !isDemo else { return }
        try await push(holdingUndoable: false)
    }

    /// Re-reads a project from GitHub even if nothing appears to have changed.
    public func forcePull(projectId: String) async throws {
        guard !isDemo else { return }
        forceSweep.insert(projectId)
        try await pull(projectId: projectId)
    }

    private func idle() async {
        if kicked {
            kicked = false
            return
        }
        let seconds = wasOffline ? min(pollInterval, 10) : pollInterval
        let task = Task<Void, Never> { _ = try? await Task.sleep(for: .seconds(seconds)) }
        sleeper = task
        await task.value
        sleeper = nil
        kicked = false
    }

    // MARK: Cycle

    private func cycle() async {
        do {
            try await db.writer.write { try Outbox.purgeSent($0) }
            let pending = try await db.reader.read {
                try OutboxEntry.filter(Column("state") == OutboxState.pending.rawValue).fetchCount($0)
            }
            let neverSynced = activeProjectId.map { lastPull[$0] == nil } ?? false
            if pending > 0 || neverSynced { await setPhase(.syncing) }

            if lastProjectListPull.map({ Date().timeIntervalSince($0) > 300 }) ?? true {
                try await refreshProjects()
            }

            // After being offline (or idle for a while) look at GitHub first, so clashes are noticed before sending.
            let stale = wasOffline || age(of: activeProjectId) > 45
            if stale { try await pullActive() }
            try await push()
            if !stale, age(of: activeProjectId) >= pollInterval - 1 { try await pullActive() }

            if let watchedIssueId, !watchedIssueId.hasPrefix(LocalID.prefix),
               lastDetailPull.map({ Date().timeIntervalSince($0) >= pollInterval - 1 }) ?? true {
                try await loadIssueDetail(contentId: watchedIssueId)
            }
            if Date() >= nextInboxPull { try await pullInboxInRound() }
            try await pullOneBackgroundProject()
            try await pullRepositories()

            wasOffline = false
            await finish(.idle, syncedAt: Date())
        } catch let error as APIError {
            switch error {
            case .unauthorized, .noToken:
                await finish(.unauthorized)
            case _ where error.isTransient:
                wasOffline = true
                await finish(.offline)
            default:
                await finish(.failed(error.localizedDescription))
            }
        } catch is CancellationError {
            return
        } catch {
            await finish(.failed(error.localizedDescription))
        }
    }

    private func age(of projectId: String?) -> TimeInterval {
        guard let projectId, let date = lastPull[projectId] else { return .infinity }
        return Date().timeIntervalSince(date)
    }

    private func pullActive() async throws {
        guard let activeProjectId else { return }
        try await pull(projectId: activeProjectId)
    }

    /// Other projects are refreshed one per cycle, at most every five minutes each, so "My Issues" stays usable.
    private func pullOneBackgroundProject() async throws {
        let ids = try await db.reader.read {
            try String.fetchAll($0, sql: "SELECT id FROM project WHERE closed = 0")
        }
        guard let next = ids.first(where: { $0 != activeProjectId && age(of: $0) > 300 }) else { return }
        do {
            try await pull(projectId: next)
        } catch let error as APIError where !error.isTransient {
            // A project we cannot read should not stop everything else from syncing.
            lastPull[next] = Date()
        }
    }

    @MainActor
    private func setPhase(_ phase: SyncStatus.Phase) {
        status.phase = phase
    }

    @MainActor
    private func finish(_ phase: SyncStatus.Phase, syncedAt: Date? = nil) {
        status.phase = phase
        if let syncedAt { status.lastSyncedAt = syncedAt }
    }

    @MainActor
    private func post(_ notices: [Notice]) {
        for notice in notices { status.post(notice) }
    }

    @MainActor
    private func publish(remaps: [String: String]) {
        status.idRemaps.merge(remaps) { _, new in new }
    }

    // MARK: Project list

    public func refreshProjects() async throws {
        guard !isDemo else { return }
        let (viewer, projects) = try await api.viewerAndProjects()
        try await db.writer.write { db in
            try KV.setViewer(db, viewer)
            let remoteIds = Set(projects.map(\.id))
            for id in try String.fetchAll(db, sql: "SELECT id FROM project") where !remoteIds.contains(id) {
                try Project.deleteOne(db, key: id)
            }
            for remote in projects {
                if var local = try Project.fetchOne(db, key: remote.id) {
                    local.title = remote.title
                    local.url = remote.url
                    local.closed = remote.closed
                    local.viewerCanUpdate = remote.viewerCanUpdate
                    local.ownerLogin = remote.ownerLogin
                    try local.update(db)
                } else {
                    try remote.insert(db)
                }
            }
        }
        lastProjectListPull = Date()
    }

    // MARK: Pull

    public func pull(projectId: String) async throws {
        guard !isDemo else { return }
        let meta = try await api.projectMeta(id: projectId)

        let (local, dirtyIds, known) = try await db.reader.read { db -> (Project?, Set<String>, [String: String]) in
            let project = try Project.fetchOne(db, key: projectId)
            let dirty = try String.fetchSet(db, sql: "SELECT id FROM item WHERE projectId = ? AND dirty = 1", arguments: [projectId])
            var known: [String: String] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT id, remoteUpdatedAt FROM item WHERE projectId = ?", arguments: [projectId]) {
                known[row["id"]] = row["remoteUpdatedAt"] ?? ""
            }
            return (project, dirty, known)
        }
        guard let local else { return }

        // A due field that appeared, was swapped or went away changes the dates of cards GitHub doesn't count as
        // changed, so every card is read again.
        let dueFieldChanged = local.dueFieldId != meta.dueField?.id
        let changed = forceSweep.contains(projectId)
            || dueFieldChanged
            || local.lastSyncedAt == nil
            || local.remoteUpdatedAt != meta.updatedAt
            || local.itemsTotal != meta.itemsTotal
            || !dirtyIds.isEmpty

        var sweep: [SweepEntry] = []
        var hydrated: [Item] = []
        if changed {
            sweep = try await api.sweep(projectId: projectId)
            let wanted = sweep.filter { entry in
                if dirtyIds.contains(entry.id) || dueFieldChanged { return true }
                if unhydratable[entry.id] == entry.updatedAt { return false }
                return known[entry.id] != entry.updatedAt
            }.map(\.id)
            hydrated = try await api.hydrate(
                itemIds: wanted, projectId: projectId,
                statusFieldId: meta.statusField?.id, priorityFieldId: meta.priorityField?.id, dueFieldId: meta.dueField?.id
            )
            let got = Set(hydrated.map(\.id))
            for entry in sweep where wanted.contains(entry.id) && !got.contains(entry.id) {
                unhydratable[entry.id] = entry.updatedAt
            }
            // A parent's sub-issue progress changes when a child does, without the parent being touched.
            let parentContentIds = Set(hydrated.compactMap(\.parentId))
            if !parentContentIds.isEmpty {
                let parents = try await db.reader.read { db in
                    try String.fetchAll(
                        db,
                        sql: "SELECT id FROM item WHERE projectId = ? AND contentId IN (\(parentContentIds.map { _ in "?" }.joined(separator: ",")))",
                        arguments: StatementArguments([projectId] + Array(parentContentIds))
                    )
                }.filter { !got.contains($0) }
                if !parents.isEmpty {
                    hydrated += try await api.hydrate(
                        itemIds: parents, projectId: projectId,
                        statusFieldId: meta.statusField?.id, priorityFieldId: meta.priorityField?.id, dueFieldId: meta.dueField?.id
                    )
                }
            }
            // Likewise an issue's open blockers: when an issue that blocks others changed, perhaps closed, the
            // issues marked as blocked are read again.
            if hydrated.contains(where: { $0.blockingCount > 0 }) {
                let read = Set(hydrated.map(\.id))
                let blocked = try await db.reader.read { db in
                    try String.fetchAll(db, sql: "SELECT id FROM item WHERE projectId = ? AND blockedByCount > 0", arguments: [projectId])
                }.filter { !read.contains($0) }
                if !blocked.isEmpty {
                    hydrated += try await api.hydrate(
                        itemIds: blocked, projectId: projectId,
                        statusFieldId: meta.statusField?.id, priorityFieldId: meta.priorityField?.id, dueFieldId: meta.dueField?.id
                    )
                }
            }
        }

        let sweepSnapshot = sweep
        let hydratedSnapshot = hydrated
        let written = try await db.writer.write { db -> (notices: [Notice], leftBoard: Set<String>, remaps: [String: String]) in
            guard var project = try Project.fetchOne(db, key: projectId) else { return ([], [], [:]) }
            project.title = meta.title
            project.closed = meta.closed
            project.viewerCanUpdate = meta.viewerCanUpdate
            project.statusFieldId = meta.statusField?.id
            project.priorityFieldId = meta.priorityField?.id
            project.dueFieldId = meta.dueField?.id
            try Self.writeOptions(db, projectId: projectId, meta: meta)

            var repos = meta.repos
            for item in hydratedSnapshot {
                if let id = item.repoId, let name = item.repo { repos.append((id, name)) }
            }
            try Self.writeRepos(db, projectId: projectId, repos: repos)

            var notices: [Notice] = []
            var leftBoard = Set<String>()
            var remaps: [String: String] = [:]
            if changed {
                notices += try Self.reconcile(db, hydrated: hydratedSnapshot)

                var order: [String: Int] = [:]
                for (index, entry) in sweepSnapshot.enumerated() { order[entry.id] = index }
                for var item in hydratedSnapshot {
                    item.position = Double((order[item.id] ?? sweepSnapshot.count) + 1) * 1024
                    try item.save(db)
                }
                // Whether you may delete an issue goes with your rights in its repository, which change without the
                // issue changing, so it is written for every card, not only those read in full.
                for (index, entry) in sweepSnapshot.enumerated() {
                    try db.execute(
                        sql: "UPDATE item SET position = ?, viewerCanDelete = COALESCE(?, viewerCanDelete) WHERE id = ?",
                        arguments: [Double(index + 1) * 1024, entry.viewerCanDelete, entry.id]
                    )
                }

                let removed = try Self.removeMissing(db, projectId: projectId, remoteIds: Set(sweepSnapshot.map(\.id)))
                notices += removed.notices
                leftBoard = removed.repoIds
                remaps = try Self.dropCopiesWithoutProject(db)
                try Outbox.rebase(db)
                try Outbox.clearSettledDirtyFlags(db, projectId: projectId)
                project.remoteUpdatedAt = meta.updatedAt
                project.itemsTotal = meta.itemsTotal
            }
            project.lastSyncedAt = Date()
            try project.update(db)
            return (notices, leftBoard, remaps)
        }
        forceSweep.remove(projectId)
        lastPull[projectId] = Date()
        // An issue taken off the board may now be on none; its repository says so at the next full read.
        for repoId in written.leftBoard { lastFullRepoPull[repoId] = nil }
        if !written.leftBoard.isEmpty { lastAssignedPull = nil }
        if !written.remaps.isEmpty { await publish(remaps: written.remaps) }
        await post(written.notices)
    }

    /// An issue that came onto a board is shown there and no longer as an issue on no board. Returns the old ids
    /// with the board item's, so whatever showed the issue can follow it.
    static func dropCopiesWithoutProject(_ db: Database) throws -> [String: String] {
        var remaps: [String: String] = [:]
        let rows = try Row.fetchAll(db, sql: """
            SELECT loose.id AS looseId, board.id AS boardId FROM item loose
            JOIN item board ON board.contentId = loose.contentId AND board.projectId IS NOT NULL
            WHERE loose.projectId IS NULL
            """)
        for row in rows {
            let looseId: String = row["looseId"]
            remaps[looseId] = row["boardId"]
            try db.execute(sql: "DELETE FROM item WHERE id = ?", arguments: [looseId])
        }
        return remaps
    }

    private static func writeOptions(_ db: Database, projectId: String, meta: RemoteProjectMeta) throws {
        var wanted: [FieldOption] = []
        for (field, kind) in [(meta.statusField, OptionKind.status), (meta.priorityField, OptionKind.priority)] {
            guard let field else { continue }
            for (index, option) in field.options.enumerated() {
                guard let id = option.id else { continue }
                wanted.append(FieldOption(
                    id: id, fieldId: field.id, projectId: projectId, kind: kind,
                    name: option.name, color: option.color, descr: option.descr, position: index
                ))
            }
        }
        let existing = try FieldOption.filter(Column("projectId") == projectId).order(Column("kind"), Column("position")).fetchAll(db)
        let sortedWanted = wanted.sorted { ($0.kind.rawValue, $0.position) < ($1.kind.rawValue, $1.position) }
        guard existing != sortedWanted else { return }
        try FieldOption.filter(Column("projectId") == projectId).deleteAll(db)
        for option in wanted { try option.insert(db) }
    }

    private static func writeRepos(_ db: Database, projectId: String, repos: [(id: String, nameWithOwner: String)]) throws {
        var seen = Set<String>()
        for repo in repos where seen.insert(repo.id).inserted {
            if try !RepoRef.exists(db, key: ["projectId": projectId, "id": repo.id]) {
                try RepoRef(id: repo.id, nameWithOwner: repo.nameWithOwner, projectId: projectId).insert(db)
            }
        }
    }

    /// Compares unsent changes with what GitHub now has, before the fresh rows overwrite the local ones.
    private static func reconcile(_ db: Database, hydrated: [Item]) throws -> [Notice] {
        var notices: [Notice] = []
        let byItemId = Dictionary(hydrated.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var byContentId: [String: Item] = [:]
        for item in hydrated {
            if let contentId = item.contentId { byContentId[contentId] = item }
        }
        let entries = try OutboxEntry
            .filter([OutboxState.pending.rawValue, OutboxState.conflict.rawValue].contains(Column("state")))
            .order(Column("id"))
            .fetchAll(db)

        for var entry in entries {
            switch entry.mutation {
            case .setField(var m):
                guard let remote = byItemId[m.itemId] else { continue }
                let theirs = m.kind == .status ? remote.statusId : remote.priorityId
                guard theirs != m.base, theirs != m.optionId else { continue }
                let theirName = try theirs.flatMap {
                    try String.fetchOne(db, sql: "SELECT name FROM fieldOption WHERE fieldId = ? AND id = ?", arguments: [m.fieldId, $0])
                }
                let mineName = try m.optionId.flatMap {
                    try String.fetchOne(db, sql: "SELECT name FROM fieldOption WHERE fieldId = ? AND id = ?", arguments: [m.fieldId, $0])
                }
                let there: LocalizedStringResource = switch (m.kind, theirName) {
                case (.status, let name?): .noticeStatusSetThere(status: name)
                case (.status, nil): .noticeStatusSetToNoneThere
                case (.priority, let name?): .noticePrioritySetThere(priority: name)
                case (.priority, nil): .noticePrioritySetToNoneThere
                }
                var undo = m
                undo.optionId = theirs
                undo.base = m.optionId
                notices.append(Notice(
                    title: String(localized: .noticeAlsoChangedOnGitHub(number: remote.displayNumber)),
                    message: Self.clashMessage(there, mine: mineName),
                    action: theirName.map { .applyField(undo, label: String(localized: .switchToValue(value: $0))) }
                ))
                m.base = theirs
                entry.mutation = .setField(m)
                try entry.update(db)

            case .setDate(var m):
                guard let remote = byItemId[m.itemId] else { continue }
                let theirs = remote.dueDate
                guard theirs != m.base, theirs != m.date else { continue }
                func name(_ date: String?) -> String? {
                    date.flatMap(CalendarDay.init).map { $0.date().formatted(.dateTime.day().month(.abbreviated)) }
                }
                let theirName = name(theirs)
                var undo = m
                undo.date = theirs
                undo.base = m.date
                notices.append(Notice(
                    title: String(localized: .noticeAlsoChangedOnGitHub(number: remote.displayNumber)),
                    message: Self.clashMessage(
                        theirName.map { .noticeDueDateSetThere(date: $0) } ?? .noticeDueDateSetToNoneThere,
                        mine: name(m.date)
                    ),
                    action: .applyDate(undo, label: String(localized: theirs.map { .switchToValue(value: theirName ?? $0) } ?? .removeTheDate))
                ))
                m.base = theirs
                entry.mutation = .setDate(m)
                try entry.update(db)

            case .setTitle(var m):
                guard let remote = byContentId[m.contentId] else { continue }
                let state = reconcileText(&m, theirs: remote.title, mergeLines: false)
                if state != entry.state || entry.mutation != .setTitle(m) {
                    entry.state = state
                    entry.mutation = .setTitle(m)
                    try entry.update(db)
                }

            case .setBody(var m):
                guard let remote = byContentId[m.contentId] else { continue }
                let state = reconcileText(&m, theirs: remote.body, mergeLines: true)
                if state != entry.state || entry.mutation != .setBody(m) {
                    entry.state = state
                    entry.mutation = .setBody(m)
                    try entry.update(db)
                }

            default:
                continue
            }
        }
        return notices
    }

    /// "Its status was set to Done there. Your change to In Progress was applied last."
    private static func clashMessage(_ there: LocalizedStringResource, mine: String?) -> String {
        let applied: LocalizedStringResource = mine.map { .noticeYourChangeAppliedLast(value: $0) } ?? .noticeYourChangeToNoneAppliedLast
        return "\(String(localized: there)) \(String(localized: applied))"
    }

    /// Decides what to do with an unsent text edit given GitHub's current text.
    static func reconcileText(_ m: inout Mutation.SetText, theirs: String, mergeLines: Bool) -> OutboxState {
        if theirs == m.base || theirs == m.value {
            m.theirs = nil
            return .pending
        }
        if mergeLines, let merged = Diff3.merge(base: m.base, mine: m.value, theirs: theirs) {
            m.value = merged
            m.base = theirs
            m.theirs = nil
            return .pending
        }
        m.theirs = theirs
        return .conflict
    }

    private static func removeMissing(_ db: Database, projectId: String, remoteIds: Set<String>) throws -> (notices: [Notice], repoIds: Set<String>) {
        var notices: [Notice] = []
        var repoIds = Set<String>()
        let entries = try Outbox.active(db)
        // An issue we created or put on the board moments ago may not be listed yet.
        let justCreated = Set(entries.compactMap { entry -> String? in
            switch entry.mutation {
            case .createIssue(let m): m.itemId
            case .addToProject(let m): m.itemId
            default: nil
            }
        })
        let localItems = try Item.filter(Column("projectId") == projectId).fetchAll(db)
        for item in localItems where !remoteIds.contains(item.id) && !item.isLocalOnly && !justCreated.contains(item.id) {
            let orphaned = entries.filter {
                $0.state != .sent && ($0.mutation.itemId == item.id || (item.contentId != nil && $0.mutation.contentId == item.contentId))
            }
            for entry in orphaned { try entry.delete(db) }
            if !orphaned.isEmpty {
                notices.append(Notice(
                    title: String(localized: .noticeNoLongerInProject(number: item.displayNumber)),
                    message: String(localized: .noticeQueuedChangesDiscarded(count: orphaned.count)),
                    isWarning: true
                ))
            }
            if let repoId = item.repoId, item.kind == .issue { repoIds.insert(repoId) }
            try item.delete(db)
        }
        return (notices, repoIds)
    }

    // MARK: Issues on no board

    /// Repositories of your open boards. Their issues that are on none of your boards are read from them.
    private func boardRepositories() async throws -> [String] {
        try await db.reader.read { db in
            try String.fetchAll(db, sql: """
                SELECT DISTINCT r.id FROM repo r JOIN project p ON p.id = r.projectId WHERE p.closed = 0
                """)
        }
    }

    /// The repository on screen every cycle, one other repository per cycle, at most once a minute each, and the
    /// issues assigned to you elsewhere every five minutes.
    private func pullRepositories() async throws {
        let repos = try await boardRepositories()
        func read(_ repoId: String) async throws {
            do {
                try await pullRepository(repoId)
            } catch let error as APIError where !error.isTransient {
                // A repository we cannot read should not stop everything else from syncing.
                lastRepoPull[repoId] = Date()
            }
        }
        if let activeRepoId, repos.contains(activeRepoId),
           lastRepoPull[activeRepoId].map({ Date().timeIntervalSince($0) >= pollInterval - 1 }) ?? true {
            try await read(activeRepoId)
        }
        if let next = repos.first(where: { $0 != activeRepoId && (lastRepoPull[$0].map { Date().timeIntervalSince($0) > 60 } ?? true) }) {
            try await read(next)
        }
        if lastAssignedPull.map({ Date().timeIntervalSince($0) > 300 }) ?? true {
            do {
                try await pullAssigned(boardRepos: Set(repos))
            } catch let error as APIError where !error.isTransient {
                lastAssignedPull = Date()
            }
        }
    }

    /// How long closed issues on no board stay in lists, like the done issues Linear shows by default.
    static let closedIssueWindow: TimeInterval = 28 * 24 * 3600

    /// Reads a repository's issues. Every half hour all of them (the open ones and those closed lately), so
    /// issues that were moved or deleted disappear; in between only what changed. A light list comes first; only
    /// issues on none of your boards that changed are then read in full.
    public func pullRepository(_ repoId: String) async throws {
        guard !isDemo else { return }
        let started = Date()
        let full = lastFullRepoPull[repoId].map { started.timeIntervalSince($0) > 1800 } ?? true
        var refs: [IssueRef]
        if full {
            refs = try await api.repositoryIssueRefs(repoId: repoId, states: ["OPEN"], since: nil)
            refs += try await api.repositoryIssueRefs(
                repoId: repoId, states: ["CLOSED"], since: started.addingTimeInterval(-Self.closedIssueWindow)
            )
        } else {
            let since = (lastRepoPull[repoId] ?? started).addingTimeInterval(-120)
            refs = try await api.repositoryIssueRefs(repoId: repoId, states: nil, since: since)
        }
        try await writeIssuesWithoutProject(refs, prune: full ? .repository(repoId) : nil)
        lastRepoPull[repoId] = started
        if full { lastFullRepoPull[repoId] = started }
        await markRead(repoId)
    }

    @MainActor
    private func markRead(_ repoId: String) {
        status.readRepositories.insert(repoId)
    }

    /// Open issues assigned to you in repositories none of your boards use; the others come with their repository.
    private func pullAssigned(boardRepos: Set<String>) async throws {
        guard !isDemo else { return }
        let started = Date()
        let refs = try await api.assignedIssueRefs().filter { ref in
            ref.repoId.map { !boardRepos.contains($0) } ?? false
        }
        try await writeIssuesWithoutProject(refs, prune: .outside(boardRepos))
        lastAssignedPull = started
    }

    /// Reads in full what changed among the listed issues on no board, and writes them.
    private func writeIssuesWithoutProject(_ refs: [IssueRef], prune: Prune?) async throws {
        let wanted = try await db.reader.read { try Self.issuesToRead(in: refs, $0) }
        let fetched = try await api.issues(ids: wanted)
        let (notices, staleBoards) = try await db.writer.write { db in
            try Self.writeIssuesWithoutProject(db, fetched, listed: refs, prune: prune)
        }
        refreshSoon(staleBoards)
        await post(notices)
    }

    /// Issues of a light read that aren't on a board here and aren't here as they are on GitHub. Reading them in
    /// full says whether they are on one of your boards after all (and that board is read again) or on none.
    static func issuesToRead(in refs: [IssueRef], _ db: Database, now: Date = Date()) throws -> [String] {
        let onBoards = try String.fetchSet(db, sql: "SELECT contentId FROM item WHERE projectId IS NOT NULL AND contentId IS NOT NULL")
        var known: [String: String] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT id, remoteUpdatedAt FROM item WHERE projectId IS NULL") {
            known[row["id"]] = row["remoteUpdatedAt"] ?? ""
        }
        return refs.filter { ref in
            guard !onBoards.contains(ref.contentId) else { return false }
            if ref.isClosed, let closed = ref.closedAt, now.timeIntervalSince(closed) > closedIssueWindow { return false }
            return known[ref.itemId] != ref.updatedAt
        }.map(\.contentId)
    }

    /// Boards that have an issue GitHub lists but this device doesn't have yet are read again soon.
    private func refreshSoon(_ projectIds: Set<String>) {
        for id in projectIds {
            forceSweep.insert(id)
            lastPull[id] = nil
        }
    }

    enum Prune: Equatable {
        /// Everything of this repository was read: issues on no board that weren't listed are gone.
        case repository(String)
        /// Everything outside these repositories was read.
        case outside(Set<String>)
    }

    /// Writes issues read from a repository or a search. Issues on one of your boards are left to the board;
    /// the rest become items without a project. `listed` is everything the read listed, of which `issues` are
    /// the ones read in full. Returns notices and the boards that should be read again because one of their
    /// issues isn't here yet.
    static func writeIssuesWithoutProject(
        _ db: Database, _ issues: [RemoteIssue], listed: [IssueRef]? = nil, prune: Prune?, now: Date = Date()
    ) throws -> (notices: [Notice], staleBoards: Set<String>) {
        let openBoards = try String.fetchSet(db, sql: "SELECT id FROM project WHERE closed = 0")
        let onBoards = try String.fetchSet(db, sql: "SELECT contentId FROM item WHERE projectId IS NOT NULL AND contentId IS NOT NULL")
        let refs = listed ?? []
        let listed = Set((listed?.map(\.itemId)) ?? issues.map(\.item.id))
        var staleBoards = Set<String>()
        var loose: [Item] = []
        for issue in issues {
            guard let contentId = issue.item.contentId else { continue }
            let boards = Set(issue.projectIds).intersection(openBoards)
            if !boards.isEmpty {
                if !onBoards.contains(contentId) { staleBoards.formUnion(boards) }
                continue
            }
            // Someone took it off a board, or this device just put it on one and GitHub doesn't know yet.
            if onBoards.contains(contentId) { continue }
            if issue.item.isClosed, let closed = issue.item.closedAt, now.timeIntervalSince(closed) > closedIssueWindow { continue }
            loose.append(issue.item)
        }

        let notices = try reconcile(db, hydrated: loose)
        for item in loose { try item.save(db) }
        // Your rights change without the issue changing, so whether you may delete it is taken from the light read,
        // for every issue it listed, on a board or not.
        for ref in refs {
            guard let canDelete = ref.viewerCanDelete else { continue }
            try db.execute(
                sql: "UPDATE item SET viewerCanDelete = ? WHERE contentId = ? AND viewerCanDelete != ?",
                arguments: [canDelete, ref.contentId, canDelete]
            )
        }

        if let prune {
            let justCreated = Set(try Outbox.active(db).compactMap { entry -> String? in
                if case .createIssue(let m) = entry.mutation { return m.itemId }
                return nil
            })
            var stale = try Item.filter(Column("projectId") == nil).fetchAll(db).filter { item in
                !listed.contains(item.id) && !item.isLocalOnly && !justCreated.contains(item.id)
            }
            switch prune {
            case .repository(let repoId):
                stale = stale.filter { $0.repoId == repoId }
            case .outside(let repos):
                stale = stale.filter { $0.repoId.map { !repos.contains($0) } ?? true }
            }
            for item in stale { try item.delete(db) }
        }
        // Closed long enough ago to drop out of the lists.
        try db.execute(
            sql: "DELETE FROM item WHERE projectId IS NULL AND state != 'OPEN' AND closedAt < ?",
            arguments: [now.addingTimeInterval(-closedIssueWindow)]
        )
        try Outbox.rebase(db)
        try Outbox.clearSettledDirtyFlags(db, projectId: nil)
        return (notices, staleBoards)
    }

    // MARK: Push

    private enum SendOutcome {
        case sent([String: String])
        case deferred
    }

    /// How long archiving an Inbox entry can be undone before it is sent.
    public static let undoWindow: TimeInterval = 5

    private func push(holdingUndoable: Bool = true) async throws {
        var skipped = Set<Int64>()
        while true {
            let skip = skipped
            let heldSince = holdingUndoable ? Date().addingTimeInterval(-Self.undoWindow) : .distantFuture
            let next = try await db.reader.read { db in
                try OutboxEntry
                    .filter(Column("state") == OutboxState.pending.rawValue)
                    .order(Column("id"))
                    .fetchAll(db)
                    .first { !skip.contains($0.id ?? -1) && !($0.mutation.isUndoable && $0.createdAt > heldSince) }
            }
            guard let entry = next, let entryId = entry.id else { return }
            do {
                switch try await send(entry) {
                case .sent(let remaps):
                    try await db.writer.write { db in
                        try Self.markSent(db, entryId: entryId, remaps: remaps)
                    }
                    if !remaps.isEmpty { await publish(remaps: remaps) }
                case .deferred:
                    skipped.insert(entryId)
                }
            } catch let error as APIError where error.isTransient || isAuthError(error) {
                try? await db.writer.write { db in
                    try db.execute(sql: "UPDATE outbox SET attempts = attempts + 1, lastError = ? WHERE id = ?", arguments: [error.localizedDescription, entryId])
                }
                throw error
            } catch {
                let notice = try await db.writer.write { db in
                    try Self.discard(db, entryId: entryId, error: error)
                }
                if let projectId = activeProjectId { forceSweep.insert(projectId) }
                if let notice { await post([notice]) }
            }
        }
    }

    private nonisolated func isAuthError(_ error: APIError) -> Bool {
        switch error {
        case .unauthorized, .noToken: true
        default: false
        }
    }

    private func send(_ entry: OutboxEntry) async throws -> SendOutcome {
        if entry.mutation.referencedIds.contains(where: { $0.hasPrefix(LocalID.prefix) }) {
            throw APIError.graphql([GraphQLErrorItem(message: String(localized: .errorIssueNeverCreated), type: "NOT_FOUND")])
        }
        switch entry.mutation {
        case .setField(let m):
            try await api.setFieldValue(projectId: m.projectId, itemId: m.itemId, fieldId: m.fieldId, optionId: m.optionId)

        case .setDate(let m):
            // Clearing a date on a board without a date field leaves nothing to clear.
            guard let fieldId = try await dueFieldId(projectId: m.projectId, create: m.date != nil) else { break }
            try await api.setDateValue(projectId: m.projectId, itemId: m.itemId, fieldId: fieldId, date: m.date)

        case .move(let m):
            try await api.moveItem(projectId: m.projectId, itemId: m.itemId, afterId: m.afterItemId)

        case .setTitle(var m):
            let remote = try await api.issueText(contentId: m.contentId)
            let state = Self.reconcileText(&m, theirs: remote.title, mergeLines: false)
            try await store(entry, mutation: .setTitle(m), state: state)
            guard state == .pending else { return .deferred }
            try await api.updateIssue(contentId: m.contentId, title: m.value)

        case .setBody(var m):
            let remote = try await api.issueText(contentId: m.contentId)
            let state = Self.reconcileText(&m, theirs: remote.body, mergeLines: true)
            try await store(entry, mutation: .setBody(m), state: state)
            guard state == .pending else { return .deferred }
            try await api.updateIssue(contentId: m.contentId, body: m.value)

        case .setState(let m):
            if m.closed {
                try await api.closeIssue(contentId: m.contentId, reason: m.reason ?? "COMPLETED")
            } else {
                try await api.reopenIssue(contentId: m.contentId)
            }

        case .editAssignees(let m):
            try await api.editAssignees(contentId: m.contentId, add: m.add.map(\.id), remove: m.remove.map(\.id))

        case .editLabels(let m):
            try await api.editLabels(contentId: m.contentId, add: m.add.map(\.id), remove: m.remove.map(\.id))

        case .addComment(let m):
            let id = try await api.addComment(contentId: m.contentId, body: m.body)
            return .sent([m.commentId: id])

        case .createIssue(var m):
            if m.createdContentId == nil {
                let created = try await api.createIssue(
                    repoId: m.repoId, title: m.title, body: m.body,
                    assigneeIds: m.assignees.map(\.id), labelIds: m.labels.map(\.id),
                    parentContentId: m.parentContentId
                )
                m.createdContentId = created.contentId
                m.createdNumber = created.number
                m.createdUrl = created.url
                try await store(entry, mutation: .createIssue(m), state: .pending)
            }
            guard let contentId = m.createdContentId else { return .deferred }
            guard let projectId = m.projectId else {
                return .sent([m.itemId: Item.idWithoutProject(contentId), m.contentId: contentId])
            }
            let itemId = try await api.addToProject(projectId: projectId, contentId: contentId)
            if let fieldId = m.statusFieldId, let optionId = m.statusId {
                try await api.setFieldValue(projectId: projectId, itemId: itemId, fieldId: fieldId, optionId: optionId)
            }
            if let fieldId = m.priorityFieldId, let optionId = m.priorityId {
                try await api.setFieldValue(projectId: projectId, itemId: itemId, fieldId: fieldId, optionId: optionId)
            }
            if let date = m.dueDate, let fieldId = try await dueFieldId(projectId: projectId, create: true) {
                try await api.setDateValue(projectId: projectId, itemId: itemId, fieldId: fieldId, date: date)
            }
            return .sent([m.itemId: itemId, m.contentId: contentId])

        case .addToProject(let m):
            let itemId = try await api.addToProject(projectId: m.projectId, contentId: m.contentId)
            if let fieldId = m.statusFieldId, let optionId = m.statusId {
                try await api.setFieldValue(projectId: m.projectId, itemId: itemId, fieldId: fieldId, optionId: optionId)
            }
            return .sent([m.itemId: itemId])

        case .setParent(let m):
            // Changes that ended where they started need nothing from GitHub.
            guard m.parentId != m.base else { break }
            if let parentId = m.parentId {
                try await api.addSubIssue(parentId: parentId, childId: m.child.contentId)
            } else if let base = m.base {
                try await api.removeSubIssue(parentId: base, childId: m.child.contentId)
            }

        case .setBlocking(let m):
            guard m.isBlocked != m.base else { break }
            try await api.setBlockedBy(issueId: m.blocked.contentId, blockerId: m.blocker.contentId, blocked: m.isBlocked)

        case .deleteItem(let m):
            do {
                if m.isDraft, let projectId = m.projectId {
                    try await api.deleteProjectItem(projectId: projectId, itemId: m.itemId)
                } else if let contentId = m.contentId {
                    try await api.deleteIssue(contentId: contentId)
                }
            } catch let error as APIError where error.isNotFound {
                // Already gone, which is what was asked for.
            }

        case .markThreadRead(let m):
            try await ignoringGone { try await self.api.markThreadRead(m.threadId) }

        case .archiveThread(let m):
            try await ignoringGone { try await self.api.markThreadDone(m.threadId) }

        case .unsubscribeThread(let m):
            try await ignoringGone { try await self.api.unsubscribeThread(m.threadId) }

        }
        return .sent([:])
    }

    /// The project's due field: the one known locally, else one GitHub has that wasn't seen yet, else (with
    /// `create`) a new "Due date" field. Looking on GitHub first means two devices never both add one.
    private func dueFieldId(projectId: String, create: Bool) async throws -> String? {
        let known = try await db.reader.read { db in
            try String.fetchOne(db, sql: "SELECT dueFieldId FROM project WHERE id = ?", arguments: [projectId])
        }
        if let known { return known }
        let found = try await api.projectMeta(id: projectId).dueField?.id
        var id = found
        if id == nil, create {
            id = try await api.createDateField(projectId: projectId, name: "Due date").id
        }
        guard let id else { return nil }
        try await db.writer.write { db in
            try db.execute(sql: "UPDATE project SET dueFieldId = ? WHERE id = ?", arguments: [id, projectId])
            // A field someone else added may already hold dates: read every card again.
            if found != nil {
                try db.execute(sql: "UPDATE item SET remoteUpdatedAt = NULL WHERE projectId = ?", arguments: [projectId])
            }
        }
        if found != nil { forceSweep.insert(projectId) }
        return id
    }

    /// A notification that is gone already needs nothing more.
    private func ignoringGone(_ call: () async throws -> Void) async throws {
        do {
            try await call()
        } catch let error as APIError where error.isNotFound {
            return
        }
    }

    /// Saves a changed mutation (merged text, creation progress) back to its outbox row and re-applies it locally.
    private func store(_ entry: OutboxEntry, mutation: Mutation, state: OutboxState) async throws {
        guard mutation != entry.mutation || state != entry.state else { return }
        var updated = entry
        updated.mutation = mutation
        updated.state = state
        let snapshot = updated
        try await db.writer.write { db in
            try snapshot.update(db)
            try mutation.applyLocally(db)
            if case .createIssue(let m) = mutation {
                try db.execute(sql: "UPDATE item SET number = ?, url = ? WHERE id = ?", arguments: [m.createdNumber, m.createdUrl, m.itemId])
                try db.execute(sql: "UPDATE subIssue SET number = ?, url = ? WHERE id = ?", arguments: [m.createdNumber ?? 0, m.createdUrl, m.contentId])
            }
        }
    }

    private static func markSent(_ db: Database, entryId: Int64, remaps: [String: String]) throws {
        try db.execute(
            sql: "UPDATE outbox SET state = ?, sentAt = ? WHERE id = ?",
            arguments: [OutboxState.sent.rawValue, Date(), entryId]
        )
        guard !remaps.isEmpty else { return }
        for (old, new) in remaps {
            // The board item may be here already, read from GitHub while the change was on its way.
            if try Item.exists(db, key: new) {
                try db.execute(sql: "DELETE FROM item WHERE id = ?", arguments: [old])
            }
            try db.execute(sql: "UPDATE item SET id = ? WHERE id = ?", arguments: [new, old])
            try db.execute(sql: "UPDATE item SET contentId = ? WHERE contentId = ?", arguments: [new, old])
            try db.execute(sql: "UPDATE item SET parentId = ? WHERE parentId = ?", arguments: [new, old])
            try db.execute(sql: "UPDATE comment SET id = ? WHERE id = ?", arguments: [new, old])
            try db.execute(sql: "UPDATE comment SET issueId = ? WHERE issueId = ?", arguments: [new, old])
            try db.execute(sql: "UPDATE subIssue SET id = ? WHERE id = ?", arguments: [new, old])
            try db.execute(sql: "UPDATE subIssue SET parentId = ? WHERE parentId = ?", arguments: [new, old])
            try db.execute(sql: "UPDATE linkedIssue SET id = ? WHERE id = ?", arguments: [new, old])
            try db.execute(sql: "UPDATE linkedIssue SET issueId = ? WHERE issueId = ?", arguments: [new, old])
        }
        for var entry in try Outbox.active(db) {
            let remapped = entry.mutation.remapping(remaps)
            if remapped != entry.mutation {
                entry.mutation = remapped
                try entry.update(db)
            }
        }
    }

    /// Gives up on a change GitHub refused, and says so.
    private static func discard(_ db: Database, entryId: Int64, error: Error) throws -> Notice? {
        guard let entry = try OutboxEntry.fetchOne(db, key: entryId) else { return nil }
        let summary = try entry.mutation.summary(db)
        try entry.delete(db)
        if case .createIssue(let m) = entry.mutation {
            try Item.deleteOne(db, key: m.itemId)
            try db.execute(sql: "DELETE FROM subIssue WHERE id = ?", arguments: [m.contentId])
        }
        if case .addComment(let m) = entry.mutation {
            try Comment.deleteOne(db, key: m.commentId)
        }
        // A refused change of parent or blocker is undone here too, so the lists show what GitHub has.
        if case .setParent(var m) = entry.mutation {
            m.parentId = m.base
            m.parentNumber = nil
            m.parentTitle = nil
            if let base = m.base, let parent = try Item.filter(Column("contentId") == base).fetchOne(db) {
                m.parentNumber = parent.number
                m.parentTitle = parent.title
            }
            try m.apply(db)
        }
        if case .setBlocking(var m) = entry.mutation {
            m.isBlocked = m.base
            try m.apply(db)
        }
        if case .deleteItem(let m) = entry.mutation {
            return Notice(title: String(localized: .noticeCouldNotDelete(issue: m.label)), message: error.localizedDescription, isWarning: true)
        }
        let gone = (error as? APIError)?.isNotFound ?? false
        return Notice(
            title: String(localized: gone
                ? .noticeNoLongerExistsOnGitHub(number: summary.number)
                : .noticeChangeNotSaved(number: summary.number)),
            message: String(localized: gone
                ? .noticeChangeDiscarded(change: summary.text)
                : .noticeChangeDiscardedWithError(change: summary.text, error: error.localizedDescription)),
            isWarning: true
        )
    }

    // MARK: Issue detail and repository data

    public func loadIssueDetail(contentId: String) async throws {
        guard !isDemo else { return }
        let detail = try await api.issueDetail(contentId: contentId)
        try await db.writer.write { db in
            try db.execute(
                sql: "DELETE FROM comment WHERE issueId = ? AND id NOT LIKE ?",
                arguments: [contentId, LocalID.prefix + "%"]
            )
            for comment in detail.comments { try comment.save(db) }
            try db.execute(
                sql: "DELETE FROM subIssue WHERE parentId = ? AND id NOT LIKE ?",
                arguments: [contentId, LocalID.prefix + "%"]
            )
            for sub in detail.subIssues { try sub.save(db) }
            try db.execute(
                sql: "DELETE FROM linkedIssue WHERE issueId = ? AND id NOT LIKE ?",
                arguments: [contentId, LocalID.prefix + "%"]
            )
            for link in detail.links { try link.save(db) }
            func open(_ relation: LinkedIssue.Relation) -> Int {
                detail.links.filter { $0.relation == relation && !$0.isClosed }.count
            }
            try db.execute(
                sql: "UPDATE item SET commentCount = ?, subTotal = ?, subCompleted = ?, blockedByCount = ?, blockingCount = ? WHERE contentId = ?",
                arguments: [
                    detail.comments.count, detail.subIssues.count, detail.subIssues.filter(\.isClosed).count,
                    open(.blockedBy), open(.blocking), contentId,
                ]
            )
            try Outbox.rebase(db)
        }
        if contentId == watchedIssueId { lastDetailPull = Date() }
    }

    /// Labels and assignable people of a repository that is on no board, for an issue seen only in the Inbox.
    public func repoMeta(repoId: String) async throws -> (labels: [LabelRef], users: [Person]) {
        if isDemo { return DemoData.repoMeta(repoId: repoId) }
        return try await api.repoMeta(repoId: repoId)
    }

    /// Labels and assignable people of a repository, for the pickers. Cached for ten minutes.
    public func loadRepoMeta(projectId: String?, repoId: String, force: Bool = false) async throws {
        guard !isDemo else { return }
        let existing = try await db.reader.read { db in
            try RepoRef.filter(Column("id") == repoId).order(Column("metaLoadedAt").desc).fetchOne(db)
        }
        // An issue's repository that none of your boards use has nowhere to keep its labels and people.
        guard existing != nil else { return }
        if !force, let loaded = existing?.metaLoadedAt, Date().timeIntervalSince(loaded) < 600 { return }
        let meta = try await api.repoMeta(repoId: repoId)
        try await db.writer.write { db in
            try db.execute(
                sql: "UPDATE repo SET labels = ?, assignableUsers = ?, metaLoadedAt = ? WHERE id = ?",
                arguments: [
                    String(decoding: try JSONEncoder().encode(meta.labels), as: UTF8.self),
                    String(decoding: try JSONEncoder().encode(meta.users), as: UTF8.self),
                    Date(), repoId,
                ]
            )
        }
    }

    // MARK: Columns

    /// Adds, renames, recolours, reorders or removes status columns. Needs a connection; not queued.
    public func updateOptions(projectId: String, fieldId: String, kind: OptionKind, options: [RemoteOption]) async throws {
        let saved = isDemo
            ? options.map { RemoteOption(id: $0.id ?? "demo-option-\(UUID().uuidString.lowercased())", name: $0.name, color: $0.color, descr: $0.descr) }
            : try await api.updateFieldOptions(fieldId: fieldId, options: options)
        try await db.writer.write { db in
            try FieldOption.filter(Column("projectId") == projectId && Column("fieldId") == fieldId).deleteAll(db)
            for (index, option) in saved.enumerated() {
                guard let id = option.id else { continue }
                try FieldOption(
                    id: id, fieldId: fieldId, projectId: projectId, kind: kind,
                    name: option.name, color: option.color, descr: option.descr, position: index
                ).insert(db)
            }
            // Cards that sat in a removed column have no status any more.
            let ids = saved.compactMap(\.id)
            let column = kind == .status ? "statusId" : "priorityId"
            let placeholders = ids.map { _ in "?" }.joined(separator: ",")
            try db.execute(
                sql: "UPDATE item SET \(column) = NULL WHERE projectId = ? AND \(column) IS NOT NULL AND \(column) NOT IN (\(placeholders))",
                arguments: StatementArguments([projectId] + ids)
            )
        }
        forceSweep.insert(projectId)
        kick()
    }

    /// Adds the opinionated Priority field to a project that has none.
    public func createPriorityField(projectId: String) async throws {
        if isDemo {
            try await createDemoPriorityField(projectId: projectId)
            return
        }
        _ = try await api.createSelectField(projectId: projectId, name: "Priority", options: Defaults.priorityOptions)
        forceSweep.insert(projectId)
        lastPull[projectId] = nil
        try await pull(projectId: projectId)
    }

    // MARK: Sample data

    /// A sync round on the sample data: queued changes are confirmed the way GitHub would confirm them.
    private func demoCycle() async {
        do {
            try await db.writer.write { try Outbox.purgeSent($0) }
            let heldSince = Date().addingTimeInterval(-Self.undoWindow)
            let pending = try await db.reader.read { db in
                try OutboxEntry.filter(Column("state") == OutboxState.pending.rawValue).order(Column("id")).fetchAll(db)
                    .filter { !($0.mutation.isUndoable && $0.createdAt > heldSince) }
            }
            guard !pending.isEmpty else {
                await finish(.idle, syncedAt: Date())
                return
            }
            await setPhase(.syncing)
            // A moment of sending, as over a real connection.
            try? await Task.sleep(for: .milliseconds(450))
            for entry in pending {
                guard let entryId = entry.id else { continue }
                var remaps: [String: String] = [:]
                switch entry.mutation {
                case .createIssue(var m):
                    let number = try await db.reader.read { db in
                        (try Int.fetchOne(db, sql: "SELECT MAX(number) FROM item") ?? 0) + 1
                    }
                    if m.dueDate != nil, let projectId = m.projectId { try await addDemoDueField(projectId: projectId) }
                    let contentId = "demo-issue-\(number)"
                    m.createdContentId = contentId
                    m.createdNumber = number
                    m.createdUrl = "https://github.com/\(m.repo)/issues/\(number)"
                    try await store(entry, mutation: .createIssue(m), state: .pending)
                    let itemId = m.projectId == nil ? Item.idWithoutProject(contentId) : "demo-item-\(number)"
                    remaps = [m.itemId: itemId, m.contentId: contentId]
                case .addToProject(let m):
                    remaps = [m.itemId: "demo-item-\(UUID().uuidString.lowercased())"]
                case .addComment(let m):
                    remaps = [m.commentId: "demo-comment-\(UUID().uuidString.lowercased())"]
                case .setDate(let m) where m.date != nil:
                    try await addDemoDueField(projectId: m.projectId)
                default:
                    break
                }
                let confirmed = remaps
                try await db.writer.write { db in
                    try Self.markSent(db, entryId: entryId, remaps: confirmed)
                    // GitHub keeps a parent's sub-issue progress and an issue's open blockers up to date by itself.
                    try db.execute(sql: """
                        UPDATE item SET
                          subTotal = (SELECT COUNT(*) FROM subIssue s WHERE s.parentId = item.contentId),
                          subCompleted = (SELECT COUNT(*) FROM subIssue s WHERE s.parentId = item.contentId AND s.state != 'OPEN'),
                          blockedByCount = (SELECT COUNT(*) FROM linkedIssue l WHERE l.issueId = item.contentId AND l.relation = 'blockedBy' AND l.state = 'OPEN'),
                          blockingCount = (SELECT COUNT(*) FROM linkedIssue l WHERE l.issueId = item.contentId AND l.relation = 'blocking' AND l.state = 'OPEN')
                        WHERE contentId IS NOT NULL
                        """)
                }
                if !remaps.isEmpty { await publish(remaps: remaps) }
            }
            await finish(.idle, syncedAt: Date())
        } catch {
            await finish(.failed(error.localizedDescription))
        }
    }

    /// The sample data's stand-in for adding "Due date" to a project on GitHub.
    private func addDemoDueField(projectId: String) async throws {
        try await db.writer.write { db in
            try db.execute(
                sql: "UPDATE project SET dueFieldId = ? WHERE id = ? AND dueFieldId IS NULL",
                arguments: ["demo-due-\(projectId)", projectId]
            )
        }
    }

    private func createDemoPriorityField(projectId: String) async throws {
        let fieldId = "demo-priority-\(projectId)"
        try await db.writer.write { db in
            for (index, option) in Defaults.priorityOptions.enumerated() {
                try FieldOption(
                    id: "\(fieldId)-\(index)", fieldId: fieldId, projectId: projectId, kind: .priority,
                    name: option.name, color: option.color, descr: option.descr, position: index
                ).insert(db)
            }
            try db.execute(sql: "UPDATE project SET priorityFieldId = ? WHERE id = ?", arguments: [fieldId, projectId])
        }
    }
}
