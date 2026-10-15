import SwiftUI

// MARK: - Where issues sit in time

/// Where an issue sits on a view's timeline: a stretch from its start to its end, or one day.
enum TimelineSpan: Equatable {
    case stretch(CalendarDay, CalendarDay)
    /// A day, such as a due date, or the day of the milestone the issue is in (`milestone`).
    case day(CalendarDay, milestone: Bool)

    var first: CalendarDay {
        switch self {
        case .stretch(let start, _): start
        case .day(let day, _): day
        }
    }

    var last: CalendarDay {
        switch self {
        case .stretch(_, let end): end
        case .day(let day, _): day
        }
    }
}

/// One line of a view's timeline: a group of the view, or one of its issues.
struct TimelineRow: Identifiable, Equatable {
    enum Kind: Equatable {
        case group(ListSection, folded: Bool)
        case item(Item)
    }

    var id: String
    var kind: Kind
    /// For a group, the stretch its issues cover.
    var span: TimelineSpan?
}

/// How a view shows: GitHub's roadmap layout adds the timeline to board and list.
enum ViewShape: Hashable {
    case timeline
    case board
    case list
}

extension AppModel {
    /// Whether a view shows as a timeline: GitHub's roadmap layout, unless you chose a board or a list for yourself.
    func showsTimeline(_ view: ProjectView) -> Bool {
        view.layout == .roadmap && display(of: view).layout == nil
    }

    func shape(of view: ProjectView) -> ViewShape {
        showsTimeline(view) ? .timeline : layout(of: view) == .board ? .board : .list
    }

    /// Shows a view as a timeline, a board or a list, as your own choice until saved for everyone.
    func setShape(_ shape: ViewShape, of view: ProjectView) {
        switch shape {
        case .timeline:
            changeDisplay(of: view) { $0.layout = nil }
            followLayout(of: view)
        case .board:
            showLayout(.board, projectId: view.projectId)
        case .list:
            showLayout(.list, projectId: view.projectId)
        }
    }

    /// The fields an issue starts and ends on. GitHub doesn't tell which fields a roadmap view uses, so the app takes
    /// what most projects have: a date field named like a start ("Start date", "Beginn") and one named like an end
    /// ("Target date", "Due"), or, with just two date fields, the first as the start and the second as the end. One
    /// date field alone, such as a due date, is a day.
    func timelineDateFields(projectId: String) -> (start: ProjectField?, end: ProjectField?) {
        Self.timelineDateFields(fields(projectId: projectId))
    }

    static func timelineDateFields(_ fields: [ProjectField]) -> (start: ProjectField?, end: ProjectField?) {
        let dates = fields.filter { $0.kind == .date }
        // The words in order of preference: a project with a target date and a due date ends its bars on the target.
        func named(_ words: [String], except other: ProjectField? = nil) -> ProjectField? {
            for word in words {
                if let field = dates.first(where: { $0.id != other?.id && $0.name.lowercased().contains(word) }) { return field }
            }
            return nil
        }
        let start = named(Self.startWords)
        let end = named(Self.endWords, except: start)
        if start != nil || end != nil {
            return (start, end ?? dates.first { $0.id != start?.id && dates.count == 2 })
        }
        if dates.count == 2 { return (dates[0], dates[1]) }
        return (nil, dates.first)
    }

    private static let startWords = ["start", "begin", "début", "debut", "inicio", "início", "начал", "開始", "开始", "시작"]
    private static let endWords = [
        "target", "end", "finish", "ziel", "ende", "término", "fin", "конец", "終了", "结束", "종료",
        "deadline", "due", "fällig", "límite", "prazo", "срок", "期限", "截止", "마감",
    ]

    /// Where an issue sits in time: between its start and end dates, or in its iteration, or on one of those dates,
    /// or on the day of its milestone. Nil when it has none of them.
    func timelineSpan(of item: Item, view: ProjectView, dates: (start: ProjectField?, end: ProjectField?), iteration: ProjectField?) -> TimelineSpan? {
        let context = filterContext(projectId: view.projectId)
        func day(_ field: ProjectField?) -> CalendarDay? {
            field.flatMap { context?.value(of: $0, in: item)?.date }.flatMap(CalendarDay.init)
        }
        let start = day(dates.start)
        let end = day(dates.end)
        if let start, let end { return .stretch(min(start, end), max(start, end)) }
        if let field = iteration, let id = context?.value(of: field, in: item)?.iterationId,
           let span = field.iterations.first(where: { $0.id == id }), let first = span.start, let last = span.end {
            return .stretch(first, last)
        }
        if let day = end ?? start { return .day(day, milestone: false) }
        if let title = milestoneTitle(of: item), let due = milestoneGroup(projectId: view.projectId, title: title)?.due {
            return .day(due, milestone: true)
        }
        return nil
    }

