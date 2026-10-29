#if os(iOS)
import SwiftUI

/// The iPhone's first screen, as Reminders opens on its lists: the Inbox and My Issues as two tiles with their counts,
/// then what was pinned from the projects' pages, and under them every project, which opens on its open view with the
/// project's page under it. The app comes back to the screen it was left on, so Home is where Back leads more than
/// where the day starts. Projects you hid wait folded at the end of the list, as on the Mac.
struct HomeScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation
    @Environment(\.openRoute) private var openRoute
    @State private var onScreen = false
    @State private var hiddenOpen = false

    var body: some View {
        let open = model.shownProjects
        let hidden = model.hiddenProjects
        let closed = model.projects.filter(\.closed)
        List {
            Section {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    HomeTile(title: .inbox, systemImage: "tray.fill", tint: Theme.accentFill, count: model.inboxUnreadCount) {
                        openRoute(.inbox)
                    }
                    .accessibilityIdentifier("home-inbox")
                    HomeTile(title: .myIssues, systemImage: "scope", tint: Theme.urgent, count: openAssignedCount, loading: model.isLoadingMyIssues) {
                        openRoute(.myIssues)
                    }
                    .accessibilityIdentifier("home-my-issues")
                    ForEach(HomePins.shared.keys.compactMap { model.entry(pinned: $0) }) { entry in
                        PinTile(entry: entry, count: entry.counted ? HomePins.shared.openCounts[entry.key] ?? 0 : nil)
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            Section {
                if model.projects.isEmpty {
                    MobileEmptyState(
                        title: model.status.phase == .offline ? String(localized: .youreOffline) : String(localized: .lookingForProjects),
                        message: String(localized: .noProjectsMessage),
                        systemImage: "square.stack",
                        showsProgress: model.status.phase != .offline
                    )
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
                ForEach(open) { project in
                    projectLink(project, hidden: false)
                }
                if !hidden.isEmpty {
                    DisclosureGroup(isExpanded: $hiddenOpen) {
                        ForEach(hidden) { project in
                            projectLink(project, hidden: true)
                        }
                    } label: {
                        Label {
                            Text(.hiddenProjectsCount(count: hidden.count)).foregroundStyle(Theme.textSecondary)
                        } icon: {
                            Image(systemName: "eye.slash").foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .accessibilityIdentifier("home-hidden-projects")
                }
            } header: {
                Text(.projects)
            }
            if !closed.isEmpty {
                Section(.closedProjects) {
                    ForEach(closed) { project in
                        ProjectLink(project: project)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.window)
        .refreshable { await model.refreshAndWait() }
        .navigationTitle(.appName)
        .navigationSubtitle(SyncSubtitle.text(model))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { AccountButton() }
        }
        .modifier(PhoneSearchBar(context: NewIssueContext()))
        .onAppear {
            onScreen = true
            recountPins()
        }
        .onDisappear { onScreen = false }
        .onChange(of: model.dataVersion) { _, _ in
            if onScreen { recountPins() }
        }
        .onChange(of: HomePins.shared.keys) { _, _ in recountPins() }
    }

    /// Counts the pins' open issues while Home is on screen only, as a project's page does: Home stays under every
    /// screen.
    private func recountPins() {
        var fresh: [String: Int] = [:]
        for entry in HomePins.shared.keys.compactMap({ model.entry(pinned: $0) }) {
            fresh[entry.key] = model.openCount(of: entry)
        }
        if fresh != HomePins.shared.openCounts { HomePins.shared.openCounts = fresh }
    }

    /// An open project's row: a tap opens it; touch and hold, or swipe left, to hide it or show it again.
    private func projectLink(_ project: Project, hidden: Bool) -> some View {
        ProjectLink(project: project, dimmed: hidden)
        .contextMenu {
            Button {
                navigation.sheet = .projectIcon(project.id)
            } label: {
                Label(.changeIconEllipsis, systemImage: "paintpalette")
            }
            Button {
                model.setHidden(project, !hidden)
            } label: {
                Label(hidden ? .showProject : .hideProject, systemImage: hidden ? "eye" : "eye.slash")
            }
        }
        .swipeActions(edge: .trailing) {
            Button {
                model.setHidden(project, !hidden)
            } label: {
                Label(hidden ? .showProject : .hideProject, systemImage: hidden ? "eye" : "eye.slash")
            }
            .tint(hidden ? Theme.accentFill : Color(white: 0.45))
        }
    }

    /// What My Issues has left to do: its issues through its filter, without the done ones.
    private var openAssignedCount: Int {
        model.mineItems().filter { !(model.statusOption(of: $0)?.statusCategory.isClosed ?? $0.isClosed) }.count
    }
}

/// The Inbox or My Issues on Home, as Reminders shows Today and Scheduled: a symbol on a circle of its colour, the
/// count, and the name under them.
private struct HomeTile: View {
    var title: LocalizedStringResource
    var systemImage: String
    var tint: Color
    var count: Int
    /// Still fetching what the count is of: with nothing found so far, a spinner stands in for the 0.
    var loading = false
    var action: () -> Void
    @ScaledMetric(relativeTo: .body) private var circle: CGFloat = 32

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center) {
                    Image(systemName: systemImage)
                        .font(.system(size: circle * 0.47, weight: .semibold))
                        .foregroundStyle(Theme.onColor)
                        .frame(width: circle, height: circle)
                        .background(Circle().fill(tint))
                    Spacer(minLength: 8)
                    if loading, count == 0 {
                        ProgressView()
                    } else {
                        Text(count, format: .number)
                            .font(.title.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.text)
                    }
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PlainPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(loading && count == 0 ? Text(.loadingIssues) : Text(count, format: .number))
        .accessibilityAddTraits(.isButton)
    }
}

/// Something pinned from a project's page, as a tile like the Inbox's: its icon on a circle of the project's colour,
/// how many of its issues are open, its name and the project's. A tap opens it over the project's page; touch and
/// hold to unpin it.
private struct PinTile: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation
    var entry: ProjectEntry
    /// How many of its issues are open; none for the roadmap.
    var count: Int?
    @ScaledMetric(relativeTo: .body) private var circle: CGFloat = 32

    var body: some View {
        let project = model.projects.first { $0.id == entry.projectId }
        let title = model.title(of: entry)
        Button {
            open()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center) {
                    EntryIcon(entry: entry, size: circle * 0.5, tint: Theme.onColor)
                        .frame(width: circle, height: circle)
                        .background(Circle().fill(Theme.projectColor(model.projectLooks.look(entry.projectId).color)))
                    Spacer(minLength: 8)
                    if let count {
                        Text(count, format: .number)
                            .font(.title.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.text)
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    Text(project?.title ?? "")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PlainPressStyle())
        .contextMenu {
            PinMenuItem(entry: entry)
            Button {
                navigation.setPhonePath([.projectPage(entry.projectId)])
            } label: {
                Label(.goToProject, systemImage: "square.stack")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(title), \(project?.title ?? "")"))
        .accessibilityValue(count.map { Text($0, format: .number) } ?? Text(verbatim: ""))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("pin-\(title)")
    }

    /// Opens what was pinned with its project's page under it, as from the page.
    private func open() {
        switch entry {
        case .allIssues(let id): navigation.setPhonePath([.allIssues(id)])
        case .view(let view):
            model.show(view)
            navigation.setPhonePath([.project(view.projectId)])
        case .milestone(let projectId, let title): navigation.setPhonePath([.milestone(projectId: projectId, title: title)])
        case .roadmap(let id): navigation.setPhonePath([.roadmap(id)])
        }
    }
}

/// A project's row on Home, which opens its open view with the project's page under it. Both screens go onto the
/// stack at once: a link would push the view first and slip the page under it afterwards, which leaves the page's
/// search bar on the screen.
private struct ProjectLink: View {
    @Environment(MobileNavigation.self) private var navigation
    var project: Project
    /// A hidden project's row, paler than the others.
    var dimmed = false

    var body: some View {
        Button {
            navigation.setPhonePath([.projectPage(project.id), .project(project.id)])
        } label: {
            HStack(spacing: 8) {
                ProjectRow(project: project)
                    .opacity(dimmed ? 0.6 : 1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
    }
}

/// A project on Home: its icon, its name, and its owner with how many of its issues are open.
struct ProjectRow: View {
    @Environment(AppModel.self) private var model
    var project: Project

    var body: some View {
        let items = model.allItems.filter { $0.projectId == project.id && !$0.isEpic }
        let open = items.filter { !(model.statusOption(of: $0)?.statusCategory.isClosed ?? $0.isClosed) }.count
        HStack(spacing: 12) {
            ProjectIcon(projectId: project.id, size: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.title).font(.body.weight(.medium)).foregroundStyle(Theme.text)
                Text(project.lastSyncedAt == nil ? project.ownerLogin : String(localized: .ownerOpenIssueCount(owner: project.ownerLogin, count: open)))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
#endif
