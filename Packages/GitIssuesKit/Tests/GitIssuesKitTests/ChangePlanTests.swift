import Foundation
import Testing
@testable import GitIssuesKit

@Suite("Proposals the assistant makes, checked against the board")
struct ChangePlanTests {
    static let repo = "acme/app"
    static let footer = "_From the weekly sync of 13 Oct 2026._"
    static let text = """
    Kai: The emoji crash is fixed, it goes into review today.
    Jordan: The palette is done, we can close it.
    Mira takes the haptics when a card lands.
    """

    static func issue(_ number: Int, _ title: String, status: String? = "Todo", assignees: [String] = [], labels: [String] = [], body: String = "", open: Bool = true, created: Date? = nil) -> PlanIssue {
        PlanIssue(
            contentId: "I_\(number)", number: number, repo: repo, title: title, body: body, isOpen: open, stateReason: nil,
            status: status, priority: nil, due: nil, type: nil, milestone: nil, labels: labels, assignees: assignees,
            parent: nil, parentTitle: nil, createdAt: created, updatedAt: nil, closedAt: nil, commentCount: 0, onBoard: true
        )
    }

    static let facts = BoardFacts(
        projectTitle: "App", projectOwner: "acme", projectNumber: 1, repos: [repo],
        statuses: ["Backlog", "Todo", "In Progress", "In Review", "Done"], priorities: ["High", "Low"], hasDueField: true,
        repoFacts: [repo: RepoFacts(
            nameWithOwner: repo,
            labels: [.init(name: "bug", description: ""), .init(name: "ui", description: "")],
            issueTypes: [.init(name: "Task", description: ""), .init(name: "Bug", description: "")],
            people: [.init(name: "kai", description: "Kai Andersen"), .init(name: "mira", description: "Mira Patel")]
        )],
        milestones: [:], viewer: "jordan", viewerName: nil
    )

    static func builder(_ issues: [PlanIssue], snapshot: PlanSnapshot = .now) -> (PlanBuilder, PlanWorld) {
        let world = PlanWorld(facts: facts, issues: issues, api: nil, snapshot: snapshot)
        let input = PlanInput(title: "Weekly sync", date: "2026-10-13", text: text, footer: footer)
        return (PlanBuilder(world: world, facts: facts, input: input), world)
    }

    static func call(_ name: String, _ arguments: JSONValue) -> LLMToolCall {
        LLMToolCall(id: UUID().uuidString, name: name, arguments: arguments)
    }

    static let emptyUpdate: [String: JSONValue] = [
        "status": "", "priority": "", "due": "", "type": "", "milestone": "", "add_assignees": [], "remove_assignees": [],
        "add_labels": [], "remove_labels": [], "reason": "From the sync.", "quote": "",
    ]

    static func update(_ issue: String, _ fields: [String: JSONValue]) -> LLMToolCall {
        var arguments = emptyUpdate
        arguments["issue"] = .string(issue)
        for (key, value) in fields { arguments[key] = value }
        return call("propose_update", .object(arguments))
    }

    @Test("Quotes are checked against the text, word for word or nearly")
    func quotes() {
        let (builder, _) = Self.builder([])
        #expect(builder.quoteMatch("the palette is done, we can close it") == .exact)
        #expect(builder.quoteMatch("The emoji crash is fixed, it goes to review today") == .approximate)
        #expect(builder.quoteMatch("Theo will refactor the sync engine") == .missing)
    }

    @Test("A change to an issue that wasn't read first is refused")
    func readFirst() async {
        let (builder, _) = Self.builder([Self.issue(25, "Crash when a label contains an emoji")])
        let outcome = await builder.handle(Self.update("#25", ["status": "In Review"]))
        #expect(outcome.isError)
        #expect(builder.operations.isEmpty)
    }

