#if os(macOS)
import SwiftUI

/// A searchable list driven entirely from the keyboard: type to filter, arrows to move, Return to pick.
/// A pick closes it, so one change is one click or one key.
struct PickerList: View {
    var placeholder: String
    var items: [PickerItem]
    /// The key that opens this picker from the board, shown at the end of the search field.
    var hint: String? = nil
    /// People and labels: several can be picked. A click or Return still picks one and closes; the checkbox at
    /// the start of a row, Shift with a click or Shift-Return pick it and keep the list open for the next.
    var multiple = false
    var width: CGFloat = 260
    var maxRows = 9
    var fieldFont: Font = .ui
    /// In the command palette: a field as large as Spotlight's.
    var large = false
    /// Rows for what is typed, in place of filtering `items`, for pickers that read the text (dates).
    var search: ((String) -> [PickerItem])? = nil
    /// Single-choice pickers open on the current value; others on the first row that isn't checked.
    var opensOnSelection = true
    /// How many rows are drawn at most, for lists of issues that can run into the thousands.
    var limit = Int.max
    /// A row that makes what is typed, such as a label the repository doesn't have yet.
    var creating: ((String) -> PickerItem?)? = nil
    var onQueryChange: (String) -> Void = { _ in }
    var onPick: (String) -> Void
    var onClose: () -> Void

    @State private var query = ""
    /// The lit row, by its place in the list.
    @State private var cursor = MenuCursor<Int>(0)
    @FocusState private var focused: Bool

    var body: some View {
        let visible = filtered
        VStack(spacing: 0) {
            // A search field on top, as Spotlight has one; the key that opens the picker at its end.
            HStack(spacing: large ? 10 : 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: large ? 16 : 12, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                TextField(placeholder, text: $query)
                    .textFieldStyle(.plain)
                    .font(fieldFont)
                    .focused($focused)
                    .focusOnAppear()
                if let hint {
                    Text(hint).font(.small).foregroundStyle(Theme.textTertiary)
                }
            }
                .padding(.horizontal, large ? 14 : 10)
                .frame(height: large ? 46 : 32)
                .background(RoundedRectangle(cornerRadius: large ? 13 : 9, style: .continuous).fill(Theme.field))
                .padding([.horizontal, .top], large ? 10 : 6)
                .onKeyPress(.downArrow) {
                    cursor.moveByKeys(to: min((cursor.key ?? -1) + 1, max(visible.count - 1, 0)))
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    cursor.moveByKeys(to: max((cursor.key ?? 0) - 1, 0))
                    return .handled
                }
                .onKeyPress(.escape) {
                    onClose()
                    return .handled
                }
                .onKeyPress(phases: .down) { press in
                    // Number keys pick directly while nothing has been typed.
                    guard query.isEmpty, let item = items.first(where: { $0.shortcut == press.characters }) else { return .ignored }
                    pick(item)
                    return .handled
                }
                .onKeyPress(.return, phases: .down) { press in
                    // Shift-Return picks and stays open, ready for the next name; plain Return is the submit below.
                    guard multiple, press.modifiers.contains(.shift), let index = cursor.key, visible.indices.contains(index) else { return .ignored }
                    pick(visible[index], keepOpen: true)
                    query = ""
                    return .handled
                }
                .onSubmit {
                    if let index = cursor.key, visible.indices.contains(index) { pick(visible[index]) }
                }
            PickerRows(visible: visible, cursor: cursor, multiple: multiple, maxRows: maxRows) { item, keepOpen in
                pick(item, keepOpen: keepOpen)
            }
        }
        .frame(width: width)
        .font(.ui)
        .foregroundStyle(Theme.text)
        .onAppear {
            focused = true
            // Single-choice pickers start on the current value, so Return keeps it.
            if multiple {
                return
            } else if opensOnSelection, let current = items.firstIndex(where: \.selected) {
                cursor.moveByKeys(to: current)
            } else if !opensOnSelection, let first = items.firstIndex(where: { !$0.selected }) {
                cursor.moveByKeys(to: first)
            }
        }
        .onChange(of: query) {
            // The first match lit, and scrolled to.
            cursor.moveByKeys(to: 0)
            onQueryChange(query)
        }
    }

