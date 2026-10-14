#if os(macOS)
import SwiftUI

/// Under a view's header: its filter as chips, a button to add one, and while the filter is changed here, Reset and
/// Save. Without a filter there is nothing to show, and the bar isn't there.
struct FilterBar: View {
    @Environment(AppModel.self) private var model
    var view: ProjectView

    var body: some View {
        let changed = model.filterChanged(view)
        if !model.filter(of: view).isEmpty || changed {
            HStack(spacing: 6) {
                FilterChipsRow(
                    filter: Binding(get: { model.filter(of: view) }, set: { model.setFilter($0, of: view) }),
                    projectId: view.projectId
                )
                Spacer(minLength: 8)
                if changed {
                    Button(.reset) { model.resetFilter(of: view) }
                        .buttonStyle(QuietButtonStyle())
                        .help(Text(.resetFilterTooltip))
                    if model.canEditViews(projectId: view.projectId) {
                        Button {
                            model.saveFilter(of: view)
                        } label: {
                            HStack(spacing: 6) {
                                if model.savingViewIds.contains(view.id) { ProgressView().controlSize(.mini) }
                                Text(.saveButton)
                                Text("⌘S").opacity(0.7)
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!model.canReachGitHub || model.savingViewIds.contains(view.id))
                        .help(Text(model.canReachGitHub ? .saveViewTooltip : .needsConnection))
                    } else {
                        Text(.filterOnlyForYou)
                            .font(.small)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .frame(height: 40)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.panelBorder).frame(height: 1)
            }
            .transition(.opacity)
        }
    }
}

/// A quiet text button, such as Reset next to Save.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.small)
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .hoverFill()
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }
}

/// A filter's terms as chips, and a button to add one. Used under a view's header and in the new-view form.
struct FilterChipsRow: View {
    @Environment(AppModel.self) private var model
    @Binding var filter: ProjectFilter
    var projectId: String
    /// In a form the chips wrap onto more lines; in the bar they stay on one and scroll.
    var wraps = false
    @State private var adding = false

    var body: some View {
        let chips = Group {
            ForEach(Array(filter.terms.enumerated()), id: \.offset) { index, term in
                FilterChipView(filter: $filter, index: index, term: term, projectId: projectId)
            }
            Button {
                adding = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus").font(.system(size: 9, weight: .semibold))
                    Text(.filter)
                }
                .font(.small)
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .hoverFill(active: adding)
            }
            .buttonStyle(PlainPressStyle())
            .help(Text(.filterTooltip))
            .dropdown(isPresented: $adding) { close in
                FilterMenu(filter: $filter, projectId: projectId, close: close)
            }
        }
        if wraps {
            FlowLayout(spacing: 6) { chips }
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 6) { chips }
            }
            .scrollIndicators(.never)
        }
    }
}

/// One term as a chip: the property, how it compares (click to turn it around), its values (click to change them)
/// and a cross that takes it away.
struct FilterChipView: View {
    @Environment(AppModel.self) private var model
    @Binding var filter: ProjectFilter
    var index: Int
    var term: ProjectFilter.Term
    var projectId: String
    @State private var picking = false

    var body: some View {
        let chip = model.chip(for: term, projectId: projectId)
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                if !chip.isRaw { FilterIconView(icon: chip.icon, size: 11) }
                Text(chip.property)
                    .font(chip.isRaw ? .system(size: 11, design: .monospaced) : .small)
                    .foregroundStyle(chip.isRaw ? Theme.textSecondary : Theme.text)
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            if let comparison = chip.comparison {
                divider
                Button {
                    guard chip.negatable else { return }
                    filter = filter.replacing(index, with: term.changed { $0.negated.toggle() })
                } label: {
                    Text(comparison)
                        .font(.small)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 7)
                        .frame(maxHeight: .infinity)
                        .hoverFill(radius: 0)
                }
                .buttonStyle(PlainPressStyle())
                .disabled(!chip.negatable)
                .help(Text(.flipComparisonTooltip))
            }
            if let values = chip.values {
                divider
                Button {
                    if chip.picksValues { picking = true }
                } label: {
                    Text(values)
                        .font(.small)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .frame(maxHeight: .infinity)
                        .hoverFill(active: picking, radius: 0)
                }
                .buttonStyle(PlainPressStyle())
                .dropdown(isPresented: $picking) { close in
                    FilterValueList(filter: $filter, projectId: projectId, property: property(for: term), termIndex: index, close: close)
                }
            }
            divider
            Button {
                filter = filter.removing(index)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 22)
                    .frame(maxHeight: .infinity)
                    .hoverFill(radius: 0)
            }
            .buttonStyle(PlainPressStyle())
            .help(Text(.removeFilterTooltip))
        }
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.card))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Theme.chipBorder, lineWidth: 1))
        .fixedSize()
    }

    private var divider: some View {
        Rectangle().fill(Theme.chipBorder).frame(width: 1)
    }

    private func property(for term: ProjectFilter.Term) -> FilterProperty? {
        let key = term.key == "assignees" ? "assignee" : term.key == "labels" ? "label" : term.key
        return model.filterProperties(projectId: projectId).first { $0.id == key }
    }
}

