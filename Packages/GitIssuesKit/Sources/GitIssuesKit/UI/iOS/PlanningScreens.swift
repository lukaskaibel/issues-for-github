#if os(iOS)
import SwiftUI
import UIKit

// MARK: - A milestone

/// One milestone of a board: its issues by epic, or on a wide iPad also in the board's columns, with when it is due
/// and how far it is on top.
struct MilestoneScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation
    @Environment(\.wideLayout) private var wide
    @Environment(\.windowWidth) private var windowWidth
    var projectId: String
    var title: String

    var body: some View {
        let group = model.milestoneGroup(projectId: projectId, title: title)
        Group {
            if group == nil {
                MobileEmptyState(
                    title: String(localized: .milestoneGoneTitle), message: String(localized: .milestoneGoneMessage(milestone: title)),
                    systemImage: "questionmark.diamond"
                )
            } else if model.isLoading(projectId: projectId) {
                ProjectLoading()
            } else if wide, model.viewMode == .board {
                VStack(spacing: 0) {
                    if let group { MilestoneSummaryCard(projectId: projectId, group: group).padding(.horizontal, 18).padding(.top, 8) }
                    MobileBoard(projectId: projectId, milestone: title)
                }
            } else {
                IssueList(scope: .milestone(projectId: projectId, title: title))
            }
        }
        .background(Theme.panel)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .modifier(EditorRole(active: wide))
        .toolbar {
            let roomy = windowWidth >= 950
            if wide, let project = model.projects.first(where: { $0.id == projectId }) {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 10) {
                        ProjectIcon(projectId: project.id, size: 14)
                        Text(project.title).font(.headline).foregroundStyle(Theme.textSecondary).lineLimit(1)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.textTertiary)
                        MilestoneIcon(mark: group.map { model.mark(of: $0, projectId: projectId) } ?? .none, size: 15)
                        Text(title).font(.headline).lineLimit(1)
                        if roomy {
                            Picker(.viewModePicker, selection: Bindable(model).viewMode) {
                                Image(systemName: "rectangle.split.3x1").accessibilityLabel(.board).help(Text(.board)).tag(ViewMode.board)
                                Image(systemName: "list.bullet").accessibilityLabel(.list).help(Text(.list)).tag(ViewMode.list)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 160)
                            .padding(.leading, 8)
                        }
                    }
                }
                .sharedBackgroundVisibility(.hidden)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if let group {
                    MilestoneOptionsMenu(projectId: projectId, group: group, showsViewMode: wide && !roomy)
                }
                NewIssueButton(context: NewIssueContext(projectId: projectId, milestoneTitle: title))
            }
        }
        .onAppear {
            model.setActiveProject(projectId)
            navigation.rememberProject(projectId)
        }
        .task(id: model.dataVersion) { await model.preloadAvatars(for: .milestone(projectId: projectId, title: title)) }
    }
}

/// On top of a milestone's list or board: what it is about, when it is due, how far it is, and completing it.
struct MilestoneSummaryCard: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation
    var projectId: String
    var group: MilestoneGroup

    var body: some View {
        let progress = model.progress(projectId: projectId, milestone: group.title)
        let today = CalendarDay.today()
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    navigation.sheet = .milestoneEditor(projectId: projectId, title: group.title, assigning: [])
                } label: {
                    HStack(spacing: 6) {
                        DueDateIcon(tone: group.isOpen && (group.due.map { $0 < today } ?? false) ? .overdue : nil, size: 13)
                        (group.due.map { Text($0.mediumLabel(today: today)) } ?? Text(.addDueDate))
                            .foregroundStyle(group.due == nil ? Theme.textTertiary : Theme.textBody)
                    }
                    .font(.subheadline)
                }
                .buttonStyle(PlainPressStyle())
                .accessibilityLabel(group.due.map { Text(.dueOn(date: $0.longLabel)) } ?? Text(.setMilestoneDueDate))
                Spacer(minLength: 8)
                if progress.total > 0 {
                    Text(.subIssuesProgress(done: progress.done, total: progress.total))
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                    ProgressView(value: Double(progress.done), total: Double(progress.total))
                        .progressViewStyle(ThinProgressStyle())
                        .frame(width: 56)
                        .accessibilityLabel(Text(.milestoneProgressTooltip(done: progress.done, total: progress.total)))
                }
            }
            let text = group.descr.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if group.isOpen, isReady(progress: progress, today: today) {
                Button(.completeMilestoneEllipsis) {
                    model.milestoneToComplete = MilestoneRef(projectId: projectId, title: group.title)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.groupHeader))
    }

    private func isReady(progress: Roadmap.Count, today: CalendarDay) -> Bool {
        if progress.total > 0, progress.done == progress.total { return true }
        return group.due.map { $0 <= today } ?? false
    }
}

