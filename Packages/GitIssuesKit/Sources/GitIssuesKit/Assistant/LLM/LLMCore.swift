import Foundation

// One way to talk to every language model the assistant can use. The rest of the app knows only these types; each
// provider translates them to its own API, and keeps its own form of an answer so it can be sent back unchanged.

/// The services that can run the assistant.
public enum LLMProviderKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case anthropic
    case openAI
    case google
    case ollama

    public var id: String { rawValue }
    public var needsKey: Bool { self != .ollama }
}

/// A model a provider offers.
public struct LLMModel: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// How many tokens of context it can take, where the provider says.
    public var contextTokens: Int?

    public init(id: String, name: String, contextTokens: Int? = nil) {
        self.id = id
        self.name = name
        self.contextTokens = contextTokens
    }
}

/// A tool the model may call: a name, what it does, and a JSON Schema for its arguments. Schemas list every property
/// as required and allow no others, so every provider can enforce them strictly.
public struct LLMToolSpec: Sendable {
    public var name: String
    public var description: String
    public var parameters: JSONValue

    public init(name: String, description: String, parameters: JSONValue) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

public enum LLMToolChoice: Sendable, Equatable {
    case auto
    /// Some tool must be called. Providers or models that can't force one fall back to `auto`.
    case required
    /// This tool must be called, where the model allows forcing one.
    case named(String)
    case none
}

public struct LLMToolCall: Codable, Sendable, Hashable {
    public var id: String
    public var name: String
    /// The arguments as an object. Empty when they couldn't be read; `unreadable` then says why.
    public var arguments: JSONValue
    public var unreadable: String?

    public init(id: String, name: String, arguments: JSONValue, unreadable: String? = nil) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.unreadable = unreadable
    }

    /// Arguments that arrive as a JSON string (OpenAI, some Ollama models).
    static func parsing(id: String, name: String, text: String) -> LLMToolCall {
        if let data = text.data(using: .utf8), let value = try? JSONDecoder().decode(JSONValue.self, from: data), case .object = value {
            return LLMToolCall(id: id, name: name, arguments: value)
        }
        return LLMToolCall(id: id, name: name, arguments: .object([:]), unreadable: String(text.prefix(300)))
    }
}

public struct LLMToolResult: Codable, Sendable {
    public var callId: String
    public var name: String
    public var content: String
    public var isError: Bool

    public init(callId: String, name: String, content: String, isError: Bool = false) {
        self.callId = callId
        self.name = name
        self.content = content
        self.isError = isError
    }
}

/// One turn of the conversation.
public struct LLMMessage: Codable, Sendable {
    public enum Role: String, Codable, Sendable {
        case user
        case assistant
        /// The results of the tool calls of the assistant turn before, with an optional note from the app.
        case tool
    }

    public var role: Role
    public var text: String
    public var toolCalls: [LLMToolCall] = []
    public var toolResults: [LLMToolResult] = []
    /// The provider's own form of an assistant turn (thinking, signatures, reasoning items), sent back as it came.
    public var native: JSONValue?
    public var nativeProvider: LLMProviderKind?
    /// Ends a stable beginning of the conversation that providers with explicit caching should cache.
    public var cacheBreakpoint = false

    public static func user(_ text: String, cache: Bool = false) -> LLMMessage {
        LLMMessage(role: .user, text: text, cacheBreakpoint: cache)
    }

    public static func results(_ results: [LLMToolResult], note: String = "") -> LLMMessage {
        LLMMessage(role: .tool, text: note, toolResults: results)
    }
}

public struct LLMUsage: Codable, Sendable, Equatable {
    /// Input tokens read without a cache.
    public var input = 0
    public var output = 0
    /// Input tokens read from the provider's cache.
    public var cacheRead = 0
    /// Input tokens written to the cache (Anthropic bills these a little higher).
    public var cacheWrite = 0

    public init(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
    }

    /// Everything the model read in this request.
    public var totalInput: Int { input + cacheRead + cacheWrite }

    public static func + (lhs: LLMUsage, rhs: LLMUsage) -> LLMUsage {
        LLMUsage(
            input: lhs.input + rhs.input, output: lhs.output + rhs.output,
            cacheRead: lhs.cacheRead + rhs.cacheRead, cacheWrite: lhs.cacheWrite + rhs.cacheWrite
        )
    }
}

public enum LLMStopReason: String, Codable, Sendable {
    case toolUse
    case end
    case maxTokens
    case refusal
}

public struct LLMResponse: Sendable {
    public var message: LLMMessage
    public var usage: LLMUsage
    public var stop: LLMStopReason
    /// The model that answered, which can differ from the one asked (fallbacks).
    public var model: String?
}

public struct LLMChatRequest: Sendable {
    public var model: String
    public var system: String
    public var messages: [LLMMessage]
    public var tools: [LLMToolSpec]
    public var toolChoice: LLMToolChoice
    public var maxOutputTokens: Int
    /// How hard the model should think: "low", "medium", "high" … Providers without such a setting ignore it.
    public var effort: String?

