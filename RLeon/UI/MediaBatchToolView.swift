import AppKit
import SwiftUI

struct MediaBatchToolView: View {
    @EnvironmentObject private var mediaBatchTool: MediaBatchToolStore
    @EnvironmentObject private var appEnvironment: AppEnvironmentStore

    @AppStorage("geminiBatchApiKey") private var apiKey = ""
    @AppStorage("geminiBatchModel") private var model = ""
    @AppStorage("geminiBatchSystemPrompt") private var systemPrompt = ""
    @AppStorage("geminiBatchUserPrompt") private var userPrompt = ""
    @AppStorage("geminiBatchResponseMimeType") private var responseMimeType = ""
    @AppStorage("geminiBatchTemperature") private var temperatureText = ""
    @AppStorage("geminiBatchMaxFiles") private var maxFilesPerBatch = 10
    @AppStorage("geminiBatchPollInterval") private var pollIntervalSeconds = 30
    @AppStorage("geminiBatchSaveResults") private var saveResultsToFiles = true
    @AppStorage("geminiBatchSaveNextToSource") private var saveNextToSource = true
    @AppStorage("geminiBatchOutputDirectoryPath") private var outputDirectoryPath = ""
    @AppStorage("geminiBatchOutputExtension") private var outputExtension = ""
    @AppStorage("geminiBatchSkipExisting") private var skipExistingOutputFiles = true

    @State private var revealsAPIKey = false
    @State private var showPromptEditor = false
    @State private var showAdvancedOptions = false
    @State private var showLogs = false

    private enum PromptPreset: String, CaseIterable, Identifiable {
        case lectureNotes
        case genericAnalysis
        case structuredJSON

        var id: String { rawValue }

        var title: String {
            switch self {
            case .lectureNotes: return "Lecture notes"
            case .genericAnalysis: return "Generic analysis"
            case .structuredJSON: return "Structured JSON"
            }
        }

        var defaultModel: String { "gemini-3-pro-preview" }

        var systemPrompt: String {
            switch self {
            case .lectureNotes:
                return """
                You are an expert AI Engineering instructor's assistant, specialized in extracting and teaching every piece of knowledge from educational video content about AI agents, MCP (Model Context Protocol), and agentic systems.

                ---

                ## YOUR MISSION

                You will receive a transcript or content from a video lecture in the course: **"AI Engineer Agentic Track: The Complete Agent & MCP Course"**.

                Your job is to produce a **complete, detailed knowledge document** for a student who wants to fully learn and understand every single thing covered in the video — as if they are reading a thorough textbook chapter based on that video.

                ---

                ## STRICT RULES — READ CAREFULLY

                ### ✅ RULE 1: ZERO OMISSION POLICY
                - You MUST document **EVERY** concept, term, tool, technique, code pattern, analogy, comparison, "why" explanation, architecture decision, and example mentioned in the video.
                - **Do NOT summarize broadly.** Treat each individual point as its own item.
                - Even briefly mentioned tools, names, or terms must appear — if the instructor says it, you document it.
                - Going through the content **chronologically** is mandatory.
                - A longer, complete, detailed document is always better than a shorter, incomplete one. **Never sacrifice completeness for brevity.**

                ### ✅ RULE 2: FORMAT AND DEPTH FOR EACH ITEM
                For every point you extract, use this format:

                **🔹 [Concept/Topic Name]**
                → [A thorough explanation of this concept. Do not cut it short. Explain what it is, how it works, why it matters, and how it fits into the bigger picture — using the instructor's terminology and logic. Do not simplify to the point of losing meaning.]

                - If the instructor provides or implies a **code example**, reproduce it fully and annotate each part:
                  ```
                  //
                  ```

                - If the instructor explains a **workflow, pipeline, or sequence of steps**, list them clearly as numbered steps.

                - If the instructor makes a **comparison** (X vs Y, approach A vs approach B), present it as a clear side-by-side breakdown.

                - If the instructor uses an **analogy or metaphor**, include it — it helps retention.

                ### ✅ RULE 3: EXAM-CRITICAL FLAGGING
                Identify and flag concepts that are likely to appear in an exam. Use this judgment:
                - The instructor defines it explicitly or emphasizes it
                - The instructor repeats it more than once
                - It is a named framework, protocol, architecture, or design pattern
                - It involves a comparison (e.g., "X vs Y", "use X when..., use Y when...")
                - It answers a "why" or "how" question at a foundational level
                - It is a core building block of agentic systems or MCP

                For these items, add the following **immediately after the explanation**:

                > ⭐ **EXAM NOTE:** [A specific sentence explaining why this is likely to be tested — e.g., "This is the foundational definition of the agentic loop pattern; understanding it is required to answer any architecture-level question."]

                Also write the concept name in **bold** and mark it with ⭐ in the header:

                **⭐ 🔹 **

                ### ✅ RULE 4: OUTPUT STRUCTURE

                Start your response with:
                ```
                📹 VIDEO TOPIC:
                🕐 COVERAGE: [Approximate scope, e.g., "Introduction to MCP + Tool Calling Basics"]
                ```

                Then list all extracted points in **chronological order of appearance in the video**.

                End with:

                ```
                ***
                ## ⭐ MUST-KNOW LIST (Exam-Critical Concepts)
                [Numbered list of only the flagged concept names — no re-explanation, just names]
                ```

                ---

                ## CRITICAL REMINDER BEFORE YOU BEGIN

                > Before generating your output, ask yourself: *"Have I missed anything from this video — even a single term, analogy, code example, tool name, or explanation?"*
                > If yes, go back and add it. **Completeness and depth are your first and second obligations.** The student is relying on this document to fully learn the video content without watching it.

                ---
                """
            case .genericAnalysis:
                return """
                You analyze user-provided media files accurately. Use the file itself as the primary source of truth, avoid hallucinations, and state uncertainty when something is ambiguous.
                """
            case .structuredJSON:
                return """
                You convert media into precise structured data. Keep field names stable, avoid extra prose, and return only well-formed JSON that matches the requested shape.
                """
            }
        }

