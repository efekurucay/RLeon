import Foundation
import UniformTypeIdentifiers

struct GeminiUploadedFile {
    let name: String
    let uri: String
    let mimeType: String
    let expirationTime: String?
}

struct GeminiBatchInlinedResponse {
    let text: String?
    let errorMessage: String?
}

struct GeminiBatchStatus {
    let name: String
    let state: String
    let done: Bool
    let inlinedResponses: [GeminiBatchInlinedResponse]
    let errorMessage: String?
}

actor GeminiUploadCacheStore {
    struct Entry: Codable {
        let cacheKey: String
        let filePath: String
        let name: String
        let uri: String
        let mimeType: String
        let uploadedAt: String
        let expirationTime: String?
    }

    private let fileURL: URL
    private var entries: [String: Entry] = [:]
    private var hasLoaded = false

    init(fileManager: FileManager = .default) {
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let cacheDirectory = baseDirectory.appendingPathComponent("RLeon", isDirectory: true)
        fileURL = cacheDirectory.appendingPathComponent("gemini-upload-cache.json")
    }

    func cachedFile(for localFileURL: URL) throws -> GeminiUploadedFile? {
        try loadIfNeeded()
        pruneExpiredEntries()
        let key = try cacheKey(for: localFileURL)
        guard let entry = entries[key] else { return nil }
        return GeminiUploadedFile(
            name: entry.name,
            uri: entry.uri,
            mimeType: entry.mimeType,
            expirationTime: entry.expirationTime
        )
    }

    func store(file: GeminiUploadedFile, for localFileURL: URL) throws {
        try loadIfNeeded()
        let key = try cacheKey(for: localFileURL)
        entries[key] = Entry(
            cacheKey: key,
            filePath: localFileURL.path,
            name: file.name,
            uri: file.uri,
            mimeType: file.mimeType,
            uploadedAt: Self.iso8601String(from: Date()),
            expirationTime: file.expirationTime
        )
        try save()
    }

    func clear() throws {
        entries.removeAll()
        hasLoaded = true
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    func count() throws -> Int {
        try loadIfNeeded()
        pruneExpiredEntries()
        return entries.count
    }

    private func loadIfNeeded() throws {
        guard !hasLoaded else { return }
        defer { hasLoaded = true }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            entries = [:]
            return
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        entries = try decoder.decode([String: Entry].self, from: data)
        pruneExpiredEntries()
    }

    private func save() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }

    private func cacheKey(for localFileURL: URL) throws -> String {
        let values = try localFileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = values.fileSize ?? 0
        let modifiedAt = values.contentModificationDate?.timeIntervalSince1970 ?? 0
        return "\(localFileURL.path)::\(size)::\(Int(modifiedAt))"
    }

    private func pruneExpiredEntries() {
        let now = Date()
        let filtered = entries.filter { _, entry in
            if let expirationTime = entry.expirationTime,
               let expirationDate = Self.parseISO8601(expirationTime)
            {
                return expirationDate > now
            }

            guard let uploadedAt = Self.parseISO8601(entry.uploadedAt) else { return false }
            return uploadedAt.addingTimeInterval(47 * 60 * 60) > now
        }

        if filtered.count != entries.count {
            entries = filtered
            try? save()
        }
    }

    private static func parseISO8601(_ value: String) -> Date? {
        if let date = fractionalFormatter.date(from: value) {
            return date
        }
        return basicFormatter.date(from: value)
    }

    private static func iso8601String(from date: Date) -> String {
        fractionalFormatter.string(from: date)
    }

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let basicFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

enum GeminiBatchAPIClient {
    struct GeminiError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    struct RequestConfiguration {
        let systemPrompt: String
        let userPrompt: String
        let responseMimeType: String?
        let temperature: Double?
    }

    static func resolveMimeType(for fileURL: URL) -> String {
        if let values = try? fileURL.resourceValues(forKeys: [.contentTypeKey]),
           let type = values.contentType,
           let mimeType = type.preferredMIMEType
        {
            return mimeType
        }

        let ext = fileURL.pathExtension
        if let type = UTType(filenameExtension: ext), let mimeType = type.preferredMIMEType {
            return mimeType
        }

        switch ext.lowercased() {
        case "md": return "text/markdown"
        case "jsonl", "ndjson": return "application/x-ndjson"
        case "m4a": return "audio/mp4"
        case "m4v": return "video/x-m4v"
        case "mov": return "video/quicktime"
        default: return "application/octet-stream"
        }
    }

    static func uploadFile(
        apiKey: String,
        fileURL: URL,
        cacheStore: GeminiUploadCacheStore
    ) async throws -> GeminiUploadedFile {
        try Task.checkCancellation()
        if let cached = try await cacheStore.cachedFile(for: fileURL) {
            return cached
        }

        let mimeType = resolveMimeType(for: fileURL)
        let fileSize = try fileURL.fileSizeBytes()
        let displayName = fileURL.deletingPathExtension().lastPathComponent

        let startURL = URL(string: "https://generativelanguage.googleapis.com/upload/v1beta/files")!
        var startRequest = URLRequest(url: startURL)
        startRequest.httpMethod = "POST"
        startRequest.timeoutInterval = 120
        startRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        startRequest.setValue("resumable", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        startRequest.setValue("start", forHTTPHeaderField: "X-Goog-Upload-Command")
        startRequest.setValue(String(fileSize), forHTTPHeaderField: "X-Goog-Upload-Header-Content-Length")
        startRequest.setValue(mimeType, forHTTPHeaderField: "X-Goog-Upload-Header-Content-Type")
        startRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        startRequest.httpBody = try encodeSnakeCase(FileUploadStartEnvelope(file: FileUploadMetadata(displayName: displayName)))

        let (_, startResponse) = try await URLSession.shared.data(for: startRequest)
        try throwIfHTTPError(startResponse, data: Data())

        guard let httpResponse = startResponse as? HTTPURLResponse,
              let uploadURLHeader = httpResponse.value(forHTTPHeaderField: "x-goog-upload-url"),
              let uploadURL = URL(string: uploadURLHeader.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            throw GeminiError(message: "Could not start resumable Gemini upload.")
        }

        var uploadRequest = URLRequest(url: uploadURL)
        uploadRequest.httpMethod = "POST"
        uploadRequest.timeoutInterval = 3_600
        uploadRequest.setValue(String(fileSize), forHTTPHeaderField: "Content-Length")
        uploadRequest.setValue("0", forHTTPHeaderField: "X-Goog-Upload-Offset")
        uploadRequest.setValue("upload, finalize", forHTTPHeaderField: "X-Goog-Upload-Command")

        let (uploadData, uploadResponse) = try await URLSession.shared.upload(for: uploadRequest, fromFile: fileURL)
        try throwIfHTTPError(uploadResponse, data: uploadData)

        let uploadedEnvelope = try JSONDecoder().decode(FileEnvelope.self, from: uploadData)
        let activeFile = try await waitUntilFileIsActive(
            apiKey: apiKey,
            initialFile: uploadedEnvelope.file
        )

        let result = GeminiUploadedFile(
            name: activeFile.name,
            uri: activeFile.uri,
            mimeType: activeFile.mimeType ?? mimeType,
            expirationTime: activeFile.expirationTime
        )
        try await cacheStore.store(file: result, for: fileURL)
        return result
    }

    static func createInlineBatch(
        apiKey: String,
        model: String,
        displayName: String,
        requests: [InlinedBatchRequest]
    ) async throws -> String {
        let normalizedModel = modelPathComponent(from: model)
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(normalizedModel):batchGenerateContent")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encodeSnakeCase(BatchCreateEnvelope(
            batch: BatchCreateRequest(
                displayName: displayName,
                inputConfig: BatchInputConfig(
                    requests: BatchRequestList(requests: requests)
                )
            )
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        try throwIfHTTPError(response, data: data)

        let operation = try JSONDecoder().decode(BatchOperation.self, from: data)
        guard !operation.name.isEmpty else {
            throw GeminiError(message: "Gemini Batch API did not return a batch name.")
        }
        return operation.name
    }

    static func getBatchStatus(apiKey: String, name: String) async throws -> GeminiBatchStatus {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/\(name)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 60
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let (data, response) = try await URLSession.shared.data(for: request)
        try throwIfHTTPError(response, data: data)

        let operation = try JSONDecoder().decode(BatchOperation.self, from: data)
        let responses = operation.response?.inlinedResponses?.map { inline in
            GeminiBatchInlinedResponse(
                text: inline.response?.textValue,
                errorMessage: inline.error?.message
            )
        } ?? []

        let state = operation.metadata?.state
            ?? (operation.done == true ? (operation.error == nil ? "JOB_STATE_SUCCEEDED" : "JOB_STATE_FAILED") : "JOB_STATE_PENDING")

        return GeminiBatchStatus(
            name: operation.name,
            state: state,
            done: operation.done ?? false,
            inlinedResponses: responses,
            errorMessage: operation.error?.message
        )
    }

    static func cancelBatch(apiKey: String, name: String) async throws {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/\(name):cancel")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let (data, response) = try await URLSession.shared.data(for: request)
        try throwIfHTTPError(response, data: data)
    }

    static func makeBatchRequest(
        uploadedFile: GeminiUploadedFile,
        configuration: RequestConfiguration
    ) -> InlinedBatchRequest {
        var parts: [RequestPart] = [
            RequestPart(fileData: RequestFileData(mimeType: uploadedFile.mimeType, fileURI: uploadedFile.uri))
        ]

        let trimmedUserPrompt = configuration.userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedUserPrompt.isEmpty {
            parts.append(RequestPart(text: trimmedUserPrompt))
        }

        let trimmedSystemPrompt = configuration.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let systemInstruction = trimmedSystemPrompt.isEmpty
            ? nil
            : RequestContent(parts: [RequestPart(text: trimmedSystemPrompt)])

        let generationConfig: RequestGenerationConfig?
        if let responseMimeType = configuration.responseMimeType?.trimmingCharacters(in: .whitespacesAndNewlines),
           !responseMimeType.isEmpty || configuration.temperature != nil
        {
            generationConfig = RequestGenerationConfig(
                responseMimeType: responseMimeType.isEmpty ? nil : responseMimeType,
                temperature: configuration.temperature
            )
        } else if configuration.temperature != nil {
            generationConfig = RequestGenerationConfig(responseMimeType: nil, temperature: configuration.temperature)
        } else {
            generationConfig = nil
        }

        return InlinedBatchRequest(
            request: BatchGenerateRequest(
                contents: [RequestContent(role: "user", parts: parts)],
                systemInstruction: systemInstruction,
                generationConfig: generationConfig
            ),
            metadata: nil
        )
    }

    private static func waitUntilFileIsActive(
        apiKey: String,
        initialFile: GeminiFile
    ) async throws -> GeminiFile {
        var file = initialFile
        while file.state == "PROCESSING" {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 5_000_000_000)
            file = try await getFile(apiKey: apiKey, name: file.name)
        }

        guard file.state == "ACTIVE" else {
            let detail = file.error?.message ?? file.state ?? "unknown"
            throw GeminiError(message: "Gemini file upload did not become active: \(detail)")
        }

        return file
    }

    private static func getFile(apiKey: String, name: String) async throws -> GeminiFile {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/\(name)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 60
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let (data, response) = try await URLSession.shared.data(for: request)
        try throwIfHTTPError(response, data: data)
        return try JSONDecoder().decode(FileEnvelope.self, from: data).file
    }

    private static func modelPathComponent(from input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("models/") {
            return String(trimmed.dropFirst("models/".count))
        }
        return trimmed
    }

    private static func encodeSnakeCase<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try encoder.encode(value)
    }

    private static func throwIfHTTPError(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200 ... 299).contains(http.statusCode) else {
            if let apiError = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
                throw GeminiError(message: "HTTP \(http.statusCode): \(apiError.error.message)")
            }
            let snippet = String(data: data, encoding: .utf8) ?? ""
            throw GeminiError(message: "HTTP \(http.statusCode): \(snippet.prefix(500))")
        }
    }
}

