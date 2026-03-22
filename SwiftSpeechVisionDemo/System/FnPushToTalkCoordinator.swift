import AppKit
import SwiftUI

/// FN: kısa dokunuş → “sadece diktasyon” modunu silahlar; ardından basılı tutunca Ollama’ya gitmeden metin üretir.
/// Uzun basılı tutma (~250 ms) → konuşma + OCR → bırakınca Ollama (önceki davranış).
@MainActor
final class FnPushToTalkCoordinator: ObservableObject {
    enum Phase: String {
        case idle
        case recording
        case sending
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var lastError: String?
    @Published private(set) var lastOllamaReply: String?
    /// Sadece diktasyon (FN kısa dokunuş + sonra basılı tut) sonucu; Ollama’ya gönderilmez.
    @Published private(set) var lastDictationOnlyTranscript: String?
    /// Diktasyon metninin odaklı uygulamaya yazılması denemesinin özeti (başarı / hata).
    @Published private(set) var lastDictationFocusMessage: String?
    @Published private(set) var isMonitoring = false

    private let speech: SpeechTranscriber
    private var globalMonitor: Any?
    private var localMonitor: Any?

    private var ocrTask: Task<String, Error>?
    private var deferredSpeechStart: Task<Void, Never>?
    private var fnLogicalDown = false

    private var fnDownAt: Date?
    private var holdToFullTask: Task<Void, Never>?
    private var armedDictationOnly = false
    private var armExpiry: Date?

    private enum ActiveRecordingKind {
        case full
        case dictationOnly
    }

    private var activeRecording: ActiveRecordingKind?

    private static let fnKeyCode: UInt16 = 63
    private static let fullHoldThresholdNs: UInt64 = 250_000_000
    private static let armLifetimeSeconds: TimeInterval = 120

    init(speech: SpeechTranscriber) {
        self.speech = speech
    }

