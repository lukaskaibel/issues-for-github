import Foundation

/// OpenAI through the Responses API. Unlike Chat Completions it lets a reasoning model keep its reasoning between
/// tool calls: the reasoning items come back encrypted and are sent along with the next turn.
public struct OpenAIProvider: LLMProvider {
    public let kind = LLMProviderKind.openAI
    let apiKey: String
    let http: LLMHTTP
    let baseURL: URL

    public init(apiKey: String, session: URLSession? = nil, baseURL: URL = URL(string: "https://api.openai.com/v1/")!) {
        self.apiKey = apiKey
        self.http = LLMHTTP(provider: .openAI, session: session)
        self.baseURL = baseURL
    }

    private var headers: [String: String] { ["Authorization": ["Bearer", apiKey].joined(separator: " ")] }

    public func models() async throws -> [LLMModel] {
        let json = try await http.send(try LLMHTTP.request(baseURL.appendingPathComponent("models"), method: "GET", headers: headers, timeout: 30))
        let excluded = ["audio", "realtime", "tts", "transcribe", "search", "image", "embedding", "instruct", "moderation", "whisper", "dall-e", "davinci", "babbage", "codex", "computer"]
        let ids = (json["data"]?.array ?? []).compactMap { $0["id"]?.string }.filter { id in
            (id.hasPrefix("gpt-") || id.hasPrefix("o3") || id.hasPrefix("o4")) && !excluded.contains { id.contains($0) }
        }
        guard !ids.isEmpty else { throw LLMError.noModels(.openAI) }
        return ids.sorted().reversed().map { LLMModel(id: $0, name: $0) }
    }

    public func canForceToolChoice(model: String) -> Bool { true }

    static func isReasoningModel(_ model: String) -> Bool {
        model.hasPrefix("gpt-5") || model.hasPrefix("o3") || model.hasPrefix("o4") || model.hasPrefix("gpt-6")
    }

    public func respond(_ request: LLMChatRequest) async throws -> LLMResponse {
        var body: [String: JSONValue] = [
            "model": .string(request.model),
            "instructions": .string(request.system),
            "input": .array(encode(request.messages)),
            "max_output_tokens": .number(Double(request.maxOutputTokens)),
            "store": false,
        ]
        if !request.tools.isEmpty {
            body["tools"] = .array(request.tools.map { tool in
                ["type": "function", "name": .string(tool.name), "description": .string(tool.description), "parameters": tool.parameters, "strict": true]
            })
            body["tool_choice"] = switch request.toolChoice {
            case .auto: "auto"
            case .none: "none"
            case .required: "required"
            case .named(let name): ["type": "function", "name": .string(name)]
            }
        }
        if Self.isReasoningModel(request.model) {
            body["reasoning"] = ["effort": .string(request.effort ?? "medium")]
            body["include"] = ["reasoning.encrypted_content"]
        }
        let json = try await http.send(try LLMHTTP.request(baseURL.appendingPathComponent("responses"), headers: headers, body: .object(body)))
        return try parse(json)
    }

    private func encode(_ messages: [LLMMessage]) -> [JSONValue] {
        var items: [JSONValue] = []
        for message in messages {
            switch message.role {
            case .user:
                items.append(["role": "user", "content": .string(message.text)])
            case .assistant:
                if message.nativeProvider == .openAI, let native = message.native?.array {
                    items += native
                } else {
                    if !message.text.isEmpty { items.append(["role": "assistant", "content": .string(message.text)]) }
                    for call in message.toolCalls {
                        items.append(["type": "function_call", "call_id": .string(call.id), "name": .string(call.name), "arguments": .string(call.arguments.jsonText)])
                    }
                }
            case .tool:
                for result in message.toolResults {
                    let output = result.isError ? "ERROR: \(result.content)" : result.content
                    items.append(["type": "function_call_output", "call_id": .string(result.callId), "output": .string(output)])
                }
                if !message.text.isEmpty { items.append(["role": "user", "content": .string(message.text)]) }
            }
        }
        return items
    }

    private func parse(_ json: JSONValue) throws -> LLMResponse {
        if let error = json["error"], error != .null { throw LLMError.badResponse(LLMHTTP.errorMessage(json)) }
        let output = json["output"]?.array ?? []
        var text = ""
        var calls: [LLMToolCall] = []
        var refusal: String?
        for item in output {
            switch item["type"]?.string {
            case "message":
                for part in item["content"]?.array ?? [] {
                    if part["type"]?.string == "output_text" { text += part["text"]?.string ?? "" }
                    if part["type"]?.string == "refusal" { refusal = part["refusal"]?.string }
                }
            case "function_call":
                let id = item["call_id"]?.string ?? UUID().uuidString
                calls.append(LLMToolCall.parsing(id: id, name: item["name"]?.string ?? "", text: item["arguments"]?.string ?? "{}"))
            default:
                break
            }
        }
        if let refusal, calls.isEmpty { throw LLMError.refused(refusal) }
        var stop: LLMStopReason = calls.isEmpty ? .end : .toolUse
        if json["status"]?.string == "incomplete", json["incomplete_details"]?["reason"]?.string == "max_output_tokens" { stop = .maxTokens }
        let usage = json["usage"]
        let cached = usage?["input_tokens_details"]?["cached_tokens"]?.int ?? 0
        return LLMResponse(
            message: LLMMessage(role: .assistant, text: text, toolCalls: calls, native: .array(output), nativeProvider: .openAI),
            usage: LLMUsage(input: (usage?["input_tokens"]?.int ?? 0) - cached, output: usage?["output_tokens"]?.int ?? 0, cacheRead: cached),
            stop: stop,
            model: json["model"]?.string
        )
    }
}