    @Test("What already holds is dropped, the rest becomes one proposal per field")
    func reconciles() async {
        let (builder, _) = Self.builder([Self.issue(25, "Crash when a label contains an emoji", status: "Todo", assignees: ["kai"], labels: ["bug"])])
        _ = await builder.handle(Self.call("get_issues", ["numbers": [25]]))
        let outcome = await builder.handle(Self.update("#25", [
            "status": "in review", "add_assignees": ["@kai", "mira"], "add_labels": ["bug"],
            "quote": "The emoji crash is fixed, it goes into review today.",
        ]))
        #expect(!outcome.isError)
        let kinds = builder.operations.map(\.kind)
        #expect(kinds == [.setStatus, .assign])
        #expect(builder.operations[0].after == "In Review")
        #expect(builder.operations[0].before == "Todo")
        #expect(builder.operations[1].values == ["mira"])
        #expect(builder.dropped.count == 2)
        #expect(builder.operations.allSatisfy { $0.quoteMatch == .exact })
    }

    @Test("Unknown labels, statuses and people are refused with the options")
    func refusesUnknown() async {
        let (builder, _) = Self.builder([Self.issue(25, "Crash")])
        _ = await builder.handle(Self.call("get_issues", ["numbers": [25]]))
        let label = await builder.handle(Self.update("#25", ["add_labels": ["haptics"]]))
        #expect(label.isError && label.text.contains("bug, ui"))
        let person = await builder.handle(Self.update("#25", ["add_assignees": ["alex"]]))
        #expect(person.isError && person.text.contains("kai"))
        #expect(builder.operations.isEmpty)
    }

    @Test("A second comment from the same text is refused")
    func commentsOnce() async {
        let issue = Self.issue(17, "Command palette")
        let (builder, world) = Self.builder([issue])
        let earlier = Comment(id: "C1", issueId: "I_17", authorLogin: "jordan", authorAvatarUrl: nil, body: "Done.\n\n\(Self.footer)", createdAt: Date())
        await world.seed(PlanDetail(comments: [earlier], subIssues: [], blockedBy: [], blocking: []), for: issue)
        _ = await builder.handle(Self.call("get_issues", ["numbers": [17]]))
        let comment: JSONValue = ["issue": "#17", "body": "It's done.", "reason": "Decided.", "quote": "The palette is done"]
        let outcome = await builder.handle(Self.call("propose_comment", comment))
        #expect(outcome.isError)
    }

    @Test("Comments and new issues get the footer; closing needs the decision quoted")
    func footerAndClose() async {
        let (builder, _) = Self.builder([Self.issue(17, "Command palette")])
        _ = await builder.handle(Self.call("get_issues", ["numbers": [17]]))
        _ = await builder.handle(Self.call("propose_comment", ["issue": "#17", "body": "Done, see the sync.", "reason": "r", "quote": "The palette is done"]))
        #expect(builder.operations.first?.body == "Done, see the sync.\n\n\(Self.footer)")
        let unquoted = await builder.handle(Self.call("propose_close", ["issue": "#17", "close_reason": "completed", "duplicate_of": "", "reason": "r", "quote": "We never said that"]))
        #expect(unquoted.isError)
        let quoted = await builder.handle(Self.call("propose_close", ["issue": "#17", "close_reason": "completed", "duplicate_of": "", "reason": "r", "quote": "we can close it"]))
        #expect(!quoted.isError)
        #expect(builder.operations.last?.kind == .close)
    }

