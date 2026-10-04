import AppKit
import GRDB
import Network
import Observation
import SwiftUI

struct BoardColumn: Identifiable, Equatable {
    static let noStatusId = "no-status"

    var id: String
    var option: FieldOption?
    var glyph: StatusGlyph
    var items: [Item]

    var title: String { option?.name ?? "No status" }
}

struct ListSection: Identifiable, Equatable {
    var id: String
    var title: String
    var glyph: StatusGlyph
    var option: FieldOption?
    var items: [Item]
}

enum PaletteMode: Hashable {
    case root
    case status(itemId: String)
    case priority(itemId: String)
    case assignees(itemId: String)
    case labels(itemId: String)
    case projects
}

enum Overlay: Equatable {
    case palette(PaletteMode)
    case newIssue(statusId: String?, parentItemId: String?)
}

enum ViewMode: String {
    case board
    case list
}

enum Scope: Hashable {
    case project(String)
    case myIssues
}

/// Everything the views read, kept in step with the database, plus navigation state.
@MainActor
@Observable
public final class AppModel {
    let db: AppDatabase
    let auth: AuthStore
    let engine: SyncEngine
    public let status: SyncStatus
    let boardDrag = BoardDrag()

    // Data mirrored from the database.
    private(set) var viewer: Viewer?
    private(set) var projects: [Project] = []
    private(set) var allItems: [Item] = []
    private(set) var options: [FieldOption] = []
    private(set) var repos: [RepoRef] = []
    private(set) var outbox: [OutboxEntry] = []
    private(set) var comments: [Comment] = []
    private(set) var subIssues: [SubIssue] = []

    // Derived from the above for the current scope.
    private(set) var columns: [BoardColumn] = []
    private(set) var sections: [ListSection] = []
    private(set) var glyphs: [String: StatusGlyph] = [:]

    // Navigation.
    var signedIn: Bool
    private(set) var scope: Scope?
    var viewMode: ViewMode {
        didSet {
            UserDefaults.standard.set(viewMode.rawValue, forKey: "viewMode")
            recordNavigation()
        }
    }
    private(set) var openItemId: String?
    /// The issue the keyboard focus is on. The issue under the pointer is tracked separately and is not
    /// observed, so moving the mouse over a long list does not redraw it.
    var focusedItemId: String?
    @ObservationIgnored var hoveredItemId: String?

