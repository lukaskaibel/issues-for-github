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
                IconButton(systemName: "chevron.left", label: "Back (⌘[)") { model.goBack() }
                    .disabled(!model.canGoBack)
                    .opacity(model.canGoBack ? 1 : 0.35)
                IconButton(systemName: "chevron.right", label: "Forward (⌘])") { model.goForward() }
                    .disabled(!model.canGoForward)
                    .opacity(model.canGoForward ? 1 : 0.35)
            }
            .frame(height: 44)

            HStack(spacing: 8) {
                AccountMenu()
                Spacer(minLength: 4)
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
                .help("New issue (C)")
                .accessibilityLabel("New issue")
                .disabled(model.currentProjectId == nil)
            }
            .padding(.trailing, 6)
            .frame(height: 32)
            .padding(.bottom, 8)

            SidebarRow(title: "Search", systemImage: "magnifyingglass", trailing: "⌘K") {
                model.overlay = .palette(.root)
            }
            SidebarRow(title: "My Issues", systemImage: "scope", active: model.scope == .myIssues) {
                model.select(.myIssues)
            }

            Text("Projects")
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
                    HiddenProjects(projects: open.filter { model.hiddenProjectIds.contains($0.id) })
                }
            }
            .scrollIndicators(.never)

            SyncIndicator()
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
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
                Button("Show in Sidebar", systemImage: "eye") { model.setHidden(project, false) }
            } else {
                Button("Hide from Sidebar", systemImage: "eye.slash") { model.setHidden(project, true) }
            }
            Divider()
            Button("Copy Link", systemImage: "link") { model.copyLink(project.url, for: project.title) }
            Button("Open on GitHub", systemImage: "arrow.up.right.square") {
                if let url = URL(string: project.url) { NSWorkspace.shared.open(url) }
            }
        }
        .transition(.opacity)
    }
}

/// Hidden projects fold away under one quiet line at the end of the list.
struct HiddenProjects: View {
    var projects: [Project]
    @State var expanded = false

    var body: some View {
        if !projects.isEmpty {
            Button {
                withAnimation(Theme.spring) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 14)
                    Text("\(projects.count) hidden")
                    Spacer(minLength: 0)
                }
                .font(.small)
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 6)
                .frame(height: 26)
                .hoverFill()
            }
            .buttonStyle(PlainPressStyle())
            .help(expanded ? "Fold hidden projects away" : "Show hidden projects")
            if expanded {
                ForEach(projects) { project in
                    ProjectRow(project: project, hidden: true)
                }
            }
        }
    }
}

/// The account at the top of the sidebar. Clicking it opens everything about the session.
struct AccountMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            if model.isDemo {
                Text("Sample data on this Mac")
            } else if let login = model.viewer?.login {
                Text("Signed in as \(login)")
            }
            Button("Sync Now") { model.refresh() }
            Divider()
            Picker("Appearance", selection: Bindable(model).appearance) {
                ForEach(AppearanceSetting.allCases) { Text($0.title).tag($0) }
            }
            Button("Settings…") { model.settingsRequest += 1 }
            Divider()
            if model.isDemo {
                Button("Leave Sample Data") { model.leaveDemo() }
            } else {
                Button("Sign Out") { model.signOut() }
                if model.loginIsShared {
                    Button("Sign Out Everywhere…") { model.confirmSignOutEverywhere = true }
                }
            }
        } label: {
            HStack(spacing: 8) {
                if let viewer = model.viewer {
                    Avatar(login: viewer.login, url: viewer.avatarUrl, size: 20)
                    Text(viewer.login).font(.uiSemibold).lineLimit(1)
                } else {
                    Text("GitHub").font(.uiSemibold)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 6)
            .frame(height: 28)
            .hoverFill()
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Account")
    }
}

struct SidebarRow: View {
    var title: String
    var systemImage: String
    var active = false
    var trailing: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 14)
                Text(title)
                Spacer(minLength: 0)
                if let trailing {
                    Text(trailing).font(.tiny).foregroundStyle(Theme.textTertiary)
                }
            }
            .foregroundStyle(active ? Theme.text : Theme.textSecondary)
            .padding(.horizontal, 6)
            .frame(height: 28)
            .hoverFill(active: active)
        }
        .buttonStyle(PlainPressStyle())
    }
}

// MARK: - Sync indicator

struct SyncIndicator: View {
    @Environment(AppModel.self) private var model
    @State private var showQueue = false
    @State private var hovering = false

    var body: some View {
        Button {
            showQueue.toggle()
        } label: {
            SyncPill(highlighted: hovering || showQueue)
        }
        .buttonStyle(PlainPressStyle())
        .onHover { hovering = $0 }
        // The pill's padding would push the dot right of the sidebar's other icons; pull it back in line.
        .padding(.leading, -4)
        .popover(isPresented: $showQueue, arrowEdge: .top) {
            QueuePopover()
        }
        .help("Queued changes")
    }
}

/// Sync state as a small pill: a dot and a line of text, with a capsule behind it on hover.
struct SyncPill: View {
    @Environment(AppModel.self) private var model
    var highlighted: Bool

    var body: some View {
        HStack(spacing: 7) {
            indicator
            TimelineView(.periodic(from: .now, by: 20)) { _ in
                Text(text)
                    .font(.small)
                    .foregroundStyle(isOffline ? Theme.text : Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .frame(height: 26)
        .background(Capsule().fill(highlighted ? Theme.hover : .clear))
        .contentShape(Capsule())
        .animation(Theme.quick, value: highlighted)
    }

    private var isOffline: Bool { model.status.phase == .offline }

    @ViewBuilder
    private var indicator: some View {
        switch model.status.phase {
        case .syncing:
            ProgressView().controlSize(.mini).frame(width: 12, height: 12)
        case .offline:
            Circle().stroke(Theme.warning, lineWidth: 1.5).frame(width: 7, height: 7)
        case .failed, .unauthorized:
            Circle().fill(Theme.warning).frame(width: 7, height: 7)
        case .idle:
            Circle().fill(model.pendingCount > 0 ? Theme.accent : Theme.positive).frame(width: 7, height: 7)
        }
    }

    private var text: String {
        model.syncLine()
    }
}

struct QueuePopover: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let waiting = model.outbox.filter { $0.state != .sent }
        VStack(alignment: .leading, spacing: 0) {
            Text(waiting.isEmpty ? "Everything is saved to GitHub" : "Queued changes")
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
                    Text(entry.state == .conflict ? "\(summary.text) — needs your decision" : summary.text)
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
                Text("and \(waiting.count - 12) more")
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
                Button("Sync now") { model.refresh() }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 340)
        .font(.ui)
        .foregroundStyle(Theme.text)
        .background(Theme.popover)
    }

    private var footer: String {
        switch model.status.phase {
        case .offline: "Sends automatically when you are back online"
        case .failed(let message): message
        default: "Changes are saved locally first, then sent"
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
                if case .applyField(_, let label) = notice.action {
                    HStack(spacing: 8) {
                        Button("Keep mine") { model.status.dismiss(notice.id) }
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
            IconButton(systemName: "xmark", label: "Dismiss", size: 20) {
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
