import SwiftUI
import Testing
@testable import GitIssuesKit

@Suite("Pickers offer what was chosen lately first")
@MainActor
struct RecentPicksTests {
    private func rows(_ ids: [String], selected: Set<String> = [], alwaysShown: Set<String> = []) -> [PickerItem] {
        ids.map { id in
            PickerItem(id: id, title: id.uppercased(), selected: selected.contains(id), icon: AnyView(EmptyView()), alwaysShown: alwaysShown.contains(id))
        }
    }

    @Test("A choice goes to the front once, and only the last eight are kept")
    func noting() {
        #expect(AppModel.noting("b", in: ["a", "b", "c"]) == ["b", "a", "c"])
        #expect(AppModel.noting("z", in: []) == ["z"])
        let many = (1...8).map(String.init)
        #expect(AppModel.noting("new", in: many) == ["new"] + (1...7).map(String.init))
    }

    @Test("Recent rows come first, most recent first, at most three, the rest in their order")
    func order() {
        let result = AppModel.recentFirst(rows(["a", "b", "c", "d", "e", "f"]), recent: ["e", "x", "b", "f", "c"])
        #expect(result.map(\.id) == ["e", "b", "f", "a", "c", "d"])
        #expect(result.map(\.recent) == [true, true, true, false, false, false])
    }

    @Test("Leading rows such as Remove and the current parent stay in front")
    func lead() {
        let result = AppModel.recentFirst(rows(["remove", "current", "a", "b"], selected: ["current"]), recent: ["b"], after: 2)
        #expect(result.map(\.id) == ["remove", "current", "b", "a"])
    }

    @Test("Checked rows and rows that are always there don't move up")
    func checkedStay() {
        let result = AppModel.recentFirst(rows(["a", "b", "c", "new"], selected: ["b"], alwaysShown: ["new"]), recent: ["new", "b", "c"])
        #expect(result.map(\.id) == ["c", "a", "b", "new"])
        #expect(result.filter(\.recent).map(\.id) == ["c"])
    }

    @Test("Labels are matched by name, since every repository has its own")
    func byName() {
        let result = AppModel.recentFirst(rows(["L1", "L2"]), recent: ["L2"], key: \.title)
        #expect(result.map(\.id) == ["L2", "L1"])
    }

    @Test("Nothing chosen lately leaves the rows alone")
    func nothingRecent() {
        let result = AppModel.recentFirst(rows(["a", "b"]), recent: [])
        #expect(result.map(\.id) == ["a", "b"])
        #expect(result.filter(\.recent).isEmpty)
    }
}