struct InlinedBatchRequest: Encodable {
    let request: BatchGenerateRequest
    let metadata: [String: String]?
}

private struct FileUploadStartEnvelope: Encodable {
    let file: FileUploadMetadata
}

private struct FileUploadMetadata: Encodable {
    let displayName: String
}

private struct FileEnvelope: Decodable {
    let file: GeminiFile
}

private struct GeminiFile: Decodable {
    let name: String
    let uri: String
    let mimeType: String?
    let state: String?
    let expirationTime: String?
    let error: GoogleStatus?
}

private struct BatchCreateEnvelope: Encodable {
    let batch: BatchCreateRequest
}

private struct BatchCreateRequest: Encodable {
    let displayName: String
    let inputConfig: BatchInputConfig
}

private struct BatchInputConfig: Encodable {
    let requests: BatchRequestList
}

private struct BatchRequestList: Encodable {
    let requests: [InlinedBatchRequest]
}

struct BatchGenerateRequest: Encodable {
    let contents: [RequestContent]
    let systemInstruction: RequestContent?
    let generationConfig: RequestGenerationConfig?
}

struct RequestContent: Encodable {
    let role: String?
    let parts: [RequestPart]

    init(role: String? = nil, parts: [RequestPart]) {
        self.role = role
        self.parts = parts
    }
}

