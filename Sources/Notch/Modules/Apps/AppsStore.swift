import AppKit

/// Программа на диске.
struct AppEntry: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    var id: String { url.path }
}

/// Папка программ — то, чего больше всего не хватает после Launchpad.
struct AppFolder: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    /// Пути к программам. Храним пути, а не bundle id: у двух копий одной
    /// программы (бета и релиз) id один, а человек держит их отдельно.
    var items: [String]
}

/// Раскладка пользователя: что закреплено сверху и какие есть папки.
/// Программа живёт в одном месте — как в Launchpad: закреплённая или
/// разложенная по папке в общем списке уже не повторяется.
struct AppsLayout: Codable {
    var pinned: [String] = []
    var folders: [AppFolder] = []
}

/// Программы для модуля «Приложения» — замены Launchpad, который убрали
/// из macOS 26.
///
/// Список читаем с диска при открытии модуля, и не чаще раза в минуту:
/// программы ставят редко, а обход папок — это сотни `stat`. Фонового
/// слежения за папками нет вовсе — пока модуль закрыт, он ничего не стоит.
@MainActor
final class AppsStore: ObservableObject {
    @Published private(set) var apps: [AppEntry] = []
    @Published private(set) var layout: AppsLayout
    @Published private(set) var running: Set<String> = []

    @Published var query = ""
    @Published var isSearching = false {
        didSet { if !isSearching { query = "" } }
    }
    /// Раскрытая папка. Живёт в памяти: при следующем открытии панели
    /// человек ждёт увидеть все программы, а не то, где бросил.
    @Published var openFolderID: UUID?

    private let storage = JSONStore<AppsLayout>(filename: "apps.json")
    private var lastScan: Date?
    private var icons: [String: NSImage] = [:]

    init() {
        layout = storage.load().first ?? AppsLayout()
    }

    // MARK: - Список

