#if os(iOS)
import SwiftUI

/// Dragging issues in the iPhone's and iPad's list. Touch and hold an issue, then drag: held over the middle of
/// another issue, that issue lights up and takes the dragged one as its sub-issue, in any list; held over a row's top
/// or bottom edge, a line shows where it goes, in a list whose groups are the board's columns in the board's order,
/// where it can also go into another status. The line rather than a gap keeps every row where it is under the finger,
/// so that the middle of a row stays where it was. An epic's header drags its issues there together.
struct ListDropTarget: Equatable {
    enum Place: Equatable {
        case above, below
        /// Under the row's issue, as its sub-issue.
        case into
    }

    /// The section (`ListSection.id`) and the row (`Nesting.Row.id`) under the finger.
    var sectionId: String
    var rowId: String
    var place: Place
}

/// What a list knows of a drag over it.
@MainActor @Observable
final class ListDrag {
    var target: ListDropTarget?
    /// What the drag carries while it hovers, read from the lift: an issue's item id, or an epic's issues
    /// (`DraggedGroup.token`).
    var dragging: String?
    /// Every row's height, read while dragging; not watched, so that nothing is drawn again when it changes.
    @ObservationIgnored var heights: [String: CGFloat] = [:]
    /// Changes as an issue lights up to take the dragged one, and as one lands, for a tick under the finger.
    var lit = 0
    var landed = 0
}

/// How a row shows where a dragged issue would go: lit up, with the issue going under it, or a line along its top or
/// bottom edge. The dragged row itself fades while it is over the list.
struct ListRowDropMark: ViewModifier {
    var drag: ListDrag
    var sectionId: String
    var rowId: String
    /// How far in the line starts: where the row's issue starts.
    var indent: CGFloat

    func body(content: Content) -> some View {
        let target = drag.target
        let place = target?.sectionId == sectionId && target?.rowId == rowId ? target?.place : nil
        content
            .background {
                if place == .into {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.selectionFill)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                }
            }
            .overlay {
                if place == .into {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.accent, lineWidth: 2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: place == .above ? .top : .bottom) {
                if place == .above || place == .below {
                    InsertionLine()
                        .padding(.leading, indent - InsertionLine.circle / 2)
                        .padding(.trailing, 12)
                        .accessibilityHidden(true)
                }
            }
            .opacity(drag.dragging == rowId && target != nil ? 0.4 : 1)
            .animation(Theme.quick, value: place)
    }
}

/// Where a dragged issue goes between two rows: a line in the accent colour, with a small ring where it starts, as
/// the system draws it.
private struct InsertionLine: View {
    static let circle: CGFloat = 8

    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .strokeBorder(Theme.accent, lineWidth: 2)
                .frame(width: Self.circle, height: Self.circle)
            Rectangle()
                .fill(Theme.accent)
                .frame(height: 2)
        }
        .frame(height: Self.circle)
    }
}

/// Lets a row be lifted and dragged, carrying `token`: an issue's item id, or an epic's issues. Outside the app it is
/// `text`, the issue's link. Without a token the row stays where it is.
struct RowDragging: ViewModifier {
    var token: String?
    var text: String

    func body(content: Content) -> some View {
        if let token {
            content.onDrag {
                CardDragMark.lifted = token
                return CardDragMark.provider(id: token, text: text)
            }
        } else {
            content
        }
    }
}

/// Move Up and Move Down for VoiceOver on a row that can be put elsewhere in its section.
struct RowSteps: ViewModifier {
    var enabled: Bool
    var step: (Int) -> Void

    func body(content: Content) -> some View {
        if enabled {
            content
                .accessibilityAction(named: Text(.moveIssueUp)) { step(-1) }
                .accessibilityAction(named: Text(.moveIssueDown)) { step(1) }
        } else {
            content
        }
    }
}

/// Reads where over a row of the list a dragged issue is held, and takes it when it's let go.
struct ListRowDrop: DropDelegate {
    var model: AppModel
    var drag: ListDrag
    var sectionId: String
    var rowId: String
    /// The issue the row shows; nil for an epic's header.
    var item: Item?
    /// Whether a dragged issue can be put above or below the row: in a section that is one of the board's columns, in
    /// the board's own order, of a project that can be changed. Then the project, whose issues alone can go there.
    var placesIn: String?
    var onDrop: (String?, ListDropTarget) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        CardDragMark.isCard(info)
    }

    func dropEntered(info: DropInfo) {
        drag.dragging = MainActor.assumeIsolated { CardDragMark.lifted }
        update(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info)
        guard let target = drag.target, target.rowId == rowId, target.sectionId == sectionId else {
            return DropProposal(operation: .forbidden)
        }
        // Going under another issue adds to what is there, which the dragged row's badge says with a plus.
        return DropProposal(operation: target.place == .into ? .copy : .move)
    }

    func dropExited(info: DropInfo) {
        if drag.target?.rowId == rowId, drag.target?.sectionId == sectionId { drag.target = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let target = drag.target, target.rowId == rowId, target.sectionId == sectionId, CardDragMark.isCard(info) else {
            drag.target = nil
            return false
        }
        CardDragMark.loadId(info) { id in onDrop(id, target) }
        return true
    }

    private func update(_ info: DropInfo) {
        let height = drag.heights[rowId] ?? 56
        let edge = DropOntoIssue.edge(of: height)
        let y = info.location.y
        var place: ListDropTarget.Place? = y < edge ? .above : y > height - edge ? .below : .into
        if place == .into, !nestsHere { place = y < height / 2 ? .above : .below }
        // Right above or below itself it would stay where it is.
        if place != .into, !placesHere || drag.dragging == rowId { place = nil }
        let next = place.map { ListDropTarget(sectionId: sectionId, rowId: rowId, place: $0) }
        if next != drag.target {
            if next?.place == .into { drag.lit += 1 }
            drag.target = next
        }
    }

    /// Whether the dragged issue can go under this row's issue.
    private var nestsHere: Bool {
        guard let item, let dragging = drag.dragging, DraggedGroup(dragging) == nil else { return false }
        return MainActor.assumeIsolated { model.item(id: dragging).map { model.canNest([$0], under: item) } ?? false }
    }

    /// Whether what is dragged can go above or below this row: issues of the section's project.
    private var placesHere: Bool {
        guard let projectId = placesIn, let dragging = drag.dragging else { return false }
        let id = DraggedGroup(dragging)?.ids.first ?? dragging
        return MainActor.assumeIsolated { model.item(id: id)?.projectId == projectId }
    }
}
#endif
