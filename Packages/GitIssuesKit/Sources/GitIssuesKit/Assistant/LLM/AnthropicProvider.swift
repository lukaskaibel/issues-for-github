import Foundation

/// Claude through the Messages API.
public struct AnthropicProvider: LLMProvider {
    public let kind = LLMProviderKind.anthropic
    let apiKey: String
    let http: LLMHTTP
    let baseURL: URL

    public static let defaultModel = "claude-opus-5-5"

    public init(apiKey: String, session: URLSession? = nil, baseURL: URL = URL(string: "https://api.anthropic.com/v1/")!) {
        self.apiKey = apiKey
        self.http = LLMHTTP(provider: .anthropic, session: session)
        self.baseURL = baseURL
    }

    private var headers: [String: String] {
        ["x-api-key": apiKey, "anthropic-version": "2023-06-01"]
    }

    public func models() async throws -> [LLMModel] {
        let url = baseURL.appendingPathComponent("models").appending(queryItems: [URLQueryItem(name: "limit", value: "100")])
        let json = try await http.send(try LLMHTTP.request(url, method: "GET", headers: headers, timeout: 30))
        let models = (json["data"]?.array ?? []).compactMap { item -> LLMModel? in
            guard let id = item["id"]?.string else { return nil }
            return LLMModel(id: id, name: item["display_name"]?.string ?? id, contextTokens: item["max_input_tokens"]?.int)
        }
        guard !models.isEmpty else { throw LLMError.noModels(.anthropic) }
        return models.sorted { lhs, _ in lhs.id == Self.defaultModel }
    }

    /// Never: the current models refuse forced tool use, and on the others a changed tool choice throws away the cached
    /// conversation, which costs more than asking in words.
    public func canForceToolChoice(model: String) -> Bool { false }

    public func respond(_ request: LLMChatRequest) async throws -> LLMResponse {
        var body: [String: JSONValue] = [
            "model": .string(request.model),
            "max_tokens": .number(Double(request.maxOutputTokens)),
            // The rules and the tools before them stay the same for the whole run: cached once.
            "system": [["type": "text", "text": .string(request.system), "cache_control": ["type": "ephemeral"]]],
            "messages": .array(encode(request.messages)),
        ]
        if !request.tools.isEmpty {
            // Not strict: ten strict tools make a grammar too large for the API. The app checks every call itself.
            body["tools"] = .array(request.tools.map { tool in
                ["name": .string(tool.name), "description": .string(tool.description), "input_schema": tool.parameters]
            })
            body["tool_choice"] = toolChoice(request.toolChoice, model: request.model)
        }
        if Self.supportsAdaptiveThinking(request.model) { body["thinking"] = ["type": "adaptive"] }
        if Self.supportsEffort(request.model), let effort = request.effort { body["output_config"] = ["effort": .string(effort)] }
        var headers = headers
        if Self.supportsServerFallback(request.model) {
            // If a safety classifier declines, Anthropic runs the turn again on the model it recommends.
            headers["anthropic-beta"] = "server-side-fallback-2026-07-01"
            body["fallbacks"] = "default"
        }
        let json = try await http.send(try LLMHTTP.request(baseURL.appendingPathComponent("messages"), headers: headers, body: .object(body)))
        return try parse(json)
    }

    private func toolChoice(_ choice: LLMToolChoice, model: String) -> JSONValue {
        switch choice {
        case .auto: return ["type": "auto"]
        case .none: return ["type": "none"]
        case .required: return canForceToolChoice(model: model) ? ["type": "any"] : ["type": "auto"]
        case .named(let name): return canForceToolChoice(model: model) ? ["type": "tool", "name": .string(name)] : ["type": "auto"]
        }
    }

