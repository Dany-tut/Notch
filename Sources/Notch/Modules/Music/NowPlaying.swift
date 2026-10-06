import AppKit

/// Что сейчас играет — в форме, не зависящей от источника данных.
struct NowPlayingInfo: Equatable {
    var title: String
    var artist: String
    var album: String = ""
    var artwork: Data?
    var elapsed: TimeInterval = 0
    var duration: TimeInterval = 0
    var isPlaying: Bool = false
    /// Имя приложения-источника: «Музыка», «Spotify», «Google Chrome».
    var source: String = ""
    /// Bundle id источника — по нему берём иконку приложения.
    var sourceBundleID: String?
    /// Трек в избранном. nil — источник про избранное ничего не знает,
    /// и звёздочку показывать нечестно: нажать её будет некуда.
    var isFavorite: Bool?
    /// Позицию можно двигать: плеер понимает «встань на такую-то секунду».
    var canSeek: Bool = false

    /// Метаданных нет, но известно, что и где играет: такой режим панель
    /// рисует иначе — иконкой приложения вместо обложки.
    var isSourceOnly: Bool { title.isEmpty && !source.isEmpty }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(elapsed / duration, 0), 1)
    }
}

/// Плейлист медиатеки. Обложек нет намеренно: картинка у плейлиста берётся
/// у его первого трека, и это отдельный запрос к плееру на каждую строку —
/// полка открывалась бы заметно дольше, чем читается список.
struct MusicPlaylist: Identifiable, Equatable {
    /// Постоянный идентификатор плеера: имена повторяются, он — нет.
    let id: String
    let name: String
    let count: Int
}

enum TransportCommand {
    case playPause
    case next
    case previous
}

/// Источник данных о воспроизведении.
///
/// Провайдеров два, потому что универсального пути может не быть: приватный
/// `MediaRemote` видит любой источник, но Apple закрыла его entitlement'ом,
/// а AppleScript видит только конкретные плееры, зато работает всегда.
@MainActor
protocol NowPlayingProvider {
    /// Короткое имя для диагностики.
    var name: String { get }
    func fetch() async -> NowPlayingInfo?
    func send(_ command: TransportCommand)
    /// Перемотка. Умеет не всякий источник — по умолчанию молча ничего.
    func seek(to seconds: TimeInterval)
}

extension NowPlayingProvider {
    func seek(to seconds: TimeInterval) {}
}
