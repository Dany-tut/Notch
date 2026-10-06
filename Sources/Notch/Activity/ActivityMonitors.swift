import Combine
import SwiftUI
import CoreAudio
import IOKit.ps

/// Источники событий для плашки. Каждый следит за своим куском системы и
/// сам решает, когда сказать `ActivityCenter.show`.
///
/// Все источники запускаются всегда: проверку «включено ли это в настройках»
/// делает центр — иначе каждый пришлось бы учить подписываться на настройки.
@MainActor
final class ActivityMonitors {
    private let center: ActivityCenter
    private let settings: AppSettings
    private let music: NowPlayingCoordinator
    private let calendar: CalendarStore

    private var cancellables: Set<AnyCancellable> = []
    private var observers: [NSObjectProtocol] = []
    private var powerSource: CFRunLoopSource?
    private var audioListener: AudioObjectPropertyListenerBlock?

    /// Предыдущее состояние — чтобы говорить только о переменах.
    private var lastTrackKey: String?
    private var lastPluggedIn: Bool?
    private var lastLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    private var lastOutputDevice: AudioDeviceID = 0

    init(
        center: ActivityCenter,
        settings: AppSettings,
        music: NowPlayingCoordinator,
        calendar: CalendarStore
    ) {
        self.center = center
        self.settings = settings
        self.music = music
        self.calendar = calendar
    }

    func start() {
        startMusic()
        startPinnedMusic()
        startPower()
        startLockScreen()
        startAudioDevice()
        startFocus()
        startCalendar()
    }

    // MARK: - Музыка

    /// Сменился трек — показываем обложку и название. Пауза и перемотка
    /// плашку не поднимают: это не новость.
    private func startMusic() {
        music.$info
            .receive(on: RunLoop.main)
            .sink { [weak self] info in
                MainActor.assumeIsolated { self?.handleTrack(info) }
            }
            .store(in: &cancellables)
    }

    private func handleTrack(_ info: NowPlayingInfo?) {
        guard let info, info.isPlaying, !info.title.isEmpty else {
            lastTrackKey = nil
            // Закреплённая плашка сама не уходит по времени, поэтому
            // снимаем её руками: музыка кончилась — говорить больше нечего.
            if settings.pinMusicActivity { center.dismiss(kind: .music) }
            return
        }
        let key = info.title + "|" + info.artist
        guard key != lastTrackKey else {
            // Тот же трек — только подвинуть прогресс, если плашка ещё висит.
            center.update(musicActivity(info))
            return
        }
        lastTrackKey = key
        center.show(musicActivity(info))
    }

    private func musicActivity(_ info: NowPlayingInfo) -> NotchActivity {
        NotchActivity(
            kind: .music,
            symbol: "music.note",
            artwork: info.artwork,
            title: info.title,
            subtitle: info.artist.isEmpty ? nil : info.artist,
            progress: info.duration > 0 ? info.progress : nil,
            // Цвет берём из обложки — тот же, которым светится раскрытая
            // панель. Розовая полоса поверх голубого свечения читалась как
            // чужая: у плашки и у панели один трек, значит и цвет один.
            // Обложки нет или она серая — остаётся палитровый розовый.
            tint: ArtworkColor.dominant(info.artwork) ?? ActivityTint.pink,
            // Закреплённой плашке время не нужно: ноль — «до явного снятия».
            duration: settings.pinMusicActivity ? 0 : settings.activityDuration
        )
    }

    /// Закреплённая плашка трека.
    ///
    /// У музыки самый низкий приоритет, поэтому её перебивает любая другая
    /// активность — громкость, зарядка, наушники. Чтобы «закреплено»
    /// держалось не до первого нажатия на клавишу громкости, возвращаем
    /// плашку сразу, как только вырез освободился.
    private func startPinnedMusic() {
        center.$current
            .sink { [weak self] current in
                guard current == nil else { return }
                // Отложенно: `@Published` присылает значение до того, как
                // оно записано, а показывать новое прямо внутри этой
                // рассылки — значит менять её же источник.
                Task { @MainActor in self?.restorePinnedMusic() }
            }
            .store(in: &cancellables)

        settings.$pinMusicActivity
            .dropFirst()
            .sink { [weak self] pinned in
                Task { @MainActor in
                    guard let self else { return }
                    // Выключили — снимаем сразу, иначе последняя плашка
                    // осталась бы висеть уже без своего времени показа.
                    if pinned { self.restorePinnedMusic() } else { self.center.dismiss(kind: .music) }
                }
            }
            .store(in: &cancellables)
    }

    private func restorePinnedMusic() {
        guard settings.pinMusicActivity,
              center.current == nil,
              let info = music.info,
              info.isPlaying,
              !info.title.isEmpty
        else { return }
        center.show(musicActivity(info))
    }

    // MARK: - Питание

