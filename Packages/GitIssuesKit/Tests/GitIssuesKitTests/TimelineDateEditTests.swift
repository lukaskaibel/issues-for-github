import Foundation
import GRDB
import Testing
@testable import GitIssuesKit

@Suite("Moving and resizing issue dates on a timeline")
struct TimelineDateEditTests {
    static let first = CalendarDay(year: 2026, month: 12, day: 29)
    static let last = CalendarDay(year: 2027, month: 1, day: 4)
    static let startField = ProjectField(id: "S", projectId: "P1", databaseId: 1, name: "Start date", dataType: "DATE", position: 1)
    static let endField = ProjectField(id: "E", projectId: "P1", databaseId: 2, name: "Target date", dataType: "DATE", position: 2)

    func item(start: CalendarDay? = Self.first, end: CalendarDay? = Self.last, due: Bool = false) -> Item {
        var item = Item(id: "I1", projectId: "P1", kind: .issue, position: 1, contentId: "issue-1", number: 1, title: "One", body: "", state: "OPEN")
        item.fieldValues["S"] = start.map { FieldValue(date: $0.string) }
        if due { item.dueDate = end?.string } else { item.fieldValues["E"] = end.map { FieldValue(date: $0.string) } }
        return item
    }

    func edit(_ item: Item, due: Bool = false, displayedSpan: TimelineSpan? = .stretch(Self.first, Self.last), canUpdate: Bool = true) -> TimelineDateEdit? {
        let context = FilterContext(
            viewerLogin: "me", today: Self.first, fields: [Self.startField, Self.endField],
            statusFieldId: nil, priorityFieldId: nil, dueFieldId: due ? "E" : nil,
            optionName: { _, _ in nil }, parentReference: { _ in nil }
        )
        return TimelineDateEdit.make(
            item: item, dates: (Self.startField, Self.endField), context: context,
            displayedSpan: displayedSpan, canUpdate: canUpdate
        )
    }

    @Test("Moving in either direction keeps a range's duration across month and year boundaries", arguments: [-35, -1, 0, 1, 35])
    func movesRange(days: Int) throws {
        let original = try #require(edit(item()))
        let moved = original.adjusted(by: days, part: .move)
        #expect(moved.start?.day == Self.first.adding(days: days))
        #expect(moved.end?.day == Self.last.adding(days: days))
        #expect(moved.span.last.days(from: moved.span.first) == Self.last.days(from: Self.first))
        #expect(original.start?.day == Self.first)
        #expect(original.end?.day == Self.last)
    }

    @Test("Each resize changes only its endpoint and stops at a one-day range")
    func clampsEndpoints() throws {
        let original = try #require(edit(item()))
        let start = original.adjusted(by: 100, part: .start)
        #expect(start.span == .stretch(Self.last, Self.last))
        #expect(start.end == original.end)
        let end = original.adjusted(by: -100, part: .end)
        #expect(end.span == .stretch(Self.first, Self.first))
        #expect(end.start == original.start)
        #expect(original.adjusted(by: -3, part: .start).start?.day == Self.first.adding(days: -3))
        #expect(original.adjusted(by: 3, part: .end).end?.day == Self.last.adding(days: 3))
    }

    @Test("A single date moves without creating another endpoint", arguments: [true, false])
    func singleDate(startOnly: Bool) throws {
        let item = item(start: startOnly ? Self.first : nil, end: startOnly ? nil : Self.last)
        let day = startOnly ? Self.first : Self.last
        let original = try #require(edit(item, displayedSpan: .day(day, milestone: false)))
        #expect(!original.canResize)
        #expect(original.adjusted(by: -4, part: .move).span == .day(day.adding(days: -4), milestone: false))
        #expect(original.adjusted(by: 2, part: .start) == original)
        #expect(original.adjusted(by: 2, part: .end) == original)
    }

