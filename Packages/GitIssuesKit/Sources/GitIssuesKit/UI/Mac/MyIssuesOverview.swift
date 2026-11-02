#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

/// My Issues as an overview: a widget per project with what you are doing there and what comes next, and widgets that
/// look across every project, on the board's grey. A large project widget is a lane, In progress, Up next and Later
/// side by side, so large ones read down a column for what you are doing everywhere; medium ones stack them, small ones
/// count. Drag a widget by its header to put it elsewhere; its menu changes its size or takes it out, and Edit Widgets
/// does all of it at once. Issues dragged from Up next to In progress start, and back.
struct MyIssuesOverview: View {
    @Environment(AppModel.self) private var model
    @State private var drag = OverviewDrag()

    var body: some View {
        if model.mineLanes.isEmpty, !model.editingOverview {
            emptyState
        } else {
            GeometryReader { geometry in
                grid(width: geometry.size.width)
            }
            .environment(drag)
            // A click beside the issues lets the picked ones go, as in the list; a right-click arranges the widgets.
            .contentShape(Rectangle())
            .onTapGesture { model.clearSelection() }
            .glassContextMenu { [model] in OverviewMenus.background(model) }
            // Leaving My Issues ends editing its widgets.
            .onDisappear { model.editingOverview = false }
            .task(id: model.scope) { await model.preloadAvatars() }
        }
    }

    private func grid(width: CGFloat) -> some View {
        let widgets = model.overviewWidgets
        let columns = width >= Self.wideWidth ? 4 : 2
        let rows = Self.rows(widgets, columns: columns)
        let column = Self.columnWidth(width: width, columns: columns)
        return ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: OverviewMetrics.gap) {
                        if model.editingOverview {
                            WidgetShelf()
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        ForEach(rows, id: \.self) { row in
                            HStack(alignment: .top, spacing: OverviewMetrics.gap) {
                                ForEach(row) { widget in
                                    let span = Self.span(widget.size, columns: columns)
                                    OverviewWidget(widget: widget, span: span, columns: columns)
                                        .frame(width: column * CGFloat(span) + OverviewMetrics.gap * CGFloat(span - 1))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, OverviewMetrics.margin)
                    .padding(.top, 6)
                    .padding(.bottom, 28)
                    .animation(Theme.spring, value: widgets)
                    .animation(Theme.spring, value: model.editingOverview)
                }
                .onChange(of: model.focusScrollToken) {
                    if let id = model.focusedItemId {
                        withAnimation(Theme.quick) { proxy.scrollTo(id) }
                    }
                }
        }
    }

    /// From this width on, four columns: a large widget is a lane with Later beside In progress and Up next.
    static let wideWidth: CGFloat = 1000

    /// The widgets in rows of `columns`, in their order; one that doesn't fit beside the ones before starts a row.
    static func rows(_ widgets: [MineWidget], columns: Int) -> [[MineWidget]] {
        var rows: [[MineWidget]] = []
        var row: [MineWidget] = []
        var used = 0
        for widget in widgets {
            let span = span(widget.size, columns: columns)
            if used + span > columns, !row.isEmpty {
                rows.append(row)
                row = []
                used = 0
            }
            row.append(widget)
            used += span
        }
        if !row.isEmpty { rows.append(row) }
        return rows
    }

    /// Small takes a column, medium half the width, large all of it; in two columns medium is as wide as large.
    static func span(_ size: MineWidgetSize, columns: Int) -> Int {
        switch size {
        case .small: 1
        case .medium: columns == 4 ? 2 : columns
        case .large: columns
        }
    }

    private static func columnWidth(width: CGFloat, columns: Int) -> CGFloat {
        let inner = max(width - 2 * OverviewMetrics.margin, 200)
        return (inner - OverviewMetrics.gap * CGFloat(columns - 1)) / CGFloat(columns)
    }

    @ViewBuilder
    private var emptyState: some View {
        if !model.mineFilter.isEmpty, !model.assignedItems.isEmpty {
            // The filter hides everything; one click shows it all again.
            EmptyState(title: String(localized: .nothingMatchesFilterTitle), message: String(localized: .nothingMatchesFilterMessage)) {
                Button(.clearFilter) { model.setMineFilter(ProjectFilter("")) }
                    .buttonStyle(SecondaryButtonStyle())
            }
        } else if model.isLoadingMyIssues {
            MyIssuesLoadingState()
        } else {
            EmptyState(title: String(localized: .nothingAssignedTitle), message: String(localized: .myIssuesEmptyMessage))
        }
    }
}

/// What is being dragged in the overview: an issue, or a widget by its header. A lane knows from it, before the drop,
/// whether it can take the issue, and a widget whether to make room for another.
@Observable
final class OverviewDrag {
    var itemId: String?
    var widgetId: String?
}

private enum OverviewMetrics {
    static let gap: CGFloat = 14
    static let margin: CGFloat = 20
    static let row: CGFloat = 30
    static let laneSpacing: CGFloat = 24
    static let later: CGFloat = 130
}

// MARK: - Menus

@MainActor
enum OverviewMenus {
    /// A widget's menu: its size, its project, and taking it out.
    static func widget(_ widget: MineWidget, model: AppModel) -> NSMenu {
        let menu = MenuBuilder()
        menu.submenu(.widgetSize, "square.resize") { sub in
            for size in MineWidgetSize.allCases {
                sub.item(size.title, checked: size == widget.size) {
                    withAnimation(Theme.spring) { model.setWidgetSize(widget.id, size) }
                }
            }
        }
        if let projectId = model.lane(widget.id)?.projectId {
            menu.item(.showBoard, "rectangle.split.3x1") { model.select(.project(projectId)) }
        }
        menu.divider()
        menu.item(.editWidgets, "square.and.pencil", checked: model.editingOverview) {
            withAnimation(Theme.spring) { model.editingOverview.toggle() }
        }
        menu.item(.removeFromMyIssues, "minus.circle", destructive: true) {
            withAnimation(Theme.spring) { model.removeWidget(widget.id) }
        }
        return menu.build()
    }

