import AppKit
import Carbon
import CoreGraphics

/// Detects ⌘V during a session, ends the session, and pastes all chunks in order.
@MainActor
final class PasteQueueService {

    static let shared = PasteQueueService()

    nonisolated(unsafe) static var _instance: PasteQueueService?
    nonisolated(unsafe) static var _sessionWatching = false  // true while watching for ⌘V
    nonisolated(unsafe) static var _isPasting       = false  // true while sequential paste is running

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private init() {
        PasteQueueService._instance = self
    }

    // MARK: - Session Watching

    /// Called when a session starts — begins watching for ⌘V.
    func startWatching() {
        PasteQueueService._sessionWatching = true
        PasteQueueService._isPasting = false
        startEventTap()
    }

    /// Called when a session is cancelled (⌃+⌥ second press — exits without pasting).
    func stopWatching() {
        PasteQueueService._sessionWatching = false
        PasteQueueService._isPasting = false
        stopEventTap()
    }

    // MARK: - ⌘V detected during session

    /// Called from the event tap callback when ⌘V is detected during an active session.
    func handleSessionPaste() {
        PasteQueueService._sessionWatching = false
        stopEventTap()

        let core = AppCore.shared

        // Flush any in-progress voice chunk before ending
        if core.speech.isListening {
            let spoken = core.speech.flushCurrentChunk()
            if !spoken.isEmpty {
                PromptSession.shared.addChunk(spoken)
            }
        }

        // Stop all session services
        TextSelectionService.shared.stopSession()
        ScreenshotWatcher.shared.stopSession()
        core.speech.stop { _ in }

        // Collect chunks
        let chunks = PromptSession.shared.chunks
        guard !chunks.isEmpty else {
            PromptSession.shared.clear()
            SidePanelController.shared.hide()
            return
        }

        // Save to history
        let prompt = PromptSession.shared.fullPrompt
        if !prompt.isEmpty { AppCore.shared.history.add(prompt) }

        // Clear session and hide panel
        PromptSession.shared.clear()
        SidePanelController.shared.hide()

        // Begin sequential paste
        PasteQueueService._isPasting = true
        startEventTap()  // Restart so simulated ⌘V events are allowed through

        Task { @MainActor in
            await self.pasteChunks(chunks)
        }
    }

    // MARK: - Sequential Paste

    private func pasteChunks(_ chunks: [PromptChunk]) async {
        let isTerminal = isFrontmostAppTerminal()

        // Insert a newline chunk between every pair of chunks
        var sequence: [PromptChunk] = []
        for (i, chunk) in chunks.enumerated() {
            sequence.append(chunk)
            if i < chunks.count - 1 {
                sequence.append(.text("\n"))
            }
        }

        for chunk in sequence {
            setClipboard(chunk)
            try? await Task.sleep(nanoseconds: 30_000_000)  // 30ms — wait for clipboard to settle

            // Terminal + image: use ⌃V so the running process (e.g. Claude Code) reads directly
            // from the clipboard, bypassing the Korean IME interception issue.
            // All other cases: use ⌘V.
            if isTerminal, case .image = chunk {
                simulateCtrlV()
            } else {
                simulateCmdV()
            }

            let delay: UInt64 = {
                if case .image = chunk { return 300_000_000 }  // 300ms after images
                return 100_000_000  // 100ms after text / newlines
            }()
            try? await Task.sleep(nanoseconds: delay)
        }

        PasteQueueService._isPasting = false
        stopEventTap()
        NSSound(named: "Pop")?.play()
    }

    // MARK: - Terminal Detection

    /// Returns true if the frontmost app is a terminal emulator.
    private func isFrontmostAppTerminal() -> Bool {
        let terminalBundleIDs: Set<String> = [
            "com.googlecode.iterm2",
            "com.apple.Terminal",
            "com.microsoft.VSCode",
            "com.microsoft.VSCodeInsiders",
            "com.todesktop.230313mzl4w4u92", // Cursor
            "dev.warp.Warp-Stable",
            "com.github.wez.wezterm",
            "net.kovidgoyal.kitty",
            "co.zeit.hyper",
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
            // public.file-url → web AI tools read this as a file upload
            // .string fallback → terminals and Claude Code read this as a path
            pb.writeObjects([url as NSURL])
            pb.setString(url.path, forType: .string)
        }
    }

    // MARK: - Simulate Paste

    /// Simulates ⌘V for standard apps.
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

    /// Simulates ⌃V for terminal apps when pasting images.
    /// Temporarily switches to an ASCII input source to bypass the Korean IME.
    private func simulateCtrlV() {
        let originalSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()

        // Switch to an ASCII-capable input source (e.g. ABC) to bypass the Korean IME
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

        // Restore original input source after paste is processed (150ms delay)
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

                // Intercept ⌘⇧3/4 during a session and redirect to ⌃⌘⇧3/4
                // so screenshots go directly to the clipboard instead of saving to disk.
                if PasteQueueService._sessionWatching,
                   (keyCode == 20 || keyCode == 21),   // 3 or 4
                   flags.contains(.maskCommand),
                   flags.contains(.maskShift),
                   !flags.contains(.maskControl) {

                    let capturedKeyCode = CGKeyCode(keyCode)
                    DispatchQueue.main.async {
                        let src = CGEventSource(stateID: .combinedSessionState)
                        let down = CGEvent(keyboardEventSource: src, virtualKey: capturedKeyCode, keyDown: true)
                        down?.flags = [.maskCommand, .maskShift, .maskControl]
                        down?.post(tap: .cghidEventTap)

                        let up = CGEvent(keyboardEventSource: src, virtualKey: capturedKeyCode, keyDown: false)
                        up?.flags = [.maskCommand, .maskShift, .maskControl]
                        up?.post(tap: .cghidEventTap)
                    }
                    return nil  // Suppress original (file-saving) event
                }

                guard keyCode == 9 else { return Unmanaged.passRetained(event) }  // V key only

                let isCmdV  = flags.contains(.maskCommand) && !flags.contains(.maskControl)
                                  && !flags.contains(.maskShift) && !flags.contains(.maskAlternate)
                let isCtrlV = flags.contains(.maskControl) && !flags.contains(.maskCommand)
                                  && !flags.contains(.maskShift) && !flags.contains(.maskAlternate)

                // Allow simulated ⌘V / ⌃V events through during paste
                if PasteQueueService._isPasting, (isCmdV || isCtrlV) {
                    return Unmanaged.passRetained(event)
                }

                // User pressed ⌘V during a session → end session and begin sequential paste
                if PasteQueueService._sessionWatching, isCmdV {
                    Task { @MainActor in
                        PasteQueueService._instance?.handleSessionPaste()
                    }
                    return nil  // Suppress the original ⌘V
                }

                return Unmanaged.passRetained(event)
            },
            userInfo: nil
        )

        guard let tap else {
            // Accessibility permission not granted — fall back to copying everything to clipboard
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
