import AppKit

struct TrashItem: Identifiable, Hashable {
    let id: String
    let url: URL
    let name: String
    let isDirectory: Bool
}

/// Содержимое корзины и операции над ней.
@MainActor
final class TrashStore: ObservableObject {
    @Published private(set) var items: [TrashItem] = []

    private let fileManager = FileManager.default
    private var timer: Timer?

    private var trashURL: URL? {
        try? fileManager.url(
            for: .trashDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
    }

    init() {
        reload()
    }

    func start() {
        guard timer == nil else { return }
        // Корзина меняется редко, да и смотреть в неё часто незачем.
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    /// Перекладывает файлы в корзину. Операция обратимая — файл можно
    /// вернуть из Finder, поэтому подтверждения не спрашиваем.
    @discardableResult
    func moveToTrash(_ urls: [URL]) -> Int {
        var moved = 0
        for url in urls {
            do {
                try fileManager.trashItem(at: url, resultingItemURL: nil)
                moved += 1
            } catch {
                continue
            }
        }
        if moved > 0 { reload() }
        return moved
    }

    func revealInFinder() {
        guard let trashURL else { return }
        NSWorkspace.shared.open(trashURL)
    }

    /// Необратимо удаляет всё. Вызывать только после подтверждения —
    /// вернуть эти файлы будет уже неоткуда.
    func empty() {
        let script = "tell application \"Finder\" to empty trash"
        guard let apple = NSAppleScript(source: script) else { return }
        var error: NSDictionary?
        apple.executeAndReturnError(&error)
        reload()
    }

    private func reload() {
        guard let trashURL else {
            items = []
            return
        }
        let contents = (try? fileManager.contentsOfDirectory(
            at: trashURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        items = contents.map { url in
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return TrashItem(
                id: url.path,
                url: url,
                name: url.lastPathComponent,
                isDirectory: isDirectory
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
