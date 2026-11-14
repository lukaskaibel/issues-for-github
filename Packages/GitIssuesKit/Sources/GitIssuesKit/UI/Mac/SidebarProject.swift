#if os(macOS)
import AppKit
import SwiftUI

/// One project at a time in the sidebar, under the Inbox and My Issues: its name with its menu, All Issues and its
/// views, then its next milestones with the roadmap, each a section of the list.
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
    }
}

// MARK: - The project's menu

/// The project the sidebar is about, at the head of its part, under a line that sets it apart from the Inbox and My
/// Issues: its icon on a tile, its name, and the repositories its issues come from. A click opens its menu with the
/// other projects to switch to and what can be done with this one; right-click gives the same actions.
struct ProjectMenuButton: View {
    @Environment(AppModel.self) private var model
    var project: Project
    @State private var open = false
    @State private var iconOpen = false
    @State private var hovering = false

    var body: some View {
        let hidden = model.hiddenProjectIds.contains(project.id)
        let repositories = model.repositoryLine(of: project)
        VStack(alignment: .leading, spacing: 6) {
            Rectangle()
                .fill(Theme.popoverBorder)
                .frame(height: 1)
                .padding(.horizontal, 2)
            Button {
                open = true
            } label: {
                HStack(spacing: 9) {
                    ProjectTile(projectId: project.id, size: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(project.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Text(repositories)
                            .font(.tiny)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .lineLimit(1)
                    .truncationMode(.tail)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.trailing, 2)
                }
                .padding(.horizontal, 4)
                .frame(height: 42)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(open || hovering ? Theme.field : .clear))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help(repositories)
            .accessibilityLabel(.project)
            .accessibilityValue("\(project.title), \(repositories)")
            .dropdown(isPresented: $open) { close in
                ProjectDropdown(project: project, close: close, changeIcon: { iconOpen = true })
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
        .padding(.top, 4)
    }
}

/// The menu of the project at the head of its part of the sidebar, as Linear's team menu: the projects to switch to,
/// each with its repositories, then its icon, a new milestone, its link, and hiding it. It opens as a dropdown like
/// the pickers; the arrow keys move, Return picks, → opens a submenu.
struct ProjectDropdown: View {
    @Environment(AppModel.self) private var model
    var project: Project
    var close: () -> Void
    /// Opens the icon picker in the menu's place.
    var changeIcon: () -> Void

    @State private var cursor = MenuCursor<Entry>()
    @State private var hiddenOpen = false

    enum Entry: Hashable {
        case project(String), hidden, more, icon, milestone, copyLink, openOnGitHub, hide
    }

    /// Up to this many projects are listed; with more, the command palette finds them by name.
    private static let listed = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuHeading(Text(.projects), inset: 12, top: 10, bottom: 4)
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
            row(.icon)
            if project.viewerCanUpdate { row(.milestone) }
            MenuDivider()
            row(.copyLink)
            row(.openOnGitHub)
            MenuDivider()
            row(.hide)
        }
        .padding(.bottom, 4)
        .frame(width: 264)
        .font(.ui)
        .foregroundStyle(Theme.text)
        .background(MenuKeys(
            onMove: { cursor.step($0, through: entries) },
            onActivate: { if let active = cursor.key { perform(active) } },
            onOpen: { if cursor.key == .hidden { perform(.hidden) } }
        ))
    }

    private var hidden: Bool {
        model.hiddenProjectIds.contains(project.id)
    }

    private var shownProjects: [Project] {
        model.openProjects.filter { !model.hiddenProjectIds.contains($0.id) }
    }

    /// The projects in the menu: the first few, and the one the sidebar is about wherever it comes.
    private var listedProjects: [Project] {
        var list = Array(shownProjects.prefix(Self.listed))
        if !list.contains(where: { $0.id == project.id }) {
            if list.count == Self.listed { list.removeLast() }
            list.append(project)
        }
        return list
    }

    private var hiddenProjects: [Project] {
        model.openProjects.filter { model.hiddenProjectIds.contains($0.id) && $0.id != project.id }
    }

    private var entries: [Entry] {
        var list: [Entry] = listedProjects.map { .project($0.id) }
        if !hiddenProjects.isEmpty { list.append(.hidden) }
        if shownProjects.count > Self.listed { list.append(.more) }
        list.append(.icon)
        if project.viewerCanUpdate { list.append(.milestone) }
        list += [.copyLink, .openOnGitHub, .hide]
        return list
    }

    @ViewBuilder
    private func row(_ entry: Entry) -> some View {
        switch entry {
        case .project(let id):
            if let other = model.openProjects.first(where: { $0.id == id }) {
                ProjectMenuRow(
                    project: other, detail: model.repositoryLine(of: other), checked: other.id == project.id,
                    cursor: cursor, key: entry, action: { perform(entry) }
                )
            }
        case .hidden:
            MenuRow(title: String(localized: .hiddenProjectsCount(count: hiddenProjects.count)), systemImage: "eye.slash", submenu: true, cursor: cursor, key: entry, open: hiddenOpen, action: { perform(entry) })
        case .more:
            MenuRow(title: String(localized: .switchProjectEllipsis), systemImage: "square.stack", cursor: cursor, key: entry, action: { perform(entry) })
        case .icon:
            MenuRow(title: String(localized: .changeIconEllipsis), systemImage: "paintpalette", cursor: cursor, key: entry, action: { perform(entry) })
        case .milestone:
            MenuRow(title: String(localized: .newMilestoneEllipsis), systemImage: "plus", cursor: cursor, key: entry, action: { perform(entry) })
        case .copyLink:
            MenuRow(title: String(localized: .copyLink), systemImage: "link", cursor: cursor, key: entry, action: { perform(entry) })
        case .openOnGitHub:
            MenuRow(title: String(localized: .openOnGitHub), systemImage: "arrow.up.right.square", cursor: cursor, key: entry, action: { perform(entry) })
        case .hide:
            MenuRow(
                title: String(localized: hidden ? .showInSidebar : .hideFromSidebar), systemImage: hidden ? "eye" : "eye.slash",
                cursor: cursor, key: entry, action: { perform(entry) }
            )
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
        case .icon:
            close()
            changeIcon()
        case .milestone:
            close()
            model.overlay = .milestoneEditor(projectId: project.id, title: nil, assigning: [])
        case .copyLink:
            close()
            model.copyLink(project.url, for: project.title)
        case .openOnGitHub:
            close()
            if let url = URL(string: project.url) { NSWorkspace.shared.open(url) }
        case .hide:
            close()
            model.setHidden(project, !hidden)
        }
    }
}

/// A project in the project's menu: its icon, its name with its repositories under it, and a check on the one the
/// sidebar is about.
struct ProjectMenuRow<Key: Hashable & Sendable>: View {
    var project: Project
    /// A second line under the name, such as its repositories.
    var detail: String?
    var checked: Bool
    var dimmed = false
    var cursor: MenuCursor<Key>
    var key: Key
    var action: () -> Void

