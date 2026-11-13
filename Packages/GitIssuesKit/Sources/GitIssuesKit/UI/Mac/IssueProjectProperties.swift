#if os(macOS)
import SwiftUI

struct IssuePropertyRow<Content: View>: View {
    var title: Text
    @Binding var labelWidth: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            title
                .font(.small)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: min(labelWidth, 110), alignment: .leading)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 30)
    }
}

/// Project fields are independent of the board view's visible columns and of the current selection.
struct IssueProjectProperties: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var section: IssueProjectSection
    @Binding var labelWidth: CGFloat
    @State private var hovering = false
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(reduceMotion ? nil : Theme.spring) { expanded.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        ProjectIcon(projectId: section.project.id)
                        Text(section.project.title)
                            .font(.smallMedium)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(section.project.title)
                .accessibilityValue(Text(expanded ? .sectionOpen : .sectionFolded))
                .accessibilityIdentifier("toggle-project-\(section.project.id)")
                if section.item.kind != .draft, section.project.viewerCanUpdate {
                    IconButton(systemName: "xmark", label: String(localized: .removeIssueFromProject(project: section.project.title)), size: 20) {
                        model.setMembership(of: section.item, in: section.project, isMember: false)
                    }
                    .opacity(hovering ? 1 : 0)
                    .disabled(model.projectMembershipChanges.isSaving(section.item, projectId: section.project.id, in: model.db, remaps: model.status.idRemaps))
                    .accessibilityIdentifier("remove-project-\(section.project.id)")
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            VStack(alignment: .leading, spacing: 0) {
                if expanded {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(section.fields) { field in
                            IssuePropertyRow(title: Text(verbatim: field.name), labelWidth: $labelWidth) {
                                ProjectFieldProperty(section: section, field: field)
                            }
                        }
                        // Preserve the existing shortcut for adding a due-date field to a project that has none.
                        if !section.fields.contains(where: { $0.id == section.project.dueFieldId }) {
                            IssuePropertyRow(title: Text(.dueDate), labelWidth: $labelWidth) {
                                ProjectDueDateProperty(item: section.item, canEdit: section.project.viewerCanUpdate)
                            }
                        }
                    }
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(section.project.title)
    }
}

struct IssueProjectsButton: View {
    var item: Item
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            Label(.addToProjectPlaceholder, systemImage: "plus")
                .font(.small)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 8)
                .frame(minHeight: 28)
                .hoverFill(active: open, radius: 8)
        }
        .buttonStyle(PlainPressStyle())
        .accessibilityIdentifier("issue-projects")
        .dropdown(isPresented: $open) { close in
            IssueProjectsPicker(item: item, close: close)
        }
    }
}

private struct IssueProjectsPicker: View {
    @Environment(AppModel.self) private var model
    var item: Item
    var close: () -> Void

    var body: some View {
        if let current = model.item(referencedBy: IssueReference(item)) {
            let memberships = Set(model.allItems.filter { $0.contentId == current.contentId }.compactMap(\.projectId))
            let projects = model.openProjects.filter(\.viewerCanUpdate)
            PickerList(placeholder: String(localized: .searchIssueProjects), items: projects.map { project in
                PickerItem(id: project.id, title: project.title, subtitle: project.ownerLogin,
                           selected: memberships.contains(project.id), icon: AnyView(ProjectIcon(projectId: project.id)),
                           trailing: model.projectMembershipChanges.isSaving(current, projectId: project.id, in: model.db, remaps: model.status.idRemaps)
                               ? AnyView(ProgressView().controlSize(.mini)) : nil)
            }, multiple: true, width: 320, onPick: { id in
                guard let project = model.projects.first(where: { $0.id == id }) else { return }
                model.setMembership(of: current, in: project, isMember: !memberships.contains(id))
            }, onClose: close)
        } else {
            Color.clear.task { close() }
        }
    }
}

private struct ProjectFieldProperty: View {
    @Environment(AppModel.self) private var model
    var section: IssueProjectSection
    var field: ProjectField
    @State private var open = false

    private var value: FieldValue? { section.value(of: field) }
    private var selectedOption: FieldChoice? {
        if field.id == section.project.statusFieldId {
            return model.statusOption(of: section.item).map { FieldChoice(id: $0.id, name: $0.name, color: $0.color, descr: $0.descr) }
        }
        if field.id == section.project.priorityFieldId {
            return model.priorityOption(of: section.item).map { FieldChoice(id: $0.id, name: $0.name, color: $0.color, descr: $0.descr) }
        }
        return field.options.first { $0.id == value?.optionId }
    }

