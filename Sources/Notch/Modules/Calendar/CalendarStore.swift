import AppKit
import EventKit
import SwiftUI

/// Ближайшие встречи из системного Календаря.
@MainActor
final class CalendarStore: ObservableObject {
    enum Access: Equatable {
        case unknown
        case granted
        case denied
        /// Приложение запущено не бандлом (`swift run`) — у процесса нет ни
        /// идентификатора, ни описаний доступа, так что запрашивать нечего:
        /// система молча откажет и в список «Календари» нас не добавит.
        case unavailable
    }

    @Published private(set) var access: Access = .unknown
    @Published private(set) var events: [EKEvent] = []

    /// Месяц, который сейчас показывает сетка (первое число, начало дня).
    /// Тем же правилом «по середине недели», что и лента, — иначе для
    /// недели на стыке месяцев шапка при старте и шапка при прокрутке
    /// называли бы разные месяцы для одной и той же недели.
    @Published private(set) var month: Date = CalendarGrid.headerMonth(
        forWeekStart: CalendarGrid.startOfWeek(Date())
    )
    /// День, встречи которого открыты рядом с сеткой.
    @Published private(set) var selectedDay: Date = Calendar.current.startOfDay(for: Date())
    /// Встречи видимой сетки, разложенные по дням: сетка показывает точки,
    /// а правая колонка — список выбранного дня, и оба берут их отсюда.
    @Published private(set) var monthEvents: [Date: [EKEvent]] = [:]

    /// Общий с Напоминаниями — один на приложение.
    private let store: EKEventStore
    private var refreshTimer: Timer?
    /// Какой отрезок уже прочитан — чтобы не дёргать EventKit на каждый
    /// оборот колеса.
    private var loadedRange: Range<Date>?

    /// Есть ли у нас Info.plist с идентификатором и текстом запроса —
    /// без этого EventKit не сможет показать системный диалог.
    private static var isProperlyBundled: Bool {
        Bundle.main.bundleIdentifier != nil
            && Bundle.main.object(forInfoDictionaryKey: "NSCalendarsFullAccessUsageDescription") != nil
    }

    init(store: EKEventStore) {
        self.store = store
        refreshAccess()
    }

    func start() {
        guard refreshTimer == nil else { return }
        // Календарь меняется редко — раз в минуту достаточно.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        if access == .granted { reload() }
    }

    /// Листает сетку на месяц вперёд или назад.
    func step(months: Int) {
        let base = Calendar.current.date(byAdding: .month, value: months, to: month) ?? month
        show(month: base)
    }

    func show(month newMonth: Date) {
        month = CalendarGrid.startOfMonth(newMonth)
        loadWindow()
    }

    func select(day: Date) {
        let day = Calendar.current.startOfDay(for: day)
        selectedDay = day
        // Лента прокручивается свободно, так что уводить её к выбранному дню
        // не надо — достаточно догрузить встречи вокруг него. Месяц шапки —
        // тем же правилом недели, что и everywhere: иначе тап по хвостовому
        // числу соседнего месяца в текущей строке подписывал бы шапку не
        // тем месяцем, что показывает сама строка.
        let headerMonth = CalendarGrid.headerMonth(forWeekStart: CalendarGrid.startOfWeek(day))
        if !Calendar.current.isDate(headerMonth, equalTo: month, toGranularity: .month) {
            month = headerMonth
            loadWindow()
        }
    }

    /// Возвращает сетку к сегодняшнему дню. Месяц в шапке — по правилу
    /// недели, тому же, что использует прокрутка: иначе для недели на
    /// стыке месяцев кнопка называла бы месяц иначе, чем сама лента после
    /// того как доедет и её досмотрит видимость.
    func goToToday() {
        let today = Calendar.current.startOfDay(for: Date())
        selectedDay = today
        show(month: CalendarGrid.headerMonth(forWeekStart: CalendarGrid.startOfWeek(today)))
    }

    func events(on day: Date) -> [EKEvent] {
        monthEvents[Calendar.current.startOfDay(for: day)] ?? []
    }

    func requestAccess() {
        guard access != .unavailable else { return }
        Task {
            let granted = (try? await store.requestFullAccessToEvents()) ?? false
            // Диалог могли и не показать (например, доступ уже запрещён) —
            // верим системе, а не результату вызова.
            refreshAccess()
            if !granted, access == .unknown { access = .denied }
            if access == .granted { reload() }
        }
    }

