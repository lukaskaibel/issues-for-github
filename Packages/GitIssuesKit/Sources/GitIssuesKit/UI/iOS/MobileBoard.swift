#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers

/// The board on the iPad: the Mac's columns and cards, moved with the system's drag and drop. Touch and
/// hold a card to lift it (or to open its menu), then drag it to another place or column; the cards there
/// make room. Dragged out of the app, a card is its link on GitHub.
struct MobileBoard: View {
    @Environment(AppModel.self) private var model
    var projectId: String

    @State private var target: BoardDropTarget?
    @State private var dragging: String?
    @State private var dropped = 0
    @State private var addingStatus = false
    @State private var newStatus = ""

    var body: some View {
        let columns = model.columns(projectId: projectId)
        let canEdit = model.projects.first { $0.id == projectId }?.viewerCanUpdate == true
        GeometryReader { proxy in
            let width = columnWidth(available: proxy.size.width, count: columns.count, canEdit: canEdit)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(columns) { column in
                        MobileColumn(
                            projectId: projectId, column: column, width: width,
                            target: $target, dragging: $dragging,
                            onDrop: { id, index in move(id, to: column, at: index) }
                        )
                        .frame(width: width)
                    }
                    if canEdit {
                        Button {
                            newStatus = ""
                            addingStatus = true
                        } label: {
                            Label("Add Status", systemImage: "plus")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.horizontal, 12)
                                .frame(height: 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .hoverEffect(.highlight)
                        .frame(width: 170, alignment: .leading)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.panel)
        .sensoryFeedback(.impact(weight: .medium), trigger: dropped)
        .alert("New Status", isPresented: $addingStatus) {
            TextField("Name", text: $newStatus)
            Button("Cancel", role: .cancel) {}
            Button("Add") {
                let name = newStatus.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                let options = model.statusOptions(projectId: projectId).map(\.remote) + [RemoteOption(id: nil, name: name, color: "GRAY")]
                withAnimation(Theme.spring) { model.saveColumns(projectId: projectId, options) }
            }
        } message: {
            Text("A new column at the end of the board.")
        }
    }

    private func columnWidth(available: CGFloat, count: Int, canEdit: Bool) -> CGFloat {
        guard count > 0 else { return 290 }
        let extra: CGFloat = canEdit ? 184 : 0
        let fitted = (available - 36 - extra - CGFloat(count - 1) * 14) / CGFloat(count)
        return min(max(fitted, 268), 330)
    }

    private func move(_ id: String, to column: BoardColumn, at index: Int) {
        target = nil
        dragging = nil
        guard let item = model.item(id: id), item.projectId == projectId else { return }
        dropped += 1
        withAnimation(Theme.spring) { model.drop(item, in: column, at: index) }
    }
}

/// Where a dragged card would land: a column, and the position among its other cards.
struct BoardDropTarget: Equatable {
    var columnId: String
    var index: Int
}

/// Card frames inside a column, read while dropping. Kept outside view state so scrolling never redraws.
@MainActor
final class CardFrames {
    var frames: [String: CGRect] = [:]
}

private struct MobileColumn: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation
    @Environment(\.openRoute) private var openRoute
    var projectId: String
    var column: BoardColumn
    var width: CGFloat
    @Binding var target: BoardDropTarget?
    @Binding var dragging: String?
    var onDrop: (String, Int) -> Void

    @State private var frames = CardFrames()

    var body: some View {
        let space = "column-\(column.id)"
        VStack(spacing: 8) {
            MobileColumnHeader(projectId: projectId, column: column)
            ScrollView(.vertical) {
                LazyVStack(spacing: 8) {
                    ForEach(Array(column.items.enumerated()), id: \.element.id) { index, item in
                        if gapPosition == index {
                            gap
                        }
                        card(item, space: space)
                    }
                    if gapPosition == column.items.count {
                        gap
                    }
                }
                .padding(.bottom, 80)
                .animation(Theme.spring, value: target)
                .animation(Theme.spring, value: column.items.map(\.id))
            }
            .scrollIndicators(.hidden)
            .coordinateSpace(.named(space))
            .frame(maxHeight: .infinity)
            .accessibilityIdentifier("column-\(column.title)")
            .onDrop(of: [.plainText, .url], delegate: ColumnDrop(
                column: column, frames: frames, target: $target, dragging: $dragging, onDrop: onDrop
            ))
        }
    }

    /// Where the gap shows among all of the column's cards, the dragged one included.
    private var gapPosition: Int? {
        guard let target, target.columnId == column.id else { return nil }
        if let original = column.items.firstIndex(where: { $0.id == dragging }), target.index >= original {
            return min(target.index + 1, column.items.count)
        }
        return min(target.index, column.items.count)
    }

    private var gap: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Theme.accent.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Theme.accent.opacity(0.5), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
            )
            .frame(height: 76)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private func card(_ item: Item, space: String) -> some View {
        Button {
            openRoute(.issue(item.id))
        } label: {
            CardView(card: model.cardModel(for: item), width: width, avatarVersion: model.avatarVersion)
                .equatable()
        }
        .buttonStyle(CardPressStyle())
        .accessibilityIdentifier("card-\(item.displayNumber)")
        .hoverEffect(.lift)
        .opacity(dragging == item.id && target != nil ? 0.35 : 1)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(space))
        } action: { frame in
            frames.frames[item.id] = frame
        }
        .onDisappear { frames.frames[item.id] = nil }
        .onDrag {
            dragging = item.id
            return CardDragMark.provider(text: dragText(item))
        } preview: {
            CardView(card: model.cardModel(for: item), width: width, lifted: true, avatarVersion: model.avatarVersion)
        }
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contextMenu {
            ItemMenuContent(item: item) { openRoute(.issue(item.id)) }
        } preview: {
            IssuePreview(item: item)
                .environment(model)
        }
        .accessibilityAction(named: "Move to Next Status") { step(item, by: 1) }
        .accessibilityAction(named: "Move to Previous Status") { step(item, by: -1) }
    }

    /// What a card is outside the app: its link on GitHub, or its number and title.
    private func dragText(_ item: Item) -> String {
        item.url ?? "\(item.displayNumber) \(item.title)"
    }

    /// For VoiceOver, which can't drag: moves the card to the neighbouring column.
    private func step(_ item: Item, by delta: Int) {
        let columns = model.columns(projectId: projectId)
        guard let index = columns.firstIndex(where: { $0.id == column.id }),
              columns.indices.contains(index + delta) else { return }
        let next = columns[index + delta]
        withAnimation(Theme.spring) { model.drop(item, in: next, at: next.items.count) }
    }
}

