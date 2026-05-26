import Foundation
import Speech
import AVFoundation
import Combine

@MainActor
final class SpeechService: ObservableObject {

    enum State { case idle, requesting, listening, unavailable(String) }

    @Published var state: State = .idle
    @Published var liveTranscript: String = ""

    var isListening: Bool {
        if case .listening = state { return true }
        return false
    }

    // 현재 선택된 언어로 recognizer를 세션 시작 때마다 새로 생성
    private var recognizer: SFSpeechRecognizer?
    private var audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var onFinishedCallback: ((String) -> Void)?

    // Each recognition session gets a unique ID.
    // Callbacks check this to ignore stale/cancelled sessions.
    private var currentSessionID = UUID()

    // MARK: - Public API

    func start(onFinished: @escaping (String) -> Void) {
        self.onFinishedCallback = onFinished
        // 세션 시작 시 현재 선택된 언어로 recognizer 생성
        let localeID = UserDefaults.standard.string(forKey: "speechLocale") ?? "en-US"
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID))
        Task {
            await requestPermissions { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.startAudioEngine()
                    self.startRecognition()
                } else {
                    self.state = .unavailable("Microphone or speech recognition permission required.")
                }
            }
        }
    }

    func stop(onFinished: @escaping (String) -> Void) {
        let final = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)

        // Invalidate current session so its callback is ignored
        currentSessionID = UUID()

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        liveTranscript = ""
        state = .idle

        onFinished(final)
    }

    /// Saves spoken text so far as a completed chunk, then
    /// swaps the recognition session — audio engine stays on, no mic gap.
    @discardableResult
    func flushCurrentChunk() -> String {
        let text = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        liveTranscript = ""
        PromptSession.shared.liveText = ""

        if isListening {
            swapRecognition()
        }

        return text
    }

    // MARK: - Audio Engine (lives for the whole session)

    private func startAudioEngine() {
        audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            state = .listening
        } catch {
            state = .unavailable("Audio engine failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Recognition (swappable without touching audio engine)

    private func startRecognition() {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false
        recognitionRequest = request

        let sessionID = currentSessionID  // capture for this closure

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                Task { @MainActor in
                    // Ignore if this session was already replaced
                    guard self.currentSessionID == sessionID else { return }
                    self.liveTranscript = text
                    PromptSession.shared.liveText = text
                }
            }

            if result?.isFinal == true || error != nil {
                Task { @MainActor in
                    // Only auto-restart if this is still the active session
                    guard self.currentSessionID == sessionID, self.isListening else { return }
                    self.swapRecognition()
                }
            }
        }
    }

    /// Replaces the recognition session without stopping the audio engine.
    private func swapRecognition() {
        // Invalidate old session — its pending callbacks will be ignored
        currentSessionID = UUID()

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil

        startRecognition()
    }

    // MARK: - Permissions

    private func requestPermissions(completion: @escaping (Bool) -> Void) async {
        state = .requesting
        let micGranted = await withCheckedContinuation { cont in
            AVCaptureDevice.requestAccess(for: .audio) { cont.resume(returning: $0) }
        }
        guard micGranted else { completion(false); return }
        let speechGranted = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        completion(speechGranted)
    }
}
