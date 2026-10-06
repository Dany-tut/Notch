import AppKit
import SwiftUI

/// Таймер, секундомер и будильники — одним хозяйством.
///
/// Всё время считается по часам, а не сложением тиков: у таймера хранится
/// момент окончания, у секундомера — момент старта. Тик нужен только для
/// перерисовки. Иначе после сна Мака (тики не идут) таймер отстал бы ровно
/// на столько, сколько машина спала.
@MainActor
final class TimersStore: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable, Sendable {
        case timer, stopwatch, alarm

        var id: String { rawValue }

        var titleKey: L10n.Key {
            switch self {
            case .timer: return .timersTimer
            case .stopwatch: return .timersStopwatch
            case .alarm: return .timersAlarm
            }
        }

        var symbol: String {
            switch self {
            case .timer: return "timer"
            case .stopwatch: return "stopwatch"
            case .alarm: return "alarm"
            }
        }
    }

    /// Будильник: время суток и переключатель. Повтор ежедневный —
    /// разовый будильник на Маке живёт ровно до первого звонка, а это
    /// поведение мы и так даём выключателем.
    struct Alarm: Identifiable, Codable, Equatable {
        var id = UUID()
        var hour: Int
        var minute: Int
        var isOn: Bool = true

        /// «07:05» — часы у будильника всегда 24-часовые: он же не текст,
        /// а число, которое выставляют стрелками.
        var text: String { String(format: "%02d:%02d", hour, minute) }
    }

    /// Кто сейчас звонит. Звонок живёт, пока его не остановят, —
    /// будильник, который сам себя выключил, бесполезен.
    enum Ringing: Equatable {
        case timer
        case alarm(Alarm)
    }

    private enum Keys {
        static let mode = "timers.mode"
        static let duration = "timers.duration"
        static let alarms = "timers.alarms"
        static let draft = "timers.draft"
        static let focusSound = "timers.focusSound"
        static let focusVolume = "timers.focusVolume"
    }

    @Published var mode: Mode {
        didSet { defaults.set(mode.rawValue, forKey: Keys.mode) }
    }

    /// Заданная длительность таймера — с неё же начинается обратный отсчёт.
    @Published private(set) var duration: TimeInterval
    @Published private(set) var remaining: TimeInterval
    @Published private(set) var isTimerRunning = false {
        didSet { if isTimerRunning != oldValue { updateFocusSound() } }
    }

    @Published private(set) var stopwatch: TimeInterval = 0
    @Published private(set) var isStopwatchRunning = false
    @Published private(set) var laps: [TimeInterval] = []

    /// Время, набранное на вкладке будильника, но ещё не заведённое, —
    /// минуты от полуночи. Живёт в сторе, а не в вёрстке: циферблат
    /// слева показывает его же, пока ни один будильник не заведён.
    @Published private(set) var draft: Int {
        didSet { defaults.set(draft, forKey: Keys.draft) }
    }

    @Published private(set) var alarms: [Alarm] = []

    /// Фоновый звук на время таймера. Звучит, только пока таймер идёт:
    /// пауза, сброс и звонок его гасят, а выбор без идущего таймера
    /// просто запоминается.
    @Published var focusSound: FocusSound {
        didSet {
            defaults.set(focusSound.rawValue, forKey: Keys.focusSound)
            updateFocusSound()
        }
    }

    @Published var focusVolume: Double {
        didSet {
            defaults.set(focusVolume, forKey: Keys.focusVolume)
            focusPlayer.setVolume(focusVolume)
        }
    }
    @Published private(set) var ringing: Ringing?

    /// Что показывать у схлопнутого выреза. Отдельный объект, а не поля
    /// стора: тут тикает двадцать раз в секунду ради сотых у секундомера,
    /// и панель, подписанная прямо на стор, перекладывалась бы столько же
    /// раз. Здесь строка меняется раз в секунду — ровно тогда, когда на
    /// кружке правда что-то поменялось.
    let island = TimerIslandState()

    /// Доля пройденного у таймера — для дуги вокруг цифр.
    var timerProgress: Double {
        guard duration > 0 else { return 0 }
        return min(max(1 - remaining / duration, 0), 1)
    }

    private let defaults: UserDefaults
    private let settings: AppSettings
    private weak var activity: ActivityCenter?

    /// Момент, когда таймер должен зазвонить. Пока он стоит на паузе,
    /// здесь `nil`, а остаток лежит в `remaining`.
    private var deadline: Date?
    /// Момент старта секундомера плюс уже накопленное до паузы.
    private var startedAt: Date?
    private var accumulated: TimeInterval = 0

    /// Перерисовка. Живёт, только пока есть что перерисовывать.
    private var tick: Timer?
    /// Раз в секунду — проверка будильников. Отдельно от перерисовки:
    /// будильник должен звонить и тогда, когда ничего не идёт.
    private var watch: Timer?
    /// Докуда будильники уже проверены: между двумя проверками время
    /// могло перескочить (сон Мака), и пропускать звонок нельзя.
    private var checkedUpTo = Date()

    private var ringTimer: Timer?
    private var ringsLeft = 0

    private let focusPlayer = FocusSoundPlayer()

    init(settings: AppSettings, activity: ActivityCenter, defaults: UserDefaults = .standard) {
        self.settings = settings
        self.activity = activity
        self.defaults = defaults
        self.mode = defaults.string(forKey: Keys.mode).flatMap(Mode.init(rawValue:)) ?? .timer
        let stored = defaults.object(forKey: Keys.duration) as? Double ?? 5 * 60
        self.duration = stored
        self.remaining = stored
        self.draft = defaults.object(forKey: Keys.draft) as? Int ?? 8 * 60
        self.focusSound = defaults.string(forKey: Keys.focusSound).flatMap(FocusSound.init(rawValue:)) ?? .off
        self.focusVolume = defaults.object(forKey: Keys.focusVolume) as? Double ?? 0.5
        if let data = defaults.data(forKey: Keys.alarms),
           let list = try? JSONDecoder().decode([Alarm].self, from: data) {
            self.alarms = list
        }
    }

    func start() {
        guard watch == nil else { return }
        checkedUpTo = Date()
        watch = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkAlarms() }
        }
    }

    // MARK: - Таймер

    /// Пресеты в минутах: чай, разминка, помидор, перерыв, час.
    static let presets: [Int] = [1, 3, 5, 10, 25, 45]

    func setDuration(_ seconds: TimeInterval) {
        let clamped = min(max(seconds, 1), 24 * 3600)
        duration = clamped
        defaults.set(clamped, forKey: Keys.duration)
        if isTimerRunning {
            deadline = Date().addingTimeInterval(clamped)
        }
        remaining = clamped
    }

    /// Прибавить на ходу: «ещё пять минут» — самое частое, что делают
    /// с работающим таймером.
    func addToTimer(_ seconds: TimeInterval) {
        if isTimerRunning, let deadline {
            let next = deadline.addingTimeInterval(seconds)
            let left = next.timeIntervalSinceNow
            guard left > 0 else { return }
            self.deadline = next
            duration += seconds
            remaining = left
        } else {
            setDuration(duration + seconds)
        }
    }

    func toggleTimer() {
        isTimerRunning ? pauseTimer() : startTimer()
    }

    func startTimer() {
        guard remaining > 0 else { return }
        stopRinging()
        deadline = Date().addingTimeInterval(remaining)
        isTimerRunning = true
        startTicking()
        refreshIsland()
    }

    func pauseTimer() {
        guard isTimerRunning else { return }
        remaining = max(deadline?.timeIntervalSinceNow ?? remaining, 0)
        deadline = nil
        isTimerRunning = false
        stopTickingIfIdle()
        refreshIsland()
    }

    func resetTimer() {
        stopRinging()
        isTimerRunning = false
        deadline = nil
        remaining = duration
        stopTickingIfIdle()
        refreshIsland()
    }

    private func updateFocusSound() {
        if isTimerRunning {
            focusPlayer.play(focusSound, volume: focusVolume)
        } else {
            focusPlayer.stop()
        }
    }

    // MARK: - Секундомер

    func toggleStopwatch() {
        isStopwatchRunning ? pauseStopwatch() : startStopwatch()
    }

    func startStopwatch() {
        startedAt = Date()
        isStopwatchRunning = true
        startTicking()
        refreshIsland()
    }

    func pauseStopwatch() {
        guard isStopwatchRunning else { return }
        accumulated = elapsed()
        startedAt = nil
        stopwatch = accumulated
        isStopwatchRunning = false
        stopTickingIfIdle()
        refreshIsland()
    }

    func resetStopwatch() {
        startedAt = nil
        accumulated = 0
        stopwatch = 0
        laps = []
        isStopwatchRunning = false
        stopTickingIfIdle()
        refreshIsland()
    }

    /// Круг пишем от предыдущего круга, а не от старта: именно этот
    /// промежуток и интересен, общее время и так видно крупно.
    func lap() {
        guard isStopwatchRunning else { return }
        let total = elapsed()
        laps.insert(total - laps.reduce(0, +), at: 0)
    }

    private func elapsed() -> TimeInterval {
        guard let startedAt else { return accumulated }
        return accumulated + Date().timeIntervalSince(startedAt)
    }

    // MARK: - Будильники

    // MARK: - Набор времени

    var draftHour: Int { draft / 60 }
    var draftMinute: Int { draft % 60 }
    var draftText: String { String(format: "%02d:%02d", draftHour, draftMinute) }

    /// Шаг минут: будильник на 07:23 никому не нужен, а двадцать три
    /// щелчка ради него — тем более.
    nonisolated static let draftStep = 5

    /// Сутки замкнуты: за полуночью идёт час ночи, а не конец шкалы.
    func setDraft(minutesOfDay: Int) {
        draft = ((minutesOfDay % 1440) + 1440) % 1440
    }

    /// Завести то, что набрано.
    func addDraftAlarm() {
        addAlarm(hour: draftHour, minute: draftMinute)
    }

    func addAlarm(hour: Int, minute: Int) {
        let alarm = Alarm(hour: hour, minute: minute)
        // Ставим по времени суток: список, в котором будильники лежат
        // как на циферблате, читается без поиска глазами.
        alarms.append(alarm)
        alarms.sort { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
        persistAlarms()
    }

    func removeAlarm(_ alarm: Alarm) {
        alarms.removeAll { $0.id == alarm.id }
        if case .alarm(let ringing) = ringing, ringing.id == alarm.id { stopRinging() }
        persistAlarms()
    }

    func setAlarm(_ alarm: Alarm, on: Bool) {
        guard let index = alarms.firstIndex(where: { $0.id == alarm.id }) else { return }
        alarms[index].isOn = on
        if !on, case .alarm(let ringing) = ringing, ringing.id == alarm.id { stopRinging() }
        persistAlarms()
    }

    /// Когда будильник зазвонит в следующий раз — для подписи «через 7 ч».
    func nextFire(for alarm: Alarm) -> Date? {
        guard alarm.isOn else { return nil }
        return nextFire(hour: alarm.hour, minute: alarm.minute)
    }

    /// То же самое для времени, которое ещё не заведено: подпись под
    /// набором обещает ровно то, что получится.
    func nextFire(hour: Int, minute: Int) -> Date? {
        Calendar.current.nextDate(
            after: Date(),
            matching: DateComponents(hour: hour, minute: minute),
            matchingPolicy: .nextTime
        )
    }

    private func persistAlarms() {
        guard let data = try? JSONEncoder().encode(alarms) else { return }
        defaults.set(data, forKey: Keys.alarms)
    }

    /// Звонит всё, чьё время попало в промежуток с прошлой проверки.
    /// Промежуток, а не «сейчас ровно»: Мак мог спать, и минута, на
    /// которую был заведён будильник, прошла без единого тика.
    private func checkAlarms() {
        let now = Date()
        defer { checkedUpTo = now }
        guard now > checkedUpTo else { return }

        for alarm in alarms where alarm.isOn {
            guard let fire = Calendar.current.nextDate(
                after: checkedUpTo,
                matching: DateComponents(hour: alarm.hour, minute: alarm.minute),
                matchingPolicy: .nextTime
            ) else { continue }
            if fire <= now {
                ring(.alarm(alarm))
                break
            }
        }
    }

    // MARK: - Ход времени

    private func startTicking() {
        guard tick == nil else { return }
        // Двадцать кадров в секунду: сотые у секундомера должны бежать,
        // а не мигать. Тик живёт только пока что-то идёт.
        tick = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
    }

    private func stopTickingIfIdle() {
        guard !isTimerRunning, !isStopwatchRunning else { return }
        tick?.invalidate()
        tick = nil
    }

    /// Обновить кружок. Зовём отовсюду, где время могло поменяться, но
    /// пишем в объект, только если строка правда стала другой: иначе
    /// вёрстка выреза перекладывалась бы каждый тик.
    private func refreshIsland() {
        let next: (symbol: String, clock: String, short: String, progress: Double)?
        if isTimerRunning {
            next = ("timer", TimeFormat.clock(remaining), TimeFormat.short(remaining), timerProgress)
        } else if isStopwatchRunning {
            // Секундомеру не от чего считать долю — общего времени у него
            // нет. Дуга ходит по минуте: один оборот — одна минута, и по
            // ней видно ход даже там, где число стоит на месте.
            next = (
                "stopwatch",
                TimeFormat.clock(stopwatch),
                TimeFormat.short(stopwatch),
                stopwatch.truncatingRemainder(dividingBy: 60) / 60
            )
        } else {
            next = nil
        }
        if island.clock != next?.clock { island.clock = next?.clock }
        if island.short != next?.short { island.short = next?.short }
        if let symbol = next?.symbol, island.symbol != symbol { island.symbol = symbol }
        // Доля меняется каждый тик, а видно её только ступеньками: пишем
        // раз в четверть градуса, остальное досглаживает сама дуга.
        let progress = next?.progress ?? 0
        if abs(island.progress - progress) >= 0.004 || (progress == 0 && island.progress != 0) {
            island.progress = progress
        }
    }

    private func advance() {
        if isStopwatchRunning { stopwatch = elapsed() }
        if isTimerRunning, let deadline {
            let left = deadline.timeIntervalSinceNow
            if left <= 0 {
                remaining = 0
                isTimerRunning = false
                self.deadline = nil
                stopTickingIfIdle()
                ring(.timer)
            } else {
                remaining = left
            }
        }
        refreshIsland()
    }

    // MARK: - Звонок

    private func ring(_ what: Ringing) {
        ringing = what
        ringsLeft = 12
        playRing()
        ringTimer?.invalidate()
        ringTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.playRing() }
        }
        showActivity(for: what)
    }

    /// Остановить звонок. Таймер при этом возвращается к заданному
    /// времени: нажать «стоп» и получить готовый к следующему запуску
    /// таймер — ровно то, чего ждёшь.
    func stopRinging() {
        guard ringing != nil else { return }
        if case .timer = ringing { remaining = duration }
        ringing = nil
        ringTimer?.invalidate()
        ringTimer = nil
        activity?.dismiss(kind: .timer)
    }

    private func playRing() {
        guard ringsLeft > 0 else {
            // Сам звонок выдыхается через полминуты, но плашка и надпись
            // в панели остаются: вернувшись, надо увидеть, что звонило.
            ringTimer?.invalidate()
            ringTimer = nil
            return
        }
        ringsLeft -= 1
        NSSound(named: "Submarine")?.play()
    }

    private func showActivity(for what: Ringing) {
        let title: String
        let subtitle: String
        switch what {
        case .timer:
            title = settings.t(.timersDone)
            subtitle = TimeFormat.clock(duration)
        case .alarm(let alarm):
            title = settings.t(.timersAlarmRinging)
            subtitle = alarm.text
        }
        activity?.show(
            NotchActivity(
                kind: .timer,
                symbol: what == .timer ? "timer" : "alarm.fill",
                title: title,
                subtitle: subtitle,
                tint: ActivityTint.orange,
                // Без времени жизни: звонок снимает пользователь, а не часы.
                duration: 0
            )
        )
    }
}

