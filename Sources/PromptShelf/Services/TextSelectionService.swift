import AppKit

@MainActor
final class TextSelectionService {

    static let shared = TextSelectionService()

    private var pollTimer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var lastCapturedText: String = ""

    private init() {}

    // MARK: - Session

    func startSession() {
        lastChangeCount = NSPasteboard.general.changeCount
        lastCapturedText = ""

        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            Task { @MainActor in
                TextSelectionService.shared.checkClipboard()
            }
        }
    }

    func stopSession() {
        pollTimer?.invalidate()
        pollTimer = nil
        lastCapturedText = ""
    }

    // MARK: - Clipboard

    private func checkClipboard() {
        let current = NSPasteboard.general.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current
        captureCurrentClipboard()
    }

    private func captureCurrentClipboard() {
        let pb = NSPasteboard.general

        // 1) 이미지 우선 체크 (TIFF → PNG 순)
        if let image = imageFromPasteboard(pb) {
            flushSpeechIfNeeded()
            PromptSession.shared.addImageChunk(image)
                return
        }

        // 2) 텍스트
        guard let text = pb.string(forType: .string) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 1, trimmed != lastCapturedText else { return }

        lastCapturedText = trimmed
        flushSpeechIfNeeded()
        PromptSession.shared.addChunk(trimmed)
    }

    private func imageFromPasteboard(_ pb: NSPasteboard) -> NSImage? {
        // TIFF (대부분의 macOS 복사)
        if let data = pb.data(forType: .tiff), let img = NSImage(data: data) {
            return img
        }
        // PNG (웹 브라우저 등)
        if let data = pb.data(forType: .png), let img = NSImage(data: data) {
            return img
        }
        return nil
    }

    private func flushSpeechIfNeeded() {
        let speech = AppCore.shared.speech
        if speech.isListening {
            let spoken = speech.flushCurrentChunk()
            if !spoken.isEmpty {
                PromptSession.shared.addChunk(spoken)
            }
        }
    }
}
