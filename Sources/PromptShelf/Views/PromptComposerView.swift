import SwiftUI
import UniformTypeIdentifiers

struct PromptComposerView: View {

    @EnvironmentObject var session: PromptSession
    @EnvironmentObject var speech: SpeechService
    @EnvironmentObject var panelState: PanelState
    @State private var isDropTargeted = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .trailing, spacing: 8) {

                    // Finalized chunks
                    ForEach(Array(session.chunks.enumerated()), id: \.offset) { _, chunk in
                        switch chunk {
                        case .text(let text):
                            glassBubble {
                                Text(text)
                                    .font(.system(size: 14))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.trailing)
                            }
                            .frame(maxWidth: 300, alignment: .trailing)

                        case .image(let nsImage):
                            glassBubble(padding: 6) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: 260, maxHeight: 200)
                                    .cornerRadius(8)
                            }
                            .frame(maxWidth: 300, alignment: .trailing)

                        case .file(_, let name):
                            glassBubble {
                                HStack(spacing: 7) {
                                    Image(systemName: "doc.text.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                    Text(name)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                            .frame(maxWidth: 300, alignment: .trailing)
                        }
                    }

                    // Live transcription bubble
                    if !session.liveText.isEmpty {
                        glassBubble(style: .live) {
                            Text(session.liveText)
                                .font(.system(size: 14))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.trailing)
                        }
                        .frame(maxWidth: 300, alignment: .trailing)
                        .id("live")
                    }

                    // Listening indicator (no text yet)
                    if speech.isListening && session.liveText.isEmpty && session.chunks.isEmpty {
                        glassBubble(style: .live) {
                            HStack(spacing: 6) {
                                Text("Listening…")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.primary)
                                Circle()
                                    .fill(Color.red.opacity(0.85))
                                    .frame(width: 6, height: 6)
                            }
                        }
                    }

                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .onChange(of: session.liveText) { _ in
                withAnimation { proxy.scrollTo("bottom") }
            }
            .onChange(of: session.chunks.count) { _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom") }
            }
            .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
                for provider in providers {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url, url.isFileURL else { return }
                        Task { @MainActor in
                            PromptSession.shared.addFileChunk(url: url)
                        }
                    }
                }
                return true
            }
            .overlay {
                if isDropTargeted { dropOverlay }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }

    // MARK: - Glass Bubble

    enum BubbleStyle { case normal, live }

    @ViewBuilder
    private func glassBubble<Content: View>(
        style: BubbleStyle = .normal,
        padding: CGFloat = 10,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(.horizontal, padding == 10 ? 14 : padding)
            .padding(.vertical, padding)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.regularMaterial)
            }
    }

    // MARK: - Drop Overlay

    private var dropOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.85)

            Rectangle()
                .strokeBorder(
                    Color.accentColor.opacity(0.5),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
                .padding(12)

            VStack(spacing: 10) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(Color.accentColor)
                Text("Drop to add")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .ignoresSafeArea()
        .transition(.opacity)
        .animation(.easeOut(duration: 0.12), value: isDropTargeted)
    }
}
