import AppKit
import Foundation

/// Watches the screenshot save folder and adds any new image to the shelf.
/// Works without additional permissions.
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

        // Mark all existing files as already seen so pre-session screenshots are ignored
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

    /// Resolves the screenshot save location from System Settings (defaults to ~/Desktop).
    private var screenshotFolder: String {
        let custom = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location")
        let expanded = (custom ?? "~/Desktop").replacingOccurrences(of: "~", with: NSHomeDirectory())
        return expanded
    }

    // MARK: - File Watcher

    private func startWatching(_ path: String) {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,  // directory write = file added or removed
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
    }

    private func stopWatching() {
        watchSource?.cancel()
        watchSource = nil
        folderFD = -1
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

            // Only accept files created within the last 5 seconds (ignore pre-existing files)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: fullPath),
               let created = attrs[.creationDate] as? Date,
               now.timeIntervalSince(created) < 5.0 {

                seenFiles.insert(fullPath)
                loadAndAdd(path: fullPath)
            } else {
                seenFiles.insert(fullPath)
            }
        }
    }

    private func loadAndAdd(path: String, retryCount: Int = 0) {
        guard isRunning else { return }

        if let image = NSImage(contentsOfFile: path) {
            let speech = AppCore.shared.speech
            if speech.isListening {
                let spoken = speech.flushCurrentChunk()
                if !spoken.isEmpty {
                    PromptSession.shared.addChunk(spoken)
                }
            }
            PromptSession.shared.addImageChunk(image)
        } else if retryCount < 5 {
            // File not fully written yet — retry in 100ms
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.loadAndAdd(path: path, retryCount: retryCount + 1)
            }
        }
    }
}
