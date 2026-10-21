import Testing
@testable import GitIssuesKit

@Suite("Where the keyboard focus goes when its issue leaves")
@MainActor
struct FocusTests {
    let columns = [["a", "b", "c"], ["d"], [], ["e", "f"]]

    @Test("To the next issue in its column, else the one before it")
    func sameColumn() {
        #expect(AppModel.neighbour(of: "b", in: columns) { $0 != "b" } == "c")
        #expect(AppModel.neighbour(of: "c", in: columns) { $0 != "c" } == "b")
        #expect(AppModel.neighbour(of: "b", in: columns) { !["b", "c"].contains($0) } == "a")
    }

    @Test("With its column empty, to the next column's first issue, else the last one before")
    func otherColumns() {
        #expect(AppModel.neighbour(of: "d", in: columns) { $0 != "d" } == "e")
        #expect(AppModel.neighbour(of: "f", in: columns) { !["e", "f"].contains($0) } == "d")
        #expect(AppModel.neighbour(of: "a", in: columns) { _ in false } == nil)
        #expect(AppModel.neighbour(of: "x", in: columns) { _ in true } == nil)
    }
}
