#if os(iOS)
import SwiftUI

// MARK: - Rows

/// One issue in a list: status, title over two lines, and a line of details underneath, with the
/// assignees on the right. The same order as on the Mac, folded for a narrow screen.
struct IssueRow: View {
    @Environment(AppModel.self) private var model
    var item: Item
    /// In My Issues and search, where rows come from several projects.
    var showsProject = false
    /// Part of the title to highlight, for search results.
    var highlight: String? = nil
    /// How the row hangs under a parent in its group.
    var place = Nesting.Place()
    /// How many sub-issues hang under it in its group, folded or not; nil when none do.
    var nested: Int? = nil
    var folded = false
    /// A sub-issue whose parent is in another group names the parent.
    var showsParent = false
    /// The milestone, where the list isn't a milestone's.
    var showsMilestone = true
    /// The epic, where the row isn't in its epic's group.
    var showsEpic = true
    /// The project's own fields the view shows, such as an iteration.
    var chips: [FieldChip] = []
    @ScaledMetric(relativeTo: .body) private var glyphSize: CGFloat = 20
    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 26

    /// Sub-issues hang this much further in per level, down to a few levels.
    static let indent: CGFloat = 18
    static let deepestIndent = 3
    static let leading: CGFloat = 22

    var body: some View {
        let indent = CGFloat(min(place.depth, Self.deepestIndent)) * Self.indent
        HStack(alignment: .top, spacing: 12) {
            StatusIcon(glyph: model.glyph(of: item), size: glyphSize)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                title
                    .font(.body)
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                details
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !item.assignees.isEmpty {
                AvatarStack(people: item.assignees, size: avatarSize)
                    .padding(.top, 1)
            }
        }
        .padding(.vertical, 11)
        .padding(.leading, Self.leading + indent)
        .padding(.trailing, 18)
        .background(alignment: .topLeading) {
            if place.depth > 0 || nested != nil { tree }
        }
        // A hairline from where the title starts, as between Reminders' rows.
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.rowSeparator).frame(height: 1).padding(.leading, Self.leading + indent + glyphSize + 12)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("row-\(item.displayNumber)")
    }

    /// Lines from the parents above down to this row, and from this row down to its own sub-issues, with the
    /// arrow that folds them left of the status icon.
    private var tree: some View {
        let depth = min(place.depth, Self.deepestIndent)
        let midY = 13 + glyphSize / 2
        let statusX = Self.leading + CGFloat(depth) * Self.indent
        return Canvas { context, size in
            var path = Path()
            for level in 0..<depth {
                let lineX = Self.leading + CGFloat(level) * Self.indent + glyphSize / 2
                let continues = place.continues.indices.contains(level) && place.continues[level]
                if level < depth - 1 {
                    if continues {
                        path.move(to: CGPoint(x: lineX, y: 0))
                        path.addLine(to: CGPoint(x: lineX, y: size.height))
                    }
                    continue
                }
                if continues {
                    path.move(to: CGPoint(x: lineX, y: 0))
                    path.addLine(to: CGPoint(x: lineX, y: size.height))
                    path.move(to: CGPoint(x: lineX, y: midY))
                } else {
                    path.move(to: CGPoint(x: lineX, y: 0))
                    path.addLine(to: CGPoint(x: lineX, y: midY - 5))
                    path.addQuadCurve(to: CGPoint(x: lineX + 5, y: midY), control: CGPoint(x: lineX, y: midY))
                }
                path.addLine(to: CGPoint(x: statusX - 4, y: midY))
            }
            if nested != nil, !folded {
                let lineX = statusX + glyphSize / 2
                path.move(to: CGPoint(x: lineX, y: midY + glyphSize / 2 + 4))
                path.addLine(to: CGPoint(x: lineX, y: size.height))
            }
            context.stroke(path, with: .color(Theme.treeLine), lineWidth: 1)
            if nested != nil {
                context.draw(
                    Text(Image(systemName: folded ? "chevron.right" : "chevron.down"))
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.textSecondary),
                    at: CGPoint(x: statusX - 11, y: midY), anchor: .center
                )
            }
        }
        .accessibilityHidden(true)
    }

    private var title: Text {
        guard let highlight, !highlight.isEmpty,
              let range = item.title.range(of: highlight, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return Text(item.title)
        }
        let match = Text(item.title[range]).foregroundStyle(Theme.accent).fontWeight(.semibold)
        return Text("\(Text(item.title[..<range.lowerBound]))\(match)\(Text(item.title[range.upperBound...]))")
    }

    private var details: some View {
        HStack(spacing: 7) {
            if model.project(of: item)?.priorityFieldId != nil {
                PriorityIcon(level: model.priorityLevel(of: item))
            }
            Text(item.displayNumber)
                .monospacedDigit()
            if item.kind == .pullRequest {
                Image(systemName: "arrow.triangle.pull")
            }
            let epicParent = item.parentId.flatMap { model.issue(contentId: $0) }.flatMap { $0.isEpic ? $0 : nil }
            if showsParent, let parent = item.parentNumber, epicParent == nil {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.turn.left.up")
                    Text("#\(parent)").monospacedDigit()
                }
            }
            // Before the project and labels, so the fade at the end never hides it.
            if let due = model.dueBadge(for: item) {
                MobileChip(tint: due.tone.color) {
                    Image(systemName: "calendar")
                    Text(due.label)
                }
            }
            if showsParent, let epic = epicParent {
                // An epic by its icon and name, like a project in Linear; a long name gives way to what follows.
                HStack(spacing: 4) {
                    EpicIcon(size: 11)
                    Text(epic.title).truncationMode(.tail)
                }
                .frame(maxWidth: 160, alignment: .leading)
            }
            if showsProject, let project = model.project(of: item) {
                HStack(spacing: 5) {
                    ProjectIcon(projectId: project.id, size: 10)
                    Text(project.title)
                }
            } else if showsProject, !item.isOnBoard, let repo = item.repoShortName {
                // On no board: where the issue lives instead.
                HStack(spacing: 4) {
                    RepositoryIcon(size: 9)
                    Text(repo)
                }
            }
            if item.blockedByCount > 0 {
                MobileChip { BlockedIcon(size: 9) }
            }
            if item.subTotal > 0 {
                MobileChip {
                    SubIssueGlyph().frame(width: 11, height: 11)
                    Text("\(item.subCompleted)/\(item.subTotal)").monospacedDigit()
                }
            }
            if showsMilestone, let milestone = model.milestoneTitle(of: item) {
                MobileChip {
                    MilestoneIcon(mark: model.milestoneMark(of: item), size: 9)
                    Text(milestone)
                }
            }
            ForEach(chips, id: \.self) { chip in
                MobileChip {
                    FieldChipIcon(icon: chip.icon)
                    Text(chip.text)
                }
            }
            // An epic's own label says what the row shows already.
            ForEach(item.labels.filter { !(item.isEpic && Item.isEpicLabel($0.name)) }.prefix(3)) { label in
                MobileChip(tint: Theme.textBody, fill: Theme.labelColor(label.color).opacity(0.14)) {
                    Circle().fill(Theme.labelColor(label.color)).frame(width: 7, height: 7)
                    Text(label.name)
                }
            }
        }
        .font(.footnote)
        .foregroundStyle(Theme.textTertiary)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        // Exactly as wide as the row, however many chips there are: without the minimum, a line of chips wider
        // than the row would widen the row instead of fading out at its end.
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .clipped()
        .mask(LinearGradient(stops: [.init(color: .black, location: 0.86), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
    }

    private var accessibilityText: String {
        let status = item.isOnBoard
            ? model.statusOption(of: item)?.name ?? String(localized: .noStatus)
            : String(localized: item.isClosed ? LocalizedStringResource.stateClosed : .noProject)
        var parts = [item.displayNumber, item.title, status]
        let epic = model.epic(of: item)
        // Right under an epic, the epic says it (or its group does).
        if let parent = item.parentNumber, epic?.contentId != item.parentId {
            parts.append(String(localized: .subIssueOf(number: "#\(parent)")))
        }
        if let nested, folded { parts.append(String(localized: .unfoldSubIssuesTooltip(count: nested))) }
        if let priority = model.priorityOption(of: item)?.name { parts.append(String(localized: .priorityLevelSpoken(priority: priority))) }
        if item.blockedByCount > 0 { parts.append(String(localized: .blockedSpoken)) }
        if !item.labels.isEmpty {
            parts.append(String(localized: .labelsSpoken(labels: item.labels.map(\.name).joined(separator: ", "))))
        }
        if !item.assignees.isEmpty {
            parts.append(String(localized: .assignedToSpoken(names: item.assignees.map(\.login).joined(separator: ", "))))
        }
        if let due = model.dueBadge(for: item) { parts.append(due.tooltip) }
        if showsMilestone, let milestone = model.milestoneTitle(of: item) {
            parts.append(String(localized: .milestoneTooltip(milestone: milestone)))
        }
        if showsEpic, let epic { parts.append(String(localized: .epicTooltip(epic: epic.title))) }
        parts += chips.map(model.spokenChip)
        if showsProject, let place = model.project(of: item)?.title ?? item.repoShortName { parts.append(place) }
        return parts.joined(separator: ", ")
    }
}

/// A list row that highlights while pressed, as a system row does, without tinting its text.
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.selected : Color.clear)
            .contentShape(Rectangle())
            .hoverEffect(.highlight)
    }
}