    /// The menu beside the widgets: editing them, arranging them by themselves, and what can be added.
    static func background(_ model: AppModel) -> NSMenu {
        let menu = MenuBuilder()
        menu.item(.editWidgets, "square.and.pencil", checked: model.editingOverview) {
            withAnimation(Theme.spring) { model.editingOverview.toggle() }
        }
        menu.item(.arrangeAutomatically, "sparkles", checked: model.mineArrangement.automatic) {
            withAnimation(Theme.spring) { model.setArrangesAutomatically(!model.mineArrangement.automatic) }
        }
        let addable = model.addableWidgets
        if !addable.isEmpty {
            menu.divider()
            for widget in addable {
                menu.item(String(localized: .addToMyIssues(name: model.widgetTitle(widget.id))), widget.smart?.systemImage ?? "plus.circle") {
                    withAnimation(Theme.spring) { model.addWidget(widget) }
                }
            }
        }
        return menu.build()
    }
}

// MARK: - Editing

/// At the top while editing: what can be added, a click each, and whether the overview arranges itself.
private struct WidgetShelf: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let addable = model.addableWidgets
        HStack(spacing: 8) {
            Text(.addWidget)
                .font(.smallMedium)
                .foregroundStyle(Theme.textTertiary)
                .padding(.trailing, 2)
            ForEach(addable) { widget in
                Button {
                    withAnimation(Theme.spring) { model.addWidget(widget) }
                } label: {
                    HStack(spacing: 7) {
                        WidgetIcon(id: widget.id, size: 14)
                        Text(model.widgetTitle(widget.id)).lineLimit(1)
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Theme.accent)
                    }
                    .font(.small)
                    .padding(.leading, 10)
                    .padding(.trailing, 7)
                    .frame(height: 28)
                    .background(Capsule().fill(Theme.control))
                    .contentShape(Capsule())
                }
                .buttonStyle(PlainPressStyle())
                .help(Text(.addToMyIssues(name: model.widgetTitle(widget.id))))
            }
            Spacer(minLength: 12)
            Toggle(isOn: Binding(
                get: { model.mineArrangement.automatic },
                set: { automatic in withAnimation(Theme.spring) { model.setArrangesAutomatically(automatic) } }
            )) {
                Text(.arrangeAutomatically)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(.small)
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
        .shadow(color: Theme.cardShadow, radius: 2, y: 1)
    }
}

