#if os(macOS)
import SwiftUI

public struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    public init() {}

    public var body: some View {
        ZStack {
            if model.signedIn {
                MainLayout()
                    .transition(.opacity)
            } else {
                SignInView()
                    .toolbar(removing: .title)
                    .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                    .background(Theme.window.ignoresSafeArea())
                    .transition(.opacity)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .font(.ui)
        .foregroundStyle(Theme.text)
        .tint(Theme.accent)
        .animation(Theme.overlay, value: model.signedIn)
        .background(WindowReader { model.mainWindow = $0 })
        .alert(
            Text(model.deletionCandidate.map { .deleteItemQuestion(number: $0.displayNumber) } ?? .deleteQuestion),
            isPresented: Binding(
                get: { model.deletionCandidate != nil },
                set: { if !$0 { model.deletionCandidate = nil } }
            ),
            presenting: model.deletionCandidate
        ) { item in
            // Return confirms, as in Linear; Escape cancels.
            Button(.delete, role: .destructive) { model.delete(item) }
                .keyboardShortcut(.defaultAction)
            Button(.cancel, role: .cancel) { model.deletionCandidate = nil }
        } message: { item in
            if item.kind == .draft {
                Text(.draftDeletionMessage(title: item.title))
            } else {
                Text(.issueDeletionMessage(title: item.title))
            }
        }
        .modifier(CompleteMilestoneAlert())
        .confirmationDialog(Text(.signOutEverywhereQuestion), isPresented: Bindable(model).confirmSignOutEverywhere) {
            Button(.signOutEverywhere, role: .destructive) { model.signOut(everywhere: true) }
            Button(.cancel, role: .cancel) {}
        } message: {
            Text(.signOutEverywhereMessage)
        }
        .alert(Text(.shareLoginQuestion), isPresented: Bindable(model).offerLoginSharing) {
            Button(.shareLogin) { model.answerLoginSharing(true) }
                .keyboardShortcut(.defaultAction)
            Button(.notNow, role: .cancel) { model.answerLoginSharing(false) }
        } message: {
            Text(.shareLoginMessage)
        }
        .task(id: model.signedIn) {
            try? await Task.sleep(for: .seconds(1.5))
            model.offerLoginSharingIfUseful()
        }
        .onChange(of: model.settingsRequest) {
            openSettings()
        }
        // The Inbox's unread number on the Dock icon, as Mail shows it.
        .onChange(of: model.dockBadge, initial: true) { _, badge in
            NSApp.dockTile.badgeLabel = badge
        }
        .onChange(of: model.status.idRemaps) { _, remaps in
            model.follow(remaps: remaps)
        }
        // Initial too: without a token the first sync fails before this view is on screen.
        .onChange(of: model.status.phase, initial: true) { _, phase in
            if phase == .unauthorized { model.signedIn = false }
        }
    }
}

/// The window, built like Notes, Mail and the other apps on the Mac: the sidebar, the page with a glass toolbar over
/// it, and beside an open issue an inspector with its properties.
struct MainLayout: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 340)
        } detail: {
            ContentPanel()
        }
        .overlay {
            OverlayHost()
        }
        .overlay(alignment: .bottom) {
            // Above the selection bar while issues are picked.
            ToastStack()
                .padding(.bottom, model.selectedIds.isEmpty ? 20 : 76)
                .animation(Theme.overlay, value: model.selectedIds.isEmpty)
        }
    }
}

struct ContentPanel: View {
    @Environment(AppModel.self) private var model
    @AppStorage("showsIssueInspector") private var showsInspector = true
    /// Ticks so the subtitle's "Synced 2 min ago" stays true.
    @State private var clock = Date()

