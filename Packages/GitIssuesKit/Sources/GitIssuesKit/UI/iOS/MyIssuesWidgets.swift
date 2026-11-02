#if os(iOS)
import SwiftUI

// MARK: - The overview's widgets in a list

/// How the overview's widgets stand in the iPhone's and iPad's list: each as a section of its own, except small
/// project widgets, which stand two to a row as tiles.
enum MobileWidgetRow: Identifiable {
    case widget(MineWidget)
    case tiles([MineWidget])

    var id: String {
        switch self {
        case .widget(let widget): widget.id
        case .tiles(let widgets): "tiles:" + widgets.map(\.id).joined(separator: ",")
        }
    }

    /// Small project widgets next to each other pair up; the issues on no board and the smart widgets have no page of
    /// their own to open, so they stay sections whatever their size.
    static func rows(_ widgets: [MineWidget], lanes: [String: MineLane]) -> [MobileWidgetRow] {
        var rows: [MobileWidgetRow] = []
        var waiting: [MineWidget] = []
        func flush() {
            for pair in stride(from: 0, to: waiting.count, by: 2) {
                rows.append(.tiles(Array(waiting[pair..<min(pair + 2, waiting.count)])))
            }
            waiting = []
        }
        for widget in widgets {
            if widget.size == .small, lanes[widget.id]?.projectId != nil {
                waiting.append(widget)
            } else {
                flush()
                rows.append(.widget(widget))
            }
        }
        flush()
        return rows
    }
}

/// The header of a smart widget in the list: its symbol and name, how many it holds, and the arrow that folds it.
struct SmartWidgetHeader: View {
    @Environment(AppModel.self) private var model
    let widget: MineSmartWidget
    let count: Int
    @ScaledMetric(relativeTo: .title3) private var glyphSize: CGFloat = 18

    var body: some View {
        let folded = model.isSectionCollapsed(widget.id, in: .myIssues)
        Button {
            withAnimation(Theme.spring) { model.toggleSection(widget.id, in: .myIssues) }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                    .rotationEffect(.degrees(folded ? -90 : 0))
                    .frame(width: 12)
                Image(systemName: widget.systemImage)
                    .font(.system(size: glyphSize * 0.86, weight: .medium))
                    .foregroundStyle(widget == .needsYou ? Theme.urgent : widget == .doneThisWeek ? Theme.accent : Theme.textSecondary)
                    .frame(width: glyphSize, height: glyphSize)
                Text(widget.title).font(.title3.weight(.bold)).foregroundStyle(Theme.text).lineLimit(1)
                Text("\(count)").font(.body).monospacedDigit().foregroundStyle(Theme.textTertiary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainPressStyle())
        .accessibilityIdentifier("section-\(widget.title)")
        .accessibilityLabel(.sectionIssueCount(title: widget.title, count: count))
        .accessibilityValue(Text(folded ? LocalizedStringResource.sectionFolded : .sectionOpen))
        .padding(.leading, 10)
        .padding(.trailing, 20)
        .padding(.top, 14)
        .padding(.bottom, 4)
        .frame(minHeight: 44)
        .background(Theme.panel)
        .animation(Theme.quick, value: folded)
    }
}

/// An issue that needs you, in the list: the row with why it is there, in the reason's colour, under its title.
struct NeedsYouListRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openRoute) private var openRoute
    let entry: NeedsYouEntry
    @ScaledMetric(relativeTo: .body) private var glyphSize: CGFloat = 20

    var body: some View {
        let item = entry.item
        Button {
            openRoute(.issue(item.id))
        } label: {
            HStack(alignment: .top, spacing: 12) {
                StatusIcon(glyph: model.glyph(of: item), size: glyphSize)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.body)
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        Text(reason).foregroundStyle(color).fontWeight(.medium)
                        Text(verbatim: "·").foregroundStyle(Theme.textTertiary)
                        if let projectId = item.projectId {
                            ProjectIcon(projectId: projectId, size: 10)
                        }
                        Text(model.project(of: item)?.title ?? item.repoShortName ?? "")
                            .foregroundStyle(Theme.textTertiary)
                        Text(item.displayNumber).monospacedDigit().foregroundStyle(Theme.textTertiary)
                    }
                    .font(.footnote)
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 11)
            .padding(.leading, IssueRow.leading)
            .padding(.trailing, 18)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.rowSeparator).frame(height: 1).padding(.leading, IssueRow.leading + glyphSize + 12)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("needs-\(item.displayNumber)")
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Theme.panel)
        .contextMenu {
            ItemMenuContent(item: item, foldable: false) { openRoute(.issue(item.id)) }
        } preview: {
            IssuePreview(item: item)
                .environment(model)
        }
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

/// Small project widgets, two to a row: the project's icon and how many are started, to do and waiting; a tap shows
/// the project, as a tile on Home does.
struct ProjectTilesRow: View {
    @Environment(AppModel.self) private var model
    let widgets: [MineWidget]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(widgets) { widget in
                if let lane = model.lane(widget.id) {
                    ProjectWidgetTile(lane: lane)
                }
            }
            if widgets.count == 1 { Color.clear.frame(maxWidth: .infinity) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Theme.panel)
    }
}

