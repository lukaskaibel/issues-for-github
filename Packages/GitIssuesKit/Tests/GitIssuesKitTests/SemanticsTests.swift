import Testing
@testable import GitIssuesKit

@Suite("Meaning inferred from column and option names")
struct SemanticsTests {
    @Test(arguments: [
        ("Backlog", StatusCategory.backlog), ("Icebox", .backlog), ("Triage", .backlog),
        ("Todo", .unstarted), ("To do", .unstarted), ("Up Next", .unstarted), ("Open", .unstarted), ("Ready", .unstarted),
        ("In Progress", .started), ("In Review", .started), ("Ready for review", .started), ("Blocked", .started),
        ("Needs Discussion", .started),
        ("Done", .completed), ("Shipped", .completed), ("Closed", .completed),
        ("Canceled", .canceled), ("Won't do", .canceled), ("Duplicate", .canceled),
    ])
    func statusCategory(name: String, expected: StatusCategory) {
        #expect(StatusCategory.infer(from: name) == expected)
    }

    @Test func onlyClosedCategoriesCloseTheIssue() {
        #expect(StatusCategory.completed.closeReason == "COMPLETED")
        #expect(StatusCategory.canceled.closeReason == "NOT_PLANNED")
        #expect(StatusCategory.started.closeReason == nil)
        #expect(StatusCategory.backlog.closeReason == nil)
    }

    @Test(arguments: [
        ("Urgent", PriorityLevel.urgent), ("P0", .urgent), ("Critical", .urgent),
        ("High", .high), ("P1", .high), ("Medium", .medium), ("P2", .medium), ("Low", .low), ("P3", .low),
    ])
    func priorityLevel(name: String, expected: PriorityLevel) {
        #expect(PriorityLevel.infer(from: name) == expected)
    }

    @Test func fuzzyMatchingFindsSubsequencesAndRanksPrefixesFirst() {
        #expect(fuzzyScore("cps", "Change priority and status") != nil)
        #expect(fuzzyScore("xyz", "Change status") == nil)
        let prefix = fuzzyScore("sta", "Status")!
        let scattered = fuzzyScore("sta", "Set a target")!
        #expect(prefix > scattered)
    }
}

@Suite("Branch names copied for an issue")
struct BranchNameTests {
    private func item(_ number: Int?, _ title: String) -> Item {
        Item(id: "PVTI_1", projectId: "PVT_1", kind: .issue, position: 0, number: number, title: title, body: "", state: "OPEN")
    }

    @Test(arguments: [
        ("Sign in with GitHub device flow", "14-sign-in-with-github-device-flow"),
        ("Fix: Zurückziehen von Antworten!", "14-fix-zuruckziehen-von-antworten"),
        ("  --Leading and trailing--  ", "14-leading-and-trailing"),
        ("🚀", "14"),
    ])
    func followsGitHub(title: String, expected: String) {
        #expect(item(14, title).branchName == expected)
    }

    @Test func staysShort() {
        let name = item(7, String(repeating: "word ", count: 40)).branchName ?? ""
        #expect(name.count <= 62)
        #expect(!name.hasSuffix("-"))
    }

    @Test func draftsHaveNone() {
        #expect(item(nil, "A draft").branchName == nil)
    }
}