    @Test("Read-only projects, unscheduled issues and derived dates do not expose a date drag")
    func protectsDerivedDates() {
        #expect(edit(item(), canUpdate: false) == nil)
        #expect(edit(item(start: nil, end: nil), displayedSpan: nil) == nil)
        #expect(edit(item(start: nil, end: nil), displayedSpan: .day(Self.last, milestone: true)) == nil)
        #expect(edit(item(start: Self.first, end: nil), displayedSpan: .stretch(Self.first, Self.last)) == nil)
        #expect(edit(item(start: nil, end: nil), displayedSpan: .stretch(Self.first, Self.last)) == nil)
    }

    @Test("A reversed existing range can move together without swapping the fields")
    func reversedRange() throws {
        let original = try #require(edit(item(start: Self.last, end: Self.first)))
        #expect(!original.canResize)
        let moved = original.adjusted(by: 3, part: .move)
        #expect(moved.start?.day == Self.last.adding(days: 3))
        #expect(moved.end?.day == Self.first.adding(days: 3))
        #expect(moved.adjusted(by: 1, part: .end) == moved)
    }

    @Test("A preview queues nothing; dropping moves both fields through the outbox and survives a refresh")
    func queuesBothEndpoints() throws {
        let db = try AppDatabase.inMemory()
        let item = item()
        try db.writer.write { db in
            try Project(id: "P1", ownerLogin: "me", ownerIsOrg: false, number: 1, title: "Board", url: "", closed: false, viewerCanUpdate: true).insert(db)
            try item.insert(db)
        }
        let original = try #require(edit(item))
        let preview = original.adjusted(by: 10, part: .move)
        #expect(try db.reader.read { try OutboxEntry.fetchCount($0) } == 0)
        let changes = preview.mutations(from: original, item: item, dueFieldId: nil)
        #expect(changes.count == 2)
        try db.writer.write { db in
            for change in changes { try Outbox.enqueue(db, change) }
        }
        let stored = try db.reader.read { try Item.fetchOne($0, key: "I1") }
        let changed = try #require(stored)
        #expect(changed.fieldValues["S"]?.date == Self.first.adding(days: 10).string)
        #expect(changed.fieldValues["E"]?.date == Self.last.adding(days: 10).string)
        #expect(changed.dirty)
        try db.writer.write { db in
            try item.update(db)
            try Outbox.rebase(db)
        }
        let storedAfterRefresh = try db.reader.read { try Item.fetchOne($0, key: "I1") }
        let rebased = try #require(storedAfterRefresh)
        #expect(rebased.fieldValues == changed.fieldValues)
        #expect(try db.reader.read { try OutboxEntry.fetchCount($0) } == 2)
    }

    @Test("The due endpoint uses the due-date mutation so cards and reminders see it immediately")
    func dueDateUsesItsColumn() throws {
        let db = try AppDatabase.inMemory()
        let item = item(due: true)
        try db.writer.write { db in
            try Project(id: "P1", ownerLogin: "me", ownerIsOrg: false, number: 1, title: "Board", url: "", closed: false, viewerCanUpdate: true, dueFieldId: "E").insert(db)
            try item.insert(db)
        }
        let original = try #require(edit(item, due: true))
        let resized = original.adjusted(by: 3, part: .end)
        let changes = resized.mutations(from: original, item: item, dueFieldId: "E")
        #expect(changes == [.setDate(.init(itemId: "I1", projectId: "P1", date: Self.last.adding(days: 3).string, base: Self.last.string))])
        try db.writer.write { db in
            for change in changes { try Outbox.enqueue(db, change) }
        }
        let stored = try db.reader.read { try Item.fetchOne($0, key: "I1") }
        let changed = try #require(stored)
        #expect(changed.dueDate == Self.last.adding(days: 3).string)
        #expect(changed.fieldValues["E"] == nil)
        #expect(changed.fieldValues["S"] == item.fieldValues["S"])
    }