/// Lands cards dropped on a column at the place the finger points to.
private struct ColumnDrop: DropDelegate {
    var column: BoardColumn
    var frames: CardFrames
    @Binding var target: BoardDropTarget?
    @Binding var dragging: String?
    var onDrop: (String, Int) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        dragging != nil && CardDragMark.isCard(info)
    }

    func dropEntered(info: DropInfo) {
        update(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if target?.columnId == column.id { target = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let id = dragging, CardDragMark.isCard(info) else { return false }
        let others = column.items.filter { $0.id != id }.count
        let index = target?.columnId == column.id ? min(target!.index, others) : others
        onDrop(id, index)
        return true
    }

    /// The position among the column's other cards, from where the finger is.
    private func update(_ info: DropInfo) {
        let others = column.items.filter { $0.id != dragging }
        var index = 0
        for (position, item) in others.enumerated() {
            guard let frame = MainActor.assumeIsolated({ frames.frames[item.id] }) else { continue }
            if frame.midY < info.location.y { index = position + 1 }
        }
        let next = BoardDropTarget(columnId: column.id, index: index)
        if next != target { target = next }
    }
}

/// Marks a card being dragged as one of this app's, visible to this app only. A long press that opens the menu,
/// or a drag let go outside the board, leaves no drop behind, so text dragged in from another app afterwards must
/// not be taken for that card.
private enum CardDragMark {
    static let typeIdentifier = "com.lukaskbl.GitIssues.card"

    static func provider(text: String) -> NSItemProvider {
        let provider = NSItemProvider(object: text as NSString)
        provider.registerDataRepresentation(forTypeIdentifier: typeIdentifier, visibility: .ownProcess) { completion in
            completion(Data(), nil)
            return nil
        }
        return provider
    }

    static func isCard(_ info: DropInfo) -> Bool {
        info.itemProviders(for: [.plainText, .url]).contains { $0.registeredTypeIdentifiers.contains(typeIdentifier) }
    }
}

/// A card dims a little while pressed, like the rest of the app's plain buttons.
private struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(Theme.quick, value: configuration.isPressed)
    }
}

