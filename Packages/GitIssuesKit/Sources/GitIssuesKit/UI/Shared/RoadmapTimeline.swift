import SwiftUI

/// Where things sit on the roadmap's timeline, worked out once per drawing: the days it shows, how wide a day is,
/// and the rows.
struct TimelineLayout {
    static let monthsHeight: CGFloat = 26
    static let milestonesHeight: CGFloat = 32
    static let headerHeight = monthsHeight + milestonesHeight
    static let rowHeight: CGFloat = 34
    static let laterGap: CGFloat = 10
    static let barHeight: CGFloat = 20

    var roadmap: Roadmap
    var first: CalendarDay
    var days: Int
    var scale: CGFloat

    init(roadmap: Roadmap, zoom: RoadmapZoom, available: CGFloat, today: CalendarDay = .today(), scale: CGFloat? = nil) {
        self.roadmap = roadmap
        let span = roadmap.span ?? today.adding(days: -14)...today.adding(days: 60)
        // Today shows even when the milestones are all ahead.
        first = min(span.lowerBound, today.adding(days: -6))
        let last = max(span.upperBound, today.adding(days: 14))
        days = max(last.days(from: first) + 1, 1)
        self.scale = TimelineZoom.clamp(scale ?? zoom.scale)
        days = max(days, Int(ceil(max(available, 0) / self.scale)))
    }

    var width: CGFloat { CGFloat(days) * scale }

    func x(_ day: CalendarDay) -> CGFloat {
        CGFloat(day.days(from: first)) * scale
    }

    /// The day under an x position.
    func day(at x: CGFloat) -> CalendarDay {
        first.adding(days: Int((x / scale).rounded(.down)))
    }

    /// A window's stretch: from the start of its first day to the end of its last.
    func span(of window: Roadmap.Window) -> ClosedRange<CGFloat> {
        x(window.start)...(x(window.end) + scale)
    }

    /// The window an x position falls into, the nearest when it falls between or outside them.
    func window(at x: CGFloat) -> Int? {
        guard !roadmap.windows.isEmpty else { return nil }
        if let inside = roadmap.windows.firstIndex(where: { span(of: $0).contains(x) }) { return inside }
        return roadmap.windows.indices.min { a, b in
            distance(x, span(of: roadmap.windows[a])) < distance(x, span(of: roadmap.windows[b]))
        }
    }

    private func distance(_ x: CGFloat, _ range: ClosedRange<CGFloat>) -> CGFloat {
        x < range.lowerBound ? range.lowerBound - x : x - range.upperBound
    }

    /// The x where a milestone's diamond sits: the end of the day it is due.
    func dueX(_ window: Roadmap.Window) -> CGFloat {
        x(window.end) + scale
    }

    func rowTop(_ index: Int) -> CGFloat {
        Self.headerHeight + CGFloat(index) * Self.rowHeight
    }

    /// Where the "Later" section starts, below the planned epics.
    var laterTop: CGFloat {
        rowTop(roadmap.rows.count) + Self.laterGap
    }

    func laterRowTop(_ index: Int) -> CGFloat {
        laterTop + Self.rowHeight + CGFloat(index) * Self.rowHeight
    }

    var height: CGFloat {
        laterRowTop(roadmap.later.count) + 16
    }

    /// The stretches a row's bars cover, with how many of the epic's issues each holds.
    func bars(of row: Roadmap.Row) -> [(rect: CGRect, count: Roadmap.Count)] {
        row.runs.map { run in
            let whole = row.runs.count == 1
            let start = span(of: roadmap.windows[run.lowerBound]).lowerBound
            let end = span(of: roadmap.windows[run.upperBound]).upperBound
            var count = Roadmap.Count(done: 0, total: 0)
            for index in run {
                if let part = row.perMilestone[roadmap.windows[index].group.title] {
                    count.done += part.done
                    count.total += part.total
                }
            }
            // One bar says how far the whole epic is; bars apart say how far each stretch is.
            if whole { count = Roadmap.Count(done: row.done, total: row.total) }
            return (CGRect(x: start + 2, y: 0, width: max(end - start - 4, 8), height: Self.barHeight), count)
        }
    }

