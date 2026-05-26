import Foundation

struct Shelf: Identifiable, Codable {
    let id: UUID
    var name: String
    var items: [ContextItem]
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, items: [ContextItem] = []) {
        self.id = id
        self.name = name
        self.items = items
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    mutating func add(_ item: ContextItem) {
        items.append(item)
        updatedAt = Date()
    }

    mutating func remove(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        updatedAt = Date()
    }

    mutating func move(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        updatedAt = Date()
    }

    var isEmpty: Bool { items.isEmpty }
    var count: Int { items.count }
}