    var body: some View {
        let openItem = model.openItem
        ZStack {
            // The board stays mounted underneath an open issue so it is exactly as you left it on return.
            VStack(spacing: 0) {
                if model.scope == .inbox {
                    InboxView()
                        .transition(.opacity)
                } else {
                    if let view = model.currentView {
                        FilterBar(view: view)
                        // A view of one iteration says which, when, and how far it is, as Linear's cycles.
                        if let pinned = model.pinnedIteration(of: view) {
                            CycleHeader(view: view, pinned: pinned)
                                .padding(.leading, 18)
                                .padding(.trailing, 12)
                                .frame(height: 40)
                        }
                    }
                    if case .milestone(let projectId, let title) = model.scope,
                       let group = model.milestoneGroup(projectId: projectId, title: title) {
                        MilestoneSummary(projectId: projectId, group: group)
                    }
                    if model.scope == nil {
                        EmptyState(
                            title: String(localized: model.projects.isEmpty ? .lookingForProjects : .chooseProject),
                            message: String(localized: model.projects.isEmpty ? .noProjectsMessage : .pickProjectInSidebar)
                        )
                    } else if model.isLoadingProject {
                        ProjectLoadingState()
                            .transition(.opacity)
                    } else if case .milestone(let projectId, let title) = model.scope,
                              model.milestoneGroup(projectId: projectId, title: title) == nil {
                        EmptyState(
                            title: String(localized: .milestoneGoneTitle),
                            message: String(localized: .milestoneGoneMessage(milestone: title))
                        ) {
                            Button(.showBoard) { model.select(.project(projectId)) }
                                .buttonStyle(SecondaryButtonStyle())
                        }
                    } else if case .roadmap(let projectId) = model.scope {
                        RoadmapView(projectId: projectId)
                            .transition(.opacity)
                    } else if let view = model.currentView, model.showsTimeline(view) {
                        // GitHub's roadmap layout: the view's issues on a timeline.
                        ViewTimeline(view: view, open: { model.open($0) })
                            .transition(.opacity)
                    } else if model.viewMode == .board, model.currentProjectId != nil {
                        // Another view's board starts at its beginning, not where the last one was scrolled to.
                        BoardView()
                            .id(model.currentView?.id)
                            .transition(.opacity)
                    } else {
                        IssueListView()
                            .transition(.opacity)
                    }
                }
            }
            .animation(Theme.overlay, value: model.isLoadingProject)
            // Picked issues get a bar of changes at the bottom; Space peeks at an issue on the right.
            .overlay(alignment: .bottom) {
                // Centred in what the peek leaves free.
                SelectionBar()
                    .padding(.bottom, 18)
                    .padding(.trailing, model.peekItemId == nil ? 0 : 470)
            }
            .overlay(alignment: .trailing) {
                if let item = model.peekItem {
                    PeekPanel(item: item)
                        .padding(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 10))
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(Theme.overlay, value: model.selectedIds.isEmpty)
            .animation(Theme.overlay, value: model.peekItemId == nil)
            .opacity(openItem == nil ? 1 : 0)
            .allowsHitTesting(openItem == nil)

            if let item = openItem {
                IssueDetailView(item: item)
                    .id(item.id)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(x: 14)),
                        removal: .opacity.combined(with: .offset(x: 14))
                    ))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.panel.ignoresSafeArea())
        .overlay { SwipeIndicator() }
        .animation(Theme.overlay, value: model.openItemId)
        .navigationTitle(title(openItem))
        .navigationSubtitle(subtitle(openItem))
        .toolbar {
            MainToolbar(model: model, openItem: openItem, showsInspector: $showsInspector)
        }
        .inspector(isPresented: Binding(
            get: { openItem != nil && showsInspector },
            set: { shown in if openItem != nil { showsInspector = shown } }
        )) {
            Group {
                if let item = openItem {
                    IssueProperties(item: item)
                        .id(item.id)
                } else {
                    Color.clear
                }
            }
            .inspectorColumnWidth(min: 250, ideal: 290, max: 380)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                clock = Date()
            }
        }
    }

    /// The window's title, as Mail names the mailbox: the view, the issue or the place on screen.
    private func title(_ openItem: Item?) -> String {
        if let openItem { return openItem.displayNumber }
        switch model.scope {
        case .project:
            if let view = model.currentView { return view.name }
            return model.currentProject?.title ?? "Issues"
        case .myIssues:
            return String(localized: .myIssues)
        case .inbox:
            return String(localized: .inbox)
        case .repository:
            return model.currentRepository?.shortName ?? "Issues"
        case .milestone(_, let title):
            return title
        case .roadmap:
            return String(localized: .roadmap)
        case nil:
            return "Issues"
        }
    }

    /// Under the title: where it belongs and how syncing is going, as Mail writes "Updated Just Now".
    private func subtitle(_ openItem: Item?) -> String {
        let sync = model.syncLine(at: clock)
        if let openItem {
            if let project = model.project(of: openItem) { return project.title }
            return openItem.repo ?? ""
        }
        switch model.scope {
        case .project:
            guard model.currentView != nil, let project = model.currentProject else { return sync }
            return "\(project.title) · \(sync)"
        case .milestone(let projectId, _), .roadmap(let projectId):
            return model.projects.first { $0.id == projectId }?.title ?? sync
        case .repository:
            guard let repo = model.currentRepository else { return sync }
            return "\(repo.nameWithOwner.dropLast(repo.shortName.count + 1)) · \(sync)"
        case .inbox:
            let unread = model.inboxUnreadCount
            return unread > 0 ? String(localized: .unreadCount(count: unread)) : sync
        case .myIssues, nil:
            return sync
        }
    }
}

