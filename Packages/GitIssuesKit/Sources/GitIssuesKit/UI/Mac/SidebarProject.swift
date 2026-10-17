#if os(macOS)
import AppKit
import SwiftUI

/// One project at a time in the sidebar, under its menu at the top: the project's views, its next milestones with the
/// roadmap, and its repositories, each a section of the list.
struct SidebarProject: View {
    @Environment(AppModel.self) private var model
    var project: Project
    var current: SidebarSelection?

    var body: some View {
        SidebarViews(project: project, current: current)
        if model.hasPlanning(projectId: project.id) {
            Section(String(localized: .milestones)) {
                ForEach(model.sidebarMilestones(projectId: project.id)) { group in
                    MilestoneRow(projectId: project.id, group: group, current: current)
                }
                RoadmapRow(projectId: project.id, current: current)
            }
        }
        let repos = model.boardRepositories.filter { repo in model.repos(projectId: project.id).contains { $0.id == repo.id } }
        if !repos.isEmpty {
            // Like the teams in Linear: every issue of a repository, whether it is on a board or not.
            Section(String(localized: .repositories)) {
                ForEach(repos.filter { !model.hiddenRepositoryIds.contains($0.id) }) { repo in
                    RepositoryRow(repo: repo, hidden: false, current: current)
                }
                HiddenRepositories(repos: repos.filter { model.hiddenRepositoryIds.contains($0.id) }, current: current)
            }
        }
    }
}

// MARK: - The project's menu

/// The project the sidebar is about, at its top, as Linear shows its workspace: its icon on a tile with the state of
/// syncing as a dot, and its name. A click opens its menu with the other projects and the account; right-click it to
/// change its icon, hide it, copy its link or open it on GitHub.
struct ProjectMenuButton: View {
    @Environment(AppModel.self) private var model
    var project: Project
    @State private var open = false
    @State private var iconOpen = false

    var body: some View {
        let hidden = model.hiddenProjectIds.contains(project.id)
        TimelineView(.periodic(from: .now, by: 20)) { context in
            Button {
                open = true
            } label: {
                HStack(spacing: 9) {
                    StatusProjectIcon(projectId: project.id, size: 24, tile: true)
                    Text(project.title)
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
            .accessibilityLabel(.project)
            .accessibilityValue("\(project.title), \(model.accountSummary(at: context.date))")
            .dropdown(isPresented: $open) { close in
                AccountDropdown(project: project, close: close)
            }
            .dropdown(isPresented: $iconOpen) { close in
                ProjectIconPicker(projectId: project.id, close: close)
            }
            .onChange(of: model.projectIconRequest) { iconOpen = true }
            .glassSidebarMenu { [model, project, hidden, $iconOpen] in
                let menu = MenuBuilder()
                menu.item(.changeIconEllipsis, "paintpalette") { $iconOpen.wrappedValue = true }
                menu.divider()
                if hidden {
                    menu.item(.showInSidebar, "eye") { model.setHidden(project, false) }
                } else {
                    menu.item(.hideFromSidebar, "eye.slash") { model.setHidden(project, true) }
                }
                if project.viewerCanUpdate {
                    menu.divider()
                    menu.item(.newMilestoneEllipsis, "plus") {
                        model.overlay = .milestoneEditor(projectId: project.id, title: nil, assigning: [])
                    }
                }
                menu.divider()
                menu.item(.copyLink, "link") { model.copyLink(project.url, for: project.title) }
                menu.item(.openOnGitHub, "arrow.up.right.square") {
                    if let url = URL(string: project.url) { NSWorkspace.shared.open(url) }
                }
                return menu.build()
            }
        }
    }
}

/// A project in the project's menu: its icon, its name, and a check on the one the sidebar is about.
struct ProjectMenuRow: View {
    var project: Project
    var checked: Bool
    var dimmed = false
    var active: Bool
    var action: () -> Void
    var onHover: (Bool) -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ProjectIcon(projectId: project.id, size: 12)
                    .opacity(dimmed ? 0.5 : 1)
                    .frame(width: 16, height: 16)
                Text(project.title)
                    .lineLimit(1)
                    .foregroundStyle(dimmed ? Theme.textSecondary : Theme.text)
                Spacer(minLength: 12)
                if checked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textBody)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(active ? Theme.menuHighlight : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainPressStyle())
        .padding(.horizontal, 4)
        .help("\(project.ownerLogin) · \(project.title)")
        .onHover(perform: onHover)
    }
}

/// The projects hidden from the sidebar, as a submenu of the project's menu.
struct HiddenProjectsMenu: View {
    @Environment(AppModel.self) private var model
    var projects: [Project]
    var close: () -> Void
    @State private var active: Int?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
                ProjectMenuRow(
                    project: project, checked: false, dimmed: true, active: active == index, action: { pick(project) },
                    onHover: { inside in
                        if inside { active = index } else if active == index { active = nil }
                    }
                )
            }
        }
        .padding(.vertical, 4)
        .frame(width: 220)
        .font(.ui)
        .foregroundStyle(Theme.text)
        .background(MenuKeys(
            onMove: { active = menuStep(active, by: $0, count: projects.count) },
            onActivate: { if let active, projects.indices.contains(active) { pick(projects[active]) } },
            onBack: close
        ))
    }

    private func pick(_ project: Project) {
        close()
        model.select(.project(project.id))
    }
}

