#if os(macOS)
import Observation
import SwiftUI

/// Where each row of a board column goes, worked out from heights known in advance, top to bottom with a gap
/// between rows.
struct RowPlan: Equatable {
    private(set) var tops: [CGFloat] = []
    private(set) var heights: [CGFloat] = []
    /// The whole column, with room under the last row.
    private(set) var height: CGFloat = 0

    init() {}

    init(heights: [CGFloat], gap: CGFloat, bottom: CGFloat) {
        var y: CGFloat = 0
        tops.reserveCapacity(heights.count)
        for (index, height) in heights.enumerated() {
            if index > 0 { y += gap }
            tops.append(y)
            y += height
        }
        self.heights = heights
        height = y + bottom
    }

    var count: Int { tops.count }

    /// The rows that reach into a stretch of the column, in the column's coordinates; a row that only touches its
    /// edge doesn't.
    func rows(in range: ClosedRange<CGFloat>) -> Range<Int> {
        // The first row whose bottom is below the stretch's top, then the first whose top isn't above its bottom.
        var low = 0, high = count
        while low < high {
            let middle = (low + high) / 2
            if tops[middle] + heights[middle] <= range.lowerBound { low = middle + 1 } else { high = middle }
        }
        let first = low
        high = count
        while low < high {
            let middle = (low + high) / 2
            if tops[middle] < range.upperBound { low = middle + 1 } else { high = middle }
        }
        return first..<max(first, low)
    }
}

/// Which row each of a column's row views shows. Only the rows on screen and near it have a view. A row that
/// scrolls in takes over the view of one that scrolled out, of the same kind where there is one, so scrolling
/// changes what a view shows instead of building a new one, and only that view is drawn anew.
@MainActor @Observable
final class RowWindow {
    /// How far past the part on screen rows get a view, so that they are ready before they show.
    static let margin: CGFloat = 200

    /// The part on screen, in the column's coordinates; until the column reports it, the top of a short column.
    @ObservationIgnored private(set) var visible: ClosedRange<CGFloat> = 0...600
    /// The row each view shows, by its id; nil for a view that shows nothing.
    @ObservationIgnored private var slots: [String?] = []
    @ObservationIgnored private var slotOf: [String: Int] = [:]
    /// Views whose row is no longer near the screen, kept to show another one.
    @ObservationIgnored private var parked: Set<Int> = []
    /// The rows as the views last showed them.
    @ObservationIgnored private var ids: [String] = []
    @ObservationIgnored private var kinds: [Int] = []
    @ObservationIgnored private var indexOf: [String: Int] = [:]
    @ObservationIgnored private var plan = RowPlan()
    /// Changes when scrolling needs more views than there are, which only the rows' container reads.
    private(set) var growth = 0

    /// The row a view shows. A view asks for its own, so a row coming in redraws only the view that shows it.
    subscript(slot slot: Int) -> String? {
        access(keyPath: \.[slot: slot])
        return slots.indices.contains(slot) ? slots[slot] : nil
    }

    var slotCount: Int { slots.count }

    /// Where a row is among the rows as the views last showed them.
    func index(of id: String) -> Int? {
        indexOf[id]
    }

    /// Called as the column scrolls: hands the views of rows that went out to rows that came in.
    func scrolled(to visible: ClosedRange<CGFloat>) {
        self.visible = visible
        let changed = assign(reusing: true)
        guard !changed.isEmpty else { return }
        let paths = changed.map { \RowWindow.[slot: $0] }
        for path in paths { _$observationRegistrar.willSet(self, keyPath: path) }
        for path in paths { _$observationRegistrar.didSet(self, keyPath: path) }
    }

    /// Called by the rows' container when the rows or their places change. A row coming in this way gets a view of
    /// its own, so that it fades in as a lazy stack's row would, rather than moving in from another row's place.
    func update(ids: [String], kinds: [Int], plan: RowPlan) {
        if ids != self.ids || kinds != self.kinds || plan != self.plan {
            if ids != self.ids {
                indexOf = Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
            }
            self.ids = ids
            self.kinds = kinds
            self.plan = plan
        }
        _ = assign(reusing: false)
    }

    /// Gives every row near the screen a view; returns the views that now show another row.
    private func assign(reusing: Bool) -> [Int] {
        let live = plan.rows(in: (visible.lowerBound - Self.margin)...(visible.upperBound + Self.margin))
            .clamped(to: 0..<ids.count)
        let wanted = Set(ids[live])
        var changed: [Int] = []
        // Views whose row went away or out of reach.
        for (slot, id) in slots.enumerated() {
            guard let id, !wanted.contains(id), !parked.contains(slot) else { continue }
            parked.insert(slot)
        }
        if !reusing {
            // Kept for scrolling, but a row that comes in now must not take one over.
            for slot in parked where slots[slot].map({ !wanted.contains($0) }) ?? false {
                slotOf[slots[slot]!] = nil
                slots[slot] = nil
                changed.append(slot)
            }
            parked.removeAll()
        }
        let free = slots.indices.filter { slots[$0] == nil && !changed.contains($0) }
        var freeIndex = 0
        for index in live {
            let id = ids[index]
            if let slot = slotOf[id] {
                parked.remove(slot)
                continue
            }
            var slot: Int?
            if reusing {
                // Only a view that showed a row of the same kind: one of another kind would be built anew all the
                // same, and the next row of its own kind would find none to take over.
                slot = parked.first { slotKind($0) == kinds[index] }
                if let taken = slot {
                    parked.remove(taken)
                    if let old = slots[taken] { slotOf[old] = nil }
                }
            }
            if slot == nil, freeIndex < free.count {
                slot = free[freeIndex]
                freeIndex += 1
            }
            if slot == nil {
                slots.append(nil)
                slot = slots.count - 1
                if reusing { growth &+= 1 }
            }
            slots[slot!] = id
            slotOf[id] = slot!
            changed.append(slot!)
        }
        return changed
    }

