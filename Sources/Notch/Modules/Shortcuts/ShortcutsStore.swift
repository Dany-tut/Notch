import Foundation

/// Быстрые команды пользователя через системную утилиту `shortcuts`.
///
/// Своего API к Быстрым командам у macOS нет — только командная строка:
/// `shortcuts list` и `shortcuts run`. Утилита лежит в системе, особых прав
/// не просит и под Hardened Runtime запускается как любой процесс. Всё, что
/// спросит сама команда (доступ к файлам, к другим программам), спрашивает
/// уже процесс `shortcuts`, а не мы.
@MainActor
final class ShortcutsStore: ObservableObject {
    struct Shortcut: Identifiable, Hashable {
        /// Идентификатор из `--show-identifiers`: по нему и запускаем —
        /// имена у команд могут совпадать.
        let id: String
        let name: String
    }

    enum Phase: Equatable {
        /// Ещё ни разу не читали.
        case idle
        case loaded
        /// Утилиты нет или она упала — показываем ошибку вместо списка.
        case failed
    }

    enum RunState: Equatable {
        case running
        case done
        case failed(String)
    }

    @Published private(set) var shortcuts: [Shortcut] = []
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var isLoading = false
    @Published private(set) var runs: [String: RunState] = [:]
    @Published private(set) var favorites: [String] {
        didSet { defaults.set(favorites, forKey: Self.favoritesKey) }
    }

    @Published var query = ""
    @Published var isSearching = false {
        didSet { if !isSearching { query = "" } }
    }

    private static let favoritesKey = "shortcuts.favorites"
    private nonisolated static let tool = URL(fileURLWithPath: "/usr/bin/shortcuts")
    /// Как долго список считается свежим: открыли панель второй раз за
    /// минуту — утилиту заново не зовём.
    private static let freshness: TimeInterval = 30

    private let defaults: UserDefaults
    private var loadedAt: Date?
    private var isVisible = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        favorites = defaults.stringArray(forKey: Self.favoritesKey) ?? []
    }

    // MARK: Видимость

    /// Модуль на экране. Кэш показываем сразу, а свежий список читаем,
    /// только если старый успел залежаться.
    func resume() {
        isVisible = true
        if let loadedAt, Date().timeIntervalSince(loadedAt) < Self.freshness { return }
        refresh()
    }

    func suspend() {
        isVisible = false
    }

    func refresh() {
        guard isVisible, !isLoading else { return }
        isLoading = true
        Task {
            let result = await Self.execute(["list", "--show-identifiers"])
            isLoading = false
            guard result.status == 0 else {
                // Упавшее чтение не стирает уже показанный список.
                if shortcuts.isEmpty { phase = .failed }
                return
            }
            shortcuts = Self.parse(result.output)
            phase = .loaded
            loadedAt = Date()
        }
    }

    // MARK: Список

    /// Избранные — сверху, в порядке закрепления; остальные по алфавиту,
    /// как в самом приложении Быстрые команды.
    var visible: [Shortcut] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        let matching = needle.isEmpty
            ? shortcuts
            : shortcuts.filter { $0.name.localizedStandardContains(needle) }
        let pinned = favorites.compactMap { id in matching.first { $0.id == id } }
        let rest = matching
            .filter { !favorites.contains($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return pinned + rest
    }

    func isFavorite(_ shortcut: Shortcut) -> Bool { favorites.contains(shortcut.id) }

    func toggleFavorite(_ shortcut: Shortcut) {
        if let index = favorites.firstIndex(of: shortcut.id) {
            favorites.remove(at: index)
        } else {
            favorites.append(shortcut.id)
        }
    }

    // MARK: Запуск

    func run(_ shortcut: Shortcut) {
        guard runs[shortcut.id] != .running else { return }
        runs[shortcut.id] = .running
        Task {
            let result = await Self.execute(["run", shortcut.id])
            let state: RunState = result.status == 0
                ? .done
                : .failed(Self.firstLine(of: result.error))
            runs[shortcut.id] = state
            // Отметка висит недолго: успех — пару секунд, ошибка — дольше,
            // чтобы успеть прочесть подсказку.
            try? await Task.sleep(for: .seconds(state == .done ? 2.5 : 6))
            if runs[shortcut.id] == state { runs[shortcut.id] = nil }
        }
    }

    // MARK: Утилита

    /// Строки вида `Имя команды (C00B4BD7-BA95-445D-8FDD-4E980FE05B5A)`.
    /// Имя может само содержать скобки, поэтому идентификатор берём с
    /// конца строки.
    nonisolated static func parse(_ output: String) -> [Shortcut] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let line = line.trimmingCharacters(in: .whitespaces)
            guard line.hasSuffix(")"),
                  let open = line.range(of: " (", options: .backwards)
            else { return nil }
            let id = String(line[open.upperBound..<line.index(before: line.endIndex)])
            let name = String(line[..<open.lowerBound])
            guard UUID(uuidString: id) != nil, !name.isEmpty else { return nil }
            return Shortcut(id: id, name: name)
        }
    }

    private nonisolated static func firstLine(of text: String) -> String {
        text.split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }

    private struct Result: Sendable {
        let status: Int32
        let output: String
        let error: String
    }

    /// Запуск утилиты не на главном потоке: команда может работать долго
    /// или ждать ответа пользователя в своём окне.
    private nonisolated static func execute(_ arguments: [String]) async -> Result {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = tool
            process.arguments = arguments
            let out = Pipe()
            let err = Pipe()
            process.standardOutput = out
            process.standardError = err
            process.standardInput = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                return Result(status: -1, output: "", error: error.localizedDescription)
            }
            // Читаем до конца раньше, чем ждём выхода: забитый канал иначе
            // остановил бы процесс навсегда. Ошибки читаем параллельно.
            let errorData = Task.detached { err.fileHandleForReading.readDataToEndOfFile() }
            let outputData = out.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return Result(
                status: process.terminationStatus,
                output: String(decoding: outputData, as: UTF8.self),
                error: String(decoding: await errorData.value, as: UTF8.self)
            )
        }.value
    }
}