    public init(
        model: String, system: String, messages: [LLMMessage], tools: [LLMToolSpec] = [], toolChoice: LLMToolChoice = .auto,
        maxOutputTokens: Int = 16_000, effort: String? = nil
    ) {
        self.model = model
        self.system = system
        self.messages = messages
        self.tools = tools
        self.toolChoice = toolChoice
        self.maxOutputTokens = maxOutputTokens
        self.effort = effort
    }
}

public protocol LLMProvider: Sendable {
    var kind: LLMProviderKind { get }
    /// Models this account can use, best guesses first.
    func models() async throws -> [LLMModel]
    /// One turn: sends the conversation and returns the model's answer.
    func respond(_ request: LLMChatRequest) async throws -> LLMResponse
    /// Whether the model can be made to call a tool. If not, the caller asks for it in words.
    func canForceToolChoice(model: String) -> Bool
}

public enum LLMError: Error, Equatable, Sendable {
    case missingKey(LLMProviderKind)
    case invalidKey(LLMProviderKind)
    case rateLimited(LLMProviderKind)
    case overloaded(LLMProviderKind)
    case refused(String)
    case truncated
    case server(LLMProviderKind, Int, String)
    case unreachable(LLMProviderKind, String)
    case badResponse(String)
    case noModels(LLMProviderKind)

    /// Worth trying again after a short wait.
    var isTransient: Bool {
        switch self {
        case .rateLimited, .overloaded, .unreachable: true
        case .server(_, let status, _): status >= 500
        default: false
        }
    }
}

// MARK: - JSON

/// A JSON value, for request bodies, schemas and tool arguments without stringly typed dictionaries.
public enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value):
            if value == value.rounded(), abs(value) < 1e15 { try container.encode(Int(value)) } else { try container.encode(value) }
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let object) = self { return object[key] }
        return nil
    }

    public var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var array: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var object: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    public var number: Double? {
        if case .number(let value) = self { return value }
        if case .string(let value) = self { return Double(value) }
        return nil
    }

    public var int: Int? { number.map { Int($0) } }

    public var bool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    /// Compact JSON text.
    public var jsonText: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? "null"
    }

    /// The same value without the given keys anywhere in it, for providers that reject parts of a schema.
    func removingKeys(_ keys: Set<String>) -> JSONValue {
        switch self {
        case .object(let object):
            var result: [String: JSONValue] = [:]
            for (key, value) in object where !keys.contains(key) { result[key] = value.removingKeys(keys) }
            return .object(result)
        case .array(let array):
            return .array(array.map { $0.removingKeys(keys) })
        default:
            return self
        }
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral, ExpressibleByIntegerLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) { self = .object(Dictionary(uniqueKeysWithValues: elements)) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
}

// MARK: - HTTP

/// Plumbing the providers share: JSON in, JSON out, typed errors, a few retries.
struct LLMHTTP: Sendable {
    let session: URLSession
    let provider: LLMProviderKind

    init(provider: LLMProviderKind, session: URLSession? = nil) {
        self.provider = provider
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            // A thinking model can take minutes for one turn; a local one longer.
            config.timeoutIntervalForRequest = 900
            config.timeoutIntervalForResource = 1800
            self.session = URLSession(configuration: config)
        }
    }

    func send(_ request: URLRequest, retries: Int = 3) async throws -> JSONValue {
        var attempt = 0
        while true {
            do {
                return try await sendOnce(request)
            } catch let error as LLMError where error.isTransient && attempt < retries {
                attempt += 1
                try await Task.sleep(for: .seconds(Double(attempt * attempt) * 3))
            }
        }
    }

    private func sendOnce(_ request: URLRequest) async throws -> JSONValue {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw LLMError.unreachable(provider, error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw LLMError.badResponse("no HTTP response") }
        let json = try? JSONDecoder().decode(JSONValue.self, from: data)
        guard (200..<300).contains(http.statusCode) else {
            let message = json.map(Self.errorMessage) ?? String(decoding: data.prefix(400), as: UTF8.self)
            switch http.statusCode {
            case 401, 403: throw LLMError.invalidKey(provider)
            case 429: throw LLMError.rateLimited(provider)
            case 529, 503: throw LLMError.overloaded(provider)
            default: throw LLMError.server(provider, http.statusCode, message)
            }
        }
        guard let json else { throw LLMError.badResponse(String(decoding: data.prefix(300), as: UTF8.self)) }
        return json
    }

    /// The readable part of the error bodies the providers send.
    static func errorMessage(_ json: JSONValue) -> String {
        if let message = json["error"]?["message"]?.string { return message }
        if let message = json["error"]?.string { return message }
        if let message = json["message"]?.string { return message }
        return json.jsonText
    }

    static func request(_ url: URL, method: String = "POST", headers: [String: String] = [:], body: JSONValue? = nil, timeout: TimeInterval = 900) throws -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        return request
    }
}