    private var filtered: [PickerItem] {
        if let search, !query.isEmpty { return search(query) }
        let rows = matching(query, in: items, creating: query.isEmpty ? nil : creating?(query))
        guard rows.count > limit else { return rows }
        // Rows that are always there stay, after the best matches.
        let kept = rows.filter(\.alwaysShown)
        return Array(rows.filter { !$0.alwaysShown }.prefix(limit - kept.count)) + kept
    }

    private func pick(_ item: PickerItem, keepOpen: Bool = false) {
        onPick(item.id)
        if !keepOpen { onClose() }
    }
}

/// A picker's rows, scrolling when there are more than fit. Apart from the search field above, so moving the light
/// with the keys redraws the list and not the search behind it.
private struct PickerRows: View {
    var visible: [PickerItem]
    var cursor: MenuCursor<Int>
    var multiple: Bool
    var maxRows: Int
    var onPick: (_ item: PickerItem, _ keepOpen: Bool) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { position, item in
                        PickerRow(item: item, cursor: cursor, position: position, onCheck: multiple && !item.creates ? { onPick(item, true) } : nil)
                            .id(item.id)
                            .onTapGesture {
                                onPick(item, multiple && !NSEvent.modifierFlags.isDisjoint(with: [.shift, .command]))
                            }
                            .onHover { if $0 { cursor.key = position } }
                    }
                    if visible.isEmpty {
                        Text(.noMatches)
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 15)
                            .frame(height: PickerRow.height)
                    }
                }
                .padding(.vertical, 6)
            }
            .scrollIndicators(.never)
            .frame(height: min(CGFloat(max(visible.count, 1)), CGFloat(maxRows)) * PickerRow.height + 12)
            .onChange(of: cursor.keyMoves) {
                // Only for the keys: the pointer is on its row already, and scrolling would move the row away from it.
                if let index = cursor.key, visible.indices.contains(index) { proxy.scrollTo(visible[index].id) }
            }
        }
    }
}

struct PickerRow: View {
    /// Taller than a menu's rows, so they are easy to hit, as in Linear.
    static let height: CGFloat = 30

    var item: PickerItem
    var cursor: MenuCursor<Int>
    /// Its place in the list, which the cursor goes by.
    var position: Int
    /// In pickers that take several values: picks the row without closing, from a checkbox at its start.
    var onCheck: (() -> Void)? = nil

    var body: some View {
        let active = cursor.isLit(position)
        HStack(spacing: 10) {
            if let onCheck {
                // Ticked when picked; on the row under the pointer or keyboard an empty box offers it.
                PickerCheckbox(checked: item.selected)
                    .opacity(item.selected || active ? 1 : 0)
                    .frame(width: 22, height: Self.height)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onCheck)
                    .help(Text(.pickAndKeepOpenTooltip))
                    .padding(.horizontal, -4)
            }
            item.icon.frame(width: 18, height: 18)
            if let prefix = item.prefix {
                // Issue numbers in a column of their own, so titles start in line.
                Text(prefix).font(.small).monospacedDigit().foregroundStyle(Theme.textTertiary).lineLimit(1)
                    .frame(minWidth: prefix.hasPrefix("#") ? 30 : nil, alignment: .leading)
            }
            Text(item.title).lineLimit(1).truncationMode(.tail)
            if let subtitle = item.subtitle {
                Text(subtitle).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let trailing = item.trailing { trailing }
            if item.selected, onCheck == nil {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }
            if let shortcut = item.shortcut {
                Text(shortcut)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(active ? Theme.textSecondary : Theme.textTertiary)
                    .frame(minWidth: 12, alignment: .trailing)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: Self.height)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(active ? Theme.menuHighlight : .clear))
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
    }
}