    func refreshIfNeeded() {
        running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.path })
        if let lastScan, Date().timeIntervalSince(lastScan) < 60 { return }
        lastScan = Date()
        Task {
            let found = await Task.detached(priority: .utility) { Self.scan() }.value
            apps = found
            prune()
        }
    }

    /// Где лежат программы. Вложенные папки смотрим на один уровень:
    /// так находятся и «Утилиты», и наборы вроде «Adobe Photoshop 2026».
    nonisolated private static func scan() -> [AppEntry] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            home.appendingPathComponent("Applications")
        ]
        var seen: Set<String> = []
        var result: [AppEntry] = []

        func add(_ url: URL) {
            let path = url.resolvingSymlinksInPath().path
            guard seen.insert(path).inserted else { return }
            let name = fm.displayName(atPath: url.path)
            result.append(AppEntry(
                url: url,
                name: name.hasSuffix(".app") ? String(name.dropLast(4)) : name
            ))
        }

        for root in roots {
            let items = (try? fm.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            )) ?? []
            for item in items {
                if item.pathExtension == "app" {
                    add(item)
                } else if (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    let nested = (try? fm.contentsOfDirectory(
                        at: item, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
                    )) ?? []
                    nested.filter { $0.pathExtension == "app" }.forEach(add)
                }
            }
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Удалённые программы уходят из раскладки сами — иначе в папке
    /// остаётся дырка на месте программы, которой уже нет.
    private func prune() {
        let existing = Set(apps.map(\.id))
        var next = layout
        next.pinned.removeAll { !existing.contains($0) }
        for index in next.folders.indices {
            next.folders[index].items.removeAll { !existing.contains($0) }
        }
        next.folders.removeAll { $0.items.isEmpty }
        if next.pinned != layout.pinned || next.folders != layout.folders { commit(next) }
    }

    private var byPath: [String: AppEntry] {
        Dictionary(apps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var pinnedApps: [AppEntry] {
        let map = byPath
        return layout.pinned.compactMap { map[$0] }
    }

    func items(of folder: AppFolder) -> [AppEntry] {
        let map = byPath
        return folder.items.compactMap { map[$0] }
    }

    var openFolder: AppFolder? {
        openFolderID.flatMap { id in layout.folders.first { $0.id == id } }
    }

    /// Всё, что не закреплено и не разложено по папкам.
    var loose: [AppEntry] {
        let placed = Set(layout.pinned + layout.folders.flatMap(\.items))
        return apps.filter { !placed.contains($0.id) }
    }

    /// Поиск идёт по всем программам сразу, включая папки: ищут название,
    /// а не место, куда его когда-то положили.
    var searchResults: [AppEntry] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return apps }
        let hits = apps.filter { $0.name.localizedCaseInsensitiveContains(needle) }
        // Совпадение с начала названия — выше: «Te» ищет Telegram, а не
        // «Инструмент Terminal».
        return hits.sorted { lhs, rhs in
            let l = lhs.name.lowercased().hasPrefix(needle.lowercased())
            let r = rhs.name.lowercased().hasPrefix(needle.lowercased())
            return l && !r
        }
    }

    func folder(containing app: AppEntry) -> AppFolder? {
        layout.folders.first { $0.items.contains(app.id) }
    }

    func isPinned(_ app: AppEntry) -> Bool { layout.pinned.contains(app.id) }

    func isRunning(_ app: AppEntry) -> Bool { running.contains(app.url.path) }

    func icon(for app: AppEntry) -> NSImage {
        if let cached = icons[app.id] { return cached }
        let image = NSWorkspace.shared.icon(forFile: app.url.path)
        icons[app.id] = image
        return image
    }

    // MARK: - Действия

    func launch(_ app: AppEntry) {
        NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration())
    }

    func reveal(_ app: AppEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([app.url])
    }

    /// Закрепить и поставить перед `target` (или в конец). Из папки
    /// программа при этом уходит: место у неё одно.
    func pin(_ path: String, before target: String? = nil) {
        var next = layout
        detach(path, from: &next)
        if let target, let index = next.pinned.firstIndex(of: target) {
            next.pinned.insert(path, at: index)
        } else {
            next.pinned.append(path)
        }
        commit(next)
    }

    func unpin(_ app: AppEntry) {
        var next = layout
        next.pinned.removeAll { $0 == app.id }
        commit(next)
    }

    func newFolder(with app: AppEntry, name: String) {
        var next = layout
        detach(app.id, from: &next)
        next.folders.append(AppFolder(name: name, items: [app.id]))
        commit(next)
    }

    func add(_ path: String, to folderID: UUID) {
        var next = layout
        detach(path, from: &next)
        guard let index = next.folders.firstIndex(where: { $0.id == folderID }) else { return }
        next.folders[index].items.append(path)
        commit(next)
    }

    func removeFromFolder(_ app: AppEntry) {
        var next = layout
        detach(app.id, from: &next)
        commit(next)
    }

    func rename(_ folderID: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let index = layout.folders.firstIndex(where: { $0.id == folderID })
        else { return }
        var next = layout
        next.folders[index].name = trimmed
        commit(next)
    }

    /// Папка уходит, программы из неё возвращаются в общий список.
    func deleteFolder(_ folderID: UUID) {
        var next = layout
        next.folders.removeAll { $0.id == folderID }
        if openFolderID == folderID { openFolderID = nil }
        commit(next)
    }

    /// Убрать программу отовсюду, где она лежит, — перед тем как положить
    /// её в новое место. Опустевшая папка исчезает сама.
    private func detach(_ path: String, from layout: inout AppsLayout) {
        layout.pinned.removeAll { $0 == path }
        for index in layout.folders.indices {
            layout.folders[index].items.removeAll { $0 == path }
        }
        let emptied = layout.folders.filter(\.items.isEmpty).map(\.id)
        layout.folders.removeAll { $0.items.isEmpty }
        if let open = openFolderID, emptied.contains(open) { openFolderID = nil }
    }

    private func commit(_ next: AppsLayout) {
        layout = next
        storage.save([next])
    }
}
