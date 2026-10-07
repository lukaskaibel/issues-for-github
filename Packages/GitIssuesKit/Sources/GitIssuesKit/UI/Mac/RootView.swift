#if os(macOS)
import SwiftUI

public struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    public init() {}

    public var body: some View {
        ZStack {
            Theme.window.ignoresSafeArea()
            if model.signedIn {
                MainLayout()
                    .transition(.opacity)
            } else {
                SignInView()
                    .transition(.opacity)
            }
        }
        .frame(minWidth: 980, minHeight: 600)
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

struct MainLayout: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
                .frame(width: Theme.sidebarWidth)
            ContentPanel()
        }
        .ignoresSafeArea()
        .overlay {
            OverlayHost()
        }
        .overlay(alignment: .bottomTrailing) {
            ToastStack()
                .padding(20)
        }
    }
}

struct ContentPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            // The board stays mounted underneath an open issue so it is exactly as you left it on return.
            VStack(spacing: 0) {
                if model.scope == .inbox {
                    InboxView()
                        .transition(.opacity)
                } else {
                    ProjectHeader()
                    if model.scope == nil {
                        EmptyState(
                            title: String(localized: model.projects.isEmpty ? .lookingForProjects : .chooseProject),
                            message: String(localized: model.projects.isEmpty ? .noProjectsMessage : .pickProjectInSidebar)
                        )
                    } else if model.isLoadingProject {
                        ProjectLoadingState()
                            .transition(.opacity)
                    } else if model.viewMode == .board, model.currentProjectId != nil {
                        BoardView()
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
                        .padding(EdgeInsets(top: 52, leading: 0, bottom: 10, trailing: 10))
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(Theme.overlay, value: model.selectedIds.isEmpty)
            .animation(Theme.overlay, value: model.peekItemId == nil)
            .opacity(model.openItem == nil ? 1 : 0)
            .allowsHitTesting(model.openItem == nil)

            if let item = model.openItem {
                IssueDetailView(item: item)
                    .id(item.id)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(x: 14)),
                        removal: .opacity.combined(with: .offset(x: 14))
                    ))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.panelBorder, lineWidth: 1))
        .overlay { SwipeIndicator() }
        .padding(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 8))
        .animation(Theme.overlay, value: model.openItemId)
    }
}

/// The arrow that slides in from the edge while a two-finger swipe is deciding whether to go back or forward.
struct SwipeIndicator: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let progress = model.swipeProgress
        let amount = min(abs(progress), 1)
        HStack {
            if progress < 0 { Spacer() }
            Image(systemName: progress > 0 ? "chevron.left" : "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(amount >= 0.5 ? Color.white : Theme.textSecondary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(amount >= 0.5 ? Theme.accentFill : Theme.popover))
                .overlay(Circle().stroke(Theme.popoverBorder, lineWidth: amount >= 0.5 ? 0 : 1))
                .shadow(color: Theme.shadow, radius: 10, y: 4)
                .scaleEffect(0.7 + 0.3 * amount)
                .offset(x: (progress > 0 ? 1 : -1) * (-40 + 56 * amount))
            if progress > 0 { Spacer() }
        }
        .opacity(amount == 0 ? 0 : 1)
        .allowsHitTesting(false)
    }
}

struct ProjectHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 8) {
            switch model.scope {
            case .project:
                if let project = model.currentProject {
                    ProjectSwatch(title: project.title)
                    Text(project.title).font(.uiSemibold).lineLimit(1)
                    ViewModeSwitch(mode: $model.viewMode)
                        .padding(.leading, 10)
                }
            case .myIssues:
                Image(systemName: "scope").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textSecondary)
                Text(.myIssues).font(.uiSemibold)
            case .repository:
                if let repo = model.currentRepository {
                    RepositoryIcon()
                    // Owner and name as GitHub writes them; there is no board, so no switch between board and list.
                    let owner = Text(repo.nameWithOwner.dropLast(repo.shortName.count)).foregroundStyle(Theme.textSecondary)
                    Text("\(owner)\(Text(repo.shortName).font(.uiSemibold))")
                        .lineLimit(1)
                }
            case .inbox, nil:
                EmptyView()
            }
            Spacer()
            if let repo = model.currentRepository, let url = repo.url {
                Button {
                    Platform.open(url)
                } label: {
                    HStack(spacing: 5) {
                        Text(.openOnGitHub)
                        Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold))
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .help(Text(.openRepositoryOnGitHubTooltip(repository: repo.nameWithOwner)))
            }
            if let project = model.currentProject, project.priorityFieldId == nil, project.viewerCanUpdate, project.lastSyncedAt != nil {
                Button(.addPriorityField) { model.addPriorityField(projectId: project.id) }
                    .buttonStyle(SecondaryButtonStyle())
                    .help(Text(.addPriorityFieldTooltip))
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .frame(height: Theme.headerHeight)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.panelBorder).frame(height: 1)
        }
    }
}

struct ViewModeSwitch: View {
    @Binding var mode: ViewMode
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            segment(.board, .board)
            segment(.list, .list)
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.control))
    }

    private func segment(_ title: LocalizedStringResource, _ value: ViewMode) -> some View {
        Button {
            withAnimation(Theme.spring) { mode = value }
        } label: {
            Text(title)
                .font(.smallMedium)
                .foregroundStyle(mode == value ? Theme.text : Theme.textSecondary)
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background {
                    if mode == value {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Theme.segmentActive)
                            .matchedGeometryEffect(id: "segment", in: namespace)
                    }
                }
        }
        .buttonStyle(PlainPressStyle())
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
            EmptyState(title: String(localized: .projectCouldNotLoad), message: message) {
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
