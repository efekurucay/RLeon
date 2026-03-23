import Foundation

@MainActor
final class MediaBatchToolStore: ObservableObject {
    enum Phase: String {
        case queued
        case skipped
        case uploading
        case uploaded
        case batchQueued
        case batchRunning
        case completed
        case saved
        case failed
        case cancelled
    }

    struct Item: Identifiable {
        let id = UUID()
        let fileURL: URL
        let mimeType: String
        let fileSizeBytes: Int64

        var phase: Phase = .queued
        var detail: String?
        var outputText: String = ""
        var outputURL: URL?
        var remoteFileURI: String?
        var remoteFileName: String?
    }

    struct RunConfiguration {
        let apiKey: String
        let model: String
        let systemPrompt: String
        let userPrompt: String
        let responseMimeType: String?
        let temperature: Double?
        let maxFilesPerBatch: Int
        let pollIntervalSeconds: Int
        let saveResultsToFiles: Bool
        let saveNextToSource: Bool
        let outputDirectory: URL?
        let outputExtension: String
        let skipExistingOutputFiles: Bool
    }

    @Published private(set) var items: [Item] = []
    @Published private(set) var isRunning = false
    @Published private(set) var currentBatchName: String?
    @Published private(set) var currentBatchState = "Idle"
    @Published private(set) var totalScheduled = 0
    @Published private(set) var finishedCount = 0
    @Published private(set) var cacheEntryCount = 0
    @Published private(set) var logs: [String] = []
    @Published private(set) var lastRunMessage: String?

    private let cacheStore = GeminiUploadCacheStore()
    private var runTask: Task<Void, Never>?
    private var activeAPIKeyForCancellation: String?

    init() {
        Task { await refreshCacheCount() }
    }

    func addFiles(_ urls: [URL]) {
        guard !isRunning else { return }
        let existingPaths = Set(items.map(\.fileURL.path))
        let newItems = urls
            .filter { !existingPaths.contains($0.path) }
            .compactMap { url -> Item? in
                let mimeType = GeminiBatchAPIClient.resolveMimeType(for: url)
                let size = (try? url.fileSizeBytes()) ?? 0
                return Item(fileURL: url, mimeType: mimeType, fileSizeBytes: size)
            }
        items.append(contentsOf: newItems.sorted { $0.fileURL.lastPathComponent.localizedCaseInsensitiveCompare($1.fileURL.lastPathComponent) == .orderedAscending })
    }

    func remove(_ itemID: UUID) {
        guard !isRunning else { return }
        items.removeAll { $0.id == itemID }
    }

    func clearSelection() {
        guard !isRunning else { return }
        items.removeAll()
        totalScheduled = 0
        finishedCount = 0
        lastRunMessage = nil
    }

    func clearCache() {
        Task {
            do {
                try await cacheStore.clear()
                await MainActor.run {
                    cacheEntryCount = 0
                    appendLog("Upload cache cleared.")
                }
            } catch {
                await MainActor.run {
                    appendLog("Upload cache could not be cleared: \(error.localizedDescription)")
                }
            }
        }
    }

    func start(configuration: RunConfiguration) {
        guard !isRunning else { return }

        let validationError = validate(configuration: configuration)
        if let validationError {
            lastRunMessage = validationError
            appendLog(validationError)
            return
        }

        isRunning = true
        activeAPIKeyForCancellation = configuration.apiKey
        lastRunMessage = nil
        currentBatchState = "Preparing"
        currentBatchName = nil
        finishedCount = 0
        totalScheduled = 0

        for index in items.indices {
            items[index].phase = .queued
            items[index].detail = nil
            items[index].outputText = ""
            items[index].outputURL = nil
            items[index].remoteFileURI = nil
            items[index].remoteFileName = nil
        }

        runTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.process(configuration: configuration)
            } catch is CancellationError {
                await MainActor.run {
                    self.currentBatchState = "Cancelled"
                    self.lastRunMessage = "Run cancelled."
                    self.appendLog("Run cancelled.")
                    self.markQueuedItemsCancelled()
                    self.isRunning = false
                    self.currentBatchName = nil
                    self.activeAPIKeyForCancellation = nil
                }
            } catch {
                await MainActor.run {
                    self.currentBatchState = "Failed"
                    self.lastRunMessage = error.localizedDescription
                    self.appendLog("Run failed: \(error.localizedDescription)")
                    self.markQueuedItemsFailed(message: error.localizedDescription)
                    self.isRunning = false
                    self.currentBatchName = nil
                    self.activeAPIKeyForCancellation = nil
                }
            }

