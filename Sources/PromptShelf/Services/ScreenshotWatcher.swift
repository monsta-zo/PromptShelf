import AppKit
import Foundation

/// 스크린샷 저장 폴더를 감시해서 새 .png 파일이 생기면 셸프에 추가합니다.
/// 별도 권한 없이 동작합니다.
@MainActor
final class ScreenshotWatcher {

    static let shared = ScreenshotWatcher()

    private var watchSource: DispatchSourceFileSystemObject?
    private var folderFD: Int32 = -1
    private var seenFiles: Set<String> = []
    private var isRunning = false

    private init() {}

    // MARK: - Session

    func startSession() {
        guard !isRunning else { return }
        isRunning = true
        seenFiles = []

        // 현재 폴더에 있는 파일들을 "이미 존재"로 마킹 (세션 시작 전 파일 무시)
        let folder = screenshotFolder
        if let existing = try? FileManager.default.contentsOfDirectory(atPath: folder) {
            for name in existing where name.hasSuffix(".png") || name.hasSuffix(".jpg") {
                seenFiles.insert((folder as NSString).appendingPathComponent(name))
            }
        }

        startWatching(folder)
    }

    func stopSession() {
        isRunning = false
        stopWatching()
    }

    // MARK: - Folder

    /// 스크린샷 저장 위치 (시스템 설정에서 바꿀 수 있음)
    private var screenshotFolder: String {
        let custom = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location")
        let expanded = (custom ?? "~/Desktop").replacingOccurrences(of: "~", with: NSHomeDirectory())
        return expanded
    }

    // MARK: - DispatchSource File Watcher

    private func startWatching(_ path: String) {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            print("⚠️ ScreenshotWatcher: 폴더 열기 실패 — \(path)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,   // 디렉토리 write = 파일 추가/삭제
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.handleFolderChange()
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        watchSource = source
        folderFD = fd

        print("✅ ScreenshotWatcher 시작: \(path)")
    }

    private func stopWatching() {
        watchSource?.cancel()
        watchSource = nil
        folderFD = -1
        print("🛑 ScreenshotWatcher 중지")
    }

    // MARK: - New File Detection

    private func handleFolderChange() {
        let folder = screenshotFolder
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: folder) else { return }

        let now = Date()

        for name in files {
            guard name.hasSuffix(".png") || name.hasSuffix(".jpg") else { continue }

            let fullPath = (folder as NSString).appendingPathComponent(name)
            guard !seenFiles.contains(fullPath) else { continue }

            // 파일 생성 시각이 5초 이내인 경우만 (오래된 파일 무시)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: fullPath),
               let created = attrs[.creationDate] as? Date,
               now.timeIntervalSince(created) < 5.0 {

                seenFiles.insert(fullPath)
                loadAndAdd(path: fullPath)
            } else {
                // 오래된 파일도 seen에 추가해서 이후에 또 감지하지 않도록
                seenFiles.insert(fullPath)
            }
        }
    }

    private func loadAndAdd(path: String, retryCount: Int = 0) {
        guard isRunning else { return }

        if let image = NSImage(contentsOfFile: path) {
            print("📸 스크린샷 캡처: \(path)")

            let speech = AppCore.shared.speech
            if speech.isListening {
                let spoken = speech.flushCurrentChunk()
                if !spoken.isEmpty {
                    PromptSession.shared.addChunk(spoken)
                }
            }

            PromptSession.shared.addImageChunk(image)
        } else if retryCount < 5 {
            // 파일이 아직 준비 안 된 경우 0.1초 후 재시도
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.loadAndAdd(path: path, retryCount: retryCount + 1)
            }
        } else {
            print("⚠️ ScreenshotWatcher: 이미지 로드 실패 — \(path)")
        }
    }
}
