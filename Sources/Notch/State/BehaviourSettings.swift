import AppKit

/// Поведение панели: на каком экране жить, когда прятаться, как раскрываться,
/// какого размера считать вырез.
///
/// Отдельный объект, а не поле в `AppSettings`: настроек поведения много, они
/// меняются пачками и почти все влияют на геометрию окна — держать их рядом
/// удобнее, чем размазывать по общему списку.
@MainActor
final class BehaviourSettings: ObservableObject {
    /// Экран, на котором живёт панель.
    enum DisplayTarget: String, CaseIterable, Identifiable, Sendable {
        /// Экран с настоящим вырезом, иначе основной. Поведение по умолчанию.
        case builtIn
        /// Всегда основной экран, даже если нотч на другом.
        case main
        /// Тот экран, где сейчас курсор — панель переезжает следом.
        case active

        var id: String { rawValue }

        var titleKey: L10n.Key {
            switch self {
            case .builtIn: return .behaviourDisplayBuiltIn
            case .main: return .behaviourDisplayMain
            case .active: return .behaviourDisplayActive
            }
        }
    }

    private enum Keys {
        static let display = "behaviour.display"
        static let expandOnHover = "behaviour.expandOnHover"
        static let hoverDuration = "behaviour.hoverDuration"
        static let hideInFullscreen = "behaviour.hideInFullscreen"
        static let hideWhileGaming = "behaviour.hideWhileGaming"
        static let hideFromScreenCapture = "behaviour.hideFromScreenCapture"
        static let hideMenuBarIcon = "behaviour.hideMenuBarIcon"
        static let forceSimulatedNotch = "behaviour.forceSimulatedNotch"
        static let dropToShelf = "behaviour.dropToShelf"
        static let swipeToSkip = "behaviour.swipeToSkip"
        static let swipeToToggle = "behaviour.swipeToToggle"
        static let widthAdjust = "behaviour.widthAdjust"
        static let heightAdjust = "behaviour.heightAdjust"
    }

    /// Правки, после которых окно нужно пересобрать (экран, размер выреза).
    private func geometryChanged() {
        NotificationCenter.default.post(name: .notchBehaviourDidChange, object: nil)
    }

    @Published var displayTarget: DisplayTarget {
        didSet {
            guard displayTarget != oldValue else { return }
            defaults.set(displayTarget.rawValue, forKey: Keys.display)
            geometryChanged()
        }
    }

    /// Раскрывать по наведению. Выключено — панель открывается только
    /// кликом или горячей клавишей.
    @Published var expandOnHover: Bool {
        didSet { defaults.set(expandOnHover, forKey: Keys.expandOnHover) }
    }

    /// Сколько курсор должен провисеть над вырезом, прежде чем панель
    /// раскроется. Ноль — мгновенно.
    @Published var hoverDuration: Double {
        didSet { defaults.set(hoverDuration, forKey: Keys.hoverDuration) }
    }

    /// Файл, поднесённый к вырезу, раскрывает панель на полке. Панель
    /// при этом начинает принимать события мыши — но только пока идёт
    /// перетаскивание, и только над самим вырезом.
    @Published var dropToShelf: Bool {
        didSet { defaults.set(dropToShelf, forKey: Keys.dropToShelf) }
    }

    @Published var hideInFullscreen: Bool {
        didSet { defaults.set(hideInFullscreen, forKey: Keys.hideInFullscreen) }
    }

    @Published var hideWhileGaming: Bool {
        didSet { defaults.set(hideWhileGaming, forKey: Keys.hideWhileGaming) }
    }

    /// Панель не попадает в скриншоты, запись экрана и демонстрацию.
    @Published var hideFromScreenCapture: Bool {
        didSet {
            defaults.set(hideFromScreenCapture, forKey: Keys.hideFromScreenCapture)
            NotificationCenter.default.post(name: .notchSharingPolicyDidChange, object: nil)
        }
    }

    /// Иконку в меню-баре можно убрать: настройки открываются шестерёнкой
    /// в самой панели и горячей клавишей.
    @Published var hideMenuBarIcon: Bool {
        didSet {
            defaults.set(hideMenuBarIcon, forKey: Keys.hideMenuBarIcon)
            NotificationCenter.default.post(name: .notchMenuBarPolicyDidChange, object: nil)
        }
    }