    /// IOKit присылает событие на любое изменение источника питания:
    /// воткнули зарядку, изменился процент, сел аккумулятор.
    private func startPower() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitors = Unmanaged<ActivityMonitors>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitors.handlePower() }
        }, context)?.takeRetainedValue() else { return }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        powerSource = source

        let token = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleLowPower() }
        }
        observers.append(token)

        lastPluggedIn = Self.powerState()?.isPluggedIn
    }

    private func handlePower() {
        guard let state = Self.powerState() else { return }

        if lastPluggedIn != state.isPluggedIn {
            lastPluggedIn = state.isPluggedIn
            center.show(
                NotchActivity(
                    kind: .power,
                    symbol: state.isPluggedIn ? "battery.100percent.bolt" : "battery.50percent",
                    title: settings.t(state.isPluggedIn ? .activityCharging : .activityOnBattery),
                    subtitle: "\(Int(state.percentage * 100))%",
                    progress: state.percentage,
                    tint: state.isPluggedIn
                        ? ActivityTint.green
                        : ActivityTint.orange,
                    duration: settings.activityDuration
                )
            )
            return
        }

        // Разряд ниже порога — предупреждаем один раз на спуске.
        let threshold = settings.lowBatteryThreshold / 100
        if !state.isPluggedIn, state.percentage <= threshold, !warnedLowBattery {
            warnedLowBattery = true
            center.show(
                NotchActivity(
                    kind: .power,
                    symbol: "battery.25percent",
                    title: settings.t(.activityLowBattery),
                    subtitle: "\(Int(state.percentage * 100))%",
                    progress: state.percentage,
                    tint: ActivityTint.red,
                    duration: settings.activityDuration
                )
            )
        } else if state.isPluggedIn || state.percentage > threshold + 0.05 {
            warnedLowBattery = false
        }
    }

    private var warnedLowBattery = false

    private func handleLowPower() {
        let enabled = ProcessInfo.processInfo.isLowPowerModeEnabled
        guard enabled != lastLowPower else { return }
        lastLowPower = enabled
        center.show(
            NotchActivity(
                kind: .power,
                symbol: enabled ? "bolt.badge.a" : "bolt",
                title: settings.t(enabled ? .activityLowPowerOn : .activityLowPowerOff),
                tint: ActivityTint.orange,
                duration: settings.activityDuration
            )
        )
    }

    /// Заряд и питание от сети одним запросом к IOKit.
    static func powerState() -> (percentage: Double, isPluggedIn: Bool)? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in list {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any],
                let current = description[kIOPSCurrentCapacityKey] as? Int,
                let max = description[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }
            let state = description[kIOPSPowerSourceStateKey] as? String
            return (Double(current) / Double(max), state == kIOPSACPowerValue)
        }
        return nil
    }

    // MARK: - Блокировка экрана

    private func startLockScreen() {
        let center = DistributedNotificationCenter.default()
        for (name, locked) in [
            ("com.apple.screenIsLocked", true),
            ("com.apple.screenIsUnlocked", false)
        ] {
            let token = center.addObserver(
                forName: Notification.Name(name),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleLock(locked: locked) }
            }
            observers.append(token)
        }
    }

    private func handleLock(locked: Bool) {
        // При блокировке показывать некому — интересна разблокировка.
        guard !locked else { return }
        var activity = NotchActivity(
            kind: .lockScreen,
            symbol: "lock.open",
            title: settings.t(.activityWelcomeBack),
            tint: ActivityTint.indigo,
            duration: settings.activityDuration
        )
        if let state = Self.powerState() {
            activity.subtitle = "\(Int(state.percentage * 100))%"
            activity.progress = state.percentage
        }
        center.show(activity)
    }

    // MARK: - Аудиоустройство

    /// Смена устройства вывода — подключили наушники или колонку.
    private func startAudioDevice() {
        lastOutputDevice = Self.defaultOutputDevice()

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.handleAudioDevice() }
            }
        }
        audioListener = listener
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            listener
        )
    }

    private func handleAudioDevice() {
        let device = Self.defaultOutputDevice()
        guard device != lastOutputDevice, device != 0 else { return }
        lastOutputDevice = device
        guard let name = Self.deviceName(device) else { return }

        center.show(
            NotchActivity(
                kind: .audioDevice,
                symbol: Self.symbol(forDeviceNamed: name),
                title: name,
                subtitle: settings.t(.activityConnected),
                tint: ActivityTint.teal,
                duration: settings.activityDuration
            )
        )
    }

    static func defaultOutputDevice() -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        )
        return status == noErr ? device : 0
    }

    static func deviceName(_ device: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, pointer)
        }
        guard status == noErr else { return nil }
        let result = name as String
        return result.isEmpty ? nil : result
    }

    /// Иконку выбираем по имени: точного типа устройства CoreAudio не даёт.
    static func symbol(forDeviceNamed name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("airpods max") { return "airpods.max" }
        if lower.contains("airpods pro") { return "airpods.pro" }
        if lower.contains("airpods") { return "airpods" }
        if lower.contains("beats") || lower.contains("headphone") { return "headphones" }
        if lower.contains("display") || lower.contains("tv") { return "tv" }
        if lower.contains("macbook") || lower.contains("built-in") { return "laptopcomputer" }
        return "hifispeaker"
    }

    // MARK: - Встречи

    /// Раз в полминуты смотрим, не начинается ли ближайшая встреча. Каждую
    /// объявляем один раз — иначе плашка висела бы все пять минут подряд.
    private func startCalendar() {
        calendarTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkCalendar() }
        }
        checkCalendar()
    }

    private var calendarTimer: Timer?
    private var announcedEvent: String?

    private func checkCalendar() {
        guard let event = calendar.events.first,
              let start = event.startDate,
              let id = event.eventIdentifier
        else { return }

        let minutes = start.timeIntervalSinceNow / 60
        guard minutes > 0, minutes <= settings.calendarLeadMinutes else {
            if minutes <= 0 { announcedEvent = nil }
            return
        }
        let left = String(Int(minutes.rounded(.up)))
        let startsIn = String(format: settings.t(.calendarStartsIn), left)
        // Есть ссылка на созвон — плашка становится кнопкой входа и висит
        // до начала встречи: ради неё её и ждали, и прятать через пару
        // секунд значит заставить искать ссылку в календаре.
        let meeting = MeetingLink.find(in: event)
        let activity = NotchActivity(
            kind: .calendar,
            symbol: meeting == nil ? "calendar" : "video.fill",
            title: event.title ?? settings.t(.activityCalendar),
            subtitle: meeting == nil ? startsIn : "\(settings.t(.calendarJoin)) · \(startsIn)",
            tint: ActivityTint.red,
            duration: meeting == nil ? settings.activityDuration : start.timeIntervalSinceNow + 60,
            link: meeting?.url
        )
        // Уже показали — только освежаем отсчёт, иначе «через 5 мин»
        // провисит все пять минут.
        guard announcedEvent != id else {
            guard meeting != nil, !center.dismissedByUser.contains(.calendar) else { return }
            if center.current?.kind == .calendar {
                center.refresh(activity)
            } else {
                // Плашку встречи перебила короткая — громкость, зарядка.
                // Возвращаем: ссылка нужна до самого начала.
                center.show(activity)
            }
            return
        }
        announcedEvent = id
        center.forgetUserDismissal(.calendar)
        center.show(activity)
    }

    // MARK: - Фокусирование

    /// Системного API для «включён ли Не беспокоить» нет, поэтому смотрим
    /// на файл, который macOS пишет при смене режима. Не сможем прочитать —
    /// источник просто промолчит, остальные от этого не страдают.
    private func startFocus() {
        guard let url = Self.focusAssertionsURL else { return }
        focusWatcher = FileWatcher(url: url.deletingLastPathComponent()) { [weak self] in
            MainActor.assumeIsolated { self?.handleFocus() }
        }
        lastFocusOn = Self.isFocusOn()
    }

    private var focusWatcher: FileWatcher?
    private var lastFocusOn = false

    private func handleFocus() {
        let on = Self.isFocusOn()
        guard on != lastFocusOn else { return }
        lastFocusOn = on
        center.show(
            NotchActivity(
                kind: .focus,
                symbol: on ? "moon.fill" : "moon",
                title: settings.t(on ? .activityFocusOn : .activityFocusOff),
                tint: ActivityTint.indigo,
                duration: settings.activityDuration
            )
        )
    }

    static let focusAssertionsURL: URL? = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appending(path: "Library/DoNotDisturb/DB/Assertions.json")
    }()

    static func isFocusOn() -> Bool {
        guard let url = focusAssertionsURL,
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let records = root["data"] as? [[String: Any]]
        else { return false }

        return records.contains { record in
            guard let details = record["storeAssertionRecords"] as? [[String: Any]] else { return false }
            return !details.isEmpty
        }
    }

    func stop() {
        cancellables.removeAll()
        observers.forEach(NotificationCenter.default.removeObserver(_:))
        observers.removeAll()
        if let powerSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode)
        }
        powerSource = nil
        focusWatcher = nil
        calendarTimer?.invalidate()
        calendarTimer = nil
    }
}

/// Простой сторож за каталогом: GCD-источник на файловом дескрипторе.
final class FileWatcher {
    private let descriptor: Int32
    private let source: DispatchSourceFileSystemObject

    init?(url: URL, onChange: @escaping () -> Void) {
        descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .extend],
            queue: .main
        )
        source.setEventHandler(handler: onChange)
        source.resume()
    }

    deinit {
        source.cancel()
        close(descriptor)
    }
}
