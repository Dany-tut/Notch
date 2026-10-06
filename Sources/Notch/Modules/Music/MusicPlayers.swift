import AppKit

/// Плеер, которым Notch умеет управлять.
///
/// Скриптуемых мы читаем целиком, остальным — только шлём медиа-клавиши:
/// метаданные они наружу не отдают, но кнопки до них доходят.
struct MusicPlayer: Identifiable, Sendable {
    let bundleID: String
    /// Имя на случай, если приложение не установлено и спросить некого.
    let fallbackName: String
    /// Как к приложению обращается AppleScript. nil — не скриптуемое.
    let scriptName: String?
    /// Папка в Application Support, где Electron-плеер держит кэш
    /// Chromium. Оттуда берётся обложка: в дереве доступа её нет.
    let chromiumCacheFolder: String?
    /// Панель плеера читается и нажимается через «Универсальный доступ».
    /// Так живут Electron-приложения: слов они не понимают, но свой DOM
    /// показывают деревом доступа целиком.
    let usesAccessibility: Bool
    /// Spotify отдаёт длительность в миллисекундах, Music — в секундах.
    let durationInMilliseconds: Bool

    var id: String { bundleID }

    static let all: [MusicPlayer] = [
        MusicPlayer(
            bundleID: "com.apple.Music",
            fallbackName: "Music",
            scriptName: "Music",
            chromiumCacheFolder: nil,
            usesAccessibility: false,
            durationInMilliseconds: false
        ),
        MusicPlayer(
            bundleID: "com.spotify.client",
            fallbackName: "Spotify",
            scriptName: "Spotify",
            chromiumCacheFolder: nil,
            usesAccessibility: false,
            durationInMilliseconds: true
        ),
        MusicPlayer(
            bundleID: "ru.yandex.desktop.music",
            fallbackName: "Яндекс Музыка",
            scriptName: nil,
            chromiumCacheFolder: "YandexMusic",
            usesAccessibility: true,
            durationInMilliseconds: false
        )
    ]

    static var scriptable: [MusicPlayer] { all.filter { $0.scriptName != nil } }

    static var accessible: [MusicPlayer] { all.filter(\.usesAccessibility) }

    /// В списке выбора показываем только то, что есть на диске.
    static var installed: [MusicPlayer] { all.filter { $0.appURL != nil } }

    static func player(for bundleID: String) -> MusicPlayer? {
        all.first { $0.bundleID == bundleID }
    }

    var appURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    /// Имя берём с диска — так плеер называется на языке системы.
    var displayName: String {
        guard let appURL else { return fallbackName }
        return appURL.deletingPathExtension().lastPathComponent
    }

    var runningApp: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    var isRunning: Bool { runningApp != nil }

    func launch() {
        guard let appURL else { return }
        NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// Кем управляют кнопки: тем, что играет сейчас, или выбранным плеером.
enum MusicSource: Hashable, Sendable {
    case auto
    case player(String)

    var bundleID: String? {
        if case let .player(id) = self { return id }
        return nil
    }

    var storageValue: String { bundleID ?? "auto" }

    init(storageValue: String) {
        self = storageValue == "auto" ? .auto : .player(storageValue)
    }
}
