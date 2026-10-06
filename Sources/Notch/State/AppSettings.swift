import SwiftUI

/// Пользовательские настройки: язык, отклик, состав и порядок модулей.
@MainActor
final class AppSettings: ObservableObject {
    private enum Keys {
        static let language = "settings.language"
        static let soundEnabled = "settings.sound"
        static let haptics = "settings.haptics"
        static let volume = "settings.volume"
        static let sound = "settings.soundName"
        static let moduleOrder = "settings.moduleOrder"
        static let disabledModules = "settings.disabledModules"
        static let lastModule = "settings.lastModule"
        static let hotkeys = "settings.hotkeys"
        static let persistClipboard = "settings.persistClipboard"
        static let clipboardGrid = "settings.clipboardGrid"
        static let shelfGrid = "settings.shelfGrid"
        static let islandDisabled = "settings.islandDisabled"
        static let islandSides = "settings.islandSides"
        static let activityDisabled = "settings.activityDisabled"
        static let activityOptIn = "settings.activityOptIn"
        static let activityDuration = "settings.activityDuration"
        static let lowBattery = "settings.lowBatteryThreshold"
        static let pinMusicActivity = "settings.pinMusicActivity"
        static let calendarLead = "settings.calendarLead"
        static let musicVisualizer = "settings.musicVisualizer"
        static let musicStations = "settings.musicStations"
        static let railSize = "settings.railSize"
        static let railPlacement = "settings.railPlacement"
        static let railSettingsInline = "settings.railSettingsInline"
        static let railLabels = "settings.railLabels"
        static let railGap = "settings.railGap"
        static let railIconStyle = "settings.railIconStyle"
    }

    @Published var language: AppLanguage {
        didSet {
            guard language != oldValue else { return }
            defaults.set(language.rawValue, forKey: Keys.language)
            NotificationCenter.default.post(name: .notchLanguageDidChange, object: nil)
        }
    }

