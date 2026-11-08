import Foundation

// MARK: - Errors

enum ClaudeError: LocalizedError {
    case noAPIKey(String)
    case consentRequired(String)
    case imagesNotSupported(String)
    case imageConversionFailed
    case parseError
    case networkError
    case apiError(Int, String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey(let name):
            return "No API key for \(name). Add one in Settings."
        case .consentRequired(let company):
            return "Turn on data sharing for \(company) in Settings first. Your health summary and meal photos are sent to \(company) when you use AI features."
        case .imagesNotSupported(let name):
            return "\(name) can't read photos here. Choose Gemini, OpenAI or Claude in Settings, or use Type it out."
        case .imageConversionFailed:
            return "Failed to process image."
        case .parseError:
            return "Could not parse the response."
        case .networkError:
            return "No connection to the AI service. Check your internet and try again."
        case .apiError(429, _):
            return "AI quota reached. Wait a bit and try again."
        case .apiError(let code, let body):
            var text = "API error \(code)"
            if let detail = AIProvider.errorDetail(fromBody: body) { text += ": \(detail)" }
            if code == 404 {
                text += " The model may have been retired. In Settings, tap Find available models."
            } else {
                text += " Check your key and model in Settings."
            }
            return text
        }
    }
}

// MARK: - Request model

struct AIMessage {
    enum Role: String { case user, assistant }
    let role: Role
    let text: String
}

struct AIRequestSpec {
    var system: String
    var messages: [AIMessage]
    var maxTokens: Int
    var wantsJSON = false
    /// A JPEG attached to the last user message.
    var imageJPEG: Data?
}

// MARK: - Providers

enum AIProvider: String, CaseIterable, Identifiable {
    case gemini, openai, anthropic, local

    var id: String { rawValue }

    /// Reasoning models spend tokens thinking before the visible reply; without headroom the reply can come back empty.
    static let reasoningHeadroom = 1200

    var displayName: String {
        switch self {
        case .gemini:    return "Google Gemini"
        case .openai:    return "OpenAI"
        case .anthropic: return "Anthropic Claude"
        case .local:     return "Local (Ollama)"
        }
    }

    /// Who receives your data when this provider is selected.
    var company: String {
        switch self {
        case .gemini:    return "Google"
        case .openai:    return "OpenAI"
        case .anthropic: return "Anthropic"
        case .local:     return "your own server"
        }
    }

    var isCloud: Bool { self != .local }
    var supportsImages: Bool { self != .local }

    var defaultModel: String {
        switch self {
        case .gemini:    return "gemini-2.5-flash"
        case .openai:    return "gpt-4o-mini"
        case .anthropic: return "claude-haiku-5-5"
        case .local:     return "llama3.2"
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .gemini:    return "AIza..."
        case .openai:    return "sk-..."
        case .anthropic: return "sk-ant-..."
        case .local:     return ""
        }
    }

    var keyURL: URL? {
        switch self {
        case .gemini:    return URL(string: "https://aistudio.google.com/apikey")
        case .openai:    return URL(string: "https://platform.openai.com/api-keys")
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")
        case .local:     return nil
        }
    }

    /// Keychain account. Gemini keeps the original name so keys saved by earlier builds still work.
    var keychainAccount: String {
        self == .gemini ? "apex_claude_api_key" : "apex_key_\(rawValue)"
    }

    /// UserDefaults key. Gemini keeps the original name so earlier consent still counts.
    var consentDefaultsKey: String {
        self == .gemini ? "apex_ai_consent" : "apex_ai_consent_\(rawValue)"
    }

    /// Local keeps its original key so a model name saved by earlier builds still counts.
    var modelDefaultsKey: String { self == .local ? "apex_local_ai_model" : "apex_ai_model_\(rawValue)" }

    // MARK: Build the request

    func urlRequest(_ spec: AIRequestSpec, apiKey: String, model: String, localBaseURL: String = "") throws -> URLRequest {
        if spec.imageJPEG != nil && !supportsImages { throw ClaudeError.imagesNotSupported(displayName) }

        var request: URLRequest
        let body: [String: Any]

        switch self {
        case .gemini:
            guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
                throw ClaudeError.networkError
            }
            request = URLRequest(url: url)
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            body = [
                "contents": geminiContents(spec),
                "systemInstruction": ["parts": [["text": spec.system]]],
                "generationConfig": ["maxOutputTokens": spec.maxTokens + Self.reasoningHeadroom],
            ]

        case .openai:
            guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else { throw ClaudeError.networkError }
            request = URLRequest(url: url)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            var b: [String: Any] = [
                "model": model,
                "messages": [["role": "system", "content": spec.system]] + openAIMessages(spec),
                "max_completion_tokens": spec.maxTokens + Self.reasoningHeadroom,
            ]
            if spec.wantsJSON { b["response_format"] = ["type": "json_object"] }
            body = b

        case .anthropic:
            guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { throw ClaudeError.networkError }
            request = URLRequest(url: url)
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = [
                "model": model,
                "max_tokens": spec.maxTokens,
                "system": spec.system,
                "messages": anthropicMessages(spec),
            ]

        case .local:
            guard let url = URL(string: "\(localBaseURL)/api/chat") else { throw ClaudeError.networkError }
            request = URLRequest(url: url, timeoutInterval: 90)
            var b: [String: Any] = [
                "model": model,
                "messages": [["role": "system", "content": spec.system]]
                    + spec.messages.map { ["role": $0.role.rawValue, "content": $0.text] },
                "stream": false,
                "options": ["num_predict": spec.maxTokens + Self.reasoningHeadroom],
            ]
            if spec.wantsJSON { b["format"] = "json" }
            body = b
        }

        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: Parse the reply