    private func slotKind(_ slot: Int) -> Int? {
        guard let id = slots[slot], let index = indexOf[id] else { return nil }
        return kinds[index]
    }
}

/// A board column's rows, each placed where the plan puts it, of which only those on screen or near it have a view.
/// A lazy stack measures every row it builds, places them one after another and builds a new view for each row
/// that comes in; here nothing is measured, and a row that comes in takes over the view of one that went out.
struct PlacedRows<Row: Identifiable, Content: View, Spoken: View>: View where Row.ID == String {
    var rows: [Row]
    var plan: RowPlan
    var window: RowWindow
    /// Rows of one kind take over each other's views.
    var kind: (Row) -> Int
    @ViewBuilder var content: (Row) -> Content
    /// What VoiceOver finds in place of a row, as big as the row. While VoiceOver or another assistive technology is
    /// on, every row has it, also those without a view, so that VoiceOver goes through the whole column in order, as
    /// it does in a lazy stack; the row views, which come and go and stand in no order, are hidden from it.
    @ViewBuilder var spoken: (Row) -> Spoken
    @Environment(\.accessibilityEnabled) private var accessibilityEnabled

    var body: some View {
        let _ = window.growth
        let _ = window.update(ids: rows.map(\.id), kinds: rows.map(kind), plan: plan)
        PlacedRowsLayout(height: plan.height) {
            ForEach(0..<window.slotCount, id: \.self) { slot in
                RowSlot(slot: slot, window: window) { id in
                    if let row = window.index(of: id), rows.indices.contains(row) {
                        content(rows[row])
                            .offset(y: plan.tops[row])
                    }
                }
            }
        }
        .accessibilityHidden(accessibilityEnabled)
        .background {
            if accessibilityEnabled {
                PlacedRowsLayout(height: plan.height) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        spoken(row)
                            .offset(y: plan.tops[index])
                    }
                }
                .allowsHitTesting(false)
            }
        }
    }
}

/// One of the column's row views, showing whichever row the window gives it.
private struct RowSlot<Content: View>: View {
    var slot: Int
    var window: RowWindow
    @ViewBuilder var content: (String) -> Content

    var body: some View {
        if let id = window[slot: slot] {
            content(id)
        }
    }
}

/// Puts every row view at the column's top, as wide as the column and as tall as it is; each moves itself down to
/// its place. It is as tall as the plan says, without asking the rows.
private struct PlacedRowsLayout: Layout {
    var height: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: nil))
        }
    }
}

/// How tall rows drawn with text views are, which only their views know: each is measured the first time it is
/// drawn and kept. Until then a height worked out from its text stands in, and the rows under it move only if the
/// two differ, which they mostly don't.
@MainActor @Observable
final class MeasuredHeights {
    /// What a row's height depends on, and how to work it out without drawing the row.
    struct Measure {
        var key: String
        var guess: () -> CGFloat
    }

    struct Report: Equatable {
        var key: String
        var height: CGFloat
    }

    /// Changes when a row turns out taller or shorter than the column took it for.
    private(set) var version = 0
    @ObservationIgnored private var heights: [String: CGFloat] = [:]

    func height(_ measure: Measure) -> CGFloat {
        _ = version
        if let height = heights[measure.key] { return height }
        let guess = measure.guess()
        heights[measure.key] = guess
        return guess
    }

    func report(_ report: Report) {
        guard heights[report.key] != report.height else { return }
        #if DEBUG
        if let guess = heights[report.key] { Self.missed.append("\(report.key): \(guess) → \(report.height)") }
        #endif
        heights[report.key] = report.height
        version &+= 1
    }

    #if DEBUG
    /// Guesses that turned out wrong, for the debug remote.
    nonisolated(unsafe) static var missed: [String] = []
    #endif

    static func width(of text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
    }

    /// How many lines a text takes at this width, up to a limit.
    static func lines(of text: String, font: NSFont, width: CGFloat, limit: Int) -> Int {
        let bounds = NSAttributedString(string: text, attributes: [.font: font])
            .boundingRect(with: CGSize(width: max(width, 1), height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading])
        let line = NSLayoutManager().defaultLineHeight(for: font)
        return min(limit, max(1, Int((bounds.height / line).rounded())))
    }

    /// How tall a text view is with this many lines.
    static func textHeight(lines: Int, font: NSFont) -> CGFloat {
        (CGFloat(lines) * NSLayoutManager().defaultLineHeight(for: font)).rounded(.up)
    }
}

extension View {
    /// Tells `measured` how tall this view is, under `key`.
    func reportsHeight(_ key: String, to measured: MeasuredHeights) -> some View {
        onGeometryChange(for: MeasuredHeights.Report.self) { proxy in
            MeasuredHeights.Report(key: key, height: proxy.size.height)
        } action: { report in
            measured.report(report)
        }
    }
}
#endif
