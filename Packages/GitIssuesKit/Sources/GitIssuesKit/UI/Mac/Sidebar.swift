#if os(macOS)
import GRDB
import SwiftUI

/// What the sidebar can select: a place, the project's issues, one of its views or milestones, or its roadmap.
enum SidebarSelection: Hashable {
    case inbox
    case myIssues
    /// A project before its views have been read: its board.
    case board(String)
    case view(projectId: String, viewId: String)
    case milestone(projectId: String, title: String)
    case roadmap(String)
    case allIssues(String)
}

/// The system's sidebar, as in Notes and Mail: the project at the top with its menu, the Inbox and My Issues, then
/// All Issues and the project's views, and its next milestones with the roadmap. One project at a time, as Linear
/// shows one workspace.
struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List(selection: selection) {
            Section {
                SidebarProjectHeader()
                    .selectionDisabled()
                Label { Text(.inbox) } icon: { Image(systemName: "tray") }
                    .badge(model.inboxUnreadCount)
                    .tag(SidebarSelection.inbox)
                    .help(Text(.inboxShortcutTooltip))
                    .accessibilityValue(model.inboxUnreadCount > 0 ? String(localized: .unreadCount(count: model.inboxUnreadCount)) : "")
                    .sidebarReselect(.inbox, current: current)
                Label { Text(.myIssues) } icon: { Image(systemName: "scope") }
                    .tag(SidebarSelection.myIssues)
                    .sidebarReselect(.myIssues, current: current)
            }
            if let project = model.sidebarProject {
                SidebarProject(project: project, current: current)
            }
        }
        .listStyle(.sidebar)
        // The system's own text colour instead of the window's, so a selected row turns it white on the accent.
        .foregroundStyle(.primary)
        // Nothing while everything is on GitHub; a card when you're offline or something needs you.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let attention = model.syncAttention {
                SyncHintCard(attention: attention)
                    .padding(10)
                    .transition(.opacity.combined(with: .offset(y: 8)))
            }
        }
        .animation(Theme.overlay, value: model.syncAttention)
        .toolbar {
            ToolbarItem {
                Button {
                    model.overlay = .newIssue(statusId: nil, parentItemId: nil)
                } label: {
                    Label(String(localized: .newIssueAction), systemImage: "square.and.pencil")
                }
                .help(Text(.newIssueShortcutTooltip))
                .disabled(model.projects.isEmpty)
            }
        }
    }

    /// The row for what is on screen.
    private var current: SidebarSelection? {
        switch model.scope {
        case .inbox: .inbox
        case .myIssues: .myIssues
        case .project(let id):
            if let view = model.currentView { .view(projectId: id, viewId: view.id) } else { .board(id) }
        case .milestone(let projectId, let title): .milestone(projectId: projectId, title: title)
        case .roadmap(let id): .roadmap(id)
        case .allIssues(let id): .allIssues(id)
        case nil: nil
        }
    }

    private var selection: Binding<SidebarSelection?> {
        Binding {
            current
        } set: { selection in
            guard let selection, selection != current else { return }
            switch selection {
            case .inbox: model.select(.inbox)
            case .myIssues: model.select(.myIssues)
            case .board(let id): model.select(.project(id))
            case .view(_, let viewId): if let view = model.view(id: viewId) { model.show(view) }
            case .milestone(let projectId, let title): model.select(.milestone(projectId: projectId, title: title))
            case .roadmap(let id): model.select(.roadmap(id))
            case .allIssues(let id): model.select(.allIssues(id))
            }
        }
    }
}

extension View {
    /// A click on the row of what is on screen while an issue is open goes back to it, as the row always did; the
    /// list itself only reports clicks that change what is selected.
    func sidebarReselect(_ row: SidebarSelection, current: SidebarSelection?) -> some View {
        modifier(SidebarReselect(row: row, current: current))
    }
}

private struct SidebarReselect: ViewModifier {
    @Environment(AppModel.self) private var model
    var row: SidebarSelection
    var current: SidebarSelection?

    func body(content: Content) -> some View {
        content.simultaneousGesture(TapGesture().onEnded {
            if row == current, model.openItem != nil { model.closeDetail() }
        })
    }
}