    func parseReply(_ data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ClaudeError.parseError }
        let text: String?
        switch self {
        case .gemini:
            let parts = ((json["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]
            text = parts?.compactMap { $0["text"] as? String }.joined()
        case .openai:
            text = (((json["choices"] as? [[String: Any]])?.first?["message"]) as? [String: Any])?["content"] as? String
        case .anthropic:
            let blocks = json["content"] as? [[String: Any]]
            text = blocks?.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
        case .local:
            text = (json["message"] as? [String: Any])?["content"] as? String
        }
        guard let reply = text, !reply.isEmpty else { throw ClaudeError.parseError }
        return reply
    }

    // MARK: Per-provider message shapes

    private func geminiContents(_ spec: AIRequestSpec) -> [[String: Any]] {
        spec.messages.enumerated().map { index, message in
            var parts: [[String: Any]] = [["text": message.text]]
            if let image = spec.imageJPEG, index == lastUserIndex(spec) {
                parts.append(["inline_data": ["mime_type": "image/jpeg", "data": image.base64EncodedString()]])
            }
            return ["role": message.role == .user ? "user" : "model", "parts": parts]
        }
    }

    private func openAIMessages(_ spec: AIRequestSpec) -> [[String: Any]] {
        spec.messages.enumerated().map { index, message in
            if let image = spec.imageJPEG, index == lastUserIndex(spec) {
                let content: [[String: Any]] = [
                    ["type": "text", "text": message.text],
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(image.base64EncodedString())"]],
                ]
                return ["role": message.role.rawValue, "content": content]
            }
            return ["role": message.role.rawValue, "content": message.text]
        }
    }

    private func anthropicMessages(_ spec: AIRequestSpec) -> [[String: Any]] {
        spec.messages.enumerated().map { index, message in
            if let image = spec.imageJPEG, index == lastUserIndex(spec) {
                let content: [[String: Any]] = [
                    ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": image.base64EncodedString()]],
                    ["type": "text", "text": message.text],
                ]
                return ["role": message.role.rawValue, "content": content]
            }
            return ["role": message.role.rawValue, "content": message.text]
        }
    }

    private func lastUserIndex(_ spec: AIRequestSpec) -> Int? {
        spec.messages.lastIndex { $0.role == .user }
    }
}

// MARK: - Errors and model lists from the provider

extension AIProvider {
    /// The human message inside a provider's JSON error body, if there is one.
    static func errorDetail(fromBody body: String) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any] else { return nil }
        let message = (json["error"] as? [String: Any])?["message"] as? String ?? json["message"] as? String
        guard let text = message?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text.count > 220 ? String(text.prefix(220)) + "..." : text
    }

    func modelsRequest(apiKey: String) -> URLRequest? {
        let urlString: String
        switch self {
        case .gemini:    urlString = "https://generativelanguage.googleapis.com/v1beta/models?pageSize=200"
        case .openai:    urlString = "https://api.openai.com/v1/models"
        case .anthropic: urlString = "https://api.anthropic.com/v1/models?limit=100"
        case .local:     return nil
        }
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        switch self {
        case .gemini:
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        case .openai:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .anthropic:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .local:
            break
        }
        return request
    }

    /// Model ids this provider says it can chat with, sorted.
    func parseModels(_ data: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let ids: [String]
        switch self {
        case .gemini:
            let models = json["models"] as? [[String: Any]] ?? []
            ids = models
                .filter { ($0["supportedGenerationMethods"] as? [String])?.contains("generateContent") == true }
                .compactMap { ($0["name"] as? String)?.replacingOccurrences(of: "models/", with: "") }
        case .openai:
            let all = (json["data"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
            ids = all.filter { $0.hasPrefix("gpt") || $0.hasPrefix("chatgpt") || $0.range(of: "^o[0-9]", options: .regularExpression) != nil }
        case .anthropic:
            ids = (json["data"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }.filter { $0.hasPrefix("claude") }
        case .local:
            ids = []
        }
        return Array(Set(ids)).sorted()
    }
}