/// A small part of a row's line of details: a symbol and text, as Reminders writes a date; a label in a capsule
/// tinted with its colour.
struct MobileChip<Content: View>: View {
    var tint = Theme.textSecondary
    var fill: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 4) { content }
            .font(.caption.weight(fill == nil ? .regular : .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, fill == nil ? 0 : 8)
            .padding(.vertical, 2)
            .frame(minHeight: 20)
            .background { if let fill { Capsule().fill(fill) } }
    }
}

/// The header over the issues of an epic standing together in a list's section: the arrow that folds them away
/// left of the epic's icon, as sub-issues fold, the icon where the issues' status icons stand and the line down to
/// them starts, its name on up to two lines and how many of its issues are there. A tap opens the epic, one on the
/// arrow or the icon folds its issues or shows them again; touching and holding offers its menu.
struct EpicGroupRow: View {
    @Environment(AppModel.self) private var model
    var group: Nesting.EpicGroup
    /// The board's column the section shows, whose issues of the epic its menu can move.
    var column: BoardColumn?
    var open: () -> Void
    @ScaledMetric(relativeTo: .callout) private var glyphSize: CGFloat = 16

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Button {
                model.toggleEpicGroup(group)
            } label: {
                HStack(spacing: 0) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .rotationEffect(.degrees(group.folded ? -90 : 0))
                        .frame(width: IssueRow.leading)
                    EpicIcon(size: glyphSize)
                }
                .frame(height: glyphSize)
                .padding(.top, 12)
                .padding(.bottom, 6)
                .padding(.trailing, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(group.folded ? .unfoldEpicGroupTooltip(count: group.count) : .foldEpicGroupTooltip))
            .accessibilityIdentifier("fold-epic-\(group.epic.title)")
            Button(action: open) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(group.epic.title)
                        .font(.uiSemibold)
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text("\(group.count)")
                        .font(.ui)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                    Spacer(minLength: 0)
                }
                .padding(.top, 12)
                .padding(.bottom, 6)
                .padding(.trailing, 18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(.epicGroupSpoken(epic: group.epic.title, count: group.count)))
            .accessibilityValue(Text(group.folded ? .sectionFolded : .sectionOpen))
            .accessibilityIdentifier("epic-group-\(group.epic.title)")
        }
        .background(alignment: .topLeading) {
            // The start of the line down to the epic's issues.
            if !group.folded {
                Rectangle()
                    .fill(Theme.treeLine)
                    .frame(width: 1)
                    .padding(.top, 12 + glyphSize + 3)
                    .padding(.leading, IssueRow.leading + glyphSize / 2 - 0.5)
            }
        }
        .contextMenu {
            EpicGroupMenuItems(group: group, column: column, open: open)
        }
    }
}