/// The project the sidebar is about, at its top, as Linear shows its workspace and Mail its accounts: its icon with
/// the state of syncing as a dot, its name, and its menu.
private struct SidebarProjectHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let project = model.sidebarProject {
                ProjectMenuButton(project: project)
            } else {
                AccountMenuButton()
            }
        }
        .padding(.bottom, 4)
    }
}

/// A milestone of the sidebar's project: its diamond, its name and when it is due.
struct MilestoneRow: View {
    @Environment(AppModel.self) private var model
    /// Increased on the selected row, which is filled with the accent colour.
    @Environment(\.backgroundProminence) private var prominence
    var projectId: String
    var group: MilestoneGroup
    var current: SidebarSelection?

    var body: some View {
        let row = SidebarSelection.milestone(projectId: projectId, title: group.title)
        Label {
            Text(group.title).lineLimit(1)
        } icon: {
            MilestoneIcon(mark: model.mark(of: group, projectId: projectId), size: 13, tint: prominence == .increased ? .white : nil)
        }
        .badge(dueBadge)
        .help(group.due.map { Text(.dueOn(date: $0.longLabel)) } ?? Text(group.title))
        .glassSidebarMenu { [model, projectId, group] in MilestoneMenuItems.menu(projectId: projectId, group: group, model: model) }
        .sidebarReselect(row, current: current)
        // Last, so the list sees it: under the menu's modifier it can't, and the row can't be selected.
        .tag(row)
    }

    private var dueBadge: Text? {
        guard let due = group.due else { return nil }
        let today = CalendarDay.today()
        let text = Text(due.shortLabel(today: today)).monospacedDigit()
        return due < today && prominence != .increased ? text.foregroundStyle(Theme.overdue) : text
    }
}

/// The roadmap of the sidebar's project.
struct RoadmapRow: View {
    @Environment(AppModel.self) private var model
    var projectId: String
    var current: SidebarSelection?

    var body: some View {
        let row = SidebarSelection.roadmap(projectId)
        Label {
            Text(.roadmap).lineLimit(1)
        } icon: {
            RoadmapIcon(size: 14)
        }
        .help(Text(.roadmapShortcutTooltip))
        .glassSidebarMenu { [model, projectId] in
            guard model.projects.first(where: { $0.id == projectId })?.viewerCanUpdate == true else { return nil }
            let menu = MenuBuilder()
            menu.item(.newEpic, "plus") {
                model.select(.roadmap(projectId))
                model.newIssuePlan = NewIssuePlan(isEpic: true)
                model.overlay = .newIssue(statusId: nil, parentItemId: nil)
            }
            menu.item(.newMilestoneEllipsis, "plus") {
                model.overlay = .milestoneEditor(projectId: projectId, title: nil, assigning: [])
            }
            return menu.build()
        }
        .sidebarReselect(row, current: current)
        .tag(row)
    }
}

/// All Issues of the sidebar's project: its board's issues and those of its repositories on no board, with how many
/// of them are on no board as a quiet count, as the Inbox counts what is unread.
struct AllIssuesRow: View {
    @Environment(AppModel.self) private var model
    var projectId: String
    var current: SidebarSelection?

    var body: some View {
        let row = SidebarSelection.allIssues(projectId)
        let onNoBoard = model.countOnNoBoard(projectId: projectId)
        Label { Text(.allIssues) } icon: { Image(systemName: "rectangle.stack") }
            .badge(onNoBoard)
            .help(Text(.allIssuesShortcutTooltip))
            .accessibilityValue(onNoBoard > 0 ? String(localized: .noBoardCount(count: onNoBoard)) : "")
            .sidebarReselect(row, current: current)
            .tag(row)
    }
}

/// The account at the top of the sidebar while there is no project: the avatar with the state of syncing as a dot,
/// and the login. Clicking it opens the account menu; the tooltip says when the app last synced.
struct AccountMenuButton: View {
    @Environment(AppModel.self) private var model
    @State private var open = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 20)) { context in
            Button {
                open = true
            } label: {
                HStack(spacing: 9) {
                    StatusAvatar(size: 24)
                    Text(model.viewer?.login ?? "GitHub")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.text)
                .frame(height: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(model.accountSummary(at: context.date))
            .accessibilityLabel(.account)
            .accessibilityValue(model.accountSummary(at: context.date))
            .dropdown(isPresented: $open) { close in
                AccountDropdown(close: close)
            }
        }
    }
}