/// The "…" of a milestone: Board or List where the bar has no room, change it, complete or reopen it, its link.
struct MilestoneOptionsMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation
    var projectId: String
    var group: MilestoneGroup
    var showsViewMode = false

    var body: some View {
        Menu {
            if showsViewMode {
                Picker(.viewModePicker, selection: Bindable(model).viewMode) {
                    Label(.board, systemImage: "rectangle.split.3x1").tag(ViewMode.board)
                    Label(.list, systemImage: "list.bullet").tag(ViewMode.list)
                }
                .pickerStyle(.inline)
                Divider()
            }
            Button {
                navigation.sheet = .milestoneEditor(projectId: projectId, title: group.title, assigning: [])
            } label: {
                Label(.editMilestoneEllipsis, systemImage: "pencil")
            }
            if group.isOpen {
                Button {
                    model.milestoneToComplete = MilestoneRef(projectId: projectId, title: group.title)
                } label: {
                    Label(.completeMilestoneEllipsis, systemImage: "checkmark.circle")
                }
            } else {
                Button {
                    model.reopenMilestone(group)
                } label: {
                    Label(.reopenMilestone, systemImage: "arrow.uturn.backward.circle")
                }
            }
            if let url = group.url {
                Divider()
                Button {
                    model.copyLink(url, for: group.title)
                } label: {
                    Label(.copyLink, systemImage: "link")
                }
                if let parsed = URL(string: url) {
                    Button {
                        Platform.open(parsed)
                    } label: {
                        Label(.openOnGitHub, systemImage: "arrow.up.right.square")
                    }
                }
            }
        } label: {
            Label(.milestoneOptions, systemImage: "ellipsis")
        }
    }
}

// MARK: - The roadmap