// MARK: - A widget

/// One widget: its header, then what it holds at its size.
private struct OverviewWidget: View {
    @Environment(AppModel.self) private var model
    @Environment(OverviewDrag.self) private var drag
    let widget: MineWidget
    let span: Int
    let columns: Int
    @State private var hovering = false
    @State private var targeted = false

    var body: some View {
        let lifted = drag.widgetId == widget.id
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(widget: widget, hovering: hovering, compact: span == 1)
            content
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.card)
                .shadow(color: lifted ? Theme.cardRaisedShadow : Theme.cardShadow, radius: lifted ? 6 : 2, y: 1)
        )
        .overlay(alignment: .topLeading) {
            if model.editingOverview {
                Button {
                    withAnimation(Theme.spring) { model.removeWidget(widget.id) }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Theme.popover))
                        .overlay(Circle().stroke(Theme.popoverBorder, lineWidth: 0.5))
                        .shadow(color: Theme.cardShadow, radius: 2, y: 1)
                        .contentShape(Circle())
                }
                .buttonStyle(PlainPressStyle())
                .help(Text(.removeFromMyIssues))
                .accessibilityLabel(Text(.removeFromMyIssues))
                .offset(x: -8, y: -8)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .onHover { hovering = $0 }
        .glassContextMenu { [model, widget] in OverviewMenus.widget(widget, model: model) }
        .onDrop(of: [.plainText], delegate: WidgetDrop(id: widget.id, model: model, drag: drag))
    }

    @ViewBuilder
    private var content: some View {
        if let smart = widget.smart {
            SmartWidgetContent(widget: smart, size: widget.size)
        } else if let lane = model.lane(widget.id) {
            switch widget.size {
            case .large where columns == 4: LargeLane(lane: lane)
            case .large, .medium: MediumLane(lane: lane)
            case .small: SmallLane(lane: lane)
            }
        }
    }
}

/// A widget passing over another takes its place; the widgets between move along.
private struct WidgetDrop: DropDelegate {
    let id: String
    let model: AppModel
    let drag: OverviewDrag

    func validateDrop(info: DropInfo) -> Bool { drag.widgetId != nil }

    func dropEntered(info: DropInfo) {
        guard let moving = drag.widgetId, moving != id else { return }
        withAnimation(Theme.spring) { model.moveWidget(moving, onto: id) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: drag.widgetId != nil ? .move : .forbidden)
    }

    func performDrop(info: DropInfo) -> Bool {
        drag.widgetId = nil
        return true
    }
}

/// The widget's name, a click away from its project, with how many issues are open there and how many overdue. Its
/// grip shows where to drag it; while editing, its size buttons, else on hover its menu.
private struct WidgetHeader: View {
    @Environment(AppModel.self) private var model
    @Environment(OverviewDrag.self) private var drag
    let widget: MineWidget
    let hovering: Bool
    /// One column wide.
    let compact: Bool
    @State private var hoveringName = false

