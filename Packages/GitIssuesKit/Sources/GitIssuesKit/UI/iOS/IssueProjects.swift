#if os(iOS)
import SwiftUI
import UIKit.UIDevice

/// The open projects of an issue on iPhone and narrow iPad windows, in a sheet of their own. A notice about taking the
/// issue off one, with its Undo, has to show over the sheet.
struct IssueProjectsSheet: View {
    var reference: IssueReference
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                MobileIssueProjects(reference: reference, addsWithoutProject: true)
                    .padding(20)
            }
            .accessibilityIdentifier("issue-projects-scroll")
            .background(Theme.panel)
            .navigationTitle(.issueProjectsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(.done, systemImage: "checkmark") { dismiss() }
                        .accessibilityIdentifier("issue-projects-done")
                }
            }
        }
        .overlay(alignment: .top) { NoticeBanners() }
        .presentationDetents([.large])
    }
}

/// The project the issue was opened from with the fields that have a value, the others folded under their name and
/// status, and a way to add more.
struct MobileIssueProjects: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var reference: IssueReference
    /// Whether an issue on no project can be added here too. The iPad's column has its own Project row for that.
    var addsWithoutProject = false
    @State private var editor: ProjectFieldTarget?
    @State private var adding = false
    @State private var dueTarget: ProjectFieldTarget?

    var body: some View {
        if let item = model.item(referencedBy: reference) {
            let sections = IssueProjectSection.sections(for: item, items: model.allItems, projects: model.projects, fields: model.fields)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 0) {
                        header(section)
                        if model.isIssueProjectUnfolded(section) {
                            fields(section)
                                .transition(.opacity)
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("issue-project-\(section.project.id)")
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
                }
                if item.isOnBoard || addsWithoutProject, item.kind != .draft, item.contentId != nil {
                    Button { adding = true } label: {
                        Label(.addToProjectPlaceholder, systemImage: "plus")
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("issue-projects")
                }
            }
            .font(.subheadline)
            .sheet(item: $editor) { target in MobileProjectFieldEditor(target: target) }
            .sheet(isPresented: $adding) { IssueMembershipSheet(reference: reference) }
            .sheet(item: $dueTarget) { target in ProjectDueDateSheet(target: target) }
        }
    }

    private func header(_ section: IssueProjectSection) -> some View {
        let unfolded = model.isIssueProjectUnfolded(section)
        return HStack(spacing: 8) {
            if section.isPrimary {
                title(section)
            } else {
                Button {
                    withAnimation(reduceMotion ? nil : Theme.spring) { model.toggleIssueProject(section) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.textTertiary)
                            .rotationEffect(.degrees(unfolded ? 90 : 0))
                            .frame(width: 12)
                        title(section)
                        if !unfolded, section.project.statusFieldId != nil {
                            StatusIcon(glyph: model.glyph(of: section.item), size: 15)
                            Text(model.statusText(of: section.item))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(section.project.title)
                .accessibilityValue(Text(unfolded ? .sectionOpen : .sectionFolded))
                .accessibilityIdentifier("toggle-project-\(section.project.id)")
            }
            if section.item.kind != .draft, section.project.viewerCanUpdate {
                Button {
                    withAnimation(reduceMotion ? nil : Theme.spring) {
                        model.setMembership(of: section.item, in: section.project, isMember: false)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(.removeIssueFromProject(project: section.project.title))
                .accessibilityIdentifier("remove-project-\(section.project.id)")
            }
        }
        .frame(minHeight: 44)
    }

    private func title(_ section: IssueProjectSection) -> some View {
        HStack(spacing: 8) {
            ProjectIcon(projectId: section.project.id)
            Text(section.project.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
        }
    }

    @ViewBuilder
    private func fields(_ section: IssueProjectSection) -> some View {
        let showsEmpty = model.showsEmptyFields(of: section)
        VStack(alignment: .leading, spacing: 0) {
            // All of them in the project's order once they show, so a field doesn't jump when it gets a value.
            ForEach(showsEmpty ? section.listedFields : section.filledFields) { field in
                fieldRow(section, field: field)
            }
            if showsEmpty, section.offersDueField {
                Button { dueTarget = ProjectFieldTarget(item: section.item, fieldId: "@due") } label: {
                    LabeledContent {
                        (section.item.due.map { Text($0.mediumLabel()) } ?? Text(.addDueDate))
                            .foregroundStyle(section.item.dueDate == nil ? Theme.textTertiary : Theme.text)
                    } label: { Text(.dueDate).foregroundStyle(Theme.textSecondary) }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!section.project.viewerCanUpdate)
                .accessibilityIdentifier("project-due-\(section.project.id)")
            }
            if section.hiddenCount > 0 {
                Button {
                    withAnimation(reduceMotion ? nil : Theme.spring) { model.toggleEmptyFields(of: section) }
                } label: {
                    (showsEmpty ? Text(.projectFieldsFewer) : Text(.projectFieldsMore(count: section.hiddenCount)))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("project-more-fields-\(section.project.id)")
            }
        }
    }

    private func fieldRow(_ section: IssueProjectSection, field: ProjectField) -> some View {
        let target = ProjectFieldTarget(item: section.item, fieldId: field.id)
        let isStatus = field.id == section.project.statusFieldId
        let text = isStatus ? model.statusText(of: section.item) : valueText(section, field: field)
        return Button { editor = target } label: {
            LabeledContent {
                HStack(spacing: 6) {
                    if isStatus { StatusIcon(glyph: model.glyph(of: section.item), size: 15) }
                    Text(verbatim: text)
                        .foregroundStyle(section.value(of: field) == nil ? Theme.textTertiary : Theme.text)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } label: {
                Text(verbatim: field.name).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 5)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!section.project.viewerCanUpdate || !model.canEditValue(of: field, on: section.item))
        .accessibilityLabel(field.name)
        .accessibilityValue(text)
        .accessibilityIdentifier("project-field-\(section.project.id)-\(field.id)")
    }

    private func valueText(_ section: IssueProjectSection, field: ProjectField) -> String {
        let value = section.value(of: field)
        if let iteration = field.iterations.first(where: { $0.id == value?.iterationId }),
           let when = model.iterationPlace(iteration, field: field) ?? model.iterationRange(iteration) {
            return "\(iteration.title) · \(when)"
        }
        return ProjectFieldEditing.label(field: field, value: value)
    }
}

private struct IssueMembershipSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var reference: IssueReference

    var body: some View {
        PickerSheet(title: .issueProjectsTitle, prompt: .searchIssueProjects, multiple: true, items: {
            guard let item = model.item(referencedBy: reference) else { return [] }
            let memberships = Set(model.allItems.filter { $0.contentId == item.contentId }.compactMap(\.projectId))
            return model.openProjects.filter(\.viewerCanUpdate).map { project in
                PickerItem(id: project.id, title: project.title, subtitle: project.ownerLogin,
                           selected: memberships.contains(project.id), icon: AnyView(ProjectIcon(projectId: project.id)))
            }
        }, onPick: { id in
            guard let item = model.item(referencedBy: reference),
                  let project = model.openProjects.first(where: { $0.id == id }) else { return }
            let member = model.allItems.contains { $0.contentId == item.contentId && $0.projectId == id }
            withAnimation(reduceMotion ? nil : Theme.spring) {
                model.setMembership(of: item, in: project, isMember: !member)
            }
        }, detents: UIDevice.current.userInterfaceIdiom == .pad ? [.large] : [.medium, .large])
    }
}

private struct ProjectDueDateSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var target: ProjectFieldTarget

    var body: some View {
        if let item = model.item(targetedBy: target), let project = model.project(of: item),
           !project.closed, project.viewerCanUpdate {
            DueDateSheet(current: [item.dueDate], addsField: project.dueFieldId == nil) { day in
                model.saveProjectDueDate(target, to: day)
            }
        } else {
            Color.clear.task { dismiss() }
        }
    }
}

private struct MobileProjectFieldEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var target: ProjectFieldTarget

    var body: some View {
        if let item = model.item(targetedBy: target), let field = model.field(id: target.fieldId),
           let project = model.project(of: item), field.projectId == project.id, project.viewerCanUpdate {
            let value = IssueProjectSection(project: project, item: item, fields: []).value(of: field)
            Group {
                switch field.kind {
                case .singleSelect, .multiSelect, .iteration:
                    PickerSheet(title: .projectFieldEmpty, prompt: .projectFieldEmpty, multiple: field.kind == .multiSelect, fieldName: field.name, items: {
                        model.projectFieldChoices(field: field, value: value)
                    }, creating: { query in
                        model.newProjectStatusRow(query, target: target)
                    }, onPick: { id in
                        model.pickProjectField(id, target: target)
                    })
                    .task {
                        if field.id == project.statusFieldId { model.refreshStatuses(projectId: project.id) }
                    }
                case .date:
                    DueDateSheet(current: [value?.date], addsField: false, fieldName: field.name) { day in
                        model.saveProjectField(target, value: day.map { FieldValue(date: $0.string) })
                    }
                case .text, .number:
                    ProjectValueSheet(target: target, field: field, value: value)
                default:
                    EmptyView()
                }
            }
        } else {
            Color.clear.task { dismiss() }
        }
    }
}

private struct ProjectValueSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var target: ProjectFieldTarget
    var field: ProjectField
    var value: FieldValue?
    @State private var text = ""
    @FocusState private var focused: Bool

    private var empty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var invalid: Bool { field.kind == .number && !empty && ProjectFieldInput.number(text) == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(field.name, text: $text, axis: field.kind == .number ? .horizontal : .vertical)
                        .keyboardType(field.kind == .number ? .numbersAndPunctuation : .default)
                        .lineLimit(1...8)
                        .focused($focused)
                        .accessibilityIdentifier("project-field-input")
                } footer: {
                    if invalid { Text(.projectFieldInvalidNumber).foregroundStyle(Theme.warning) }
                }
                if value != nil {
                    Button(.projectFieldClear, role: .destructive) { save(nil) }
                        .accessibilityIdentifier("project-field-clear")
                }
            }
            .navigationTitle(Text(verbatim: field.name))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(.cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(.saveButton) {
                        guard !invalid else { return }
                        if empty { save(nil) }
                        else if field.kind == .number { save(ProjectFieldInput.number(text).map { FieldValue(number: $0) }) }
                        else { save(FieldValue(text: text)) }
                    }
                    .disabled(invalid)
                    .accessibilityIdentifier("project-field-save")
                }
            }
        }
        .onAppear {
            text = value?.text ?? value?.number.map { $0.formatted(.number.grouping(.never).precision(.significantDigits(1...17))) } ?? ""
            focused = true
        }
    }

    private func save(_ value: FieldValue?) {
        model.saveProjectField(target, value: value)
        dismiss()
    }
}
#endif
