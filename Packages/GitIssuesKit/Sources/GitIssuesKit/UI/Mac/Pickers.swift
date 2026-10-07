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
    var onPick: (String) -> Void
    var onClose: () -> Void

    @State private var query = ""
    @State private var index = 0
    @FocusState private var focused: Bool

    var body: some View {
        let visible = filtered
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField(placeholder, text: $query)
                    .textFieldStyle(.plain)
                    .font(fieldFont)
                    .focused($focused)
                    .focusOnAppear()
                if let hint { Keycap(hint) }
            }
                .padding(.horizontal, 12)
                .frame(height: 40)
                .onKeyPress(.downArrow) {
                    index = min(index + 1, max(visible.count - 1, 0))
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    index = max(index - 1, 0)
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
                    guard multiple, press.modifiers.contains(.shift), visible.indices.contains(index) else { return .ignored }
                    pick(visible[index], keepOpen: true)
                    query = ""
                    return .handled
                }
                .onSubmit {
                    if visible.indices.contains(index) { pick(visible[index]) }
                }
            Rectangle().fill(Theme.popoverBorder).frame(height: 1)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(visible.enumerated()), id: \.element.id) { position, item in
                            PickerRow(item: item, active: position == index, onCheck: multiple ? { pick(item, keepOpen: true) } : nil)
                                .id(item.id)
                                .onTapGesture {
                                    pick(item, keepOpen: multiple && !NSEvent.modifierFlags.isDisjoint(with: [.shift, .command]))
                                }
                                .onHover { if $0 { index = position } }
                        }
                        if visible.isEmpty {
                            Text("No matches")
                                .foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.never)
                .frame(height: min(CGFloat(max(visible.count, 1)), CGFloat(maxRows)) * 32 + 8)
                .onChange(of: index) {
                    if visible.indices.contains(index) { proxy.scrollTo(visible[index].id) }
                }
            }
        }
        .frame(width: width)
        .font(.ui)
        .foregroundStyle(Theme.text)
        .onAppear {
            focused = true
            // Single-choice pickers start on the current value, so Return keeps it.
            if !multiple, let current = items.firstIndex(where: \.selected) { index = current }
        }
        .onChange(of: query) { index = 0 }
    }

    private var filtered: [PickerItem] {
        guard !query.isEmpty else { return items }
        return items
            .compactMap { item -> (PickerItem, Int)? in
                let score = max(fuzzyScore(query, item.title) ?? -1, item.subtitle.flatMap { fuzzyScore(query, $0) } ?? -1)
                return score >= 0 ? (item, score) : nil
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    private func pick(_ item: PickerItem, keepOpen: Bool = false) {
        onPick(item.id)
        if !keepOpen { onClose() }
    }
}

struct PickerRow: View {
    var item: PickerItem
    var active: Bool
    /// In pickers that take several values: picks the row without closing, from a checkbox at its start.
    var onCheck: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            if let onCheck {
                // Ticked when picked; on the row under the pointer or keyboard an empty box offers it.
                PickerCheckbox(checked: item.selected)
                    .opacity(item.selected || active ? 1 : 0)
                    .frame(width: 22, height: 32)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onCheck)
                    .help("Pick and keep the list open, to pick more")
                    .padding(.horizontal, -4)
            }
            item.icon.frame(width: 18, height: 18)
            if let prefix = item.prefix {
                Text(prefix).font(.small).monospacedDigit().foregroundStyle(Theme.textTertiary).lineLimit(1)
            }
            Text(item.title).lineLimit(1).truncationMode(.tail)
            if let subtitle = item.subtitle {
                Text(subtitle).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let trailing = item.trailing { trailing }
            if item.selected, onCheck == nil {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textBody)
            }
            if let shortcut = item.shortcut {
                Text(shortcut)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(active ? Theme.textSecondary : Theme.textTertiary)
                    .frame(minWidth: 12, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(active ? Theme.popoverSelected : .clear))
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }
}

/// The box at the start of a row in a picker that takes several values, drawn like the list's checkboxes.
private struct PickerCheckbox: View {
    var checked: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(checked ? Theme.accentFill : .clear)
            .strokeBorder(checked ? .clear : Theme.textTertiary, lineWidth: 1.2)
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
    var close: () -> Void

    var body: some View {
        if let item = model.item(id: itemId) {
            PickerList(
                placeholder: model.pickerPlaceholder(kind, for: item),
                items: model.pickerItems(kind, for: item),
                hint: kind.hint,
                multiple: kind.multiple,
                width: width ?? kind.width,
                maxRows: 10,
                fieldFont: fieldFont,
                onPick: { model.pick(kind, id: $0, for: item) },
                onClose: close
            )
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
                .hoverFill(active: open)
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
