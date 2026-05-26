import AppKit
import SwiftUI

// MARK: - Panel State

@MainActor
final class PanelState: ObservableObject {
    static let shared = PanelState()
    @Published var isHovered = false
    private init() {}
}

// MARK: - SidePanelController

@MainActor
final class SidePanelController {

    static let shared = SidePanelController()

    private var panel: NSPanel?
    private let panelWidth: CGFloat = 360
    private let edgeInset: CGFloat = 0

    private var dragMonitor: Any?
    private var mouseUpMonitor: Any?
    private var hoverTimer: Timer?

    private init() {}

    var isVisible: Bool { panel?.isVisible ?? false }

    // MARK: - Show / Hide

    func show() {
        let panel = getOrCreatePanel()
        startDragMonitoring()

        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame

        let visibleFrame = NSRect(
            x: vf.maxX - panelWidth - edgeInset,
            y: vf.minY,
            width: panelWidth,
            height: vf.height
        )
        let offscreenFrame = NSRect(
            x: vf.maxX,
            y: vf.minY,
            width: panelWidth,
            height: vf.height
        )

        panel.setFrame(offscreenFrame, display: false)
        panel.orderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(visibleFrame, display: true)
        }
        NotificationCenter.default.post(name: .sidePanelVisibilityChanged, object: nil)
    }

    func hide() {
        stopDragMonitoring()
        PanelState.shared.isHovered = false
        guard let panel, panel.isVisible else { return }
        guard let screen = NSScreen.main else { panel.orderOut(nil); return }

        let vf = screen.visibleFrame
        let current = panel.frame
        let offscreen = NSRect(x: vf.maxX, y: current.minY,
                               width: current.width, height: current.height)

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(offscreen, display: true)
        }, completionHandler: {
            panel.orderOut(nil)
            NotificationCenter.default.post(name: .sidePanelVisibilityChanged, object: nil)
        })
    }

    func toggle() { isVisible ? hide() : show() }

    // MARK: - Drag & Hover Monitoring

    private func startDragMonitoring() {
        guard dragMonitor == nil else { return }

        // Poll mouse position to fade the panel on hover (reduces visual obstruction)
        var lastOverPanel = false
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let panel = self.panel else { return }

            let mouse = NSEvent.mouseLocation
            let overPanel = panel.frame.contains(mouse)
            guard overPanel != lastOverPanel else { return }
            lastOverPanel = overPanel

            guard let layer = self.containerView?.layer else { return }
            let targetOpacity: Float = overPanel ? 0.4 : 1.0
            let anim = CABasicAnimation(keyPath: "opacity")
            anim.fromValue = layer.presentation()?.opacity ?? layer.opacity
            anim.toValue = targetOpacity
            anim.duration = overPanel ? 0.25 : 0.45
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            anim.fillMode = .forwards
            anim.isRemovedOnCompletion = false
            layer.add(anim, forKey: "hoverFade")
            layer.opacity = targetOpacity
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer

        // Only accept mouse events while a file drag is over the panel
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            guard let self, let panel = self.panel else { return }
            let dragBoard = NSPasteboard(name: .drag)
            let isFileDrag = dragBoard.canReadObject(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            )
            let overPanel = panel.frame.contains(NSEvent.mouseLocation)
            Task { @MainActor in
                panel.ignoresMouseEvents = !(isFileDrag && overPanel)
            }
        }

        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            guard let self, let panel = self.panel else { return }
            Task { @MainActor in
                panel.ignoresMouseEvents = true
            }
        }
    }

    private func stopDragMonitoring() {
        if let m = dragMonitor    { NSEvent.removeMonitor(m); dragMonitor = nil }
        if let m = mouseUpMonitor { NSEvent.removeMonitor(m); mouseUpMonitor = nil }
        hoverTimer?.invalidate(); hoverTimer = nil
        containerView?.layer?.opacity = 1.0
    }

    // MARK: - Panel Setup

    // Stored outside the panel's view hierarchy so SwiftUI doesn't manage this layer
    nonisolated(unsafe) private var containerView: NSView?

    private func getOrCreatePanel() -> NSPanel {
        if let existing = panel { return existing }

        let core = AppCore.shared
        let rootView = PromptComposerView()
            .environmentObject(core.session)
            .environmentObject(core.speech)
            .environmentObject(PanelState.shared)

        let hosting = NSHostingController(rootView: rootView)

        // Wrap the hosting view in a plain container whose layer we control for opacity.
        // NSHostingView's internal layer is managed by SwiftUI — touching it directly causes stale state.
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = .clear

        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        containerView = container

        let p = NSPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        p.contentView = container
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isMovable = false
        p.hasShadow = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.ignoresMouseEvents = true

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: p,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.panel = nil
                self?.containerView = nil
            }
        }

        self.panel = p
        return p
    }
}