// MARK: - Views

/// The project's views, in GitHub's order, and a row for a new one. A click opens a view, a double-click renames it,
/// right-click for the rest.
private struct SidebarViews: View {
    @Environment(AppModel.self) private var model
    var project: Project
    var current: SidebarSelection?

    @State private var renaming: String?
    @State private var deleting: ProjectView?
    @State private var newOpen = false
    /// The view a new one copies, from "Duplicate View…"; nil starts from the one open.
    @State private var duplicating: ProjectView?

    var body: some View {
        let views = model.views(projectId: project.id)
        let canEdit = model.canEditViews(projectId: project.id)
        Section(String(localized: .views)) {
            if views.isEmpty {
                // Until GitHub's views have been read: the board, as before there were views.
                let row = SidebarSelection.board(project.id)
                Label { Text(.board) } icon: { Image(systemName: "rectangle.split.3x1") }
                    .tag(row)
                    .sidebarReselect(row, current: current)
            }
            ForEach(views) { view in
                SidebarViewRow(
                    view: view, current: current, renaming: $renaming,
                    onDuplicate: {
                        duplicating = view
                        newOpen = true
                    },
                    onDelete: { deleting = view }
                )
            }
            if canEdit {
                Button {
                    duplicating = nil
                    newOpen = true
                } label: {
                    Label { Text(.newViewTooltip) } icon: { Image(systemName: "plus") }
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .selectionDisabled()
                .dropdown(isPresented: $newOpen, placement: .trailing) { close in
                    NewViewForm(
                        projectId: project.id, source: duplicating ?? model.currentView(projectId: project.id),
                        duplicate: duplicating != nil, close: close
                    )
                }
            }
        }
        .onChange(of: model.newViewRequest) { if canEdit { newOpen = true } }
        .alert(
            Text(deleting.map { .deleteViewQuestion(view: $0.name) } ?? .deleteViewEllipsis),
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { view in
            Button(.deleteView, role: .destructive) { model.delete(view) }
            Button(.cancel, role: .cancel) {}
        } message: { _ in
            Text(.deleteViewMessage(project: project.title))
        }
    }
}

/// One view in the sidebar: its layout, its name, and a dot while its filter is changed here and not saved.
private struct SidebarViewRow: View {
    @Environment(AppModel.self) private var model
    /// Increased on the selected row, which is filled with the accent colour.
    @Environment(\.backgroundProminence) private var prominence
    var view: ProjectView
    var current: SidebarSelection?
    @Binding var renaming: String?
    var onDuplicate: () -> Void
    var onDelete: () -> Void

    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        let row = SidebarSelection.view(projectId: view.projectId, viewId: view.id)
        let canEdit = model.canEditViews(projectId: view.projectId)
        Group {
            if renaming == view.id {
                Label {
                    TextField(.viewNamePlaceholder, text: $name)
                        .textFieldStyle(.plain)
                        .focused($focused)
                        .focusOnAppear()
                        .onSubmit(commit)
                        .onKeyPress(.escape) {
                            renaming = nil
                            return .handled
                        }
                        .onChange(of: focused) { _, now in if !now { commit() } }
                } icon: {
                    icon
                }
            } else {
                Label {
                    HStack(spacing: 6) {
                        Text(view.name).lineLimit(1)
                        Spacer(minLength: 4)
                        if model.filterChanged(view) {
                            Circle().fill(prominence == .increased ? Color.white : Theme.accent).frame(width: 6, height: 6)
                        }
                    }
                } icon: {
                    icon
                }
                .simultaneousGesture(TapGesture(count: 2).onEnded { if canEdit { startRenaming() } })
                .help(Text(view.filter.isEmpty ? view.name : "\(view.name) · \(view.filter)"))
                .accessibilityValue(model.filterChanged(view) ? Text(.filterChangedSpoken) : Text(verbatim: ""))
                .glassSidebarMenu { [model, view, canEdit, onDuplicate, onDelete, $name, $renaming] in
                    let menu = MenuBuilder()
                    if canEdit {
                        menu.item(.rename, "pencil") {
                            $name.wrappedValue = view.name
                            $renaming.wrappedValue = view.id
                        }
                        menu.item(.duplicateView, "plus.square.on.square") { onDuplicate() }
                        menu.divider()
                    }
                    if let project = model.project(of: view), let url = view.url(projectURL: project.url) {
                        menu.item(.copyLink, "link") { model.copyLink(url.absoluteString, for: view.name) }
                        menu.item(.openOnGitHub, "arrow.up.right.square") { NSWorkspace.shared.open(url) }
                    }
                    if canEdit, model.views(projectId: view.projectId).count > 1 {
                        menu.divider()
                        menu.item(.deleteViewEllipsis, "trash", destructive: true) { onDelete() }
                    }
                    return menu.build()
                }
                .sidebarReselect(row, current: current)
            }
        }
        .tag(row)
    }

    @ViewBuilder
    private var icon: some View {
        if view.layout == .roadmap, model.display(of: view).layout == nil {
            RoadmapIcon(size: 14)
        } else {
            Image(systemName: model.layout(of: view) == .board ? "rectangle.split.3x1" : "list.bullet")
        }
    }

    private func startRenaming() {
        name = view.name
        renaming = view.id
    }

    private func commit() {
        guard renaming == view.id else { return }
        renaming = nil
        model.rename(view, to: name)
    }
}
#endif
