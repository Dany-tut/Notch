import Foundation

/// Простейшее хранилище: один Codable-массив в одном файле внутри
/// Application Support. Для заготовок и истории буфера этого достаточно,
/// база данных здесь была бы лишней.
struct JSONStore<Element: Codable> {
    let fileURL: URL

    init(filename: String) {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Notch", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent(filename)
    }

    func load() -> [Element] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([Element].self, from: data)) ?? []
    }

    func removeFile() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    func save(_ elements: [Element]) {
        guard let data = try? JSONEncoder().encode(elements) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
