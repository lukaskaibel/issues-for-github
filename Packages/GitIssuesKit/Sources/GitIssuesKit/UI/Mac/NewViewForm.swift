#if os(macOS)
import AppKit
import SwiftUI

/// A view's layout as you see it: a board, a list or GitHub's roadmap.
struct ViewLayoutIcon: View {
    @Environment(AppModel.self) private var model
    var view: ProjectView
    var size: CGFloat = 11

    var body: some View {
        Group {
            if view.layout == .roadmap, model.display(of: view).layout == nil {
                RoadmapIcon(size: size + 1)
            } else {
                Image(systemName: model.layout(of: view) == .board ? "rectangle.split.3x1" : "list.bullet")
                    .font(.system(size: size, weight: .medium))
            }
        }
        .frame(width: size + 3, height: size + 3)
        .accessibilityHidden(true)
    }
}

// MARK: - A new view

/// Makes a new view, starting from the one open or the one being duplicated: name it, and set its layout, filter,
/// columns, grouping and order, which GitHub takes only now.
struct NewViewForm: View {
    @Environment(AppModel.self) private var model
    var projectId: String
    var source: ProjectView?
    var duplicate: Bool
    var close: () -> Void

    @State private var template: ProjectView?
    @State private var name = ""
    @State private var layout: ViewMode = .board
    @State private var filter = ProjectFilter("")
    @State private var creating = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        let project = model.projects.first { $0.id == projectId }
        VStack(alignment: .leading, spacing: 12) {
            Text(.newViewIn(project: project?.title ?? ""))
                .font(.uiSemibold)
            TextField(.viewNamePlaceholder, text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .focused($nameFocused)
                .focusOnAppear()
                .padding(.horizontal, 9)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(nameFocused ? Theme.accent : Theme.chipBorder, lineWidth: nameFocused ? 1.5 : 1))
                .onSubmit(create)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text(.layout).foregroundStyle(Theme.textSecondary)
                    LayoutSwitch(mode: $layout)
                }
                GridRow(alignment: .top) {
                    Text(.filter).foregroundStyle(Theme.textSecondary).frame(height: 24)
                    FilterChipsRow(filter: $filter, projectId: projectId, wraps: true)
                }
                if let binding = templateBinding {
                    if layout == .board {
                        GridRow {
                            Text(.columns).foregroundStyle(Theme.textSecondary)
                            FieldMenu(choices: model.columnChoices(projectId: projectId), selection: binding.columnFieldId, noneTitle: nil)
                        }
                    } else {
                        GridRow {
                            Text(.groupBy).foregroundStyle(Theme.textSecondary)
                            FieldMenu(choices: model.groupChoices(projectId: projectId), selection: binding.groupByFieldId, noneTitle: model.statusFieldTitle(projectId: projectId))
                        }
                    }
                    GridRow {
                        Text(.orderBy).foregroundStyle(Theme.textSecondary)
                        SortMenu(projectId: projectId, sort: binding.sortBy)
                    }
                }
            }
            .font(.small)
            Text(.groupingFixedHint)
                .font(.tiny)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(Theme.popoverBorder).frame(height: 1).padding(.horizontal, -14)
            HStack(spacing: 8) {
                if let source {
                    Text(.startsFrom(view: source.name))
                        .font(.small)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Button(.cancel, action: close)
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(action: create) {
                    HStack(spacing: 6) {
                        if creating { ProgressView().controlSize(.mini) }
                        Text(.createView)
                        Text("⌘↩").opacity(0.7)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || creating || !model.canReachGitHub)
                .help(model.canReachGitHub ? Text(.createView) : Text(.needsConnection))
            }
        }
        .padding(14)
        .frame(width: 440)
        .font(.ui)
        .foregroundStyle(Theme.text)
        .onAppear {
            var start = model.template(from: source, projectId: projectId, name: duplicate ? String(localized: .viewCopyName(view: source?.name ?? "")) : "")
            if source == nil { start.columnFieldId = model.currentStatusFieldId(projectId: projectId) }
            template = start
            name = start.name
            layout = start.layout == .board ? .board : .list
            filter = ProjectFilter(start.filter)
        }
    }

    private var templateBinding: Binding<ProjectView>? {
        guard template != nil else { return nil }
        return Binding(get: { template! }, set: { template = $0 })
    }

    private func create() {
        guard var view = template, !creating else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        view.name = trimmed
        view.filter = filter.text
        if layout == .board {
            view.layout = .board
            view.groupByFieldId = nil
            if view.columnFieldId == nil { view.columnFieldId = model.currentStatusFieldId(projectId: projectId) }
        } else {
            view.layout = view.layout == .roadmap ? .roadmap : .table
            view.columnFieldId = nil
        }
        creating = true
        Task {
            let made = await model.createView(view)
            creating = false
            if made { close() }
        }
    }
}