/// A board's roadmap: on a wide iPad its epics on a timeline over the milestones, or as a list; on the iPhone the list.
struct RoadmapScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation
    @Environment(\.openRoute) private var openRoute
    @Environment(\.wideLayout) private var wide
    var projectId: String

    var body: some View {
        let roadmap = model.roadmap(projectId: projectId)
        let canEdit = model.projects.first { $0.id == projectId }?.viewerCanUpdate == true
        Group {
            if model.isLoading(projectId: projectId) {
                ProjectLoading()
            } else if roadmap.rows.isEmpty, roadmap.later.isEmpty {
                MobileEmptyState(
                    title: String(localized: .roadmapEmptyTitle), message: String(localized: .roadmapEmptyMessage),
                    systemImage: "calendar.day.timeline.left"
                ) {
                    if canEdit {
                        Button(.newEpic) {
                            navigation.sheet = .newIssue(NewIssueContext(projectId: projectId, isEpic: true))
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else if wide, model.roadmapLayout == .timeline {
                RoadmapTimeline(projectId: projectId, nameWidth: 240) { openRoute(.issue($0.id)) }
            } else {
                IssueList(scope: .roadmap(projectId))
            }
        }
        .background(Theme.panel)
        .navigationTitle(Text(.roadmap))
        .navigationBarTitleDisplayMode(.inline)
        .modifier(EditorRole(active: wide))
        .toolbar {
            if wide, let project = model.projects.first(where: { $0.id == projectId }) {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 10) {
                        ProjectIcon(projectId: project.id, size: 14)
                        Text(project.title).font(.headline).foregroundStyle(Theme.textSecondary).lineLimit(1)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.textTertiary)
                        Text(.roadmap).font(.headline)
                        Picker(.roadmapLayoutPicker, selection: Bindable(model).roadmapLayout) {
                            Text(.timeline).tag(RoadmapLayout.timeline)
                            Text(.list).tag(RoadmapLayout.list)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                        .padding(.leading, 8)
                    }
                }
                .sharedBackgroundVisibility(.hidden)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if wide, model.roadmapLayout == .timeline {
                    Menu {
                        Picker(.zoomPicker, selection: Bindable(model).roadmapZoom) {
                            Text(.months).tag(RoadmapZoom.months)
                            Text(.quarters).tag(RoadmapZoom.quarters)
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Label(.zoomPicker, systemImage: "plus.magnifyingglass")
                    }
                }
                if canEdit {
                    Menu {
                        Button {
                            navigation.sheet = .newIssue(NewIssueContext(projectId: projectId, isEpic: true))
                        } label: {
                            Label(.newEpic, systemImage: "square.stack.3d.up")
                        }
                        Button {
                            navigation.sheet = .milestoneEditor(projectId: projectId, title: nil, assigning: [])
                        } label: {
                            Label(.newMilestoneEllipsis, systemImage: "diamond")
                        }
                    } label: {
                        Label(.newEpic, systemImage: "plus")
                    }
                    .accessibilityIdentifier("roadmap-add")
                }
            }
        }
        .onAppear {
            model.setActiveProject(projectId)
            navigation.rememberProject(projectId)
        }
    }
}

// MARK: - The milestone dialog

/// A new milestone, or one to change: its name, when it is due, and what it is about.
struct MilestoneEditorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var projectId: String?
    var title: String?
    var assigning: [String]

    @State private var name = ""
    @State private var due: CalendarDay?
    @State private var descr = ""
    @State private var editingDescription = false
    @State private var choosingDate = false
    @State private var prepared = false
    @FocusState private var nameFocused: Bool
    @State private var titleLink = TitleLink()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(.milestoneNamePlaceholder, text: $name)
                        .font(.title3.weight(.semibold))
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .accessibilityIdentifier("milestone-name")
                        .titleOf(titleLink) { nameFocused = true }
                    MarkdownEditor(
                        draft: $descr,
                        placeholder: .milestoneDescriptionPlaceholder,
                        editing: $editingDescription,
                        titleLink: titleLink,
                        accessibilityLabel: .milestoneDescriptionPlaceholder,
                        accessibilityIdentifier: "milestone-description"
                    )
                    .frame(minHeight: EditorStyle.lineHeight * 3, alignment: .top)
                    // A tap below the text puts the caret at its end.
                    .background { Color.clear.contentShape(.rect).onTapGesture { editingDescription = true } }
                }
                Section {
                    Button {
                        choosingDate = true
                    } label: {
                        HStack {
                            Label {
                                Text(.dueDate)
                            } icon: {
                                DueDateIcon(size: 15)
                            }
                            .foregroundStyle(Theme.text)
                            Spacer()
                            (due.map { Text($0.mediumLabel()) } ?? Text(.noDate))
                                .foregroundStyle(due == nil ? Theme.textTertiary : Theme.textSecondary)
                        }
                    }
                    .accessibilityIdentifier("milestone-due")
                } footer: {
                    if !assigning.isEmpty {
                        Text(.milestoneWillHoldIssues(count: assigning.count))
                    } else if let repo = repository, existing == nil {
                        Text(.milestoneMadeIn(repository: repo.nameWithOwner))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.panel)
            .navigationTitle(existing == nil ? LocalizedStringResource.newMilestone : .editMilestone)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(.cancel, systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? LocalizedStringResource.create : .saveButton, action: save)
                        .disabled(!canSave)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .sheet(isPresented: $choosingDate) {
                DueDateSheet(current: [due?.string], addsField: false) { due = $0 }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear(perform: prepare)
    }

    private var boardId: String? {
        projectId ?? model.openProjects.first?.id
    }

    private var existing: MilestoneGroup? {
        guard let title, let boardId else { return nil }
        return model.milestoneGroup(projectId: boardId, title: title)
    }

    private var repository: RepoRef? {
        boardId.flatMap { model.repositoryForNewMilestone(projectId: $0) }
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool {
        guard !trimmed.isEmpty, let boardId else { return false }
        if trimmed != existing?.title, model.milestoneGroup(projectId: boardId, title: trimmed)?.isOpen == true { return false }
        return existing != nil || repository != nil
    }

    private func prepare() {
        guard !prepared else { return }
        prepared = true
        if let existing {
            name = existing.title
            due = existing.due
            descr = existing.descr
        }
        nameFocused = existing == nil
    }

    private func save() {
        guard canSave, let boardId else { return }
        if let existing {
            model.editMilestone(existing, projectId: boardId, title: trimmed, due: due, descr: descr)
        } else if let group = model.createMilestone(projectId: boardId, title: trimmed, due: due, descr: descr) {
            let items = assigning.compactMap { model.item(id: $0) }
            if !items.isEmpty { model.setMilestone(of: items, to: group) }
        }
        dismiss()
    }
}

// MARK: - Images

/// Planning's glyphs as images, for the iPad sidebar, whose entries need one. Drawn for the appearance on screen.
@MainActor
enum PlanningImages {
    private static var cache: [String: UIImage] = [:]

    static func milestone(_ mark: MilestoneMark, _ scheme: ColorScheme) -> UIImage {
        image("milestone-\(mark)", scheme) { MilestoneIcon(mark: mark, size: 15) }
    }

    static func roadmap(_ scheme: ColorScheme) -> UIImage {
        image("roadmap", scheme) { RoadmapIcon(size: 17).foregroundStyle(Theme.textSecondary) }
    }

    private static func image<Content: View>(_ key: String, _ scheme: ColorScheme, @ViewBuilder _ content: () -> Content) -> UIImage {
        let fullKey = "\(key)-\(scheme == .dark ? "dark" : "light")"
        if let cached = cache[fullKey] { return cached }
        // As wide as the sidebar's symbol column, so names line up with the projects'.
        let renderer = ImageRenderer(content: content()
            .frame(width: 28, height: 28)
            .environment(\.colorScheme, scheme))
        renderer.scale = 3
        let image = renderer.uiImage?.withRenderingMode(.alwaysOriginal) ?? UIImage()
        cache[fullKey] = image
        return image
    }
}
#endif