    var body: some View {
        let lane = model.lane(widget.id)
        HStack(spacing: 8) {
            if let projectId = lane?.projectId {
                Button {
                    model.select(.project(projectId))
                } label: {
                    name
                        .underline(hoveringName && !model.editingOverview, color: Theme.textTertiary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hoveringName = $0 }
                .help(Text(.overviewShowProjectTooltip))
            } else {
                name
            }
            if let lane {
                Text("\(lane.open)")
                    .font(.ui)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                    .help(Text(.overviewOpen(count: lane.open)))
                // A small widget being edited keeps its room for its name and size buttons.
                if lane.overdue > 0, !(compact && model.editingOverview) {
                    Text(.overviewOverdue(count: lane.overdue))
                        .font(.smallMedium)
                        .foregroundStyle(Theme.overdue)
                        .lineLimit(1)
                }
            } else if let count = smartCount {
                Text("\(count)").font(.ui).monospacedDigit().foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 6)
            if model.editingOverview {
                SizeButtons(widget: widget)
            } else {
                GlassMenuButton(label: .widgetMenu, size: CGSize(width: 24, height: 24)) {
                    OverviewMenus.widget(widget, model: model)
                }
                .opacity(hovering ? 1 : 0)
            }
        }
        .lineLimit(1)
        .frame(height: 40)
        // Where to take hold of the widget, in its margin, so the name lines up with the columns under it.
        .overlay(alignment: .leading) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .opacity(hovering || model.editingOverview ? 1 : 0)
                .offset(x: -12)
                .accessibilityHidden(true)
        }
        .background(alignment: .bottom) {
            Rectangle().fill(Theme.rowSeparator).frame(height: 1).padding(.horizontal, -14)
        }
        .padding(.bottom, 4)
        .contentShape(Rectangle())
        .onDrag {
            drag.itemId = nil
            drag.widgetId = widget.id
            return NSItemProvider(object: widget.id as NSString)
        }
    }

    private var name: some View {
        HStack(spacing: 8) {
            WidgetIcon(id: widget.id, size: 15)
            Text(model.widgetTitle(widget.id))
                .font(.uiSemibold)
                .foregroundStyle(Theme.text)
        }
    }

    private var smartCount: Int? {
        switch widget.smart {
        case .needsYou: model.needsYou.count
        case .dueThisWeek: model.dueThisWeek.count
        case .doneThisWeek: model.doneThisWeek.count
        case nil: nil
        }
    }
}

/// A widget's icon: its project's glyph, the ring of the issues on no board, or a smart widget's symbol.
private struct WidgetIcon: View {
    @Environment(AppModel.self) private var model
    let id: String
    var size: CGFloat = 15

    var body: some View {
        if let smart = MineSmartWidget(id: id) {
            Image(systemName: smart.systemImage)
                .font(.system(size: size - 1, weight: .medium))
                .foregroundStyle(smart == .needsYou ? Theme.urgent : smart == .doneThisWeek ? Theme.accent : Theme.textSecondary)
                .frame(width: size, height: size)
        } else if id.hasPrefix("project/") {
            ProjectIcon(projectId: String(id.dropFirst(8)), size: size)
        } else {
            StatusIcon(glyph: .noProject, size: size)
        }
    }
}

/// Small, Medium and Large, while editing.
private struct SizeButtons: View {
    @Environment(AppModel.self) private var model
    let widget: MineWidget

    var body: some View {
        HStack(spacing: 2) {
            ForEach(MineWidgetSize.allCases) { size in
                let on = size == widget.size
                Button {
                    withAnimation(Theme.spring) { model.setWidgetSize(widget.id, size) }
                } label: {
                    Text(verbatim: size.letter)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(on ? Theme.text : Theme.textTertiary)
                        .frame(width: 24, height: 20)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(on ? Theme.segmentActive : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainPressStyle())
                .help(Text(size.title))
                .accessibilityLabel(Text(size.title))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.control))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.widgetSize))
    }
}

// MARK: - Projects

/// A large project widget: In progress, Up next and Later side by side, a lane.
private struct LargeLane: View {
    @Environment(AppModel.self) private var model
    let lane: MineLane

