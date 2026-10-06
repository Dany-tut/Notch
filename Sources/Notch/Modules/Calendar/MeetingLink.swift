import EventKit
import Foundation

/// Ссылка на видеовстречу внутри события.
///
/// Единого поля у EventKit нет: Zoom кладёт ссылку в `url`, Meet — в заметки,
/// Teams — в место проведения. Поэтому просматриваем всё подряд и берём
/// первое, что похоже на известный сервис.
enum MeetingLink {
    private static let hosts = [
        "zoom.us": "Zoom",
        "meet.google.com": "Google Meet",
        "teams.microsoft.com": "Teams",
        "teams.live.com": "Teams",
        "webex.com": "Webex",
        "whereby.com": "Whereby",
        "discord.gg": "Discord",
        "meet.jit.si": "Jitsi",
        "telemost.yandex.ru": "Телемост",
        "ktalk.ru": "Контур.Толк"
    ]

    struct Found {
        let url: URL
        /// Название сервиса — его показываем на кнопке.
        let service: String
    }

    static func find(in event: EKEvent) -> Found? {
        if let url = event.url, let found = match(url) { return found }

        for text in [event.location, event.notes].compactMap({ $0 }) {
            if let found = firstLink(in: text) { return found }
        }
        return nil
    }

    private static func match(_ url: URL) -> Found? {
        guard let host = url.host()?.lowercased() else { return nil }
        for (needle, service) in hosts where host.hasSuffix(needle) || host.contains(needle) {
            return Found(url: url, service: service)
        }
        return nil
    }

    /// Первая ссылка известного сервиса в свободном тексте.
    private static func firstLink(in text: String) -> Found? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return nil }

        let range = NSRange(text.startIndex..., in: text)
        for result in detector.matches(in: text, range: range) {
            if let url = result.url, let found = match(url) { return found }
        }
        return nil
    }
}
