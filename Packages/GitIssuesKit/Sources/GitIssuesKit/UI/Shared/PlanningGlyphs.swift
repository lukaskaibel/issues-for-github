import SwiftUI

/// How a milestone's diamond reads: the one the board works towards is marked, as in Linear; a completed one is filled.
enum MilestoneMark: Equatable {
    /// Open, after the current one.
    case upcoming
    /// The first open milestone: the one being worked towards.
    case current
    /// The current one, past its due date.
    case late
    case completed
    /// "No milestone".
    case none

    var color: Color {
        switch self {
        case .upcoming: Theme.textSecondary
        case .current: Theme.started
        case .late: Theme.overdue
        case .completed: Theme.accent
        case .none: Theme.textTertiary
        }
    }
}

/// The shapes of planning: a milestone's diamond and an epic's stack of layers, in a 14 pt square, for SwiftUI and
/// Core Graphics alike.
enum PlanningGlyph {
    static func diamond(in rect: CGRect, inset: CGFloat = 1.6) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        var path = Path()
        path.move(to: CGPoint(x: r.midX, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        path.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        path.addLine(to: CGPoint(x: r.minX, y: r.midY))
        path.closeSubpath()
        return path
    }

    /// Three layers, stacked: the top one whole, the two below as their lower edges.
    static func layers(in rect: CGRect) -> Path {
        let s = rect.width / 14
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var path = Path()
        path.move(to: p(7, 1.8))
        path.addLine(to: p(12.4, 4.6))
        path.addLine(to: p(7, 7.4))
        path.addLine(to: p(1.6, 4.6))
        path.closeSubpath()
        path.move(to: p(1.6, 7.2))
        path.addLine(to: p(7, 10))
        path.addLine(to: p(12.4, 7.2))
        path.move(to: p(1.6, 9.8))
        path.addLine(to: p(7, 12.6))
        path.addLine(to: p(12.4, 9.8))
        return path
    }

    /// Draws a milestone's diamond into a Core Graphics context, as the list and menus need.
    static func drawMilestone(_ mark: MilestoneMark, in rect: CGRect, cg context: CGContext) {
        let color = PlatformColor(mark.color).cgColor
        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(color)
        context.setFillColor(color)
        context.setLineWidth(1.5)
        context.setLineJoin(.round)
        let outline = diamond(in: rect).cgPath
        switch mark {
        case .completed:
            context.addPath(outline)
            context.fillPath()
        case .none:
            context.setLineDash(phase: 0, lengths: [2, 2])
            context.addPath(outline)
            context.strokePath()
        case .current, .late:
            context.addPath(outline)
            context.strokePath()
            context.addPath(diamond(in: rect, inset: rect.width * 0.34).cgPath)
            context.fillPath()
        case .upcoming:
            context.addPath(outline)
            context.strokePath()
        }
    }

    static func drawEpic(in rect: CGRect, cg context: CGContext, color: Color = Theme.epic) {
        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(PlatformColor(color).cgColor)
        context.setLineWidth(1.4 * rect.width / 14)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.addPath(layers(in: rect).cgPath)
        context.strokePath()
    }
}

/// A milestone's diamond.
struct MilestoneIcon: View {
    var mark: MilestoneMark
    var size: CGFloat = 14
    /// One colour instead of the mark's, such as white on a selected row of the sidebar.
    var tint: Color?