struct RequestPart: Encodable {
    let text: String?
    let fileData: RequestFileData?

    init(text: String? = nil, fileData: RequestFileData? = nil) {
        self.text = text
        self.fileData = fileData
    }
}

struct RequestFileData: Encodable {
    let mimeType: String
    let fileURI: String
}

struct RequestGenerationConfig: Encodable {
    let responseMimeType: String?
    let temperature: Double?
}

private struct BatchOperation: Decodable {
    let name: String
    let metadata: BatchMetadata?
    let done: Bool?
    let error: GoogleStatus?
    let response: BatchResponsePayload?
}

private struct BatchMetadata: Decodable {
    let state: String?
}

private struct BatchResponsePayload: Decodable {
    let inlinedResponses: [BatchInlineResponsePayload]?
    let responsesFile: String?

    private enum CodingKeys: String, CodingKey {
        case inlinedResponses
        case responsesFile
        case output
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let output = try container.decodeIfPresent(OutputContainer.self, forKey: .output)
        let decodedInlinedResponses: [BatchInlineResponsePayload]?

        if let nestedResponses = try container.decodeIfPresent(InlinedResponsesContainer.self, forKey: .inlinedResponses) {
            decodedInlinedResponses = nestedResponses.inlinedResponses
        } else {
            decodedInlinedResponses = try container.decodeIfPresent([BatchInlineResponsePayload].self, forKey: .inlinedResponses)
        }