    enum Hit: Equatable {
        case row(Int)
        case later(Int)
        case laterHeader
        case milestone(Int)
    }

    /// What is under a point of the timeline.
    func hit(_ point: CGPoint) -> Hit? {
        if point.y < Self.headerHeight {
            guard point.y >= Self.monthsHeight else { return nil }
            for (index, window) in roadmap.windows.enumerated() where abs(point.x - dueX(window)) <= 9 {
                return .milestone(index)
            }
            return nil
        }
        if point.y < rowTop(roadmap.rows.count) {
            return .row(Int((point.y - Self.headerHeight) / Self.rowHeight))
        }
        if point.y >= laterTop, point.y < laterTop + Self.rowHeight { return .laterHeader }
        let index = Int((point.y - laterTop - Self.rowHeight) / Self.rowHeight)
        return roadmap.later.indices.contains(index) && point.y >= laterTop ? .later(index) : nil
    }
}

/// The roadmap as a timeline, as Linear's: the board's open milestones as stretches of time ending on the day each
/// is due, and its epics as bars over the milestones they and their issues are in. Dragging a bar to another
/// milestone moves the epic and its unfinished issues there; dragging a milestone's diamond changes its date.
struct RoadmapTimeline: View {
    @Environment(AppModel.self) private var model
    var projectId: String
    var nameWidth: CGFloat = 260
    /// Opens an epic: the issue view on the Mac, a pushed screen on the iPad.
    var open: (Item) -> Void

    @State private var hovered: TimelineLayout.Hit?
    @State private var drag: BarDrag?
    @State private var dueDrag: DueDrag?
    @State private var cancelledDrag = false
    @GestureState private var dragActive = false

    struct BarDrag: Equatable {
        var epicId: String
        var from: TimelineLayout.Hit
        var start: CGPoint
        var location: CGPoint
        /// The window it would land in, or nil over "Later".
        var target: Int?
        var overLater: Bool
    }

    struct DueDrag: Equatable {
        var window: Int
        var day: CalendarDay
    }

