import CoreGraphics
import Foundation

/// ⌘-dragging over issues picks them as the pointer passes over them: everything between the issue the press started on
/// and the pointer is swept, so going back lets go of the issues it leaves again. Started on an issue that is picked
/// already, the sweep lets go instead, as a table's rows do. The list, the lists on an issue's page, the board, My Issues'
/// overview and the Inbox all sweep this way: each says where its issues are, and this works out which ones are swept.
struct SweepPick: Equatable {
    /// Which picks a sweep changes.
    enum Place: Equatable {
        /// The picked issues of a list or board.
        case issues
        /// The sub-issues picked on the open issue's page.
        case subIssues
        /// The picked notifications of the Inbox.
        case inbox
    }

    var place: Place
    /// The issue the press started on.
    var anchor: String
    /// What was picked when the sweep started, which the swept issues are added to or taken from.
    var before: Set<String>
    /// What was picked, as it goes back to when the sweep is called off.
    var original: Set<String>
    /// Whether the sweep picks. Started on a picked issue, it lets go.
    var picks: Bool

    /// `counted` is what the sweep counts as picked before it, which can be more than `picked`: in the Inbox the
    /// notification on screen is picked along with the first one, as a ⌘-click picks it.
    init(place: Place, anchor: String, picked: Set<String>, counted: Set<String>? = nil) {
        self.place = place
        self.anchor = anchor
        original = picked
        before = counted ?? picked
        picks = !picked.contains(anchor)
    }

    /// The picks with `swept` swept: the issues the sweep left again are as they were before it.
    func picked(sweeping swept: Set<String>) -> Set<String> {
        picks ? before.union(swept) : before.subtracting(swept)
    }

    /// The ones among `rows` that the rectangle from `start` to `end` meets. In a list, whose rows reach across it, only
    /// how far up or down the pointer is counts (`sideways` false), so it may wander off to the side.
    static func swept(_ rows: [SweepRow], from start: CGPoint, to end: CGPoint, sideways: Bool = true) -> Set<String> {
        let top = min(start.y, end.y), bottom = max(start.y, end.y)
        let left = min(start.x, end.x), right = max(start.x, end.x)
        var ids = Set<String>()
        // A row meets the rectangle when it reaches into it; with the pointer back on the row it started on, that row
        // alone. Half-open, so that a point on the line between two rows is on only one of them.
        for row in rows where row.frame.minY <= bottom && row.frame.maxY > top
            && (!sideways || (row.frame.minX <= right && row.frame.maxX > left)) {
            ids.insert(row.id)
        }
        return ids
    }
}

/// An issue a sweep can pick, and where it is now.
struct SweepRow: Equatable {
    var id: String
    var frame: CGRect
}

extension AppModel {
    /// Starts a ⌘-drag on the issue the press is on: it is picked at once, or let go if it was picked.
    func beginSweep(on id: String, in place: SweepPick.Place) {
        let sweep: SweepPick
        switch place {
        case .issues:
            sweep = SweepPick(place: place, anchor: id, picked: selectedIds)
        case .subIssues:
            sweep = SweepPick(place: place, anchor: id, picked: pickedSubIssueIds)
        case .inbox:
            // As a ⌘-click does, picking starts with the notification on screen.
            var counted = inboxPicked
            if counted.isEmpty, let selected = inboxSelectedId, selected != id { counted.insert(selected) }
            sweep = SweepPick(place: place, anchor: id, picked: inboxPicked, counted: counted)
        }
        activeSweep = sweep
        self.sweep(over: [id])
    }

    /// The issues swept now, the one the press started on among them.
    func sweep(over ids: Set<String>) {
        guard let sweep = activeSweep else { return }
        let picked = sweep.picked(sweeping: ids.union([sweep.anchor]))
        set(picked, in: sweep)
    }

    /// The button is up: the issues swept stay picked, and Shift-click goes on from where the sweep started.
    func endSweep() {
        activeSweep = nil
    }

    /// Escape during a sweep: the picks go back to what they were before it.
    func cancelSweep() {
        guard let sweep = activeSweep else { return }
        set(sweep.original, in: sweep)
        activeSweep = nil
    }

    private func set(_ picked: Set<String>, in sweep: SweepPick) {
        switch sweep.place {
        case .issues:
            if selectedIds != picked { selectedIds = picked }
            selectionAnchorId = sweep.anchor
            selectionRange = []
        case .subIssues:
            if pickedSubIssueIds != picked { pickedSubIssueIds = picked }
            subIssuePickAnchor = sweep.anchor
        case .inbox:
            if inboxPicked != picked { inboxPicked = picked }
            inboxPickAnchor = sweep.anchor
            inboxPickRange = []
        }
    }
}
