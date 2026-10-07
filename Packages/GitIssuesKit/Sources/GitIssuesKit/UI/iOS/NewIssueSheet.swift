#if os(iOS)
import SwiftUI

/// Writing a new issue: the keyboard is up with the cursor in the title, and status, priority, people and
/// labels sit as chips right above the keyboard, as in Linear.
struct NewIssueSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    var context: NewIssueContext

    @State private var draft = NewIssueDraft(projectId: nil)
    @State private var prepared = false
    @State private var picker: PickerKind?
    @State private var confirmDiscard = false
    @State private var created = 0
    @FocusState private var focus: Field?

    private enum Field {
        case title
        case body
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    whereChips
                    TextField("Issue title", text: $draft.title, axis: .vertical)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .focused($focus, equals: .title)
                        .submitLabel(.next)
                        .onChange(of: draft.title) { _, new in
                            // Return moves on to the description instead of breaking the title.
                            guard new.contains("\n") else { return }
                            draft.title = new.replacingOccurrences(of: "\n", with: "")
                            focus = .body
                        }
                        .onSubmit { focus = .body }
                        .accessibilityLabel("Title")
                        .accessibilityIdentifier("new-title")
                    TextField("Add a description…", text: $draft.body, axis: .vertical)
                        .font(.body)
                        .foregroundStyle(Theme.textBody)
                        .lineLimit(4...)
                        .focused($focus, equals: .body)
                        .accessibilityLabel("Description")
                        .accessibilityIdentifier("new-description")
                    if repos.isEmpty, draft.projectId != nil {
                        Label("This project has no repository yet. Issues are created in a repository linked to the project; link one on GitHub first.", systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(Theme.warning)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.panel)
            // ⌘↵ creates the issue from inside the text too, where Return alone moves on or breaks the line.
            .screenKey("Create Issue", "\r", modifiers: .command) { create() }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                propertyBar
            }
            .navigationTitle(draft.parent == nil ? "New Issue" : "New Sub-issue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        if hasContent { confirmDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: create)
                        .disabled(!canCreate)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .confirmationDialog("Discard this issue?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
            .sheet(item: $picker) { kind in
                DraftPickerSheet(kind: kind, draft: $draft)
            }
        }
        .interactiveDismissDisabled(hasContent)
        .sensoryFeedback(.success, trigger: created)
        .onAppear(perform: prepare)
    }

    // MARK: Where it goes

    private var whereChips: some View {
        HStack(spacing: 8) {
            if draft.parent == nil {
                Menu {
                    ForEach(projectChoices) { project in
                        Button {
                            selectProject(project.id)
                        } label: {
                            if project.id == draft.projectId {
                                Label(project.title, systemImage: "checkmark")
                            } else {
                                Text(project.title)
                            }
                        }
                    }
                    if context.repoId != nil {
                        // Started in a repository, the issue can also stay on no board, like in Linear.
                        Divider()
                        Button {
                            selectProject(nil)
                        } label: {
                            if draft.projectId == nil {
                                Label("No project", systemImage: "checkmark")
                            } else {
                                Text("No project")
                            }
                        }
                    }
                } label: {
                    contextChip {
                        if let project {
                            ProjectSwatch(title: project.title, size: 11)
                            Text(project.title)
                        } else if context.repoId != nil {
                            Text("No project")
                        } else {
                            Text("Choose a project")
                        }
                        Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                    }
                }
                .accessibilityLabel("Project: \(project?.title ?? "none")")
            } else if let parent = draft.parent {
                contextChip {
                    SubIssueGlyph().frame(width: 11, height: 11)
                    Text("Sub-issue of \(parent.displayNumber)")
                }
            }
            if context.repoId != nil || (draft.projectId == nil && draft.parent != nil), let repo = repos.first {
                contextChip {
                    RepositoryIcon(size: 10)
                    Text(repo.shortName)
                }
                .accessibilityLabel("Repository: \(repo.nameWithOwner)")
            } else if repos.count > 1, draft.parent == nil {
                Menu {
                    ForEach(repos) { repo in
                        Button {
                            selectRepo(repo.id)
                        } label: {
                            if repo.id == draft.repoId {
                                Label(repo.nameWithOwner, systemImage: "checkmark")
                            } else {
                                Text(repo.nameWithOwner)
                            }
                        }
                    }
                } label: {
                    contextChip {
                        Text(repos.first { $0.id == draft.repoId }?.shortName ?? "Repository")
                        Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                    }
                }
                .accessibilityLabel("Repository: \(repos.first { $0.id == draft.repoId }?.nameWithOwner ?? "none")")
            }
        }
    }

    private func contextChip<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 6) { content() }
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 11)
            .frame(minHeight: 30)
            .background(Capsule().fill(Theme.control))
    }

    // MARK: Properties above the keyboard

    private var propertyBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                if !statuses.isEmpty {
                    Menu {
                        Picker("Status", selection: $draft.statusId) {
                            ForEach(statuses) { option in
                                Label {
                                    Text(option.name)
                                } icon: {
                                    MenuImages.status(model.glyph(projectId: draft.projectId, optionId: option.id), scheme)
                                }
                                .tag(Optional(option.id))
                            }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        PropertyChip(text: statuses.first { $0.id == draft.statusId }?.name ?? "Status") {
                            StatusIcon(glyph: model.glyph(projectId: draft.projectId, optionId: draft.statusId), size: 16)
                        }
                    }
                    .accessibilityLabel("Status: \(statuses.first { $0.id == draft.statusId }?.name ?? "none")")
                    .accessibilityIdentifier("new-status")
                }
                if !priorities.isEmpty {
                    Menu {
                        Picker("Priority", selection: $draft.priorityId) {
                            Label {
                                Text("No priority")
                            } icon: {
                                MenuImages.priority(.none, scheme)
                            }
                            .tag(String?.none)
                            ForEach(priorities) { option in
                                Label {
                                    Text(option.name)
                                } icon: {
                                    MenuImages.priority(option.priorityLevel, scheme)
                                }
                                .tag(Optional(option.id))
                            }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        let option = priorities.first { $0.id == draft.priorityId }
                        PropertyChip(text: option?.name ?? "Priority", placeholder: option == nil) {
                            PriorityIcon(level: option?.priorityLevel ?? .none)
                        }
                    }
                    .accessibilityLabel("Priority: \(priorities.first { $0.id == draft.priorityId }?.name ?? "none")")
                    .accessibilityIdentifier("new-priority")
                }
                Button {
                    picker = .assignees
                } label: {
                    if draft.assignees.isEmpty {
                        PropertyChip(text: "Assignee", placeholder: true) {
                            Image(systemName: "person").foregroundStyle(Theme.textTertiary)
                        }
                    } else {
                        PropertyChip(text: draft.assignees.count == 1 ? draft.assignees[0].login : "\(draft.assignees.count) people") {
                            AvatarStack(people: draft.assignees, size: 18)
                        }
                    }
                }
                .buttonStyle(PlainPressStyle())
                .accessibilityLabel(draft.assignees.isEmpty ? "Assignee: none" : "Assignees: \(draft.assignees.map(\.login).joined(separator: ", "))")
                .accessibilityIdentifier("new-assignee")
                Button {
                    picker = .labels
                } label: {
                    if draft.labels.isEmpty {
                        PropertyChip(text: "Labels", placeholder: true) {
                            Image(systemName: "tag").foregroundStyle(Theme.textTertiary)
                        }
                    } else {
                        PropertyChip(text: draft.labels.count == 1 ? draft.labels[0].name : "\(draft.labels.count) labels") {
                            Circle().fill(Theme.labelColor(draft.labels[0].color)).frame(width: 8, height: 8)
                        }
                    }
                }
                .buttonStyle(PlainPressStyle())
                .accessibilityLabel(draft.labels.isEmpty ? "Labels: none" : "Labels: \(draft.labels.map(\.name).joined(separator: ", "))")
                .accessibilityIdentifier("new-labels")
                if draft.projectId != nil {
                    Button {
                        picker = .dueDate
                    } label: {
                        let day = draft.dueDate.flatMap(CalendarDay.init)
                        PropertyChip(text: day?.mediumLabel() ?? "Due date", placeholder: day == nil) {
                            DueDateIcon(size: 13)
                        }
                    }
                    .buttonStyle(PlainPressStyle())
                    .accessibilityLabel(draft.dueDate.flatMap(CalendarDay.init).map { "Due \($0.longLabel)" } ?? "Due date: none")
                    .accessibilityIdentifier("new-due")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
        .background(.bar)
    }

    // MARK: Data

    private var project: Project? { model.projects.first { $0.id == draft.projectId } }
    private var statuses: [FieldOption] { model.statusOptions(projectId: draft.projectId) }
    private var priorities: [FieldOption] { model.priorityOptions(projectId: draft.projectId) }
    private var repos: [RepoRef] { model.repos(forNewIssueIn: draft.projectId, repoId: draft.repoId) }

    /// The boards a new issue can go on: a repository's, when it was started in one, or else every open board.
    private var projectChoices: [Project] {
        context.repoId.map { model.boards(ofRepository: $0) } ?? model.openProjects
    }

    private var hasContent: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canCreate: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.repoId != nil
    }

    private func prepare() {
        guard !prepared else { return }
        prepared = true
        let parent = context.parentItemId.flatMap { model.item(id: $0) }
        let projectId: String?
        if let parent {
            // A sub-issue goes where its parent is, on its board or on none.
            projectId = parent.projectId
        } else if let repoId = context.repoId {
            projectId = model.boards(ofRepository: repoId).first?.id
        } else {
            projectId = context.projectId ?? model.openProjects.first?.id
        }
        var new = NewIssueDraft(projectId: projectId)
        new.parent = parent
        // A sub-issue lives in its parent's repository; one started in a repository lives there.
        new.repoId = parent?.repoId ?? context.repoId ?? projectId.flatMap { model.defaultRepoId(projectId: $0) }
        new.statusId = context.statusId ?? defaultStatus(projectId: projectId)
        if context.assignToMe, let viewer = model.viewer { new.assignees = [viewer.person] }
        draft = new
        model.loadRepoMeta(projectId: projectId)
        if projectId == nil, let parent { model.loadRepoMeta(for: parent) }
        focus = .title
    }

    private func defaultStatus(projectId: String?) -> String? {
        let options = model.statusOptions(projectId: projectId)
        return options.first { $0.statusCategory == .unstarted }?.id
            ?? options.first { $0.statusCategory == .backlog }?.id
            ?? options.first?.id
    }

    private func selectProject(_ id: String?) {
        guard id != draft.projectId else { return }
        draft.projectId = id
        draft.statusId = defaultStatus(projectId: id)
        draft.priorityId = nil
        model.loadRepoMeta(projectId: id)
        // In a repository, every choice keeps it, and with it the people and labels picked.
        guard context.repoId == nil, let id else { return }
        draft.repoId = model.defaultRepoId(projectId: id)
        // People and labels belong to a repository, so choices made for another one no longer apply.
        draft.assignees = []
        draft.labels = []
    }

    private func selectRepo(_ id: String) {
        guard id != draft.repoId else { return }
        draft.repoId = id
        draft.labels = []
    }

    private func create() {
        guard canCreate else { return }
        if model.createIssue(draft) != nil {
            created += 1
            dismiss()
        }
    }
}