    var body: some View {
        let roadmap = model.roadmap(projectId: projectId)
        GeometryReader { proxy in
            let layout = TimelineLayout(roadmap: roadmap, zoom: model.roadmapZoom, available: max(proxy.size.width - nameWidth - 1, 200), scale: model.timelineScale)
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    names(layout)
                        .frame(width: nameWidth)
                    Rectangle().fill(Theme.panelBorder).frame(width: 1, height: layout.height)
                    ScrollView(.horizontal) {
                        canvas(layout)
                    }
                    .scrollIndicators(.automatic)
                    .defaultScrollAnchor(.leading)
                    .timelineZoom(scale: layout.scale)
                }
            }
            .scrollIndicators(.never)
        }
        .animation(Theme.spring, value: roadmap.rows.map(\.id))
        .onChange(of: model.dragCancelToken) { _, _ in
            if drag != nil || dueDrag != nil {
                cancelledDrag = true
                clearDrag()
            }
        }
        .onChange(of: dragActive) { _, active in
            if !active {
                clearDrag()
                cancelledDrag = false
            }
        }
        .onDisappear { clearDrag() }
    }

    private func clearDrag() {
        guard drag != nil || dueDrag != nil else { return }
        drag = nil
        dueDrag = nil
        model.isDragging = false
    }

    // MARK: Names

    private func names(_ layout: TimelineLayout) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(.epicsCount(count: layout.roadmap.rows.count + layout.roadmap.later.count))
                    .font(.tinySemibold)
                    .foregroundStyle(Theme.textTertiary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 9)
            .frame(height: TimelineLayout.headerHeight, alignment: .bottom)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.panelBorder).frame(height: 1) }
            ForEach(Array(layout.roadmap.rows.enumerated()), id: \.element.id) { index, row in
                nameCell(row, hit: .row(index))
            }
            HStack(spacing: 8) {
                Text(.later).font(.uiSemibold).foregroundStyle(Theme.text)
                Text("\(layout.roadmap.later.count)").font(.ui).foregroundStyle(Theme.textTertiary).monospacedDigit()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: TimelineLayout.rowHeight)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.groupHeader))
            .padding(.leading, 6)
            .padding(.top, TimelineLayout.laterGap)
            .help(Text(.laterTooltip))
            ForEach(Array(layout.roadmap.later.enumerated()), id: \.element.id) { index, row in
                nameCell(row, hit: .later(index))
            }
            Spacer(minLength: 16)
        }
        .frame(height: layout.height, alignment: .top)
    }

    private func nameCell(_ row: Roadmap.Row, hit: TimelineLayout.Hit) -> some View {
        Button {
            open(row.epic)
        } label: {
            HStack(spacing: 8) {
                EpicIcon(color: model.isDone(row.epic) ? Theme.textTertiary : Theme.epic)
                Text(row.epic.title)
                    .font(.uiMedium)
                    .foregroundStyle(model.isDone(row.epic) ? Theme.textSecondary : Theme.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.leading, 16 + CGFloat(row.depth) * 18)
            .padding(.trailing, 10)
            .frame(height: TimelineLayout.rowHeight)
            .background(hovered == hit ? Theme.hover.opacity(0.7) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainPressStyle())
        .onHover { inside in
            if inside { hovered = hit } else if hovered == hit { hovered = nil }
        }
        .help(Text(tooltip(row)))
        .accessibilityLabel(Text(row.epic.title))
        .accessibilityValue(Text(accessibilityValue(row)))
        .modifier(EpicRowMenu(epic: row.epic))
    }

    // MARK: Timeline

    private func canvas(_ layout: TimelineLayout) -> some View {
        let today = CalendarDay.today()
        let marks = layout.roadmap.windows.map { model.mark(of: $0.group, projectId: projectId, today: today) }
        let done = Set((layout.roadmap.rows + layout.roadmap.later).filter { model.isDone($0.epic) }.map(\.epic.id))
        let (shownHover, shownDrag, shownDueDrag) = (hovered, drag, dueDrag)
        return Canvas { context, size in
            TimelinePainter(
                context: context, size: size, layout: layout, marks: marks, doneEpics: done, today: today,
                hovered: shownHover, drag: shownDrag, dueDrag: shownDueDrag
            ).draw()
        }
        .frame(width: layout.width, height: layout.height)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let point): hovered = layout.hit(point)
            case .ended: hovered = nil
            }
        }
        .help(Text(hoverTooltip(layout)))
        .gesture(
            DragGesture(minimumDistance: 4)
                .updating($dragActive) { _, active, _ in active = true }
                .onChanged { value in changed(value, layout) }
                .onEnded { _ in ended(layout) }
        )
        .simultaneousGesture(SpatialTapGesture().onEnded { value in
            switch layout.hit(value.location) {
            case .row(let index): open(layout.roadmap.rows[index].epic)
            case .later(let index): open(layout.roadmap.later[index].epic)
            default: break
            }
        })
        .accessibilityHidden(true)
    }

    private func changed(_ value: DragGesture.Value, _ layout: TimelineLayout) {
        guard !cancelledDrag else { return }
        if drag == nil, dueDrag == nil {
            guard model.projects.first(where: { $0.id == projectId })?.viewerCanUpdate == true else { return }
            switch layout.hit(value.startLocation) {
            case .milestone(let index):
                dueDrag = DueDrag(window: index, day: layout.roadmap.windows[index].end)
            case .row(let index):
                let row = layout.roadmap.rows[index]
                // A drag starts on the epic's bar, not on the empty track beside it.
                let top = layout.rowTop(index) + (TimelineLayout.rowHeight - TimelineLayout.barHeight) / 2
                let onBar = layout.bars(of: row).contains { $0.rect.offsetBy(dx: 0, dy: top).insetBy(dx: -2, dy: -4).contains(value.startLocation) }
                guard onBar else { return }
                drag = BarDrag(epicId: row.epic.id, from: .row(index), start: value.startLocation, location: value.location, target: nil, overLater: false)
            case .later(let index):
                drag = BarDrag(
                    epicId: layout.roadmap.later[index].epic.id, from: .later(index), start: value.startLocation,
                    location: value.location, target: nil, overLater: true
                )
            default:
                return
            }
        }
        if drag != nil || dueDrag != nil { model.isDragging = true }
        if var current = dueDrag {
            let window = layout.roadmap.windows[current.window]
            // Not before the day after the milestone before it, nor after the one after it.
            var day = layout.day(at: value.location.x)
            if current.window > 0 { day = max(day, layout.roadmap.windows[current.window - 1].end.adding(days: 1)) }
            if layout.roadmap.windows.indices.contains(current.window + 1), !layout.roadmap.windows[current.window + 1].undated {
                day = min(day, layout.roadmap.windows[current.window + 1].end.adding(days: -1))
            }
            if window.undated { return }
            current.day = day
            if current != dueDrag { dueDrag = current }
            return
        }
        guard var current = drag else { return }
        current.location = value.location
        current.overLater = value.location.y >= layout.laterTop - TimelineLayout.laterGap / 2
        current.target = current.overLater ? nil : layout.window(at: value.location.x)
        drag = current
    }

    private func ended(_ layout: TimelineLayout) {
        defer {
            clearDrag()
            cancelledDrag = false
        }
        guard !cancelledDrag else { return }
        if let dueDrag {
            let window = layout.roadmap.windows[dueDrag.window]
            if dueDrag.day != window.end { model.setDue(window.group, to: dueDrag.day) }
            return
        }
        guard let drag, let epic = model.allItems.first(where: { $0.id == drag.epicId }) else { return }
        // A short drag that ends where it started changes nothing.
        guard abs(drag.location.x - drag.start.x) > 6 || abs(drag.location.y - drag.start.y) > 6 else { return }
        if drag.overLater {
            if case .row = drag.from { model.moveEpic(epic, to: nil, projectId: projectId) }
            return
        }
        guard let target = drag.target else { return }
        let group = layout.roadmap.windows[target].group
        if case .row(let index) = drag.from, layout.roadmap.rows[index].runs == [target...target] { return }
        model.moveEpic(epic, to: group, projectId: projectId)
    }

    // MARK: Words

    private func tooltip(_ row: Roadmap.Row) -> String {
        var lines = [row.epic.title]
        lines.append(accessibilityValue(row))
        return lines.joined(separator: "\n")
    }

    private func accessibilityValue(_ row: Roadmap.Row) -> String {
        let windows = model.roadmap(projectId: projectId).windows
        let titles = row.runs.flatMap { run in run.map { windows[$0].group.title } }
        let progress = String(localized: .subIssuesProgress(done: row.done, total: row.total))
        guard !titles.isEmpty else { return progress }
        return "\(titles.formatted(.list(type: .and))) · \(progress)"
    }

    private func hoverTooltip(_ layout: TimelineLayout) -> String {
        switch hovered {
        case .row(let index) where layout.roadmap.rows.indices.contains(index):
            return tooltip(layout.roadmap.rows[index])
        case .later(let index) where layout.roadmap.later.indices.contains(index):
            return String(localized: .dragOntoMilestoneTooltip)
        case .milestone(let index) where layout.roadmap.windows.indices.contains(index):
            let window = layout.roadmap.windows[index]
            if window.undated { return String(localized: .milestoneWithoutDateTooltip(milestone: window.group.title)) }
            return String(localized: .milestoneDueDragTooltip(milestone: window.group.title, date: window.end.longLabel))
        default:
            return ""
        }
    }
}

