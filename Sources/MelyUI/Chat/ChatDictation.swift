import Foundation
import AVFoundation
import Speech
import Observation

/// Dictation into the chat field: the microphone through Speech, on the device when
/// the language supports it. Asks for the microphone and speech recognition on first use.
@MainActor
@Observable
public final class ChatDictation {
    public private(set) var isRecording = false
    /// The field's text plus what has been heard so far.
    public private(set) var text = ""
    public private(set) var error: String?

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var prefix = ""

    public init() {}

    /// Starts listening; what is heard is appended to `existing`.
    public func start(from existing: String) async {
        error = nil
        guard await Self.authorized() else {
            error = "Нужен доступ к микрофону и распознаванию речи (Системные настройки → Конфиденциальность)"
            return
        }
        let locale = Locale(identifier: Locale.preferredLanguages.first?.hasPrefix("en") == true ? "en-US" : "ru-RU")
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            error = "Распознавание речи сейчас недоступно"
            return
        }
        prefix = existing.isEmpty || existing.hasSuffix(" ") ? existing : existing + " "
        text = existing
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request
        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            request.append(buffer)
        }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            self.error = "Микрофон не запустился"
            return
        }
        isRecording = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, failure in
            let heard = result?.bestTranscription.formattedString
            let final = result?.isFinal == true || failure != nil
            Task { @MainActor in
                guard let self else { return }
                if let heard { self.text = self.prefix + heard }
                if final { self.stopAudio() }
            }
        }
    }

    /// Stops listening and returns the final text.
    @discardableResult
    public func finish() async -> String {
        request?.endAudio()
        // Give the recognizer a moment to settle the last words.
        try? await Task.sleep(for: .milliseconds(350))
        stopAudio()
        return text
    }

    private func stopAudio() {
        guard isRecording else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        task?.cancel()
        task = nil
        request = nil
        isRecording = false
    }

    private static func authorized() async -> Bool {
        let speech = await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { done.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVCaptureDevice.requestAccess(for: .audio)
    }
}