    /// Light, dark, or whatever the system is set to.
    var appearance: AppearanceSetting {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: "appearance")
            appearance.apply()
        }
    }

    /// Which icon the app shows in the Dock while it is running.
    var appIcon: AppIconChoice {
        didSet {
            UserDefaults.standard.set(appIcon.rawValue, forKey: AppIconChoice.defaultsKey)
            appIcon.apply()
        }
    }

    // Back and forward, like a browser.
    var history: [Location] = []
    var historyIndex = -1
    @ObservationIgnored var isRestoringLocation = false
    /// -1...1 while a two-finger swipe is in progress; positive means "going back".
    var swipeProgress: Double = 0
    /// Bumped when avatar images arrive, so painted rows redraw with them.
    var avatarVersion = 0
    /// Bumped to ask for the settings window from places that cannot open it themselves.
    var settingsRequest = 0
    /// The issue waiting for "Delete?" to be confirmed.
    var deletionCandidate: Item?
    /// Bumped when a list section is folded in or out, so the list redraws.
    var collapseVersion = 0
    /// A new issue that was closed before it was created, kept for the next time the dialog opens.
    @ObservationIgnored var unsentNewIssue: NewIssueDraft?
    /// Projects tucked away in the sidebar. They can still be found in the command palette.
    var hiddenProjectIds = Set(UserDefaults.standard.stringArray(forKey: "hiddenProjects") ?? []) {
        didSet { UserDefaults.standard.set(Array(hiddenProjectIds), forKey: "hiddenProjects") }
    }
    var overlay: Overlay? {
        didSet {
            if overlay != nil, overlay != oldValue { overlayOpenedAt = Date() }
        }
    }
    /// When the current dialog or palette opened, and keys typed before its text field had focus.
    @ObservationIgnored var overlayOpenedAt: Date?
    @ObservationIgnored var heldKeys: [NSEvent] = []
    @ObservationIgnored var heldKeysTimer: Timer?
    /// The app's main window, to tell it apart from popovers and the settings window.
    @ObservationIgnored weak var mainWindow: NSWindow?
    /// Set while a board drag is in progress so keyboard shortcuts stay out of the way.
    var isDragging = false
    /// Bumped when Escape is pressed during a drag.
    var dragCancelToken = 0
    /// Bumped when the keyboard moves the focus, so lists can scroll it into view.
    var focusScrollToken = 0
    /// Issues picked to change together (X, ⌘-click, Shift-click).
    var selectedIds: Set<String> = []
    /// Where a Shift-click or Shift-arrow range starts, and the range it added last.
    @ObservationIgnored var selectionAnchorId: String?
    @ObservationIgnored var selectionRange: Set<String> = []
    /// The issue shown in the quick look that Space opens.
    var peekItemId: String?

    @ObservationIgnored private var dataObservation: AnyDatabaseCancellable?
    @ObservationIgnored private var detailObservation: AnyDatabaseCancellable?
    @ObservationIgnored private var pathMonitor: NWPathMonitor?
    @ObservationIgnored var keyMonitorToken: Any?
    @ObservationIgnored var pendingGoTo: Date?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    public init() {
        do {
            db = try AppDatabase.onDisk()
        } catch {
            fatalError("Could not open the local database: \(error)")
        }
        auth = AuthStore()
        status = SyncStatus()
        engine = SyncEngine(db: db, api: GitHubAPI(client: GraphQLClient(tokenSource: auth)), status: status)
        signedIn = auth.isSignedIn
        viewMode = ViewMode(rawValue: UserDefaults.standard.string(forKey: "viewMode") ?? "") ?? .board
        appearance = AppearanceSetting(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system
        appIcon = AppIconChoice(rawValue: UserDefaults.standard.string(forKey: AppIconChoice.defaultsKey) ?? "") ?? .standard
        appearance.apply()
        appIcon.apply()
        startObserving()
        restoreScope()
        installKeyMonitor()
        installNavigationMonitors()
        #if DEBUG
        DebugRemote.startIfRequested(model: self)
        #endif
        if signedIn { startSyncing() }
    }

    // MARK: Session

    func startSyncing() {
        Task {
            await engine.setActiveProject(currentProjectId)
            await engine.start()
        }
        if pathMonitor == nil {
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { [engine] path in
                if path.status == .satisfied { Task { await engine.kick() } }
            }
            monitor.start(queue: .global(qos: .utility))
            pathMonitor = monitor
        }
        if observers.isEmpty {
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [engine] _ in
                Task {
                    await engine.setPollInterval(15)
                    await engine.kick()
                }
            })
            observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [engine] _ in
                Task { await engine.setPollInterval(60) }
            })
        }
    }

    func completeSignIn() {
        signedIn = true
        startSyncing()
    }

    func signOut() {
        Task {
            await engine.stop()
            await auth.signOut()
            try? db.wipe()
            signedIn = false
            scope = nil
            openItemId = nil
            history = []
            historyIndex = -1
            overlay = nil
            status.phase = .idle
            status.notices = []
        }
    }

    // MARK: Observing the database

    private struct Snapshot {
        var viewer: Viewer?
        var projects: [Project]
        var items: [Item]
        var options: [FieldOption]
        var repos: [RepoRef]
        var outbox: [OutboxEntry]
    }

    private nonisolated static func fetchSnapshot(_ db: Database) throws -> Snapshot {
        Snapshot(
            viewer: try KV.viewer(db),
            projects: try Project
                .order(Column("closed"), Column("ownerLogin").collating(.localizedCaseInsensitiveCompare), Column("title").collating(.localizedCaseInsensitiveCompare))
                .fetchAll(db),
            items: try Item.order(Column("position")).fetchAll(db),
            options: try FieldOption.order(Column("position")).fetchAll(db),
            repos: try RepoRef.order(Column("nameWithOwner")).fetchAll(db),
            outbox: try OutboxEntry.order(Column("id")).fetchAll(db)
        )
    }

    private func startObserving() {
        let observation = ValueObservation.tracking { try Self.fetchSnapshot($0) }
        dataObservation = observation.start(
            in: db.reader,
            scheduling: .immediate,
            onError: { error in print("Database observation failed: \(error)") },
            onChange: { [weak self] snapshot in
                MainActor.assumeIsolated { self?.apply(snapshot) }
            }
        )
    }

    /// Reads the database right now instead of waiting for the observation, so a user action shows in the same frame.
    func reloadNow() {
        if let snapshot = try? db.reader.read({ try Self.fetchSnapshot($0) }) {
            apply(snapshot)
        }
        if let contentId = openItem?.contentId {
            loadDetail(contentId: contentId)
        }
    }

    private func apply(_ snapshot: Snapshot) {
        if viewer != snapshot.viewer { viewer = snapshot.viewer }
        var listed = snapshot.projects
        #if DEBUG
        // For screenshots and demos: show a single project and hide the rest.
        if let only = UserDefaults.standard.string(forKey: "debugOnlyProject") {
            listed = listed.filter { $0.title == only }
        }
        #endif
        if projects != listed { projects = listed }
        if options != snapshot.options { options = snapshot.options }
        if repos != snapshot.repos { repos = snapshot.repos }
        if allItems != snapshot.items { allItems = snapshot.items }
        outbox = snapshot.outbox
        if scope == nil { restoreScope() }
        rebuild()
    }

    private func observeDetail(contentId: String?) {
        detailObservation = nil
        comments = []
        subIssues = []
        guard let contentId else { return }
        let observation = ValueObservation.tracking { db in
            (
                try Comment.filter(Column("issueId") == contentId).order(Column("createdAt")).fetchAll(db),
                try SubIssue.filter(Column("parentId") == contentId).order(Column("position")).fetchAll(db)
            )
        }
        detailObservation = observation.start(
            in: db.reader,
            scheduling: .immediate,
            onError: { _ in },
            onChange: { [weak self] value in
                MainActor.assumeIsolated {
                    self?.comments = value.0
                    self?.subIssues = value.1
                }
            }
        )
    }

    private func loadDetail(contentId: String) {
        if let value = try? db.reader.read({ db in
            (
                try Comment.filter(Column("issueId") == contentId).order(Column("createdAt")).fetchAll(db),
                try SubIssue.filter(Column("parentId") == contentId).order(Column("position")).fetchAll(db)
            )
        }) {
            comments = value.0
            subIssues = value.1
        }
    }

    // MARK: Derived data

    var currentProjectId: String? {
        if case .project(let id) = scope { return id }
        return nil
    }

    var currentProject: Project? {
        currentProjectId.flatMap { id in projects.first { $0.id == id } }
    }

    /// True until the open project has been fetched from GitHub once.
    var isLoadingProject: Bool {
        currentProject.map { $0.lastSyncedAt == nil } ?? false
    }

    var openItem: Item? {
        openItemId.flatMap { id in allItems.first { $0.id == id } }
    }

    /// Items of the current scope, in board order.
    var scopedItems: [Item] {
        switch scope {
        case .project(let id): allItems.filter { $0.projectId == id }
        case .myIssues:
            if let login = viewer?.login {
                allItems.filter { item in item.assignees.contains { $0.login == login } }
            } else {
                []
            }
        case nil: []
        }
    }

    func project(of item: Item) -> Project? {
        projects.first { $0.id == item.projectId }
    }

    func statusOptions(projectId: String) -> [FieldOption] {
        options.filter { $0.projectId == projectId && $0.kind == .status }
    }

    func priorityOptions(projectId: String) -> [FieldOption] {
        options.filter { $0.projectId == projectId && $0.kind == .priority }
    }

    func statusOption(of item: Item) -> FieldOption? {
        guard let id = item.statusId else { return nil }
        return options.first { $0.id == id && $0.projectId == item.projectId && $0.kind == .status }
    }

    func priorityOption(of item: Item) -> FieldOption? {
        guard let id = item.priorityId else { return nil }
        return options.first { $0.id == id && $0.projectId == item.projectId && $0.kind == .priority }
    }

    func priorityLevel(of item: Item) -> PriorityLevel {
        priorityOption(of: item)?.priorityLevel ?? .none
    }

    func glyph(of item: Item) -> StatusGlyph {
        glyph(projectId: item.projectId, optionId: item.statusId)
    }

    /// GitHub reuses option ids across projects (every default "Todo" has the same one), so glyphs are keyed per project.
    func glyph(projectId: String, optionId: String?) -> StatusGlyph {
        optionId.flatMap { glyphs["\(projectId)/\($0)"] } ?? .none
    }

    func repos(projectId: String) -> [RepoRef] {
        repos.filter { $0.projectId == projectId }
    }

    func repo(of item: Item) -> RepoRef? {
        repos.first { $0.projectId == item.projectId && $0.id == item.repoId }
    }

    /// The project item for an issue's node id, if that issue is on a board we know.
    func item(contentId: String) -> Item? {
        allItems.first { $0.contentId == contentId }
    }

    var pendingCount: Int {
        outbox.filter { $0.state == .pending }.count
    }

    func conflict(for item: Item) -> [OutboxEntry] {
        outbox.filter { $0.state == .conflict && $0.mutation.contentId == item.contentId }
    }

    private func rebuild() {
        var map: [String: StatusGlyph] = [:]
        for project in projects {
            for (optionId, glyph) in StatusGlyph.map(for: statusOptions(projectId: project.id)) {
                map["\(project.id)/\(optionId)"] = glyph
            }
        }
        if glyphs != map { glyphs = map }

        let items = scopedItems
        var newColumns: [BoardColumn] = []
        var newSections: [ListSection] = []

        switch scope {
        case .project(let projectId):
            let statuses = statusOptions(projectId: projectId)
            let known = Set(statuses.map(\.id))
            let unsorted = items.filter { $0.statusId == nil || !known.contains($0.statusId!) }
            if !unsorted.isEmpty {
                newColumns.append(BoardColumn(id: BoardColumn.noStatusId, option: nil, glyph: .none, items: unsorted))
            }
            for option in statuses {
                newColumns.append(BoardColumn(
                    id: option.id, option: option, glyph: map["\(projectId)/\(option.id)"] ?? .none,
                    items: items.filter { $0.statusId == option.id }
                ))
            }
            // The list leads with what is being worked on, like Linear does.
            func rank(_ column: BoardColumn) -> Int {
                guard let option = column.option else { return 3 }
                switch option.statusCategory {
                case .started: return 0
                case .unstarted: return 1
                case .backlog: return 2
                case .completed: return 4
                case .canceled: return 5
                }
            }
            let ordered = newColumns.enumerated().sorted { a, b in
                let ra = rank(a.element), rb = rank(b.element)
                if ra != rb { return ra < rb }
                // Within "started", later columns (closer to done) come first.
                return ra == 0 ? a.offset > b.offset : a.offset < b.offset
            }.map(\.element)
            newSections = ordered.filter { !$0.items.isEmpty }.map {
                ListSection(id: $0.id, title: $0.title, glyph: $0.glyph, option: $0.option, items: $0.items)
            }

        case .myIssues:
            let groups: [(StatusCategory?, String)] = [
                (.started, "In progress"), (.unstarted, "Todo"), (.backlog, "Backlog"),
                (nil, "No status"), (.completed, "Done"), (.canceled, "Canceled"),
            ]
            for (category, title) in groups {
                let matching = items.filter { statusOption(of: $0)?.statusCategory == category }
                guard !matching.isEmpty else { continue }
                let glyph: StatusGlyph = switch category {
                case .started: StatusGlyph(category: .started, progress: 0.5, color: Theme.started)
                case .unstarted: StatusGlyph(category: .unstarted, progress: 0, color: Theme.textBody)
                case .completed: StatusGlyph(category: .completed, progress: 1, color: Theme.accent)
                case .canceled: StatusGlyph(category: .canceled, progress: 0, color: Theme.textTertiary)
                default: .none
                }
                newSections.append(ListSection(id: title, title: title, glyph: glyph, option: nil, items: matching))
            }

        case nil:
            break
        }
        // Sections the user dragged into their own order keep it.
        let custom = customListOrder
        if !custom.isEmpty {
            newSections = newSections.enumerated().sorted { a, b in
                let ia = custom.firstIndex(of: a.element.id) ?? Int.max
                let ib = custom.firstIndex(of: b.element.id) ?? Int.max
                return ia != ib ? ia < ib : a.offset < b.offset
            }.map(\.element)
        }
        if columns != newColumns { columns = newColumns }
        if sections != newSections { sections = newSections }
    }

    // MARK: Navigation

    private func restoreScope() {
        guard scope == nil, !projects.isEmpty else { return }
        let saved = UserDefaults.standard.string(forKey: "selectedProject")
        let project = projects.first { $0.id == saved }
            ?? projects.first { !$0.closed && !hiddenProjectIds.contains($0.id) }
            ?? projects.first { !$0.closed } ?? projects.first
        if let project { select(.project(project.id)) }
    }

    func select(_ newScope: Scope) {
        scope = newScope
        openItemId = nil
        focusedItemId = nil
        clearSelection()
        peekItemId = nil
        observeDetail(contentId: nil)
        if case .project(let id) = newScope {
            UserDefaults.standard.set(id, forKey: "selectedProject")
            Task { await engine.setActiveProject(id) }
        }
        Task { await engine.setWatchedIssue(nil) }
        rebuild()
        recordNavigation()
    }

    func open(_ item: Item, replacingHistory: Bool = false) {
        peekItemId = nil
        focusedItemId = item.id
        openItemId = item.id
        recordNavigation(replacing: replacingHistory)
        observeDetail(contentId: item.contentId)
        let contentId = item.contentId
        let projectId = item.projectId
        let repoId = item.repoId
        let fetchable = item.kind != .draft && !item.isLocalOnly
        Task {
            await engine.setWatchedIssue(fetchable ? contentId : nil)
            // Fetch comments and sub-issues right away rather than at the next sync cycle.
            if fetchable, let contentId { try? await engine.loadIssueDetail(contentId: contentId) }
            if let repoId { try? await engine.loadRepoMeta(projectId: projectId, repoId: repoId) }
        }
    }

    /// Back from the open issue, with its back button or Escape: to the issue it was opened from, such as the
    /// parent of a sub-issue, or else to the board or list.
    func leaveIssue() {
        if historyIndex > 0, history.indices.contains(historyIndex) {
            let previous = history[historyIndex - 1]
            if previous.scope == scope, let id = previous.itemId, id != openItemId, allItems.contains(where: { $0.id == id }) {
                goBack()
                return
            }
        }
        closeDetail()
    }

    func closeDetail() {
        guard openItemId != nil else { return }
        // Closing an issue returns to where it was opened from, so Forward brings it back.
        if !isRestoringLocation, historyIndex > 0,
           history[historyIndex - 1] == Location(scope: scope, viewMode: viewMode, itemId: nil) {
            goBack()
            return
        }
        openItemId = nil
        observeDetail(contentId: nil)
        Task { await engine.setWatchedIssue(nil) }
        recordNavigation()
    }

    /// Follows an issue whose temporary id was replaced after GitHub created it.
    func follow(remaps: [String: String]) {
        if let id = openItemId, let new = remaps[id] {
            openItemId = new
            if let item = openItem { open(item) }
        }
        if let id = focusedItemId, let new = remaps[id] { focusedItemId = new }
        if let id = hoveredItemId, let new = remaps[id] { hoveredItemId = new }
        for index in history.indices {
            if let id = history[index].itemId, let new = remaps[id] { history[index].itemId = new }
        }
    }

    /// Fetches the avatars of everyone assigned to something in view, once.
    func preloadAvatars() async {
        let urls = Set(scopedItems.flatMap(\.assignees).compactMap(\.avatarUrl))
        var loadedAny = false
        for url in urls where AvatarCache.shared.cached(url) == nil {
            if await AvatarCache.shared.load(url) != nil { loadedAny = true }
        }
        if loadedAny { avatarVersion += 1 }
    }

    func loadRepoMeta(projectId: String) {
        let ids = repos(projectId: projectId).map(\.id)
        Task {
            for id in ids { try? await engine.loadRepoMeta(projectId: projectId, repoId: id) }
        }
    }

    func refresh() {
        Task { await engine.forceRefresh() }
    }

    // MARK: Writing

    /// Applies mutations locally and queues them for GitHub.
    func perform(_ mutations: [Mutation]) {
        guard !mutations.isEmpty else { return }
        do {
            try db.writer.write { db in
                for mutation in mutations { try Outbox.enqueue(db, mutation) }
            }
            reloadNow()
        } catch {
            status.post(Notice(title: "That change could not be saved", message: error.localizedDescription, isWarning: true))
        }
        Task { await engine.kick() }
    }

    func resolveConflict(_ entry: OutboxEntry, keepMine: Bool) {
        guard let id = entry.id else { return }
        try? db.writer.write { try Outbox.resolveConflict($0, entryId: id, keepMine: keepMine) }
        reloadNow()
        Task { await engine.kick() }
    }
}
