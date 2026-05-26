import AppKit
import Foundation

// MARK: - Chunk

enum PromptChunk: Identifiable {
    case text(String)
    case image(NSImage)
    case file(url: URL, name: String)   // 경로만 저장, 내용 읽지 않음

    var id: UUID { UUID() }  // 뷰 렌더링용
}

// MARK: - Session

/// Holds the current prompt being built — stacked spoken + copied chunks.
@MainActor
final class PromptSession: ObservableObject {

    static let shared = PromptSession()

    @Published private(set) var chunks: [PromptChunk] = []
    @Published var liveText: String = ""   // in-progress speech (real-time)

    private init() {}

    // MARK: - API

    func addChunk(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        chunks.append(.text(trimmed))
        liveText = ""
    }

    func addImageChunk(_ image: NSImage) {
        chunks.append(.image(image))
    }

    func addFileChunk(url: URL) {
        let speech = AppCore.shared.speech
        if speech.isListening {
            let spoken = speech.flushCurrentChunk()
            if !spoken.isEmpty { addChunk(spoken) }
        }
        chunks.append(.file(url: url, name: url.lastPathComponent))
    }

    /// 텍스트/파일 청크를 이어붙인 전체 프롬프트 (히스토리 저장용)
    var fullPrompt: String {
        chunks.compactMap {
            switch $0 {
            case .text(let t):          return t
            case .file(let url, _):     return url.path
            case .image:                return nil
            }
        }.joined(separator: "\n")
    }

    /// 이미지 포함 여부
    var hasImages: Bool {
        chunks.contains { if case .image = $0 { return true }; return false }
    }

    /// 외부에서 캡처한 청크 배열을 직접 클립보드에 복사 (세션 clear 후에도 사용 가능)
    static func copyToClipboard(chunks: [PromptChunk]) {
        guard !chunks.isEmpty else { return }

        let pb = NSPasteboard.general
        pb.clearContents()

        let html = PromptSession.shared.buildHTMLFrom(chunks)
        pb.setString(html, forType: NSPasteboard.PasteboardType("public.html"))

        let plain = chunks.compactMap { if case .text(let t) = $0 { return t } else { return nil } }
            .joined(separator: "\n\n")
        if !plain.isEmpty { pb.setString(plain, forType: .string) }
    }

    /// 모든 청크를 순서대로 클립보드에 복사
    /// - public.html : 텍스트 + 이미지 순서 유지 (Claude web, Cursor AI, Notes 등)
    /// - .string     : 텍스트만 (터미널, 순수 텍스트 에디터 폴백)
    func copyAllToClipboard() {
        guard !chunks.isEmpty else { return }

        let pb = NSPasteboard.general
        pb.clearContents()

        // 1) HTML — 텍스트와 이미지를 순서대로 포함
        let html = buildHTML()
        pb.setString(html, forType: NSPasteboard.PasteboardType("public.html"))

        // 2) Plain text 폴백 (HTML을 못 읽는 앱용)
        let plainText = chunks.compactMap { chunk -> String? in
            if case .text(let t) = chunk { return t }
            return nil
        }.joined(separator: "\n\n")
        if !plainText.isEmpty {
            pb.setString(plainText, forType: .string)
        }
    }

    // MARK: - HTML Builder

    private func buildHTMLFrom(_ source: [PromptChunk]) -> String {
        var html = "<html><body style='font-family:system-ui;font-size:14px;'>"
        for chunk in source {
            switch chunk {
            case .text(let t):
                let escaped = t
                    .replacingOccurrences(of: "&", with: "&amp;")
                    .replacingOccurrences(of: "<", with: "&lt;")
                    .replacingOccurrences(of: ">", with: "&gt;")
                    .replacingOccurrences(of: "\n", with: "<br>")
                html += "<p>\(escaped)</p>"
            case .image(let img):
                if let b64 = jpegBase64(img, maxWidth: 1200, quality: 0.8) {
                    html += "<p><img src='data:image/jpeg;base64,\(b64)' style='max-width:100%;border-radius:6px;'></p>"
                }
            case .file(let url, let name):
                html += "<p><code>\(url.path)</code></p>"
            }
        }
        html += "</body></html>"
        return html
    }

    private func buildHTML() -> String {
        var html = "<html><body style='font-family:system-ui;font-size:14px;'>"

        for chunk in chunks {
            switch chunk {
            case .text(let t):
                let escaped = t
                    .replacingOccurrences(of: "&", with: "&amp;")
                    .replacingOccurrences(of: "<", with: "&lt;")
                    .replacingOccurrences(of: ">", with: "&gt;")
                    .replacingOccurrences(of: "\n", with: "<br>")
                html += "<p>\(escaped)</p>"

            case .image(let img):
                // 최대 1200px로 축소 후 JPEG 80% 압축 (용량 절감)
                if let b64 = jpegBase64(img, maxWidth: 1200, quality: 0.8) {
                    html += "<p><img src='data:image/jpeg;base64,\(b64)' style='max-width:100%;border-radius:6px;'></p>"
                }
            case .file(let url, let name):
                html += "<p><code>\(url.path)</code></p>"
            }
        }

        html += "</body></html>"
        return html
    }

    private func jpegBase64(_ image: NSImage, maxWidth: CGFloat, quality: CGFloat) -> String? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }

        let scale  = min(1.0, maxWidth / size.width)
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)

        // 리사이즈
        let resized = NSImage(size: newSize)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: size),
                   operation: .copy, fraction: 1.0)
        resized.unlockFocus()

        guard let tiff   = resized.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg   = bitmap.representation(using: .jpeg,
                                                 properties: [.compressionFactor: quality])
        else { return nil }

        return jpeg.base64EncodedString()
    }

    var isEmpty: Bool { chunks.isEmpty && liveText.isEmpty }

    func clear() {
        chunks = []
        liveText = ""
    }
}
