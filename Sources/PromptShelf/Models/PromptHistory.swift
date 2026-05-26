import Foundation

struct PromptEntry: Identifiable {
    let id = UUID()
    let text: String
    let date: Date
}

@MainActor
final class PromptHistory: ObservableObject {

    static let shared = PromptHistory()

    @Published private(set) var entries: [PromptEntry] = []

    private init() {}

    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        entries.insert(PromptEntry(text: trimmed, date: Date()), at: 0) // newest first
    }

    func remove(_ entry: PromptEntry) {
        entries.removeAll { $0.id == entry.id }
    }

    func clear() {
        entries = []
    }
}
