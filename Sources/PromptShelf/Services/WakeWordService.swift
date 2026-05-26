import Foundation
import Speech
import AVFoundation
import AppKit

/// 웨이크워드 감지 서비스
///
/// 설계 원칙:
/// - 오디오 탭을 항상 열어두고, 인식 요청도 항상 활성 상태 유지
/// - 말하기 시작할 때 이미 버퍼가 인식기에 들어가고 있으므로 "자비" 유실 없음
/// - 세션 오류·타임아웃 시 즉시 새 세션으로 자동 교체 (Apple 서버 한도 회피)
@MainActor
final class WakeWordService: ObservableObject {

    // MARK: - State

    enum State: Equatable {
        case stopped
        case waiting        // 항상 인식 중, 웨이크워드 기다리는 중
        case triggered      // 웨이크워드 감지됨, SpeechService 핸드오프 직전
        case error(String)
    }

    @Published var state: State = .stopped
    var isRunning: Bool { state == .waiting || state == .triggered }

    // MARK: - Config

    var wakeWords: [String] = ["context"] {
        didSet { wakeWordSet = Set(wakeWords.map { $0.lowercased() }) }
    }
    private var wakeWordSet: Set<String> = ["context"]

    // Apple 서버 세션 한도를 피해 주기적으로 세션 교체 (초)
    private let sessionRefreshInterval: TimeInterval = 25

    // MARK: - Private

    private var audioEngine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var refreshTimer: Task<Void, Never>?
    private var onDetected: (() -> Void)?
    private var isSuspended = false   // pause/resume 용

    // MARK: - Public API

    func start(wakeWords: [String]? = nil, onDetected: @escaping () -> Void) async {
        if let words = wakeWords {
            self.wakeWords = words
            self.wakeWordSet = Set(words.map { $0.lowercased() })
        }
        self.onDetected = onDetected

        guard await requestPermissions() else {
            state = .error("마이크 또는 음성 인식 권한이 필요합니다.")
            return
        }

        refreshRecognizer()
        startCycle()
    }

    func stop() {
        isSuspended = false
        teardown()
        state = .stopped
    }

    /// SpeechService 가 마이크를 써야 할 때 호출 — 오디오 엔진만 멈춤
    func pause() {
        isSuspended = true
        teardown()
        // state 는 .waiting 유지 — resume 이 재시작 판단에 사용
    }

    /// SpeechService 가 끝난 뒤 호출 — 웨이크워드 청취 재개
    func resume() {
        guard isSuspended else { return }
        isSuspended = false
        startCycle()
    }

    // MARK: - Cycle (항상-실행 인식 세션)

    private func startCycle() {
        guard !isSuspended, state != .stopped else { return }

        // 이전 세션 정리
        teardownSession()

        // 새 오디오 엔진
        audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        // 새 인식 요청 — 오디오 탭보다 먼저 만들어야 첫 버퍼부터 들어감
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false
        recognitionRequest = request

        // 탭 설치 — 모든 버퍼를 즉시 인식 요청에 공급
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            state = .error("오디오 엔진 시작 실패: \(error.localizedDescription)")
            print("❌ 오디오 엔진: \(error)")
            return
        }

        state = .waiting
        print("✅ 웨이크워드 대기 중: \(wakeWords)")

        // 인식 태스크
        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            // 결과 처리
            if let result {
                let text = result.bestTranscription.formattedString
                if !text.isEmpty { print("🎙️ \(text)") }

                if self.containsWakeWord(text) {
                    Task { @MainActor in self.handleDetection() }
                    return
                }
            }

            // 에러 또는 세션 종료 → 새 사이클로
            if let error {
                let code = (error as NSError).code
                // 1101/1700 = 정상 세션 종료, 그 외 = 실제 오류
                if code != 1101 && code != 1700 {
                    print("⚠️ 인식 에러 (코드 \(code)): \(error.localizedDescription)")
                }
            }
            if result?.isFinal == true || error != nil {
                Task { @MainActor in
                    guard self.state == .waiting && !self.isSuspended else { return }
                    print("🔄 세션 종료 → 새 사이클 시작")
                    self.startCycle()
                }
            }
        }

        // 일정 시간마다 세션 강제 교체 (Apple 서버 한도 예방)
        refreshTimer?.cancel()
        refreshTimer = Task {
            try? await Task.sleep(for: .seconds(sessionRefreshInterval))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.state == .waiting && !self.isSuspended else { return }
                print("🔄 주기적 세션 교체")
                self.startCycle()
            }
        }
    }

    // MARK: - Detection

    private func handleDetection() {
        guard state == .waiting else { return }   // 중복 방지
        state = .triggered
        print("✅ 웨이크워드 감지!")

        teardown()
        playActivationSound()
        onDetected?()
    }

    // MARK: - Teardown Helpers

    /// 세션만 종료 (오디오 엔진은 그대로)
    private func teardownSession() {
        refreshTimer?.cancel()
        refreshTimer = nil
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
    }

    /// 세션 + 오디오 엔진 모두 종료
    private func teardown() {
        teardownSession()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
    }

    // MARK: - Recognizer Setup

    private func refreshRecognizer() {
        if let kr = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR")), kr.isAvailable {
            recognizer = kr
            print("🗣️ 한국어 인식기")
        } else if let en = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), en.isAvailable {
            recognizer = en
            print("🗣️ 영어 인식기 (한국어 불가)")
        } else {
            print("⚠️ 인식기 없음 — 잠시 후 재시도")
        }
    }

    // MARK: - Wake Word Match

    private func containsWakeWord(_ text: String) -> Bool {
        let lower = text.lowercased()
        return wakeWordSet.contains { lower.contains($0) }
    }

    // MARK: - Sound Feedback

    func playActivationSound() { NSSound(named: "Tink")?.play() }
    func playDoneSound()       { NSSound(named: "Pop")?.play()  }

    // MARK: - Permissions

    private func requestPermissions() async -> Bool {
        let mic = await withCheckedContinuation { cont in
            AVCaptureDevice.requestAccess(for: .audio) { cont.resume(returning: $0) }
        }
        guard mic else { return false }
        return await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
    }
}
