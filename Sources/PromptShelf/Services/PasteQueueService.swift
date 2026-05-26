import AppKit
import Carbon
import CoreGraphics
import os.log

private let pqLogger = Logger(subsystem: "com.promptshelf.app", category: "PasteQueue")

/// ⌘V를 감지해 세션을 종료하고 모든 청크를 순서대로 자동 붙여넣기합니다.
@MainActor
final class PasteQueueService {

    static let shared = PasteQueueService()

    nonisolated(unsafe) static var _instance: PasteQueueService?
    nonisolated(unsafe) static var _sessionWatching = false  // 세션 중 ⌘V 감시
    nonisolated(unsafe) static var _isPasting       = false  // 순차 붙여넣기 진행 중

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private init() {
        PasteQueueService._instance = self
    }

    // MARK: - Session Watching

    /// 세션 시작 시 호출 — ⌘V를 감시하기 시작
    func startWatching() {
        PasteQueueService._sessionWatching = true
        PasteQueueService._isPasting = false
        startEventTap()
        pqLogger.info("👀 PasteQueue: 세션 감시 시작")
    }

    /// 세션 취소 시 호출 (⌃+⌥ 두 번째 → 붙여넣기 없이 종료)
    func stopWatching() {
        PasteQueueService._sessionWatching = false
        PasteQueueService._isPasting = false
        stopEventTap()
        pqLogger.info("🛑 PasteQueue: 감시 중지")
    }

    // MARK: - ⌘V detected during session

    /// C 콜백에서 세션 중 ⌘V 감지 시 호출
    func handleSessionPaste() {
        PasteQueueService._sessionWatching = false
        stopEventTap()

        let core = AppCore.shared

        // 말하던 중이면 현재 음성 청크 즉시 저장
        if core.speech.isListening {
            let spoken = core.speech.flushCurrentChunk()
            if !spoken.isEmpty {
                PromptSession.shared.addChunk(spoken)
            }
        }

        // 서비스 중지
        TextSelectionService.shared.stopSession()
        ScreenshotWatcher.shared.stopSession()
        core.speech.stop { _ in }  // 녹음 중지 (이미 flush했으므로 콜백 불필요)

        // 청크 수집
        let chunks = PromptSession.shared.chunks
        guard !chunks.isEmpty else {
            pqLogger.info("⚠️ 청크 없음 — 붙여넣기 스킵")
            PromptSession.shared.clear()
            SidePanelController.shared.hide()
            return
        }

        // 히스토리 저장
        let prompt = PromptSession.shared.fullPrompt
        if !prompt.isEmpty { AppCore.shared.history.add(prompt) }

        // 세션 정리
        PromptSession.shared.clear()
        SidePanelController.shared.hide()

        // 순차 붙여넣기 시작
        pqLogger.info("🚀 순차 붙여넣기 시작: \(chunks.count)개")
        PasteQueueService._isPasting = true
        startEventTap()  // 시뮬레이션된 ⌘V를 통과시키기 위해 재시작

        Task { @MainActor in
            await self.pasteChunks(chunks)
        }
    }

    // MARK: - Sequential Paste

    private func pasteChunks(_ chunks: [PromptChunk]) async {
        let isTerminal = isFrontmostAppTerminal()
        pqLogger.info("🖥️ 대상 앱: \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"), 터미널: \(isTerminal)")

        // 모든 청크 사이에 줄바꿈 청크 삽입 (text↔text, text↔image, image↔image 모두)
        var sequence: [PromptChunk] = []
        for (i, chunk) in chunks.enumerated() {
            sequence.append(chunk)
            if i < chunks.count - 1 {
                sequence.append(.text("\n"))
            }
        }

        for (i, chunk) in sequence.enumerated() {
            setClipboard(chunk)
            try? await Task.sleep(nanoseconds: 30_000_000)  // 30ms — 클립보드 반영 대기

            // 터미널 + 이미지: ⌃V (Claude Code가 직접 클립보드 읽음, 한글 IME 우회 포함)
            // 그 외 모든 경우: ⌘V
            if isTerminal, case .image = chunk {
                simulateCtrlV()
                pqLogger.info("  📎 이미지 → ⌃V (터미널 우회)")
            } else {
                simulateCmdV()
            }

            // 마지막 청크 포함 모두 대기 — 탭을 끄기 전에 이벤트가 처리되도록
            let delay: UInt64 = {
                if case .image = chunk { return 300_000_000 }  // 이미지 후 300ms (⌃V 처리 여유)
                return 100_000_000  // 텍스트/줄바꿈 후 100ms
            }()
            try? await Task.sleep(nanoseconds: delay)

            pqLogger.info("  ✅ 청크 \(i + 1)/\(sequence.count)")
        }

        PasteQueueService._isPasting = false
        stopEventTap()
        NSSound(named: "Pop")?.play()
        pqLogger.info("🎉 붙여넣기 완료")
    }

    // MARK: - Terminal Detection

    /// 현재 포커스된 앱이 터미널 에뮬레이터인지 확인
    private func isFrontmostAppTerminal() -> Bool {
        let terminalBundleIDs: Set<String> = [
            "com.googlecode.iterm2",       // iTerm2
            "com.apple.Terminal",          // macOS 기본 터미널
            "com.microsoft.VSCode",        // VS Code 통합 터미널
            "com.microsoft.VSCodeInsiders",
            "com.todesktop.230313mzl4w4u92", // Cursor
            "dev.warp.Warp-Stable",        // Warp
            "com.github.wez.wezterm",      // WezTerm
            "net.kovidgoyal.kitty",        // Kitty
            "co.zeit.hyper",               // Hyper
        ]
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        return terminalBundleIDs.contains(bundleID)
    }

