#if os(macOS)
import AppKit
import SwiftUI

/// One project at a time in the sidebar, under its menu at the top: the project's views, its next milestones with the
/// roadmap, and its repositories.
struct SidebarProject: View {
    @Environment(AppModel.self) private var model
    var project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SidebarViews(project: project)
            if model.hasPlanning(projectId: project.id) {
                SidebarHeading(title: .milestones)
                ForEach(model.sidebarMilestones(projectId: project.id)) { group in
                    MilestoneRow(projectId: project.id, group: group)
                }
                RoadmapRow(projectId: project.id)
            }
            let repos = model.boardRepositories.filter { repo in model.repos(projectId: project.id).contains { $0.id == repo.id } }
            if !repos.isEmpty {
                // Like the teams in Linear: every issue of a repository, whether it is on a board or not.
                SidebarHeading(title: .repositories)
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
}

/// A quiet heading over a part of the sidebar.
struct SidebarHeading: View {
    var title: LocalizedStringResource

    var body: some View {
        Text(title)
            .font(.tinySemibold)
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 6)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }
}

// MARK: - The project's menu

/// The project the sidebar is about, at its top, as Linear shows its workspace: its colour with the state of syncing
/// as a dot, and its name. A click opens its menu with the other projects and the account; right-click it to hide
/// it, copy its link or open it on GitHub.
struct ProjectMenuButton: View {
    @Environment(AppModel.self) private var model
    var project: Project
    @State private var open = false

    var body: some View {
        let hidden = model.hiddenProjectIds.contains(project.id)
        TimelineView(.periodic(from: .now, by: 20)) { context in
            Button {
                open = true
            } label: {
                HStack(spacing: 8) {
                    StatusSwatch(title: project.title, size: 18)
                    Text(project.title)
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
            .accessibilityLabel(.project)
            .accessibilityValue("\(project.title), \(model.accountSummary(at: context.date))")
            .dropdown(isPresented: $open) { close in
                AccountDropdown(project: project, close: close)
            }
            .contextMenu {
                if hidden {
                    Button(.showInSidebar, systemImage: "eye") { model.setHidden(project, false) }
                } else {
                    Button(.hideFromSidebar, systemImage: "eye.slash") { model.setHidden(project, true) }
                }
                if project.viewerCanUpdate {
                    Divider()
                    Button(.newMilestoneEllipsis, systemImage: "plus") {
                        model.overlay = .milestoneEditor(projectId: project.id, title: nil, assigning: [])
                    }
                }
                Divider()
                Button(.copyLink, systemImage: "link") { model.copyLink(project.url, for: project.title) }
                Button(.openOnGitHub, systemImage: "arrow.up.right.square") {
                    if let url = URL(string: project.url) { NSWorkspace.shared.open(url) }
                }
            }
        }
    }
}

/// A project in the project's menu: its colour, its name, and a check on the one the sidebar is about.
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
                ProjectSwatch(title: project.title, size: 12)
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
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(active ? Theme.popoverSelected : .clear))
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

    @State private var renaming: String?
    @State private var deleting: ProjectView?
    @State private var newOpen = false
    /// The view a new one copies, from "Duplicate View…"; nil starts from the one open.
    @State private var duplicating: ProjectView?

    var body: some View {
        let views = model.views(projectId: project.id)
        let canEdit = model.canEditViews(projectId: project.id)
        VStack(alignment: .leading, spacing: 2) {
            SidebarHeading(title: .views)
            if views.isEmpty {
                // Until GitHub's views have been read: the board, as before there were views.
                let active = model.scope == .project(project.id)
                Button {
                    model.select(.project(project.id))
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.split.3x1")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(active ? Theme.textSecondary : Theme.textTertiary)
                            .frame(width: 14)
                        Text(.board)
                        Spacer(minLength: 0)
                    }
                    .font(active ? .uiMedium : .ui)
                    .foregroundStyle(active ? Theme.text : Theme.textSecondary)
                    .padding(.horizontal, 6)
                    .frame(height: 28)
                    .hoverFill(active: active)
                }
                .buttonStyle(PlainPressStyle())
            }
            ForEach(views) { view in
                SidebarViewRow(
                    view: view, renaming: $renaming,
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
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 14)
                        Text(.newViewTooltip)
                        Spacer(minLength: 0)
                    }
                    .font(.ui)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 6)
                    .frame(height: 28)
                    .hoverFill(active: newOpen)
                }
                .buttonStyle(PlainPressStyle())
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
    var view: ProjectView
    @Binding var renaming: String?
    var onDuplicate: () -> Void
    var onDelete: () -> Void

    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        let active = model.scope == .project(view.projectId) && model.currentView?.id == view.id
        let canEdit = model.canEditViews(projectId: view.projectId)
        if renaming == view.id {
            HStack(spacing: 8) {
                ViewLayoutIcon(view: view)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 14)
                TextField(.viewNamePlaceholder, text: $name)
                    .textFieldStyle(.plain)
                    .font(.ui)
                    .focused($focused)
                    .focusOnAppear()
                    .onSubmit(commit)
                    .onKeyPress(.escape) {
                        renaming = nil
                        return .handled
                    }
                    .onChange(of: focused) { _, now in if !now { commit() } }
            }
            .padding(.horizontal, 6)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Theme.accent, lineWidth: 1.5))
        } else {
            Button {
                model.show(view)
            } label: {
                HStack(spacing: 8) {
                    ViewLayoutIcon(view: view)
                        .foregroundStyle(active ? Theme.textSecondary : Theme.textTertiary)
                        .frame(width: 14)
                    Text(view.name).lineLimit(1)
                    Spacer(minLength: 4)
                    if model.filterChanged(view) {
                        Circle().fill(Theme.accent).frame(width: 6, height: 6)
                    }
                }
                .font(active ? .uiMedium : .ui)
                .foregroundStyle(active ? Theme.text : Theme.textSecondary)
                .padding(.horizontal, 6)
                .frame(height: 28)
                .hoverFill(active: active)
            }
            .buttonStyle(PlainPressStyle())
            .simultaneousGesture(TapGesture(count: 2).onEnded { if canEdit { startRenaming() } })
            .help(Text(view.filter.isEmpty ? view.name : "\(view.name) · \(view.filter)"))
            .accessibilityAddTraits(active ? .isSelected : [])
            .accessibilityValue(model.filterChanged(view) ? Text(.filterChangedSpoken) : Text(verbatim: ""))
            .contextMenu {
                if canEdit {
                    Button(.rename, systemImage: "pencil") { startRenaming() }
                    Button(.duplicateView, systemImage: "plus.square.on.square") { onDuplicate() }
                    Divider()
                }
                if let project = model.project(of: view), let url = view.url(projectURL: project.url) {
                    Button(.copyLink, systemImage: "link") { model.copyLink(url.absoluteString, for: view.name) }
                    Button(.openOnGitHub, systemImage: "arrow.up.right.square") { NSWorkspace.shared.open(url) }
                }
                if canEdit, model.views(projectId: view.projectId).count > 1 {
                    Divider()
                    Button(.deleteViewEllipsis, systemImage: "trash", role: .destructive) { onDelete() }
                }
            }
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