    /// The iteration field a timeline places issues by: the one the view groups or filters by, else the project's
    /// first.
    func timelineIterationField(of view: ProjectView) -> ProjectField? {
        if let field = groupField(of: view), field.kind == .iteration { return field }
        if let pinned = pinnedIteration(of: view) { return pinned.field }
        return fields(projectId: view.projectId).first { $0.kind == .iteration }
    }

    /// A view's lines on the timeline: its groups as the list has them, each with the issues in it unless folded.
    func timelineRows(of view: ProjectView, in scope: Scope? = nil) -> [TimelineRow] {
        let dates = timelineDateFields(projectId: view.projectId)
        let iteration = timelineIterationField(of: view)
        let sections = groupedSections(of: view) ?? sections(for: .project(view.projectId))
        var rows: [TimelineRow] = []
        for section in sections {
            let folded = isFolded(section, in: scope)
            let spans = section.nesting.members.compactMap { timelineSpan(of: $0, view: view, dates: dates, iteration: iteration) }
            let span: TimelineSpan? = if let first = spans.map(\.first).min(), let last = spans.map(\.last).max() {
                .stretch(first, last)
            } else {
                nil
            }
            if sections.count > 1 || !section.title.isEmpty {
                rows.append(TimelineRow(id: "group/" + section.id, kind: .group(section, folded: folded), span: span))
            }
            if !folded {
                for item in section.items {
                    rows.append(TimelineRow(id: section.id + "/" + item.id, kind: .item(item), span: timelineSpan(of: item, view: view, dates: dates, iteration: iteration)))
                }
            }
        }
        return rows
    }
}

// MARK: - Layout

/// Where things sit on a view's timeline: the days it shows and how wide a day is.
struct ViewTimelineLayout {
    static let monthsHeight: CGFloat = 26
    static let milestonesHeight: CGFloat = 28
    static let headerHeight = monthsHeight + milestonesHeight
    static let rowHeight: CGFloat = 34
    static let barHeight: CGFloat = 18

    var rows: [TimelineRow]
    var first: CalendarDay
    var days: Int
    var scale: CGFloat

    init(rows: [TimelineRow], milestones: [CalendarDay], zoom: RoadmapZoom, available: CGFloat, today: CalendarDay = .today()) {
        self.rows = rows
        let ends = rows.compactMap(\.span).flatMap { [$0.first, $0.last] } + milestones
        // A little before today and the earliest date, and a while past the last.
        first = min(ends.min() ?? today, today).adding(days: -10)
        let last = max(ends.max() ?? today, today.adding(days: 30)).adding(days: 14)
        days = max(last.days(from: first) + 1, 1)
        scale = max(zoom.scale, available / CGFloat(days))
    }

    var width: CGFloat { CGFloat(days) * scale }
    var height: CGFloat { Self.headerHeight + CGFloat(rows.count) * Self.rowHeight + 16 }

    func x(_ day: CalendarDay) -> CGFloat {
        CGFloat(day.days(from: first)) * scale
    }

    func rowTop(_ index: Int) -> CGFloat {
        Self.headerHeight + CGFloat(index) * Self.rowHeight
    }

    func row(at y: CGFloat) -> Int? {
        guard y >= Self.headerHeight else { return nil }
        let index = Int((y - Self.headerHeight) / Self.rowHeight)
        return rows.indices.contains(index) ? index : nil
    }

    /// The rectangle a stretch or a day takes in a row.
    func rect(of span: TimelineSpan, top: CGFloat, height: CGFloat = barHeight) -> CGRect {
        let y = top + (Self.rowHeight - height) / 2
        switch span {
        case .stretch(let start, let end):
            return CGRect(x: x(start), y: y, width: max(x(end.adding(days: 1)) - x(start), height), height: height)
        case .day(let day, _):
            return CGRect(x: x(day) + scale / 2 - height / 2, y: y, width: height, height: height)
        }
    }
}

// MARK: - The timeline