/// The icon of a filter property or value.
struct FilterIconView: View {
    var icon: FilterIcon
    var size: CGFloat = 13

    var body: some View {
        switch icon {
        case .status(let glyph): StatusIcon(glyph: glyph, size: size + 1)
        case .symbol(let name):
            Image(systemName: name).font(.system(size: size - 1, weight: .medium)).foregroundStyle(Theme.textSecondary)
                .frame(width: size + 2, height: size + 2)
        case .person(let person): Avatar(login: person.login, url: person.avatarUrl, size: size + 3)
        case .label(let color):
            Circle().fill(Theme.labelColor(color)).frame(width: size * 0.62, height: size * 0.62).frame(width: size + 2, height: size + 2)
        case .milestone(let mark): MilestoneIcon(mark: mark, size: size)
        case .dot(let color): GroupIcon(icon: .dot(color), size: size + 1)
        case .iteration(let current): IterationIcon(size: size + 1).foregroundStyle(current ? Theme.started : Theme.textSecondary)
        case .priority(let level): PriorityIcon(level: level).scaleEffect(size / 14)
        case .none: EmptyView()
        }
    }
}

/// What a filter can be by, then its values: type to find a property or a value straight away.
struct FilterMenu: View {
    @Environment(AppModel.self) private var model
    @Binding var filter: ProjectFilter
    var projectId: String
    var close: () -> Void

    @State private var property: FilterProperty?
    @State private var editingText = false

    var body: some View {
        if editingText {
            FilterTextEditor(filter: $filter, close: close)
        } else if let property {
            FilterValueList(filter: $filter, projectId: projectId, property: property, termIndex: model.termIndex(for: property, in: filter), close: close)
        } else {
            let properties = model.filterProperties(projectId: projectId)
            PickerList(
                placeholder: String(localized: .filterEllipsis),
                items: properties.map { property in
                    PickerItem(id: "property:\(property.id)", title: property.title, icon: AnyView(FilterIconView(icon: property.icon)),
                               trailing: AnyView(Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.textTertiary)))
                } + [PickerItem(id: "text", title: String(localized: .editFilterAsText), icon: AnyView(FilterIconView(icon: .symbol("chevron.left.forwardslash.chevron.right"))), alwaysShown: true)],
                hint: "F",
                width: 280,
                search: { query in
                    let matchingProperties = properties.filter { fuzzyScore(query, $0.title) != nil }.map { property in
                        PickerItem(id: "property:\(property.id)", title: property.title, icon: AnyView(FilterIconView(icon: property.icon)))
                    }
                    let values = model.allFilterValues(projectId: projectId).compactMap { entry -> (PickerItem, Int)? in
                        guard let score = fuzzyScore(query, entry.value.title) ?? entry.value.subtitle.flatMap({ fuzzyScore(query, $0) }) else { return nil }
                        return (PickerItem(
                            id: "value:\(entry.value.id)", title: entry.value.title, subtitle: entry.property.title,
                            icon: AnyView(FilterIconView(icon: entry.value.icon)),
                            trailing: AnyView(Text("\(entry.value.count)").font(.small).monospacedDigit().foregroundStyle(Theme.textTertiary))
                        ), score)
                    }
                    .sorted { $0.1 > $1.1 }
                    .prefix(30)
                    .map(\.0)
                    return matchingProperties + values
                },
                onPick: { id in
                    if id == "text" {
                        editingText = true
                    } else if id.hasPrefix("property:") {
                        property = properties.first { "property:\($0.id)" == id }
                    } else if id.hasPrefix("value:"), let entry = model.allFilterValues(projectId: projectId).first(where: { "value:\($0.value.id)" == id }) {
                        filter = model.toggling(entry.value, in: filter, termIndex: model.termIndex(for: entry.property, in: filter))
                        close()
                    }
                },
                onClose: {
                    // Picking a property or the text goes on to its next step instead.
                    if property == nil, !editingText { close() }
                }
            )
            .onAppear {
                if let start = model.filterMenuStart {
                    model.filterMenuStart = nil
                    property = properties.first { $0.id == start }
                }
            }
        }
    }
}

