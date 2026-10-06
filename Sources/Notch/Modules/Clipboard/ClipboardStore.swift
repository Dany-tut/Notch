import AppKit
import CryptoKit

struct ClipboardEntry: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var text: String
    var date: Date = Date()
    var isPinned: Bool = false
    /// Имя файла картинки в папке `Clipboard`. У текстовых записей — nil.
    /// Опционально, чтобы прежняя история без этого поля читалась как раньше.
    var imageFile: String?
    /// Отпечаток картинки: по нему ловим повторное копирование того же кадра.
    var imageHash: String?

    var isImage: Bool { imageFile != nil }

    /// Путь к картинке. Пересобираем от папки, а не храним: папка приложения
    /// переезжает вместе с домашним каталогом, абсолютный путь — нет.
    var imageURL: URL? {
        imageFile.map { ClipboardStore.imagesDirectory.appendingPathComponent($0) }
    }
}

/// Следит за системным буфером обмена опросом `changeCount` — публичного
/// уведомления об изменении буфера в macOS нет.
@MainActor
final class ClipboardStore: ObservableObject {
    @Published private(set) var entries: [ClipboardEntry] = []

    /// Строка поиска и то, развёрнуто ли поле.
    ///
    /// Живёт в сторе, а не в самом модуле: поле переехало в строку
    /// заголовка, а список остался внизу — это разные ветки дерева видов,
    /// и общее у них теперь только хранилище.
    @Published var query = ""
    @Published var isSearching = false

