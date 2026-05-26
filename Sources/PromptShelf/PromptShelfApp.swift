import SwiftUI
import AppKit
import Combine
import ServiceManagement
import os.log

private let logger = Logger(subsystem: "com.promptshelf.app", category: "main")

// MARK: - App Core

@MainActor
final class AppCore: ObservableObject {
    static let shared = AppCore()

    let speech  = SpeechService()
    let session = PromptSession.shared
    let history = PromptHistory.shared

    private init() {}
}

// MARK: - App

@main
struct PromptShelfApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // All UI is managed by AppDelegate (NSStatusItem + NSPopover)
        Settings { EmptyView() }
    }
}

// MARK: - AppDelegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupPopover()
        setupLaunchAtLogin()
        requestAccessibilityPermission()
        setupIconObservation()
        setupGlobalHotkeys()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }

        button.image = Self.booksImage()
        button.action = #selector(statusItemClicked)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover(sender)
        }
    }

    // MARK: - Right-Click Menu

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit PromptShelf", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        DispatchQueue.main.async { [weak self] in
            self?.statusItem.menu = nil
        }
    }

    // MARK: - Launch at Login

    /// Registers the app as a login item on first launch.
    /// The user can disable it anytime via System Settings → General → Login Items.
    private func setupLaunchAtLogin() {
        let service = SMAppService.mainApp
        guard service.status != .enabled else { return }
        do {
            try service.register()
            logger.info("Registered as login item")
        } catch {
            logger.error("Failed to register login item: \(error.localizedDescription)")
        }
    }

    // MARK: - Popover

    private func setupPopover() {
        let core = AppCore.shared
        let contentView = PromptHistoryView()
            .environmentObject(core.history)

        let controller = NSHostingController(rootView: contentView)
        popover = NSPopover()
        popover.contentViewController = controller
        popover.behavior = .transient
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Icon Updates

    private func setupIconObservation() {
        let speech = AppCore.shared.speech

        // Observe speech state changes (isListening is derived from state)
        speech.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.refreshIcon() }
            }
            .store(in: &cancellables)

        // Update icon when side panel shows/hides
        NotificationCenter.default.publisher(for: .sidePanelVisibilityChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.refreshIcon() }
            }
            .store(in: &cancellables)
    }

    @MainActor
    func refreshIcon() {
        guard let button = statusItem?.button else { return }
        let isRecording = AppCore.shared.speech.isListening
        let isActive    = SidePanelController.shared.isVisible

        if isRecording {
            button.image = Self.recordingImage()
        } else if isActive {
            button.image = Self.booksImage()
        } else {
            button.image = Self.booksImage()
        }
    }

    // MARK: - Icon Helpers

    /// Standard books icon (template — adapts to dark/light menu bar)
    static func booksImage() -> NSImage? {
        let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let img = NSImage(systemSymbolName: "books.vertical.fill", accessibilityDescription: "PromptShelf")?
            .withSymbolConfiguration(cfg)
        img?.isTemplate = true
        return img
    }

    /// Waveform + red dot composite for recording state
    static func recordingImage() -> NSImage {
        let size = NSSize(width: 28, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            // Waveform (white — template-style, drawn explicitly)
            if let waveform = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil) {
                let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
                if let configured = waveform.withSymbolConfiguration(cfg) {
                    configured.draw(in: NSRect(x: 0, y: 2, width: 18, height: 14))
                }
            }
            // Red dot
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: NSRect(x: 21, y: 6, width: 6, height: 6)).fill()
            return true
        }
        // Not a template — keeps the red color
        image.isTemplate = false
        return image
    }

    // MARK: - Accessibility

    private func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        logger.info("Accessibility trusted: \(trusted)")
    }

    // MARK: - Global Hotkeys
    // ⌃+⌥ first press  → open side panel + start recording
    // ⌃+⌥ second press → stop recording + save to history + hide panel

    private func setupGlobalHotkeys() {
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags == [.control, .option] else { return }

            Task { @MainActor in
                let core = AppCore.shared

                if core.speech.isListening {
                    // CANCEL — end session without pasting
                    PasteQueueService.shared.stopWatching()
                    TextSelectionService.shared.stopSession()
                    ScreenshotWatcher.shared.stopSession()
                    core.speech.stop { _ in }
                    core.session.clear()
                    SidePanelController.shared.hide()
                    NSSound(named: "Pop")?.play()

                } else {
                    // START
                    PasteQueueService.shared.stopWatching()
                    SidePanelController.shared.show()
                    TextSelectionService.shared.startSession()
                    ScreenshotWatcher.shared.startSession()

                    logger.info("Session start — AXIsProcessTrusted: \(AXIsProcessTrusted())")
                    PasteQueueService.shared.startWatching()

                    core.speech.start { _ in }
                }
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let sidePanelVisibilityChanged = Notification.Name("sidePanelVisibilityChanged")
}
