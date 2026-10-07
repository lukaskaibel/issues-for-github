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
    @ScaledMetric(relativeTo: .callout) private var glyphSize: CGFloat = 16
    @ScaledMetric(relativeTo: .callout) private var avatarSize: CGFloat = 24

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            StatusIcon(glyph: model.glyph(of: item), size: glyphSize)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                title
                    .font(.uiMedium)
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
        .padding(.vertical, 10)
        .padding(.leading, 22)
        .padding(.trailing, 18)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("row-\(item.displayNumber)")
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
            // Before the project and labels, so the fade at the end never hides it.
            if let due = model.dueBadge(for: item) {
                MobileChip(tint: due.tone.color) {
                    Image(systemName: "calendar")
                    Text(due.label)
                }
            }
            if showsProject, let project = model.project(of: item) {
                HStack(spacing: 5) {
                    ProjectSwatch(title: project.title, size: 10)
                    Text(project.title)
                }
            }
            if item.subTotal > 0 {
                MobileChip {
                    SubIssueGlyph().frame(width: 11, height: 11)
                    Text("\(item.subCompleted)/\(item.subTotal)").monospacedDigit()
                }
            }
            ForEach(item.labels.prefix(3)) { label in
                MobileChip {
                    Circle().fill(Theme.labelColor(label.color)).frame(width: 7, height: 7)
                    Text(label.name)
                }
            }
        }
        .font(.small)
        .foregroundStyle(Theme.textTertiary)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .mask(LinearGradient(stops: [.init(color: .black, location: 0.86), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
    }

    private var accessibilityText: String {
        var parts = [item.displayNumber, item.title, model.statusOption(of: item)?.name ?? "No status"]
        if let priority = model.priorityOption(of: item)?.name { parts.append("\(priority) priority") }
        if !item.labels.isEmpty { parts.append("labels " + item.labels.map(\.name).joined(separator: ", ")) }
        if !item.assignees.isEmpty { parts.append("assigned to " + item.assignees.map(\.login).joined(separator: ", ")) }
        if let due = model.dueBadge(for: item) { parts.append(due.tooltip) }
        if showsProject, let project = model.project(of: item) { parts.append(project.title) }
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

/// A small outlined capsule, for labels and sub-issue progress in rows.
struct MobileChip<Content: View>: View {
    var tint = Theme.textSecondary
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 5) { content }
            .font(.tiny)
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .frame(minHeight: 20)
            .overlay(Capsule().stroke(Theme.chipBorder, lineWidth: 1))
    }
}

/// The band at the top of a list section: fold arrow, status, name and count, with "+" for a new issue.
struct SectionHeaderBand: View {
    var title: String
    var glyph: StatusGlyph
    var count: Int
    var folded: Bool
    var onToggle: () -> Void
    var onAdd: (() -> Void)?
    @ScaledMetric(relativeTo: .callout) private var glyphSize: CGFloat = 15

    var body: some View {
        HStack(spacing: 9) {
            Button(action: onToggle) {
                HStack(spacing: 9) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .rotationEffect(.degrees(folded ? -90 : 0))
                        .frame(width: 12)
                    StatusIcon(glyph: glyph, size: glyphSize)
                    Text(title).font(.uiSemibold).foregroundStyle(Theme.text)
                    Text("\(count)").font(.ui).monospacedDigit().foregroundStyle(Theme.textTertiary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainPressStyle())
            .accessibilityIdentifier("section-\(title)")
            .accessibilityLabel("\(title), \(count) issue\(count == 1 ? "" : "s")")
            .accessibilityValue(folded ? "Folded" : "Open")
            .accessibilityHint(folded ? "Shows the issues of this section" : "Hides the issues of this section")
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
                .accessibilityLabel("New issue in \(title)")
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, onAdd == nil ? 12 : 4)
        .frame(minHeight: 40)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Theme.groupHeader)
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(glyph.color.opacity(0.08)))
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
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
        .padding(.horizontal, 11)
        .frame(minHeight: 34)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.chipBorder, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