    /// Записи, прошедшие через поиск.
    var visible: [ClipboardEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return entries }
        return entries.filter { $0.text.range(of: trimmed, options: .caseInsensitive) != nil }
    }

    private let store = SecureStore<ClipboardEntry>(
        filename: "clipboard.data",
        keyTag: "clipboard"
    )
    /// Старый открытый файл — чистим его при первом же запуске.
    private let legacyFile = JSONStore<ClipboardEntry>(filename: "clipboard.json")
    private let settings: AppSettings
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?

    /// Сколько незакреплённых записей храним.
    private let limit = 60
    /// Картинок держим меньше: каждая — файл на диске, а не строка.
    private let imageLimit = 24
    private let pollInterval: TimeInterval = 0.4

    /// Менеджеры паролей помечают такие записи — их нельзя сохранять.
    private static let concealedTypes: [NSPasteboard.PasteboardType] = [
        .init("org.nspasteboard.ConcealedType"),
        .init("com.agilebits.onepassword"),
        .init("com.apple.is-sensitive")
    ]

    /// Папка с картинками истории. Рядом с остальными данными приложения.
    nonisolated static var imagesDirectory: URL {
        let url = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Notch/Clipboard", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    init(settings: AppSettings) {
        self.settings = settings
        lastChangeCount = pasteboard.changeCount
        entries = settings.persistClipboard ? store.load() : []
        migrateLegacyFile()
        dropOrphanImages()
    }

    /// До появления шифрования история лежала в открытом JSON. Переносим
    /// её и удаляем файл — оставлять открытую копию нельзя.
    private func migrateLegacyFile() {
        let legacy = legacyFile.load()
        guard !legacy.isEmpty else { return }
        if settings.persistClipboard && entries.isEmpty {
            entries = legacy
            store.save(entries)
        }
        legacyFile.removeFile()
    }

    /// Картинки от прошлых запусков, на которые уже никто не ссылается:
    /// история не сохраняется или запись из неё выпала. Папка иначе растёт
    /// без конца — её никто не видит и никто не чистит.
    private func dropOrphanImages() {
        let alive = Set(entries.compactMap(\.imageFile))
        let manager = FileManager.default
        let files = (try? manager.contentsOfDirectory(
            at: Self.imagesDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        for file in files where !alive.contains(file.lastPathComponent) {
            try? manager.removeItem(at: file)
        }
    }

    /// Пользователь передумал хранить историю — стираем файл с диска.
    func persistenceDidChange() {
        if settings.persistClipboard {
            persist()
        } else {
            store.removeFile()
        }
    }

    /// Забыть всё, что накопилось.
    func clearAll() {
        let removed = entries
        entries.removeAll()
        persist()
        discardImages(of: removed)
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Кладёт текст в буфер, не считая это новой записью истории.
    func copy(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastChangeCount = pasteboard.changeCount
    }

    /// Возвращает в буфер запись целиком — текстом или картинкой.
    func copy(_ entry: ClipboardEntry) {
        guard let url = entry.imageURL, let data = try? Data(contentsOf: url) else {
            copy(entry.text)
            return
        }
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .png)
        // Многие приложения читают из буфера только TIFF — кладём оба типа.
        if let tiff = NSImage(data: data)?.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
        lastChangeCount = pasteboard.changeCount
    }

    func togglePin(_ entry: ClipboardEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].isPinned.toggle()
        sortAndPersist()
    }

    func remove(_ entry: ClipboardEntry) {
        entries.removeAll { $0.id == entry.id }
        persist()
        discardImages(of: [entry])
    }

    func clearUnpinned() {
        let removed = entries.filter { !$0.isPinned }
        entries.removeAll { !$0.isPinned }
        persist()
        discardImages(of: removed)
    }

    private func poll() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        let types = pasteboard.types ?? []
        guard !types.contains(where: { Self.concealedTypes.contains($0) }) else { return }

        let text = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // Текст главнее: скопированный в Finder файл и картинка из браузера
        // приходят вместе со строкой, и строка — то, что человек вставит.
        // Кадром запись становится, только когда строки в буфере вовсе нет:
        // так выглядит скриншот и копирование из «Фото».
        if text.isEmpty {
            captureImage()
        } else if let raw = pasteboard.string(forType: .string) {
            captureText(raw)
        }
    }

    private func captureText(_ text: String) {
        // Тот же текст скопировали снова — поднимаем запись, а не дублируем.
        if let index = entries.firstIndex(where: { !$0.isImage && $0.text == text }) {
            var existing = entries.remove(at: index)
            existing.date = Date()
            entries.insert(existing, at: 0)
        } else {
            entries.insert(ClipboardEntry(text: text), at: 0)
        }

        trimToLimit()
        sortAndPersist()
    }

    /// Сохраняет кадр из буфера файлом: в истории он должен пережить и
    /// следующее копирование, и перезапуск, и его же надо отдавать наружу
    /// при перетаскивании.
    private func captureImage() {
        guard let png = pngFromPasteboard() else { return }
        let hash = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()

        // Тот же кадр уже лежит в истории — поднимаем его наверх.
        if let index = entries.firstIndex(where: { $0.imageHash == hash }) {
            var existing = entries.remove(at: index)
            existing.date = Date()
            entries.insert(existing, at: 0)
            sortAndPersist()
            return
        }

        let name = "\(UUID().uuidString).png"
        let url = Self.imagesDirectory.appendingPathComponent(name)
        guard (try? png.write(to: url, options: .atomic)) != nil else { return }

        let size = NSImage(data: png)?.size ?? .zero
        let label = "\(Int(size.width.rounded())) × \(Int(size.height.rounded()))"
        entries.insert(
            ClipboardEntry(text: label, imageFile: name, imageHash: hash),
            at: 0
        )

        trimToLimit()
        sortAndPersist()
    }

    /// PNG из буфера. TIFF — то, во что macOS кладёт вырезанный кусок экрана;
    /// перегоняем его в PNG: он меньше и универсальнее.
    private func pngFromPasteboard() -> Data? {
        if let data = pasteboard.data(forType: .png) { return data }
        guard let tiff = pasteboard.data(forType: .tiff) else { return nil }
        return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    }

    private func trimToLimit() {
        var unpinnedSeen = 0
        var imagesSeen = 0
        var dropped: [ClipboardEntry] = []

        entries = entries.filter { entry in
            if entry.isPinned { return true }
            unpinnedSeen += 1
            if entry.isImage { imagesSeen += 1 }
            let keep = unpinnedSeen <= limit && (!entry.isImage || imagesSeen <= imageLimit)
            if !keep { dropped.append(entry) }
            return keep
        }

        discardImages(of: dropped)
    }

    /// Файлы выпавших записей не оставляем: на них уже никто не сошлётся.
    private func discardImages(of removed: [ClipboardEntry]) {
        for entry in removed {
            guard let url = entry.imageURL else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func sortAndPersist() {
        entries.sort { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.date > rhs.date
        }
        persist()
    }

    private func persist() {
        guard settings.persistClipboard else { return }
        store.save(entries)
    }
}