    var body: some View {
        let active = cursor.isLit(key)
        Button(action: action) {
            HStack(spacing: 10) {
                ProjectIcon(projectId: project.id, size: 12)
                    .opacity(dimmed ? 0.5 : 1)
                    .frame(width: 16, height: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(project.title)
                        .foregroundStyle(dimmed ? Theme.textSecondary : Theme.text)
                    if let detail {
                        Text(detail)
                            .font(.tiny)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 12)
                if checked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textBody)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: detail == nil ? 30 : 40)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(active ? Theme.menuHighlight : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainPressStyle())
        .padding(.horizontal, 4)
        .help("\(project.ownerLogin) · \(project.title)")
        .onHover { cursor.hover(key, $0) }
    }
}

/// The projects hidden from the sidebar, as a submenu of the project's menu.
struct HiddenProjectsMenu: View {
    @Environment(AppModel.self) private var model
    var projects: [Project]
    var close: () -> Void
    @State private var cursor = MenuCursor<String>()

    var body: some View {
        VStack(spacing: 0) {
            ForEach(projects) { project in
                ProjectMenuRow(project: project, checked: false, dimmed: true, cursor: cursor, key: project.id, action: { pick(project) })
            }
        }
        .padding(.vertical, 4)
        .frame(width: 220)
        .font(.ui)
        .foregroundStyle(Theme.text)
        .background(MenuKeys(
            onMove: { cursor.step($0, through: projects.map(\.id)) },
            onActivate: { if let id = cursor.key, let project = projects.first(where: { $0.id == id }) { pick(project) } },
            onBack: close
        ))
    }

    private func pick(_ project: Project) {
        close()
        model.select(.project(project.id))
    }
}

// MARK: - Views

/// The project's name with its menu, then All Issues, as Linear's team starts with its issues, then the project's
/// views, in GitHub's order, and a row for a new one. A click opens a view, a double-click renames it, right-click for
/// the rest.
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
        Section {
            ProjectMenuButton(project: project)
                .selectionDisabled()
            AllIssuesRow(projectId: project.id, current: current)
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
        if let symbol = model.layoutSymbol(of: view) {
            Image(systemName: symbol)
        } else {
            RoadmapIcon(size: 14)
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
