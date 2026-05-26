import Foundation
import AppKit

// MARK: - Context Item

struct ContextItem: Identifiable, Codable {
    let id: UUID
    var label: String
    var contentType: ContentType
    var rawContent: String       // 텍스트/파일 내용 또는 URL
    var imageName: String?       // 이미지 파일명 (별도 저장)
    var filePath: String?        // 원본 파일 경로
    var language: String?        // 코드 파일 언어
    let createdAt: Date

    enum ContentType: String, Codable {
        case text, file, image, url
    }

    // MARK: - Computed

    var displayIcon: String {
        switch contentType {
        case .text:  return "text.quote"
        case .file:  return "doc.text"
        case .image: return "photo"
        case .url:   return "link"
        }
    }

    var displayTitle: String {
        label.isEmpty ? defaultTitle : label
    }

    private var defaultTitle: String {
        switch contentType {
        case .text:
            let preview = rawContent.prefix(40).replacingOccurrences(of: "\n", with: " ")
            return preview.isEmpty ? "텍스트" : String(preview)
        case .file:
            return filePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "파일"
        case .image:
            return imageName ?? "이미지"
        case .url:
            return rawContent
        }
    }

    // MARK: - Factory

    static func makeText(_ text: String, label: String = "") -> ContextItem {
        ContextItem(
            id: UUID(), label: label, contentType: .text,
            rawContent: text, createdAt: Date()
        )
    }

    static func makeFile(path: URL, content: String, language: String) -> ContextItem {
        ContextItem(
            id: UUID(),
            label: path.lastPathComponent,
            contentType: .file,
            rawContent: content,
            filePath: path.path,
            language: language,
            createdAt: Date()
        )
    }

    static func makeURL(_ url: URL, title: String? = nil) -> ContextItem {
        ContextItem(
            id: UUID(),
            label: title ?? "",
            contentType: .url,
            rawContent: url.absoluteString,
            createdAt: Date()
        )
    }

    static func makeImage(name: String) -> ContextItem {
        ContextItem(
            id: UUID(),
            label: "",
            contentType: .image,
            rawContent: "",
            imageName: name,
            createdAt: Date()
        )
    }
}