private struct ProjectWidgetTile: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openRoute) private var openRoute
    let lane: MineLane

    var body: some View {
        Button {
            if let projectId = lane.projectId { openRoute(.project(projectId)) }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    if let projectId = lane.projectId { ProjectTile(projectId: projectId, size: 30) }
                    Spacer(minLength: 4)
                    if lane.overdue > 0 {
                        Text(.overviewOverdue(count: lane.overdue))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.overdue)
                            .lineLimit(1)
                    }
                }
                Text(lane.title)
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                HStack(spacing: 10) {
                    count(AppModel.statusGlyph(.started), lane.started.count)
                    count(AppModel.statusGlyph(.unstarted), lane.next.count)
                    count(StatusGlyph(category: .backlog, progress: 0, color: Theme.textTertiary), lane.later)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.groupHeader))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PlainPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(lane.title))
        .accessibilityValue(
            Text(.statusGroupInProgress) + Text(verbatim: " \(lane.started.count), ")
                + Text(.upNext) + Text(verbatim: " \(lane.next.count), ")
                + Text(.overviewInBacklog(count: lane.later))
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("tile-\(lane.title)")
    }

    private func count(_ glyph: StatusGlyph, _ value: Int) -> some View {
        HStack(spacing: 4) {
            StatusIcon(glyph: glyph, size: 14)
            Text("\(value)").monospacedDigit()
        }
        .font(.subheadline)
        .foregroundStyle(value == 0 ? Theme.textTertiary : Theme.textSecondary)
    }
}

// MARK: - Customize

/// Arranging the overview on iPhone and iPad, as Home's widgets are listed in iOS: whether it arranges itself, then
/// the widgets shown, to move, resize or take out, then those that can be added.
struct CustomizeMyIssuesSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let widgets = model.overviewWidgets
        let addable = model.addableWidgets
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: Binding(
                        get: { model.mineArrangement.automatic },
                        set: { automatic in withAnimation(Theme.spring) { model.setArrangesAutomatically(automatic) } }
                    )) {
                        Text(.arrangeAutomatically)
                    }
                    .accessibilityIdentifier("arrange-automatically")
                } footer: {
                    Text(.arrangeAutomaticallyFooter)
                }
                Section {
                    ForEach(widgets) { widget in
                        HStack(spacing: 12) {
                            CustomizeIcon(id: widget.id)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.widgetTitle(widget.id)).lineLimit(1)
                                Menu {
                                    Picker(.widgetSize, selection: Binding(
                                        get: { widget.size },
                                        set: { size in withAnimation(Theme.spring) { model.setWidgetSize(widget.id, size) } }
                                    )) {
                                        ForEach(MineWidgetSize.allCases) { Text($0.title).tag($0) }
                                    }
                                } label: {
                                    HStack(spacing: 3) {
                                        Text(widget.size.title)
                                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
                                    }
                                    .font(.footnote)
                                    .foregroundStyle(Theme.textSecondary)
                                }
                                .accessibilityLabel(Text(.widgetSize))
                                .accessibilityValue(Text(widget.size.title))
                                .accessibilityIdentifier("size-\(model.widgetTitle(widget.id))")
                            }
                        }
                    }
                    .onMove { from, to in
                        guard let index = from.first else { return }
                        let id = widgets[index].id
                        // `to` counts the widget itself where it stood.
                        let target = to > index ? to - 1 : to
                        withAnimation(Theme.spring) { model.moveWidget(id, toShownIndex: target) }
                    }
                    .onDelete { offsets in
                        for index in offsets { withAnimation(Theme.spring) { model.removeWidget(widgets[index].id) } }
                    }
                } header: {
                    Text(.widgetsShown)
                }
                if !addable.isEmpty {
                    Section {
                        ForEach(addable) { widget in
                            Button {
                                withAnimation(Theme.spring) { model.addWidget(widget) }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.white, .green)
                                    CustomizeIcon(id: widget.id)
                                    Text(model.widgetTitle(widget.id)).foregroundStyle(Theme.text)
                                }
                            }
                            .accessibilityLabel(Text(.addToMyIssues(name: model.widgetTitle(widget.id))))
                        }
                    } header: {
                        Text(.widgetsNotShown)
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(.customizeMyIssues)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(.done, systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// A widget's icon in the Customize sheet.
private struct CustomizeIcon: View {
    let id: String

    var body: some View {
        Group {
            if let smart = MineSmartWidget(id: id) {
                Image(systemName: smart.systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(smart == .needsYou ? Theme.urgent : smart == .doneThisWeek ? Theme.accent : Theme.textSecondary)
            } else if id.hasPrefix("project/") {
                ProjectIcon(projectId: String(id.dropFirst(8)), size: 20)
            } else {
                StatusIcon(glyph: .noProject, size: 20)
            }
        }
        .frame(width: 28, height: 28)
    }
}
#endif
