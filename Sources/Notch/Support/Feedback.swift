import AppKit

/// Звук, который проигрывается при появлении панели.
///
/// Часть вариантов — системные из `/System/Library/Sounds`, часть лежит
/// в ресурсах приложения. Хранится по `rawValue`, поэтому переименование
/// вариантов ломает сохранённую настройку.
enum NotchSound: String, CaseIterable, Identifiable, Sendable {
    case none

    // Свои, короткие и сухие.
    case click
    case hover
    case pop

    // Системные Apple.
    case systemPop
    case systemTink
    case systemBottle
    case systemMorse
    case systemPurr
    case systemSubmarine

    var id: String { rawValue }

    /// Имя в списке. Системные пишем как у Apple, свои — переводим.
    var displayName: String {
        switch self {
        case .none: return ""            // подставляется локализованно
        case .click: return "Click"
        case .hover: return "Hover"
        case .pop: return "Pop (custom)"
        case .systemPop: return "Pop"
        case .systemTink: return "Tink"
        case .systemBottle: return "Bottle"
        case .systemMorse: return "Morse"
        case .systemPurr: return "Purr"
        case .systemSubmarine: return "Submarine"
        }
    }

    /// Файл в ресурсах приложения, если звук наш.
    fileprivate var bundledResource: String? {
        switch self {
        case .click: return "click"
        case .hover: return "hover"
        case .pop: return "pop"
        default: return nil
        }
    }

    /// Имя системного звука, если он из системы.
    fileprivate var systemName: String? {
        switch self {
        case .systemPop: return "Pop"
        case .systemTink: return "Tink"
        case .systemBottle: return "Bottle"
        case .systemMorse: return "Morse"
        case .systemPurr: return "Purr"
        case .systemSubmarine: return "Submarine"
        default: return nil
        }
    }
}

/// Короткий отклик на появление панели: тактильный «тук» по трекпаду плюс
/// приглушённый звук. Оба канала независимо выключаются в настройках.
@MainActor
final class Feedback {
    private let settings: AppSettings

    /// NSSound нельзя переиграть, пока он звучит, поэтому держим по экземпляру
    /// на вариант и переиспользуем их.
    private var cache: [NotchSound: NSSound] = [:]

    /// Не даём отклику сработать дважды подряд, если панель дёрнулась.
    private var lastPlayed: Date = .distantPast
    private let minimumInterval: TimeInterval = 0.25

    init(settings: AppSettings) {
        self.settings = settings
    }

    func panelDidAppear() {
        let now = Date()
        guard now.timeIntervalSince(lastPlayed) > minimumInterval else { return }
        lastPlayed = now

        if settings.hapticsEnabled {
            // .alignment — самый сухой из системных паттернов, одиночный щелчок.
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        play(settings.sound)
    }

    /// Проигрывает звук прямо сейчас — для кнопки прослушивания в настройках.
    func preview(_ sound: NotchSound) {
        play(sound, ignoringEnabledFlag: true)
    }

    private func play(_ sound: NotchSound, ignoringEnabledFlag: Bool = false) {
        guard ignoringEnabledFlag || settings.soundEnabled else { return }
        guard sound != .none, let player = loadSound(sound) else { return }
        player.volume = Float(settings.feedbackVolume)
        if player.isPlaying { player.stop() }
        player.play()
    }

    /// Какие звуки реально нашлись — печатается в режиме снимка.
    func diagnostics() -> String {
        NotchSound.allCases
            .filter { $0 != .none }
            .map { "\($0.rawValue)=\(loadSound($0) == nil ? "нет" : "ок")" }
            .joined(separator: " ")
    }

    private func loadSound(_ sound: NotchSound) -> NSSound? {
        if let cached = cache[sound] { return cached }

        var loaded: NSSound?
        if let resource = sound.bundledResource,
           let url = Bundle.module.url(forResource: resource, withExtension: "wav", subdirectory: "Sounds")
            ?? Bundle.module.url(forResource: resource, withExtension: "wav") {
            loaded = NSSound(contentsOf: url, byReference: false)
        } else if let name = sound.systemName {
            loaded = NSSound(named: NSSound.Name(name))
        }

        cache[sound] = loaded
        return loaded
    }
}

// MARK: - Тик

extension Feedback {
    /// Сухой щелчок там, где что-то раскрылось само: превью под зажатым
    /// пальцем появляется без клика, и без отклика это читается как сбой —
    /// вроде ничего не нажимал, а панель сменилась.
    ///
    /// Звук здесь не тот, что выбран для панели: выбранный бывает густым
    /// (Submarine, Purr), а на мелкое движение нужен самый тихий тик. Громкость
    /// тоже ниже — отклик должен быть на грани слышимости.
    static func tick(_ settings: AppSettings) {
        if settings.hapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        guard settings.soundEnabled, let sound = tickSound else { return }
        sound.volume = Float(min(settings.feedbackVolume, 0.2))
        if sound.isPlaying { sound.stop() }
        sound.play()
    }

    /// Свой «клик», а если его нет в бандле — системный Tink.
    private static let tickSound: NSSound? = {
        if let url = Bundle.module.url(forResource: "click", withExtension: "wav", subdirectory: "Sounds")
            ?? Bundle.module.url(forResource: "click", withExtension: "wav") {
            return NSSound(contentsOf: url, byReference: false)
        }
        return NSSound(named: NSSound.Name("Tink"))
    }()
}
