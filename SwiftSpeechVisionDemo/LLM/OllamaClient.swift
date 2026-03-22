import Foundation

/// Yerel Ollama HTTP API (`http://127.0.0.1:11434` varsayılan).
enum OllamaClient {
    struct OllamaError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func listModels(baseURL: URL) async throws -> [String] {
        let url = baseURL.appendingPathComponent("api/tags")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: req)
        try throwIfHTTPError(response, data: data)

        let decoded = try JSONDecoder().decode(TagsResponse.self, from: data)
        return decoded.models.map(\.name).sorted()
    }

    static func chat(
        baseURL: URL,
        model: String,
        systemPrompt: String?,
        userContent: String
    ) async throws -> String {
        var messages: [ChatMessage] = []
        if let systemPrompt, !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append(ChatMessage(role: "system", content: systemPrompt))
        }
        messages.append(ChatMessage(role: "user", content: userContent))

        let body = ChatRequest(model: model, messages: messages, stream: false)
        let url = baseURL.appendingPathComponent("api/chat")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        req.timeoutInterval = 600

        let (data, response) = try await URLSession.shared.data(for: req)
        try throwIfHTTPError(response, data: data)

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        return decoded.message.content
    }

    private static func throwIfHTTPError(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200 ... 299).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8) ?? ""
            throw OllamaError(message: "HTTP \(http.statusCode): \(snippet.prefix(500))")
        }
    }

    private struct TagsResponse: Decodable {
        struct Model: Decodable {
            let name: String
        }

        let models: [Model]
    }

    private struct ChatMessage: Encodable {
        let role: String
        let content: String
    }

    private struct ChatRequest: Encodable {
        let model: String
        let messages: [ChatMessage]
        let stream: Bool
    }

    private struct ChatResponse: Decodable {
        struct Message: Decodable {
            let role: String
            let content: String
        }

        let message: Message
    }
}