    /// Перечитывает разрешение у системы: его могли выдать или отобрать
    /// в Системных настройках, пока панель висела открытой.
    func refreshAccess() {
        guard Self.isProperlyBundled else {
            access = .unavailable
            return
        }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: access = .granted
        // Доступ «только запись» нам не годится: читать встречи он не даёт.
        case .denied, .restricted, .writeOnly: access = .denied
        default: access = .unknown
        }
        if access == .granted, events.isEmpty { reload() }
    }

    /// Открывает нужный раздел Системных настроек — искать его руками долго.
    func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Встречи от «сейчас» и на неделю вперёд, без целодневных —
    /// в панели полезно именно то, к чему нужно успеть.
    private func reload() {
        guard access == .granted else { return }
        let now = Date()
        guard let end = Calendar.current.date(byAdding: .day, value: 7, to: now) else { return }

        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        events = store.events(matching: predicate)
            .filter { !$0.isAllDay && ($0.endDate ?? now) > now }
            .sorted { ($0.startDate ?? now) < ($1.startDate ?? now) }

        loadedRange = nil
        loadWindow()
    }

    /// Встречи вокруг того месяца, что сейчас в шапке: лента прокручивается
    /// непрерывно, поэтому держим запас по три месяца в обе стороны и
    /// перечитываем, только когда из него выехали.
    private func loadWindow() {
        guard access == .granted else { return }
        let calendar = Calendar.current
        guard let first = calendar.date(byAdding: .month, value: -3, to: month),
              let end = calendar.date(byAdding: .month, value: 4, to: month)
        else { return }
        // Запас ещё держит текущий месяц — читать заново нечего.
        if let loaded = loadedRange, loaded.contains(month),
           let inner = calendar.date(byAdding: .month, value: 1, to: loaded.lowerBound),
           let outer = calendar.date(byAdding: .month, value: -1, to: loaded.upperBound),
           (inner..<outer).contains(month) {
            return
        }
        loadedRange = first..<end

        let predicate = store.predicateForEvents(withStart: first, end: end, calendars: nil)
        var byDay: [Date: [EKEvent]] = [:]
        for event in store.events(matching: predicate) {
            guard let start = event.startDate else { continue }
            byDay[calendar.startOfDay(for: start), default: []].append(event)
        }
        // Целодневные наверх, остальные по времени начала — так список дня
        // читается сверху вниз ровно так, как день и идёт.
        for (day, list) in byDay {
            byDay[day] = list.sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                return (lhs.startDate ?? day) < (rhs.startDate ?? day)
            }
        }
        monthEvents = byDay
    }
}

/// Сетка месяца: полные недели с хвостами соседей, как в системном календаре.
enum CalendarGrid {
    static func startOfMonth(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    /// Недели ленты: начала недель от `back` месяцев назад до `forward`
    /// вперёд. Лента одна на всё время жизни панели, поэтому считаем её от
    /// сегодняшнего дня, а не от месяца в шапке — иначе список пересобирался
    /// бы под курсором.
    static func weeks(
        back: Int,
        forward: Int,
        from date: Date = Date(),
        calendar: Calendar = .current
    ) -> [Date] {
        guard let from = calendar.date(byAdding: .month, value: -back, to: startOfMonth(date, calendar: calendar)),
              let to = calendar.date(byAdding: .month, value: forward, to: startOfMonth(date, calendar: calendar))
        else { return [] }
        var week = startOfWeek(from, calendar: calendar)
        var result: [Date] = []
        while week < to {
            result.append(week)
            guard let next = calendar.date(byAdding: .day, value: 7, to: week) else { break }
            week = next
        }
        return result
    }

    static func startOfWeek(_ date: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let lead = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -lead, to: day) ?? day
    }

    /// Месяц, который лента подпишет в шапке для недели, начинающейся с
    /// `week`, — по её середине, а не по первому дню: неделя на стыке
    /// месяцев (скажем, 28 сентября — 4 октября) иначе читалась бы то
    /// сентябрём, то октябрём в зависимости от того, кто её месяц считает —
    /// кнопка «Сегодня» или прокрутка. Оба должны сходиться в одной точке,
    /// поэтому оба берут её отсюда.
    static func headerMonth(forWeekStart week: Date, calendar: Calendar = .current) -> Date {
        let middle = calendar.date(byAdding: .day, value: 3, to: week) ?? week
        return startOfMonth(middle, calendar: calendar)
    }

    /// Подписи дней недели в порядке, принятом в системе (у нас неделя с пн).
    static func weekdaySymbols(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return (0..<7).map { symbols[($0 + shift) % 7] }
    }
}