    var body: some View {
        let unfolded = model.showsAllNext(lane)
        HStack(alignment: .top, spacing: OverviewMetrics.laneSpacing) {
            VStack(alignment: .leading, spacing: 0) {
                ColumnLabel(title: .statusGroupInProgress, glyph: AppModel.statusGlyph(.started), count: lane.started.count)
                LaneColumn(lane: lane, kind: .started) { StartedRows(lane: lane) }
            }
            VStack(alignment: .leading, spacing: 0) {
                NextLabel(lane: lane)
                LaneColumn(lane: lane, kind: .unstarted) { NextRows(lane: lane, unfolded: unfolded) }
            }
            VStack(alignment: .leading, spacing: 0) {
                ColumnLabel(title: .later, glyph: StatusGlyph(category: .backlog, progress: 0, color: Theme.textTertiary), count: nil)
                LaterCounts(lane: lane)
            }
            .frame(width: OverviewMetrics.later, alignment: .leading)
        }
    }
}

/// A medium project widget, and a large one in a narrow window: In progress over Up next, the rest as counts.
private struct MediumLane: View {
    @Environment(AppModel.self) private var model
    let lane: MineLane

    var body: some View {
        let unfolded = model.showsAllNext(lane)
        VStack(alignment: .leading, spacing: 0) {
            // The issues on no board have no status, so nothing of theirs is started.
            if lane.projectId != nil {
                ColumnLabel(title: .statusGroupInProgress, glyph: AppModel.statusGlyph(.started), count: lane.started.count)
                LaneColumn(lane: lane, kind: .started) { StartedRows(lane: lane) }
                    .padding(.bottom, 4)
            }
            NextLabel(lane: lane)
            LaneColumn(lane: lane, kind: .unstarted) { NextRows(lane: lane, unfolded: unfolded) }
            if lane.later > 0 || lane.doneThisWeek > 0 {
                Rectangle().fill(Theme.rowSeparator).frame(height: 1).padding(.horizontal, -14).padding(.top, 6)
                HStack(spacing: 14) {
                    LaterCounts(lane: lane, inline: true)
                }
                .padding(.top, 2)
            }
        }
    }
}

/// A small project widget: how many are started, to do and waiting, and the first two of them.
private struct SmallLane: View {
    let lane: MineLane

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                if lane.projectId != nil {
                    count(AppModel.statusGlyph(.started), lane.started.count, .statusGroupInProgress)
                }
                count(lane.projectId == nil ? .noProject : AppModel.statusGlyph(.unstarted), lane.next.count, lane.projectId == nil ? .needsYouOnNoBoard : .upNext)
                if lane.projectId != nil {
                    count(StatusGlyph(category: .backlog, progress: 0, color: Theme.textTertiary), lane.later, .later)
                }
            }
            .frame(height: 28)
            ForEach(lane.smallRows) { OverviewRow(item: $0, lead: .status, showsNumber: false) }
        }
    }

    private func count(_ glyph: StatusGlyph, _ value: Int, _ name: LocalizedStringResource) -> some View {
        HStack(spacing: 5) {
            StatusIcon(glyph: glyph, size: 12)
            Text("\(value)").monospacedDigit()
        }
        .font(.small)
        .foregroundStyle(value == 0 ? Theme.textTertiary : Theme.textSecondary)
        .help(Text(name) + Text(verbatim: ": \(value)"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(name) + Text(verbatim: ", \(value)"))
    }
}

/// Over a column of a project widget: what it holds and how many.
private struct ColumnLabel: View {
    let title: LocalizedStringResource
    let glyph: StatusGlyph
    let count: Int?

