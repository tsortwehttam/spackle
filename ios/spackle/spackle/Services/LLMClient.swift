import Foundation

enum LLMClientError: LocalizedError {
    case invalidConfig
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidConfig:
            return "Invalid provider configuration"
        case .invalidResponse:
            return "Provider returned an unexpected response"
        }
    }
}

private struct OpenAIResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            var content: String
        }
        var message: Message
    }
    var choices: [Choice]
}

private struct AnthropicResponse: Decodable {
    struct ContentPart: Decodable {
        var type: String
        var text: String
    }
    var content: [ContentPart]
}

final class LLMClient {
    private let userInstruction = "Return only the final replacement text."

    func cancel() {}

    func calcCompletion(settings: AppSettings, apiKey: String, systemPrompt: String) async throws -> String {
        let req = try calcRequest(settings: settings, apiKey: apiKey, systemPrompt: systemPrompt)
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 20
        let session = URLSession(configuration: cfg)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw LLMClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw LLMClientError.invalidResponse
        }

        switch settings.provider {
        case .anthropic:
            let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
            return decoded.content.first(where: { $0.type == "text" })?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        case .openAI, .openRouter, .custom:
            let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
            return decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
    }

    private func calcRequest(settings: AppSettings, apiKey: String, systemPrompt: String) throws -> URLRequest {
        if apiKey.isEmpty {
            throw LLMClientError.invalidConfig
        }
        let model = calcModel(settings)
        if model.isEmpty {
            throw LLMClientError.invalidConfig
        }

        let endpoint: String
        switch settings.provider {
        case .openAI:
            endpoint = "https://api.openai.com/v1/chat/completions"
        case .anthropic:
            endpoint = "https://api.anthropic.com/v1/messages"
        case .openRouter:
            endpoint = "https://openrouter.ai/api/v1/chat/completions"
        case .custom:
            let raw = settings.customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if raw.isEmpty {
                throw LLMClientError.invalidConfig
            }
            endpoint = raw
        }

        guard let url = URL(string: endpoint) else {
            throw LLMClientError.invalidConfig
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        switch settings.provider {
        case .anthropic:
            req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            let body: [String: Any] = [
                "model": model,
                "max_tokens": 512,
                "system": systemPrompt,
                "messages": [["role": "user", "content": userInstruction]]
            ]
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        case .openAI, .openRouter, .custom:
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            let body: [String: Any] = [
                "model": model,
                "messages": [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": userInstruction]
                ],
                "temperature": 0.7
            ]
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        return req
    }

    private func calcModel(_ settings: AppSettings) -> String {
        let value = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty == false {
            return value
        }
        return ModelCatalog.calcOptions(provider: settings.provider).first ?? ""
    }
}
