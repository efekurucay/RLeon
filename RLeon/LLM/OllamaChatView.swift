import SwiftUI

/// Local Ollama chat: connection, system prompt, and send message.
struct OllamaChatView: View {
    var speechTranscript: String
    var ocrText: String

    @AppStorage("ollamaBaseURL") private var baseURLString = "http://127.0.0.1:11434"
    @AppStorage("ollamaModel") private var modelName = "qwen2.5:7b"
    @AppStorage("ollamaUseTools") private var useToolCalling = false
    @AppStorage("rleonSystemPrompt") private var systemPrompt = ""

    @State private var userMessage = ""
    @State private var assistantReply = ""
    @State private var isBusy = false
    @State private var errorText: String?
    @State private var availableModels: [String] = []
    @State private var promptPreset: PromptPreset = .standard

    private enum PromptPreset: String, CaseIterable, Identifiable {
        case standard
        case concise
        case technical
        var id: String { rawValue }
        var label: String {
            switch self {
            case .standard: return "Default"
            case .concise: return "Concise"
            case .technical: return "Technical"
            }
        }
        var text: String {
            switch self {
            case .standard:
                return "You are a helpful assistant. Answer in clear English; use bullet points when helpful."
            case .concise:
                return "Reply in English. Be brief and direct; no filler."
            case .technical:
                return "For technical and code topics, be detailed; give examples or shell commands when useful. Answer in English."
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RLeonSectionHeader("Local LLM", subtitle: "Ollama (`ollama serve`) — stays on your machine.")

                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("Server") {
                        TextField("http://127.0.0.1:11434", text: $baseURLString)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Model") {
                        HStack {
                            TextField("qwen2.5:7b", text: $modelName)
                                .textFieldStyle(.roundedBorder)
                            Button("List models") {
                                Task { await refreshModels() }
                            }
                            .disabled(isBusy)
                        }
                    }
                    if !availableModels.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(availableModels, id: \.self) { name in
                                    Button(name) { modelName = name }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                }
                            }
                        }
                    }
                }
                .rleonCard()

                VStack(alignment: .leading, spacing: 10) {
                    Text("System prompt")
                        .font(.subheadline.weight(.semibold))
                    Picker("Template", selection: $promptPreset) {
                        ForEach(PromptPreset.allCases) { p in
                            Text(p.label).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: promptPreset) { _, new in
                        systemPrompt = new.text
                    }
                    TextEditor(text: $systemPrompt)
                        .font(.body)
                        .frame(minHeight: 88)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                }
                .rleonCard()
                .onAppear {
                    if systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        systemPrompt = PromptPreset.standard.text
                    }
                }

                Toggle("Local tools (tool calling)", isOn: $useToolCalling)
                    .tint(RLeonTheme.accent)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Message")
                        .font(.subheadline.weight(.semibold))
                    HStack {
                        Button("Speech") { userMessage = speechTranscript }
                            .disabled(speechTranscript.isEmpty)
                        Button("OCR") { userMessage = ocrText }
                            .disabled(ocrText.isEmpty)
                        Button("Merge") {
                            var p: [String] = []
                            if !speechTranscript.isEmpty { p.append("[Speech]\n\(speechTranscript)") }
                            if !ocrText.isEmpty { p.append("[OCR]\n\(ocrText)") }
                            userMessage = p.joined(separator: "\n\n")
                        }
                        .disabled(speechTranscript.isEmpty && ocrText.isEmpty)
                    }
                    .controlSize(.small)
                    TextEditor(text: $userMessage)
                        .font(.body)
                        .frame(minHeight: 120)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    HStack {
                        Button("Send") {
                            Task { await runChat() }
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(isBusy || userMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if isBusy { ProgressView().controlSize(.small) }
                    }
                }
                .rleonCard()

                if let errorText {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Reply")
                        .font(.subheadline.weight(.semibold))
                    Text(assistantReply.isEmpty ? "…" : assistantReply)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .rleonCard()
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func baseURL() throws -> URL {
        guard let u = URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = u.scheme, scheme == "http" || scheme == "https" else {
            throw OllamaClient.OllamaError(message: "Enter a valid URL (e.g. http://127.0.0.1:11434).")
        }
        return u
    }

    private func refreshModels() async {
        errorText = nil
        isBusy = true
        defer { isBusy = false }
        do {
            let url = try baseURL()
            availableModels = try await OllamaClient.listModels(baseURL: url)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func runChat() async {
        errorText = nil
        assistantReply = ""
        isBusy = true
        defer { isBusy = false }
        do {
            let url = try baseURL()
            let m = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !m.isEmpty else {
                throw OllamaClient.OllamaError(message: "Model name is empty.")
            }
            let content = userMessage
            let toolsEnabled = useToolCalling && !LocalToolStore.loadEnabled().isEmpty
            if toolsEnabled {
                assistantReply = try await OllamaToolCalling.chatWithLocalTools(
                    baseURL: url,
                    model: m,
                    systemPrompt: systemPrompt,
                    userContent: content
                )
            } else {
                assistantReply = try await OllamaClient.chat(
                    baseURL: url,
                    model: m,
                    systemPrompt: systemPrompt,
                    userContent: content
                )
            }
        } catch {
            errorText = error.localizedDescription
        }
    }
}