    var body: some View {
        HStack(spacing: 6) {
            StatusIcon(glyph: glyph, size: 12)
            Text(title)
            if let count {
                Text("\(count)").monospacedDigit().foregroundStyle(Theme.textTertiary).fontWeight(.regular)
            }
        }
        .font(.smallMedium)
        .foregroundStyle(Theme.textSecondary)
        .lineLimit(1)
        .frame(height: 26)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Up next, or for the issues on no board where they wait.
private struct NextLabel: View {
    let lane: MineLane

    var body: some View {
        if lane.projectId == nil {
            ColumnLabel(title: .needsYouOnNoBoard, glyph: .noProject, count: lane.next.count)
        } else {
            ColumnLabel(title: .upNext, glyph: AppModel.statusGlyph(.unstarted), count: lane.next.count)
        }
    }
}

private struct StartedRows: View {
    let lane: MineLane

    var body: some View {
        if lane.started.isEmpty {
            Text(.overviewNothingInProgress)
                .foregroundStyle(Theme.textTertiary)
                .frame(height: OverviewMetrics.row, alignment: .leading)
        } else {
            ForEach(lane.started) { OverviewRow(item: $0, lead: .status) }
        }
    }
}

private struct NextRows: View {
    let lane: MineLane
    let unfolded: Bool

    var body: some View {
        if lane.next.isEmpty {
            Text(.overviewNothingToDo)
                .foregroundStyle(Theme.textTertiary)
                .frame(height: OverviewMetrics.row, alignment: .leading)
        } else {
            ForEach(lane.shownNext(unfolded: unfolded)) { OverviewRow(item: $0, lead: lane.projectId == nil ? .status : .priority) }
            MoreNextButton(lane: lane, unfolded: unfolded)
        }
    }
}

/// Backlog and what was finished this week, counted rather than listed.
private struct LaterCounts: View {
    let lane: MineLane
    var inline = false

    var body: some View {
        if inline {
            content
        } else {
            VStack(alignment: .leading, spacing: 0) { content }
        }
    }

    @ViewBuilder
    private var content: some View {
        if lane.later > 0 {
            line(StatusGlyph(category: .backlog, progress: 0, color: Theme.textTertiary), Text(.overviewInBacklog(count: lane.later)))
        }
        if lane.doneThisWeek > 0 {
            line(AppModel.statusGlyph(.completed), Text(.overviewDoneThisWeek(count: lane.doneThisWeek)))
        }
    }

    private func line(_ glyph: StatusGlyph, _ text: Text) -> some View {
        HStack(spacing: 7) {
            StatusIcon(glyph: glyph, size: 12)
            text.lineLimit(1)
        }
        .font(.small)
        .foregroundStyle(Theme.textTertiary)
        .frame(height: OverviewMetrics.row)
    }
}

/// In progress or Up next of a project widget. Issues of the lane's project dragged here from the other one take
/// this one's first status; a dragged widget passing over makes room, as over the rest of the widget.
private struct LaneColumn<Content: View>: View {
    @Environment(AppModel.self) private var model
    @Environment(OverviewDrag.self) private var drag
    let lane: MineLane
    let kind: StatusCategory
    @ViewBuilder var content: Content
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(targeted ? Theme.selectionFill : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(targeted ? Theme.selectionBorder : .clear, lineWidth: 1.5)
        )
        .padding(.horizontal, -6)
        .onDrop(of: [.plainText], delegate: LaneDrop(lane: lane, kind: kind, model: model, drag: drag, targeted: $targeted))
    }
}

/// A drop on In progress or Up next: an issue of the same project, from the other column, moves to the first status
/// of this one, as if picked from its status menu. A widget passing over moves to where this lane's widget is.
private struct LaneDrop: DropDelegate {
    let lane: MineLane
    let kind: StatusCategory
    let model: AppModel
    let drag: OverviewDrag
    @Binding var targeted: Bool

    private var item: Item? {
        guard let id = drag.itemId, let projectId = lane.projectId else { return nil }
        guard let item = model.allItems.first(where: { $0.id == id }), item.projectId == projectId,
              model.kindOfStatus(of: item) != kind, model.project(of: item)?.viewerCanUpdate == true else { return nil }
        return item
    }

    func validateDrop(info: DropInfo) -> Bool { drag.widgetId != nil || item != nil }

    func dropEntered(info: DropInfo) {
        if let moving = drag.widgetId {
            if moving != lane.id { withAnimation(Theme.spring) { model.moveWidget(moving, onto: lane.id) } }
            return
        }
        withAnimation(Theme.quick) { targeted = item != nil }
    }

    func dropExited(info: DropInfo) {
        withAnimation(Theme.quick) { targeted = false }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: drag.widgetId != nil || item != nil ? .move : .forbidden)
    }

