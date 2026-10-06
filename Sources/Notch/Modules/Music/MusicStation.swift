import Foundation

/// Станция Apple Music, принесённая ссылкой.
///
/// Своего списка станций плеер не отдаёт: в AppleScript их нет ни одним
/// объектом — ни среди плейлистов, ни в `radio tuner playlists`. Зато
/// Music понимает `open location`, и ссылка на станцию («Поделиться →
/// Скопировать ссылку») запускает её как обычную. Поэтому список живёт
/// у нас: пользователь приносит ссылку один раз, дальше — клик в полке.
struct MusicStation: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var url: String

    init(id: UUID = UUID(), name: String, url: String) {
        self.id = id
        self.name = name
        self.url = url
    }

    /// Ссылка, по которой вообще есть смысл ходить. Music открывает и
    /// `music://`, и `https://music.apple.com/…`; всё остальное — чужой
    /// адрес, и отдавать его плееру незачем.
    var isPlayable: Bool {
        guard let url = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host?.lowercased() else {
            return url.hasPrefix("music://") || url.hasPrefix("itmss://")
        }
        return host.hasSuffix("music.apple.com") || host.hasSuffix("itunes.apple.com")
    }
}