/// A column's header: status, name and count, with its menu and "+" for a new issue in it.
private struct MobileColumnHeader: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileNavigation.self) private var navigation
    @Environment(\.colorScheme) private var scheme
    var projectId: String
    var column: BoardColumn

    @State private var renaming = false
    @State private var name = ""
    @State private var confirmDelete = false

    var body: some View {
        HStack(spacing: 8) {
            StatusIcon(glyph: column.glyph, size: 16)
            Text(column.title).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text("\(column.items.count)").font(.subheadline).monospacedDigit().foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 0)
            if canEdit, let option = column.option {
                Menu {
                    Button {
                        name = option.name
                        renaming = true
                    } label: {
                        Label("Rename…", systemImage: "pencil")
                    }
                    Menu {
                        Picker("Colour", selection: Binding(
                            get: { option.color },
                            set: { color in edit { $0.color = color } }
                        )) {
                            ForEach(Defaults.optionColors, id: \.self) { color in
                                Label {
                                    Text(color.capitalized)
                                } icon: {
                                    MenuImages.label(StatusEditor.hex(color), scheme)
                                }
                                .tag(color)
                            }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Label("Colour", systemImage: "paintpalette")
                    }
                    Divider()
                    Button {
                        move(-1)
                    } label: {
                        Label("Move Left", systemImage: "arrow.left")
                    }
                    .disabled(position == 0)
                    Button {
                        move(1)
                    } label: {
                        Label("Move Right", systemImage: "arrow.right")
                    }
                    .disabled(position >= statuses.count - 1)
                    Divider()
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Delete Status…", systemImage: "trash")
                    }
                    .disabled(statuses.count <= 1)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Options for \(column.title)")
            }
            Button {
                navigation.sheet = .newIssue(NewIssueContext(projectId: projectId, statusId: column.option?.id))
            } label: {
                Image(systemName: "plus")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .accessibilityLabel("New issue in \(column.title)")
        }
        .padding(.horizontal, 4)
        .frame(minHeight: 36)
        .alert("Rename Status", isPresented: $renaming) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty, trimmed != column.title { edit { $0.name = trimmed } }
            }
        }
        .confirmationDialog("Delete the \"\(column.title)\" status?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Status", role: .destructive) { delete() }
        } message: {
            Text(column.items.isEmpty
                 ? "The status is removed from the project on GitHub."
                 : "The status is removed from the project on GitHub. Its \(column.items.count) issue\(column.items.count == 1 ? "" : "s") stay in the project without a status.")
        }
    }

    private var canEdit: Bool { model.projects.first { $0.id == projectId }?.viewerCanUpdate == true }
    private var statuses: [FieldOption] { model.statusOptions(projectId: projectId) }
    private var position: Int { statuses.firstIndex { $0.id == column.id } ?? 0 }

    private func edit(_ change: (inout RemoteOption) -> Void) {
        var options = statuses.map(\.remote)
        guard options.indices.contains(position) else { return }
        change(&options[position])
        model.saveColumns(projectId: projectId, options)
    }

    private func move(_ delta: Int) {
        var options = statuses.map(\.remote)
        let destination = position + delta
        guard options.indices.contains(position), options.indices.contains(destination) else { return }
        options.swapAt(position, destination)
        withAnimation(Theme.spring) { model.saveColumns(projectId: projectId, options) }
    }

    private func delete() {
        var options = statuses.map(\.remote)
        guard options.indices.contains(position) else { return }
        options.remove(at: position)
        withAnimation(Theme.spring) { model.saveColumns(projectId: projectId, options) }
    }
}
#endif