/// Кружок таймера у схлопнутого выреза: символ (таймер или секундомер) и
/// время на нём. `clock == nil` — показывать нечего, кружка нет вовсе.
///
/// Живёт отдельно от стора нарочно: см. `TimersStore.island`.
@MainActor
final class TimerIslandState: ObservableObject {
    @Published fileprivate(set) var clock: String?
    /// Одно число для кружка: минуты, а под конец — секунды.
    @Published fileprivate(set) var short: String?
    @Published fileprivate(set) var symbol: String = "timer"
    /// Сколько дуги закрашено, 0…1.
    @Published fileprivate(set) var progress: Double = 0
}

/// Одно место, где решается, как выглядит время в этом модуле.
enum TimeFormat {
    /// «25:00», а после часа — «1:05:00».
    static func clock(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.up))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }

    /// Одно число вместо часов: пока идут минуты — их, а когда осталось
    /// меньше минуты, секунды. На кружке помещается только одно число, и
    /// полезно всегда то, которое сейчас меняется на глазах.
    static func short(_ interval: TimeInterval) -> String {
        let total = Int(max(interval, 0))
        return total < 60 ? "\(total)" : "\(total / 60)"
    }

    /// Секундомеру нужны сотые — без них кажется, что он стоит.
    static func precise(_ interval: TimeInterval) -> String {
        let hundredths = Int(interval * 100)
        let minutes = hundredths / 6000
        let seconds = (hundredths / 100) % 60
        let rest = hundredths % 100
        return String(format: "%02d:%02d,%02d", minutes, seconds, rest)
    }

    /// «через 7 ч 20 мин» — коротко и системными словами.
    static func until(_ date: Date) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .short
        formatter.maximumUnitCount = 2
        formatter.calendar = Calendar.current
        return formatter.string(from: max(date.timeIntervalSinceNow, 60)) ?? ""
    }
}