    private func encode(_ messages: [LLMMessage]) -> [JSONValue] {
        var result: [JSONValue] = []
        // The last turn moves the cache forward. The cache looks back only 20 blocks from a breakpoint, and a turn
        // with many tool calls has more, so the end of the turn before is marked too: that is where the last request's
        // cache ends.
        let previousEnd = messages.indices.dropLast().last { messages[$0].role != .assistant }
        for (index, message) in messages.enumerated() {
            let cache = message.cacheBreakpoint || index == messages.count - 1 || index == previousEnd
            switch message.role {
            case .user:
                result.append(["role": "user", "content": .array([text(message.text, cache: cache)])])
            case .assistant:
                if message.nativeProvider == .anthropic, let native = message.native {
                    result.append(["role": "assistant", "content": native])
                } else {
                    var blocks: [JSONValue] = message.text.isEmpty ? [] : [text(message.text, cache: false)]
                    for call in message.toolCalls {
                        blocks.append(["type": "tool_use", "id": .string(call.id), "name": .string(call.name), "input": call.arguments])
                    }
                    result.append(["role": "assistant", "content": .array(blocks)])
                }
            case .tool:
                var blocks: [JSONValue] = message.toolResults.map { result in
                    ["type": "tool_result", "tool_use_id": .string(result.callId), "content": .string(result.content), "is_error": .bool(result.isError)]
                }
                if !message.text.isEmpty { blocks.append(text(message.text, cache: false)) }
                if cache, case .object(var last) = blocks.last {
                    last["cache_control"] = ["type": "ephemeral"]
                    blocks[blocks.count - 1] = .object(last)
                }
                result.append(["role": "user", "content": .array(blocks)])
            }
        }
        return result
    }

    private func text(_ text: String, cache: Bool) -> JSONValue {
        var block: [String: JSONValue] = ["type": "text", "text": .string(text)]
        if cache { block["cache_control"] = ["type": "ephemeral"] }
        return .object(block)
    }

    private func parse(_ json: JSONValue) throws -> LLMResponse {
        let content = json["content"]?.array ?? []
        var text = ""
        var calls: [LLMToolCall] = []
        for block in content {
            switch block["type"]?.string {
            case "text": text += block["text"]?.string ?? ""
            case "tool_use":
                calls.append(LLMToolCall(id: block["id"]?.string ?? UUID().uuidString, name: block["name"]?.string ?? "", arguments: block["input"] ?? .object([:])))
            default: break
            }
        }
        let stop: LLMStopReason = switch json["stop_reason"]?.string {
        case "tool_use": .toolUse
        case "max_tokens": .maxTokens
        case "refusal": .refusal
        default: calls.isEmpty ? .end : .toolUse
        }
        if stop == .refusal, calls.isEmpty, text.isEmpty {
            throw LLMError.refused(json["stop_details"]?["category"]?.string ?? "")
        }
        let usage = json["usage"]
        return LLMResponse(
            message: LLMMessage(role: .assistant, text: text, toolCalls: calls, native: .array(content), nativeProvider: .anthropic),
            usage: LLMUsage(
                input: usage?["input_tokens"]?.int ?? 0, output: usage?["output_tokens"]?.int ?? 0,
                cacheRead: usage?["cache_read_input_tokens"]?.int ?? 0, cacheWrite: usage?["cache_creation_input_tokens"]?.int ?? 0
            ),
            stop: stop,
            model: json["model"]?.string
        )
    }

    static func supportsAdaptiveThinking(_ model: String) -> Bool {
        ["claude-fable", "claude-mythos", "claude-opus-5", "claude-sonnet-5", "claude-haiku-5", "claude-opus-4-8", "claude-opus-4-7", "claude-opus-4-6", "claude-sonnet-4-6"]
            .contains { model.hasPrefix($0) }
    }

    static func supportsEffort(_ model: String) -> Bool {
        supportsAdaptiveThinking(model) || model.hasPrefix("claude-opus-4-5")
    }

    static func supportsServerFallback(_ model: String) -> Bool {
        ["claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5"].contains(model)
    }
}
