import SwiftUI

/// Событие, ради которого схлопнутый вырез на пару секунд превращается
/// в плашку: сменился трек, воткнули зарядку, подключились наушники.
///
/// От кружков острова это отличается тем, что активность живёт временем,
/// а не состоянием: показалась, договорила и ушла.
struct NotchActivity: Identifiable, Equatable {
    /// Повод. По нему же включаются и выключаются активности в настройках.
    enum Kind: String, CaseIterable, Identifiable, Sendable {
        case music
        case power
        case lockScreen
        case audioDevice
        case focus
        case calendar
        case timer
        case levels

        var id: String { rawValue }

        /// Включается только руками. Громкость и яркость перехватывают
        /// системные клавиши и требуют «Универсального доступа» — такое не
        /// включают за пользователя, даже по умолчанию.
        var isOptIn: Bool { self == .levels }

        var titleKey: L10n.Key {
            switch self {
            case .music: return .activityMusic
            case .power: return .activityPower
            case .lockScreen: return .activityLockScreen
            case .audioDevice: return .activityAudioDevice
            case .focus: return .activityFocus
            case .calendar: return .activityCalendar
            case .timer: return .activityTimer
            case .levels: return .activityLevels
            }
        }

        var symbol: String {
            switch self {
            case .music: return "music.note"
            case .power: return "battery.100percent.bolt"
            case .lockScreen: return "lock"
            case .audioDevice: return "airpods.pro"
            case .focus: return "moon"
            case .calendar: return "calendar"
            case .timer: return "timer"
            case .levels: return "speaker.wave.2"
            }
        }

        /// Кого можно перебить. Блокировка экрана важнее смены трека.
        var priority: Int {
            switch self {
            // Звонок ждать не может: он и есть то, ради чего его заводили.
            // Ответ на нажатие клавиши: его ждут прямо сейчас, и вернуть
            // прежнюю плашку через полторы секунды дешевле, чем промолчать.
            case .levels: return 50
            case .timer: return 48
            case .calendar: return 45
            case .lockScreen: return 40
            case .power: return 30
            case .audioDevice: return 20
            case .focus: return 15
            case .music: return 10
            }
        }

        /// Модуль, который откроется по клику. Нет — значит клик не по делу.
        var moduleID: String? {
            switch self {
            case .music: return "music"
            case .timer: return "timers"
            case .calendar: return "calendar"
            // Там выбор выхода звука — ради него на плашку и нажимают.
            case .levels: return "music"
            default: return nil
            }
        }
    }

    /// Личность плашки, а не значения: пока на экране один и тот же трек,
    /// она не меняется, сколько бы раз ни подвинулся прогресс. Вид сверяет
    /// с ней свои анимации, и новый `id` на каждом тике заставлял его
    /// переигрывать появление — текст растягивало по буквам, а обложка
    /// моргала на каждой секунде.
    var id = UUID()
    let kind: Kind
    /// Иконка слева. Если есть обложка — она её перекрывает.
    var symbol: String
    var artwork: Data?
    var title: String
    var subtitle: String?
    /// Полоска прогресса под текстом: заряд, громкость, позиция в треке.
    var progress: Double?
    var tint: Color
    /// Сколько держать на экране. Ноль — до явного снятия.
    var duration: TimeInterval
    /// Куда ведёт нажатие, если не в модуль: ссылка на созвон. С ней
    /// плашка — это кнопка «Подключиться», а не просто напоминание.
    var link: URL?

    static func == (lhs: NotchActivity, rhs: NotchActivity) -> Bool {
        lhs.id == rhs.id
    }

    /// Совпадают по сути — значит, показывать заново не нужно, достаточно
    /// обновить текущую и продлить время.
    func isSameSubject(as other: NotchActivity) -> Bool {
        kind == other.kind && title == other.title && subtitle == other.subtitle
    }
}

extension NotchActivity {
    /// Образец для проверки вёрстки из терминала: `NOTCH_ACTIVITY=music`.
    @MainActor
    static func sample(_ kind: Kind, settings: AppSettings) -> NotchActivity {
        switch kind {
        case .music:
            return NotchActivity(
                kind: .music,
                symbol: kind.symbol,
                title: "Bohemian Rhapsody",
                subtitle: "Queen",
                progress: 0.42,
                tint: ActivityTint.pink,
                duration: 0
            )
        case .power:
            return NotchActivity(
                kind: .power,
                symbol: "battery.100percent.bolt",
                title: settings.t(.activityCharging),
                subtitle: "87%",
                progress: 0.87,
                tint: ActivityTint.green,
                duration: 0
            )
        case .lockScreen:
            return NotchActivity(
                kind: .lockScreen,
                symbol: "lock.open",
                title: settings.t(.activityWelcomeBack),
                subtitle: "64%",
                progress: 0.64,
                tint: ActivityTint.indigo,
                duration: 0
            )
        case .audioDevice:
            return NotchActivity(
                kind: .audioDevice,
                symbol: "airpods.pro",
                title: "AirPods Pro",
                subtitle: settings.t(.activityConnected),
                tint: ActivityTint.teal,
                duration: 0
            )
        case .focus:
            return NotchActivity(
                kind: .focus,
                symbol: "moon.fill",
                title: settings.t(.activityFocusOn),
                tint: ActivityTint.indigo,
                duration: 0
            )
        case .calendar:
            return NotchActivity(
                kind: .calendar,
                symbol: "video.fill",
                title: "Daily standup",
                subtitle: "\(settings.t(.calendarJoin)) · " + String(format: settings.t(.calendarStartsIn), "5"),
                tint: ActivityTint.red,
                duration: 0,
                link: URL(string: "https://meet.google.com/")
            )
        case .levels:
            return NotchActivity(
                kind: .levels,
                symbol: "speaker.wave.2.fill",
                title: "MacBook Pro Speakers",
                subtitle: "56 %",
                progress: 0.56,
                tint: ActivityTint.teal,
                duration: 0
            )
        case .timer:
            return NotchActivity(
                kind: .timer,
                symbol: "timer",
                title: settings.t(.timersDone),
                subtitle: "25:00",
                tint: ActivityTint.orange,
                duration: 0
            )
        }
    }
}

/// Цвета плашек. Те же, что у плиток настроек, — одна палитра на всё
/// приложение читается спокойнее, чем набор случайных оттенков.
enum ActivityTint {
    static let pink = Color(red: 0.90, green: 0.32, blue: 0.53)
    static let green = Color(red: 0.20, green: 0.68, blue: 0.38)
    static let orange = Color(red: 0.94, green: 0.55, blue: 0.16)
    static let red = Color(red: 0.87, green: 0.30, blue: 0.27)
    static let indigo = Color(red: 0.42, green: 0.38, blue: 0.86)
    static let teal = Color(red: 0.16, green: 0.66, blue: 0.66)
    static let blue = Color(red: 0.24, green: 0.50, blue: 0.96)
}