        var userPrompt: String {
            switch self {
            case .lectureNotes:
                return ""
            case .genericAnalysis:
                return "Analyze the attached file and return the most useful output in Markdown."
            case .structuredJSON:
                return """
                Return a JSON object with: title, summary, transcript_or_visible_text, key_points, entities, timestamps_if_any, action_items, and confidence_notes.
                """
            }
        }

        var responseMimeType: String {
            switch self {
            case .structuredJSON: return "application/json"
            default: return ""
            }
        }

        var outputExtension: String {
            switch self {
            case .structuredJSON: return "json"
            default: return "md"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RLeonSectionHeader("Media Batch", subtitle: "Choose files, keep the default prompt if it already matches your task, then run.")
                runCard
                filesCard
                outputCard
                promptCard
                advancedCard
                logsCard
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            hydrateFromEnvironmentIfNeeded()
        }
    }

    private var runCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            RLeonSectionHeader("1. Choose and run", subtitle: runSummary)

            HStack(spacing: 10) {
                Button("Choose files") { chooseFiles() }
                    .disabled(mediaBatchTool.isRunning)

                Button("Clear all") { mediaBatchTool.clearSelection() }
                    .disabled(mediaBatchTool.isRunning || mediaBatchTool.items.isEmpty)

                Spacer()

                if mediaBatchTool.isRunning {
                    Button("Cancel run", role: .destructive) { mediaBatchTool.cancelRun() }
                } else {
                    Button("Start batch") { startRun() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(mediaBatchTool.items.isEmpty)
                }
            }

            if mediaBatchTool.isRunning || mediaBatchTool.lastRunMessage != nil {
                Divider()
            }

            if let lastRunMessage = mediaBatchTool.lastRunMessage {
                Text(lastRunMessage)
                    .font(.caption)
                    .foregroundStyle(mediaBatchTool.currentBatchState == "Failed" ? .red : .secondary)
            }

            if mediaBatchTool.isRunning {
                VStack(alignment: .leading, spacing: 8) {
                    Text(mediaBatchTool.currentBatchName == nil ? mediaBatchTool.currentBatchState : "\(mediaBatchTool.currentBatchState) • \(mediaBatchTool.currentBatchName!)")
                        .font(.subheadline.weight(.semibold))
                    ProgressView(value: progressValue)
                }
            }
        }
        .rleonCard()
    }

