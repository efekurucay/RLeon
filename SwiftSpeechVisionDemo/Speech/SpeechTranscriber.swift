import AVFoundation
import Foundation
import Speech

@MainActor
final class SpeechTranscriber: ObservableObject {
    @Published private(set) var transcript: String = ""
    @Published private(set) var isListening = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var authStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    /// Sunucu yok: yalnızca cihaz üzeri model (dil desteklenmiyorsa `start` başlamaz).
    var supportsOnDeviceRecognition: Bool {
        (recognizer?.supportsOnDeviceRecognition ?? false) && (recognizer?.isAvailable ?? false)
    }

    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var awaitingFinalContinuation: CheckedContinuation<Void, Never>?
    private var finalTimeoutTask: Task<Void, Never>?
    private var suppressRecognitionErrors = false

    init(locale: Locale = Locale(identifier: "en-US")) {
        recognizer = SFSpeechRecognizer(locale: locale)
    }

    func refreshAuthorization() {
        authStatus = SFSpeechRecognizer.authorizationStatus()
    }

    func requestAuthorization() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            SFSpeechRecognizer.requestAuthorization { _ in
                Task { @MainActor in
                    self.refreshAuthorization()
                    continuation.resume()
                }
            }
        }
    }

    func start() {
        start(clearTranscript: true)
    }

    func start(clearTranscript: Bool) {
        if isListening {
            hardStopAudioAndSpeech()
        }

        errorMessage = nil
        suppressRecognitionErrors = false
        if clearTranscript {
            transcript = ""
        }

        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition is not available for this language."
            return
        }

        guard recognizer.supportsOnDeviceRecognition else {
            errorMessage = "On-device speech recognition is not available for this language. Check System Settings → Siri & Spotlight / Language & Region for language packs."
            return
        }

        guard authStatus == .authorized else {
            errorMessage = "Speech recognition permission was not granted."
            return
        }

        // Her oturumda reset pahalı ve ana iş parçacığını kilitleyebilir; `hardStop` / `stop` zaten sıfırlıyor.

        request = SFSpeechAudioBufferRecognitionRequest()
        guard let request else { return }
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            errorMessage = "Invalid microphone format (sample rate 0). Another app may be using the mic."
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            errorMessage = "Audio engine failed to start: \(error.localizedDescription)"
            inputNode.removeTap(onBus: 0)
            return
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.resumeAwaitingFinalIfNeeded()
                    }
                }
                if let error {
                    self.handleRecognitionError(error)
                }
            }
        }

        isListening = true
    }

    /// FN basılı tutma: transkript önceki oturumdan birikmez.
    func startForPushToTalk() {
        start(clearTranscript: true)
    }

    /// FN iptal veya `start` henüz çalışmadan bırakma: metni temiz tut.
    func clearTranscriptForCancelledPushToTalk() {
        transcript = ""
    }

    /// FN bırakıldı: önce akışı bitir, sonra motoru durdur; ardından final bekle.
    func stopPushToTalkAwaitFinal() async {
        guard isListening else {
            return
        }

        suppressRecognitionErrors = true
        finalTimeoutTask?.cancel()

        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        if audioEngine.isRunning {
            audioEngine.stop()
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            awaitingFinalContinuation = continuation
            finalTimeoutTask = Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    self.resumeAwaitingFinalIfNeeded()
                }
            }
        }

        finalTimeoutTask?.cancel()
        finalTimeoutTask = nil
        task?.cancel()
        task = nil
        request = nil
        isListening = false
        audioEngine.reset()
        suppressRecognitionErrors = false
    }

    private func handleRecognitionError(_ error: Error) {
        if suppressRecognitionErrors {
            resumeAwaitingFinalIfNeeded()
            return
        }
        let ns = error as NSError
        if ns.domain == "kAFAssistantErrorDomain" || ns.domain.contains("Assistant") {
            if [1101, 1110].contains(ns.code) {
                resumeAwaitingFinalIfNeeded()
                return
            }
        }
        if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorCancelled {
            resumeAwaitingFinalIfNeeded()
            return
        }
        errorMessage = error.localizedDescription
        resumeAwaitingFinalIfNeeded()
    }

    private func resumeAwaitingFinalIfNeeded() {
        if let c = awaitingFinalContinuation {
            awaitingFinalContinuation = nil
            c.resume()
        }
    }

    /// Arayüz “Durdur” — hızlı kesme.
    func stop() {
        suppressRecognitionErrors = true
        finalTimeoutTask?.cancel()
        finalTimeoutTask = nil
        resumeAwaitingFinalIfNeeded()

        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        task?.cancel()
        task = nil
        request = nil
        isListening = false
        audioEngine.reset()
        suppressRecognitionErrors = false
    }

    private func hardStopAudioAndSpeech() {
        suppressRecognitionErrors = true
        finalTimeoutTask?.cancel()
        finalTimeoutTask = nil
        resumeAwaitingFinalIfNeeded()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        task?.cancel()
        task = nil
        request = nil
        isListening = false
        audioEngine.reset()
        suppressRecognitionErrors = false
    }
}