/// The arrow that grows at the side of the page while a two-finger swipe goes back or forward, filled once letting
/// go will go. It stays inside the page, clear of the sidebar and the inspector floating at its edges.
struct SwipeIndicator: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // One arrow on each side, so the one that fades out stays where it was.
        let progress = model.swipeProgress / AppModel.swipeThreshold
        HStack {
            arrow(back: true, reach: min(max(progress, 0), 1))
            Spacer()
            arrow(back: false, reach: min(max(-progress, 0), 1))
        }
        .padding(.horizontal, 16)
        .allowsHitTesting(false)
    }

    private func arrow(back: Bool, reach: Double) -> some View {
        let full = reach >= 1
        return Image(systemName: back ? "chevron.left" : "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(full ? Color.white : Theme.textSecondary)
            .frame(width: 34, height: 34)
            .background {
                if full { Circle().fill(Theme.accentFill) }
            }
            .glassPanel(in: Circle())
            .scaleEffect(0.6 + 0.4 * reach)
            .offset(x: (back ? 12 : -12) * (reach - 1))
            .opacity(min(reach * 3, 1))
            .animation(Theme.quick, value: full)
    }
}

struct EmptyState<Accessory: View>: View {
    var title: String
    var message: String
    var showsProgress: Bool
    var accessory: Accessory

    init(title: String, message: String, showsProgress: Bool = false, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.message = message
        self.showsProgress = showsProgress
        self.accessory = accessory()
    }

    var body: some View {
        VStack(spacing: 6) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
                    .padding(.bottom, 6)
            }
            Text(title).font(.uiSemibold)
            Text(message)
                .font(.ui)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            accessory
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EmptyState where Accessory == EmptyView {
    init(title: String, message: String, showsProgress: Bool = false) {
        self.init(title: title, message: message, showsProgress: showsProgress) { EmptyView() }
    }
}

/// Shown in the board and the list alike until a project has been fetched from GitHub once.
/// Afterwards the local copy is shown straight away and refreshed in the background.
struct ProjectLoadingState: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.status.phase {
        case .offline:
            EmptyState(title: String(localized: .youreOffline), message: String(localized: .projectLoadsWhenOnline))
        case .failed(let message):
            EmptyState(title: String(localized: .projectLoadFailed), message: message) {
                Button(.tryAgain) { model.refresh() }
                    .buttonStyle(SecondaryButtonStyle())
            }
        default:
            EmptyState(title: String(localized: .loadingIssues), message: String(localized: .fetchingProject), showsProgress: true)
        }
    }
}

/// Dimmed backdrop plus whichever modal is open: command palette or new issue.
struct OverlayHost: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack(alignment: .top) {
            if let overlay = model.overlay {
                Theme.scrim
                    .ignoresSafeArea()
                    .onTapGesture { model.overlay = nil }
                    .transition(.opacity)

                Group {
                    switch overlay {
                    case .palette(let mode):
                        CommandPalette(mode: mode)
                            .id(mode)
                            .padding(.top, 120)
                    case .newIssue(let statusId, let parentItemId):
                        NewIssueView(statusId: statusId, parentItemId: parentItemId)
                            .padding(.top, 110)
                    case .milestoneEditor(let projectId, let title, let assigning):
                        MilestoneEditor(projectId: projectId, title: title, assigning: assigning)
                            .padding(.top, 110)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)).combined(with: .offset(y: -6)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Theme.overlay, value: model.overlay)
    }
}
#endif
