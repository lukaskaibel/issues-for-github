import Foundation
@testable import GitIssuesKit
import GRDB
import Security

// Proposes changes to a board's issues from a text, without changing anything: GitHub is read through a client
// that refuses every write, and the plan is only printed and saved. Usage:
//   gi-cli plan --project "Git Issues" --input notes.md --title "Weekly Sync" --date 2026-10-12 --footer "…" \
//       --provider anthropic|openAI|google|ollama --model claude-opus-5-5 [--effort high] [--db board.sqlite]
//       [--refresh] [--snapshot asof.json] [--out plan.json] [--people "Name=login,…"] [--num-ctx 131072]
//       [--key-env VAR | --keychain] [--max-rounds 24]
enum PlanCommand {
    static func run(_ arguments: [String]) async throws {
        var options: [String: String] = [:]
        var flags: Set<String> = []
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            guard argument.hasPrefix("--") else { throw CLIError("Unexpected argument \(argument)") }
            let name = String(argument.dropFirst(2))
            if index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") {
                options[name] = arguments[index + 1]
                index += 2
            } else {
                flags.insert(name)
                index += 1
            }
        }
        func required(_ name: String) throws -> String {
            guard let value = options[name] else { throw CLIError("--\(name) is required") }
            return value
        }

        var text = try String(contentsOfFile: try required("input"), encoding: .utf8)
        if flags.contains("merge-turns") { text = mergingTurns(text) }
        let input = PlanInput(title: try required("title"), date: try required("date"), text: text, footer: try required("footer"))
        guard let kind = LLMProviderKind(rawValue: try required("provider")) else { throw CLIError("--provider: anthropic, openAI, google or ollama") }
        let model = try required("model")

        // The board, read into a database of its own. Nothing is ever written to GitHub.
        let dbPath = options["db"] ?? NSTemporaryDirectory() + "gi-plan.sqlite"
        let db = try AppDatabase.onDisk(at: URL(fileURLWithPath: dbPath))
        let api = GitHubAPI(client: GraphQLClient(tokenSource: CLITokens(), readOnly: true))
        let status = await MainActor.run { SyncStatus() }
        let engine = SyncEngine(db: db, api: api, status: status)
        let projectTitle = try required("project")
        var project = try db.projects().first { $0.title.localizedCaseInsensitiveContains(projectTitle) }
        if project == nil || flags.contains("refresh") {
            log("Reading the board from GitHub …")
            try await engine.refreshProjects()
            let found = try findProject(db, title: projectTitle)
            project = found
            try await engine.pull(projectId: found.id)
            let repoIds = try await db.reader.read { db in
                try String.fetchAll(db, sql: "SELECT id FROM repo WHERE projectId = ?", arguments: [found.id])
            }
            for repoId in repoIds { try await engine.pullRepository(repoId) }
        }
        guard let project else { throw CLIError("No project matching \"\(projectTitle)\".") }

        var snapshot = PlanSnapshot.now
        if let path = options["snapshot"] {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            snapshot = try decoder.decode(PlanSnapshot.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        }
        let world = try await PlanWorld.load(db: db, api: api, projectId: project.id, snapshot: snapshot)
        let issues = await world.allIssues()
        log("Board \"\(project.title)\": \(issues.filter(\.isOpen).count) open and \(issues.filter { !$0.isOpen }.count) closed issues\(snapshot.asOf.map { " as of \($0.formatted(.iso8601))" } ?? "").")

        var people: [String: String] = [:]
        for pair in (options["people"] ?? "").split(separator: ",") {
            let parts = pair.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 { people[parts[0]] = parts[1] }
        }
        var limits = PlannerLimits()
        if let rounds = options["max-rounds"].flatMap(Int.init) { limits.maxRounds = rounds }
        if let seconds = options["max-seconds"].flatMap(Double.init) { limits.maxSeconds = seconds }
        limits.maxPromptTokens = options["max-prompt"].flatMap(Int.init)
        if let path = options["context-only"] {
            // What the model would get first, to read before spending tokens.
            let open = issues.filter(\.isOpen)
            let style = PlanStyle(people: people)
            let opening = PlanText.system(style: style, input: input, viewer: world.facts.viewer)
                + "\n\n=====\n\n" + PlanText.context(facts: world.facts, open: open, input: input)
            try opening.write(toFile: path, atomically: true, encoding: .utf8)
            log("Opening written to \(path): \(opening.count) characters.")
            return
        }

        let provider: any LLMProvider
        switch kind {
        case .ollama:
            let context = options["num-ctx"].flatMap(Int.init) ?? 131_072
            provider = OllamaProvider(contextTokens: context, think: options["think"].map { $0 == "true" } ?? true)
        default:
            let key = try apiKey(for: kind, options: options, flags: flags)
            provider = switch kind {
            case .anthropic: AnthropicProvider(apiKey: key)
            case .openAI: OpenAIProvider(apiKey: key)
            default: GeminiProvider(apiKey: key)
            }
        }
        let planner = ChangePlanner(
            provider: provider, model: model, effort: options["effort"], world: world, input: input,
            style: PlanStyle(people: people), limits: limits
        )
        let opening = await planner.openingCharacters()
        log("Opening context: \(opening) characters, about \(opening / 3) tokens.")
        let boardCharacters = issues.filter(\.isOpen).map { PlanText.indexLine($0).count + 1 }.reduce(0, +)
        let estimate = ModelProfile.profile(for: model, provider: kind).map {
            PlanEstimate.make(inputCharacters: input.text.count, boardCharacters: boardCharacters, profile: $0)
        }
        if let estimate { log("Estimate: " + describe(estimate)) }
        if case .ollama = kind, let context = options["num-ctx"].flatMap(Int.init) ?? Optional(131_072), opening / 3 > context * 7 / 10 {
            throw CLIError("The opening alone needs about \(opening / 3) tokens; --num-ctx \(context) is too small.")
        }

        let plan = try await planner.run { event in
            switch event {
            case .round(let number, let usage):
                log("── round \(number) · input \(usage.input) + cached \(usage.cacheRead) + cache write \(usage.cacheWrite) · output \(usage.output)")
            case .call(let name, let arguments):
                log("→ \(name) \(arguments.prefix(220))")
            case .result(_, let text, let isError):
                log("  \(isError ? "✗" : "✓") \(text.split(separator: "\n").prefix(isError ? 4 : 2).joined(separator: " ⏎ ").prefix(260))")
            case .said(let text):
                log("  » \(text.replacingOccurrences(of: "\n", with: " ").prefix(300))")
            case .note(let text):
                log("  ! \(text)")
            }
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let out = options["out"] ?? NSTemporaryDirectory() + "gi-plan.json"
        try encoder.encode(plan).write(to: URL(fileURLWithPath: out))
        print(render(plan))
        if let estimate { log("Estimate before the run: " + describe(estimate)) }
        log("Plan written to \(out)")
    }

    /// A transcript as Transcripts exports it, "**Name** (1:02): text" per segment, with a speaker's consecutive
    /// segments joined into one turn. Same words, fewer tokens.
    static func mergingTurns(_ text: String) -> String {
        var lines: [String] = []
        var speaker: String?
        for line in text.components(separatedBy: "\n") {
            guard let match = line.wholeMatch(of: #/\*\*([^*]+)\*\* \(([0-9:]+)\): (.*)/#) else {
                if !line.trimmingCharacters(in: .whitespaces).isEmpty { speaker = nil }
                if !(line.isEmpty && speaker != nil) { lines.append(line) }
                continue
            }
            let (name, time, said) = (String(match.output.1), String(match.output.2), String(match.output.3))
            if name == speaker, let last = lines.indices.last {
                lines[last] += " " + said
            } else {
                lines.append("\(name) (\(time)): \(said)")
                speaker = name
            }
        }
        return lines.joined(separator: "\n")
    }

    static func describe(_ estimate: PlanEstimate) -> String {
        let cost = estimate.cost.upperBound == 0 ? "free" : String(format: "$%.3f–%.3f", estimate.cost.lowerBound, estimate.cost.upperBound)
        return "opening \(estimate.openingTokens) tokens, \(estimate.rounds.lowerBound)–\(estimate.rounds.upperBound) rounds, "
            + "largest request \(estimate.largestPrompt.lowerBound)–\(estimate.largestPrompt.upperBound), \(cost), "
            + "\(Int(estimate.seconds.lowerBound / 60))–\(Int(estimate.seconds.upperBound / 60 + 1)) min"
    }

    static func render(_ plan: ChangePlan) -> String {
        var lines = ["# Plan: \(plan.input.title) (\(plan.provider) \(plan.model))", ""]
        lines.append("\(plan.operations.count) operations, \(plan.dropped.count) dropped, \(plan.skipped.count) skipped; finished: \(plan.finished) (\(plan.stats.stopReason))")
        let usage = plan.stats.usage
        lines.append("rounds \(plan.stats.rounds), calls \(plan.stats.toolCalls.values.reduce(0, +)) \(plan.stats.toolCalls.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")), rejected \(plan.stats.rejected)")
        lines.append("tokens: input \(usage.input), cached \(usage.cacheRead), cache write \(usage.cacheWrite), output \(usage.output); largest request \(plan.stats.largestPrompt); \(Int(plan.stats.seconds)) s")
        lines.append("")
        for operation in plan.operations {
            var line = "- \(operation.id) \(operation.issue) \(operation.kind.rawValue)"
            if let value = operation.value { line += " \(value)" }
            if let values = operation.values { line += " \(values.joined(separator: ", "))" }
            if let title = operation.title { line += " \"\(title)\"" }
            if let new = operation.newIssue {
                line += " [" + [new.type, new.status, new.priority, new.due, new.parent.map { "parent \($0)" }].compactMap { $0 }.joined(separator: ", ")
                line += new.labels.isEmpty ? "" : "; labels \(new.labels.joined(separator: ", "))"
                line += new.assignees.isEmpty ? "" : "; @\(new.assignees.joined(separator: " @"))"
                line += "]"
            }
            if let before = operation.before { line += " (was \(before))" }
            line += " · quote \(operation.quoteMatch.rawValue)"
            if !operation.warnings.isEmpty { line += " · ⚠︎ \(operation.warnings.joined(separator: " / "))" }
            lines.append(line)
            lines.append("    why: \(operation.reason)")
            if let body = operation.body, operation.kind != .editBody {
                lines.append(body.split(separator: "\n", omittingEmptySubsequences: false).map { "    | \($0)" }.joined(separator: "\n"))
            }
        }
        if !plan.dropped.isEmpty {
            lines.append("")
            lines.append("Dropped (already so):")
            lines += plan.dropped.map { "- \($0.what)" }
        }
        if !plan.skipped.isEmpty {
            lines.append("")
            lines.append("Skipped:")
            lines += plan.skipped.map { "- \($0.what): \($0.why)" }
        }
        if !plan.summary.isEmpty {
            lines.append("")
            lines.append("Summary: \(plan.summary)")
        }
        return lines.joined(separator: "\n")
    }

    /// From an environment variable, or from the keychain entry Transcripts keeps for the same provider (macOS asks
    /// once whether this tool may read it).
    static func apiKey(for kind: LLMProviderKind, options: [String: String], flags: Set<String>) throws -> String {
        if let variable = options["key-env"], let key = ProcessInfo.processInfo.environment[variable], !key.isEmpty { return key }
        if flags.contains("keychain") {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "com.lukaskbl.Transcripts.api-keys",
                kSecAttrAccount as String: kind.rawValue,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            guard status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
                throw CLIError("No \(kind.rawValue) key in the keychain (status \(status)).")
            }
            return key
        }
        throw CLIError("Give the key with --key-env VARIABLE or --keychain.")
    }

    static func log(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }
}