    /// Смахивание вбок над вырезом переключает трек.
    @Published var swipeToSkip: Bool {
        didSet { defaults.set(swipeToSkip, forKey: Keys.swipeToSkip) }
    }

    /// Смахивание вниз раскрывает панель, вверх — убирает.
    @Published var swipeToToggle: Bool {
        didSet { defaults.set(swipeToToggle, forKey: Keys.swipeToToggle) }
    }

    /// Жесты живут только над свёрнутым вырезом, а раскрытие по наведению
    /// сворачивает это окно в ноль: курсор вошёл в зону — панель уже
    /// открыта, и смахивать нечего, ни вбок, ни вниз. Сохранённые «Вкл»
    /// при этом не трогаем — выключат наведение, и жесты вернутся такими,
    /// какими их оставили.
    var gesturesReachable: Bool { !expandOnHover }
    var swipeToSkipActive: Bool { swipeToSkip && gesturesReachable }
    var swipeToToggleActive: Bool { swipeToToggle && gesturesReachable }

    /// Рисовать виртуальный вырез даже там, где есть настоящий.
    @Published var forceSimulatedNotch: Bool {
        didSet {
            guard forceSimulatedNotch != oldValue else { return }
            defaults.set(forceSimulatedNotch, forKey: Keys.forceSimulatedNotch)
            geometryChanged()
        }
    }

    /// Поправки к размеру выреза в точках. Настоящий нотч мы не меняем,
    /// но схлопнутая панель может быть чуть шире или ниже его.
    @Published var widthAdjust: Double {
        didSet {
            guard widthAdjust != oldValue else { return }
            defaults.set(widthAdjust, forKey: Keys.widthAdjust)
            geometryChanged()
        }
    }

    @Published var heightAdjust: Double {
        didSet {
            guard heightAdjust != oldValue else { return }
            defaults.set(heightAdjust, forKey: Keys.heightAdjust)
            geometryChanged()
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.displayTarget = defaults.string(forKey: Keys.display)
            .flatMap(DisplayTarget.init(rawValue:)) ?? .builtIn
        self.expandOnHover = defaults.object(forKey: Keys.expandOnHover) as? Bool ?? true
        self.hoverDuration = defaults.object(forKey: Keys.hoverDuration) as? Double ?? 0
        self.dropToShelf = defaults.object(forKey: Keys.dropToShelf) as? Bool ?? true
        self.hideInFullscreen = defaults.object(forKey: Keys.hideInFullscreen) as? Bool ?? true
        self.hideWhileGaming = defaults.object(forKey: Keys.hideWhileGaming) as? Bool ?? false
        self.hideFromScreenCapture = defaults.object(forKey: Keys.hideFromScreenCapture) as? Bool ?? false
        self.hideMenuBarIcon = defaults.object(forKey: Keys.hideMenuBarIcon) as? Bool ?? false
        self.swipeToSkip = defaults.object(forKey: Keys.swipeToSkip) as? Bool ?? true
        self.swipeToToggle = defaults.object(forKey: Keys.swipeToToggle) as? Bool ?? true
        self.forceSimulatedNotch = defaults.object(forKey: Keys.forceSimulatedNotch) as? Bool ?? false
        self.widthAdjust = defaults.object(forKey: Keys.widthAdjust) as? Double ?? 0
        self.heightAdjust = defaults.object(forKey: Keys.heightAdjust) as? Double ?? 0
    }

    /// Правки размера выреза, ограниченные разумными пределами.
    var clampedWidthAdjust: CGFloat { CGFloat(min(max(widthAdjust, -60), 120)) }
    var clampedHeightAdjust: CGFloat { CGFloat(min(max(heightAdjust, -10), 20)) }

    func resetTuning() {
        widthAdjust = 0
        heightAdjust = 0
        forceSimulatedNotch = false
    }
}

extension Notification.Name {
    /// Изменилось то, от чего зависит геометрия окна панели.
    static let notchBehaviourDidChange = Notification.Name("notchBehaviourDidChange")
    static let notchSharingPolicyDidChange = Notification.Name("notchSharingPolicyDidChange")
    static let notchMenuBarPolicyDidChange = Notification.Name("notchMenuBarPolicyDidChange")
}
