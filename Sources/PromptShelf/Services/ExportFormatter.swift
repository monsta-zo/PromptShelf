import Foundation
import AppKit

struct ExportFormatter {

    // MARK: - Main Export

    static func toMarkdown(_ shelf: Shelf) -> String {
        guard !shelf.items.isEmpty else { return "" }

        var lines: [String] = []
        lines.append("## Context: \(shelf.name)")
        lines.append("")

        for item in shelf.items {
            lines.append(contentsOf: formatItem(item))
            lines.append("")
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
    }

    private static func formatItem(_ item: ContextItem) -> [String] {
        var lines: [String] = []

        switch item.contentType {
        case .text:
            if !item.label.isEmpty {
                lines.append("**[\(item.label)]**")
            }
            lines.append(item.rawContent)

        case .file:
            let filename = item.filePath.flatMap { URL(fileURLWithPath: $0).lastPathComponent } ?? item.label
            let lang = item.language ?? ""
            lines.append("**[\(filename)]**")
            if let path = item.filePath {
                lines.append("*경로: \(path)*")
            }
            lines.append("```\(lang)")
            lines.append(item.rawContent)
            lines.append("```")

        case .image:
            let name = item.imageName ?? "이미지"
            lines.append("**[이미지: \(name)]**")
            lines.append("*(이미지는 별도로 첨부해주세요)*")

        case .url:
            let title = item.label.isEmpty ? item.rawContent : item.label
            lines.append("**[링크: \(title)]**")
            lines.append(item.rawContent)
        }

        return lines
    }

    // MARK: - Copy to Clipboard

    static func copyToClipboard(_ shelf: Shelf) {
        let markdown = toMarkdown(shelf)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(markdown, forType: .string)
    }

    // MARK: - Claude Code 형식 (파일 참조 포함)

    static func toClaudeCodeFormat(_ shelf: Shelf) -> String {
        var lines: [String] = []

        for item in shelf.items {
            switch item.contentType {
            case .file:
                // Claude Code는 파일 경로를 직접 인식
                if let path = item.filePath {
                    lines.append("@\(path)")
                }
            case .url:
                lines.append(item.rawContent)
            default:
                lines.append(contentsOf: formatItem(item))
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}
