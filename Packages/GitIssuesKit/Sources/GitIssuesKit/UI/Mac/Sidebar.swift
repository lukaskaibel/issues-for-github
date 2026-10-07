#if os(macOS)
import GRDB
import SwiftUI

struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Room for the window's traffic lights, with back and forward on the right.
            HStack(spacing: 2) {
                Spacer()
                IconButton(systemName: "chevron.left", label: String(localized: .backShortcutTooltip)) { model.goBack() }
                    .disabled(!model.canGoBack)
                    .opacity(model.canGoBack ? 1 : 0.35)
                IconButton(systemName: "chevron.right", label: String(localized: .forwardShortcutTooltip)) { model.goForward() }
                    .disabled(!model.canGoForward)
                    .opacity(model.canGoForward ? 1 : 0.35)
            }
            .frame(height: 44)

            // The account, with the state of syncing as a dot on the avatar, then search and a new issue, as in
            // Linear's workspace header.
            HStack(spacing: 2) {
                AccountMenuButton()
                Spacer(minLength: 4)
                SidebarIconButton(systemName: "magnifyingglass", label: .search, help: .searchShortcutTooltip) {
                    model.overlay = .palette(.root)
                }
                Button {
                    model.overlay = .newIssue(statusId: nil, parentItemId: nil)
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textBody)
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.hover))
                }
                .buttonStyle(PlainPressStyle())
                .help(Text(.newIssueShortcutTooltip))
                .accessibilityLabel(.newIssueAction)
                .disabled(model.currentProjectId == nil && model.currentRepositoryId == nil)
            }
            .padding(.trailing, 6)
            .frame(height: 32)
            .padding(.bottom, 8)

            SidebarRow(title: .inbox, systemImage: "tray", active: model.scope == .inbox, count: model.inboxUnreadCount) {
                model.select(.inbox)
            }
            .help(Text(.inboxShortcutTooltip))
            SidebarRow(title: .myIssues, systemImage: "scope", active: model.scope == .myIssues) {
                model.select(.myIssues)
            }

            Text(.projects)
                .font(.tinySemibold)
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 6)
                .padding(.top, 14)
                .padding(.bottom, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    let open = model.projects.filter { !$0.closed }
                    ForEach(open.filter { !model.hiddenProjectIds.contains($0.id) }) { project in
                        ProjectRow(project: project, hidden: false)
                    }
                    HiddenGroup(count: open.filter { model.hiddenProjectIds.contains($0.id) }.count, noun: "projects") {
                        ForEach(open.filter { model.hiddenProjectIds.contains($0.id) }) { project in
                            ProjectRow(project: project, hidden: true)
                        }
                    }

                    // Like the teams in Linear: every issue of a repository, whether it is on a board or not.
                    let repos = model.boardRepositories
                    if !repos.isEmpty {
                        Text(.repositories)
                            .font(.tinySemibold)
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.top, 14)
                            .padding(.bottom, 4)
                        ForEach(repos.filter { !model.hiddenRepositoryIds.contains($0.id) }) { repo in
                            RepositoryRow(repo: repo, hidden: false)
                        }
                        HiddenGroup(count: repos.filter { model.hiddenRepositoryIds.contains($0.id) }.count, noun: "repositories") {
                            ForEach(repos.filter { model.hiddenRepositoryIds.contains($0.id) }) { repo in
                                RepositoryRow(repo: repo, hidden: true)
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.never)

            // Nothing while everything is on GitHub; a card when you're offline or something needs you.
            if let attention = model.syncAttention {
                SyncHintCard(attention: attention)
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .offset(y: 8)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .animation(Theme.overlay, value: model.syncAttention)
    }
}

/// One project in the sidebar. Right-click to hide it, copy its link or open it on GitHub.
struct ProjectRow: View {
    @Environment(AppModel.self) private var model
    var project: Project
    var hidden: Bool

    var body: some View {
        let active = model.scope == .project(project.id)
        Button {
            model.select(.project(project.id))
        } label: {
            HStack(spacing: 8) {
                ProjectSwatch(title: project.title)
                    .opacity(hidden ? 0.5 : 1)
                Text(project.title).lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(active ? .uiMedium : .ui)
            .foregroundStyle(active ? Theme.text : hidden ? Theme.textTertiary : Theme.textSecondary)
            .padding(.horizontal, 6)
            .frame(height: 28)
            .hoverFill(active: active)
        }
        .buttonStyle(PlainPressStyle())
        .help("\(project.ownerLogin) · \(project.title)")
        .contextMenu {
            if hidden {
                Button(.showInSidebar, systemImage: "eye") { model.setHidden(project, false) }
            } else {
                Button(.hideFromSidebar, systemImage: "eye.slash") { model.setHidden(project, true) }
            }
            Divider()
            Button(.copyLink, systemImage: "link") { model.copyLink(project.url, for: project.title) }
            Button(.openOnGitHub, systemImage: "arrow.up.right.square") {
                if let url = URL(string: project.url) { NSWorkspace.shared.open(url) }
            }
        }
        .transition(.opacity)
    }
}

/// One repository in the sidebar. Right-click to hide it, copy its link or open it on GitHub.
struct RepositoryRow: View {
    @Environment(AppModel.self) private var model
    var repo: RepoRef
    var hidden: Bool

    var body: some View {
        let active = model.scope == .repository(repo.id)
        Button {
            model.select(.repository(repo.id))
        } label: {
            HStack(spacing: 8) {
                RepositoryIcon()
                    .foregroundStyle(active ? Theme.textSecondary : Theme.textTertiary)
                    .opacity(hidden ? 0.5 : 1)
                Text(model.displayName(of: repo)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(active ? .uiMedium : .ui)
            .foregroundStyle(active ? Theme.text : hidden ? Theme.textTertiary : Theme.textSecondary)
            .padding(.horizontal, 6)
            .frame(height: 28)
            .hoverFill(active: active)
        }
        .buttonStyle(PlainPressStyle())
        .help(repo.nameWithOwner)
        .contextMenu {
            if hidden {
                Button(.showInSidebar, systemImage: "eye") { model.setHidden(repo, false) }
            } else {
                Button(.hideFromSidebar, systemImage: "eye.slash") { model.setHidden(repo, true) }
            }
            Divider()
            if let url = repo.url {
                Button(.copyLink, systemImage: "link") { model.copyLink(url.absoluteString, for: repo.nameWithOwner) }
                Button(.openOnGitHub, systemImage: "arrow.up.right.square") { NSWorkspace.shared.open(url) }
            }
        }
        .transition(.opacity)
    }
}

/// Hidden projects or repositories fold away under one quiet line at the end of their list.
struct HiddenGroup<Rows: View>: View {
    var count: Int
    /// "projects" or "repositories", which picks the texts.
    var noun: String
    @ViewBuilder var rows: Rows
    @State var expanded = false

    var body: some View {
        if count > 0 {
            Button {
                withAnimation(Theme.spring) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 14)
                    Text(isProjects ? .hiddenProjectsCount(count: count) : .hiddenRepositoriesCount(count: count))
                    Spacer(minLength: 0)
                }
                .font(.small)
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 6)
                .frame(height: 26)
                .hoverFill()
            }
            .buttonStyle(PlainPressStyle())
            .help(Text(tooltip))
            if expanded {
                rows
            }
        }
    }

    private var isProjects: Bool { noun == "projects" }

    private var tooltip: LocalizedStringResource {
        if isProjects { return expanded ? .foldHiddenProjectsAway : .showHiddenProjects }
        return expanded ? .foldHiddenRepositoriesAway : .showHiddenRepositories
    }
}

/// The account at the top of the sidebar: the avatar with the state of syncing as a dot, and the login. Clicking it
/// opens the account menu; the tooltip says when the app last synced.
struct AccountMenuButton: View {
    @Environment(AppModel.self) private var model
    @State private var open = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 20)) { context in
            Button {
                open = true
            } label: {
                HStack(spacing: 8) {
                    StatusAvatar(size: 20)
                    Text(model.viewer?.login ?? "GitHub")
                        .font(.uiSemibold)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 6)
                .frame(height: 28)
                .hoverFill(active: open)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainPressStyle())
            .help(model.accountSummary(at: context.date))
            .accessibilityLabel(.account)
            .accessibilityValue(model.accountSummary(at: context.date))
            .dropdown(isPresented: $open) { close in
                AccountDropdown(close: close)
            }
        }
    }
}