/// Board or List, as the header's switch shows them.
struct LayoutSwitch: View {
    @Binding var mode: ViewMode

    var body: some View {
        ViewModeSwitch(mode: $mode)
    }
}

/// Timeline, Board or List, for a view in GitHub's roadmap layout.
struct ShapeSwitch: View {
    @Binding var shape: ViewShape
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            segment(.timeline, .timeline)
            segment(.board, .board)
            segment(.list, .list)
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.control))
    }

    private func segment(_ title: LocalizedStringResource, _ value: ViewShape) -> some View {
        Button {
            withAnimation(Theme.spring) { shape = value }
        } label: {
            Text(title)
                .font(.smallMedium)
                .foregroundStyle(shape == value ? Theme.text : Theme.textSecondary)
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background {
                    if shape == value {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Theme.segmentActive)
                            .matchedGeometryEffect(id: "segment", in: namespace)
                    }
                }
        }
        .buttonStyle(PlainPressStyle())
    }
}

/// A field to pick from a menu, such as what a board's columns or a list's groups are by.
struct FieldMenu: View {
    var choices: [ProjectField]
    @Binding var selection: String?
    /// What no field means here, such as "Status"; nil when a field must be chosen.
    var noneTitle: String?
    var marked = false

    var body: some View {
        var options: [SelectDropdown.Option] = []
        if let noneTitle { options.append(.init(id: "", title: noneTitle)) }
        options += choices.map { .init(id: $0.id, title: $0.name) }
        return SelectDropdown(options: options, selected: selection ?? "", marked: marked) { id in
            selection = id.isEmpty ? nil : id
        }
    }
}

/// The order of a view: none (as placed on the board), or by a field, up or down.
struct SortMenu: View {
    @Environment(AppModel.self) private var model
    var projectId: String
    @Binding var sort: [ViewSort]
    var marked = false

    var body: some View {
        let first = sort.first
        HStack(spacing: 6) {
            SelectDropdown(
                options: [.init(id: "", title: String(localized: .manualOrder))]
                    + model.sortCandidates(projectId: projectId).map { .init(id: $0.id, title: $0.name) },
                selected: first?.fieldId ?? "", marked: marked
            ) { id in
                sort = id.isEmpty ? [] : [ViewSort(fieldId: id, descending: first?.descending ?? false)]
            }
            if let first {
                Button {
                    sort = [ViewSort(fieldId: first.fieldId, descending: !first.descending)] + sort.dropFirst()
                } label: {
                    Image(systemName: first.descending ? "arrow.down" : "arrow.up")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 24, height: 24)
                        .hoverFill()
                }
                .buttonStyle(PlainPressStyle())
                .help(Text(first.descending ? .descending : .ascending))
            }
        }
    }
}

/// A value to pick from a short list, which opens as the app's dropdowns do and closes on a pick.
struct SelectDropdown: View {
    struct Option: Identifiable, Equatable {
        var id: String
        var title: String
    }

    var options: [Option]
    var selected: String
    var marked = false
    var onPick: (String) -> Void
    @State private var open = false

    var body: some View {
        Button {
            open = true
        } label: {
            MenuLabel(title: options.first { $0.id == selected }?.title ?? "", marked: marked, open: open)
        }
        .buttonStyle(PlainPressStyle())
        .fixedSize()
        .dropdown(isPresented: $open) { close in
            SelectList(options: options, selected: selected) { id in
                onPick(id)
                close()
            }
        }
    }
}

private struct SelectList: View {
    var options: [SelectDropdown.Option]
    var selected: String
    var onPick: (String) -> Void
    @State private var active: Int?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                MenuRow(
                    title: option.title, checked: option.id == selected, active: active == index,
                    action: { onPick(option.id) },
                    onHover: { if $0 { active = index } else if active == index { active = nil } }
                )
            }
        }
        .padding(.vertical, 4)
        .frame(minWidth: 190)
        .font(.ui)
        .foregroundStyle(Theme.text)
        .background(MenuKeys(
            onMove: { active = menuStep(active, by: $0, count: options.count) },
            onActivate: { if let active, options.indices.contains(active) { onPick(options[active].id) } }
        ))
        .onAppear { active = options.firstIndex { $0.id == selected } }
    }
}

/// What a menu in a form shows: its value, with a quiet arrow; outlined when it differs from the view on GitHub.
struct MenuLabel: View {
    var title: String
    var marked = false
    var open = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title).lineLimit(1)
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(Theme.textTertiary)
        }
        .font(.small)
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 8)
        .frame(minWidth: 150, alignment: .leading)
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(open ? Theme.controlActive : Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(marked ? Theme.accent : Theme.chipBorder, lineWidth: marked ? 1.5 : 1))
        .contentShape(Rectangle())
    }
}

#endif
