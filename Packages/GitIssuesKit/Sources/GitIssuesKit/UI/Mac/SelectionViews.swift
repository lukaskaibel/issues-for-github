#if os(macOS)
import SwiftUI

/// The bar that floats at the bottom while issues are picked, as in Linear: how many, the changes that apply
/// to all of them, and a way out.
struct SelectionBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let items = model.selectedItems
        if let first = items.first {
            HStack(spacing: 4) {
                HStack(spacing: 6) {
                    Text("\(items.count) selected").font(.uiMedium).monospacedDigit()
                    Button {
                        model.clearSelection()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 18, height: 18)
                            .hoverFill(radius: 9)
                    }
                    .buttonStyle(PlainPressStyle())
                    .help("Clear selection (Esc)")
                }
                .padding(.leading, 12)
                .padding(.trailing, 6)

                Rectangle().fill(Theme.popoverBorder).frame(width: 1, height: 18)

                // The icons show the picked issues' value when they share one.
                let sameStatus = Set(items.map { model.statusOption(of: $0)?.name ?? "" }).count == 1
                let samePriority = Set(items.map { model.priorityLevel(of: $0) }).count == 1
                BarAction(kind: .status, item: first, title: "Status", key: "S") {
                    StatusIcon(glyph: sameStatus ? model.glyph(of: first) : .none, size: 13)
                }
                if model.project(of: first)?.priorityFieldId != nil {
                    BarAction(kind: .priority, item: first, title: "Priority", key: "P") {
                        PriorityIcon(level: samePriority ? model.priorityLevel(of: first) : .none)
                    }
                }
                if items.contains(where: { $0.kind != .draft }) {
                    BarAction(kind: .assignees, item: first, title: "Assignee", key: "A") {
                        Image(systemName: "person.crop.circle").font(.system(size: 13))
                    }
                    BarAction(kind: .labels, item: first, title: "Labels", key: "L") {
                        Image(systemName: "tag").font(.system(size: 12))
                    }
                }
                Button {
                    model.copyLinks(items)
                } label: {
                    Image(systemName: "link")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 30, height: 30)
                        .hoverFill(radius: 7)
                }
                .buttonStyle(PlainPressStyle())
                .help("Copy links (⌘⇧C)")
                .padding(.trailing, 4)
            }
            .foregroundStyle(Theme.textBody)
            .frame(height: 40)
            .background(Capsule().fill(Theme.popover))
            .overlay(Capsule().stroke(Theme.popoverBorder, lineWidth: 1))
            .shadow(color: Theme.shadow, radius: 24, y: 10)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// One change in the selection bar. Its dropdown acts on every picked issue.
private struct BarAction<Icon: View>: View {
    var kind: PickerKind
    var item: Item
    var title: String
    var key: String
    @ViewBuilder var icon: Icon

    @State private var open = false

    var body: some View {
        Button {
            open = true
        } label: {
            HStack(spacing: 6) {
                icon.frame(width: 14, height: 14)
                Text(title)
            }
            .font(.small)
            .padding(.horizontal, 9)
            .frame(height: 30)
            .hoverFill(active: open, radius: 7)
        }
        .buttonStyle(PlainPressStyle())
        .help("\(title) (\(key))")
        .dropdown(isPresented: $open) { close in
            ItemPicker(kind: kind, itemId: item.id, close: close)
        }
    }
}

// MARK: - Peek

/// Space: a quick look at an issue on top of the board or list, without leaving it. Moving with the
/// keyboard moves the peek along; Space or Escape puts it away, Return opens the issue.
struct PeekPanel: View {
    @Environment(AppModel.self) private var model
    var item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if let project = model.project(of: item) {
                    ProjectSwatch(title: project.title, size: 10)
                }
                Text(item.displayNumber).font(.small).monospacedDigit().foregroundStyle(Theme.textSecondary)
                if let repo = item.repoShortName {
                    Text(repo).font(.small).foregroundStyle(Theme.textTertiary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Button("Open") { model.open(item) }
                    .buttonStyle(SecondaryButtonStyle())
                    .help("Open the issue (↵)")
                IconButton(systemName: "xmark", label: "Close (Space)") { model.togglePeek() }
            }
            .padding(.leading, 16)
            .padding(.trailing, 10)
            .frame(height: 44)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.popoverBorder).frame(height: 1) }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(item.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .onTapGesture { model.open(item) }

                    properties

                    if item.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("No description").foregroundStyle(Theme.textTertiary)
                    } else {
                        MarkdownText(text: item.body)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)

            HStack(spacing: 14) {
                hint("Space", "close")
                hint("J K", "next")
                hint("↵", "open")
                Spacer()
                if let updated = item.updatedAt {
                    Text("Updated \(relativeDate(updated))").font(.tiny).foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 36)
            .overlay(alignment: .top) { Rectangle().fill(Theme.popoverBorder).frame(height: 1) }
        }
        .frame(width: 460)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.popover))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.popoverBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Theme.shadow, radius: 30, y: 12)
    }

    /// Status, priority, assignees, labels and sub-issues, each changeable in place.
    private var properties: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                PropertyButton(kind: .status, item: item) {
                    HStack(spacing: 6) {
                        StatusIcon(glyph: model.glyph(of: item))
                        Text(model.statusOption(of: item)?.name ?? "No status")
                    }
                    .font(.small)
                }
                if model.project(of: item)?.priorityFieldId != nil {
                    PropertyButton(kind: .priority, item: item) {
                        HStack(spacing: 6) {
                            PriorityIcon(level: model.priorityLevel(of: item))
                            Text(model.priorityOption(of: item)?.name ?? "No priority")
                        }
                        .font(.small)
                    }
                }
                if item.kind != .draft {
                    PropertyButton(kind: .assignees, item: item) {
                        HStack(spacing: 6) {
                            if item.assignees.isEmpty {
                                Image(systemName: "person.crop.circle.dashed").foregroundStyle(Theme.textTertiary)
                                Text("Unassigned").foregroundStyle(Theme.textTertiary)
                            } else {
                                AvatarStack(people: item.assignees, size: 16)
                                Text(item.assignees.count == 1 ? item.assignees[0].login : "\(item.assignees.count) people")
                            }
                        }
                        .font(.small)
                    }
                }
            }
            if item.kind != .draft || item.subTotal > 0 {
                HStack(spacing: 6) {
                    if item.kind != .draft {
                        PropertyButton(kind: .labels, item: item) {
                            HStack(spacing: 6) {
                                if item.labels.isEmpty {
                                    Image(systemName: "tag").foregroundStyle(Theme.textTertiary)
                                    Text("Add label").foregroundStyle(Theme.textTertiary)
                                } else {
                                    ForEach(item.labels) { LabelChip(label: $0) }
                                }
                            }
                            .font(.small)
                        }
                    }
                    if item.subTotal > 0 {
                        SubIssueChip(completed: item.subCompleted, total: item.subTotal)
                    }
                }
            }
        }
        .padding(.leading, -8)
        .foregroundStyle(Theme.textBody)
    }

    private func hint(_ keys: String, _ action: String) -> some View {
        HStack(spacing: 5) {
            Keycap(keys)
            Text(action).font(.tiny).foregroundStyle(Theme.textTertiary)
        }
    }
}
#endif