        if let directFile = try container.decodeIfPresent(String.self, forKey: .responsesFile) {
            responsesFile = directFile
        } else if let output {
            responsesFile = output.responsesFile
        } else {
            responsesFile = nil
        }

        inlinedResponses = decodedInlinedResponses ?? output?.inlinedResponses?.inlinedResponses
    }
}

private struct InlinedResponsesContainer: Decodable {
    let inlinedResponses: [BatchInlineResponsePayload]
}

private struct OutputContainer: Decodable {
    let responsesFile: String?
    let inlinedResponses: InlinedResponsesContainer?
}

private struct BatchInlineResponsePayload: Decodable {
    let response: GeneratedContentResponse?
    let error: GoogleStatus?
}

private struct GeneratedContentResponse: Decodable {
    let candidates: [GeneratedCandidate]?

    var textValue: String? {
        let texts = candidates?
            .flatMap { $0.content?.parts ?? [] }
            .compactMap(\.text)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            ?? []
        guard !texts.isEmpty else { return nil }
        return texts.joined(separator: "\n\n")
    }
}

private struct GeneratedCandidate: Decodable {
    let content: GeneratedContent?
}

private struct GeneratedContent: Decodable {
    let parts: [GeneratedContentPart]?
}

private struct GeneratedContentPart: Decodable {
    let text: String?
}

private struct GoogleStatus: Decodable {
    let code: Int?
    let message: String?
}

private struct APIErrorEnvelope: Decodable {
    struct ErrorBody: Decodable {
        let code: Int?
        let message: String
        let status: String?
    }

    let error: ErrorBody
}

private extension URL {
    func fileSizeBytes() throws -> Int64 {
        let values = try resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }
}
