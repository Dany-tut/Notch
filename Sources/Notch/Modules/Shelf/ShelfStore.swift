import AppKit

/// Запись полки. Файл не копируется — храним закладку, чтобы ссылка пережила
/// переименование и перемещение оригинала.
struct ShelfEntry: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var bookmark: Data
    var name: String
    var addedAt: Date = Date()
    /// Файл создали мы сами (вставили из буфера) — значит, и удалять его нам.
    /// Опционально, чтобы старые shelf.json без этого поля читались как раньше.
    var isOwned: Bool?
}

/// Запись вместе с разрешённым путём — то, что реально рисует панель.
struct ShelfItem: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let name: String
}

@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []

    private let store = JSONStore<ShelfEntry>(filename: "shelf.json")
    private var entries: [ShelfEntry] = []

    init() {
        entries = store.load()
        resolve()
    }

    func add(_ urls: [URL]) {
        var added = false
        for url in urls {
            guard let bookmark = try? url.bookmarkData(options: .minimalBookmark) else { continue }
            // Один и тот же файл не кладём дважды.
            guard !items.contains(where: { $0.url == url }) else { continue }
            entries.append(ShelfEntry(bookmark: bookmark, name: url.lastPathComponent))
            added = true
        }
        guard added else { return }
        persistAndResolve()
    }

    /// Кладёт на полку содержимое буфера обмена.
    ///
    /// Скопированные в Finder файлы приходят как ссылки — кладём оригиналы.
    /// Скриншот же лежит в буфере просто картинкой, файла за ним нет, поэтому
    /// сохраняем его сами и помечаем запись своей.
    @discardableResult
    func paste(from pasteboard: NSPasteboard = .general) -> Bool {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
           !urls.isEmpty {
            add(urls)
            return true
        }

        guard let drop = Self.materialize(pasteboard) else { return false }
        return adopt(drop)
    }

    func remove(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let removed = entries.filter { ids.contains($0.id) }
        entries.removeAll { ids.contains($0.id) }
        persistAndResolve()
        discardOwnedFiles(of: removed)
    }

    func removeAll() {
        let removed = entries
        entries.removeAll()
        persistAndResolve()
        discardOwnedFiles(of: removed)
    }

    /// Свежие пути для отправки: закладки разворачиваются заново, а не
    /// берутся из уже нарисованного списка — файл могли переименовать или
    /// перенести, пока полка висела открытой. Пустой `ids` — вся полка.
    func urlsForSharing(_ ids: Set<UUID> = []) -> [URL] {
        entries
            .filter { ids.isEmpty || ids.contains($0.id) }
            .compactMap { entry in
                var stale = false
                guard let url = try? URL(
                    resolvingBookmarkData: entry.bookmark,
                    options: [],
                    relativeTo: nil,
                    bookmarkDataIsStale: &stale
                ), FileManager.default.fileExists(atPath: url.path) else { return nil }
                return url
            }
    }

    /// Записывает уже созданный нами файл как свою запись полки.
    private func adopt(_ url: URL) -> Bool {
        guard let bookmark = try? url.bookmarkData(options: .minimalBookmark) else {
            try? FileManager.default.removeItem(at: url)
            return false
        }
        entries.append(ShelfEntry(bookmark: bookmark, name: url.lastPathComponent, isOwned: true))
        persistAndResolve()
        return true
    }

    /// Свои файлы после удаления записи не оставляем — иначе папка растёт
    /// без конца. Чужие оригиналы не трогаем никогда.
    private func discardOwnedFiles(of removed: [ShelfEntry]) {
        for entry in removed where entry.isOwned == true {
            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: entry.bookmark,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Разворачивает закладки в пути и отбрасывает то, что исчезло с диска.
    private func resolve() {
        var alive: [ShelfEntry] = []
        var resolved: [ShelfItem] = []

        for entry in entries {
            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: entry.bookmark,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ), FileManager.default.fileExists(atPath: url.path) else { continue }

            alive.append(entry)
            resolved.append(ShelfItem(id: entry.id, url: url, name: url.lastPathComponent))
        }

        // Файл удалили мимо нас — чистим запись, а не показываем битую ссылку.
        if alive.count != entries.count {
            entries = alive
            store.save(entries)
        }
        items = resolved
    }

    private func persistAndResolve() {
        store.save(entries)
        resolve()
    }
}

// MARK: - Буфер в файл

private extension ShelfStore {
    /// Папка для вставленного: лежит рядом с остальными данными приложения.
    static var dropsDirectory: URL {
        let url = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Notch/Shelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Имя вида `Clipboard 2026-09-19 at 20.41.05` — сортируется по времени
    /// и не конфликтует с уже лежащими файлами.
    static func dropName(extension ext: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Clipboard \(formatter.string(from: Date())).\(ext)"
    }

    /// Достаёт из буфера то, что можно сохранить файлом: картинку, PDF или
    /// текст. Порядок важен — скриншот приходит сразу в нескольких типах.
    static func materialize(_ pasteboard: NSPasteboard) -> URL? {
        if let data = pasteboard.data(forType: .png) {
            return write(data, extension: "png")
        }
        // TIFF — то, во что macOS кладёт вырезанный кусок экрана и картинки
        // из большинства приложений. Перегоняем в PNG: он меньше и универсальнее.
        if let tiff = pasteboard.data(forType: .tiff),
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            return write(png, extension: "png")
        }
        if let data = pasteboard.data(forType: .pdf) {
            return write(data, extension: "pdf")
        }
        if let text = pasteboard.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let data = text.data(using: .utf8) {
            return write(data, extension: "txt")
        }
        return nil
    }

    static func write(_ data: Data, extension ext: String) -> URL? {
        let url = dropsDirectory.appendingPathComponent(dropName(extension: ext))
        guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }
}
