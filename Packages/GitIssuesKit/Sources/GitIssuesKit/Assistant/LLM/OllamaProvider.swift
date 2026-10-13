import Foundation

/// A model running in Ollama on this Mac. Nothing leaves it.
public struct OllamaProvider: LLMProvider {
    public let kind = LLMProviderKind.ollama
    let baseURL: URL
    let http: LLMHTTP
    /// The context window asked of Ollama, in tokens. Changing it makes Ollama load the model again, so it stays
    /// the same for a model rather than following each request.
    public let contextTokens: Int
    /// Whether thinking models think before answering. Slower, but better at choosing tools.
    public let think: Bool?

    public static let defaultURL = URL(string: "http://localhost:11434")!

    public init(baseURL: URL = OllamaProvider.defaultURL, contextTokens: Int = 65_536, think: Bool? = true, session: URLSession? = nil) {
        self.baseURL = baseURL
        self.http = LLMHTTP(provider: .ollama, session: session)
        self.contextTokens = contextTokens
        self.think = think
    }

    public func canForceToolChoice(model: String) -> Bool { false }

    public func version() async throws -> String {
        let request = try LLMHTTP.request(baseURL.appendingPathComponent("api/version"), method: "GET", timeout: 5)
        return try await http.send(request, retries: 0)["version"]?.string ?? ""
    }

    /// Installed models that can call tools.
    public func models() async throws -> [LLMModel] {
        let request = try LLMHTTP.request(baseURL.appendingPathComponent("api/tags"), method: "GET", timeout: 10)
        let names = (try await http.send(request, retries: 0)["models"]?.array ?? []).compactMap { $0["name"]?.string }
        var models: [LLMModel] = []
        for name in names {
            let info = try await modelInfo(name)
            if info.capabilities.contains("tools") { models.append(LLMModel(id: name, name: name, contextTokens: info.contextTokens)) }
        }
        guard !models.isEmpty else { throw LLMError.noModels(.ollama) }
        return models
    }

    public struct ModelInfo: Sendable {
        public var capabilities: [String]
        public var contextTokens: Int?
        public var parameterSize: String?
    }

    /// What Ollama says about an installed model, without loading it.
    public func modelInfo(_ name: String) async throws -> ModelInfo {
        let request = try LLMHTTP.request(baseURL.appendingPathComponent("api/show"), body: ["model": .string(name)], timeout: 10)
        let json = try await http.send(request, retries: 0)
        let context = json["model_info"]?.object?.first { $0.key.hasSuffix(".context_length") }?.value.int
        return ModelInfo(
            capabilities: (json["capabilities"]?.array ?? []).compactMap(\.string),
            contextTokens: context,
            parameterSize: json["details"]?["parameter_size"]?.string
        )
    }

    public func respond(_ request: LLMChatRequest) async throws -> LLMResponse {
        var messages: [JSONValue] = [["role": "system", "content": .string(request.system)]]
        for message in request.messages {
            switch message.role {
            case .user:
                messages.append(["role": "user", "content": .string(message.text)])
            case .assistant:
                if message.nativeProvider == .ollama, let native = message.native {
                    messages.append(native)
                } else {
                    let calls: [JSONValue] = message.toolCalls.map { ["function": ["name": .string($0.name), "arguments": $0.arguments]] }
                    messages.append(["role": "assistant", "content": .string(message.text), "tool_calls": .array(calls)])
                }
            case .tool:
                for result in message.toolResults {
                    let content = result.isError ? "ERROR: \(result.content)" : result.content
                    messages.append(["role": "tool", "content": .string(content), "tool_name": .string(result.name)])
                }
                if !message.text.isEmpty { messages.append(["role": "user", "content": .string(message.text)]) }
            }
        }
        var body: [String: JSONValue] = [
            "model": .string(request.model),
            "messages": .array(messages),
            "stream": false,
            "options": ["num_ctx": .number(Double(contextTokens)), "num_predict": .number(Double(request.maxOutputTokens))],
        ]
        if !request.tools.isEmpty, request.toolChoice != .none {
            body["tools"] = .array(request.tools.map { tool in
                ["type": "function", "function": ["name": .string(tool.name), "description": .string(tool.description), "parameters": tool.parameters]]
            })
        }
        if let think { body["think"] = .bool(think) }
        let json = try await http.send(try LLMHTTP.request(baseURL.appendingPathComponent("api/chat"), body: .object(body), timeout: 1800), retries: 0)
        if let error = json["error"]?.string { throw LLMError.server(.ollama, 500, error) }
        guard let message = json["message"] else { throw LLMError.badResponse("no message") }
        var calls: [LLMToolCall] = []
        for (index, call) in (message["tool_calls"]?.array ?? []).enumerated() {
            let name = call["function"]?["name"]?.string ?? ""
            let id = call["id"]?.string ?? "call-\(index)-\(UUID().uuidString.prefix(8))"
            switch call["function"]?["arguments"] {
            case .string(let text): calls.append(LLMToolCall.parsing(id: id, name: name, text: text))
            case let value?: calls.append(LLMToolCall(id: id, name: name, arguments: value))
            case nil: calls.append(LLMToolCall(id: id, name: name, arguments: .object([:])))
            }
        }
        let text = Self.strippingThinking(message["content"]?.string ?? "")
        return LLMResponse(
            message: LLMMessage(role: .assistant, text: text, toolCalls: calls, native: message, nativeProvider: .ollama),
            usage: LLMUsage(input: json["prompt_eval_count"]?.int ?? 0, output: json["eval_count"]?.int ?? 0),
            stop: json["done_reason"]?.string == "length" ? .maxTokens : (calls.isEmpty ? .end : .toolUse),
            model: json["model"]?.string
        )
    }

    static func strippingThinking(_ text: String) -> String {
        var result = text
        while let start = result.range(of: "<think>"), let end = result.range(of: "</think>", range: start.upperBound..<result.endIndex) {
            result.removeSubrange(start.lowerBound..<end.upperBound)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