/// The menu of the project at the top of the sidebar, as Linear's workspace menu: who is signed in and how syncing is
/// going, the projects to switch to, then Sync Now, the queue, appearance, settings and signing out. It opens as a
/// dropdown like the pickers; the arrow keys move, Return picks, → opens a submenu.
struct AccountDropdown: View {
    @Environment(AppModel.self) private var model
    /// The project the sidebar is about; the menu lists the others to switch to.
    var project: Project?
    var close: () -> Void

    @State private var cursor = MenuCursor<Entry>()
    @State private var queueOpen = false
    @State private var appearanceOpen = false
    @State private var hiddenOpen = false

    enum Entry: Hashable {
        case project(String), hidden, more, sync, queue, appearance, settings, signOut, signOutEverywhere
    }

    /// Up to this many projects are listed; with more, the command palette finds them by name.
    private static let listed = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            MenuDivider()
            if project != nil {
                Text(.projects)
                    .font(.tinySemibold)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 12)
                    .padding(.top, 2)
                    .padding(.bottom, 4)
                ForEach(listedProjects) { project in
                    row(.project(project.id))
                }
                if !hiddenProjects.isEmpty {
                    row(.hidden)
                        .dropdown(isPresented: $hiddenOpen, placement: .trailing) { close in
                            HiddenProjectsMenu(projects: hiddenProjects, close: {
                                close()
                                self.close()
                            })
                        }
                }
                if shownProjects.count > Self.listed {
                    row(.more)
                }
                MenuDivider()
            }
            row(.sync)
            if waiting > 0 {
                row(.queue)
                    .dropdown(isPresented: $queueOpen, placement: .trailing) { close in
                        QueueList(close: close)
                    }
            }
            MenuDivider()
            row(.appearance)
                .dropdown(isPresented: $appearanceOpen, placement: .trailing) { close in
                    AppearanceDropdown(close: close)
                }
            row(.settings)
            MenuDivider()
            row(.signOut)
            if model.loginIsShared { row(.signOutEverywhere) }
        }
        .padding(.bottom, 4)
        .frame(width: 264)
        .font(.ui)
        .foregroundStyle(Theme.text)
        .background(MenuKeys(
            onMove: { cursor.step($0, through: entries) },
            onActivate: { if let active = cursor.key { perform(active) } },
            onOpen: { if let active = cursor.key, active == .queue || active == .appearance || active == .hidden { perform(active) } }
        ))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                AccountAvatar(size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.viewer?.login ?? "GitHub").font(.uiSemibold).lineLimit(1)
                    Text(model.viewer?.name ?? String(localized: model.isDemo ? .sampleData : .signedInWithGitHub))
                        .font(.small)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            TimelineView(.periodic(from: .now, by: 20)) { context in
                HStack(spacing: 10) {
                    SyncDot(style: model.syncDotStyle, size: 7)
                        .frame(width: 16)
                    Text(model.syncLine(at: context.date))
                        .font(.small)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
    }

    /// Changes not yet on GitHub, including any that need a decision.
    private var waiting: Int {
        model.outbox.filter { $0.state != .sent }.count
    }

    private var shownProjects: [Project] {
        model.openProjects.filter { !model.hiddenProjectIds.contains($0.id) }
    }

    /// The projects in the menu: the first few, and the one the sidebar is about wherever it comes.
    private var listedProjects: [Project] {
        var list = Array(shownProjects.prefix(Self.listed))
        if let project, !list.contains(where: { $0.id == project.id }) {
            if list.count == Self.listed { list.removeLast() }
            list.append(project)
        }
        return list
    }

    private var hiddenProjects: [Project] {
        model.openProjects.filter { model.hiddenProjectIds.contains($0.id) }
    }

    private var entries: [Entry] {
        var list: [Entry] = []
        if project != nil {
            list += listedProjects.map { .project($0.id) }
            if !hiddenProjects.isEmpty { list.append(.hidden) }
            if shownProjects.count > Self.listed { list.append(.more) }
        }
        list.append(.sync)
        if waiting > 0 { list.append(.queue) }
        list += [.appearance, .settings, .signOut]
        if model.loginIsShared { list.append(.signOutEverywhere) }
        return list
    }

    @ViewBuilder
    private func row(_ entry: Entry) -> some View {
        switch entry {
        case .project(let id):
            if let other = model.openProjects.first(where: { $0.id == id }) {
                ProjectMenuRow(project: other, checked: other.id == project?.id, cursor: cursor, key: entry, action: { perform(entry) })
            }
        case .hidden:
            MenuRow(title: String(localized: .hiddenProjectsCount(count: hiddenProjects.count)), systemImage: "eye.slash", submenu: true, cursor: cursor, key: entry, open: hiddenOpen, action: { perform(entry) })
        case .more:
            MenuRow(title: String(localized: .switchProjectEllipsis), systemImage: "square.stack", cursor: cursor, key: entry, action: { perform(entry) })
        case .sync:
            MenuRow(title: String(localized: .syncNow), systemImage: "arrow.triangle.2.circlepath", shortcut: "⌘R", cursor: cursor, key: entry, action: { perform(entry) })
        case .queue:
            MenuRow(title: String(localized: .queuedChangesTitle), systemImage: "tray.full", value: "\(waiting)", submenu: true, cursor: cursor, key: entry, open: queueOpen, action: { perform(entry) })
        case .appearance:
            MenuRow(title: String(localized: .appearance), systemImage: "circle.lefthalf.filled", value: model.appearance.title, submenu: true, cursor: cursor, key: entry, open: appearanceOpen, action: { perform(entry) })
        case .settings:
            MenuRow(title: String(localized: .settingsEllipsis), systemImage: "gearshape", shortcut: "⌘,", cursor: cursor, key: entry, action: { perform(entry) })
        case .signOut:
            MenuRow(title: String(localized: model.isDemo ? .leaveSampleData : .signOut), systemImage: "rectangle.portrait.and.arrow.right", cursor: cursor, key: entry, action: { perform(entry) })
        case .signOutEverywhere:
            MenuRow(title: String(localized: .signOutEverywhereEllipsis), cursor: cursor, key: entry, action: { perform(entry) })
        }
    }

    private func perform(_ entry: Entry) {
        switch entry {
        case .project(let id):
            close()
            model.select(.project(id))
        case .hidden:
            hiddenOpen = true
        case .more:
            close()
            model.overlay = .palette(.projects)
        case .sync:
            close()
            model.refresh()
        case .queue:
            queueOpen = true
        case .appearance:
            appearanceOpen = true
        case .settings:
            close()
            model.settingsRequest += 1
        case .signOut:
            close()
            model.requestSignOut()
        case .signOutEverywhere:
            close()
            model.confirmSignOutEverywhere = true
        }
    }
}