/// The right-click menu of an epic on the roadmap: on the Mac the issue's menu, as everywhere.
private struct EpicRowMenu: ViewModifier {
    @Environment(AppModel.self) private var model
    var epic: Item
    #if os(macOS)
    @State private var region = UUID()
    #endif

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                let id = epic.id
                ContextMenus.shared.register(region, frame: frame) { [model] _ in
                    model.allItems.first { $0.id == id }.map { ItemMenuBuilder(model: model, item: $0).menu() }
                }
            }
            .onDisappear { ContextMenus.shared.remove(region) }
        #else
        content.contextMenu {
            ItemMenuContent(item: epic, foldable: false) {}
        }
        #endif
    }
}

/// Draws the timeline in one pass: months, the milestones' stretches and diamonds, today, and the epics' bars.
private struct TimelinePainter {
    var context: GraphicsContext
    var size: CGSize
    var layout: TimelineLayout
    var marks: [MilestoneMark]
    var doneEpics: Set<String>
    var today: CalendarDay
    var hovered: TimelineLayout.Hit?
    var drag: RoadmapTimeline.BarDrag?
    var dueDrag: RoadmapTimeline.DueDrag?

    private var roadmap: Roadmap { layout.roadmap }

    func draw() {
        let plannedBottom = layout.rowTop(roadmap.rows.count)

        // Every other milestone's stretch, lightly, from the milestone row down through the planned epics.
        for (index, window) in roadmap.windows.enumerated() where index % 2 == 1 || isDropTarget(index) {
            let span = layout.span(of: window)
            let rect = CGRect(x: span.lowerBound, y: TimelineLayout.monthsHeight, width: span.upperBound - span.lowerBound, height: plannedBottom - TimelineLayout.monthsHeight)
            context.fill(Path(rect), with: .color(isDropTarget(index) ? Theme.epic.opacity(0.10) : Theme.timelineBand))
        }
        // Hovered row.
        if case .row(let index) = hovered, drag == nil {
            context.fill(Path(CGRect(x: 0, y: layout.rowTop(index), width: size.width, height: TimelineLayout.rowHeight)), with: .color(Theme.hover.opacity(0.7)))
        }
        if case .later(let index) = hovered, drag == nil {
            context.fill(Path(CGRect(x: 0, y: layout.laterRowTop(index), width: size.width, height: TimelineLayout.rowHeight)), with: .color(Theme.hover.opacity(0.7)))
        }

        drawMonths(today: today)
        drawMilestones(today: today)

        // The header's lower edge.
        context.fill(Path(CGRect(x: 0, y: TimelineLayout.headerHeight - 1, width: size.width, height: 1)), with: .color(Theme.panelBorder))

        // Today.
        let todayX = layout.x(today) + layout.scale / 2
        if todayX >= 0, todayX <= size.width {
            context.fill(Path(CGRect(x: todayX - 0.75, y: 2, width: 1.5, height: plannedBottom - 2)), with: .color(Theme.accent))
            let label = context.resolve(Text(.today).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.accent))
            context.draw(label, at: CGPoint(x: todayX + 4, y: 0), anchor: .topLeading)
        }