    var body: some View {
        let color = tint ?? mark.color
        Canvas { context, canvas in
            let rect = CGRect(origin: .zero, size: canvas)
            let outline = PlanningGlyph.diamond(in: rect, inset: rect.width * 0.114)
            let line = StrokeStyle(lineWidth: 1.5 * canvas.width / 14, lineJoin: .round, dash: mark == .none ? [2, 2] : [])
            switch mark {
            case .completed:
                context.fill(outline, with: .color(color))
            case .current, .late:
                context.stroke(outline, with: .color(color), style: line)
                context.fill(PlanningGlyph.diamond(in: rect, inset: rect.width * 0.34), with: .color(color))
            case .upcoming, .none:
                context.stroke(outline, with: .color(color), style: line)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// An epic's stack of layers.
struct EpicIcon: View {
    var size: CGFloat = 14
    var color: Color = Theme.epic

    var body: some View {
        Canvas { context, canvas in
            context.stroke(
                PlanningGlyph.layers(in: CGRect(origin: .zero, size: canvas)), with: .color(color),
                style: StrokeStyle(lineWidth: 1.4 * canvas.width / 14, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The roadmap: a few bars of different length, offset like a timeline.
struct RoadmapIcon: View {
    var size: CGFloat = 14

    var body: some View {
        Canvas { context, canvas in
            let s = canvas.width / 14
            var path = Path()
            path.move(to: CGPoint(x: 2 * s, y: 3.6 * s))
            path.addLine(to: CGPoint(x: 8 * s, y: 3.6 * s))
            path.move(to: CGPoint(x: 5 * s, y: 7 * s))
            path.addLine(to: CGPoint(x: 12.2 * s, y: 7 * s))
            path.move(to: CGPoint(x: 3.2 * s, y: 10.4 * s))
            path.addLine(to: CGPoint(x: 8.6 * s, y: 10.4 * s))
            context.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: 1.6 * s, lineCap: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Done of all, as a ring that fills, like the progress of Linear's projects.
struct ProgressRing: View {
    var done: Int
    var total: Int
    var size: CGFloat = 14
    var color: Color = Theme.epic

    var body: some View {
        let fraction = total > 0 ? Double(done) / Double(total) : 0
        ZStack {
            Circle().stroke(Theme.barOff, lineWidth: 2)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(1)
        .frame(width: size, height: size)
        .animation(Theme.spring, value: fraction)
        .accessibilityHidden(true)
    }
}

/// What stands at the start of a list group's header.
enum SectionIcon: Equatable {
    case status(StatusGlyph)
    case milestone(MilestoneMark)
    case epic
    case plain
    /// An option of a single-select field, in GitHub's colour (GRAY, BLUE…).
    case dot(String)
    /// An iteration; the one under way is marked.
    case iteration(current: Bool)
    case person(Person)
    /// A parent issue, with how far its sub-issues are.
    case progress(done: Int, total: Int)
    case repository
    case priority(PriorityLevel)
    /// A project's glyph in its colour.
    case project(ProjectLook)
    /// A calendar in the colour of a due date: red once passed, orange for today.
    case due(DueTone)
}

extension AppModel {
    /// The icon of a list group: its status, its milestone's diamond, an epic, or nothing for "No epic" and the
    /// roadmap's "Later".
    func sectionIcon(_ section: ListSection, projectId: String?) -> SectionIcon {
        switch section.kind {
        case .status: .status(section.glyph)
        case .epic(let contentId): contentId == nil ? .plain : .epic
        case .milestone(let title):
            title.flatMap { title in projectId.flatMap { milestoneGroup(projectId: $0, title: title) } }
                .map { .milestone(mark(of: $0, projectId: projectId)) } ?? .plain
        case .group, .mine: section.groupIcon ?? .plain
        }
    }

    /// How a milestone's diamond reads on a board.
    func mark(of group: MilestoneGroup, projectId: String?, today: CalendarDay = .today()) -> MilestoneMark {
        guard group.isOpen else { return .completed }
        guard isCurrentMilestone(group, projectId: projectId) else { return .upcoming }
        if let due = group.due, due < today { return .late }
        return .current
    }

    /// The mark of the milestone an issue is in.
    func milestoneMark(of item: Item) -> MilestoneMark {
        guard let group = milestoneGroup(of: item) else { return item.milestoneId == nil ? .none : .upcoming }
        return mark(of: group, projectId: item.projectId)
    }
}

/// How far an epic is, in one bar split by milestone: each part as wide as its share of the issues, filled as far as
/// they are done, with the milestone's name and count under it where there is room.
struct SegmentedProgress: View {
    struct Part {
        var mark: MilestoneMark
        var title: String
        var done: Int
        var total: Int
    }

    var parts: [Part]
    static let gap: CGFloat = 4

    var body: some View {
        let total = max(parts.map(\.total).reduce(0, +), 1)
        GeometryReader { proxy in
            let room = max(proxy.size.width - Self.gap * CGFloat(max(parts.count - 1, 0)), 0)
            HStack(alignment: .top, spacing: Self.gap) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    let width = max(room * CGFloat(part.total) / CGFloat(total), 1)
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: Double(part.done), total: Double(max(part.total, 1)))
                            .progressViewStyle(ThinProgressStyle())
                        HStack(spacing: 5) {
                            MilestoneIcon(mark: part.mark, size: 10)
                            Text(part.title).lineLimit(1)
                            Text("\(part.done)/\(part.total)").monospacedDigit().foregroundStyle(Theme.textTertiary)
                        }
                        .font(.tiny)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize()
                        .frame(width: width, alignment: .leading)
                        .clipped()
                    }
                    .frame(width: width, alignment: .leading)
                    .help(Text("\(part.title) \(part.done)/\(part.total)"))
                }
            }
        }
        .frame(height: 30)
        .accessibilityElement(children: .combine)
    }
}

/// The icon of a view's group or column, for SwiftUI: an option's colour, an iteration, a person, a parent's
/// progress, a repository or a priority. Statuses, milestones and epics have their own.
struct GroupIcon: View {
    var icon: SectionIcon
    var size: CGFloat = 14

    var body: some View {
        switch icon {
        case .status(let glyph): StatusIcon(glyph: glyph, size: size)
        case .milestone(let mark): MilestoneIcon(mark: mark, size: size)
        case .epic: EpicIcon(size: size)
        case .plain: EmptyView()
        case .dot(let color):
            Circle()
                .fill(Theme.optionColor(color) ?? Theme.textTertiary)
                .frame(width: size * 0.62, height: size * 0.62)
                .frame(width: size, height: size)
        case .iteration(let current):
            IterationIcon(size: size)
                .foregroundStyle(current ? Theme.started : Theme.textSecondary)
        case .person(let person):
            Avatar(login: person.login, url: person.avatarUrl, size: size + 2)
        case .progress(let done, let total):
            ProgressRing(done: done, total: total, size: size, color: Theme.positive)
        case .repository:
            RepositoryIcon(size: size - 2).foregroundStyle(Theme.textSecondary)
        case .priority(let level):
            PriorityIcon(level: level)
        case .project(let look):
            ProjectGlyphImage(look: look, size: size)
        case .due(let tone):
            Image(systemName: "calendar")
                .font(.system(size: size * 0.82, weight: .medium))
                .foregroundStyle(tone.color)
                .frame(width: size, height: size)
        }
    }
}

/// GitHub's iterations, its cycles: two arrows going round.
struct IterationIcon: View {
    var size: CGFloat = 14

    var body: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .font(.system(size: size * 0.78, weight: .semibold))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

extension PlanningGlyph {
    /// A parent's progress as a ring, for the Mac's painted list.
    static func drawProgress(done: Int, total: Int, in rect: CGRect, cg context: CGContext) {
        let fraction = total > 0 ? Double(done) / Double(total) : 0
        context.saveGState()
        defer { context.restoreGState() }
        let inset = rect.insetBy(dx: rect.width * 0.14, dy: rect.height * 0.14)
        let width = rect.width * 0.15
        context.setLineWidth(width)
        context.setStrokeColor(PlatformColor(Theme.barOff).cgColor)
        context.strokeEllipse(in: inset)
        guard fraction > 0 else { return }
        context.setStrokeColor(PlatformColor(Theme.positive).cgColor)
        context.setLineCap(.round)
        let center = CGPoint(x: inset.midX, y: inset.midY)
        let start = -CGFloat.pi / 2
        context.addArc(center: center, radius: inset.width / 2, startAngle: start, endAngle: start + 2 * .pi * min(fraction, 1), clockwise: false)
        context.strokePath()
    }

    /// An option's colour as a dot.
    static func drawDot(_ color: String, in rect: CGRect, cg context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        context.setFillColor(PlatformColor(Theme.optionColor(color) ?? Theme.textTertiary).cgColor)
        let side = rect.width * 0.62
        context.fillEllipse(in: CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side))
    }
}

/// The icon of a project field's chip on a row.
struct FieldChipIcon: View {
    var icon: FieldChip.Icon

    var body: some View {
        Group {
            switch icon {
            case .option(let color): Circle().fill(Theme.optionColor(color) ?? Theme.textTertiary).frame(width: 7, height: 7)
            case .iteration: Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 8, weight: .semibold))
            case .date: Image(systemName: "calendar").font(.system(size: 8))
            case .text: Image(systemName: "text.alignleft").font(.system(size: 8))
            }
        }
        .accessibilityHidden(true)
    }
}