    private var filesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            RLeonSectionHeader("2. Files", subtitle: "Current selection and per-file results.")

            if mediaBatchTool.items.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("No files selected yet.")
                        .font(.subheadline.weight(.medium))
                    Text("Pick video, audio, image, PDF, or text files to start.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Choose files") { chooseFiles() }
                }
                .padding(12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(mediaBatchTool.items) { item in
                        fileCard(item)
                    }
                }
            }
        }
        .rleonCard()
    }

    private var outputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            RLeonSectionHeader("3. Output", subtitle: "Default is Markdown next to the source file. Change only if needed.")

            Toggle("Save results to files", isOn: $saveResultsToFiles)
                .tint(RLeonTheme.accent)

            if saveResultsToFiles {
                Toggle("Save next to source file", isOn: $saveNextToSource)
                    .tint(RLeonTheme.accent)

                if !saveNextToSource {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Output folder")
                                .font(.subheadline.weight(.semibold))
                            Text(outputDirectoryDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer()

                        Button("Choose folder") {
                            chooseOutputFolder()
                        }
                    }
                }
            } else {
                Text("Results stay inside the app until you copy or export them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .rleonCard()
    }

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                RLeonSectionHeader("4. Prompt", subtitle: "Python-style lecture-notes prompt is preloaded. Edit only if you want a different output.")
                Spacer()
                Menu("Preset") {
                    ForEach(PromptPreset.allCases) { preset in
                        Button(preset.title) { applyPreset(preset) }
                    }
                }
            }

            DisclosureGroup(isExpanded: $showPromptEditor) {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("System prompt")
                            .font(.subheadline.weight(.semibold))
                        TextEditor(text: $systemPrompt)
                            .font(.body)
                            .frame(minHeight: 140)
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("User prompt")
                            .font(.subheadline.weight(.semibold))
                        TextEditor(text: $userPrompt)
                            .font(.body)
                            .frame(minHeight: 90)
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.top, 6)
            } label: {
                Text(showPromptEditor ? "Hide prompt editor" : "Edit prompt")
                    .font(.subheadline.weight(.medium))
            }
        }
        .rleonCard()
    }

    private var advancedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            DisclosureGroup(isExpanded: $showAdvancedOptions) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Button("Use app env") {
                            hydrateFromEnvironmentIfNeeded(force: true)
                        }
                        .controlSize(.small)

                        Button("Clear cache") { mediaBatchTool.clearCache() }
                            .controlSize(.small)
                            .disabled(mediaBatchTool.isRunning)

                        Spacer()

                        Text("Upload cache: \(mediaBatchTool.cacheEntryCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Gemini API key")
                                .font(.subheadline.weight(.semibold))
                            Group {
                                if revealsAPIKey {
                                    TextField("AIza...", text: $apiKey)
                                        .textFieldStyle(.roundedBorder)
                                } else {
                                    SecureField("AIza...", text: $apiKey)
                                        .textFieldStyle(.roundedBorder)
                                }
                            }
                        }

                        Button(revealsAPIKey ? "Hide" : "Show") {
                            revealsAPIKey.toggle()
                        }
                        .controlSize(.small)
                        .padding(.top, 24)
                    }

                    Text(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && appEnvironment.value(for: "GEMINI_API_KEY") != nil
                         ? "Using `GEMINI_API_KEY` from Settings → Environment variables when this field is blank."
                         : "You can leave fields blank and let the app env section provide defaults.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Model")
                                .font(.subheadline.weight(.semibold))
                            TextField("gemini-3-pro-preview", text: $model)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Response MIME type")
                                .font(.subheadline.weight(.semibold))
                            TextField("Optional, e.g. application/json", text: $responseMimeType)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Temperature")
                                .font(.subheadline.weight(.semibold))
                            TextField("Optional", text: $temperatureText)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 120)
                        }
                    }

                    HStack(spacing: 12) {
                        Stepper(value: $maxFilesPerBatch, in: 1 ... 100) {
                            Text("Max files per batch: \(maxFilesPerBatch)")
                        }
                        Stepper(value: $pollIntervalSeconds, in: 5 ... 300, step: 5) {
                            Text("Poll every \(pollIntervalSeconds)s")
                        }
                    }

                    Toggle("Skip files that already have an output file", isOn: $skipExistingOutputFiles)
                        .tint(RLeonTheme.accent)
                        .disabled(!saveResultsToFiles)

                    HStack(alignment: .center, spacing: 12) {
                        Text("Output extension")
                            .font(.subheadline.weight(.semibold))
                        TextField("md", text: $outputExtension)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 120)
                    }
                }
                .padding(.top, 6)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Advanced")
                        .font(.subheadline.weight(.semibold))
                    Text("API key, model, batch size, output extension, and cache.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .rleonCard()
    }

    private func fileCard(_ item: MediaBatchToolStore.Item) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol(for: item.mimeType))
                    .font(.title3)
                    .foregroundStyle(RLeonTheme.accent)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.fileURL.lastPathComponent)
                        .font(.subheadline.weight(.semibold))
                    Text("\(item.mimeType) • \(ByteCountFormatter.string(fromByteCount: item.fileSizeBytes, countStyle: .file))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let detail = item.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(item.phase == .failed ? .red : .secondary)
                            .textSelection(.enabled)
                    }
                }

                Spacer(minLength: 8)

                statusBadge(for: item.phase)

                if !mediaBatchTool.isRunning {
                    Button {
                        mediaBatchTool.remove(item.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove from selection")
                }
            }

            if let outputURL = item.outputURL {
                HStack(spacing: 10) {
                    Button("Reveal output") {
                        NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                    }
                    .controlSize(.small)

                    Button("Open result") {
                        NSWorkspace.shared.open(outputURL)
                    }
                    .controlSize(.small)
                }
            }

            if !item.outputText.isEmpty {
                ScrollView {
                    Text(item.outputText)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 140)
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))

                HStack {
                    Button("Copy result") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(item.outputText, forType: .string)
                    }
                    .controlSize(.small)
                    Spacer()
                }
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func statusBadge(for phase: MediaBatchToolStore.Phase) -> some View {
        let color: Color
        let text: String

        switch phase {
        case .queued:
            color = .secondary
            text = "Queued"
        case .skipped:
            color = .orange
            text = "Skipped"
        case .uploading:
            color = RLeonTheme.accent
            text = "Uploading"
        case .uploaded:
            color = RLeonTheme.accentSecondary
            text = "Uploaded"
        case .batchQueued:
            color = .secondary
            text = "Submitted"
        case .batchRunning:
            color = RLeonTheme.accent
            text = "Running"
        case .completed:
            color = .green
            text = "Done"
        case .saved:
            color = .green
            text = "Saved"
        case .failed:
            color = .red
            text = "Failed"
        case .cancelled:
            color = .orange
            text = "Cancelled"
        }

        return Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }

    private var logsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            DisclosureGroup(isExpanded: $showLogs) {
                ScrollView {
                    Text(mediaBatchTool.logs.isEmpty ? "No log entries yet." : mediaBatchTool.logs.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 140)
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .padding(.top, 6)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Logs")
                        .font(.subheadline.weight(.semibold))
                    Text("Hidden by default to keep the main flow clean.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .rleonCard()
    }

    private var outputDirectoryDescription: String {
        if saveNextToSource {
            return "Saved next to each source file."
        }
        if outputDirectoryPath.isEmpty {
            return "No output folder selected."
        }
        return outputDirectoryPath
    }

    private var progressValue: Double {
        guard mediaBatchTool.totalScheduled > 0 else { return 0 }
        return Double(mediaBatchTool.finishedCount) / Double(mediaBatchTool.totalScheduled)
    }

    private var runSummary: String {
        if mediaBatchTool.items.isEmpty {
            return "Pick one or more files. Each selected file becomes one batch request."
        }
        return "\(mediaBatchTool.items.count) file(s) selected. Start the batch when ready."
    }

    private func startRun() {
        let config = MediaBatchToolStore.RunConfiguration(
            apiKey: resolvedAPIKey,
            model: resolvedModel,
            systemPrompt: resolvedSystemPrompt,
            userPrompt: resolvedUserPrompt,
            responseMimeType: resolvedResponseMimeType,
            temperature: Double(temperatureText.trimmingCharacters(in: .whitespacesAndNewlines)),
            maxFilesPerBatch: max(1, maxFilesPerBatch),
            pollIntervalSeconds: max(5, pollIntervalSeconds),
            saveResultsToFiles: saveResultsToFiles,
            saveNextToSource: saveNextToSource,
            outputDirectory: outputDirectoryPath.isEmpty ? nil : URL(fileURLWithPath: outputDirectoryPath, isDirectory: true),
            outputExtension: resolvedOutputExtension,
            skipExistingOutputFiles: skipExistingOutputFiles
        )
        mediaBatchTool.start(configuration: config)
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK else { return }
        mediaBatchTool.addFiles(panel.urls)
    }

    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        outputDirectoryPath = url.path
    }

    private func applyPreset(_ preset: PromptPreset) {
        systemPrompt = preset.systemPrompt
        userPrompt = preset.userPrompt
        responseMimeType = preset.responseMimeType
        outputExtension = preset.outputExtension
    }

    private func hydrateFromEnvironmentIfNeeded(force: Bool = false) {
        if force || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            apiKey = appEnvironment.value(for: "GEMINI_API_KEY") ?? apiKey
        }
        if force || model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            model = appEnvironment.value(for: "GEMINI_MODEL") ?? PromptPreset.lectureNotes.defaultModel
        }
        if force || systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            systemPrompt = appEnvironment.value(for: "GEMINI_BATCH_SYSTEM_PROMPT") ?? PromptPreset.lectureNotes.systemPrompt
        }
        if force || userPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            userPrompt = appEnvironment.value(for: "GEMINI_BATCH_USER_PROMPT") ?? PromptPreset.lectureNotes.userPrompt
        }
        if force || responseMimeType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            responseMimeType = appEnvironment.value(for: "GEMINI_BATCH_RESPONSE_MIME_TYPE") ?? PromptPreset.lectureNotes.responseMimeType
        }
        if force || outputExtension.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            outputExtension = appEnvironment.value(for: "GEMINI_BATCH_OUTPUT_EXTENSION") ?? PromptPreset.lectureNotes.outputExtension
        }
    }

    private var resolvedAPIKey: String {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return appEnvironment.value(for: "GEMINI_API_KEY") ?? ""
    }

    private var resolvedModel: String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return appEnvironment.value(for: "GEMINI_MODEL") ?? PromptPreset.lectureNotes.defaultModel
    }

    private var resolvedSystemPrompt: String {
        let trimmed = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return appEnvironment.value(for: "GEMINI_BATCH_SYSTEM_PROMPT") ?? PromptPreset.lectureNotes.systemPrompt
    }

    private var resolvedUserPrompt: String {
        let trimmed = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return appEnvironment.value(for: "GEMINI_BATCH_USER_PROMPT") ?? PromptPreset.lectureNotes.userPrompt
    }

    private var resolvedResponseMimeType: String? {
        let trimmed = responseMimeType.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let envValue = appEnvironment.value(for: "GEMINI_BATCH_RESPONSE_MIME_TYPE") ?? PromptPreset.lectureNotes.responseMimeType
        return envValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : envValue
    }

    private var resolvedOutputExtension: String {
        let trimmed = outputExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let envValue = appEnvironment.value(for: "GEMINI_BATCH_OUTPUT_EXTENSION") ?? PromptPreset.lectureNotes.outputExtension
        return envValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "md" : envValue
    }

    private func symbol(for mimeType: String) -> String {
        if mimeType.hasPrefix("video/") { return "film.stack.fill" }
        if mimeType.hasPrefix("audio/") { return "waveform" }
        if mimeType.hasPrefix("image/") { return "photo.fill.on.rectangle.fill" }
        if mimeType == "application/pdf" { return "doc.richtext.fill" }
        return "doc.text.fill"
    }
}
