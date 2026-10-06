import AppKit
import ApplicationServices
import EventKit

/// Разрешения системы, без которых часть панели молча не работает.
///
/// Раньше об этом знал только тот, кому рассказали: жесты и горячие клавиши
/// без «Универсального доступа» просто ничего не делают — ни ошибки, ни
/// подсказки. Здесь состояние доступа собрано в одном месте, чтобы панель
/// могла о нём сказать сама.
@MainActor
enum SystemAccess {
    enum State: Equatable {
        case granted
        case missing
        /// Запущено не бандлом (`swift run`): системе нечего запоминать,
        /// и просить бесполезно.
        case unavailable
    }

    /// Собран ли бандл. Без Info.plist система не покажет ни один запрос.
    static var isBundled: Bool { Bundle.main.bundleIdentifier != nil }

    // MARK: - Универсальный доступ

    /// Нужен жестам и горячим клавишам: и те и другие читают события мимо
    /// нашего окна, а это система без разрешения не отдаёт.
    static var accessibility: State {
        guard isBundled else { return .unavailable }
        // Проверка живёт в MediaKeys с тех пор, как доступ был нужен одному
        // плееру. Своей копии здесь нет намеренно: два места, отвечающих на
        // один вопрос, рано или поздно начинают отвечать по-разному.
        return MediaKeys.isTrusted ? .granted : .missing
    }

    /// Системный запрос, а следом — нужный раздел настроек: диалог
    /// показывается лишь раз за всю жизнь записи в TCC, и если его уже
    /// отклоняли, человек остался бы ни с чем.
    static func requestAccessibility() { MediaKeys.requestTrust() }

    /// Открывает Finder на бандле. В списке доступа могут висеть несколько
    /// одноимённых строк от прошлых сборок — считается только эта.
    static func revealApp() { MediaKeys.revealBundle() }

    // MARK: - Календарь

    static var calendar: State {
        guard isBundled else { return .unavailable }
        return switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        default: .missing
        }
    }

    static func openCalendarSettings() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
        )
        if let url { NSWorkspace.shared.open(url) }
    }
}

/// Состояние доступа как наблюдаемое значение.
///
/// Разрешение выдают в Системных настройках — чужом окне, о котором нам
/// никто не сообщит. Поэтому опрашиваем систему, пока настройки открыты:
/// человек возвращается в панель и видит, что доступ уже выдан, а не
/// прежнюю красную плашку.
@MainActor
final class AccessWatch: ObservableObject {
    @Published private(set) var accessibility: SystemAccess.State = .unavailable
    @Published private(set) var calendar: SystemAccess.State = .unavailable

    private var timer: Timer?

    init() { refresh() }

    func refresh() {
        accessibility = SystemAccess.accessibility
        calendar = SystemAccess.calendar
    }

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
