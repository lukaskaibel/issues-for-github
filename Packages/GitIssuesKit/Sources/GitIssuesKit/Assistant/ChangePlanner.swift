import Foundation

/// How far a run may go before it has to finish.
public struct PlannerLimits: Sendable {
    public var maxRounds = 24
    public var maxSeconds: TimeInterval = 1200
    /// Input tokens over all rounds, cached ones included.
    public var maxInputTokens = 3_000_000
    public var maxOutputTokensPerTurn = 16_000
    /// Malformed or refused calls in a row before the run gives up.
    public var maxFailuresInARow = 6
    /// The most one request may read. Some models cost several times as much above a size (Claude Haiku 5.5 above
    /// 100 000 tokens), so the run finishes before a request gets there.
    public var maxPromptTokens: Int?

    public init() {}
}

/// What a run is doing, for a progress display.
public enum PlannerEvent: Sendable {
    case round(Int, usage: LLMUsage)
    case call(name: String, arguments: String)
    case result(name: String, text: String, isError: Bool)
    case said(String)
    case note(String)
}

/// The assistant's loop: the model reads the board and proposes changes through tools, the app answers each call,
/// until the model calls finish or a limit is reached. Nothing is written anywhere; the result is a plan to review.
public actor ChangePlanner {
    let provider: any LLMProvider
    let model: String
    let effort: String?
    let world: PlanWorld
    let input: PlanInput
    let style: PlanStyle
    let limits: PlannerLimits

    public init(provider: any LLMProvider, model: String, effort: String? = nil, world: PlanWorld, input: PlanInput, style: PlanStyle = PlanStyle(), limits: PlannerLimits = PlannerLimits()) {
        self.provider = provider
        self.model = model
        self.effort = effort
        self.world = world
        self.input = input
        self.style = style
        self.limits = limits
    }

    public func run(onEvent: @escaping @Sendable (PlannerEvent) -> Void = { _ in }) async throws -> ChangePlan {
        let started = Date()
        let facts = world.facts
        let open = await world.allIssues().filter(\.isOpen)
        let builder = PlanBuilder(world: world, facts: facts, input: input)
        let system = PlanText.system(style: style, input: input, viewer: facts.viewer)
        var messages: [LLMMessage] = [.user(PlanText.context(facts: facts, open: open, input: input), cache: true)]
        var stats = PlanStats()
        var nudges = 0
        var failures = 0
        var lastCall = false
        var lastPrompt = 0

        while !builder.finished {
            try Task.checkCancellation()
            stats.rounds += 1
            let elapsed = Date().timeIntervalSince(started)
            let promptFull = limits.maxPromptTokens.map { lastPrompt > Int(Double($0) * 0.85) } ?? false
            if !lastCall, stats.rounds >= limits.maxRounds || elapsed > limits.maxSeconds * 0.85
                || stats.usage.totalInput > Int(Double(limits.maxInputTokens) * 0.85) || promptFull {
                lastCall = true
                // The newest message hasn't been sent yet, so the request to finish can still go into it.
                messages[messages.count - 1].text += (messages[messages.count - 1].text.isEmpty ? "" : "\n\n") + PlanText.finishNow()
                onEvent(.note(PlanText.finishNow()))
            }
            let choice: LLMToolChoice = lastCall && provider.canForceToolChoice(model: model) ? .named("finish") : .auto
            let response = try await provider.respond(LLMChatRequest(
                model: model, system: system, messages: messages, tools: PlanText.tools, toolChoice: choice,
                maxOutputTokens: limits.maxOutputTokensPerTurn, effort: effort
            ))
            stats.usage = stats.usage + response.usage
            lastPrompt = response.usage.totalInput
            stats.largestPrompt = max(stats.largestPrompt, lastPrompt)
            onEvent(.round(stats.rounds, usage: stats.usage))
            messages.append(response.message)
            if !response.message.text.isEmpty { onEvent(.said(response.message.text)) }

            if response.message.toolCalls.isEmpty {
                if lastCall || nudges >= 2 {
                    stats.stopReason = "no tool call"
                    break
                }
                nudges += 1
                messages.append(.user(response.stop == .maxTokens ? PlanText.cutOff() : PlanText.nudge()))
                continue
            }

            var results: [LLMToolResult] = []
            for call in response.message.toolCalls {
                stats.toolCalls[call.name, default: 0] += 1
                onEvent(.call(name: call.name, arguments: call.unreadable ?? call.arguments.jsonText))
                let outcome = await builder.handle(call)
                if outcome.isError {
                    stats.rejected += 1
                    failures += 1
                } else {
                    failures = 0
                }
                onEvent(.result(name: call.name, text: outcome.text, isError: outcome.isError))
                results.append(LLMToolResult(callId: call.id, name: call.name, content: outcome.text, isError: outcome.isError))
            }
            if builder.finished {
                stats.stopReason = "finish"
                break
            }
            if failures >= limits.maxFailuresInARow {
                stats.stopReason = "too many failed calls"
                break
            }
            if lastCall {
                stats.stopReason = "limit"
                break
            }
            messages.append(.results(results, note: response.stop == .maxTokens ? PlanText.cutOff() : ""))
        }

        stats.seconds = Date().timeIntervalSince(started)
        return ChangePlan(
            input: input, provider: provider.kind.rawValue, model: model, operations: builder.operations,
            dropped: builder.dropped, skipped: builder.skipped, summary: builder.summary, finished: builder.finished, stats: stats
        )
    }

    /// The first message and the instructions, for estimating whether a run fits a model's context.
    public func openingCharacters() async -> Int {
        let open = await world.allIssues().filter(\.isOpen)
        return PlanText.context(facts: world.facts, open: open, input: input).count
            + PlanText.system(style: style, input: input, viewer: world.facts.viewer).count
            + PlanText.tools.reduce(0) { $0 + $1.description.count + $1.parameters.jsonText.count }
    }
}