    // MARK: - Clipboard

    private func setClipboard(_ chunk: PromptChunk) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch chunk {
        case .text(let t):
            pb.setString(t, forType: .string)
        case .image(let img):
            pb.writeObjects([img])
        case .file(let url, _):
            // public.file-url → 브라우저/웹 AI가 파일 업로드로 인식
            // .string 폴백 → Claude Code / 터미널은 경로 텍스트로 인식
            pb.writeObjects([url as NSURL])
            pb.setString(url.path, forType: .string)
        }
    }

    // MARK: - Simulate Paste

    /// 일반 앱용 ⌘V
    private func simulateCmdV() {
        let src  = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9

        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        down?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)

        let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        up?.flags = .maskCommand
        up?.post(tap: .cghidEventTap)
    }

    /// 터미널 앱에서 이미지 붙여넣기용 ⌃V
    /// — 터미널 에뮬레이터가 가로채지 않고 실행 중인 프로세스(Claude Code 등)로 전달됨
    /// — 한글 IME 활성 상태일 때 ⌃V가 가로채지는 문제를 방지하기 위해 잠시 ASCII 소스로 전환
    private func simulateCtrlV() {
        // 현재 입력 소스 저장
        let originalSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()

        // ASCII 지원 입력 소스(ABC, U.S. 등)로 전환 — 한글 IME 우회
        let filter = [kTISPropertyInputSourceIsASCIICapable: true] as CFDictionary
        if let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
           let asciiSource = list.first {
            TISSelectInputSource(asciiSource)
        }

        let src  = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9

        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        down?.flags = .maskControl
        down?.post(tap: .cghidEventTap)

        let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        up?.flags = .maskControl
        up?.post(tap: .cghidEventTap)

        // 이벤트 처리 후 원래 입력 소스 복구 (150ms 대기 — 붙여넣기 처리 완료 후)
        if let original = originalSource {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                TISSelectInputSource(original)
            }
        }
    }

    // MARK: - CGEventTap

    private func startEventTap() {
        stopEventTap()

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, _ -> Unmanaged<CGEvent>? in
                guard type == .keyDown else { return Unmanaged.passRetained(event) }

                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags   = event.flags

                // 세션 중 Cmd+Shift+3/4 → Ctrl+Cmd+Shift+3/4(클립보드)로 교체
                // 파일 저장 없이 즉시 클립보드로 캡처
                if PasteQueueService._sessionWatching,
                   (keyCode == 20 || keyCode == 21),   // 3 or 4
                   flags.contains(.maskCommand),
                   flags.contains(.maskShift),
                   !flags.contains(.maskControl) {      // Ctrl 없는 원본만 가로챔

                    let capturedKeyCode = CGKeyCode(keyCode)
                    DispatchQueue.main.async {
                        let src = CGEventSource(stateID: .combinedSessionState)
                        let down = CGEvent(keyboardEventSource: src, virtualKey: capturedKeyCode, keyDown: true)
                        down?.flags = [.maskCommand, .maskShift, .maskControl]  // Ctrl 추가
                        down?.post(tap: .cghidEventTap)

                        let up = CGEvent(keyboardEventSource: src, virtualKey: capturedKeyCode, keyDown: false)
                        up?.flags = [.maskCommand, .maskShift, .maskControl]
                        up?.post(tap: .cghidEventTap)
                    }
                    return nil  // 원본(파일저장) 억제
                }

                guard keyCode == 9 else { return Unmanaged.passRetained(event) }  // V키만 처리

                let isCmdV  = flags.contains(.maskCommand) && !flags.contains(.maskControl)
                                  && !flags.contains(.maskShift) && !flags.contains(.maskAlternate)
                let isCtrlV = flags.contains(.maskControl) && !flags.contains(.maskCommand)
                                  && !flags.contains(.maskShift) && !flags.contains(.maskAlternate)

                // 우리가 시뮬레이션한 ⌘V / ⌃V → 통과
                if PasteQueueService._isPasting, (isCmdV || isCtrlV) {
                    return Unmanaged.passRetained(event)
                }

                // 세션 중 유저의 ⌘V → 세션 종료 + 순차 붙여넣기
                if PasteQueueService._sessionWatching, isCmdV {
                    Task { @MainActor in
                        PasteQueueService._instance?.handleSessionPaste()
                    }
                    return nil  // 원본 ⌘V 억제
                }

                return Unmanaged.passRetained(event)
            },
            userInfo: nil
        )

        guard let tap else {
            pqLogger.error("❌ CGEventTap 생성 실패 — Accessibility 권한 필요")
            // 폴백: 세션 중이면 HTML 클립보드 복사 방식으로 전환
            PasteQueueService._sessionWatching = false
            Task { @MainActor in
                let chunks = PromptSession.shared.chunks
                if !chunks.isEmpty {
                    PromptSession.copyToClipboard(chunks: chunks)
                    NSSound(named: "Pop")?.play()
                }
            }
            return
        }

        CGEvent.tapEnable(tap: tap, enable: true)
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)

        eventTap      = tap
        runLoopSource = src
        pqLogger.info("✅ CGEventTap 활성")
    }

    private func stopEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let src = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            }
        }
        eventTap      = nil
        runLoopSource = nil
    }
}