/// The values of one property, with how many issues each finds. A click picks one and closes; the box at the start
/// of a row, or Shift, picks more ("is any of").
struct FilterValueList: View {
    @Environment(AppModel.self) private var model
    @Binding var filter: ProjectFilter
    var projectId: String
    var property: FilterProperty?
    var termIndex: Int?
    var close: () -> Void

    var body: some View {
        if let property {
            let values = model.filterValues(property, projectId: projectId)
            let picked = termIndex.flatMap { filter.terms.indices.contains($0) ? model.pickedValues(filter.terms[$0]) : nil } ?? []
            PickerList(
                placeholder: property.title,
                items: values.map { value in
                    PickerItem(
                        id: value.id, title: value.title, subtitle: value.subtitle,
                        selected: picked.contains(value.id) || picked.contains("\(value.key):\(value.value.lowercased())"),
                        icon: AnyView(FilterIconView(icon: value.icon)),
                        trailing: AnyView(Text("\(value.count)").font(.small).monospacedDigit().foregroundStyle(Theme.textTertiary))
                    )
                },
                multiple: property.takesSeveral,
                width: 300,
                opensOnSelection: false,
                onPick: { id in
                    guard let value = values.first(where: { $0.id == id }) else { return }
                    // The term this property writes into, as it is now: picking may have made or taken one away.
                    let index = model.termIndex(for: property, in: filter)
                        ?? (value.key == "no" || value.key == "has" ? filter.terms.firstIndex { $0.key == value.key && $0.values.contains(value.value) } : nil)
                    filter = model.toggling(value, in: filter, termIndex: index)
                },
                onClose: close
            )
        }
    }
}

/// The filter in GitHub's own words, for those who know them: `label:bug is:open -status:Done`.
struct FilterTextEditor: View {
    @Binding var filter: ProjectFilter
    var close: () -> Void
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(.filterTextPlaceholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .focusOnAppear()
                .onSubmit {
                    filter = ProjectFilter(text)
                    close()
                }
            Text(.filterTextHint)
                .font(.tiny)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(width: 380)
        .onAppear { text = filter.text }
    }
}

/// Lays its children out in rows, starting a new row when one is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var line: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += line + spacing
                x = 0
                line = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            line = max(line, size.height)
        }
        return CGSize(width: min(widest, width), height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var line: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += line + spacing
                x = bounds.minX
                line = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}

// MARK: - The header's buttons

/// The header's filter button: adds a filter to the view open (F).
struct HeaderFilterButton: View {
    @Environment(AppModel.self) private var model
    var view: ProjectView
    @State private var open = false

    var body: some View {
        Button {
            open = true
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 28, height: 26)
                .hoverFill(active: open)
        }
        .buttonStyle(PlainPressStyle())
        .help(Text(.filterTooltip))
        .accessibilityLabel(.filter)
        .dropdown(isPresented: $open) { close in
            FilterMenu(
                filter: Binding(get: { model.filter(of: view) }, set: { model.setFilter($0, of: view) }),
                projectId: view.projectId, close: close
            )
        }
        .onChange(of: model.filterMenuRequest) { open = true }
    }
}

/// The header's Display button: board or list, columns, grouping, order and the fields shown (⇧V).
struct DisplayButton: View {
    @Environment(AppModel.self) private var model
    var view: ProjectView
    @State private var open = false

    var body: some View {
        Button {
            open = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3").font(.system(size: 11, weight: .medium))
                Text(.display)
                if model.displayDiffers(view) {
                    Circle().fill(Theme.accent).frame(width: 5, height: 5)
                }
            }
            .font(.smallMedium)
            .foregroundStyle(Theme.textBody)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(open ? Theme.controlActive : .clear))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Theme.keycapBorder, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainPressStyle())
        .help(Text(.displayTooltip))
        .dropdown(isPresented: $open) { close in
            DisplayOptions(view: view, close: close)
        }
        .onChange(of: model.displayMenuRequest) { open = true }
    }
}