    var body: some View {
        Button { open = true } label: {
            HStack(spacing: 7) {
                if let option = selectedOption {
                    if field.id == section.project.statusFieldId {
                        StatusIcon(glyph: model.glyph(of: section.item))
                    } else if field.id == section.project.priorityFieldId {
                        PriorityIcon(level: model.priorityLevel(of: section.item))
                    } else {
                        Circle().fill(Theme.optionColor(option.color) ?? Theme.textTertiary).frame(width: 9, height: 9)
                    }
                    Text(option.name)
                } else if let ids = value?.optionIds, !ids.isEmpty {
                    Text(field.options.filter { ids.contains($0.id) }.map(\.name).formatted(.list(type: .and)))
                } else if let iteration = field.iterations.first(where: { $0.id == value?.iterationId }) {
                    IterationIcon(size: 13)
                    Text(iteration.title)
                } else if let day = value?.date.flatMap(CalendarDay.init) {
                    if field.id == section.project.dueFieldId, let due = model.dueBadge(for: section.item) {
                        DueDateIcon(tone: due.tone, size: 12)
                        Text(day.mediumLabel())
                            .foregroundStyle(due.tone == .overdue || due.tone == .today ? due.tone.color : Theme.text)
                    } else {
                        Image(systemName: "calendar").font(.system(size: 12))
                        Text(day.mediumLabel())
                    }
                } else if let text = value?.text {
                    Text(verbatim: text)
                } else if let number = value?.number {
                    Text(number.formatted()).monospacedDigit()
                } else {
                    Text(.projectFieldEmpty).foregroundStyle(Theme.textTertiary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .padding(.horizontal, 8)
            .hoverFill(active: open, radius: 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainPressStyle())
        .disabled(!section.project.viewerCanUpdate || model.projectEdits.isSaving(ProjectFieldTarget(item: section.item, fieldId: field.id), in: model.db, remaps: model.status.idRemaps))
        .accessibilityLabel(field.name)
        .accessibilityValue(spokenValue)
        .accessibilityIdentifier("project-field-\(section.item.id)-\(field.id)")
        .dropdown(isPresented: $open) { close in
            switch field.kind {
            case .singleSelect, .multiSelect, .iteration:
                ProjectFieldChoicePicker(target: ProjectFieldTarget(item: section.item, fieldId: field.id), close: close)
            case .date:
                DueDatePicker(current: [value?.date], addsField: false, fieldName: field.name, onPick: { day in
                    save(day.map { FieldValue(date: $0.string) })
                }, onClose: close)
            case .text, .number:
                ProjectFieldTextEditor(field: field, value: value, onSave: save, close: close)
            default:
                EmptyView()
            }
        }
    }

    private var spokenValue: String {
        if field.id == section.project.statusFieldId || field.id == section.project.priorityFieldId {
            return selectedOption?.name ?? String(localized: .projectFieldEmpty)
        }
        return ProjectFieldEditing.label(field: field, value: value)
    }

    private func save(_ value: FieldValue?) {
        model.saveProjectField(ProjectFieldTarget(item: section.item, fieldId: field.id), value: value)
    }
}

/// A dropdown has a root of its own. Read the observed model here so checks follow picks that keep it open.
private struct ProjectFieldChoicePicker: View {
    @Environment(AppModel.self) private var model
    var target: ProjectFieldTarget
    var close: () -> Void

    var body: some View {
        if let item = model.item(targetedBy: target), let field = model.field(id: target.fieldId), let project = model.project(of: item) {
            let value = IssueProjectSection(project: project, item: item, fields: []).value(of: field)
            PickerList(placeholder: field.name, items: model.projectFieldChoices(field: field, value: value), multiple: field.kind == .multiSelect,
                       creating: field.id == project.statusFieldId ? { model.newProjectStatusRow($0, target: target) } : nil,
                       onPick: { id in
                model.pickProjectField(id, target: target)
            }, onClose: close)
            .disabled(!project.viewerCanUpdate || model.projectEdits.isSaving(target, in: model.db, remaps: model.status.idRemaps))
            .onAppear {
                if field.id == project.statusFieldId { model.refreshStatuses(projectId: project.id) }
            }
        }
    }
}

private struct ProjectDueDateProperty: View {
    @Environment(AppModel.self) private var model
    var item: Item
    var canEdit: Bool
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            (item.due.map { Text($0.mediumLabel()) } ?? Text(.addDueDate))
                .foregroundStyle(item.dueDate == nil ? Theme.textTertiary : Theme.text)
                .padding(.horizontal, 8)
                .frame(minHeight: 28)
                .hoverFill(active: open, radius: 8)
        }
        .buttonStyle(PlainPressStyle())
        .disabled(!canEdit)
        .dropdown(isPresented: $open) { close in
            ProjectDueDatePicker(target: ProjectFieldTarget(item: item, fieldId: "@due"), close: close)
        }
    }
}

private struct ProjectDueDatePicker: View {
    @Environment(AppModel.self) private var model
    var target: ProjectFieldTarget
    var close: () -> Void

    var body: some View {
        if let item = model.item(targetedBy: target), let project = model.project(of: item),
           !project.closed, project.viewerCanUpdate {
            DueDatePicker(current: [item.dueDate], addsField: project.dueFieldId == nil, onPick: { day in
                model.saveProjectDueDate(target, to: day)
            }, onClose: close)
        } else {
            Color.clear.task { close() }
        }
    }
}

private struct ProjectFieldTextEditor: View {
    var field: ProjectField
    var value: FieldValue?
    var onSave: (FieldValue?) -> Void
    var close: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    private var isNumber: Bool { field.kind == .number }
    private var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var invalid: Bool { isNumber && !isEmpty && ProjectFieldInput.number(text) == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: field.name).font(.smallMedium)
            TextField(field.name, text: $text, axis: isNumber ? .horizontal : .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...6)
                .focused($focused)
                .onSubmit(save)
                .onKeyPress(.escape) { close(); return .handled }
            if invalid {
                Text(.projectFieldInvalidNumber).font(.small).foregroundStyle(Theme.warning)
            }
            HStack {
                Button(.projectFieldClear) { onSave(nil); close() }
                    .disabled(value == nil)
                Spacer()
                Button(.cancel, action: close)
                Button(.saveButton, action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(invalid)
            }
        }
        .padding(12)
        .frame(width: 300)
        .onAppear {
            text = value?.text ?? value?.number.map { $0.formatted(.number.grouping(.never).precision(.significantDigits(1...17))) } ?? ""
            focused = true
        }
    }

    private func save() {
        guard !invalid else { return }
        if isEmpty {
            onSave(nil)
        } else if isNumber, let number = ProjectFieldInput.number(text) {
            onSave(FieldValue(number: number))
        } else {
            onSave(FieldValue(text: text))
        }
        close()
    }
}
#endif
