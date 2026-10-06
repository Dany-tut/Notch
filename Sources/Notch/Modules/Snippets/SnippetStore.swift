import AppKit

struct Snippet: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var label: String
    var value: String
    /// SF Symbol рядом со строкой. Пустая строка — иконка по умолчанию.
    var symbol: String = ""
}

@MainActor
final class SnippetStore: ObservableObject {
    @Published private(set) var snippets: [Snippet] = []

    private let store = JSONStore<Snippet>(filename: "snippets.json")

    init() {
        snippets = store.load()
    }

    func add(label: String, value: String, symbol: String = "") {
        snippets.append(Snippet(label: label, value: value, symbol: symbol))
        persist()
    }

    func update(_ snippet: Snippet) {
        guard let index = snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        snippets[index] = snippet
        persist()
    }

    func remove(at offsets: IndexSet) {
        snippets.remove(atOffsets: offsets)
        persist()
    }

    func move(from source: IndexSet, to destination: Int) {
        snippets.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    private func persist() { store.save(snippets) }
}
