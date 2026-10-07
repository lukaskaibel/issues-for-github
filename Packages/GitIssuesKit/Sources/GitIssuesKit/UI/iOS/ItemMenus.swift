#if os(iOS)
import SwiftUI

/// Everything that can be done to an issue, as one menu: what a long press on a row, a card or a
/// sub-issue shows, and the same as the Mac's right-click menu.
struct ItemMenuContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    var item: Item
    /// Hidden in the issue's own screen, where it is open already.
    var showsOpen = true
    var onOpen: () -> Void = {}

    var body: some View {
        if showsOpen {
            Button(action: onOpen) {
                Label("Open", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            Divider()
        }
        StatusMenu(item: item)
        if model.project(of: item)?.priorityFieldId != nil {
            PriorityMenu(item: item)
        }
        if item.kind != .draft {
            AssigneeMenu(item: item)
            LabelsMenu(item: item)
            if let viewer = model.viewer {
                let mine = item.assignees.contains { $0.id == viewer.id }
                Button {
                    model.toggleAssignee(item, viewer.person)
                } label: {
                    Label(mine ? "Unassign Me" : "Assign to Me", systemImage: mine ? "person.crop.circle.badge.minus" : "person.crop.circle.badge.plus")
                }
            }
        }
        if model.canHaveDueDate(item) {
            DueDateMenu(item: item)
        }
        if let url = item.webURL {
            Divider()
            Button {
                model.copyLink(item)
            } label: {
                Label("Copy Link", systemImage: "link")
            }
            if item.branchName != nil {
                Button {
                    model.copyBranchName(item)
                } label: {
                    Label("Copy Branch Name", systemImage: "arrow.triangle.branch")
                }
            }
            ShareLink(item: url, subject: Text(item.title), message: Text("\(item.displayNumber) \(item.title)"), preview: SharePreview("\(item.displayNumber) \(item.title)")) {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
            Button {
                model.openOnGitHub(item)
            } label: {
                Label("Open on GitHub", systemImage: "arrow.up.right.square")
            }
        }
        if item.kind == .issue || item.kind == .draft {
            Divider()
            Button(role: .destructive) {
                model.requestDelete(item)
            } label: {
                Label(item.kind == .draft ? "Delete Draft…" : "Delete Issue…", systemImage: "trash")
            }
            .disabled(!model.canDelete(item))
        }
    }
}

/// Status as a submenu with the app's status circles, the current one checked.
struct StatusMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    var item: Item

    var body: some View {
        if item.isOnBoard {
            statusMenu
        } else {
            // An issue on none of your boards goes onto one instead of getting a status.
            let boards = model.boards(toAdd: item)
            Menu {
                AddToProjectMenuItems(item: item)
            } label: {
                Label {
                    Text(boards.count == 1 ? "Add to \(boards[0].title)" : "Add to Project")
                } icon: {
                    MenuImages.status(model.glyph(of: item), scheme)
                }
            }
            .disabled(boards.isEmpty || item.kind != .issue)
        }
    }

    private var statusMenu: some View {
        let statuses = model.statusOptions(projectId: item.projectId)
        return Menu {
            Picker("Status", selection: selection) {
                ForEach(statuses) { option in
                    Label {
                        Text(option.name)
                    } icon: {
                        MenuImages.status(model.glyph(projectId: item.projectId, optionId: option.id), scheme)
                    }
                    .tag(Optional(option.id))
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label {
                Text("Status")
            } icon: {
                MenuImages.status(model.glyph(of: item), scheme)
            }
        }
        .disabled(statuses.isEmpty)
    }

    private var selection: Binding<String?> {
        Binding(
            get: { item.statusId },
            set: { id in
                let current = model.item(id: item.id) ?? item
                guard let option = model.statusOptions(projectId: current.projectId).first(where: { $0.id == id }) else { return }
                withAnimation(Theme.spring) { model.setStatus(current, to: option) }
            }
        )
    }
}

/// For an issue on none of your boards: the columns of the boards it can go on. One tap puts it there.
struct AddToProjectMenuItems: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    var item: Item

    var body: some View {
        let boards = model.boards(toAdd: item)
        if boards.count == 1, let project = boards.first {
            Section("Add to \(project.title)") { columns(of: project) }
        } else {
            ForEach(boards) { project in
                Menu {
                    columns(of: project)
                } label: {
                    Text(project.title)
                }
            }
        }
    }

    @ViewBuilder
    private func columns(of project: Project) -> some View {
        let statuses = model.statusOptions(projectId: project.id)
        if statuses.isEmpty {
            Button(project.title) { add(to: project, "") }
        }
        ForEach(statuses) { option in
            Button {
                add(to: project, option.id)
            } label: {
                Label {
                    Text(option.name)
                } icon: {
                    MenuImages.status(model.glyph(projectId: project.id, optionId: option.id), scheme)
                }
            }
        }
    }

    private func add(to project: Project, _ optionId: String) {
        let current = model.item(id: item.id) ?? item
        model.pick(.status, id: "\(project.id)/\(optionId)", for: current)
    }
}

/// Priority as a submenu with the bars, from "No priority" to "Urgent".
struct PriorityMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    var item: Item

    var body: some View {
        Menu {
            Picker("Priority", selection: selection) {
                Label {
                    Text("No priority")
                } icon: {
                    MenuImages.priority(.none, scheme)
                }
                .tag("")
                ForEach(model.priorityOptions(projectId: item.projectId)) { option in
                    Label {
                        Text(option.name)
                    } icon: {
                        MenuImages.priority(option.priorityLevel, scheme)
                    }
                    .tag(option.id)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label {
                Text("Priority")
            } icon: {
                MenuImages.priority(model.priorityLevel(of: item), scheme)
            }
        }
    }

    private var selection: Binding<String> {
        Binding(
            get: { item.priorityId ?? "" },
            set: { id in
                let current = model.item(id: item.id) ?? item
                model.setPriority(current, to: model.priorityOptions(projectId: current.projectId).first { $0.id == id })
            }
        )
    }
}

/// People who can be assigned, each with a checkmark when assigned.
struct AssigneeMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    var item: Item

    var body: some View {
        Menu {
            ForEach(model.people(for: item)) { person in
                Toggle(isOn: Binding(
                    get: { item.assignees.contains { $0.id == person.id } },
                    set: { _ in model.toggleAssignee(model.item(id: item.id) ?? item, person) }
                )) {
                    Label {
                        Text(person.login)
                    } icon: {
                        MenuImages.avatar(person, scheme)
                    }
                }
            }
        } label: {
            Label {
                Text("Assignee")
            } icon: {
                if let first = item.assignees.first {
                    MenuImages.avatar(first, scheme)
                } else {
                    Image(systemName: "person.crop.circle")
                }
            }
        }
        .onAppear { model.loadRepoMeta(for: item) }
    }
}

/// The repository's labels, each with a checkmark when set.
struct LabelsMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    var item: Item

    var body: some View {
        let labels = model.labels(for: item)
        Menu {
            if labels.isEmpty {
                Text("No labels in this repository")
            }
            ForEach(labels) { label in
                Toggle(isOn: Binding(
                    get: { item.labels.contains { $0.id == label.id } },
                    set: { _ in model.toggleLabel(model.item(id: item.id) ?? item, label) }
                )) {
                    Label {
                        Text(label.name)
                    } icon: {
                        MenuImages.label(label.color, scheme)
                    }
                }
            }
        } label: {
            Label("Labels", systemImage: "tag")
        }
    }
}

/// The lifted preview of a long-pressed issue: where it is, its title and its properties.
struct IssuePreview: View {
    @Environment(AppModel.self) private var model
    var item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                StatusIcon(glyph: model.glyph(of: item), size: 15)
                Text(item.displayNumber).monospacedDigit()
                if let project = model.project(of: item) {
                    ProjectSwatch(title: project.title, size: 10)
                    Text(project.title).lineLimit(1)
                } else if let repo = item.repoShortName {
                    RepositoryIcon(size: 9)
                    Text(repo).lineLimit(1)
                }
            }
            .font(.footnote)
            .foregroundStyle(Theme.textTertiary)
            Text(item.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                if let status = model.statusOption(of: item) {
                    PropertyChip(text: status.name) { StatusIcon(glyph: model.glyph(of: item), size: 14) }
                }
                if let priority = model.priorityOption(of: item) {
                    PropertyChip(text: priority.name) { PriorityIcon(level: priority.priorityLevel) }
                }
                if let person = item.assignees.first {
                    PropertyChip(text: item.assignees.count == 1 ? person.login : "\(item.assignees.count) people") {
                        AvatarStack(people: item.assignees, size: 18)
                    }
                }
                if let due = model.dueBadge(for: item) {
                    PropertyChip(text: due.label, tint: due.tone == .overdue || due.tone == .today ? due.tone.color : nil) {
                        DueDateIcon(tone: due.tone, size: 12)
                    }
                }
            }
            if !item.body.isEmpty {
                Text(item.body)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textBody)
                    .lineLimit(4)
            }
        }
        .padding(18)
        .frame(width: 340, alignment: .leading)
        .background(Theme.panel)
    }
}
#endif
