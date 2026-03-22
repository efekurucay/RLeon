import Foundation

/// Streaming variant of the Ollama chat API.
///
/// Uses `URLSession.AsyncBytes` to consume the server-sent newline-delimited JSON
/// stream emitted by Ollama when `"stream": true` is set.  Each line is a JSON
/// object with a `message.content` delta field.
///
/// Usage:
/// ```swift
/// var assembled = ""
/// for try await token in OllamaStreamClient.stream(baseURL: url, model: model,
///                                                   systemPrompt: system,
///                                                   userContent: user) {
///     assembled += token
///     await MainActor.run { self.reply = assembled }
/// }
/// ```
enum OllamaStreamClient {

    // MARK: - Public API

    /// Returns an `AsyncThrowingStream` that yields token strings as they arrive.
    /// - Parameters:
    ///   - baseURL:     Ollama server base URL.
    ///   - model:       Model name.
    ///   - systemPrompt: Optional system role message.
    ///   - userContent:  User message content.
    ///   - session:     URLSession to use (injectable for testing; defaults to `.shared`).
    static func stream(
        baseURL: URL,
        model: String,
        systemPrompt: String?,
        userContent: String,
        session: URLSession = .shared
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await performStream(
                        baseURL: baseURL,
                        model: model,
                        systemPrompt: systemPrompt,
                        userContent: userContent,
                        session: session,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private implementation

    private static func performStream(
        baseURL: URL,
        model: String,
        systemPrompt: String?,
        userContent: String,
        session: URLSession,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        var messages: [[String: String]] = []
        if let sp = systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines), !sp.isEmpty {
            messages.append(["role": "system", "content": sp])
        }
        messages.append(["role": "user", "content": userContent])

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "stream": true,
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body, options: [])
        let url = baseURL.appendingPathComponent("api/chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        request.timeoutInterval = 600

        let (asyncBytes, response) = try await session.bytes(for: request)
        try OllamaClient.throwIfHTTPError(response, data: Data())

        // Each line is a JSON object: {"message":{"role":"assistant","content":"<token>"},"done":false}
        for try await line in asyncBytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let lineData = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }

            if let msg = json["message"] as? [String: Any],
               let content = msg["content"] as? String,
               !content.isEmpty {
                continuation.yield(content)
            }

            // Ollama signals the end with `"done": true`
            if let done = json["done"] as? Bool, done {
                break
            }
        }
    }
}