    func startMonitoring() {
        guard globalMonitor == nil else { return }

        let masks: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: masks) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: masks) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
            return event
        }

        isMonitoring = globalMonitor != nil || localMonitor != nil
        if globalMonitor == nil {
            lastError = "Global FN monitoring unavailable: enable this app under Privacy → Accessibility (FN only works as expected when the app is in the foreground)."
        }
    }

    func stopMonitoring() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        isMonitoring = false
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            if event.keyCode == Self.fnKeyCode, !event.isARepeat {
                handleFnDown()
            }
        case .keyUp:
            if event.keyCode == Self.fnKeyCode {
                handleFnUp()
            }
        case .flagsChanged:
            let fn = event.modifierFlags.contains(.function)
            if fn, !fnLogicalDown {
                handleFnDown()
            } else if !fn, fnLogicalDown {
                handleFnUp()
            }
        default:
            break
        }
    }

    private func handleFnDown() {
        if phase == .sending { return }
        if activeRecording != nil { return }

        if armedDictationOnly, armExpiry == nil || Date() < armExpiry! {
            beginDictationOnlyRecording()
            armedDictationOnly = false
            armExpiry = nil
            return
        }

        guard !fnLogicalDown else { return }
        fnLogicalDown = true
        lastError = nil
        fnDownAt = Date()
        holdToFullTask?.cancel()
        holdToFullTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.fullHoldThresholdNs)
            await MainActor.run {
                guard self.fnLogicalDown, self.activeRecording == nil else { return }
                self.beginFullRecording()
            }
        }
    }

    private func beginDictationOnlyRecording() {
        activeRecording = .dictationOnly
        fnLogicalDown = true
        lastError = nil
        phase = .recording
        deferredSpeechStart?.cancel()
        speech.clearTranscriptForCancelledPushToTalk()
        ocrTask = nil
        holdToFullTask?.cancel()
        holdToFullTask = nil
        deferredSpeechStart = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            speech.startForPushToTalk()
        }
    }

    private func beginFullRecording() {
        activeRecording = .full
        lastError = nil
        phase = .recording
        deferredSpeechStart?.cancel()
        speech.clearTranscriptForCancelledPushToTalk()

        ocrTask = Task.detached(priority: .userInitiated) {
            guard let cgImage = MainDisplayCapture.captureMainDisplayCGImage() else {
                throw NSError(domain: "FnPTT", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not capture screen."])
            }
            return try VisionOCR.recognizeText(from: cgImage)
        }

        deferredSpeechStart = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            speech.startForPushToTalk()
        }
    }

    private func handleFnUp() {
        if activeRecording == .dictationOnly {
            guard fnLogicalDown else { return }
            fnLogicalDown = false
            fnDownAt = nil
            holdToFullTask?.cancel()
            holdToFullTask = nil
            phase = .sending
            deferredSpeechStart?.cancel()
            deferredSpeechStart = nil
            Task {
                await speech.stopPushToTalkAwaitFinal()
                await Task.yield()
                try? await Task.sleep(nanoseconds: 120_000_000)
                let t = speech.transcript
                let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
                let focusMsg: String?
                if trimmed.isEmpty {
                    focusMsg = nil
                } else if FocusedTextInsertion.isAccessibilityTrusted() {
                    focusMsg = await MainActor.run {
                        FocusedTextInsertion.insertText(t)
                    }
                } else {
                    focusMsg = "AX_NOT_TRUSTED"
                }
                await MainActor.run {
                    self.lastDictationOnlyTranscript = t
                    self.lastDictationFocusMessage = focusMsg
                    self.activeRecording = nil
                    self.phase = .idle
                }
            }
            ocrTask = nil
            return
        }

        if activeRecording == .full {
            guard fnLogicalDown else { return }
            fnLogicalDown = false
            fnDownAt = nil
            holdToFullTask?.cancel()
            holdToFullTask = nil
            phase = .sending
            deferredSpeechStart?.cancel()
            deferredSpeechStart = nil
            Task {
                await speech.stopPushToTalkAwaitFinal()
                let transcript = speech.transcript
                await sendToOllama(speechText: transcript, ocrTask: ocrTask)
                ocrTask = nil
            }
            return
        }

        holdToFullTask?.cancel()
        holdToFullTask = nil

        guard fnLogicalDown else { return }
        fnLogicalDown = false
        let elapsed = Date().timeIntervalSince(fnDownAt ?? Date())
        fnDownAt = nil

        if elapsed < 0.25 {
            armedDictationOnly = true
            armExpiry = Date().addingTimeInterval(Self.armLifetimeSeconds)
        }
    }

    private func sendToOllama(speechText: String, ocrTask: Task<String, Error>?) async {
        defer {
            phase = .idle
            activeRecording = nil
        }

        let ocr: String
        if let ocrTask {
            do {
                ocr = try await ocrTask.value
            } catch {
                lastError = "OCR: \(error.localizedDescription)"
                return
            }
        } else {
            ocr = ""
        }

        let defaults = UserDefaults.standard
        let base = defaults.string(forKey: "ollamaBaseURL") ?? "http://127.0.0.1:11434"
        let model = defaults.string(forKey: "ollamaModel") ?? "qwen2.5:7b"
        let useTools = defaults.bool(forKey: "ollamaUseTools")

        guard let url = URL(string: base), url.scheme == "http" || url.scheme == "https" else {
            lastError = "Invalid Ollama URL."
            return
        }

        var parts: [String] = []
        if !speechText.isEmpty {
            parts.append("[Speech]\n\(speechText)")
        }
        if !ocr.isEmpty {
            parts.append("[Screen OCR]\n\(ocr)")
        }
        let userContent = parts.isEmpty
            ? "(Empty: no speech or screen OCR content.)"
            : parts.joined(separator: "\n\n")

        let system = """
        The user held the FN key while speaking; the screen was captured and converted to text. \
        Below are [Speech] and [Screen OCR] blocks. Follow the user’s spoken instructions; \
        use the screen text as context. Reply in English.
        """

        do {
            let m = model.trimmingCharacters(in: .whitespacesAndNewlines)
            let reply: String
            if useTools {
                reply = try await OllamaToolCalling.chatWithLocalTools(
                    baseURL: url,
                    model: m,
                    systemPrompt: system,
                    userContent: userContent
                )
            } else {
                reply = try await OllamaClient.chat(
                    baseURL: url,
                    model: m,
                    systemPrompt: system,
                    userContent: userContent
                )
            }
            lastOllamaReply = reply
        } catch {
            lastError = "Ollama: \(error.localizedDescription)"
        }
    }
}