            await self.refreshCacheCount()
        }
    }

    func cancelRun() {
        guard isRunning else { return }
        appendLog("Cancellation requested.")
        if let currentBatchName, let apiKey = activeAPIKeyForCancellation {
            Task {
                try? await GeminiBatchAPIClient.cancelBatch(apiKey: apiKey, name: currentBatchName)
            }
        }
        runTask?.cancel()
    }

    private func process(configuration: RunConfiguration) async throws {
        let processableIDs = try prepareItemsForRun(configuration: configuration)
        totalScheduled = processableIDs.count
        if processableIDs.isEmpty {
            currentBatchState = "Nothing to do"
            lastRunMessage = "No files needed processing."
            appendLog("Nothing to process.")
            isRunning = false
            activeAPIKeyForCancellation = nil
            currentBatchName = nil
            return
        }

        let chunkSize = max(1, configuration.maxFilesPerBatch)
        let chunks = processableIDs.chunked(into: chunkSize)
        appendLog("Starting Gemini batch run for \(processableIDs.count) file(s) in \(chunks.count) batch(es).")

        for (chunkIndex, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            appendLog("Batch \(chunkIndex + 1)/\(chunks.count): preparing \(chunk.count) file(s).")

            var preparedRequests: [(itemID: UUID, request: InlinedBatchRequest)] = []
            for itemID in chunk {
                try Task.checkCancellation()
                guard let item = item(for: itemID) else { continue }

                updateItem(itemID) { item in
                    item.phase = .uploading
                    item.detail = "Uploading to Gemini Files API"
                }

                do {
                    let uploaded = try await GeminiBatchAPIClient.uploadFile(
                        apiKey: configuration.apiKey,
                        fileURL: item.fileURL,
                        cacheStore: cacheStore
                    )

                    updateItem(itemID) { item in
                        item.phase = .uploaded
                        item.detail = "Uploaded as \(uploaded.name)"
                        item.remoteFileURI = uploaded.uri
                        item.remoteFileName = uploaded.name
                    }

                    let request = GeminiBatchAPIClient.makeBatchRequest(
                        uploadedFile: uploaded,
                        configuration: .init(
                            systemPrompt: configuration.systemPrompt,
                            userPrompt: configuration.userPrompt,
                            responseMimeType: configuration.responseMimeType,
                            temperature: configuration.temperature
                        )
                    )
                    preparedRequests.append((itemID: itemID, request: request))
                } catch {
                    updateItem(itemID) { item in
                        item.phase = .failed
                        item.detail = error.localizedDescription
                    }
                    finishedCount += 1
                    appendLog("Upload failed for \(item.fileURL.lastPathComponent): \(error.localizedDescription)")
                }
            }

            guard !preparedRequests.isEmpty else { continue }

            let batchName = try await GeminiBatchAPIClient.createInlineBatch(
                apiKey: configuration.apiKey,
                model: configuration.model,
                displayName: "rleon-media-\(Self.batchTimestamp())",
                requests: preparedRequests.map(\.request)
            )

            currentBatchName = batchName
            currentBatchState = "Submitted"
            appendLog("Created batch \(batchName).")

            for prepared in preparedRequests {
                updateItem(prepared.itemID) { item in
                    item.phase = .batchQueued
                    item.detail = batchName
                }
            }

            let finalStatus = try await pollBatch(
                apiKey: configuration.apiKey,
                batchName: batchName,
                itemIDs: preparedRequests.map(\.itemID),
                pollIntervalSeconds: configuration.pollIntervalSeconds
            )

            try Task.checkCancellation()

            if finalStatus.state.isSuccessState {
                let responses = finalStatus.inlinedResponses
                for (index, prepared) in preparedRequests.enumerated() {
                    let response = index < responses.count ? responses[index] : GeminiBatchInlinedResponse(text: nil, errorMessage: "No inline response returned.")
                    try finalize(
                        response: response,
                        itemID: prepared.itemID,
                        configuration: configuration
                    )
                }
            } else if finalStatus.state.isCancelledState {
                for prepared in preparedRequests {
                    updateItem(prepared.itemID) { item in
                        item.phase = .cancelled
                        item.detail = "Batch was cancelled."
                    }
                    finishedCount += 1
                }
                throw CancellationError()
            } else {
                let message = finalStatus.errorMessage ?? "Batch ended with state \(finalStatus.state)."
                for prepared in preparedRequests {
                    updateItem(prepared.itemID) { item in
                        item.phase = .failed
                        item.detail = message
                    }
                    finishedCount += 1
                }
                appendLog("Batch \(batchName) failed: \(message)")
            }
        }

        currentBatchName = nil
        currentBatchState = "Completed"
        lastRunMessage = "Finished \(finishedCount) / \(totalScheduled) scheduled file(s)."
        appendLog(lastRunMessage ?? "Run completed.")
        isRunning = false
        activeAPIKeyForCancellation = nil
    }

    private func prepareItemsForRun(configuration: RunConfiguration) throws -> [UUID] {
        var processableIDs: [UUID] = []

        for index in items.indices {
            let outputURL = configuration.saveResultsToFiles ? try plannedOutputURL(for: items[index].fileURL, configuration: configuration) : nil
            if configuration.saveResultsToFiles,
               configuration.skipExistingOutputFiles,
               let outputURL,
               FileManager.default.fileExists(atPath: outputURL.path)
            {
                items[index].phase = .skipped
                items[index].detail = "Output already exists: \(outputURL.lastPathComponent)"
                items[index].outputURL = outputURL
                continue
            }

            items[index].phase = .queued
            items[index].detail = nil
            items[index].outputURL = outputURL
            processableIDs.append(items[index].id)
        }

        return processableIDs
    }

    private func pollBatch(
        apiKey: String,
        batchName: String,
        itemIDs: [UUID],
        pollIntervalSeconds: Int
    ) async throws -> GeminiBatchStatus {
        let interval = UInt64(max(5, pollIntervalSeconds)) * 1_000_000_000
        while true {
            try Task.checkCancellation()
            let status = try await GeminiBatchAPIClient.getBatchStatus(apiKey: apiKey, name: batchName)
            currentBatchState = status.state

            for itemID in itemIDs {
                updateItem(itemID) { item in
                    item.phase = status.state.isTerminalState ? item.phase : .batchRunning
                    item.detail = status.state
                }
            }

            if status.state.isTerminalState || status.done {
                appendLog("Batch \(batchName) finished with state \(status.state).")
                return status
            }

            appendLog("Batch \(batchName) state: \(status.state)")
            try await Task.sleep(nanoseconds: interval)
        }
    }

    private func finalize(
        response: GeminiBatchInlinedResponse,
        itemID: UUID,
        configuration: RunConfiguration
    ) throws {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }

        if let errorMessage = response.errorMessage, !errorMessage.isEmpty {
            items[index].phase = .failed
            items[index].detail = errorMessage
            finishedCount += 1
            appendLog("Failed \(items[index].fileURL.lastPathComponent): \(errorMessage)")
            return
        }

        let text = response.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            items[index].phase = .failed
            items[index].detail = "Gemini returned an empty response."
            finishedCount += 1
            appendLog("Empty response for \(items[index].fileURL.lastPathComponent).")
            return
        }

        items[index].outputText = text

        if configuration.saveResultsToFiles {
            let outputURL = try plannedOutputURL(for: items[index].fileURL, configuration: configuration)
            try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: outputURL, atomically: true, encoding: .utf8)
            items[index].outputURL = outputURL
            items[index].phase = .saved
            items[index].detail = outputURL.path
            appendLog("Saved \(items[index].fileURL.lastPathComponent) → \(outputURL.lastPathComponent)")
        } else {
            items[index].phase = .completed
            items[index].detail = "Response ready in app"
            appendLog("Completed \(items[index].fileURL.lastPathComponent)")
        }

        finishedCount += 1
    }

    private func plannedOutputURL(for sourceURL: URL, configuration: RunConfiguration) throws -> URL {
        let ext = configuration.outputExtension.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "md"
            : configuration.outputExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        let fileName = sourceURL.deletingPathExtension().lastPathComponent + "." + ext

        if configuration.saveNextToSource {
            return sourceURL.deletingLastPathComponent().appendingPathComponent(fileName)
        }

        guard let outputDirectory = configuration.outputDirectory else {
            throw GeminiBatchAPIClient.GeminiError(message: "Choose an output folder or enable saving next to the source file.")
        }
        return outputDirectory.appendingPathComponent(fileName)
    }

    private func validate(configuration: RunConfiguration) -> String? {
        if items.isEmpty {
            return "Choose at least one media file."
        }
        if configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Gemini API key is required."
        }
        if configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Gemini model is required."
        }
        if configuration.saveResultsToFiles,
           !configuration.saveNextToSource,
           configuration.outputDirectory == nil
        {
            return "Choose an output folder or save results next to the original file."
        }
        return nil
    }

    private func item(for itemID: UUID) -> Item? {
        items.first { $0.id == itemID }
    }

    private func updateItem(_ itemID: UUID, mutate: (inout Item) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        mutate(&items[index])
    }

    private func refreshCacheCount() async {
        do {
            let count = try await cacheStore.count()
            await MainActor.run { self.cacheEntryCount = count }
        } catch {
            await MainActor.run { self.appendLog("Could not read upload cache: \(error.localizedDescription)") }
        }
    }

    private func markQueuedItemsCancelled() {
        for index in items.indices where items[index].phase == .queued || items[index].phase == .uploading || items[index].phase == .uploaded || items[index].phase == .batchQueued || items[index].phase == .batchRunning {
            items[index].phase = .cancelled
            items[index].detail = "Cancelled"
        }
    }

    private func markQueuedItemsFailed(message: String) {
        for index in items.indices where items[index].phase == .queued || items[index].phase == .uploading || items[index].phase == .uploaded || items[index].phase == .batchQueued || items[index].phase == .batchRunning {
            items[index].phase = .failed
            items[index].detail = message
        }
    }

    private func appendLog(_ message: String) {
        let timestamp = Self.logTimeFormatter.string(from: Date())
        logs.append("[\(timestamp)] \(message)")
        if logs.count > 300 {
            logs.removeFirst(logs.count - 300)
        }
    }

    private static func batchTimestamp() -> String {
        batchFormatter.string(from: Date())
    }

    private static let batchFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    private static let logTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter
    }()
}

private extension String {
    var isTerminalState: Bool {
        [
            "JOB_STATE_SUCCEEDED",
            "JOB_STATE_FAILED",
            "JOB_STATE_CANCELLED",
            "JOB_STATE_EXPIRED",
            "BATCH_STATE_SUCCEEDED",
            "BATCH_STATE_FAILED",
            "BATCH_STATE_CANCELLED",
            "BATCH_STATE_EXPIRED",
        ].contains(self)
    }

    var isSuccessState: Bool {
        self == "JOB_STATE_SUCCEEDED" || self == "BATCH_STATE_SUCCEEDED"
    }

    var isCancelledState: Bool {
        self == "JOB_STATE_CANCELLED" || self == "BATCH_STATE_CANCELLED"
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        var result: [[Element]] = []
        var index = startIndex
        while index < endIndex {
            let nextIndex = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            result.append(Array(self[index ..< nextIndex]))
            index = nextIndex
        }
        return result
    }
}

private extension URL {
    func fileSizeBytes() throws -> Int64 {
        let values = try resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }
}
