import Foundation
import Combine
import AppKit

@MainActor
final class ShelfStore: ObservableObject {

    // MARK: - Published State

    @Published var shelves: [Shelf] = []
    @Published var activeShelfID: UUID?

    // MARK: - Computed

    var activeShelf: Shelf? {
        get { shelves.first(where: { $0.id == activeShelfID }) }
    }

    var activeShelfIndex: Int? {
        shelves.firstIndex(where: { $0.id == activeShelfID })
    }

    // MARK: - Storage

    private let saveURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("PromptShelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("shelves.json")
    }()

    // MARK: - Init

    init() {
        load()
        if shelves.isEmpty {
            let defaultShelf = Shelf(name: "기본 선반")
            shelves = [defaultShelf]
            activeShelfID = defaultShelf.id
            save()
        } else {
            activeShelfID = shelves.first?.id
        }
    }

    // MARK: - Shelf Management

    func addShelf(name: String) {
        let shelf = Shelf(name: name.isEmpty ? "새 선반" : name)
        shelves.append(shelf)
        activeShelfID = shelf.id
        save()
    }

    func removeShelf(_ shelf: Shelf) {
        shelves.removeAll { $0.id == shelf.id }
        if activeShelfID == shelf.id {
            activeShelfID = shelves.first?.id
        }
        save()
    }

    func renameShelf(_ shelf: Shelf, to name: String) {
        guard let idx = shelves.firstIndex(where: { $0.id == shelf.id }) else { return }
        shelves[idx].name = name
        save()
    }

    // MARK: - Item Management

    func addItem(_ item: ContextItem) {
        guard let idx = activeShelfIndex else { return }
        shelves[idx].add(item)
        save()
    }

    func removeItem(_ item: ContextItem) {
        guard let idx = activeShelfIndex else { return }
        shelves[idx].items.removeAll { $0.id == item.id }
        shelves[idx].updatedAt = Date()
        save()
    }

    func moveItems(from source: IndexSet, to destination: Int) {
        guard let idx = activeShelfIndex else { return }
        shelves[idx].move(from: source, to: destination)
        save()
    }

    func clearActiveShelf() {
        guard let idx = activeShelfIndex else { return }
        shelves[idx].items.removeAll()
        shelves[idx].updatedAt = Date()
        save()
    }

    // MARK: - Quick Add from Clipboard

    func addFromClipboard() {
        let pasteboard = NSPasteboard.general

        // 이미지 우선
        if let image = NSImage(pasteboard: pasteboard),
           let tiffData = image.tiffRepresentation {
            let name = "clipboard_\(Int(Date().timeIntervalSince1970)).png"
            saveImageData(tiffData, name: name)
            addItem(.makeImage(name: name))
            return
        }

        // 텍스트
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            addItem(.makeText(text))
        }
    }

    // MARK: - Persistence

    func save() {
        do {
            let data = try JSONEncoder().encode(shelves)
            try data.write(to: saveURL)
        } catch {
            print("Save error: \(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL) else { return }
        if let decoded = try? JSONDecoder().decode([Shelf].self, from: data) {
            shelves = decoded
        }
    }

    // MARK: - Image Storage

    func imageURL(for name: String) -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("PromptShelf/images/\(name)")
    }

    func saveImageData(_ data: Data, name: String) {
        let url = imageURL(for: name)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url)
    }
}
