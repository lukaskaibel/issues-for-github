#if os(iOS)
import SwiftUI

/// The iPhone's first screen, as Reminders opens on its lists: the Inbox and My Issues as two tiles with their counts,
/// and under them every project, which opens on its board or list. The app comes back to the screen it was left on,
/// so Home is where a project's back button leads more than where the day starts.
struct HomeScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation
    @Environment(\.openRoute) private var openRoute

    var body: some View {
        let open = model.openProjects
        let closed = model.projects.filter(\.closed)
        List {
            Section {
                HStack(spacing: 10) {
                    HomeTile(title: .inbox, systemImage: "tray.fill", tint: Theme.accentFill, count: model.inboxUnreadCount) {
                        openRoute(.inbox)
                    }
                    .accessibilityIdentifier("home-inbox")
                    HomeTile(title: .myIssues, systemImage: "scope", tint: Theme.urgent, count: openAssignedCount) {
                        openRoute(.myIssues)
                    }
                    .accessibilityIdentifier("home-my-issues")
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
                    NavigationLink(value: Route.project(project.id)) {
                        ProjectRow(project: project)
                    }
                    .contextMenu {
                        Button {
                            navigation.sheet = .projectIcon(project.id)
                        } label: {
                            Label(.changeIconEllipsis, systemImage: "paintpalette")
                        }
                    }
                }
            } header: {
                Text(.projects)
            }
            if !closed.isEmpty {
                Section(.closedProjects) {
                    ForEach(closed) { project in
                        NavigationLink(value: Route.project(project.id)) {
                            ProjectRow(project: project)
                        }
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
                    Text(count, format: .number)
                        .font(.title.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text)
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
        .accessibilityValue(Text(count, format: .number))
        .accessibilityAddTraits(.isButton)
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