/// System, Light or Dark, as a submenu of the account menu.
struct AppearanceDropdown: View {
    @Environment(AppModel.self) private var model
    var close: () -> Void
    @State private var cursor = MenuCursor<AppearanceSetting>()

    var body: some View {
        let options = AppearanceSetting.allCases
        VStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                MenuRow(
                    title: option.title, systemImage: option.systemImage, checked: model.appearance == option,
                    cursor: cursor, key: option, action: { pick(option) }
                )
            }
        }
        .padding(.vertical, 4)
        .frame(width: 176)
        .font(.ui)
        .foregroundStyle(Theme.text)
        .background(MenuKeys(
            onMove: { cursor.step($0, through: Array(options)) },
            onActivate: { if let active = cursor.key { pick(active) } },
            onBack: close
        ))
    }

    private func pick(_ option: AppearanceSetting) {
        model.appearance = option
        // Done with the account menu too, as with a menu.
        Dropdown.close()
    }
}

// MARK: - Syncing

/// What needs your attention about syncing, at the bottom of the sidebar: being offline, a change to decide on,
/// or a sync that failed. Nothing shows while everything is fine; the dot on the avatar says that.
struct SyncHintCard: View {
    @Environment(AppModel.self) private var model
    var attention: SyncAttention
    @State private var queueOpen = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: attention.systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.warning)
                .frame(width: 14, height: 15)
            VStack(alignment: .leading, spacing: 2) {
                Text(attention.title)
                    .font(.smallMedium)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(attention.message)
                    .font(.tiny)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                if let action = attention.actionTitle {
                    Button(action, action: perform)
                        .buttonStyle(SecondaryButtonStyle())
                        .padding(.top, 6)
                        .dropdown(isPresented: $queueOpen, placement: .above) { close in
                            QueueList(close: close)
                        }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 9)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.cardBorder, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private func perform() {
        switch attention {
        case .conflict(_, _, let itemId):
            if let itemId { model.apply(.openItem(itemId)) }
        case .failed:
            model.refresh()
        case .offline:
            queueOpen = true
        }
    }
}

