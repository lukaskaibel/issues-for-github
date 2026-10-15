import Foundation
import Testing
@testable import GitIssuesKit
#if os(macOS)
import AppKit
#endif

@MainActor
@Suite("A project's glyph and colour, kept by the app since GitHub has none")
struct ProjectLooksTests {
    static let globe = ProjectGlyph(key: "globe")!

    @Test func aProjectStartsAsGitHubsTableInGrey() {
        let looks = ProjectLooks(persistent: false)
        #expect(looks.look("p1") == .standard)
        #expect(ProjectLook.standard == ProjectLook(glyph: .table, color: "GRAY"))
        #expect(ProjectGlyph.table.systemName == "tablecells")
    }

    @Test func aPickedLookStaysWithItsProject() {
        let looks = ProjectLooks(persistent: false)
        looks.set(ProjectLook(glyph: Self.globe, color: "GREEN"), for: "p1")
        #expect(looks.look("p1") == ProjectLook(glyph: Self.globe, color: "GREEN"))
        #expect(looks.look("p2") == .standard)
    }

    @Test func goingBackToTheTableIsKeptForOtherDevices() {
        let looks = ProjectLooks(persistent: false, initial: ["p1": ProjectLook(glyph: ProjectGlyph(key: "bug")!, color: "RED")])
        looks.set(.standard, for: "p1")
        #expect(looks.look("p1") == .standard)
        // A record, not a gap, so a device that still has the red bug takes the newer table.
        #expect(looks.records["p1"]?.look == .standard)
        #expect(looks.records["p1"].map { $0.modified > .distantPast } == true)
    }

    @Test func aLookIsSavedByTheGlyphsKey() throws {
        let data = try JSONEncoder().encode(ProjectLook(glyph: Self.globe, color: "GREEN"))
        #expect(String(decoding: data, as: UTF8.self).contains(#""glyph":"globe""#))
        #expect(try JSONDecoder().decode(ProjectLook.self, from: data) == ProjectLook(glyph: Self.globe, color: "GREEN"))
    }

    @Test func aGlyphFromANewerVersionShowsAsTheTable() throws {
        let data = Data(#"{"glyph":"unicorn","color":"PINK"}"#.utf8)
        let look = try JSONDecoder().decode(ProjectLook.self, from: data)
        #expect(look == ProjectLook(glyph: .table, color: "PINK"))
    }

    @Test func everyGlyphHasItsOwnKeyAndSymbolAndAGroup() {
        let all = ProjectGlyph.all
        #expect(all.count >= 250)
        #expect(Set(all.map(\.key)).count == all.count)
        #expect(Set(all.map(\.systemName)).count == all.count)
        #expect(ProjectGlyphGroup.allCases.allSatisfy { !$0.glyphs.isEmpty })
        #expect(ProjectGlyphGroup.allCases.flatMap(\.glyphs) == all, "groups in the order of the list")
        // The Mac's picker opens on the project's group, heading and all, which takes five rows of eight at most.
        #expect(ProjectGlyphGroup.allCases.allSatisfy { $0.glyphs.count <= 40 })
    }

    @Test func searchFindsGlyphsByTheirNameOrTheirGroup() {
        #expect(ProjectGlyph.matching("").count == ProjectGlyph.all.count)
        #expect(ProjectGlyph.matching("  ").count == ProjectGlyph.all.count)
        #expect(ProjectGlyph.matching("paw").map(\.key) == ["paw"])
        #expect(ProjectGlyph.matching("GLOBE").contains(Self.globe))
        // A group's name finds all of it.
        let animals = ProjectGlyph.matching("animals")
        #expect(Set(animals) == Set(ProjectGlyphGroup.animals.glyphs))
        #expect(ProjectGlyph.matching("unicorn").isEmpty)
    }

    #if os(macOS)
    @Test func theArrowKeysMoveThroughTheColoursAndTheGlyphs() {
        typealias Picker = ProjectIconPicker
        let glyphs = ProjectGlyph.all
        // Two full rows and a short one, as a group shows them.
        let rows = [Array(glyphs[0..<8]), Array(glyphs[8..<16]), Array(glyphs[16..<19])]
        let spot = { (glyph: ProjectGlyph) in Picker.Spot.glyph(glyph.key) }
        // Down keeps the column, or ends on the last glyph of a short row; at the bottom it stays.
        #expect(Picker.vertical(from: spot(glyphs[2]), by: 1, rows: rows) == spot(glyphs[10]))
        #expect(Picker.vertical(from: spot(glyphs[13]), by: 1, rows: rows) == spot(glyphs[18]))
        #expect(Picker.vertical(from: spot(glyphs[17]), by: 1, rows: rows) == spot(glyphs[17]))
        // Up from the first row goes into the colours, and down from them comes back.
        #expect(Picker.vertical(from: spot(glyphs[5]), by: -1, rows: rows) == .color(5))
        #expect(Picker.vertical(from: .color(5), by: -1, rows: rows) == .color(5))
        #expect(Picker.vertical(from: .color(3), by: 1, rows: rows) == spot(glyphs[3]))
        // Sideways runs on into the next row and stops at the ends; the colours go round.
        #expect(Picker.sideways(from: spot(glyphs[7]), by: 1, rows: rows) == spot(glyphs[8]))
        #expect(Picker.sideways(from: spot(glyphs[0]), by: -1, rows: rows) == spot(glyphs[0]))
        #expect(Picker.sideways(from: spot(glyphs[18]), by: 1, rows: rows) == spot(glyphs[18]))
        #expect(Picker.sideways(from: .color(7), by: 1, rows: rows) == .color(0))
        // A glyph that isn't on screen (the search changed) has nowhere to go from.
        #expect(Picker.vertical(from: spot(glyphs[40]), by: 1, rows: rows) == nil)
    }

    @Test func everyGlyphIsASymbolTheSystemHas() {
        for glyph in ProjectGlyph.all {
            #expect(NSImage(systemSymbolName: glyph.systemName, accessibilityDescription: nil) != nil, "\(glyph.systemName)")
        }
    }
    #endif
}