/// How you see a view: board or list, the columns of a board, the groups and order of a list, and the fields cards
/// and rows show. Changes are yours; Save for Everyone writes what GitHub takes to the view.
struct DisplayOptions: View {
    @Environment(AppModel.self) private var model
    var view: ProjectView
    var close: () -> Void

    var body: some View {
        let view = model.view(id: self.view.id) ?? self.view
        let display = model.display(of: view)
        let mode = model.layout(of: view)
        VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text(.layout).foregroundStyle(Theme.textSecondary)
                    if view.layout == .roadmap {
                        ShapeSwitch(shape: Binding(get: { model.shape(of: view) }, set: { model.setShape($0, of: view) }))
                    } else {
                        LayoutSwitch(mode: Binding(get: { mode }, set: { model.viewMode = $0 }))
                    }
                }
                if mode == .board {
                    GridRow {
                        Text(.columns).foregroundStyle(Theme.textSecondary)
                        FieldMenu(
                            choices: model.columnChoices(projectId: view.projectId),
                            selection: Binding(get: { model.columnField(of: view)?.id }, set: { model.setColumnField($0, of: view) }),
                            noneTitle: nil, marked: display.columnFieldId != nil
                        )
                    }
                } else {
                    GridRow {
                        Text(.groupBy).foregroundStyle(Theme.textSecondary)
                        FieldMenu(
                            choices: model.groupChoices(projectId: view.projectId),
                            selection: Binding(
                                get: { model.groupField(of: view).flatMap { $0.id == model.currentStatusFieldId(projectId: view.projectId) ? nil : $0.id } },
                                set: { model.setGroupField($0 ?? model.currentStatusFieldId(projectId: view.projectId), of: view) }
                            ),
                            noneTitle: model.statusFieldTitle(projectId: view.projectId), marked: display.groupFieldId != nil
                        )
                    }
                }
                GridRow {
                    Text(.orderBy).foregroundStyle(Theme.textSecondary)
                    SortMenu(
                        projectId: view.projectId,
                        sort: Binding(get: { model.sort(of: view) }, set: { model.setSort($0, of: view) }),
                        marked: display.sort != nil
                    )
                }
            }
            .font(.small)
            let candidates = model.chipCandidates(projectId: view.projectId)
            if !candidates.isEmpty {
                Rectangle().fill(Theme.popoverBorder).frame(height: 1).padding(.horizontal, -14)
                VStack(alignment: .leading, spacing: 8) {
                    Text(.properties).font(.small).foregroundStyle(Theme.textSecondary)
                    FlowLayout(spacing: 5) {
                        let shown = Set(model.shownFieldIds(of: view))
                        ForEach(candidates) { field in
                            let on = shown.contains(field.id)
                            Button {
                                model.toggleChip(field.id, of: view)
                            } label: {
                                Text(field.name)
                                    .font(.small)
                                    .foregroundStyle(on ? Theme.text : Theme.textTertiary)
                                    .padding(.horizontal, 9)
                                    .frame(height: 22)
                                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(on ? Theme.selectionFill : .clear))
                                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(on ? Theme.selectionBorder.opacity(0.6) : Theme.chipBorder, lineWidth: 1))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainPressStyle())
                        }
                    }
                }
            }
            if model.displayDiffers(view) {
                Rectangle().fill(Theme.popoverBorder).frame(height: 1).padding(.horizontal, -14)
                HStack(spacing: 8) {
                    Text(.changedForYou).font(.small).foregroundStyle(Theme.textTertiary)
                    Spacer(minLength: 8)
                    Button(.reset) { model.resetDisplay(of: view) }
                        .buttonStyle(QuietButtonStyle())
                    if model.displayCanBeSaved(view) {
                        Button {
                            model.saveDisplay(of: view)
                        } label: {
                            HStack(spacing: 6) {
                                if model.savingViewIds.contains(view.id) { ProgressView().controlSize(.mini) }
                                Text(.saveForEveryone)
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(!model.canReachGitHub || model.savingViewIds.contains(view.id))
                        .help(Text(model.canReachGitHub ? .saveForEveryoneTooltip : .needsConnection))
                    }
                }
                if model.displayStaysYours(view) {
                    Text(.displayStaysYoursHint)
                        .font(.tiny)
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(width: 340)
        .font(.ui)
        .foregroundStyle(Theme.text)
        .background(MenuKeys(onMove: { _ in }, onActivate: {}, onBack: close))
    }
}
#endif