/// The header over the issues of an epic standing together in a column of the iPad's board: its icon where the
/// line to them starts, its name on up to three lines, how many of its issues are there, and the arrow that folds
/// them away. As in the list, a tap opens the epic and one on the arrow folds its issues; touching and holding
/// offers its menu, and dragging it moves them all.
struct EpicGroupCardHeader: View {
    @Environment(AppModel.self) private var model
    var group: Nesting.EpicGroup
    var column: BoardColumn
    var open: () -> Void
    /// Moves the epic's issues to the column beside this one, for VoiceOver, which can't drag.
    var step: (Int) -> Void = { _ in }
    @ScaledMetric(relativeTo: .subheadline) private var line: CGFloat = 20

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Button(action: open) {
                HStack(alignment: .top, spacing: 6) {
                    EpicIcon(size: 13)
                        .frame(width: CardTreeLines.indent, height: line)
                    Text(group.epic.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(group.count)")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(.epicGroupSpoken(epic: group.epic.title, count: group.count)))
            .accessibilityValue(Text(group.folded ? .sectionFolded : .sectionOpen))
            .accessibilityAction(named: Text(.moveToNextStatus)) { step(1) }
            .accessibilityAction(named: Text(.moveToPreviousStatus)) { step(-1) }
            .accessibilityIdentifier("epic-group-\(group.epic.title)")
            Button {
                model.toggleEpicGroup(group)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .rotationEffect(.degrees(group.folded ? -90 : 0))
                    .frame(width: 40, height: line + 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .accessibilityLabel(Text(group.folded ? .unfoldEpicGroupTooltip(count: group.count) : .foldEpicGroupTooltip))
            .accessibilityIdentifier("fold-epic-\(group.epic.title)")
        }
        .frame(minHeight: 32)
        .background(alignment: .topLeading) {
            // The start of the line down to the epic's issues, from under its icon.
            if !group.folded {
                Rectangle()
                    .fill(Theme.treeLine)
                    .frame(width: 1)
                    .padding(.top, 6 + line / 2 + 9)
                    .offset(x: CardTreeLines.indent / 2 - 0.5)
            }
        }
        .contextMenu {
            EpicGroupMenuItems(group: group, column: column, open: open)
        }
    }
}

/// The menu of the header over an epic's issues: open the epic, move all of its issues there to another column, fold
/// them away or show them.
struct EpicGroupMenuItems: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    var group: Nesting.EpicGroup
    var column: BoardColumn?
    var open: () -> Void

    var body: some View {
        Button(action: open) { Label(.openEpicCommand, systemImage: "square.stack.3d.up") }
        if let column {
            let members = column.members(of: group)
            let projectId = members.first?.projectId
            let statuses = model.statusOptions(projectId: projectId)
            if !statuses.isEmpty {
                Menu {
                    Picker(.moveEpicIssuesTo, selection: Binding(
                        get: { column.option?.id },
                        set: { id in
                            guard let option = statuses.first(where: { $0.id == id }) else { return }
                            model.setStatus(of: group, members: members, to: option)
                        }
                    )) {
                        ForEach(statuses) { option in
                            Label {
                                Text(option.name)
                            } icon: {
                                MenuImages.status(model.glyph(projectId: projectId, optionId: option.id), scheme)
                            }
                            .tag(Optional(option.id))
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label {
                        Text(.moveEpicIssuesTo)
                    } icon: {
                        MenuImages.status(column.glyph, scheme)
                    }
                }
            }
        }
        Button {
            model.toggleEpicGroup(group)
        } label: {
            Label(group.folded ? LocalizedStringResource.showEpicIssues : .foldEpicIssues, systemImage: group.folded ? "chevron.down" : "chevron.right")
        }
    }
}

/// The band at the top of a list section: fold arrow, status, name and count, with "+" for a new issue.
struct SectionHeaderBand: View {
    var title: String
    var glyph: StatusGlyph
    var icon: SectionIcon? = nil
    /// Quiet text after the count, such as when a milestone is due.
    var detail: String? = nil
    var count: Int
    /// What the header shows for the count, such as "4/6" for a group with its progress.
    var countText: String? = nil
    var folded: Bool
    /// A view's group with its progress, or a person's load, as a bar before the "+".
    var bar: (style: GroupStyle, progress: GroupProgress, share: CGFloat)? = nil
    var onToggle: () -> Void
    var onAdd: (() -> Void)?
    @ScaledMetric(relativeTo: .title3) private var glyphSize: CGFloat = 18
    @Environment(\.wideLayout) private var wide

    /// Folded or open, and for a group with its progress how far it is, which its bar shows.
    private var spokenValue: Text {
        let state = Text(folded ? LocalizedStringResource.sectionFolded : .sectionOpen)
        guard let bar, bar.style == .progress else { return state }
        return state + Text(verbatim: ", ") + Text(.milestoneProgressTooltip(done: bar.progress.done, total: bar.progress.total))
    }

    var body: some View {
        HStack(spacing: 9) {
            Button(action: onToggle) {
                HStack(spacing: 9) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .rotationEffect(.degrees(folded ? -90 : 0))
                        .frame(width: 12)
                    GroupIcon(icon: icon ?? .status(glyph), size: glyphSize)
                    Text(title).font(.title3.weight(.bold)).foregroundStyle(icon == .plain ? Theme.textSecondary : Theme.text).lineLimit(1)
                    Text(countText ?? "\(count)").font(.body).monospacedDigit().foregroundStyle(Theme.textTertiary)
                    if let detail {
                        Text(detail).font(.small).foregroundStyle(Theme.textTertiary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if let bar, bar.style != .plain {
                        GroupBar(style: bar.style, progress: bar.progress, share: bar.share, width: wide ? 120 : 56)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainPressStyle())
            .accessibilityIdentifier("section-\(title)")
            .accessibilityLabel(.sectionIssueCount(title: title, count: count))
            .accessibilityValue(spokenValue)
            .accessibilityHint(folded ? LocalizedStringResource.showsSectionIssues : .hidesSectionIssues)
            if let onAdd {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainPressStyle())
                .accessibilityIdentifier("add-\(title)")
                .accessibilityLabel(.newIssueInStatus(status: title))
            }
        }
        // A plain heading, as Reminders heads the parts of a list; opaque, so rows don't show through it while it is
        // pinned.
        .padding(.leading, 10)
        .padding(.trailing, onAdd == nil ? 20 : 10)
        .padding(.top, 14)
        .padding(.bottom, 4)
        .frame(minHeight: 44)
        .background(Theme.panel)
        .animation(Theme.quick, value: folded)
    }
}

/// An empty or waiting screen: a line of explanation, sometimes with a spinner or a button.
struct MobileEmptyState<Accessory: View>: View {
    var title: String
    var message: String
    var systemImage: String?
    var showsProgress = false
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(spacing: 10) {
            if showsProgress {
                ProgressView().padding(.bottom, 4)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.bottom, 4)
            }
            Text(title).font(.headline).foregroundStyle(Theme.text)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            accessory.padding(.top, 6)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension MobileEmptyState where Accessory == EmptyView {
    init(title: String, message: String, systemImage: String? = nil, showsProgress: Bool = false) {
        self.init(title: title, message: message, systemImage: systemImage, showsProgress: showsProgress) { EmptyView() }
    }
}

// MARK: - Properties

/// A property of an issue as a chip under its title: icon and value, outlined like the Mac's chips.
struct PropertyChip<Icon: View>: View {
    var text: String
    var placeholder = false
    /// A colour for the text in place of the usual one, such as red for a date that has passed.
    var tint: Color? = nil
    @ViewBuilder var icon: Icon

    var body: some View {
        HStack(spacing: 7) {
            icon
            Text(text)
                .foregroundStyle(placeholder ? Theme.textTertiary : tint ?? Theme.text)
                .lineLimit(1)
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 12)
        .frame(minHeight: 34)
        // A glass capsule, as iOS draws buttons that float over a page.
        .glassPanel(in: Capsule())
        .contentShape(Capsule())
    }
}

/// The sync state as a dot and a line, for the account sheet.
struct SyncStatusLine: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 20)) { context in
            HStack(spacing: 8) {
                Group {
                    if model.status.phase == .syncing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Circle().fill(model.syncDotColor).frame(width: 8, height: 8)
                    }
                }
                .frame(minWidth: 8)
                Text(model.syncLine(at: context.date))
                    .font(.footnote)
                    .foregroundStyle(model.status.phase == .offline ? Theme.text : Theme.textSecondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

extension Item {
    var webURL: URL? { url.flatMap(URL.init(string:)) }
}
#endif