    func performDrop(info: DropInfo) -> Bool {
        targeted = false
        if drag.widgetId != nil {
            drag.widgetId = nil
            return true
        }
        defer { drag.itemId = nil }
        guard let item, let status = model.firstStatus(kind, projectId: lane.projectId) else { return false }
        withAnimation(Theme.spring) { model.setStatus(item, to: status) }
        return true
    }
}

/// "5 more to do" under the first few, or "Show fewer" once all show.
private struct MoreNextButton: View {
    @Environment(AppModel.self) private var model
    let lane: MineLane
    let unfolded: Bool

    var body: some View {
        let more = lane.moreNext(unfolded: unfolded)
        if more > 0 || (unfolded && lane.next.count > MineLane.nextShown) {
            Button {
                withAnimation(Theme.spring) { model.toggleAllNext(lane) }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: unfolded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                    Text(unfolded ? .overviewShowFewer : .overviewMoreToDo(count: more))
                }
                .font(.smallMedium)
                .foregroundStyle(Theme.textSecondary)
                .frame(height: 26)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Smart widgets

private struct SmartWidgetContent: View {
    @Environment(AppModel.self) private var model
    let widget: MineSmartWidget
    let size: MineWidgetSize

    /// Small ones show the first two, the others up to six.
    private var limit: Int { size == .small ? 2 : 6 }

    var body: some View {
        switch widget {
        case .needsYou:
            let entries = model.needsYou
            if entries.isEmpty {
                empty(.nothingNeedsYou)
            } else {
                ForEach(entries.prefix(limit)) { NeedsYouRow(entry: $0, compact: size == .small) }
            }
        case .dueThisWeek:
            let items = model.dueThisWeek
            if items.isEmpty {
                empty(.nothingDueThisWeek)
            } else {
                ForEach(items.prefix(limit)) { OverviewRow(item: $0, lead: .project, showsNumber: size != .small) }
            }
        case .doneThisWeek:
            let items = model.doneThisWeek
            if items.isEmpty {
                empty(.nothingDoneThisWeek)
            } else {
                ForEach(items.prefix(limit)) { OverviewRow(item: $0, lead: .status, showsNumber: size != .small, finished: true) }
            }
        }
    }

    private func empty(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .foregroundStyle(Theme.textTertiary)
            .frame(height: 34, alignment: .leading)
    }
}

/// An issue that needs you: its title, and below it why, in the colour of the reason, and its project.
private struct NeedsYouRow: View {
    @Environment(AppModel.self) private var model
    let entry: NeedsYouEntry
    let compact: Bool

    var body: some View {
        let item = entry.item
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                if let projectId = item.projectId {
                    ProjectIcon(projectId: projectId, size: 13)
                } else {
                    StatusIcon(glyph: .noProject, size: 13)
                }
                if !compact {
                    Text(item.displayNumber).font(.small).monospacedDigit().foregroundStyle(Theme.textTertiary).fixedSize()
                }
                Text(item.title).font(.uiMedium).foregroundStyle(Theme.text).lineLimit(1)
            }
            HStack(spacing: 5) {
                Text(reason).foregroundStyle(color).fontWeight(.medium)
                if !compact, let place = model.project(of: item)?.title ?? item.repoShortName {
                    Text(verbatim: "· \(place)").foregroundStyle(Theme.textTertiary)
                }
            }
            .font(.small)
            .lineLimit(1)
            .padding(.leading, 21)
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(OverviewIssueInteractions(item: item))
    }

    private var reason: String {
        switch entry.reason {
        case .overdue: String(localized: .needsYouOverdue(days: entry.days))
        case .dueToday: String(localized: .dueToday)
        case .urgent: String(localized: .needsYouUrgent)
        case .idle: String(localized: .overviewIdle(days: entry.days))
        case .onNoBoard: String(localized: .needsYouOnNoBoard)
        }
    }

    private var color: Color {
        switch entry.reason {
        case .overdue: Theme.overdue
        case .dueToday, .urgent: Theme.urgent
        case .idle: Theme.textSecondary
        case .onNoBoard: Theme.accent
        }
    }
}

// MARK: - Issues

/// An issue in a widget: its status, priority or project, number and title, and what needs saying about it at the
/// end.
private struct OverviewRow: View {
    @Environment(AppModel.self) private var model
    let item: Item
    let lead: Lead
    var showsNumber = true
    /// In Done this week: when it was finished instead of what else a row says.
    var finished = false

    enum Lead {
        case status
        case priority
        case project
    }

    var body: some View {
        let selected = model.isSelected(item.id)
        HStack(spacing: 8) {
            switch lead {
            case .status: StatusIcon(glyph: model.glyph(of: item))
            case .priority: PriorityIcon(level: model.priorityLevel(of: item))
            case .project:
                if let projectId = item.projectId { ProjectIcon(projectId: projectId, size: 13) } else { StatusIcon(glyph: .noProject, size: 13) }
            }
            if showsNumber {
                Text(item.displayNumber)
                    .font(.small)
                    .monospacedDigit()
                    .foregroundStyle(selected ? Color.white.opacity(0.8) : Theme.textTertiary)
                    .lineLimit(1)
                    .fixedSize()
            }
            Text(item.title)
                .font(.uiMedium)
                .foregroundStyle(selected ? Color.white : Theme.text)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            if finished {
                if let date = item.closedAt ?? MineRules.lastChange(of: item) {
                    Text(CalendarDay(date).shortLabel())
                        .font(.small)
                        .foregroundStyle(selected ? Color.white.opacity(0.88) : Theme.textTertiary)
                        .fixedSize()
                }
            } else {
                RowSignals(item: item, selected: selected)
            }
        }
        .frame(height: OverviewMetrics.row)
        .modifier(OverviewIssueInteractions(item: item))
    }
}

/// What every issue in the overview does: the pointer and the keyboard focus light it up, a click opens it (⌘ and
/// Shift pick), a right-click has its menu, and it can be dragged to the other column of its project.
private struct OverviewIssueInteractions: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(OverviewDrag.self) private var drag
    let item: Item
    @State private var hovering = false

    func body(content: Content) -> some View {
        let selected = model.isSelected(item.id)
        let focused = model.focusedItemId == item.id
        content
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? Theme.accentFill : hovering || focused ? Theme.selected : .clear)
            )
            .padding(.horizontal, -6)
            .contentShape(Rectangle())
            .id(item.id)
            .onHover { inside in
                hovering = inside
                model.pointer(inside ? .entered : .left, item.id)
            }
            .onTapGesture {
                if model.handleSelectionClick(on: item) { return }
                model.openFromClick(item)
            }
            .onDrag {
                drag.widgetId = nil
                drag.itemId = item.id
                return NSItemProvider(object: item.id as NSString)
            }
            .glassContextMenu { [model, item] in ItemMenuBuilder(model: model, item: item).menu() }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { model.open(item) }
    }
}

/// At the end of a row: who blocks it, how long it has waited, when it is due. Columns share the width, so a
/// sub-issue's progress and labels stay on the issue's page and the title keeps its room.
private struct RowSignals: View {
    @Environment(AppModel.self) private var model
    let item: Item
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            if let blocker = model.blockerMark(for: item) {
                BlockerFlag(mark: blocker, size: 12)
            }
            if let days = model.idleDays(of: item) {
                HStack(spacing: 4) {
                    Image(systemName: "clock").font(.system(size: 10, weight: .medium))
                    Text(.overviewIdle(days: days))
                }
                .font(.small)
                .help(Text(.overviewIdleTooltip(days: days)))
            }
            if let due = model.dueBadge(for: item) {
                HStack(spacing: 4) {
                    Image(systemName: "calendar").font(.system(size: 11, weight: .medium))
                    Text(due.label)
                }
                .font(.small)
                .foregroundStyle(selected ? Color.white : due.tone.color)
                .help(due.tooltip)
            }
        }
        .foregroundStyle(selected ? Color.white.opacity(0.88) : Theme.textSecondary)
        .lineLimit(1)
        .fixedSize()
    }
}
#endif