    @Published var soundEnabled: Bool { didSet { defaults.set(soundEnabled, forKey: Keys.soundEnabled) } }
    @Published var sound: NotchSound { didSet { defaults.set(sound.rawValue, forKey: Keys.sound) } }
    @Published var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: Keys.haptics) } }
    @Published var feedbackVolume: Double { didSet { defaults.set(feedbackVolume, forKey: Keys.volume) } }

    /// Порядок вкладок в рейле. Модули, которых здесь нет, добавляются в конец.
    @Published var moduleOrder: [String] {
        didSet {
            defaults.set(moduleOrder, forKey: Keys.moduleOrder)
            NotificationCenter.default.post(name: .notchModulesDidChange, object: nil)
        }
    }

    /// Храним именно выключенные: новый модуль тогда появляется включённым.
    @Published var disabledModules: Set<String> {
        didSet {
            defaults.set(Array(disabledModules), forKey: Keys.disabledModules)
            NotificationCenter.default.post(name: .notchModulesDidChange, object: nil)
        }
    }

    /// Размер кнопок рейла. Меняет и высоту панели: рейл длиннее
    /// содержимого — значит, он её и задаёт.
    @Published var railSize: RailSize {
        didSet {
            defaults.set(railSize.rawValue, forKey: Keys.railSize)
            // Той же тропой, что и состав модулей: размер рейла меняет
            // высоту панели, а её должно подхватить окно.
            NotificationCenter.default.post(name: .notchModulesDidChange, object: nil)
        }
    }

    /// Слева, справа или рядом сверху.
    @Published var railPlacement: RailPlacement {
        didSet {
            defaults.set(railPlacement.rawValue, forKey: Keys.railPlacement)
            NotificationCenter.default.post(name: .notchModulesDidChange, object: nil)
        }
    }

    /// Подписи у кнопок — только для горизонтального ряда.
    @Published var railLabels: RailLabels {
        didSet {
            defaults.set(railLabels.rawValue, forKey: Keys.railLabels)
            NotificationCenter.default.post(name: .notchModulesDidChange, object: nil)
        }
    }

    /// Зазор между кнопками ряда.
    @Published var railGap: RailGap {
        didSet {
            defaults.set(railGap.rawValue, forKey: Keys.railGap)
            NotificationCenter.default.post(name: .notchModulesDidChange, object: nil)
        }
    }

    /// Как нарисованы иконки рейла.
    @Published var railIconStyle: RailIconStyle {
        didSet { defaults.set(railIconStyle.rawValue, forKey: Keys.railIconStyle) }
    }

    /// Шестерёнка стоит в общем ряду кнопок, а не отбитой у дальнего края.
    @Published var railSettingsInline: Bool {
        didSet { defaults.set(railSettingsInline, forKey: Keys.railSettingsInline) }
    }

    @Published var lastModuleID: String? {
        didSet { defaults.set(lastModuleID, forKey: Keys.lastModule) }
    }

    /// Сочетания по действиям. Отсутствие ключа — действие выключено.
    @Published var hotkeys: [String: KeyCombo] {
        didSet {
            if let data = try? JSONEncoder().encode(hotkeys) {
                defaults.set(data, forKey: Keys.hotkeys)
            }
            NotificationCenter.default.post(name: .notchHotkeysDidChange, object: nil)
        }
    }

    /// Выключенные кружки у выреза. Храним выключенные, а не включённые:
    /// новый индикатор тогда появляется сам.
    @Published var islandDisabled: Set<String> {
        didSet { defaults.set(Array(islandDisabled), forKey: Keys.islandDisabled) }
    }

    /// Сторона выреза для каждого кружка. Нет ключа — сторона по умолчанию.
    @Published var islandSides: [String: String] {
        didSet { defaults.set(islandSides, forKey: Keys.islandSides) }
    }

    /// Выключенные поводы для плашки у выреза. Как и у кружков, храним
    /// именно выключенные.
    @Published var activityDisabled: Set<String> {
        didSet { defaults.set(Array(activityDisabled), forKey: Keys.activityDisabled) }
    }

    /// Поводы, которые выключены, пока их не включили руками
    /// (`Kind.isOptIn`). Храним наоборот — включённые: в списке
    /// выключенных новый повод у старых пользователей оказался бы включён.
    @Published var activityOptIn: Set<String> {
        didSet { defaults.set(Array(activityOptIn), forKey: Keys.activityOptIn) }
    }

    /// Сколько секунд плашка висит, прежде чем уйти сама.
    @Published var activityDuration: Double {
        didSet { defaults.set(activityDuration, forKey: Keys.activityDuration) }
    }

    /// Держать ли плашку трека у схлопнутого выреза постоянно. Обычная
    /// активность живёт временем, а закреплённая — состоянием: пока играет
    /// музыка, она возвращается каждый раз, когда панель закрывается.
    @Published var pinMusicActivity: Bool {
        didSet { defaults.set(pinMusicActivity, forKey: Keys.pinMusicActivity) }
    }


    /// Раскачивать ли панель музыки по басу. Выключено по умолчанию:
    /// чужой звук слышен только через запись экрана, а это разрешение и
    /// индикатор в меню-баре — плата, на которую соглашаются сами.
    @Published var musicVisualizer: Bool {
        didSet { defaults.set(musicVisualizer, forKey: Keys.musicVisualizer) }
    }

    /// Станции Apple Music, принесённые ссылками. Список свой, потому
    /// что плеер станций не отдаёт вовсе; JSON, а не массив строк, —
    /// у станции два поля, и имя пользователь пишет сам.
    @Published var musicStations: [MusicStation] {
        didSet {
            guard let data = try? JSONEncoder().encode(musicStations) else { return }
            defaults.set(data, forKey: Keys.musicStations)
        }
    }

    /// За сколько минут до встречи поднимать плашку.
    @Published var calendarLeadMinutes: Double {
        didSet { defaults.set(calendarLeadMinutes, forKey: Keys.calendarLead) }
    }

    /// Процент, ниже которого предупреждаем о разряде.
    @Published var lowBatteryThreshold: Double {
        didSet { defaults.set(lowBatteryThreshold, forKey: Keys.lowBattery) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // NOTCH_LANG позволяет снять снимок на любом языке, не трогая настройки.
        let override = ProcessInfo.processInfo.environment["NOTCH_LANG"]
            .flatMap(AppLanguage.init(rawValue:))
        let stored = defaults.string(forKey: Keys.language).flatMap(AppLanguage.init(rawValue:))
        self.language = override ?? stored ?? .system

        self.soundEnabled = defaults.object(forKey: Keys.soundEnabled) as? Bool ?? true
        self.sound = defaults.string(forKey: Keys.sound)
            .flatMap(NotchSound.init(rawValue:)) ?? .click
        self.hapticsEnabled = defaults.object(forKey: Keys.haptics) as? Bool ?? true
        self.feedbackVolume = defaults.object(forKey: Keys.volume) as? Double ?? 0.06
        self.moduleOrder = defaults.stringArray(forKey: Keys.moduleOrder) ?? []
        self.disabledModules = Set(defaults.stringArray(forKey: Keys.disabledModules) ?? [])
        self.lastModuleID = defaults.string(forKey: Keys.lastModule)
        self.railSize = defaults.string(forKey: Keys.railSize)
            .flatMap(RailSize.init(rawValue:)) ?? .medium
        self.railPlacement = defaults.string(forKey: Keys.railPlacement)
            .flatMap(RailPlacement.init(rawValue:)) ?? .leading
        // Режима «у всех» больше нет. У кого он стоял, тот хотел подписи,
        // а не иконки, — переносим на ближайшее, что осталось.
        let storedLabels = defaults.string(forKey: Keys.railLabels)
        self.railLabels = storedLabels == "all"
            ? .active
            : storedLabels.flatMap(RailLabels.init(rawValue:)) ?? RailLabels.none
        self.railGap = defaults.string(forKey: Keys.railGap)
            .flatMap(RailGap.init(rawValue:)) ?? .tight
        self.railIconStyle = defaults.string(forKey: Keys.railIconStyle)
            .flatMap(RailIconStyle.init(rawValue:)) ?? .color
        self.railSettingsInline = defaults.object(forKey: Keys.railSettingsInline) as? Bool ?? false
        self.persistClipboard = defaults.object(forKey: Keys.persistClipboard) as? Bool ?? true
        self.clipboardGrid = defaults.object(forKey: Keys.clipboardGrid) as? Bool ?? false
        self.shelfGrid = defaults.object(forKey: Keys.shelfGrid) as? Bool ?? true
        self.musicVisualizer = defaults.object(forKey: Keys.musicVisualizer) as? Bool ?? false
        self.islandDisabled = Set(defaults.stringArray(forKey: Keys.islandDisabled) ?? [])
        self.islandSides = defaults.dictionary(forKey: Keys.islandSides) as? [String: String] ?? [:]
        self.activityDisabled = Set(defaults.stringArray(forKey: Keys.activityDisabled) ?? [])
        self.activityOptIn = Set(defaults.stringArray(forKey: Keys.activityOptIn) ?? [])
        self.activityDuration = defaults.object(forKey: Keys.activityDuration) as? Double ?? 3
        self.lowBatteryThreshold = defaults.object(forKey: Keys.lowBattery) as? Double ?? 20
        self.pinMusicActivity = defaults.object(forKey: Keys.pinMusicActivity) as? Bool ?? false
        self.calendarLeadMinutes = defaults.object(forKey: Keys.calendarLead) as? Double ?? 5

        if let data = defaults.data(forKey: Keys.musicStations),
           let stored = try? JSONDecoder().decode([MusicStation].self, from: data) {
            self.musicStations = stored
        } else {
            self.musicStations = []
        }

        if let data = defaults.data(forKey: Keys.hotkeys),
           var stored = try? JSONDecoder().decode([String: KeyCombo].self, from: data) {
            // Раньше действие было одно на всю панель — «открыть буфер».
            // Теперь сочетание есть у каждого модуля, и старый ключ
            // переезжает на своё место, чтобы клавиша не пропала.
            if let legacy = stored.removeValue(forKey: "openClipboard") {
                stored[HotKeyManager.Action.module("clipboard").rawValue] = legacy
            }
            self.hotkeys = stored
        } else {
            self.hotkeys = [
                HotKeyManager.Action.togglePanel.rawValue: .defaultTogglePanel,
                HotKeyManager.Action.module("clipboard").rawValue: .defaultClipboard
            ]
        }
    }

    func isEnabled(_ id: String) -> Bool { !disabledModules.contains(id) }

    // MARK: - Остров

    func isIslandEnabled(_ indicator: IslandIndicator) -> Bool {
        !islandDisabled.contains(indicator.rawValue)
    }

    func setIslandEnabled(_ enabled: Bool, for indicator: IslandIndicator) {
        if enabled {
            islandDisabled.remove(indicator.rawValue)
        } else {
            islandDisabled.insert(indicator.rawValue)
        }
    }

    // MARK: - Плашка у выреза

    func isActivityEnabled(_ kind: NotchActivity.Kind) -> Bool {
        if kind.isOptIn { return activityOptIn.contains(kind.rawValue) }
        return !activityDisabled.contains(kind.rawValue)
    }

    func setActivityEnabled(_ enabled: Bool, for kind: NotchActivity.Kind) {
        if kind.isOptIn {
            if enabled { activityOptIn.insert(kind.rawValue) } else { activityOptIn.remove(kind.rawValue) }
        } else if enabled {
            activityDisabled.remove(kind.rawValue)
        } else {
            activityDisabled.insert(kind.rawValue)
        }
    }

    func islandSide(for indicator: IslandIndicator) -> IslandSide {
        islandSides[indicator.rawValue].flatMap(IslandSide.init(rawValue:)) ?? indicator.defaultSide
    }

    func setIslandSide(_ side: IslandSide, for indicator: IslandIndicator) {
        islandSides[indicator.rawValue] = side.rawValue
    }

    /// Автозапуск живёт не в UserDefaults, а в системе — читаем и пишем
    /// напрямую, иначе настройка разъедется с реальным состоянием.
    var launchAtLogin: Bool {
        get { LaunchAtLogin.isEnabled }
        set {
            launchAtLoginError = LaunchAtLogin.set(newValue)
            objectWillChange.send()
        }
    }

    @Published var launchAtLoginError: String?

    /// Хранить ли историю буфера между запусками. Выключено — история
    /// живёт только в памяти и исчезает вместе с приложением.
    @Published var persistClipboard: Bool {
        didSet {
            defaults.set(persistClipboard, forKey: Keys.persistClipboard)
            NotificationCenter.default.post(name: .notchClipboardPolicyDidChange, object: nil)
        }
    }

    /// Как показывать историю буфера: списком строк или сеткой карточек.
    /// У картинки имя ничего не говорит — её надо видеть.
    @Published var clipboardGrid: Bool {
        didSet { defaults.set(clipboardGrid, forKey: Keys.clipboardGrid) }
    }

    /// Полка: карточками с превью или списком строк. По умолчанию карточки —
    /// на полке лежат файлы, а их узнают в лицо.
    @Published var shelfGrid: Bool {
        didSet { defaults.set(shelfGrid, forKey: Keys.shelfGrid) }
    }

    /// Действия, которым можно назначить клавишу: панель целиком и все
    /// включённые модули, в том же порядке, в каком они стоят в рейле.
    /// Выключенный модуль сюда не попадает — открывать нечего.
    var hotkeyActions: [HotKeyManager.Action] {
        [.togglePanel] + ModuleCatalog.ordered(by: moduleOrder)
            .filter { isEnabled($0.id) }
            .map { .module($0.id) }
    }

    /// Как действие называется в настройках. У модуля — «Открыть …» с его
    /// же именем: заводить отдельную строку на каждый модуль незачем.
    func hotkeyTitle(for action: HotKeyManager.Action) -> String {
        switch action {
        case .togglePanel:
            return t(.hotkeyTogglePanel)
        case .module(let id):
            let name = ModuleCatalog.descriptors.first { $0.id == id }.map { t($0.titleKey) } ?? id
            return String(format: t(.hotkeyOpenModule), name)
        }
    }

    func combo(for action: HotKeyManager.Action) -> KeyCombo? {
        hotkeys[action.rawValue]
    }

    func setCombo(_ combo: KeyCombo?, for action: HotKeyManager.Action) {
        if let combo {
            hotkeys[action.rawValue] = combo
        } else {
            hotkeys.removeValue(forKey: action.rawValue)
        }
    }

    // MARK: - Станции

    func addStation(name: String, url: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !url.isEmpty else { return }
        musicStations.append(MusicStation(name: name, url: url))
    }

    func updateStation(_ station: MusicStation) {
        guard let index = musicStations.firstIndex(where: { $0.id == station.id }) else { return }
        musicStations[index] = station
    }

    func removeStations(at offsets: IndexSet) {
        musicStations.remove(atOffsets: offsets)
    }

    func setEnabled(_ enabled: Bool, for id: String) {
        if enabled { disabledModules.remove(id) } else { disabledModules.insert(id) }
    }

    /// Короткий доступ к строке на текущем языке.
    func t(_ key: L10n.Key) -> String { L10n.string(key, language) }

    func name(for sound: NotchSound) -> String {
        sound == .none ? t(.settingsSoundNone) : sound.displayName
    }

    func name(for option: AppLanguage) -> String {
        option == .system ? t(.settingsLanguageSystem) : option.nativeName
    }
}

extension Notification.Name {
    static let notchLanguageDidChange = Notification.Name("notchLanguageDidChange")
    static let notchModulesDidChange = Notification.Name("notchModulesDidChange")
    static let notchHotkeysDidChange = Notification.Name("notchHotkeysDidChange")
    static let notchClipboardPolicyDidChange = Notification.Name("notchClipboardPolicyDidChange")
}