/// The box at the start of a row in a picker that takes several values, drawn like the list's checkboxes.
private struct PickerCheckbox: View {
    var checked: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 4.5, style: .continuous)
            .fill(checked ? Theme.accentFill : .clear)
            .strokeBorder(checked ? .clear : Theme.textTertiary.opacity(0.7), lineWidth: 1.2)
            .frame(width: 14, height: 14)
            .overlay {
                if checked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
    }
}

/// A picker for one property of one issue, as shown in dropdowns and the command palette.
struct ItemPicker: View {
    @Environment(AppModel.self) private var model
    var kind: PickerKind
    var itemId: String
    var width: CGFloat?
    var fieldFont: Font = .ui
    var large = false
    var close: () -> Void
    @State private var query = ""

    var body: some View {
        if kind == .dueDate, let item = model.item(id: itemId) {
            DueDatePicker(
                current: Set(model.targets(for: item).map(\.dueDate)),
                addsField: model.addsDueField(for: item),
                width: width ?? kind.width,
                fieldFont: fieldFont,
                large: large,
                onPick: { model.setDueDate(of: model.targets(for: model.item(id: item.id) ?? item), to: $0) },
                onClose: close
            )
        } else if let item = model.item(id: itemId) {
            PickerList(
                placeholder: model.pickerPlaceholder(kind, for: item),
                items: model.pickerItems(kind, for: item),
                hint: kind.hint,
                multiple: kind.multiple,
                width: width ?? kind.width,
                maxRows: 10,
                fieldFont: fieldFont,
                large: large,
                opensOnSelection: kind.opensOnSelection,
                limit: kind.picksIssues ? 60 : .max,
                creating: kind == .labels ? { model.newLabelRow($0, projectId: item.projectId, repoId: item.repoId) } : nil,
                onQueryChange: { query = $0 },
                onPick: { id in
                    // A title typed to look for an issue becomes the new one's, when none was picked.
                    if id == AppModel.newSubIssueId {
                        let title = query.trimmingCharacters(in: .whitespacesAndNewlines)
                        model.newIssueTitle = title.isEmpty ? nil : title
                    }
                    model.pick(kind, id: id, for: item)
                },
                onClose: close
            )
            .onAppear {
                // Sub-issues and blockers show checked or left out, so the picker wants them fresh.
                if kind.picksIssues { model.loadRelations(for: item) }
            }
        }
    }
}

/// A property value that opens its picker in a dropdown when clicked.
struct PropertyButton<Label: View>: View {
    var kind: PickerKind
    var item: Item
    @ViewBuilder var label: Label

    @State private var open = false

    var body: some View {
        Button {
            open = true
        } label: {
            label
                .padding(.horizontal, 8)
                .frame(minHeight: 28)
                .hoverFill(active: open, radius: 8)
        }
        .buttonStyle(PlainPressStyle())
        .dropdown(isPresented: $open) { close in
            ItemPicker(kind: kind, itemId: item.id, close: close)
        }
    }
}

/// A small part of a row, such as a status icon, that opens its picker for that issue in a dropdown.
/// Inside another dropdown it opens on top of it, so the list underneath stays open.
struct PartButton<Label: View>: View {
    var kind: PickerKind
    var itemId: String
    @ViewBuilder var label: Label

    @State private var open = false
    @State private var hovering = false

    var body: some View {
        // Avatars get a round halo, icons a small square, as on cards and list rows.
        let radius: CGFloat = kind == .assignees ? 12 : 5
        Button {
            open = true
        } label: {
            label
                .padding(3)
                .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(hovering || open ? Theme.partHover : .clear))
                .contentShape(Rectangle())
                .padding(-3)
        }
        .buttonStyle(PlainPressStyle())
        .onHover { hovering = $0 }
        .help(kind.help)
        .dropdown(isPresented: $open) { close in
            ItemPicker(kind: kind, itemId: itemId, close: close)
        }
    }
}
#endif
