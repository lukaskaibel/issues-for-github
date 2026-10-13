import Foundation

/// Gemini through the Generative Language API. A model turn comes back with thought signatures on its parts; they
/// have to go back unchanged, so the turn is kept in Gemini's own form.
public struct GeminiProvider: LLMProvider {
    public let kind = LLMProviderKind.google
    let apiKey: String
    let http: LLMHTTP
    let baseURL: URL

    public init(apiKey: String, session: URLSession? = nil, baseURL: URL = URL(string: "https://generativelanguage.googleapis.com/v1beta/")!) {
        self.apiKey = apiKey
        self.http = LLMHTTP(provider: .google, session: session)
        self.baseURL = baseURL
    }

    private var headers: [String: String] { ["x-goog-api-key": apiKey] }

    public func models() async throws -> [LLMModel] {
        let url = baseURL.appendingPathComponent("models").appending(queryItems: [URLQueryItem(name: "pageSize", value: "200")])
        let json = try await http.send(try LLMHTTP.request(url, method: "GET", headers: headers, timeout: 30))
        let models = (json["models"]?.array ?? []).compactMap { item -> LLMModel? in
            guard let name = item["name"]?.string, name.contains("gemini"),
                  (item["supportedGenerationMethods"]?.array ?? []).contains(.string("generateContent")) else { return nil }
            let id = name.replacingOccurrences(of: "models/", with: "")
            if ["embedding", "image", "tts", "audio", "live"].contains(where: { id.contains($0) }) { return nil }
            return LLMModel(id: id, name: item["displayName"]?.string ?? id, contextTokens: item["inputTokenLimit"]?.int)
        }
        guard !models.isEmpty else { throw LLMError.noModels(.google) }
        return models
    }

    public func canForceToolChoice(model: String) -> Bool { true }

    public func respond(_ request: LLMChatRequest) async throws -> LLMResponse {
        do {
            return try await send(request, jsonSchema: true)
        } catch LLMError.server(_, 400, let message) where message.contains("parametersJsonSchema") || message.contains("additionalProperties") {
            // Older models know only the OpenAPI subset of schemas.
            return try await send(request, jsonSchema: false)
        }
    }

    private func send(_ request: LLMChatRequest, jsonSchema: Bool) async throws -> LLMResponse {
        var body: [String: JSONValue] = [
            "systemInstruction": ["parts": [["text": .string(request.system)]]],
            "contents": .array(encode(request.messages)),
            "generationConfig": ["maxOutputTokens": .number(Double(request.maxOutputTokens))],
        ]
        if !request.tools.isEmpty {
            body["tools"] = [["functionDeclarations": .array(request.tools.map { tool in
                jsonSchema
                    ? ["name": .string(tool.name), "description": .string(tool.description), "parametersJsonSchema": tool.parameters]
                    : ["name": .string(tool.name), "description": .string(tool.description), "parameters": tool.parameters.removingKeys(["additionalProperties"])]
            })]]
            let config: JSONValue = switch request.toolChoice {
            case .auto: ["mode": "AUTO"]
            case .none: ["mode": "NONE"]
            case .required: ["mode": "ANY"]
            case .named(let name): ["mode": "ANY", "allowedFunctionNames": [.string(name)]]
            }
            body["toolConfig"] = ["functionCallingConfig": config]
        }
        let url = baseURL.appendingPathComponent("models/\(request.model):generateContent")
        let json = try await http.send(try LLMHTTP.request(url, headers: headers, body: .object(body)))
        return try parse(json)
    }

    private func encode(_ messages: [LLMMessage]) -> [JSONValue] {
        var contents: [JSONValue] = []
        for message in messages {
            switch message.role {
            case .user:
                contents.append(["role": "user", "parts": [["text": .string(message.text)]]])
            case .assistant:
                if message.nativeProvider == .google, let native = message.native {
                    contents.append(native)
                } else {
                    var parts: [JSONValue] = message.text.isEmpty ? [] : [["text": .string(message.text)]]
                    for call in message.toolCalls { parts.append(["functionCall": ["name": .string(call.name), "args": call.arguments]]) }
                    contents.append(["role": "model", "parts": .array(parts)])
                }
            case .tool:
                var parts: [JSONValue] = message.toolResults.map { result in
                    var response: [String: JSONValue] = ["name": .string(result.name), "response": [result.isError ? "error" : "result": .string(result.content)]]
                    if !result.callId.hasPrefix("local-") { response["id"] = .string(result.callId) }
                    return ["functionResponse": .object(response)]
                }
                if !message.text.isEmpty { parts.append(["text": .string(message.text)]) }
                contents.append(["role": "user", "parts": .array(parts)])
            }
        }
        return contents
    }

    private func parse(_ json: JSONValue) throws -> LLMResponse {
        if let blocked = json["promptFeedback"]?["blockReason"]?.string { throw LLMError.refused(blocked) }
        guard let candidate = json["candidates"]?.array?.first else { throw LLMError.badResponse("no candidate") }
        let finish = candidate["finishReason"]?.string
        if ["SAFETY", "RECITATION", "PROHIBITED_CONTENT", "BLOCKLIST"].contains(finish ?? "") { throw LLMError.refused(finish ?? "") }
        let content = candidate["content"] ?? ["role": "model", "parts": []]
        var text = ""
        var calls: [LLMToolCall] = []
        for part in content["parts"]?.array ?? [] {
            if part["thought"]?.bool == true { continue }
            if let value = part["text"]?.string { text += value }
            if let call = part["functionCall"] {
                let id = call["id"]?.string ?? "local-\(UUID().uuidString)"
                calls.append(LLMToolCall(id: id, name: call["name"]?.string ?? "", arguments: call["args"] ?? .object([:])))
            }
        }
        let usage = json["usageMetadata"]
        let cached = usage?["cachedContentTokenCount"]?.int ?? 0
        return LLMResponse(
            message: LLMMessage(role: .assistant, text: text, toolCalls: calls, native: content, nativeProvider: .google),
            usage: LLMUsage(
                input: (usage?["promptTokenCount"]?.int ?? 0) - cached,
                output: (usage?["candidatesTokenCount"]?.int ?? 0) + (usage?["thoughtsTokenCount"]?.int ?? 0),
                cacheRead: cached
            ),
            stop: finish == "MAX_TOKENS" ? .maxTokens : (calls.isEmpty ? .end : .toolUse),
            model: json["modelVersion"]?.string
        )
    }
}