/// A small icon button in the sidebar's header that lights up under the pointer.
struct SidebarIconButton: View {
    var systemName: String
    var label: LocalizedStringResource
    var help: LocalizedStringResource
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textBody)
                .frame(width: 26, height: 26)
                .hoverFill()
        }
        .buttonStyle(PlainPressStyle())
        .help(Text(help))
        .accessibilityLabel(label)
    }
}

/// The account menu: who is signed in and how syncing is going, then Sync Now, the queue, appearance, settings and
/// signing out. It opens as a dropdown like the pickers; the arrow keys move, Return picks, → opens a submenu.
struct AccountDropdown: View {
    @Environment(AppModel.self) private var model
    var close: () -> Void

    @State private var active: Entry?
    @State private var queueOpen = false
    @State private var appearanceOpen = false

    enum Entry: Hashable {
        case sync, queue, appearance, settings, signOut, signOutEverywhere
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            MenuDivider()
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
            onMove: { delta in
                let list = entries
                let index = menuStep(active.flatMap { list.firstIndex(of: $0) }, by: delta, count: list.count)
                active = index.map { list[$0] }
            },
            onActivate: { if let active { perform(active) } },
            onOpen: { if active == .queue || active == .appearance, let active { perform(active) } }
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

    private var entries: [Entry] {
        var list: [Entry] = [.sync]
        if waiting > 0 { list.append(.queue) }
        list += [.appearance, .settings, .signOut]
        if model.loginIsShared { list.append(.signOutEverywhere) }
        return list
    }