    @Test("A resize queues only its changed field, and a no-op queues nothing")
    func onlyChangedEndpoints() throws {
        let item = item()
        let original = try #require(edit(item))
        #expect(original.mutations(from: original, item: item, dueFieldId: nil).isEmpty)
        let changes = original.adjusted(by: 2, part: .start).mutations(from: original, item: item, dueFieldId: nil)
        #expect(changes.count == 1)
        guard case .setProjectField(let change) = changes.first else {
            Issue.record("Expected the start field to change")
            return
        }
        #expect(change.fieldId == "S")
        #expect(change.base?.date == Self.first.string)
    }

    @Test("A date changed by a refresh during the drag is not overwritten")
    func protectsConcurrentEdits() throws {
        let item = item()
        let original = try #require(edit(item))
        var refreshed = item
        refreshed.fieldValues["E"] = FieldValue(date: Self.last.adding(days: 1).string)
        #expect(original.adjusted(by: 3, part: .move).mutations(from: original, item: refreshed, dueFieldId: nil).isEmpty)
    }

    @Test("The bar's middle moves its dates; its edges resize and empty track does neither")
    func barTargets() {
        let layout = ViewTimelineLayout(rows: [], milestones: [], zoom: .months, available: 800, today: Self.first, scale: 10)
        let span = TimelineSpan.stretch(Self.first, Self.last)
        let rect = layout.rect(of: span, top: layout.rowTop(0))
        #expect(layout.editPart(at: CGPoint(x: rect.midX, y: rect.midY), row: 0, span: span, canResize: true) == .move)
        #expect(layout.editPart(at: CGPoint(x: rect.minX + 1, y: rect.midY), row: 0, span: span, canResize: true) == .start)
        #expect(layout.editPart(at: CGPoint(x: rect.maxX - 1, y: rect.midY), row: 0, span: span, canResize: true) == .end)
        #expect(layout.editPart(at: CGPoint(x: rect.maxX + 20, y: rect.midY), row: 0, span: span, canResize: true) == nil)
        #expect(layout.editPart(at: CGPoint(x: rect.midX, y: rect.maxY + 20), row: 0, span: span, canResize: true) == nil)
        #expect(layout.editPart(at: CGPoint(x: rect.minX + 1, y: rect.midY), row: 0, span: span, canResize: false) == .move)
    }

    @Test("Even a one-day bar at minimum zoom keeps a middle that can be moved")
    func narrowBarTargets() {
        let layout = ViewTimelineLayout(rows: [], milestones: [], zoom: .quarters, available: 800, today: Self.first, scale: TimelineZoom.minimumScale)
        let span = TimelineSpan.stretch(Self.first, Self.first)
        let rect = layout.rect(of: span, top: layout.rowTop(0))
        #expect(layout.editPart(at: CGPoint(x: rect.midX, y: rect.midY), row: 0, span: span, canResize: true) == .move)
        #expect(layout.editPart(at: CGPoint(x: rect.minX, y: rect.midY), row: 0, span: span, canResize: true) == .start)
        #expect(layout.editPart(at: CGPoint(x: rect.maxX, y: rect.midY), row: 0, span: span, canResize: true) == .end)
    }

    @Test("Filling a wide viewport never exceeds either timeline's date-scale limits", arguments: [CGFloat(0.01), CGFloat(100)])
    func layoutsRespectZoomBounds(requested: CGFloat) {
        let expected = requested < TimelineZoom.minimumScale ? TimelineZoom.minimumScale : TimelineZoom.maximumScale
        let issueLayout = ViewTimelineLayout(rows: [], milestones: [], zoom: .months, available: 100_000, today: Self.first, scale: requested)
        #expect(issueLayout.scale == expected)
        #expect(issueLayout.width >= 100_000)
        let roadmap = Roadmap(windows: [], rows: [], later: [])
        let epicLayout = TimelineLayout(roadmap: roadmap, zoom: .months, available: 100_000, today: Self.first, scale: requested)
        #expect(epicLayout.scale == expected)
        #expect(epicLayout.width >= 100_000)
    }
}
