#if os(iOS)
import SwiftUI

/// The iPhone's page of a project, as Mail's list of mailboxes is under its Inbox: All Issues and the project's views,
/// its next milestones and its roadmap, each with how many of its issues are open. A project opens on its open view
/// with this page under it, so Back from any of them leads here, and Back again to Home.
struct ProjectPage: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation
    @Environment(\.openRoute) private var openRoute
    var projectId: String
    /// New View was chosen here: the view it makes opens once it's there.
    @State private var awaitingNewView = false

    var body: some View {
        let project = model.projects.first { $0.id == projectId }
        Group {
            if let project {
                list(project)
            } else {
                MobileEmptyState(title: String(localized: .projectGoneTitle), message: String(localized: .projectGoneMessage), systemImage: "questionmark.square.dashed")
            }
        }
        .background(Theme.window)
        .navigationTitle(project?.title ?? String(localized: .project))
        .navigationSubtitle(project?.ownerLogin ?? "")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let project { ProjectOptionsMenu(project: project, showsView: false) }
            }
        }
        .modifier(PhoneSearchBar(context: NewIssueContext(projectId: projectId)))
        .onAppear {
            model.setActiveProject(projectId)
            navigation.rememberProject(projectId)
        }
        .onChange(of: model.views(projectId: projectId).map(\.id)) { old, new in
            // The view New View made is the open one now.
            guard awaitingNewView, new.contains(where: { !old.contains($0) }) else { return }
            awaitingNewView = false
            openRoute(.project(projectId))
        }
        .onChange(of: navigation.sheet == nil) { _, closed in
            if closed { awaitingNewView = false }
        }
    }

    private func list(_ project: Project) -> some View {
        let views = model.views(projectId: projectId)
        return List {
            Section(String(localized: .views)) {
                PageRow(entry: .allIssues(projectId), note: noBoardNote) { openRoute(.allIssues(projectId)) }
                ForEach(views) { view in
                    PageRow(entry: .view(view)) {
                        model.show(view)
                        openRoute(.project(projectId))
                    }
                }
                if views.isEmpty {
                    // Until GitHub's views are read, the project's own board or list.
                    Button {
                        openRoute(.project(projectId))
                    } label: {
                        PageRowLabel(
                            icon: Image(systemName: model.viewMode == .board ? "rectangle.split.3x1" : "list.bullet"),
                            title: String(localized: model.viewMode == .board ? .board : .list), count: nil
                        )
                    }
                    .accessibilityIdentifier("page-project")
                }
                if model.canEditViews(projectId: projectId) {
                    Button {
                        awaitingNewView = true
                        navigation.sheet = .newView(projectId: projectId, sourceViewId: model.currentView(projectId: projectId)?.id, duplicate: false)
                    } label: {
                        Label(.newViewEllipsis, systemImage: "plus")
                            .foregroundStyle(Theme.accent)
                    }
                    .accessibilityIdentifier("page-new-view")
                }
            }
            if model.hasPlanning(projectId: projectId) {
                Section(String(localized: .milestones)) {
                    ForEach(model.sidebarMilestones(projectId: projectId)) { group in
                        PageRow(entry: .milestone(projectId: projectId, title: group.title), note: dueNote(group)) {
                            openRoute(.milestone(projectId: projectId, title: group.title))
                        }
                    }
                    PageRow(entry: .roadmap(projectId)) { openRoute(.roadmap(projectId)) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable { await model.refreshAndWait() }
    }

    /// How many of the project's issues are on no board, under All Issues.
    private var noBoardNote: String? {
        let count = model.countOnNoBoard(projectId: projectId)
        return count > 0 ? String(localized: .noBoardCount(count: count)) : nil
    }

    /// When a milestone is due, under its name.
    private func dueNote(_ group: MilestoneGroup) -> String? {
        group.due.map { String(localized: .dueOn(date: $0.mediumLabel())) }
    }
}

/// An entry of a project's page: a tap opens it; a long press or a swipe to the right pins it to Home, and a view's
/// long press has the view's own menu too.
private struct PageRow: View {
    @Environment(AppModel.self) private var model
    var entry: ProjectEntry
    var note: String?
    var open: () -> Void

    var body: some View {
        let pinned = HomePins.shared.contains(entry)
        Button(action: open) {
            PageRowLabel(icon: nil, entry: entry, title: model.title(of: entry), note: note, count: model.openCount(of: entry))
        }
        .accessibilityIdentifier("page-\(model.title(of: entry))")
        .accessibilityValue(spokenState(pinned: pinned))
        .contextMenu {
            PinMenuItem(entry: entry)
            if case .view(let view) = entry {
                Divider()
                ViewMenuItems(view: view)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                withAnimation(Theme.spring) { HomePins.shared.toggle(entry) }
            } label: {
                Label(pinned ? .unpin : .pin, systemImage: pinned ? "pin.slash.fill" : "pin.fill")
            }
            .tint(.yellow)
        }
    }
}

extension PageRow {
    /// What VoiceOver says after the name: a filter changed and not saved, pinned.
    fileprivate func spokenState(pinned: Bool) -> Text {
        var parts: [String] = []
        if case .view(let view) = entry, model.filterChanged(view) { parts.append(String(localized: .filterChangedSpoken)) }
        if pinned { parts.append(String(localized: .pinnedSpoken)) }
        return Text(verbatim: parts.joined(separator: ", "))
    }
}

/// A row of a project's page: the entry's icon, its name with a line under it, how many of its issues are open, and
/// the arrow of a row that opens a screen.
private struct PageRowLabel: View {
    @Environment(AppModel.self) private var model
    var icon: Image?
    var entry: ProjectEntry?
    var title: String
    var note: String?
    var count: Int?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let entry {
                    EntryIcon(entry: entry)
                } else if let icon {
                    icon.font(.system(size: 15, weight: .medium))
                }
            }
            .foregroundStyle(Theme.textSecondary)
            .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    // A view whose filter was changed here and not saved, as its capsule showed.
                    if case .view(let view)? = entry, model.filterChanged(view) {
                        Circle().fill(Theme.accent).frame(width: 6, height: 6)
                    }
                    if let entry, HomePins.shared.contains(entry) {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                            .accessibilityHidden(true)
                    }
                }
                if let note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let count, count > 0 {
                Text(count, format: .number)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }
}

/// An entry's icon: All Issues' stack, a view's board, list or roadmap, a milestone's diamond as far as it is, the
/// roadmap's bars.
struct EntryIcon: View {
    @Environment(AppModel.self) private var model
    var entry: ProjectEntry
    var size: CGFloat = 17
    /// One colour instead of the icon's own, such as white on a pinned tile.
    var tint: Color?

    var body: some View {
        Group {
            switch entry {
            case .allIssues:
                Image(systemName: "rectangle.stack").font(.system(size: size * 0.88, weight: .medium))
            case .view(let view):
                if view.layout == .roadmap, model.display(of: view).layout == nil {
                    RoadmapIcon(size: size)
                } else {
                    Image(systemName: model.layout(of: view) == .board ? "rectangle.split.3x1" : "list.bullet")
                        .font(.system(size: size * 0.82, weight: .medium))
                }
            case .milestone(let projectId, let title):
                let mark = model.milestoneGroup(projectId: projectId, title: title).map { model.mark(of: $0, projectId: projectId) }
                MilestoneIcon(mark: mark ?? .none, size: size, tint: tint)
            case .roadmap:
                RoadmapIcon(size: size)
            }
        }
        .foregroundStyle(tint ?? Theme.textSecondary)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Pin or Unpin, for menus: what is pinned shows on Home as a tile.
struct PinMenuItem: View {
    var entry: ProjectEntry

    var body: some View {
        let pinned = HomePins.shared.contains(entry)
        Button {
            withAnimation(Theme.spring) { HomePins.shared.toggle(entry) }
        } label: {
            Label(pinned ? .unpin : .pin, systemImage: pinned ? "pin.slash" : "pin")
        }
    }
}

// MARK: - What can be pinned

/// Something of a project the iPhone's page lists and Home can pin: All Issues, a view, a milestone or the roadmap.
enum ProjectEntry: Identifiable, Hashable {
    case allIssues(String)
    case view(ProjectView)
    case milestone(projectId: String, title: String)
    case roadmap(String)

    var id: String { key }

    /// How the entry is kept among the pins.
    var key: String {
        switch self {
        case .allIssues(let id): "allIssues:\(id)"
        case .view(let view): "view:\(view.id)"
        case .milestone(let projectId, let title): "milestone:\(projectId)\u{1F}\(title)"
        case .roadmap(let id): "roadmap:\(id)"
        }
    }

    var projectId: String {
        switch self {
        case .allIssues(let id), .roadmap(let id): id
        case .view(let view): view.projectId
        case .milestone(let projectId, _): projectId
        }
    }
}

extension AppModel {
    /// The entry a pin's key names, while it is still there: a view not deleted, a milestone not gone, a project
    /// still open.
    func entry(pinned key: String) -> ProjectEntry? {
        let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let entry: ProjectEntry? = switch parts[0] {
        case "allIssues": .allIssues(parts[1])
        case "roadmap": hasPlanning(projectId: parts[1]) ? .roadmap(parts[1]) : nil
        case "view": view(id: parts[1]).map { .view($0) }
        case "milestone": milestone(pinned: parts[1])
        default: nil
        }
        guard let entry, openProjects.contains(where: { $0.id == entry.projectId }) else { return nil }
        return entry
    }

    private func milestone(pinned value: String) -> ProjectEntry? {
        let bits = value.split(separator: "\u{1F}", maxSplits: 1).map(String.init)
        guard bits.count == 2, milestoneGroup(projectId: bits[0], title: bits[1]) != nil else { return nil }
        return .milestone(projectId: bits[0], title: bits[1])
    }

    func title(of entry: ProjectEntry) -> String {
        switch entry {
        case .allIssues: String(localized: .allIssues)
        case .view(let view): view.name
        case .milestone(_, let title): title
        case .roadmap: String(localized: .roadmap)
        }
    }

    /// How many issues an entry shows that aren't done; the roadmap, which shows epics, has no count.
    func openCount(of entry: ProjectEntry) -> Int? {
        switch entry {
        case .allIssues(let id):
            return items(in: .allIssues(id)).filter { !isDone($0) }.count
        case .view(let view):
            return items(of: view).filter { !isDone($0) }.count
        case .milestone(let projectId, let title):
            let progress = progress(projectId: projectId, milestone: title)
            return progress.total - progress.done
        case .roadmap:
            return nil
        }
    }
}

/// What is pinned to the iPhone's Home, in the order it was pinned. Kept on this device, as hidden projects are.
@MainActor
@Observable
final class HomePins {
    static let shared = HomePins()
    private static let key = "mobile.pins"

    private(set) var keys: [String] = UserDefaults.standard.stringArray(forKey: HomePins.key) ?? [] {
        didSet { UserDefaults.standard.set(keys, forKey: Self.key) }
    }

    func contains(_ entry: ProjectEntry) -> Bool {
        keys.contains(entry.key)
    }

    func toggle(_ entry: ProjectEntry) {
        if let index = keys.firstIndex(of: entry.key) {
            keys.remove(at: index)
        } else {
            keys.append(entry.key)
        }
    }

    /// A pinned milestone follows it as its screens do: renamed, or completed with its open work moved on to another
    /// milestone, the pin goes along; completed with nowhere to go, it leaves Home.
    func follow(_ move: MilestoneMove) {
        let old = ProjectEntry.milestone(projectId: move.projectId, title: move.from).key
        guard let index = keys.firstIndex(of: old) else { return }
        let new = move.to.map { ProjectEntry.milestone(projectId: move.projectId, title: $0).key }
        if let new, !keys.contains(new) {
            keys[index] = new
        } else {
            keys.remove(at: index)
        }
    }
}
#endif