        for (index, row) in roadmap.rows.enumerated() {
            drawBars(row, top: layout.rowTop(index), dimmed: drag?.epicId == row.epic.id)
        }

        do {
            let rect = CGRect(x: 0, y: layout.laterTop, width: size.width, height: TimelineLayout.rowHeight)
            if drag?.overLater == true, case .row = drag?.from {
                context.fill(Path(roundedRect: rect.insetBy(dx: 6, dy: 1), cornerRadius: 7), with: .color(Theme.epic.opacity(0.10)))
                context.stroke(Path(roundedRect: rect.insetBy(dx: 6, dy: 1), cornerRadius: 7), with: .color(Theme.epic.opacity(0.45)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            } else {
                context.fill(Path(roundedRect: rect.insetBy(dx: 0, dy: 0), cornerRadius: 0), with: .color(Theme.groupHeader))
            }
        }

        drawDragged()
    }

    private func isDropTarget(_ index: Int) -> Bool {
        guard let drag, !drag.overLater else { return false }
        return drag.target == index
    }

    private func drawMonths(today: CalendarDay) {
        var month = CalendarDay(year: layout.first.year, month: layout.first.month, day: 1)
        let end = layout.first.adding(days: layout.days)
        var firstLabel = true
        while month <= end {
            let x = max(layout.x(month), 0)
            if layout.x(month) >= 0 {
                context.fill(Path(CGRect(x: x, y: 0, width: 1, height: TimelineLayout.monthsHeight)), with: .color(Theme.panelBorder))
            }
            let showsYear = firstLabel || month.month == 1 || month.year != today.year && firstLabel
            let text = month.date().formatted(showsYear && month.year != today.year ? .dateTime.month(.abbreviated).year() : .dateTime.month(.abbreviated))
            let resolved = context.resolve(Text(text).font(.system(size: 11)).foregroundStyle(Theme.textTertiary))
            // The first month's name only where there is room before the next one.
            let next = month.adding(months: 1)
            if layout.x(next) - x > 30 {
                context.draw(resolved, at: CGPoint(x: x + 6, y: 13), anchor: .topLeading)
            }
            firstLabel = false
            month = next
        }
    }

    private func drawMilestones(today: CalendarDay) {
        let midY = TimelineLayout.monthsHeight + TimelineLayout.milestonesHeight / 2
        var previousEnd: CGFloat = -.infinity
        for (index, window) in roadmap.windows.enumerated() {
            let group = window.group
            var dueX = layout.dueX(window)
            var day = window.end
            if let dueDrag, dueDrag.window == index {
                day = dueDrag.day
                dueX = layout.x(day) + layout.scale
            }
            let mark = marks.indices.contains(index) ? marks[index] : .upcoming
            let diamondRect = CGRect(x: dueX - 7, y: midY - 7, width: 14, height: 14)
            if hovered == .milestone(index) || dueDrag?.window == index {
                context.fill(Path(roundedRect: diamondRect.insetBy(dx: -4, dy: -4), cornerRadius: 5), with: .color(Theme.partHover))
            }
            let outline = PlanningGlyph.diamond(in: diamondRect)
            let style = StrokeStyle(lineWidth: 1.5, lineJoin: .round, dash: window.undated ? [2, 2] : [])
            switch mark {
            case .completed:
                context.fill(outline, with: .color(mark.color))
            case .current, .late:
                context.stroke(outline, with: .color(mark.color), style: style)
                context.fill(PlanningGlyph.diamond(in: diamondRect, inset: 4.8), with: .color(mark.color))
            case .upcoming, .none:
                context.stroke(outline, with: .color(mark.color), style: style)
            }
            // Title and date, right-aligned before the diamond, as long as they fit the stretch.
            let dateText = window.undated ? String(localized: .noDate) : day.shortLabel(today: today)
            let title = context.resolve(
                Text("\(Text(group.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text))  \(Text(dateText).font(.system(size: 11)).foregroundStyle(dueDrag?.window == index ? Theme.accent : Theme.textTertiary))")
            )
            let width = title.measure(in: CGSize(width: 400, height: 30)).width
            let room = dueX - 12 - max(layout.span(of: window).lowerBound, previousEnd + 8)
            if width <= room {
                context.draw(title, at: CGPoint(x: dueX - 12, y: midY), anchor: .trailing)
            } else {
                let short = context.resolve(Text(group.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text))
                if short.measure(in: CGSize(width: 400, height: 30)).width <= room {
                    context.draw(short, at: CGPoint(x: dueX - 12, y: midY), anchor: .trailing)
                }
            }
            previousEnd = dueX + 7
        }
    }

    private func drawBars(_ row: Roadmap.Row, top: CGFloat, dimmed: Bool) {
        let barTop = top + (TimelineLayout.rowHeight - TimelineLayout.barHeight) / 2
        let bars = layout.bars(of: row)
        let done = doneEpics.contains(row.epic.id)
        // A dashed line through the stretches between the bars, where the epic has nothing.
        for (a, b) in zip(bars, bars.dropFirst()) {
            var line = Path()
            line.move(to: CGPoint(x: a.rect.maxX, y: barTop + TimelineLayout.barHeight / 2))
            line.addLine(to: CGPoint(x: b.rect.minX, y: barTop + TimelineLayout.barHeight / 2))
            context.stroke(line, with: .color(Theme.epicBarBorder.opacity(dimmed ? 0.4 : 1)), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
        }
        for bar in bars {
            drawBar(bar.rect.offsetBy(dx: 0, dy: barTop), count: bar.count, done: done, opacity: dimmed ? 0.35 : 1)
        }
    }

    private func drawBar(_ rect: CGRect, count: Roadmap.Count, done: Bool, opacity: Double) {
        var layer = context
        layer.opacity = opacity
        let shape = Path(roundedRect: rect, cornerRadius: 6, style: .continuous)
        layer.fill(shape, with: .color(Theme.epicBar))
        let fraction = done ? 1 : count.total > 0 ? CGFloat(count.done) / CGFloat(count.total) : 0
        if fraction > 0 {
            var clipped = layer
            clipped.clip(to: shape)
            clipped.fill(Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width * fraction, height: rect.height)), with: .color(Theme.epicBarFill))
        }
        layer.stroke(shape, with: .color(Theme.epicBarBorder), lineWidth: 1)
        guard count.total > 0 else { return }
        let label = layer.resolve(
            Text("\(count.done) / \(count.total)").font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(Theme.text)
        )
        let width = label.measure(in: CGSize(width: 200, height: 20)).width
        if width + 14 <= rect.width {
            layer.draw(label, at: CGPoint(x: rect.minX + 7, y: rect.midY), anchor: .leading)
        }
    }