    @Test("New issues warn about look-alikes, refuse one made from the same text, and finish needs every ref")
    func newIssues() async {
        let made = Self.issue(30, "Haptic feedback when a card lands", body: "Mira.\n\n\(Self.footer)")
        let (builder, _) = Self.builder([Self.issue(9, "Drag cards between columns"), made])
        func new(_ ref: String, _ title: String, parent: String = "") -> LLMToolCall {
            Self.call("propose_new_issue", [
                "ref": .string(ref), "repo": "", "title": .string(title), "body": "See {{B}}.", "type": "Task", "status": "Todo",
                "priority": "", "due": "", "labels": ["ui"], "assignees": ["mira"], "parent": .string(parent), "reason": "r",
                "quote": "Mira takes the haptics when a card lands.",
            ])
        }
        let again = await builder.handle(new("A", "Haptic feedback when a card lands"))
        #expect(again.isError)
        let similar = await builder.handle(new("A", "Drag cards with haptic feedback between columns", parent: "#9"))
        #expect(!similar.isError)
        #expect(builder.operations.first?.warnings.contains { $0.contains("#9") } == true)
        let finish = await builder.handle(Self.call("finish", ["summary": "s", "skipped": []]))
        #expect(finish.isError, "{{B}} is used but never proposed")
        _ = await builder.handle(new("B", "Haptics settings"))
        let done = await builder.handle(Self.call("finish", ["summary": "s", "skipped": []]))
        #expect(done.finished)
    }

    @Test("A snapshot hides later issues and sets fields back")
    func snapshot() async {
        let meeting = Date(timeIntervalSince1970: 1_000_000)
        let snapshot = PlanSnapshot(asOf: meeting, issues: ["25": ["status": "Todo", "assignees": []]])
        let (_, world) = Self.builder([
            Self.issue(25, "Crash", status: "In Review", assignees: ["kai"], created: meeting.addingTimeInterval(-60)),
            Self.issue(31, "Made in the meeting", created: meeting.addingTimeInterval(60)),
        ], snapshot: snapshot)
        let issues = await world.allIssues()
        #expect(issues.map(\.number) == [25])
        #expect(issues.first?.status == "Todo")
        #expect(issues.first?.assignees == [])
    }
}

@Suite("What a run is guessed to cost before it starts")
struct PlanEstimateTests {
    // The meeting of the spike: 125 000 characters of transcript and 211 open issues.
    static func estimate(_ profile: ModelProfile) -> PlanEstimate {
        PlanEstimate.make(inputCharacters: 125_000, boardCharacters: 21_000, profile: profile)
    }

    @Test("The guess brackets what the measured runs cost")
    func bracketsMeasuredRuns() {
        let opus = Self.estimate(.claudeOpus)
        #expect(opus.openingTokens > 70_000 && opus.openingTokens < 85_000)
        // Measured: 1.42 $ in 7 rounds. (0.62 $ in 4 on the board after the meeting, when there was little left to do.)
        #expect(opus.cost.contains(1.42))
        #expect(opus.rounds.contains(7))
        let haiku = Self.estimate(.claudeHaiku)
        // Measured: 0.28 $ in 11 rounds and 0.12 $ in 6, most of it above 100 000 tokens.
        #expect(haiku.cost.contains(0.28) && haiku.cost.contains(0.12))
        #expect(haiku.largestPrompt.upperBound > 100_000)
        // The local run took 23 rounds and 34 minutes.
        let local = Self.estimate(.local("qwen3.5:9b"))
        #expect(local.rounds.contains(23) && local.seconds.contains(34 * 60))
    }

    @Test("Haiku costs five times as much once a request passes 100 000 tokens")
    func haikuTier() {
        let small = PlanEstimate.simulate(opening: 20_000, rounds: 8, profile: .claudeHaiku)
        let large = PlanEstimate.simulate(opening: 95_000, rounds: 8, profile: .claudeHaiku)
        #expect(small.largest < 100_000)
        #expect(large.cost > small.cost * 5)
    }

    @Test("A dictation of a few sentences takes few turns, and a local model costs nothing")
    func shortText() {
        let opus = PlanEstimate.make(inputCharacters: 600, boardCharacters: 21_000, profile: .claudeOpus)
        #expect(opus.rounds.upperBound <= 5)
        let local = PlanEstimate.make(inputCharacters: 600, boardCharacters: 21_000, profile: .local("qwen3.5:9b"))
        #expect(local.cost.upperBound == 0)
    }
}
