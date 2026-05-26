import AppKit
import SwiftUI

// MARK: - 패널 상태 (hover opacity 공유)

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

    // MARK: - 드래그 감지 + 호버 감지

    private func startDragMonitoring() {
        guard dragMonitor == nil else { return }

        // 마우스 위치 폴링 → SwiftUI opacity 조절
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

        // 파일 드래그 중일 때만 이벤트 허용
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

    nonisolated(unsafe) private var containerView: NSView?

    private func getOrCreatePanel() -> NSPanel {
        if let existing = panel { return existing }

        let core = AppCore.shared
        let rootView = PromptComposerView()
            .environmentObject(core.session)
            .environmentObject(core.speech)
            .environmentObject(PanelState.shared)

        let hosting = NSHostingController(rootView: rootView)

        // ── 컨테이너: SwiftUI 위에 씌우는 안정적인 레이어 ──────────
        // NSHostingView 는 SwiftUI 가 내부 layer 를 관리 → 직접 건드리면 stale
        // 컨테이너의 layer 만 opacity 제어 → 안정적
        let container = NSView()
        container.wantsLayer = true          // 이 layer 는 SwiftUI 가 건드리지 않음
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

        p.contentView = container            // contentViewController 대신 직접 설정
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
