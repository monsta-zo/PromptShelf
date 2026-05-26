import SwiftUI
import AVKit

// MARK: - Feature Step Model

private struct FeatureStep: Identifiable {
    let id: Int
    let title: String
    let description: String
    let shortcut: String?
    let videoName: String
}

private let steps: [FeatureStep] = [
    FeatureStep(
        id: 1,
        title: "Voice Input",
        description: "Speak naturally after triggering. Your words are transcribed in real-time and stacked as a text chunk.",
        shortcut: "⌃⌥ to start",
        videoName: "1"
    ),
    FeatureStep(
        id: 2,
        title: "Clipboard Capture",
        description: "Copy any text during a session and it's automatically added as a chunk — no extra steps needed.",
        shortcut: "⌘C",
        videoName: "2"
    ),
    FeatureStep(
        id: 3,
        title: "Image Copy",
        description: "Copy any image from a browser, design tool, or document. It stacks as a visual chunk ready to paste.",
        shortcut: "⌘C",
        videoName: "3"
    ),
    FeatureStep(
        id: 4,
        title: "Screenshot Capture",
        description: "Take a screenshot during a session and it goes straight to your shelf — no file saved to desktop.",
        shortcut: "⌘⇧3 / ⌘⇧4",
        videoName: "4"
    ),
    FeatureStep(
        id: 5,
        title: "File Drop",
        description: "Drag any file onto the panel to add it as a chunk. Works as a file URL for web AI or path text for terminal.",
        shortcut: "Drag & Drop",
        videoName: "5"
    ),
    FeatureStep(
        id: 6,
        title: "Smart Paste",
        description: "Press ⌘V to end the session. All chunks — voice, images, files — are pasted in order into your AI tool.",
        shortcut: "⌘V",
        videoName: "6"
    ),
]

// MARK: - HowToView

struct HowToView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex = 0

    private var step: FeatureStep { steps[currentIndex] }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color.primary.opacity(0.07))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Spacer()

                Text("How to Use")
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                // Page indicator
                Text("\(currentIndex + 1) / \(steps.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 32)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Video player
            LoopingVideoView(videoName: step.videoName)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 0))

            Divider()

            // Content
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(step.title)
                        .font(.system(size: 14, weight: .semibold))

                    if let shortcut = step.shortcut {
                        Text(shortcut)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }

                Text(step.description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            // Navigation
            HStack(spacing: 16) {
                // Prev
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentIndex = max(0, currentIndex - 1)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .medium))
                        Text("Prev")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(currentIndex == 0 ? Color.secondary.opacity(0.4) : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(currentIndex == 0)

                Spacer()

                // Dot indicators
                HStack(spacing: 5) {
                    ForEach(0..<steps.count, id: \.self) { i in
                        Circle()
                            .fill(i == currentIndex ? Color.accentColor : Color.primary.opacity(0.15))
                            .frame(width: i == currentIndex ? 7 : 5, height: i == currentIndex ? 7 : 5)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) { currentIndex = i }
                            }
                    }
                }

                Spacer()

                // Next
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentIndex = min(steps.count - 1, currentIndex + 1)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Next")
                            .font(.system(size: 12))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(currentIndex == steps.count - 1 ? Color.secondary.opacity(0.4) : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(currentIndex == steps.count - 1)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 360)
    }
}

// MARK: - Looping Video Player

struct LoopingVideoView: NSViewRepresentable {

    let videoName: String

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor

        guard let url = Bundle.module.url(forResource: videoName, withExtension: "mp4") else {
            return container
        }

        let item   = AVPlayerItem(url: url)
        let player = AVQueuePlayer(playerItem: item)
        let looper = AVPlayerLooper(player: player, templateItem: item)

        // Keep looper alive
        context.coordinator.looper = looper
        context.coordinator.player = player

        let playerLayer        = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspect
        playerLayer.frame      = container.bounds
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        container.layer?.addSublayer(playerLayer)

        player.play()
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Video changes handled by coordinator
        guard let url = Bundle.module.url(forResource: videoName, withExtension: "mp4") else { return }

        let item   = AVPlayerItem(url: url)
        let player = AVQueuePlayer(playerItem: item)
        let looper = AVPlayerLooper(player: player, templateItem: item)

        context.coordinator.looper = looper
        context.coordinator.player = player

        if let playerLayer = nsView.layer?.sublayers?.first(where: { $0 is AVPlayerLayer }) as? AVPlayerLayer {
            playerLayer.player = player
        }

        player.play()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var looper: AVPlayerLooper?
        var player: AVQueuePlayer?
    }
}