    /// The bar under the pointer while it is dragged, snapped to the milestone it would land in.
    private func drawDragged() {
        guard let drag, let epicRow = (roadmap.rows + roadmap.later).first(where: { $0.epic.id == drag.epicId }) else { return }
        let top = drag.location.y - TimelineLayout.barHeight / 2
        var width: CGFloat = 0
        var x: CGFloat
        if let target = drag.target {
            let span = layout.span(of: roadmap.windows[target])
            x = span.lowerBound + 2
            width = span.upperBound - span.lowerBound - 4
        } else {
            let bars = layout.bars(of: epicRow)
            width = bars.first?.rect.width ?? 120
            x = drag.location.x - width / 2
        }
        let rect = CGRect(x: x, y: top, width: max(width, 40), height: TimelineLayout.barHeight)
        var shadow = context
        shadow.addFilter(.shadow(color: Theme.shadow, radius: 8, y: 4))
        shadow.fill(Path(roundedRect: rect, cornerRadius: 6, style: .continuous), with: .color(Theme.epicBar))
        drawBar(rect, count: Roadmap.Count(done: epicRow.done, total: epicRow.total), done: doneEpics.contains(epicRow.epic.id), opacity: 1)
        let title = context.resolve(Text(epicRow.epic.title).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textSecondary))
        context.draw(title, in: CGRect(x: rect.minX, y: rect.maxY + 3, width: max(rect.width, 160), height: 14))
    }
}