/// A view in GitHub's roadmap layout, as a timeline: each issue as a bar from its start to its end, or in its
/// iteration, or as a mark on its date or its milestone's; grouped as the view groups, a folded group as one bar over
/// its issues. The months run along the top, the project's milestones with their days, and today.
struct ViewTimeline: View {
    @Environment(AppModel.self) private var model
    var view: ProjectView
    /// Where folded groups are remembered: the project on the iPad, the scope on screen on the Mac.
    var scope: Scope?
    var nameWidth: CGFloat = 300
    var open: (Item) -> Void
    @State private var hovered: String?

    var body: some View {
        let rows = model.timelineRows(of: view, in: scope)
        let milestones = model.milestoneGroups(projectId: view.projectId).filter(\.isOpen)
        GeometryReader { proxy in
            let layout = ViewTimelineLayout(
                rows: rows, milestones: milestones.compactMap(\.due), zoom: model.roadmapZoom,
                available: max(proxy.size.width - nameWidth - 1, 200)
            )
            // Worked out here, as the drawing doesn't run on the main actor.
            let marks = milestones.map { (group: $0, mark: model.mark(of: $0, projectId: view.projectId)) }
            let looks = Dictionary(rows.compactMap { row -> (String, ItemLook)? in
                guard case .item(let item) = row.kind else { return nil }
                return (item.id, ItemLook(done: model.isDone(item), started: model.glyph(of: item).category == .started))
            }, uniquingKeysWith: { first, _ in first })
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    names(layout)
                        .frame(width: nameWidth)
                    Rectangle().fill(Theme.panelBorder).frame(width: 1, height: layout.height)
                    ScrollView(.horizontal) {
                        Canvas { context, size in
                            ViewTimelinePainter(
                                context: context, size: size, layout: layout, milestones: marks, looks: looks, hovered: hovered
                            ).draw()
                        }
                        .frame(width: layout.width, height: layout.height)
                        .contentShape(Rectangle())
                        .onTapGesture { point in
                            if let index = layout.row(at: point.y) { activate(layout.rows[index]) }
                        }
                        #if os(macOS)
                        .onContinuousHover { phase in
                            if case .active(let point) = phase { hovered = layout.row(at: point.y).map { layout.rows[$0].id } } else { hovered = nil }
                        }
                        #endif
                    }
                    .scrollIndicators(.automatic)
                    .defaultScrollAnchor(.leading)
                }
            }
            .scrollIndicators(.never)
        }
        .animation(Theme.spring, value: rows.map(\.id))
    }

    private func activate(_ row: TimelineRow) {
        switch row.kind {
        case .group(let section, _):
            withAnimation(Theme.spring) { model.toggleSection(section.id, in: scope) }
        case .item(let item):
            open(item)
        }
    }

    // MARK: Names

    private func names(_ layout: ViewTimelineLayout) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: ViewTimelineLayout.headerHeight)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.panelBorder).frame(height: 1) }
            ForEach(layout.rows) { row in
                nameCell(row)
            }
            Spacer(minLength: 16)
        }
        .frame(height: layout.height, alignment: .top)
    }

    @ViewBuilder
    private func nameCell(_ row: TimelineRow) -> some View {
        Button {
            activate(row)
        } label: {
            HStack(spacing: 8) {
                switch row.kind {
                case .group(let section, let folded):
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .rotationEffect(.degrees(folded ? -90 : 0))
                        .frame(width: 10)
                    TimelineGroupIcon(icon: section.groupIcon ?? .status(section.glyph))
                    Text(section.title)
                        .font(.uiSemibold)
                        .foregroundStyle(section.groupIcon == .plain ? Theme.textSecondary : Theme.text)
                        .lineLimit(1)
                    Text(section.countText)
                        .font(.ui)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                case .item(let item):
                    StatusIcon(glyph: model.glyph(of: item), size: 13)
                        .padding(.leading, 18)
                    Text(item.title)
                        .font(.ui)
                        .foregroundStyle(model.isDone(item) ? Theme.textSecondary : Theme.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: ViewTimelineLayout.rowHeight)
            .background {
                if case .group = row.kind {
                    Rectangle().fill(Theme.groupHeader)
                } else if hovered == row.id {
                    Rectangle().fill(Theme.hover.opacity(0.7))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainPressStyle())
        #if os(macOS)
        .onHover { inside in
            if inside { hovered = row.id } else if hovered == row.id { hovered = nil }
        }
        #endif
        .accessibilityLabel(Text(label(of: row)))
        .accessibilityValue(Text(row.span.map(spoken) ?? String(localized: .noDate)))
        .accessibilityIdentifier(identifier(of: row))
    }

    private func identifier(of row: TimelineRow) -> String {
        switch row.kind {
        case .group(let section, _): "timeline-section-\(section.title)"
        case .item(let item): "timeline-row-\(item.displayNumber)"
        }
    }

    private func label(of row: TimelineRow) -> String {
        switch row.kind {
        case .group(let section, _): String(localized: .sectionIssueCount(title: section.title, count: section.count))
        case .item(let item): "\(item.displayNumber) \(item.title)"
        }
    }

    private func spoken(_ span: TimelineSpan) -> String {
        switch span {
        case .stretch(let start, let end):
            "\(start.date().formatted(.dateTime.day().month())) – \(end.date().formatted(.dateTime.day().month()))"
        case .day(let day, _):
            day.date().formatted(.dateTime.day().month())
        }
    }
}

/// The icon at the start of a group's line on the timeline.
private struct TimelineGroupIcon: View {
    var icon: SectionIcon

    var body: some View {
        Group {
            switch icon {
            case .status(let glyph): StatusIcon(glyph: glyph, size: 13)
            case .milestone(let mark): MilestoneIcon(mark: mark, size: 12)
            case .dot(let color): Circle().fill(Theme.optionColor(color) ?? Theme.textTertiary).frame(width: 8, height: 8)
            case .iteration(let current): IterationIcon(size: 13).foregroundStyle(current ? Theme.started : Theme.textSecondary)
            case .person(let person): Avatar(login: person.login, url: person.avatarUrl, size: 16)
            case .progress(let done, let total): ProgressRing(done: done, total: total, size: 13)
            case .epic: EpicIcon(color: Theme.epic)
            case .repository: RepositoryIcon(size: 12).foregroundStyle(Theme.textSecondary)
            case .priority(let level): PriorityIcon(level: level)
            case .plain: EmptyView()
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }
}

// MARK: - Drawing

/// How an issue's bar is coloured: done, under way, or not yet started.
private struct ItemLook {
    var done: Bool
    var started: Bool
}

/// Draws the timeline in one pass: months, milestones, today, and the bars.
private struct ViewTimelinePainter {
    var context: GraphicsContext
    var size: CGSize
    var layout: ViewTimelineLayout
    var milestones: [(group: MilestoneGroup, mark: MilestoneMark)]
    var looks: [String: ItemLook]
    var hovered: String?

    func draw() {
        let today = CalendarDay.today()
        let bottom = layout.rowTop(layout.rows.count)
        for (index, row) in layout.rows.enumerated() {
            let top = layout.rowTop(index)
            if case .group = row.kind {
                context.fill(Path(CGRect(x: 0, y: top, width: size.width, height: ViewTimelineLayout.rowHeight)), with: .color(Theme.groupHeader))
            } else if hovered == row.id {
                context.fill(Path(CGRect(x: 0, y: top, width: size.width, height: ViewTimelineLayout.rowHeight)), with: .color(Theme.hover.opacity(0.7)))
            }
        }
        drawMonths(today: today, bottom: bottom)
        drawMilestones(today: today, bottom: bottom)
        context.fill(Path(CGRect(x: 0, y: ViewTimelineLayout.headerHeight - 1, width: size.width, height: 1)), with: .color(Theme.panelBorder))

        let todayX = layout.x(today) + layout.scale / 2
        if todayX >= 0, todayX <= size.width {
            context.fill(Path(CGRect(x: todayX - 0.75, y: 2, width: 1.5, height: bottom - 2)), with: .color(Theme.accent))
            let label = context.resolve(Text(.today).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.accent))
            context.draw(label, at: CGPoint(x: todayX + 4, y: 7), anchor: .topLeading)
        }

        for (index, row) in layout.rows.enumerated() {
            guard let span = row.span else { continue }
            let top = layout.rowTop(index)
            switch row.kind {
            case .group(let section, _):
                drawGroup(span, progress: section.progress, top: top)
            case .item(let item):
                drawItem(span, item: item, top: top)
            }
        }
    }

    private func drawMonths(today: CalendarDay, bottom: CGFloat) {
        var month = CalendarDay(year: layout.first.year, month: layout.first.month, day: 1)
        let end = layout.first.adding(days: layout.days)
        var firstLabel = true
        while month <= end {
            let x = layout.x(month)
            if x >= 0 {
                context.fill(Path(CGRect(x: x, y: 0, width: 1, height: bottom)), with: .color(Theme.panelBorder.opacity(0.6)))
            }
            let showsYear = firstLabel || month.month == 1
            let text = month.date().formatted(showsYear && month.year != today.year ? .dateTime.month(.abbreviated).year() : .dateTime.month(.abbreviated))
            let resolved = context.resolve(Text(text).font(.system(size: 11)).foregroundStyle(Theme.textTertiary))
            let next = month.adding(months: 1)
            if layout.x(next) - max(x, 0) > 30 {
                context.draw(resolved, at: CGPoint(x: max(x, 0) + 6, y: 7), anchor: .topLeading)
            }
            firstLabel = false
            month = next
        }
    }

    /// The project's open milestones: a diamond with the name on its day, and a dashed line down through the rows.
    private func drawMilestones(today: CalendarDay, bottom: CGFloat) {
        let midY = ViewTimelineLayout.monthsHeight + ViewTimelineLayout.milestonesHeight / 2
        var previousEnd: CGFloat = -.infinity
        for (group, mark) in milestones.sorted(by: { ($0.group.due ?? today) < ($1.group.due ?? today) }) {
            guard let due = group.due else { continue }
            let x = layout.x(due) + layout.scale / 2
            var line = Path()
            line.move(to: CGPoint(x: x, y: ViewTimelineLayout.headerHeight))
            line.addLine(to: CGPoint(x: x, y: bottom))
            context.stroke(line, with: .color(mark.color.opacity(0.55)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            let diamond = CGRect(x: x - 6, y: midY - 6, width: 12, height: 12)
            context.stroke(PlanningGlyph.diamond(in: diamond), with: .color(mark.color), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            if mark == .current || mark == .late || mark == .completed {
                context.fill(PlanningGlyph.diamond(in: diamond, inset: 4), with: .color(mark.color))
            }
            let title = context.resolve(Text(group.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text))
            let width = title.measure(in: CGSize(width: 300, height: 20)).width
            if x - 10 - width > previousEnd + 8 {
                context.draw(title, at: CGPoint(x: x - 10, y: midY), anchor: .trailing)
            }
            previousEnd = x + 6
        }
    }

    /// A group's stretch: a quiet bar over its issues, filled as far as they are done.
    private func drawGroup(_ span: TimelineSpan, progress: GroupProgress?, top: CGFloat) {
        let rect = layout.rect(of: span, top: top, height: 8)
        let shape = Path(roundedRect: rect, cornerRadius: 4)
        context.fill(shape, with: .color(Theme.textTertiary.opacity(0.28)))
        if let progress, progress.total > 0 {
            var clipped = context
            clipped.clip(to: shape)
            let done = rect.width * CGFloat(progress.done) / CGFloat(progress.total)
            let started = rect.width * CGFloat(progress.started) / CGFloat(progress.total)
            clipped.fill(Path(CGRect(x: rect.minX, y: rect.minY, width: done, height: rect.height)), with: .color(Theme.positive))
            clipped.fill(Path(CGRect(x: rect.minX + done, y: rect.minY, width: started, height: rect.height)), with: .color(Theme.started))
        }
    }

    /// An issue's stretch as a bar in its status's colour, or its day as a mark: a diamond for its milestone's day.
    private func drawItem(_ span: TimelineSpan, item: Item, top: CGFloat) {
        let look = looks[item.id] ?? ItemLook(done: false, started: false)
        let done = look.done
        let color = done ? Theme.positive : look.started ? Theme.started : Theme.accent
        switch span {
        case .stretch:
            let rect = layout.rect(of: span, top: top)
            let shape = Path(roundedRect: rect, cornerRadius: 5)
            context.fill(shape, with: .color(color.opacity(done ? 0.18 : 0.22)))
            context.stroke(shape, with: .color(color.opacity(0.55)), lineWidth: 1)
            // The title inside the bar where it fits.
            let title = context.resolve(Text(item.title).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.text))
            if title.measure(in: CGSize(width: 1000, height: 20)).width + 14 <= rect.width {
                var clipped = context
                clipped.clip(to: shape)
                clipped.draw(title, at: CGPoint(x: rect.minX + 7, y: rect.midY), anchor: .leading)
            }
        case .day(_, let milestone):
            let rect = layout.rect(of: span, top: top, height: 12)
            if milestone {
                context.stroke(PlanningGlyph.diamond(in: rect), with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            } else {
                context.fill(Path(ellipseIn: rect.insetBy(dx: 1.5, dy: 1.5)), with: .color(color))
            }
        }
    }
}
