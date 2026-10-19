#if os(macOS)
import SwiftUI

/// A new milestone, or one to change: its name, the day it is due and what it is about. Like the new-issue dialog,
/// it opens over the window; ⌘↵ saves.
struct MilestoneEditor: View {
    @Environment(AppModel.self) private var model
    var projectId: String?
    /// The milestone to change; nil makes a new one.
    var title: String?
    /// Issues that go into a new milestone once it is made, when it was started from their milestone picker.
    var assigning: [String]

    @State private var name = ""
    @State private var due: CalendarDay?
    @State private var descr = ""
    @State private var dueOpen = false
    @FocusState private var focus: Field?
    @State private var editingDescription = false
    @State private var descriptionHeight: CGFloat = 74

    private enum Field {
        case name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if let project {
                    HStack(spacing: 6) {
                        ProjectIcon(projectId: project.id, size: 10)
                        Text(project.title)
                    }
                    .font(.small)
                    .foregroundStyle(Theme.textBody)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.controlActive))
                    Text("›").foregroundStyle(Theme.textTertiary)
                }
                Text(existing == nil ? .newMilestoneHeader : .editMilestoneHeader).font(.small).foregroundStyle(Theme.textSecondary)
                Spacer()
                IconButton(systemName: "xmark", label: String(localized: .closeWithEscShortcut)) { model.overlay = nil }
            }
            .padding(.leading, 18)
            .padding(.trailing, 14)
            .padding(.top, 14)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    MilestoneIcon(mark: existing.map { model.mark(of: $0, projectId: projectId) } ?? .upcoming, size: 16)
                    TextField(.milestoneNamePlaceholder, text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 18, weight: .semibold))
                        .focused($focus, equals: .name)
                        .focusOnAppear()
                        .onSubmit { editingDescription = true }
                }
                // What it is about, as it will look on GitHub, growing with the text up to a point and then scrolling.
                ScrollView {
                    MarkdownEditor(
                        draft: $descr,
                        placeholder: .milestoneDescriptionPlaceholder,
                        editing: $editingDescription,
                        onSubmit: save,
                        onEscape: { model.overlay = nil },
                        accessibilityLabel: .milestoneDescriptionPlaceholder,
                        accessibilityIdentifier: "milestone-description"
                    )
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { descriptionHeight = $0 }
                    // A click below the text puts the caret at its end.
                    .frame(minHeight: 74, alignment: .top)
                    .background { Color.clear.contentShape(.rect).onTapGesture { editingDescription = true } }
                }
                .scrollIndicators(.never)
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: min(max(descriptionHeight, 74), 260))
                .padding(.leading, 26)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 8)

            HStack(spacing: 6) {
                Button {
                    dueOpen = true
                } label: {
                    HStack(spacing: 6) {
                        DueDateIcon(size: 11)
                        (due.map { Text($0.mediumLabel()) } ?? Text(.dueDate))
                    }
                    .font(.small)
                    .foregroundStyle(Theme.textBody)
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .hoverFill(active: dueOpen, fill: Theme.controlActive)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Theme.popoverBorder, lineWidth: 1))
                }
                .buttonStyle(PlainPressStyle())
                .dropdown(isPresented: $dueOpen) { close in
                    DueDatePicker(current: [due?.string], addsField: false, width: 280, onPick: { due = $0 }, onClose: close)
                }
                if !assigning.isEmpty {
                    Text(.milestoneWillHoldIssues(count: assigning.count))
                        .font(.small)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.leading, 6)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 14)

            Rectangle().fill(Theme.popoverBorder).frame(height: 1)

            HStack(spacing: 10) {
                if let repo = repository, existing == nil {
                    Text(.milestoneMadeIn(repository: repo.nameWithOwner))
                        .font(.small)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                } else if let existing, existing.milestones.count > 1 {
                    Text(.milestoneInRepositories(count: existing.milestones.count))
                        .font(.small)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Text("⌘↵").font(.tiny).foregroundStyle(Theme.textSecondary)
                Button(existing == nil ? .createMilestoneButton : .saveButton, action: save)
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canSave)
            }
            .padding(.leading, 18)
            .padding(.trailing, 14)
            .padding(.vertical, 12)
        }
        .frame(width: 560)
        .font(.ui)
        .foregroundStyle(Theme.text)
        // A glass panel over the window, as the command palette.
        .glassPanel(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onAppear(perform: prepare)
        .onExitCommand { model.overlay = nil }
    }

    /// The board: the one given, else the one on screen, else the first.
    private var boardId: String? {
        projectId ?? model.scopeProjectId ?? model.openProjects.first?.id
    }

    private var project: Project? {
        boardId.flatMap { id in model.projects.first { $0.id == id } }
    }

    private var existing: MilestoneGroup? {
        guard let title, let boardId else { return nil }
        return model.milestoneGroup(projectId: boardId, title: title)
    }

    private var repository: RepoRef? {
        boardId.flatMap { model.repositoryForNewMilestone(projectId: $0) }
    }

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        guard !trimmed.isEmpty, let boardId else { return false }
        // Another open milestone of that name is the same one on this board.
        if trimmed != existing?.title, model.milestoneGroup(projectId: boardId, title: trimmed)?.isOpen == true { return false }
        return existing != nil || repository != nil
    }

    private func prepare() {
        if let existing {
            name = existing.title
            due = existing.due
            descr = existing.descr
        } else {
            name = model.newIssueTitle ?? ""
            model.newIssueTitle = nil
        }
        focus = .name
    }

    private func save() {
        guard canSave, let boardId else { return }
        if let existing {
            model.editMilestone(existing, projectId: boardId, title: trimmed, due: due, descr: descr)
        } else if let group = model.createMilestone(projectId: boardId, title: trimmed, due: due, descr: descr) {
            let items = assigning.compactMap { model.item(id: $0) }
            if !items.isEmpty { model.setMilestone(of: items, to: group) }
        }
        model.overlay = nil
    }
}

#endif
