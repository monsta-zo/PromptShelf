import Foundation
import UniformTypeIdentifiers

struct FileDropService {

    // MARK: - Language detection

    static func detectLanguage(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "swift":             return "swift"
        case "py":                return "python"
        case "ts", "tsx":        return "typescript"
        case "js", "jsx":        return "javascript"
        case "rs":                return "rust"
        case "go":                return "go"
        case "kt":                return "kotlin"
        case "java":              return "java"
        case "cs":                return "csharp"
        case "cpp", "cc", "cxx": return "cpp"
        case "c", "h":           return "c"
        case "rb":                return "ruby"
        case "php":               return "php"
        case "sh", "bash":       return "bash"
        case "json":              return "json"
        case "yaml", "yml":      return "yaml"
        case "toml":              return "toml"
        case "md":                return "markdown"
        case "html", "htm":      return "html"
        case "css", "scss":      return "css"
        case "sql":               return "sql"
        default:                  return ""
        }
    }

    // MARK: - File reading

    static func readTextFile(at url: URL) -> ContextItem? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let language = detectLanguage(for: url)
        return .makeFile(path: url, content: content, language: language)
    }

    // MARK: - Image check

    static func isImageFile(_ url: URL) -> Bool {
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "webp", "heic", "bmp", "tiff"]
        return imageExtensions.contains(url.pathExtension.lowercased())
    }

    static func readImageFile(at url: URL) -> ContextItem? {
        guard (try? Data(contentsOf: url)) != nil else { return nil }
        return .makeImage(name: url.lastPathComponent)
    }
}
