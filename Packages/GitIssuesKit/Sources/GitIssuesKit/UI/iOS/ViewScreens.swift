#if os(iOS)
import SwiftUI

/// Over a project's list or board: its saved views as capsules, the open one filled, and under them the open view's
/// filter. Touch and hold a view for its menu. A wide iPad lists the views in its sidebar, so there only the filter
/// shows, and only when there is one.
struct ViewBar: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation
    @Environment(\.wideLayout) private var wide
    var projectId: String

    var body: some View {
        let current = model.currentView(projectId: projectId)
        let showsFilter = current.map { !model.filter(of: $0).isEmpty || model.filterChanged($0) } ?? false
        if !wide || showsFilter {
            bar(current: current)
        }
    }

    private func bar(current: ProjectView?) -> some View {
        let views = model.views(projectId: projectId)
        return VStack(alignment: .leading, spacing: 8) {
            if !wide {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(views) { view in
                                ViewPill(view: view, selected: view.id == current?.id)
                                    .id(view.id)
                            }
                            if model.canEditViews(projectId: projectId) {
                                Button {
                                    navigation.sheet = .newView(projectId: projectId, sourceViewId: current?.id, duplicate: false)
                                } label: {
                                    Image(systemName: "plus")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Theme.textSecondary)
                                        .frame(width: 32, height: 32)
                                        .background(Circle().fill(Theme.card))
                                        .overlay(Circle().strokeBorder(Theme.cardBorder, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(.newViewTooltip)
                                .accessibilityIdentifier("new-view")
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .scrollIndicators(.never)
                    .onAppear { if let current { proxy.scrollTo(current.id, anchor: .center) } }
                    .onChange(of: current?.id) { _, id in
                        if let id { withAnimation(Theme.spring) { proxy.scrollTo(id, anchor: .center) } }
                    }
                }
            }
            if let current {
                ViewFilterLine(view: current)
                // A view of one iteration says which, when, and how far it is, as Linear's cycles.
                if let pinned = model.pinnedIteration(of: current) {
                    CycleHeader(view: current, pinned: pinned, compact: !wide)
                        .padding(.horizontal, 16)
                }
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel)
    }
}

/// One saved view: a tap opens it.
private struct ViewPill: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation
    var view: ProjectView
    var selected: Bool

    var body: some View {
        Button {
            withAnimation(Theme.spring) { model.show(view) }
        } label: {
            HStack(spacing: 6) {
                ViewLayoutGlyph(view: view)
                Text(view.name).lineLimit(1)
                if model.filterChanged(view) {
                    Circle().fill(selected ? Theme.onColor : Theme.accent).frame(width: 6, height: 6)
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(selected ? Theme.onColor : Theme.text)
            .padding(.horizontal, 13)
            .frame(height: 32)
            .background(Capsule().fill(selected ? Theme.accentFill : Theme.card))
            .overlay(Capsule().strokeBorder(selected ? .clear : Theme.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(model.filterChanged(view) ? Text(.filterChangedSpoken) : Text(verbatim: ""))
        .accessibilityIdentifier("view-\(view.name)")
        .contextMenu { ViewMenuItems(view: view) }
    }
}

/// A view's layout as a small icon: a board, a list or a roadmap.
struct ViewLayoutGlyph: View {
    @Environment(AppModel.self) private var model
    var view: ProjectView

    var body: some View {
        Group {
            if view.layout == .roadmap, model.display(of: view).layout == nil {
                RoadmapIcon(size: 12)
            } else {
                Image(systemName: model.layout(of: view) == .board ? "rectangle.split.3x1" : "list.bullet")
                    .font(.system(size: 11, weight: .semibold))
            }
        }
        .accessibilityHidden(true)
    }
}

/// What a view's menu offers: its filter, renaming, a copy, GitHub, deleting.
struct ViewMenuItems: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation
    var view: ProjectView

    var body: some View {
        let canEdit = model.canEditViews(projectId: view.projectId)
        Button {
            model.show(view)
            navigation.sheet = .viewFilter(view.id)
        } label: {
            Label(.filterEllipsis, systemImage: "line.3.horizontal.decrease")
        }
        if canEdit {
            Button {
                navigation.renamingView = view.id
            } label: {
                Label(.rename, systemImage: "pencil")
            }
            Button {
                navigation.sheet = .newView(projectId: view.projectId, sourceViewId: view.id, duplicate: true)
            } label: {
                Label(.duplicateView, systemImage: "plus.square.on.square")
            }
        }
        if let project = model.project(of: view), let url = view.url(projectURL: project.url) {
            Button {
                Platform.open(url)
            } label: {
                Label(.openOnGitHub, systemImage: "arrow.up.right.square")
            }
        }
        if canEdit, model.views(projectId: view.projectId).count > 1 {
            Divider()
            Button(role: .destructive) {
                navigation.deletingView = view.id
            } label: {
                Label(.deleteViewEllipsis, systemImage: "trash")
            }
        }
    }
}

/// The open view's filter as a line of small chips; a tap edits it. While it is changed here, Save writes it to
/// GitHub.
private struct ViewFilterLine: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation
    var view: ProjectView

    var body: some View {
        let filter = model.filter(of: view)
        let changed = model.filterChanged(view)
        if !filter.isEmpty || changed {
            HStack(spacing: 8) {
                FilterChipStrip(filter: filter, scope: .project(view.projectId), identifier: "view-filter") {
                    navigation.sheet = .viewFilter(view.id)
                }
                if changed, model.canEditViews(projectId: view.projectId) {
                    Button {
                        model.saveFilter(of: view)
                    } label: {
                        if model.savingViewIds.contains(view.id) {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(.saveButton).font(.footnote.weight(.semibold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .disabled(!model.canReachGitHub)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

/// A filter as a line of small chips that fades out at its end, as a row's chips do. The whole line is one button,
/// which opens the filter to change it.
struct FilterChipStrip: View {
    @Environment(AppModel.self) private var model
    var filter: ProjectFilter
    var scope: FilterScope
    var identifier = "filter"
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if filter.isEmpty {
                    Text(.filter).foregroundStyle(Theme.textTertiary)
                }
                ForEach(Array(filter.terms.enumerated()), id: \.offset) { _, term in
                    let chip = model.chip(for: term, in: scope)
                    HStack(spacing: 5) {
                        FilterGlyph(icon: chip.icon)
                        if chip.isRaw {
                            Text(chip.property).font(.caption.monospaced())
                        } else if let values = chip.values {
                            Text(Self.text(of: chip, values: values)).foregroundStyle(Theme.text)
                        } else {
                            Text("\(chip.property) \(chip.comparison ?? "")").foregroundStyle(Theme.text)
                        }
                    }
                    .font(.footnote)
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.groupHeader))
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .clipped()
            .mask(LinearGradient(stops: [.init(color: .black, location: 0.88), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(.filter)
        .accessibilityValue(Text(verbatim: filter.terms.map { Self.spoken(model.chip(for: $0, in: scope)) }.joined(separator: ", ")))
        .accessibilityIdentifier(identifier)
    }

    /// A chip's words in the short line. One value or any of several reads as the values alone, as the icon says
    /// what they are of; the project's own fields, whose values don't (an iteration's "Current"), add their name.
    /// Anything else, such as "is not", needs the whole phrase.
    static func text(of chip: FilterChipModel, values: String) -> String {
        guard [String(localized: .filterIs), String(localized: .filterIsAnyOf)].contains(chip.comparison) else {
            return [chip.property, chip.comparison, values].compactMap { $0 }.joined(separator: " ")
        }
        return chip.namedWithValues ? String(localized: .fieldValueSpoken(field: chip.property, value: values)) : values
    }

    /// A chip as VoiceOver reads it, in full: "Label is any of bug, sync".
    static func spoken(_ chip: FilterChipModel) -> String {
        [chip.property, chip.comparison, chip.values].compactMap { $0 }.joined(separator: " ")
    }
}

/// The icon of a filter property or value, sized for iPhone and iPad.
struct FilterGlyph: View {
    var icon: FilterIcon

    var body: some View {
        Group {
            switch icon {
            case .status(let glyph): StatusIcon(glyph: glyph, size: 13)
            case .symbol(let name): Image(systemName: name).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textSecondary)
            case .person(let person): Avatar(login: person.login, url: person.avatarUrl, size: 16)
            case .label(let color): Circle().fill(Theme.labelColor(color)).frame(width: 8, height: 8)
            case .milestone(let mark): MilestoneIcon(mark: mark, size: 12)
            case .dot(let color): GroupIcon(icon: .dot(color), size: 13)
            case .iteration(let current): IterationIcon(size: 13).foregroundStyle(current ? Theme.started : Theme.textSecondary)
            case .priority(let level): PriorityIcon(level: level)
            case .project(let look): ProjectGlyphImage(look: look, size: 14)
            case .none: EmptyView()
            }
        }
        // The name beside it says what it is; a priority's icon would otherwise read "High priority" before "Priority".
        .accessibilityHidden(true)
    }
}

// MARK: - Editing a filter

/// A view's filter, term by term. Changes show at once and stay on this device until saved to GitHub.
struct ViewFilterSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var viewId: String

    var body: some View {
        NavigationStack {
            if let view = model.view(id: viewId) {
                let changed = model.filterChanged(view)
                FilterTermsForm(
                    filter: Binding(get: { model.filter(of: view) }, set: { model.setFilter($0, of: view) }),
                    scope: .project(view.projectId)
                ) {
                    if changed {
                        Section {
                            if model.canEditViews(projectId: view.projectId) {
                                Button {
                                    model.saveFilter(of: view)
                                    dismiss()
                                } label: {
                                    Label(.saveForEveryone, systemImage: "square.and.arrow.down")
                                }
                                .disabled(!model.canReachGitHub)
                            }
                            Button(role: .destructive) {
                                model.resetFilter(of: view)
                            } label: {
                                Label(.reset, systemImage: "arrow.uturn.backward")
                            }
                        } footer: {
                            Text(model.canEditViews(projectId: view.projectId) ? (model.canReachGitHub ? .viewSaveFooter : .needsConnection) : .filterOnlyForYou)
                        }
                    }
                }
                .navigationTitle(view.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(.done) { dismiss() }
                    }
                }
            }
        }
    }
}

/// The terms of a filter as rows, a row to add one, and what the screen adds below.
struct FilterTermsForm<Footer: View>: View {
    @Environment(AppModel.self) private var model
    @Binding var filter: ProjectFilter
    var scope: FilterScope
    @ViewBuilder var footer: Footer

    var body: some View {
        Form {
            Section {
                ForEach(Array(filter.terms.enumerated()), id: \.offset) { index, term in
                    let chip = model.chip(for: term, in: scope)
                    NavigationLink {
                        FilterTermScreen(filter: $filter, scope: scope, index: index)
                    } label: {
                        HStack(spacing: 10) {
                            FilterGlyph(icon: chip.icon).frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(chip.isRaw ? chip.property : chip.property)
                                    .font(chip.isRaw ? .callout.monospaced() : .body)
                                if let comparison = chip.comparison {
                                    Text([comparison, chip.values].compactMap { $0 }.joined(separator: " "))
                                        .font(.footnote)
                                        .foregroundStyle(Theme.textSecondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                    .disabled(chip.isRaw)
                }
                .onDelete { offsets in
                    for index in offsets.sorted(by: >) { filter = filter.removing(index) }
                }
                NavigationLink {
                    FilterPropertyScreen(filter: $filter, scope: scope)
                } label: {
                    Label(.addFilter, systemImage: "plus")
                        .foregroundStyle(Theme.accent)
                }
            }
            footer
        }
    }
}

/// What to filter by, to pick before its values.
private struct FilterPropertyScreen: View {
    @Environment(AppModel.self) private var model
    @Binding var filter: ProjectFilter
    var scope: FilterScope

    var body: some View {
        List(model.filterProperties(scope)) { property in
            NavigationLink {
                FilterValuesScreen(filter: $filter, scope: scope, property: property, termIndex: nil)
            } label: {
                HStack(spacing: 10) {
                    FilterGlyph(icon: property.icon).frame(width: 20)
                    Text(property.title)
                }
            }
        }
        .navigationTitle(.addFilter)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One term: whether it is turned around, and its values.
private struct FilterTermScreen: View {
    @Environment(AppModel.self) private var model
    @Binding var filter: ProjectFilter
    var scope: FilterScope
    var index: Int

    var body: some View {
        if filter.terms.indices.contains(index), let property = property(of: filter.terms[index]) {
            FilterValuesScreen(filter: $filter, scope: scope, property: property, termIndex: index)
        } else {
            EmptyView()
        }
    }

    private func property(of term: ProjectFilter.Term) -> FilterProperty? {
        let key = term.key == "assignees" ? "assignee" : term.key == "labels" ? "label" : term.key
        if key == "has" || key == "no" {
            return model.filterProperties(scope).first { $0.id == term.values.first?.lowercased() }
        }
        return model.filterProperties(scope).first { $0.id == key }
    }
}

/// The values of a property, checked when the filter has them. A tap adds or takes one away; with several, any of
/// them is enough. "Not" turns the term around.
private struct FilterValuesScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Binding var filter: ProjectFilter
    var scope: FilterScope
    var property: FilterProperty
    var termIndex: Int?
    @State private var query = ""

    var body: some View {
        let values = model.filterValues(property, in: scope)
        let index = termIndex ?? model.termIndex(for: property, in: filter)
        let term = index.flatMap { filter.terms.indices.contains($0) ? filter.terms[$0] : nil }
        let picked = term.map(model.pickedValues) ?? []
        let shown = query.isEmpty ? values : values.filter { fuzzyScore(query, $0.title) != nil || ($0.subtitle.flatMap { fuzzyScore(query, $0) } != nil) }
        List {
            if let term, let index, term.key != "has", term.key != "no" {
                Section {
                    Toggle(isOn: Binding(
                        get: { term.negated },
                        set: { negated in filter = filter.replacing(index, with: term.changed { $0.negated = negated }) }
                    )) {
                        Text(.filterIsNot)
                    }
                }
            }
            Section {
                ForEach(shown) { value in
                    Button {
                        let wasNew = term == nil
                        filter = model.toggling(value, in: filter, termIndex: model.termIndex(for: property, in: filter) ?? index)
                        // A property that takes one value is done with its pick.
                        if wasNew, !property.takesSeveral { dismiss() }
                    } label: {
                        HStack(spacing: 10) {
                            FilterGlyph(icon: value.icon).frame(width: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(value.title).foregroundStyle(Theme.text)
                                if let subtitle = value.subtitle {
                                    Text(subtitle).font(.footnote).foregroundStyle(Theme.textSecondary)
                                }
                            }
                            Spacer(minLength: 8)
                            Text("\(value.count)").font(.footnote).monospacedDigit().foregroundStyle(Theme.textTertiary)
                            Image(systemName: "checkmark")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                                .opacity(picked.contains(value.id) || picked.contains("\(value.key):\(value.value.lowercased())") ? 1 : 0)
                        }
                    }
                }
            }
        }
        .searchable(text: $query)
        .navigationTitle(property.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - A new view

/// Makes a new view, starting from the one open or the one being duplicated.
struct NewViewSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var projectId: String
    var sourceViewId: String?
    var duplicate: Bool

    @State private var template: ProjectView?
    @State private var filter = ProjectFilter("")
    @State private var layout: ViewMode = .board
    @State private var creating = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            if let binding = templateBinding {
                FilterTermsForm(filter: $filter, scope: .project(projectId)) {
                    Section {
                        Picker(.layout, selection: $layout) {
                            Label(.board, systemImage: "rectangle.split.3x1").tag(ViewMode.board)
                            Label(.list, systemImage: "list.bullet").tag(ViewMode.list)
                        }
                        if layout == .board {
                            Picker(.columns, selection: binding.columnFieldId) {
                                ForEach(model.columnChoices(projectId: projectId)) { Text($0.name).tag(Optional($0.id)) }
                            }
                        } else {
                            Picker(.groupBy, selection: binding.groupByFieldId) {
                                Text(model.statusFieldTitle(projectId: projectId)).tag(String?.none)
                                ForEach(model.groupChoices(projectId: projectId)) { Text($0.name).tag(Optional($0.id)) }
                            }
                        }
                        Picker(.orderBy, selection: Binding(
                            get: { template?.sortBy.first?.fieldId },
                            set: { id in template?.sortBy = id.map { [ViewSort(fieldId: $0, descending: false)] } ?? [] }
                        )) {
                            Text(.manualOrder).tag(String?.none)
                            ForEach(model.sortCandidates(projectId: projectId)) { Text($0.name).tag(Optional($0.id)) }
                        }
                    } footer: {
                        Text(.groupingFixedHint)
                    }
                }
                .safeAreaInset(edge: .top) {
                    TextField(.viewNamePlaceholder, text: binding.name)
                        .font(.title3.weight(.semibold))
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Theme.panel)
                }
                .navigationTitle(.newViewTooltip)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(.cancel) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: create) {
                            if creating { ProgressView() } else { Text(.create) }
                        }
                        .disabled(binding.wrappedValue.name.trimmingCharacters(in: .whitespaces).isEmpty || creating || !model.canReachGitHub)
                    }
                }
            }
        }
        .onAppear {
            guard template == nil else { return }
            let source = model.view(id: sourceViewId)
            var start = model.template(from: source, projectId: projectId, name: duplicate ? String(localized: .viewCopyName(view: source?.name ?? "")) : "")
            if start.columnFieldId == nil { start.columnFieldId = model.currentStatusFieldId(projectId: projectId) }
            template = start
            filter = ProjectFilter(start.filter)
            layout = start.layout == .board ? .board : .list
            nameFocused = true
        }
    }

    private var templateBinding: Binding<ProjectView>? {
        guard template != nil else { return nil }
        return Binding(get: { template! }, set: { template = $0 })
    }

    private func create() {
        guard var view = template else { return }
        view.name = view.name.trimmingCharacters(in: .whitespaces)
        view.filter = filter.text
        if layout == .board {
            view.layout = .board
            view.groupByFieldId = nil
        } else {
            view.layout = view.layout == .roadmap ? .roadmap : .table
            view.columnFieldId = nil
        }
        creating = true
        Task {
            let made = await model.createView(view)
            creating = false
            if made { dismiss() }
        }
    }
}

// MARK: - Display and the view's menu

/// The Display part of a project's menu: board or list on a wide iPad, columns, groups, order and the fields shown.
struct ViewDisplayMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.wideLayout) private var wide
    var view: ProjectView

    var body: some View {
        Menu {
            if wide {
                if view.layout == .roadmap {
                    Picker(.layout, selection: Binding(get: { model.shape(of: view) }, set: { model.setShape($0, of: view) })) {
                        Label(.timeline, systemImage: "chart.bar.xaxis").tag(ViewShape.timeline)
                        Label(.board, systemImage: "rectangle.split.3x1").tag(ViewShape.board)
                        Label(.list, systemImage: "list.bullet").tag(ViewShape.list)
                    }
                } else {
                    Picker(.layout, selection: Binding(get: { model.layout(of: view) }, set: { model.showLayout($0, projectId: view.projectId) })) {
                        Label(.board, systemImage: "rectangle.split.3x1").tag(ViewMode.board)
                        Label(.list, systemImage: "list.bullet").tag(ViewMode.list)
                    }
                }
            }
            if wide, model.layout(of: view) == .board {
                Picker(.columns, selection: Binding(get: { model.columnField(of: view)?.id }, set: { model.setColumnField($0, of: view) })) {
                    ForEach(model.columnChoices(projectId: view.projectId)) { Text($0.name).tag(Optional($0.id)) }
                }
                .pickerStyle(.menu)
            } else {
                let status = model.currentStatusFieldId(projectId: view.projectId)
                Picker(.groupBy, selection: Binding(
                    get: { model.groupField(of: view).flatMap { $0.id == status ? nil : $0.id } },
                    set: { model.setGroupField($0 ?? status, of: view) }
                )) {
                    Text(model.statusFieldTitle(projectId: view.projectId)).tag(String?.none)
                    ForEach(model.groupChoices(projectId: view.projectId)) { Text($0.name).tag(Optional($0.id)) }
                }
                .pickerStyle(.menu)
            }
            Picker(.orderBy, selection: Binding(
                get: { model.sort(of: view).first?.fieldId },
                set: { id in model.setSort(id.map { [ViewSort(fieldId: $0, descending: model.sort(of: view).first?.descending ?? false)] } ?? [], of: view) }
            )) {
                Text(.manualOrder).tag(String?.none)
                ForEach(model.sortCandidates(projectId: view.projectId)) { Text($0.name).tag(Optional($0.id)) }
            }
            .pickerStyle(.menu)
            if let first = model.sort(of: view).first {
                Button {
                    model.setSort([ViewSort(fieldId: first.fieldId, descending: !first.descending)], of: view)
                } label: {
                    Label(first.descending ? .descending : .ascending, systemImage: first.descending ? "arrow.down" : "arrow.up")
                }
            }
            let candidates = model.chipCandidates(projectId: view.projectId)
            if !candidates.isEmpty {
                Section(String(localized: .properties)) {
                    let shown = Set(model.shownFieldIds(of: view))
                    ForEach(candidates) { field in
                        Toggle(field.name, isOn: Binding(get: { shown.contains(field.id) }, set: { _ in model.toggleChip(field.id, of: view) }))
                    }
                }
            }
            if model.displayDiffers(view) {
                Section {
                    if model.displayCanBeSaved(view) {
                        Button {
                            model.saveDisplay(of: view)
                        } label: {
                            Label(.saveForEveryone, systemImage: "square.and.arrow.down")
                        }
                        .disabled(!model.canReachGitHub)
                    }
                    Button(role: .destructive) {
                        model.resetDisplay(of: view)
                    } label: {
                        Label(.reset, systemImage: "arrow.uturn.backward")
                    }
                }
            }
        } label: {
            Label(.display, systemImage: "slider.horizontal.3")
        }
    }
}

/// Renaming a view and deleting one, as alerts over the project.
struct ViewAlerts: ViewModifier {
    @Environment(AppModel.self) private var model
    @Bindable var navigation: MobileNavigation
    @State private var name = ""

    func body(content: Content) -> some View {
        let renaming = navigation.renamingView.flatMap { model.view(id: $0) }
        let deleting = navigation.deletingView.flatMap { model.view(id: $0) }
        content
            .alert(Text(.rename), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { navigation.renamingView = nil } })) {
                TextField(.viewNamePlaceholder, text: $name)
                Button(.cancel, role: .cancel) {}
                Button(.saveButton) { if let renaming { model.rename(renaming, to: name) } }
            }
            .onChange(of: navigation.renamingView) { _, id in name = id.flatMap { model.view(id: $0)?.name } ?? "" }
            .alert(
                Text(deleting.map { .deleteViewQuestion(view: $0.name) } ?? .deleteViewEllipsis),
                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { navigation.deletingView = nil } })
            ) {
                Button(.deleteView, role: .destructive) { if let deleting { model.delete(deleting) } }
                Button(.cancel, role: .cancel) {}
            } message: {
                Text(.deleteViewMessage(project: deleting.flatMap { model.project(of: $0)?.title } ?? ""))
            }
    }
}
#endif
