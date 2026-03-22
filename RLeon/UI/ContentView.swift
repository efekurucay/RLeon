import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var speech: SpeechTranscriber
    @EnvironmentObject private var fnCoordinator: FnPushToTalkCoordinator
    @EnvironmentObject private var toolStore: ToolSelectionStore

    @State private var ocrText = ""
    @State private var ocrError: String?
    @State private var isOcrBusy = false
    @State private var axTrusted = FocusedTextInsertion.isAccessibilityTrusted()
    @State private var sidebarSelection: SidebarSection = .home

    private enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
        case home
        case speech
        case ocr
        case llm
        case fnShortcut
        case settings
        var id: String { rawValue }
        var title: String {
            switch self {
            case .home: return "Home"
            case .speech: return "Speech"
            case .ocr: return "Image OCR"
            case .llm: return "LLM"
            case .fnShortcut: return "FN shortcut"
            case .settings: return "Settings"
            }
        }
        var symbol: String {
            switch self {
            case .home: return "house.fill"
            case .speech: return "mic.fill"
            case .ocr: return "text.viewfinder"
            case .llm: return "bubble.left.and.bubble.right.fill"
            case .fnShortcut: return "command"
            case .settings: return "gearshape.fill"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $sidebarSelection) {
                Section("RLeon") {
                    Label(SidebarSection.home.title, systemImage: SidebarSection.home.symbol)
                        .tag(SidebarSection.home)
                }
                Section("Input") {
                    Label(SidebarSection.speech.title, systemImage: SidebarSection.speech.symbol)
                        .tag(SidebarSection.speech)
                    Label(SidebarSection.ocr.title, systemImage: SidebarSection.ocr.symbol)
                        .tag(SidebarSection.ocr)
                }
                Section("Model") {
                    Label(SidebarSection.llm.title, systemImage: SidebarSection.llm.symbol)
                        .tag(SidebarSection.llm)
                }
                Section("Shortcut") {
                    Label(SidebarSection.fnShortcut.title, systemImage: SidebarSection.fnShortcut.symbol)
                        .tag(SidebarSection.fnShortcut)
                }
                Section("System") {
                    Label(SidebarSection.settings.title, systemImage: SidebarSection.settings.symbol)
                        .tag(SidebarSection.settings)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Text("RLeon")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(RLeonTheme.accent)
                }
            }
        } detail: {
            Group {
                switch sidebarSelection {
                case .home:
                    homeView
                case .speech:
                    speechTab
                case .ocr:
                    ocrTab
                case .llm:
                    llmColumn
                case .fnShortcut:
                    fnPushToTalkStatusTab
                case .settings:
                    settingsTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(20)
        }
        .task {
            await speech.requestAuthorization()
        }
        .onAppear {
            axTrusted = FocusedTextInsertion.isAccessibilityTrusted()
            toolStore.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            axTrusted = FocusedTextInsertion.isAccessibilityTrusted()
            toolStore.refresh()
        }
    }

    private var homeView: some View {
        VStack(alignment: .leading, spacing: 20) {
            RLeonSectionHeader("RLeon", subtitle: "On-device speech, OCR, and Ollama in one window.")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                homeCard(title: "Speech", subtitle: "On-device dictation (English-focused)", icon: "mic.fill", section: .speech)
                homeCard(title: "OCR", subtitle: "Text from images with Vision", icon: "text.viewfinder", section: .ocr)
                homeCard(title: "LLM", subtitle: "Ollama + selectable tools", icon: "cpu", section: .llm)
                homeCard(title: "FN", subtitle: "Push-to-talk and dictation", icon: "command", section: .fnShortcut)
            }
        }
    }

    private func homeCard(title: String, subtitle: String, icon: String, section: SidebarSection) -> some View {
        Button {
            sidebarSelection = section
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(RLeonTheme.accent)
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .rleonCard()
        }
        .buttonStyle(.plain)
    }

    private var llmColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                RLeonSectionHeader("Local tools", subtitle: "Quick enable/disable. Full editor: Settings → Local tools.")
                toolTogglesGrid
                OllamaChatView(speechTranscript: speech.transcript, ocrText: ocrText)
            }
        }
    }

    private var toolTogglesGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Enable all") { toolStore.enableAll() }
                    .controlSize(.small)
                Button("Disable all") { toolStore.disableAll() }
                    .controlSize(.small)
                Spacer()
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                ForEach(toolStore.orderedIds, id: \.self) { id in
                    Toggle(isOn: Binding(
                        get: { toolStore.isOn(id) },
                        set: { toolStore.setOn(id, $0) }
                    )) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: RLeonToolLabel.symbol(id))
                                .foregroundStyle(RLeonTheme.accent)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(RLeonToolLabel.title(id))
                                    .font(.subheadline.weight(.medium))
                                Text(RLeonToolLabel.subtitle(id))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .rleonCard()
    }

    private var settingsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RLeonSectionHeader("Settings", subtitle: "Tools, permissions, and version.")
                ToolsSettingsSection(toolStore: toolStore)
                DangerousToolsSettingsSection()
                accessibilityTrustBanner
                Text("RLeon version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var accessibilityTrustBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: axTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(axTrusted ? .green : .orange)
                Text(axTrusted ? "Accessibility (AX): granted" : "Accessibility (AX): not granted")
                    .font(.subheadline)
                Spacer(minLength: 8)
                Button("Open Settings") { FocusedTextInsertion.openAccessibilitySettings() }
                    .controlSize(.small)
                Button("Refresh") {
                    axTrusted = FocusedTextInsertion.isAccessibilityTrusted()
                }
                .controlSize(.small)
            }
            Text(FocusedTextInsertion.bundlePathForDiagnostics())
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rleonCard()
    }

    private var speechTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RLeonSectionHeader("Speech", subtitle: "Fully on-device; no network.")
                Group {
                    switch speech.authStatus {
                    case .authorized:
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Permission granted", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            if speech.supportsOnDeviceRecognition {
                                Label("On-device model ready", systemImage: "cpu")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            } else {
                                Label("No on-device model for this language", systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .font(.caption)
                            }
                        }
                    case .denied, .restricted:
                        Label("Denied — System Settings → Privacy", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    case .notDetermined:
                        Label("Permission not determined", systemImage: "questionmark.circle")
                    @unknown default:
                        EmptyView()
                    }
                }
                if let err = speech.errorMessage {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
                HStack {
                    Button(speech.isListening ? "Stop" : "Listen") {
                        if speech.isListening { speech.stop() } else { speech.start() }
                    }
                    .keyboardShortcut(.defaultAction)
                    Button("Request permission") { Task { await speech.requestAuthorization() } }
                }
                Text("Text")
                    .font(.subheadline.weight(.semibold))
                ScrollView {
                    Text(speech.transcript.isEmpty ? "…" : speech.transcript)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 200)
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var fnPushToTalkStatusTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RLeonSectionHeader("FN", subtitle: "Short tap → dictation only; hold ~0.25s → OCR + LLM.")
                LabeledContent("State", value: fnCoordinator.phase.rawValue)
                if fnCoordinator.isMonitoring {
                    Label("Key monitoring on", systemImage: "keyboard")
                        .foregroundStyle(.green)
                }
                if let err = fnCoordinator.lastError {
                    Text(err).font(.caption).foregroundStyle(.orange)
                }
                if let d = fnCoordinator.lastDictationOnlyTranscript, !d.isEmpty {
                    Text("Last dictation")
                        .font(.subheadline.weight(.semibold))
                    if let fm = fnCoordinator.lastDictationFocusMessage {
                        Text(FocusedTextInsertion.localizedUserMessage(for: fm))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("Code: \(fm)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Text(d)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(10)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                }
                if let reply = fnCoordinator.lastOllamaReply, !reply.isEmpty {
                    Text("Last LLM reply")
                        .font(.subheadline.weight(.semibold))
                    ScrollView {
                        Text(reply)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 160)
                    .padding(10)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var ocrTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RLeonSectionHeader("Image OCR", subtitle: "Vision — on-device.")
                HStack {
                    Button("Choose image") { pickImageForOcr() }
                    Button("From clipboard") { pasteImageFromClipboard() }
                        .keyboardShortcut("v", modifiers: [.command, .shift])
                }
                if isOcrBusy { ProgressView().controlSize(.small) }
                if let ocrError {
                    Text(ocrError).font(.caption).foregroundStyle(.red)
                }
                Text("Recognized text")
                    .font(.subheadline.weight(.semibold))
                ScrollView {
                    Text(ocrText.isEmpty ? "Choose an image or use the clipboard." : ocrText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 240)
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func pickImageForOcr() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .png, .jpeg, .tiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let image = NSImage(contentsOf: url) else {
            ocrError = "Could not load image."
            return
        }
        runOcr(on: image)
    }

    private func pasteImageFromClipboard() {
        guard let image = imageFromPasteboard() else {
            ocrError = "No suitable image on the pasteboard."
            return
        }
        runOcr(on: image)
    }

    private func imageFromPasteboard() -> NSImage? {
        let pb = NSPasteboard.general
        if let image = NSImage(pasteboard: pb), image.size.width > 0, image.size.height > 0 { return image }
        if let data = pb.data(forType: .tiff), let image = NSImage(data: data) { return image }
        if let data = pb.data(forType: .png), let image = NSImage(data: data) { return image }
        if let data = pb.data(forType: NSPasteboard.PasteboardType("public.jpeg")), let image = NSImage(data: data) { return image }
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let url = urls.first,
           let image = NSImage(contentsOf: url) { return image }
        return nil
    }

    private func runOcr(on image: NSImage) {
        ocrError = nil
        isOcrBusy = true
        ocrText = ""
        Task {
            defer { isOcrBusy = false }
            do {
                ocrText = try VisionOCR.recognizeText(from: image)
            } catch {
                ocrError = error.localizedDescription
            }
        }
    }
}

#Preview {
    let app = AppState()
    ContentView()
        .environmentObject(app.speech)
        .environmentObject(app.fnCoordinator)
        .environmentObject(app.toolSelection)
}
