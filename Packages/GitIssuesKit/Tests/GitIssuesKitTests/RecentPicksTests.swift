import Foundation
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

    /// The log after these picks, made in this order (the last one latest).
    private func log(_ picks: String...) -> [String] {
        picks.reduce([]) { log, pick in AppModel.noting(pick, in: log) }
    }

    /// The rows a picker shows first, with nothing typed.
    private func recentFirst(_ rows: [PickerItem], log: [String], key: (PickerItem) -> String = { $0.id }) -> [PickerItem] {
        let (recent, rest) = AppModel.splitRecent(rows, recent: AppModel.ranked(log), key: key) { !$0.selected && !$0.alwaysShown && !$0.creates }
        return recent + rest
    }

    // MARK: Ranking

    @Test("With nothing chosen twice, the choice made last comes first")
    func latestFirst() {
        #expect(AppModel.ranked(log("a", "b", "c")) == ["c", "b", "a"])
        #expect(AppModel.ranked([]) == [])
    }

    @Test("A choice made twice in a row comes first, however long another was chosen before")
    func twiceInARow() {
        #expect(AppModel.ranked(log("p", "p", "q", "q")).first == "q")
        var picks = Array(repeating: "p", count: 30).reduce([String]()) { AppModel.noting($1, in: $0) }
        picks = AppModel.noting("q", in: picks)
        #expect(AppModel.ranked(picks).first == "p", "one other choice after a long run doesn't take the top")
        picks = AppModel.noting("q", in: picks)
        #expect(AppModel.ranked(picks).first == "q", "made twice in a row, it does")
    }

    @Test("Going through issues that all get one parent, the one that went elsewhere doesn't take its place")
    func oneOffAfterARun() {
        #expect(AppModel.ranked(log("p", "p", "q")) == ["p", "q"])
        #expect(AppModel.ranked(log("p", "p", "p", "p", "q")) == ["p", "q"])
        // After two more for the run's choice, the other is still offered second.
        #expect(AppModel.ranked(log("p", "p", "q", "p", "p")) == ["p", "q"])
    }

    @Test("Taking turns between two, the one chosen last comes first")
    func takingTurns() {
        #expect(AppModel.ranked(log("p", "q", "p", "q")).first == "q")
        #expect(AppModel.ranked(log("q", "p", "q", "p")).first == "p")
    }

    @Test("Recent picks saved before this ranking keep their order")
    func savedBefore() {
        // An older version kept each choice once, latest first.
        #expect(AppModel.ranked(["c", "b", "a"]) == ["c", "b", "a"])
    }

    // MARK: The log

    @Test("Picks are kept with their repeats, latest first")
    func repeatsKept() {
        #expect(log("a", "b", "b") == ["b", "b", "a"])
        #expect(AppModel.noting("z", in: []) == ["z"])
    }

    @Test("Eight different choices are kept; the least likely goes")
    func eightKept() {
        let many = (1...8).map(String.init)
        // Saved before: each once, latest first.
        #expect(AppModel.noting("new", in: many) == ["new"] + (1...7).map(String.init))
        // A choice made often a while ago outlasts one made once since.
        let picks = log("often", "often", "often", "1", "2", "3", "4", "5", "6", "7", "8")
        #expect(Set(picks).count == 8)
        #expect(picks.contains("often"))
        #expect(!picks.contains("1"))
    }

    @Test("A long run of one choice doesn't push the others out")
    func longRun() {
        var picks = log("a", "b", "c")
        for _ in 0..<40 { picks = AppModel.noting("p", in: picks) }
        #expect(picks.count == 24)
        #expect(AppModel.ranked(picks) == ["p", "c", "b", "a"])
    }

    @Test("One change to several issues at once is one pick")
    func samePick() {
        let now = Date(timeIntervalSinceReferenceDate: 1000)
        let last = (kind: RecentPick.label, key: "bug", date: now)
        #expect(AppModel.isSamePick(as: last, .label, "bug", at: now.addingTimeInterval(0.01)))
        #expect(!AppModel.isSamePick(as: last, .label, "bug", at: now.addingTimeInterval(5)), "the same again later is another pick")
        #expect(!AppModel.isSamePick(as: last, .label, "ui", at: now))
        #expect(!AppModel.isSamePick(as: last, .assignee, "bug", at: now))
        #expect(!AppModel.isSamePick(as: nil, .label, "bug", at: now))
    }

    // MARK: Rows

    @Test("Recent rows come first, likeliest first, at most three, the rest in their order")
    func order() {
        let result = recentFirst(rows(["a", "b", "c", "d", "e", "f"]), log: log("c", "f", "b", "x", "e"))
        #expect(result.map(\.id) == ["e", "b", "f", "a", "c", "d"])
    }

    @Test("Recent rows go above Remove and the current parent, at the very top")
    func veryTop() {
        let result = recentFirst(rows(["remove", "current", "a", "b"], selected: ["current"]), log: log("b"))
        #expect(result.map(\.id) == ["b", "remove", "current", "a"])
    }

    @Test("Checked rows and rows that are always there don't move up")
    func checkedStay() {
        let result = recentFirst(rows(["a", "b", "c", "new"], selected: ["b"], alwaysShown: ["new"]), log: log("c", "b", "new"))
        #expect(result.map(\.id) == ["c", "a", "b", "new"])
    }

    @Test("Labels are matched by name, since every repository has its own")
    func byName() {
        let result = recentFirst(rows(["L1", "L2"]), log: log("L2"), key: \.title)
        #expect(result.map(\.id) == ["L2", "L1"])
    }

    @Test("Nothing chosen lately leaves the rows alone")
    func nothingRecent() {
        let result = recentFirst(rows(["a", "b"]), log: [])
        #expect(result.map(\.id) == ["a", "b"])
    }

    @Test("Values that aren't rows, such as a menu's people, split the same way")
    func split() {
        let people = ["ann", "bob", "cid", "dan"]
        let (recent, rest) = AppModel.splitRecent(people, recent: AppModel.ranked(log("dan", "bob", "bob")), key: { $0 }) { $0 != "bob" }
        #expect(recent == ["dan"], "bob is assigned already")
        #expect(rest == ["ann", "bob", "cid"])
    }

    // MARK: Adding sub-issues

    @Test("Adding a sub-issue offers the open issues you made in the last day that are under nothing, newest first")
    func freshIssues() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        func issue(_ id: String, by author: String = "me", hoursAgo: Double, parent: String? = nil, state: String = "OPEN") -> Item {
            var item = Item(id: id, projectId: "P1", kind: .issue, position: 0, number: 1, title: id, body: "", state: state)
            item.authorLogin = author
            item.createdAt = now.addingTimeInterval(-hoursAgo * 3600)
            item.parentId = parent
            return item
        }
        let candidates = [
            issue("old", hoursAgo: 30),
            issue("a", hoursAgo: 5),
            issue("theirs", by: "someone", hoursAgo: 1),
            issue("b", hoursAgo: 1),
            issue("placed", hoursAgo: 2, parent: "X"),
            issue("done", hoursAgo: 2, state: "CLOSED"),
            issue("c", hoursAgo: 3),
            issue("d", hoursAgo: 4),
        ]
        #expect(AppModel.freshIssues(candidates, by: "me", now: now).map(\.id) == ["b", "c", "d"])
        #expect(AppModel.freshIssues(candidates, by: nil, now: now).isEmpty)
    }
}
