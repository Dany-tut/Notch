import AppKit
import EventKit
import SwiftUI

@main
@MainActor
final class NotchApp: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let snippets = SnippetStore()
    private lazy var clipboard = ClipboardStore(settings: settings)
    private let shelf = ShelfStore()
    /// Один `EKEventStore` на приложение — его делят Календарь и Напоминания.
    private let eventStore = EKEventStore()
    private lazy var calendar = CalendarStore(store: eventStore)
    private lazy var reminders = RemindersStore(store: eventStore)
    private let mirror = MirrorStore()
    private let trash = TrashStore()
    private let apps = AppsStore()
    private let shortcuts = ShortcutsStore()
    private let converter = ConverterStore()
    private let emoji = EmojiStore()
    private lazy var music = NowPlayingCoordinator(settings: settings)
    private let battery = BatteryStore()
    private let notes = NotesStore()
    private let system = SystemStore()
    private lazy var weather = WeatherStore(settings: settings)
    private let behaviour = BehaviourSettings()
    private lazy var activity = ActivityCenter(settings: settings)
    private lazy var timers = TimersStore(settings: settings, activity: activity)
    private var monitors: ActivityMonitors?
    private var levels: LevelsController?
    private var state: NotchState?
    private var controller: NotchWindowController?
    private var settingsWindow: SettingsWindowController?
    private let hotKeys = HotKeyManager()
    private var statusItem: NSStatusItem?

    static func main() {
        let app = NSApplication.shared
        let delegate = NotchApp()
        app.delegate = delegate
        // Агент: без иконки в Dock и без меню приложения.
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Дерево «Универсального доступа» чужого плеера: смотрим, за что в
        // нём вообще можно взяться. Панель и всё прочее для этого поднимать
        // не надо — печатаем и выходим первым делом.
        if let needle = ProcessInfo.processInfo.environment["NOTCH_AXDUMP"] {
            AXProbe.dump(matching: needle)
            exit(0)
        }

        if let needle = ProcessInfo.processInfo.environment["NOTCH_AXSEEK"],
           let seconds = ProcessInfo.processInfo.environment["NOTCH_AXSECONDS"].flatMap(Double.init) {
            AXProbe.seek(matching: needle, to: seconds)
            exit(0)
        }

        // Нажатие в чужом окне: проверяем, слушается ли кнопка и по чему
        // видно её новое состояние.
        if let needle = ProcessInfo.processInfo.environment["NOTCH_AXPRESS"],
           let label = ProcessInfo.processInfo.environment["NOTCH_AXLABEL"] {
            AXProbe.press(matching: needle, label: label)
            exit(0)
        }

        clipboard.start()
        calendar.start()
        trash.start()
        music.start()
        battery.start()
        timers.start()
        weather.start()

        let state = NotchState(
            modules: ModuleCatalog.all(
                snippets: snippets,
                clipboard: clipboard,
                shelf: shelf,
                calendar: calendar,
                reminders: reminders,
                mirror: mirror,
                trash: trash,
                music: music,
                battery: battery,
                timers: timers,
                notes: notes,
                system: system,
                weather: weather,
                apps: apps,
                shortcuts: shortcuts,
                converter: converter,
                emoji: emoji
            ),
            settings: settings
        )
        let feedback = Feedback(settings: settings)
        let controller = NotchWindowController(
            state: state,
            settings: settings,
            feedback: feedback,
            actions: PanelActions(
                openSettingsWindow: { [weak self] in
                    MainActor.assumeIsolated { self?.openSettings() }
                },
                clearClipboardHistory: { [weak self] in
                    MainActor.assumeIsolated { self?.clipboard.clearAll() }
                },
                previewSound: { sound in
                    MainActor.assumeIsolated { feedback.preview(sound) }
                },
                openModule: { [weak self] moduleID in
                    MainActor.assumeIsolated {
                        self?.controller?.toggleFromKeyboard(moduleID: moduleID)
                    }
                }
            ),
            shelf: shelf,
            music: music,
            timers: timers,
            weather: weather,
            activity: activity,
            behaviour: behaviour
        )
        controller.start()
        self.state = state
        self.controller = controller

        // Источники событий поднимаем после панели: первая же плашка должна
        // найти готовое окно.
        let monitors = ActivityMonitors(
            center: activity,
            settings: settings,
            music: music,
            calendar: calendar
        )
        monitors.start()
        self.monitors = monitors

        let levels = LevelsController(center: activity, settings: settings)
        levels.start()
        self.levels = levels

        self.settingsWindow = SettingsWindowController(
            settings: settings,
            snippets: snippets,
            music: music,
            clipboard: clipboard,
            feedback: feedback
        )

        installStatusItem()
        applyMenuBarPolicy()
        installHotKeys()

        NotificationCenter.default.addObserver(
            forName: .notchLanguageDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.rebuildStatusMenu()
                self?.settingsWindow?.refreshTitle()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .notchClipboardPolicyDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.clipboard.persistenceDidChange() }
        }

        NotificationCenter.default.addObserver(
            forName: .notchHotkeysDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyHotKeys() }
        }


        NotificationCenter.default.addObserver(
            forName: .notchBehaviourDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.controller?.panelSizeDidChange() }
        }

        NotificationCenter.default.addObserver(
            forName: .notchMenuBarPolicyDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyMenuBarPolicy() }
        }

        NotificationCenter.default.addObserver(
            forName: .notchModulesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.state?.reloadModules()
                self?.controller?.panelSizeDidChange()
            }
        }

        // Наполнение полки из терминала — только для снимков вёрстки.
        if let paths = ProcessInfo.processInfo.environment["NOTCH_SHELF_ADD"] {
            shelf.add(paths.split(separator: ":").map { URL(fileURLWithPath: String($0)) })
        }

        // Проверка транспорта из терминала: шлём команду тем же путём,
        // что и кнопка в панели, и сразу выходим.
        if let raw = ProcessInfo.processInfo.environment["NOTCH_SEND"] {
            let command: TransportCommand? = switch raw {
            case "playPause": .playPause
            case "next": .next
            case "previous": .previous
            default: nil
            }
            if let command {
                FileHandle.standardError.write(Data(
                    "send: \(raw) via \(music.activeProvider), trusted=\(MediaKeys.isTrusted)\n".utf8
                ))
                music.send(command)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [self] in
                    FileHandle.standardError.write(Data("after: \(self.music.info.map { "\($0.title) playing=\($0.isPlaying)" } ?? "—")\n".utf8))
                    NSApp.terminate(nil)
                }
                return
            }
        }

        // Проверка перемотки из терминала: тем же путём, что и полоса в
        // панели. Ждём первый опрос — без него перематывать нечего.
        if let seconds = ProcessInfo.processInfo.environment["NOTCH_SEEK"].flatMap(Double.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [self] in
                let before = music.info.map {
                    "\($0.title) canSeek=\($0.canSeek) elapsed=\(Int($0.elapsed))/\(Int($0.duration))"
                } ?? "—"
                FileHandle.standardError.write(Data("seek: \(before) via \(music.activeProvider)\n".utf8))
                music.seek(to: seconds)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [self] in
                    let after = music.info.map { "elapsed=\(Int($0.elapsed))" } ?? "—"
                    FileHandle.standardError.write(Data("after: \(after)\n".utf8))
                    NSApp.terminate(nil)
                }
            }
            return
        }

        if let path = ProcessInfo.processInfo.environment["NOTCH_SNAPSHOT"] {
            FileHandle.standardError.write(Data("sounds: \(feedback.diagnostics())\n".utf8))
            captureSnapshot(state: state, controller: controller, path: path)
        }
    }


    // MARK: - Строка состояния

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "rectangle.topthird.inset.filled",
            accessibilityDescription: "Notch"
        )
        statusItem = item
        rebuildStatusMenu()
    }

    /// Пункты меню — не SwiftUI, поэтому при смене языка пересобираем их.
    private func rebuildStatusMenu() {
        let menu = NSMenu()
        let settingsItem = NSMenuItem(
            title: settings.t(.menuSettings),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(
            withTitle: settings.t(.menuQuit),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        statusItem?.menu = menu
    }

    /// Иконку в меню-баре можно спрятать: настройки остаются доступны
    /// шестерёнкой в панели и горячей клавишей.
    private func applyMenuBarPolicy() {
        statusItem?.isVisible = !behaviour.hideMenuBarIcon
    }

    @objc private func openSettings() {
        settingsWindow?.show()
    }

    // MARK: - Горячие клавиши

    private func installHotKeys() {
        hotKeys.start { [weak self] action in
            MainActor.assumeIsolated { self?.perform(action) }
        }
        applyHotKeys()
    }

    private func applyHotKeys() {
        var combos: [HotKeyManager.Action: KeyCombo?] = [:]
        // Берём не список действий, а сами сохранённые сочетания: модуль
        // могли выключить, а клавишу за ним оставить — регистрировать её
        // тогда не за чем, но и терять запись не надо.
        for (raw, combo) in settings.hotkeys {
            guard let action = HotKeyManager.Action(rawValue: raw) else { continue }
            combos[action] = combo
        }
        hotKeys.apply(combos)
    }

    private func perform(_ action: HotKeyManager.Action) {
        switch action {
        case .togglePanel:
            controller?.toggleFromKeyboard()
        case .module(let id):
            controller?.toggleFromKeyboard(moduleID: id)
        }
    }

    // MARK: - Отладка

    /// Раскрыть панель, сохранить PNG и выйти — проверка вёрстки из терминала.
    private func captureSnapshot(state: NotchState, controller: NotchWindowController, path: String) {
        if let module = ProcessInfo.processInfo.environment["NOTCH_MODULE"] {
            if module == "settings" {
                state.toggleSettings()
            } else {
                state.select(module)
            }
        }
        // Плашка события: показываем образец нужного вида, не дожидаясь,
        // когда в системе что-то произойдёт.
        if let raw = ProcessInfo.processInfo.environment["NOTCH_ACTIVITY"],
           let kind = NotchActivity.Kind(rawValue: raw) {
            activity.show(NotchActivity.sample(kind, settings: settings))
        }

        // Идущее время: кружок таймера живёт, только пока что-то идёт, а
        // ждать этого от снимка нельзя — заводим сами.
        switch ProcessInfo.processInfo.environment["NOTCH_TIMER"] {
        case "stopwatch": timers.startStopwatch()
        case "timer": timers.startTimer()
        case "alarm": timers.mode = .alarm
        case "alarms":
            timers.mode = .alarm
            timers.addAlarm(hour: 7, minute: 30)
            timers.addAlarm(hour: 13, minute: 0)
        default: break
        }

        // Схлопнутый снимок — чтобы проверить значки острова у выреза.
        if ProcessInfo.processInfo.environment["NOTCH_COLLAPSED"] == nil {
            state.expand()
        }
        // Пауза до кадра. Больше секунды нужно, когда ждём, пока отговорит
        // активность и на её месте проступят значки острова.
        let delay = ProcessInfo.processInfo.environment["NOTCH_SNAPSHOT_DELAY"]
            .flatMap(Double.init) ?? 0.8
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let ok = controller.writeSnapshot(to: path)
            FileHandle.standardError.write(Data((ok ? "snapshot: ok\n" : "snapshot: failed\n").utf8))
            NSApp.terminate(nil)
        }
    }
}
