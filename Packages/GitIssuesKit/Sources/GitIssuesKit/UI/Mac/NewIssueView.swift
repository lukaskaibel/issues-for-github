#if os(macOS)
import SwiftUI

struct NewIssueView: View {
    @Environment(AppModel.self) private var model
    var statusId: String?
    var parentItemId: String?

    @State private var draft = NewIssueDraft(projectId: "")
    @State private var openPicker: PickerKind?
    @FocusState private var focus: Field?

    private enum Field {
        case title
        case body
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if let project = model.projects.first(where: { $0.id == draft.projectId }) {
                    HStack(spacing: 6) {
                        ProjectSwatch(title: project.title, size: 10)
                        Text(project.title)
                    }
                    .font(.small)
                    .foregroundStyle(Theme.textBody)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.controlActive))
                }
                Text("›").foregroundStyle(Theme.textTertiary)
                Text(draft.parent == nil ? "New issue" : "New sub-issue").font(.small).foregroundStyle(Theme.textSecondary)
                Spacer()
                IconButton(systemName: "xmark", label: "Close (Esc)") { model.overlay = nil }
            }
            .padding(.leading, 18)
            .padding(.trailing, 14)
            .padding(.top, 14)

            VStack(alignment: .leading, spacing: 8) {
                TextField("Issue title", text: $draft.title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .semibold))
                    .focused($focus, equals: .title)
                    .focusOnAppear()
                    .onSubmit { focus = .body }

                ZStack(alignment: .topLeading) {
                    if draft.body.isEmpty {
                        Text("Add a description…")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textTertiary)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $draft.body)
                        .font(.system(size: 14))
                        .lineSpacing(3)
                        .scrollContentBackground(.hidden)
                        .scrollIndicators(.never)
                        .focused($focus, equals: .body)
                        .frame(height: 110)
                        // TextEditor insets its text by 5 pt; pull it back so it lines up with the title.
                        .padding(.leading, -5)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 8)

            HStack(spacing: 6) {
                chip(.status) {
                    StatusIcon(glyph: model.glyph(projectId: draft.projectId, optionId: draft.statusId))
                    Text(statuses.first { $0.id == draft.statusId }?.name ?? "No status")
                }
                if !priorities.isEmpty {
                    chip(.priority) {
                        let option = priorities.first { $0.id == draft.priorityId }
                        PriorityIcon(level: option?.priorityLevel ?? .none)
                        Text(option?.name ?? "Priority")
                    }
                }
                chip(.assignees) {
                    if draft.assignees.isEmpty {
                        Image(systemName: "person").font(.system(size: 11, weight: .medium))
                        Text("Assignee")
                    } else {
                        AvatarStack(people: draft.assignees, size: 16)
                        Text(draft.assignees.count == 1 ? draft.assignees[0].login : "\(draft.assignees.count) people")
                    }
                }
                chip(.labels) {
                    if draft.labels.isEmpty {
                        Image(systemName: "tag").font(.system(size: 11, weight: .medium))
                        Text("Labels")
                    } else {
                        Circle().fill(Theme.labelColor(draft.labels[0].color)).frame(width: 7, height: 7)
                        Text(draft.labels.count == 1 ? draft.labels[0].name : "\(draft.labels.count) labels")
                    }
                }
                if let parent = draft.parent {
                    HStack(spacing: 6) {
                        SubIssueGlyph().frame(width: 12, height: 12)
                        Text("Sub-issue of \(parent.displayNumber)")
                    }
                    .font(.small)
                    .foregroundStyle(Theme.textBody)
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Theme.popoverBorder, lineWidth: 1))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 14)

            Rectangle().fill(Theme.popoverBorder).frame(height: 1)

            HStack(spacing: 10) {
                Text("Repository").font(.small).foregroundStyle(Theme.textSecondary)
                Menu {
                    ForEach(repos) { repo in
                        Button(repo.nameWithOwner) { selectRepo(repo.id) }
                    }
                } label: {
                    Text(repos.first { $0.id == draft.repoId }?.nameWithOwner ?? "Choose…")
                        .font(.small)
                }
                .menuStyle(.borderlessButton)
                .tint(Theme.textBody)
                .fixedSize()
                .disabled(draft.parent != nil || repos.count < 2)
                Spacer()
                Text("⌘↵").font(.tiny).foregroundStyle(Theme.textSecondary)
                Button("Create issue", action: create)
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canCreate)
            }
            .padding(.leading, 18)
            .padding(.trailing, 14)
            .padding(.vertical, 12)
        }
        .frame(width: 720)
        .font(.ui)
        .foregroundStyle(Theme.text)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.popover))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.popoverBorder, lineWidth: 1))
        .shadow(color: Theme.shadow, radius: 40, y: 24)
        .onAppear(perform: prepare)
        .task {
            try? await Task.sleep(for: .milliseconds(300))
            if focus == nil { focus = .title }
        }
        .onExitCommand { model.overlay = nil }
    }

    private var statuses: [FieldOption] { model.statusOptions(projectId: draft.projectId) }
    private var priorities: [FieldOption] { model.priorityOptions(projectId: draft.projectId) }
    private var repos: [RepoRef] { model.repos(projectId: draft.projectId) }

    private var canCreate: Bool {
        !draft.title.trimmingCharacters(in: .whitespaces).isEmpty && draft.repoId != nil
    }

    private func prepare() {
        let parent = parentItemId.flatMap { id in model.allItems.first { $0.id == id } }
        let projectId = parent?.projectId ?? model.currentProjectId ?? model.projects.first { !$0.closed }?.id ?? ""
        var new = NewIssueDraft(projectId: projectId)
        new.parent = parent
        // A sub-issue lives in its parent's repository.
        new.repoId = parent?.repoId ?? model.defaultRepoId(projectId: projectId)
        let options = model.statusOptions(projectId: projectId)
        new.statusId = statusId
            ?? options.first { $0.statusCategory == .unstarted }?.id
            ?? options.first { $0.statusCategory == .backlog }?.id
            ?? options.first?.id
        draft = new
        focus = .title
        model.loadRepoMeta(projectId: projectId)
    }

    private func selectRepo(_ id: String) {
        guard id != draft.repoId else { return }
        draft.repoId = id
        // Labels belong to a repository, so a choice made for another one no longer applies.
        draft.labels = []
    }

    private func create() {
        guard canCreate else { return }
        if model.createIssue(draft) != nil {
            model.overlay = nil
        }
    }

    private func chip<Content: View>(_ kind: PickerKind, @ViewBuilder content: () -> Content) -> some View {
        Button {
            openPicker = kind
        } label: {
            HStack(spacing: 6) { content() }
                .font(.small)
                .foregroundStyle(Theme.textBody)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .frame(height: 26)
                .hoverFill(active: openPicker == kind, fill: Theme.controlActive)
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Theme.popoverBorder, lineWidth: 1))
        }
        .buttonStyle(PlainPressStyle())
        .dropdown(isPresented: Binding(get: { openPicker == kind }, set: { if !$0 { openPicker = nil } })) { close in
            PickerList(
                placeholder: kind.placeholder,
                items: items(kind),
                staysOpen: kind.staysOpen,
                width: kind.width,
                onPick: { pick(kind, $0) },
                onClose: close
            )
        }
    }

    private func items(_ kind: PickerKind) -> [PickerItem] {
        switch kind {
        case .status:
            return statuses.map { option in
                PickerItem(id: option.id, title: option.name, selected: draft.statusId == option.id, icon: AnyView(StatusIcon(glyph: model.glyph(projectId: draft.projectId, optionId: option.id))))
            }
        case .priority:
            return [PickerItem(id: "", title: "No priority", selected: draft.priorityId == nil, icon: AnyView(PriorityIcon(level: .none)))]
                + priorities.map { option in
                    PickerItem(id: option.id, title: option.name, selected: draft.priorityId == option.id, icon: AnyView(PriorityIcon(level: option.priorityLevel)))
                }
        case .assignees:
            return model.people(projectId: draft.projectId, repoId: draft.repoId).map { person in
                PickerItem(
                    id: person.id, title: person.login, subtitle: person.name,
                    selected: draft.assignees.contains { $0.id == person.id },
                    icon: AnyView(Avatar(login: person.login, url: person.avatarUrl, size: 18))
                )
            }
        case .labels:
            return model.labels(projectId: draft.projectId, repoId: draft.repoId).map { label in
                PickerItem(
                    id: label.id, title: label.name, selected: draft.labels.contains { $0.id == label.id },
                    icon: AnyView(Circle().fill(Theme.labelColor(label.color)).frame(width: 9, height: 9))
                )
            }
        case .subIssues:
            return []
        }
    }

    private func pick(_ kind: PickerKind, _ id: String) {
        switch kind {
        case .status:
            draft.statusId = id
        case .priority:
            draft.priorityId = id.isEmpty ? nil : id
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
        case .subIssues:
            break
        }
    }
}
#endif
