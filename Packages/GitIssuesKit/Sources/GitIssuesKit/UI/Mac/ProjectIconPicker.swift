#if os(macOS)
import SwiftUI

/// A project's icon, picked in a dropdown as in Linear: a search field, GitHub's colours, which keep it open so a
/// glyph can follow, and the glyphs in their groups, which close it. Typing finds glyphs by name; the arrow keys move
/// through the colours and the glyphs while the field keeps the keyboard, and Return picks.
struct ProjectIconPicker: View {
    @Environment(AppModel.self) private var model
    var projectId: String
    var close: () -> Void

    @State private var query = ""
    /// Under the pointer or the arrow keys.
    @State private var active: Spot?
    @FocusState private var focused: Bool

    enum Spot: Hashable {
        case color(Int)
        case glyph(String)
    }

    /// A line of the grid: a group's heading, or a row of up to eight glyphs.
    private struct Line: Identifiable {
        var id: String
        var title: LocalizedStringResource?
        var glyphs: [ProjectGlyph] = []
    }

    /// As many columns as GitHub has colours, so the colours sit over the glyphs' columns.
    private static let columns = Defaults.optionColors.count
    private static let cell: CGFloat = 30

    var body: some View {
        let look = model.projectLooks.look(projectId)
        let lines = Self.lines(for: query)
        let rows = lines.filter { !$0.glyphs.isEmpty }
        VStack(spacing: 0) {
            TextField(String(localized: .searchIconsPlaceholder), text: $query)
                .textFieldStyle(.plain)
                .font(.ui)
                .focused($focused)
                .focusOnAppear()
                .padding(.horizontal, 12)
                .frame(height: 40)
                .onKeyPress(.downArrow) { move(rows: 1, in: rows, look: look) }
                .onKeyPress(.upArrow) { move(rows: -1, in: rows, look: look) }
                .onKeyPress(.rightArrow) { move(by: 1, in: rows, look: look) }
                .onKeyPress(.leftArrow) { move(by: -1, in: rows, look: look) }
                .onKeyPress(.escape) {
                    close()
                    return .handled
                }
                .onSubmit {
                    if let active { pick(active, look: look) } else { close() }
                }
            Rectangle().fill(Theme.popoverBorder).frame(height: 1)
            HStack(spacing: 2) {
                ForEach(Array(Defaults.optionColors.enumerated()), id: \.offset) { index, color in
                    colorButton(color, index: index, look: look)
                }
            }
            .padding(6)
            Rectangle().fill(Theme.popoverBorder).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(lines) { line in
                            if let title = line.title {
                                Text(title)
                                    .font(.tinySemibold)
                                    .foregroundStyle(Theme.textTertiary)
                                    .padding(.horizontal, 6)
                                    .padding(.top, line.id == lines.first?.id ? 2 : 10)
                                    .padding(.bottom, 2)
                                    .id(line.id)
                            } else {
                                HStack(spacing: 2) {
                                    ForEach(line.glyphs) { glyph in
                                        glyphButton(glyph, look: look)
                                    }
                                }
                                .id(line.id)
                            }
                        }
                        if lines.isEmpty {
                            Text(.noMatches)
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.horizontal, 6)
                                .frame(height: Self.cell)
                        }
                    }
                    .padding(6)
                }
                .scrollIndicators(.never)
                .frame(height: 288)
                // A new grid for each search, from the top: one scrolled down to a group would show nothing of a few
                // matches. Without a search it opens on the project's group again.
                .id(query)
                .onAppear {
                    // The project's glyph in view, under its group's heading; no group is taller than the grid.
                    if query.isEmpty, look.glyph.group != ProjectGlyphGroup.allCases.first {
                        proxy.scrollTo("\(look.glyph.group)", anchor: .top)
                    }
                }
                .onChange(of: active) {
                    if case .glyph(let key) = active, let row = rows.first(where: { $0.glyphs.contains { $0.key == key } }) {
                        proxy.scrollTo(row.id)
                    }
                }
            }
            Rectangle().fill(Theme.popoverBorder).frame(height: 1)
            Text(.projectIconNote)
                .font(.tiny)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .frame(width: CGFloat(Self.columns) * (Self.cell + 2) - 2 + 12)
        .foregroundStyle(Theme.text)
        .onAppear { focused = true }
        .onChange(of: query) {
            // Return picks the best match, as in the other pickers.
            let first = Self.lines(for: query).first { !$0.glyphs.isEmpty }?.glyphs.first
            active = query.isEmpty ? nil : first.map { .glyph($0.key) }
        }
    }

    /// The groups with their headings, or only the glyphs that match what is typed.
    private static func lines(for query: String) -> [Line] {
        func rows(_ glyphs: [ProjectGlyph], _ prefix: String) -> [Line] {
            stride(from: 0, to: glyphs.count, by: columns).map { start in
                Line(id: "\(prefix)-\(start)", glyphs: Array(glyphs[start..<min(start + columns, glyphs.count)]))
            }
        }
        if !query.trimmingCharacters(in: .whitespaces).isEmpty {
            return rows(ProjectGlyph.matching(query), "found")
        }
        return ProjectGlyphGroup.allCases.flatMap { group in
            [Line(id: "\(group)", title: group.title)] + rows(group.glyphs, "\(group)")
        }
    }

    private func colorButton(_ color: String, index: Int, look: ProjectLook) -> some View {
        let selected = look.color == color
        return Button {
            pick(.color(index), look: look)
        } label: {
            Circle()
                .fill(Theme.projectColor(color))
                .frame(width: 14, height: 14)
                .overlay {
                    if selected {
                        Circle().stroke(Theme.projectColor(color), lineWidth: 1.5).frame(width: 20, height: 20)
                    }
                }
                .frame(width: Self.cell, height: Self.cell)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(active == .color(index) ? Theme.popoverSelected : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainPressStyle())
        .onHover { inside in hover(.color(index), inside) }
        .help(Defaults.colourName(color))
        .accessibilityLabel(Defaults.colourName(color))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func glyphButton(_ glyph: ProjectGlyph, look: ProjectLook) -> some View {
        let selected = look.glyph == glyph
        return Button {
            pick(.glyph(glyph.key), look: look)
        } label: {
            // Every glyph in the colour picked, so the choice shows before it is made.
            ProjectGlyphImage(look: ProjectLook(glyph: glyph, color: look.color), size: 16)
                .frame(width: Self.cell, height: Self.cell)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selected ? Theme.projectColor(look.color).opacity(0.16) : active == .glyph(glyph.key) ? Theme.popoverSelected : .clear)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainPressStyle())
        .onHover { inside in hover(.glyph(glyph.key), inside) }
        .help(Text(glyph.name))
        .accessibilityLabel(Text(glyph.name))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func hover(_ spot: Spot, _ inside: Bool) {
        if inside { active = spot } else if active == spot { active = nil }
    }

    private func pick(_ spot: Spot, look: ProjectLook) {
        switch spot {
        case .color(let index):
            model.projectLooks.set(ProjectLook(glyph: look.glyph, color: Defaults.optionColors[index]), for: projectId)
        case .glyph(let key):
            guard let glyph = ProjectGlyph(key: key) else { return }
            model.projectLooks.set(ProjectLook(glyph: glyph, color: look.color), for: projectId)
            close()
        }
    }

    /// The first key press lands on the project's glyph, or on the first match while searching.
    private func start(in rows: [Line], look: ProjectLook) -> Spot? {
        let glyphs = rows.flatMap(\.glyphs)
        let glyph = query.isEmpty && glyphs.contains(look.glyph) ? look.glyph : glyphs.first
        return glyph.map { .glyph($0.key) }
    }

    private func move(rows delta: Int, in rows: [Line], look: ProjectLook) -> KeyPress.Result {
        active = active.flatMap { Self.vertical(from: $0, by: delta, rows: rows.map(\.glyphs)) } ?? start(in: rows, look: look)
        return .handled
    }

    private func move(by delta: Int, in rows: [Line], look: ProjectLook) -> KeyPress.Result {
        active = active.flatMap { Self.sideways(from: $0, by: delta, rows: rows.map(\.glyphs)) } ?? start(in: rows, look: look)
        return .handled
    }

    /// Up and down, from row to row and up into the colours, which are row -1, keeping the column where the row is
    /// long enough. Nil when the spot isn't on screen.
    static func vertical(from spot: Spot, by delta: Int, rows: [[ProjectGlyph]]) -> Spot? {
        let place: (row: Int, column: Int)
        switch spot {
        case .color(let index):
            place = (-1, index)
        case .glyph(let key):
            guard let row = rows.firstIndex(where: { $0.contains { $0.key == key } }),
                  let column = rows[row].firstIndex(where: { $0.key == key }) else { return nil }
            place = (row, column)
        }
        let target = min(max(place.row + delta, -1), rows.count - 1)
        if target < 0 { return .color(min(place.column, Defaults.optionColors.count - 1)) }
        let row = rows[target]
        return .glyph(row[min(place.column, row.count - 1)].key)
    }

    /// Left and right: along the colours, going round, or through the glyphs in reading order, stopping at the ends.
    static func sideways(from spot: Spot, by delta: Int, rows: [[ProjectGlyph]]) -> Spot? {
        switch spot {
        case .color(let index):
            let count = Defaults.optionColors.count
            return .color((index + delta + count) % count)
        case .glyph(let key):
            let glyphs = rows.flatMap { $0 }
            guard let index = glyphs.firstIndex(where: { $0.key == key }) else { return nil }
            return .glyph(glyphs[min(max(index + delta, 0), glyphs.count - 1)].key)
        }
    }
}
#endif
