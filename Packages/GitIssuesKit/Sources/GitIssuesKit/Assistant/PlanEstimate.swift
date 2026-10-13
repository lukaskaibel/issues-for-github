import Foundation

/// What a model costs and how it tends to behave in the assistant's loop, measured on real runs. Prices are in US
/// dollars per million tokens, as the providers list them (October 2026).
public struct ModelProfile: Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var provider: LLMProviderKind
    public var inputPrice: Double
    public var outputPrice: Double
    public var cacheReadPrice: Double
    public var cacheWritePrice: Double
    /// Some models charge more for a request above a size: Claude Haiku 5.5 five times as much above 100 000 tokens.
    public var expensiveAbove: Int?
    public var expensiveFactor: Double = 1
    /// How many characters of German text and Markdown make one token for its tokenizer.
    public var charactersPerToken: Double
    /// Turns a run takes besides working through the points (searching, reading, finishing), fewest to most.
    public var baseRounds: ClosedRange<Int>
    /// Points of the text handled per turn, most to fewest. A meeting has about one point per 7 000 characters.
    public var pointsPerRound: ClosedRange<Double>
    /// What each turn adds to the conversation: tool results, the model's answer and its thinking.
    public var growthPerRound: Int
    public var outputPerRound: Int
    /// Seconds per turn for a cloud model; for a local one, how fast it reads and writes (tokens per second).
    public var secondsPerRound: Double?
    public var readSpeed: Double?
    public var writeSpeed: Double?

    public var isFree: Bool { inputPrice == 0 && outputPrice == 0 }

    /// Fewest and most turns for a text of this length.
    public func rounds(forCharacters characters: Int) -> ClosedRange<Int> {
        let points = max(1, Double(characters) / 7_000)
        let fewest = baseRounds.lowerBound + Int((points / pointsPerRound.upperBound).rounded())
        let most = baseRounds.upperBound + Int((points / pointsPerRound.lowerBound).rounded())
        return fewest...max(fewest, most)
    }

    public static let claudeOpus = ModelProfile(
        id: "claude-opus-5-5", name: "Claude Opus 5.5", provider: .anthropic, inputPrice: 4, outputPrice: 20,
        cacheReadPrice: 0.2, cacheWritePrice: 5, charactersPerToken: 2.1, baseRounds: 3...4, pointsPerRound: 2.5...6,
        growthPerRound: 8_000, outputPerRound: 2_500, secondsPerRound: 22
    )
    public static let claudeSonnet = ModelProfile(
        id: "claude-sonnet-5-5", name: "Claude Sonnet 5.5", provider: .anthropic, inputPrice: 2, outputPrice: 10,
        cacheReadPrice: 0.2, cacheWritePrice: 2.5, charactersPerToken: 2.1, baseRounds: 3...5, pointsPerRound: 2.2...5,
        growthPerRound: 8_000, outputPerRound: 3_000, secondsPerRound: 16
    )
    public static let claudeHaiku = ModelProfile(
        id: "claude-haiku-5-5", name: "Claude Haiku 5.5", provider: .anthropic, inputPrice: 0.10, outputPrice: 0.50,
        cacheReadPrice: 0.01, cacheWritePrice: 0.125, expensiveAbove: 100_000, expensiveFactor: 5, charactersPerToken: 2.1,
        baseRounds: 3...5, pointsPerRound: 1.8...4, growthPerRound: 8_500, outputPerRound: 4_200, secondsPerRound: 19
    )
    /// A model of about 9 billion parameters in Ollama on an M4 Pro, which reads the whole conversation again every turn.
    public static func local(_ model: String) -> ModelProfile {
        ModelProfile(
            id: model, name: model, provider: .ollama, inputPrice: 0, outputPrice: 0, cacheReadPrice: 0, cacheWritePrice: 0,
            charactersPerToken: 3.5, baseRounds: 6...10, pointsPerRound: 0.8...1.5, growthPerRound: 800, outputPerRound: 550, readSpeed: 650, writeSpeed: 40
        )
    }

    public static let known: [ModelProfile] = [claudeOpus, claudeSonnet, claudeHaiku]

    public static func profile(for model: String, provider: LLMProviderKind) -> ModelProfile? {
        if provider == .ollama { return local(model) }
        return known.first { $0.id == model }
    }
}

/// A guess, before a run, at how much it will read and cost: from the fewest to the most turns such runs take.
public struct PlanEstimate: Sendable {
    public var openingTokens: Int
    public var rounds: ClosedRange<Int>
    /// Tokens read over the whole run, cached ones included.
    public var inputTokens: ClosedRange<Int>
    public var outputTokens: ClosedRange<Int>
    /// US dollars; zero for a local model.
    public var cost: ClosedRange<Double>
    public var seconds: ClosedRange<Double>
    /// The largest request, which decides the price tier of models that charge more above a size.
    public var largestPrompt: ClosedRange<Int>

    /// Instructions and tools, which are the same for every run.
    public static let fixedCharacters = 11_000

    /// - Parameters:
    ///   - inputCharacters: the text to work from.
    ///   - boardCharacters: the list of open issues as the assistant gets it (about 100 per issue).
    public static func make(inputCharacters: Int, boardCharacters: Int, profile: ModelProfile) -> PlanEstimate {
        let opening = Int(Double(fixedCharacters + boardCharacters + inputCharacters) / profile.charactersPerToken)
        let rounds = profile.rounds(forCharacters: inputCharacters)
        let low = simulate(opening: opening, rounds: rounds.lowerBound, profile: profile)
        let high = simulate(opening: opening, rounds: rounds.upperBound, profile: profile)
        return PlanEstimate(
            openingTokens: opening, rounds: rounds,
            inputTokens: low.input...high.input, outputTokens: low.output...high.output,
            cost: low.cost...high.cost, seconds: low.seconds...high.seconds, largestPrompt: low.largest...high.largest
        )
    }

    /// Each turn reads the conversation so far from the cache and writes what the last turn added; a local model
    /// reads it all again.
    static func simulate(opening: Int, rounds: Int, profile: ModelProfile) -> (input: Int, output: Int, cost: Double, seconds: Double, largest: Int) {
        var input = 0
        var cost = 0.0
        var seconds = 0.0
        var previous = 0
        for round in 0..<rounds {
            let prompt = opening + round * profile.growthPerRound
            let read = previous
            let written = prompt - previous
            var turn = Double(read) * profile.cacheReadPrice + Double(written) * profile.cacheWritePrice
                + Double(profile.outputPerRound) * profile.outputPrice
            if let limit = profile.expensiveAbove, prompt > limit { turn *= profile.expensiveFactor }
            cost += turn / 1_000_000
            if let perRound = profile.secondsPerRound {
                seconds += perRound
            } else if let reading = profile.readSpeed, let writing = profile.writeSpeed {
                seconds += Double(prompt) / reading + Double(profile.outputPerRound) / writing
            }
            input += prompt
            previous = prompt
        }
        return (input, rounds * profile.outputPerRound, cost, seconds, opening + (rounds - 1) * profile.growthPerRound)
    }
}