/// Changes saved on this Mac and waiting to be sent, with the ones that need a decision marked.
struct QueueList: View {
    @Environment(AppModel.self) private var model
    var close: () -> Void

    var body: some View {
        let waiting = model.outbox.filter { $0.state != .sent }
        VStack(alignment: .leading, spacing: 0) {
            Text(waiting.isEmpty ? .everythingSavedToGitHub : .queuedChanges)
                .font(.tinySemibold)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 6)

            ForEach(waiting.prefix(12)) { entry in
                let summary = model.summary(of: entry)
                HStack(spacing: 10) {
                    Text(summary.number)
                        .font(.small)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 36, alignment: .leading)
                    Text(entry.state == .conflict ? String(localized: .changeNeedsDecision(change: summary.text)) : summary.text)
                        .lineLimit(1)
                    Spacer(minLength: 12)
                    Text(entry.createdAt, style: .relative)
                        .font(.small)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 14)
                .frame(height: 30)
            }
            if waiting.count > 12 {
                Text(.moreQueuedChanges(count: waiting.count - 12))
                    .font(.small)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 14)
                    .frame(height: 26)
            }

            Divider().overlay(Theme.popoverBorder).padding(.top, 6)
            HStack {
                Text(footer)
                    .font(.small)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button(.syncNowButton) { model.refresh() }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 340)
        .font(.ui)
        .foregroundStyle(Theme.text)
        .background(MenuKeys(onMove: { _ in }, onActivate: {}, onBack: close))
    }

    private var footer: String {
        switch model.status.phase {
        case .offline: String(localized: .sendsWhenBackOnline)
        case .failed(let message): message
        default: String(localized: .changesSavedLocallyFirst)
        }
    }
}

// MARK: - Toasts

struct ToastStack: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 10) {
            ForEach(model.status.notices) { notice in
                ToastView(notice: notice)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 12)),
                        removal: .opacity.combined(with: .scale(scale: 0.96))
                    ))
            }
        }
        .animation(Theme.overlay, value: model.status.notices)
    }
}

struct ToastView: View {
    @Environment(AppModel.self) private var model
    var notice: Notice

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: notice.isWarning ? "exclamationmark.triangle" : notice.action?.isUndo == true ? "checkmark.circle" : "arrow.triangle.2.circlepath")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(notice.isWarning ? Theme.warning : Theme.accent)
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(notice.title).font(.uiSemibold)
                    Text(notice.message)
                        .font(.small)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if notice.action?.isUndo == true {
                    Button(.undo) {
                        if let action = notice.action { model.apply(action) }
                        model.status.dismiss(notice.id)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut("z", modifiers: .command)
                } else if let label = notice.action?.adoptLabel {
                    HStack(spacing: 8) {
                        Button(.keepMineMac) { model.status.dismiss(notice.id) }
                            .buttonStyle(SecondaryButtonStyle())
                        Button(label) {
                            if let action = notice.action { model.apply(action) }
                            model.status.dismiss(notice.id)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
            Spacer(minLength: 0)
            IconButton(systemName: "xmark", label: String(localized: .dismiss), size: 20) {
                model.status.dismiss(notice.id)
            }
        }
        .padding(.vertical, 12)
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .frame(width: 380, alignment: .leading)
        // Glass at the bottom of the window, as iOS shows what just happened with its Undo.
        .glassPanel(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .task {
            // Notices that ask for a decision stay until answered; one that can be undone stays a little longer.
            guard notice.action == nil || notice.action?.isUndo == true else { return }
            try? await Task.sleep(for: .seconds(notice.isWarning || notice.action?.isUndo == true ? 10 : 4))
            model.status.dismiss(notice.id)
        }
    }
}
#endif