    @ViewBuilder
    private func row(_ entry: Entry) -> some View {
        let isActive = active == entry
        let hover: (Bool) -> Void = { inside in
            if inside { active = entry } else if active == entry { active = nil }
        }
        switch entry {
        case .sync:
            MenuRow(title: String(localized: .syncNow), systemImage: "arrow.triangle.2.circlepath", shortcut: "⌘R", active: isActive, action: { perform(entry) }, onHover: hover)
        case .queue:
            MenuRow(title: String(localized: .queuedChangesMenuItem), systemImage: "tray.full", value: "\(waiting)", submenu: true, active: isActive || queueOpen, action: { perform(entry) }, onHover: hover)
        case .appearance:
            MenuRow(title: String(localized: .appearance), systemImage: "circle.lefthalf.filled", value: model.appearance.title, submenu: true, active: isActive || appearanceOpen, action: { perform(entry) }, onHover: hover)
        case .settings:
            MenuRow(title: String(localized: .settingsEllipsis), systemImage: "gearshape", shortcut: "⌘,", active: isActive, action: { perform(entry) }, onHover: hover)
        case .signOut:
            MenuRow(title: String(localized: model.isDemo ? .leaveSampleData : .signOut), systemImage: "rectangle.portrait.and.arrow.right", active: isActive, action: { perform(entry) }, onHover: hover)
        case .signOutEverywhere:
            MenuRow(title: String(localized: .signOutEverywhereEllipsis), active: isActive, action: { perform(entry) }, onHover: hover)
        }
    }

    private func perform(_ entry: Entry) {
        switch entry {
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
            model.signOut()
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
    @State private var active: Int?

    var body: some View {
        let options = AppearanceSetting.allCases
        VStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element) { index, option in
                MenuRow(
                    title: option.title, systemImage: option.systemImage, checked: model.appearance == option,
                    active: active == index, action: { pick(option) },
                    onHover: { inside in
                        if inside { active = index } else if active == index { active = nil }
                    }
                )
            }
        }
        .padding(.vertical, 4)
        .frame(width: 176)
        .font(.ui)
        .foregroundStyle(Theme.text)
        .background(MenuKeys(
            onMove: { active = menuStep(active, by: $0, count: options.count) },
            onActivate: { if let active { pick(options[active]) } },
            onBack: close
        ))
    }

    private func pick(_ option: AppearanceSetting) {
        model.appearance = option
        // Done with the account menu too, as with a menu.
        Dropdown.close()
    }
}

struct SidebarRow: View {
    var title: LocalizedStringResource
    var systemImage: String
    var active = false
    /// Shown on the right when there is something: the Inbox's unread entries.
    var count = 0
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 14)
                Text(title)
                Spacer(minLength: 0)
                if count > 0 {
                    Text("\(count)")
                        .font(.small)
                        .monospacedDigit()
                        .foregroundStyle(active ? Theme.text : Theme.textSecondary)
                        .contentTransition(.numericText())
                }
            }
            .foregroundStyle(active ? Theme.text : Theme.textSecondary)
            .padding(.horizontal, 6)
            .frame(height: 28)
            .hoverFill(active: active)
            .animation(Theme.quick, value: count)
        }
        .buttonStyle(PlainPressStyle())
        .accessibilityValue(count > 0 ? String(localized: .unreadCount(count: count)) : "")
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
            Text(waiting.isEmpty ? .everythingSavedToGitHub : .queuedChangesHeader)
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
        VStack(alignment: .trailing, spacing: 10) {
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
            Image(systemName: notice.isWarning ? "exclamationmark.triangle" : "arrow.triangle.2.circlepath")
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
                if let label = notice.action?.adoptLabel {
                    HStack(spacing: 8) {
                        Button(.keepMine) { model.status.dismiss(notice.id) }
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
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .frame(width: 360, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.popover))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.popoverBorder, lineWidth: 1))
        .shadow(color: Theme.shadow, radius: 18, y: 10)
        .task {
            // Notices that ask for a decision stay until answered.
            guard notice.action == nil else { return }
            try? await Task.sleep(for: .seconds(notice.isWarning ? 10 : 4))
            model.status.dismiss(notice.id)
        }
    }
}
#endif