/// The people and label pickers of a new issue, which change the draft rather than an issue.
private struct DraftPickerSheet: View {
    @Environment(AppModel.self) private var model
    var kind: PickerKind
    @Binding var draft: NewIssueDraft

    var body: some View {
        if kind == .dueDate {
            DueDateSheet(
                current: [draft.dueDate],
                addsField: model.projects.first { $0.id == draft.projectId }?.dueFieldId == nil
            ) { draft.dueDate = $0?.string }
        } else {
            PickerSheet(
                title: kind.sheetTitle,
                prompt: kind.searchPrompt,
                multiple: true,
                items: items,
                onPick: pick
            )
        }
    }

    private func items() -> [PickerItem] {
        switch kind {
        case .assignees:
            return model.people(projectId: draft.projectId, repoId: draft.repoId).map { person in
                PickerItem(
                    id: person.id, title: person.login, subtitle: person.name,
                    selected: draft.assignees.contains { $0.id == person.id },
                    icon: AnyView(Avatar(login: person.login, url: person.avatarUrl, size: 24))
                )
            }
        case .labels:
            return model.labels(projectId: draft.projectId, repoId: draft.repoId).map { label in
                PickerItem(
                    id: label.id, title: label.name, selected: draft.labels.contains { $0.id == label.id },
                    icon: AnyView(Circle().fill(Theme.labelColor(label.color)).frame(width: 11, height: 11))
                )
            }
        default:
            return []
        }
    }

    private func pick(_ id: String) {
        switch kind {
        case .assignees:
            if let index = draft.assignees.firstIndex(where: { $0.id == id }) {
                draft.assignees.remove(at: index)
            } else if let person = model.people(projectId: draft.projectId, repoId: draft.repoId).first(where: { $0.id == id }) {
                draft.assignees.append(person)
            }
        case .labels:
            if let index = draft.labels.firstIndex(where: { $0.id == id }) {
                draft.labels.remove(at: index)
            } else if let label = model.labels(projectId: draft.projectId, repoId: draft.repoId).first(where: { $0.id == id }) {
                draft.labels.append(label)
            }
        default:
            break
        }
    }
}
#endif
