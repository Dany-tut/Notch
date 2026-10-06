import Foundation

/// Заметка на полях: один текст, который всегда под рукой.
///
/// Записей несколько не бывает намеренно. Список требует, чтобы человек
/// сначала придумал, куда пишет, — а сюда пишут как на обороте конверта,
/// не выбирая. Что должно остаться надолго, переезжает в заготовки.
@MainActor
final class NotesStore: ObservableObject {
    @Published var text: String {
        didSet {
            guard text != oldValue else { return }
            scheduleSave()
        }
    }

    private let store = JSONStore<String>(filename: "notes.json")
    private var saveTask: Task<Void, Never>?

    init() {
        text = store.load().first ?? ""
    }

    /// Пишем не на каждую букву: набор идёт очередями, и файл нужно
    /// трогать, когда очередь кончилась.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.5))
            guard !Task.isCancelled else { return }
            self?.persist()
        }
    }

    func clear() {
        text = ""
        saveTask?.cancel()
        persist()
    }

    private func persist() {
        store.save(text.isEmpty ? [] : [text])
    }
}
