import AppKit
import Combine
import SwiftUI

/// Держит окно панели, следит за геометрией экрана и за курсором.
///
/// Приём, на котором всё держится: окно всегда имеет размер раскрытой панели,
/// а в схлопнутом состоянии получает `ignoresMouseEvents = true`. Клики
/// проходят сквозь него в меню-бар и в приложения под ним, при этом SwiftUI
/// анимирует размер содержимого без рывков от `setFrame`.
@MainActor
final class NotchWindowController {
    private let state: NotchState
    private let settings: AppSettings
    private let feedback: Feedback
    private let actions: PanelActions
    private let shelf: ShelfStore
    private let music: NowPlayingCoordinator
    private let timers: TimersStore
    private let weather: WeatherStore
    private let activity: ActivityCenter
    private let behaviour: BehaviourSettings
    private var visibility: PanelVisibility?
    private var gestures: GestureMonitor?
    private var dragWatcher: DragWatcher?
    private var panel: NotchPanel?
    private var hostingView: NSHostingView<NotchRootView>?
    private var geometry: NotchGeometry?

    private var shelfObserver: AnyCancellable?
    private var moduleObserver: Set<AnyCancellable> = []
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var leaveTimer: Timer?
    private var clickGraceTimer: Timer?
    private var hoverTimer: Timer?

    /// Запас вокруг выреза, внутри которого панель считается "под курсором".
    private let hotZoneInset: CGFloat = 6
    /// Запас вокруг раскрытой панели, чтобы она не схлопывалась от дрожания руки.
    private let leaveMargin: CGFloat = 12
    /// Запас вокруг выреза для файла, который к нему несут. Больше, чем у
    /// курсора: груз ведут не так точно, как пустую мышь, и целятся при
    /// этом не остриём, а картинкой под ним.
    private let dropZoneInset: CGFloat = 16

    init(
        state: NotchState,
        settings: AppSettings,
        feedback: Feedback,
        actions: PanelActions,
        shelf: ShelfStore,
        music: NowPlayingCoordinator,
        timers: TimersStore,
        weather: WeatherStore,
        activity: ActivityCenter,
        behaviour: BehaviourSettings
    ) {
        self.state = state
        self.settings = settings
        self.feedback = feedback
        self.actions = actions
        self.shelf = shelf
        self.music = music
        self.timers = timers
        self.weather = weather
        self.activity = activity
        self.behaviour = behaviour
    }

    func start() {
        rebuildPanel()
        installMouseMonitors()
        installEscapeMonitor()
        installQueueWidth()
        installShelfAutoClose()
        installVisibility()
        installGestures()
        installDropToShelf()

        NotificationCenter.default.addObserver(
            forName: .notchSharingPolicyDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applySharingPolicy() }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildPanel() }
        }
    }

    /// Файл, поднесённый к вырезу, раскрывает панель на полке.
    private func installDropToShelf() {
        let watcher = DragWatcher()
        watcher.onDrag = { [weak self] point in
            MainActor.assumeIsolated { self?.handleDrag(at: point) }
        }
        watcher.start()
        dragWatcher = watcher
    }

    private func handleDrag(at point: CGPoint) {
        guard behaviour.dropToShelf, !state.isExpanded, let geometry else { return }
        // Выключенная полка ловить файл не может: её нет в рейле, и
        // раскрывать панель было бы не на что.
        guard state.modules.contains(where: { $0.id == "shelf" }) else { return }
        let zone = geometry.notchRect.insetBy(dx: -dropZoneInset, dy: -dropZoneInset)
        guard zone.contains(point) else { return }
        state.select("shelf")
        expandForDrop()
    }

    /// Раскрытие под груз. От обычного отличается тем, что мышь панель
    /// берёт сразу: паузы, которая спасает чужой клик, здесь ждать нельзя —
    /// пока она идёт, файл отпустят мимо.
    private func expandForDrop() {
        cancelHover()
        clickGraceTimer?.invalidate()
        panel?.ignoresMouseEvents = false
        withAnimation(NotchTheme.expandAnimation) {
            activity.dismiss()
            state.expand()
        }
        feedback.panelDidAppear()
        startLeaveTimer()
    }

    /// Жесты над вырезом. Зону считаем на лету: она разная у голого выреза
    /// и у плашки события.
    private func installGestures() {
        let monitor = GestureMonitor(behaviour: behaviour) { [weak self] in
            MainActor.assumeIsolated { self?.gestureZone() }
        } onGesture: { [weak self] gesture in
            MainActor.assumeIsolated { self?.handle(gesture) }
        }
        monitor.start()
        gestures = monitor
    }

    /// Над раскрытой панелью жесты не ловим: там прокрутка принадлежит
    /// содержимому — спискам буфера и календаря.
    private func gestureZone() -> CGRect? {
        guard !state.isExpanded, let geometry else { return nil }
        let size = activity.current == nil
            ? geometry.notchRect.size
            : ActivityView.size(notch: geometry.notchRect.size, activity: activity.current)
        return CGRect(
            x: geometry.notchRect.midX - size.width / 2,
            y: geometry.screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    private func handle(_ gesture: GestureMonitor.Gesture) {
        switch gesture {
        // Жест — не кнопка: в него попадают случайно. Скролл над вырезом
        // ловится заодно с прокруткой страницы, и заводить им молчащий
        // плеер нельзя. Перематываем только то, что уже звучит.
        case .skipForward:
            if music.info?.isPlaying == true { music.send(.next) }
        case .skipBackward:
            if music.info?.isPlaying == true { music.send(.previous) }
        case .open:
            open()
        case .close:
            // Сначала уходит плашка: если она висит, жест целились в неё.
            if activity.current != nil {
                withAnimation(NotchTheme.expandAnimation) { activity.dismiss() }
            } else {
                collapse()
            }
        }
    }

    /// Панель уходит с экрана в фуллскрине и в играх — и возвращается,
    /// как только игра свернулась.
    private func installVisibility() {
        let visibility = PanelVisibility(behaviour: behaviour) { [weak self] hide in
            MainActor.assumeIsolated { self?.applyHidden(hide) }
        }
        visibility.start()
        self.visibility = visibility
    }

    private func applyHidden(_ hidden: Bool) {
        guard let panel else { return }
        if hidden {
            collapse()
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    private func applySharingPolicy() {
        panel?.sharingType = behaviour.hideFromScreenCapture ? .none : .readOnly
    }

    // MARK: - Окно

    private func rebuildPanel() {
        guard let screen = NotchGeometry.screen(for: behaviour) else { return }
        let geometry = NotchGeometry.current(for: screen, behaviour: behaviour)
        self.geometry = geometry
        // Высота выреза нужна раскладке раньше рамки: горизонтальный ряд
        // уходит под челку, и панель растёт на эту полосу.
        state.notchHeight = geometry.notchRect.height

        let frame = windowFrame(for: geometry)

        if panel == nil {
            let panel = NotchPanel(contentRect: frame)
            let root = NotchRootView(
                state: state,
                settings: settings,
                collapsedSize: geometry.notchRect.size,
                actions: actions,
                shelf: shelf,
                music: music,
                timers: timers.island,
                weather: weather,
                activity: activity,
                behaviour: behaviour
            )
            let hosting = NSHostingView(rootView: root)
            // Иначе SwiftUI добавит верхний safe-area-инсет экрана (высоту выреза)
            // поверх наших отступов, и содержимое уедет вниз вдвое.
            hosting.safeAreaRegions = []
            hosting.frame = CGRect(origin: .zero, size: frame.size)
            panel.contentView = hosting
            hostingView = hosting
            panel.ignoresMouseEvents = true
            panel.sharingType = behaviour.hideFromScreenCapture ? .none : .readOnly
            panel.orderFrontRegardless()
            self.panel = panel
        } else {
            panel?.setFrame(frame, display: true)
            if let hosting = panel?.contentView as? NSHostingView<NotchRootView> {
                hosting.rootView = NotchRootView(
                state: state,
                settings: settings,
                collapsedSize: geometry.notchRect.size,
                actions: actions,
                shelf: shelf,
                music: music,
                timers: timers.island,
                weather: weather,
                activity: activity,
                behaviour: behaviour
            )
            }
        }
    }

    /// Полка плеера расширяет корпус, а вместе с ним должно расти окно:
    /// иначе панель обрежется по его границе. Окно прозрачное, поэтому
    /// растим его сразу и без анимации — рывка не видно, зато клики и зона
    /// ухода считаются по новой ширине с первого кадра. Сужаем наоборот,
    /// после анимации: пока содержимое едет, ему нужно место.
    private func installQueueWidth() {
        shelfObserver = music.$isShelfOpen
            .removeDuplicates()
            .sink { [weak self] isOpen in
                // Значение берём из подписки, а не из координатора: `@Published`
                // шлёт его в `willSet`, и свойство в этот момент держит ещё
                // старое. Прочитанное оттуда состояние всегда отстаёт на шаг —
                // на этом ширина и не менялась.
                MainActor.assumeIsolated { self?.applyShelfWidth(isShelfOpen: isOpen) }
            }
    }

    /// Полка принадлежит плееру, а не панели: уходя в другой модуль или в
    /// настройки, пользователь оставляет её открытой — и корпус остаётся
    /// широким под чужим содержимым, которому эта ширина не нужна.
    /// Закрываем её вместе с уходом, той же пружиной: вернувшись в музыку,
    /// человек находит плеер таким, каким он открывается по умолчанию.
    private func installShelfAutoClose() {
        // Значение читаем из подписки: `@Published` шлёт его в `willSet`,
        // и само свойство в этот момент держит ещё старое — как и с полкой.
        state.$selectedModuleID
            .removeDuplicates()
            .sink { [weak self] id in
                MainActor.assumeIsolated { self?.closeShelfIfAway(moduleID: id) }
            }
            .store(in: &moduleObserver)

        state.$isSettingsOpen
            .removeDuplicates()
            .sink { [weak self] isOpen in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.closeShelfIfAway(isSettingsOpen: isOpen)
                }
            }
            .store(in: &moduleObserver)
    }

    private func closeShelfIfAway(moduleID: String? = nil, isSettingsOpen: Bool? = nil) {
        guard music.isShelfOpen else { return }
        let module = moduleID ?? state.selectedModuleID
        let settingsOpen = isSettingsOpen ?? state.isSettingsOpen
        guard settingsOpen || module != MusicModule.moduleID else { return }
        withAnimation(NotchTheme.collapseAnimation) { music.isShelfOpen = false }
    }

    private func applyShelfWidth(isShelfOpen: Bool) {
        let wanted = state.isExpanded && isShelfOpen ? NotchTheme.shelfPanelWidth : 0
        guard wanted != state.widthBoost else { return }

        guard wanted == 0 else {
            // Порядок важен: сначала окно, потом раскладка, и только потом
            // корпус. Наоборот SwiftUI успевает разложить широкую панель
            // внутри ещё узкого окна и обрезать её — этот кадр и читался
            // как рывок.
            resizeWindow(width: NotchTheme.panelWidth + wanted)
            setLayoutBoost(wanted)
            state.widthBoost = wanted
            return
        }

        // Закрытие наоборот: едет корпус, а раскладка держится широкой до
        // конца движения. Убери её сразу — начинка перевёрстывается под
        // ещё открытым корпусом, и видно, как содержимое схлопывается
        // раньше коробки.
        state.widthBoost = 0
        shrinkWindowWhenSettled()
    }

    /// Ширину раскладки меняем рывком: анимировать её — значит просить
    /// SwiftUI перекладывать всю панель на каждом кадре. Едет корпус, а
    /// начинка под ним стоит.
    private func setLayoutBoost(_ value: CGFloat) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { state.layoutBoost = value }
    }

    /// Левый край окна прибит к месту, ширина прирастает вправо.
    ///
    /// Раньше окно росло симметрично, и вместе с ним уезжал влево весь
    /// плеер: обложка, название, кнопки. Полка при этом проявлялась
    /// справа — два движения навстречу друг другу и читались как косая
    /// анимация. Теперь слева не меняется ничего, а полка просто
    /// открывается наружу.
    private func resizeWindow(width: CGFloat) {
        guard let panel, let geometry else { return }
        let frame = CGRect(
            x: geometry.notchRect.midX - NotchTheme.panelWidth / 2,
            y: geometry.screenFrame.maxY - state.expandedSize.height,
            width: width,
            height: state.expandedSize.height
        )
        guard frame != panel.frame else { return }
        // `display: false` здесь принципиально. С `true` окно
        // перерисовывается синхронно, прямо внутри `willSet` того самого
        // `isShelfOpen`, — то есть в кадре, где ширина раскладки уже
        // выросла, а полки в вёрстке ещё нет. Колонка плеера на один кадр
        // оказывалась в пустой широкой области и прыгала вправо на сотню
        // точек, чтобы в следующем кадре вернуться. Без принудительной
        // отрисовки оба изменения доезжают до SwiftUI вместе.
        panel.setFrame(frame, display: false)
        hostingView?.frame = CGRect(origin: .zero, size: frame.size)
    }

    private func windowFrame(for geometry: NotchGeometry) -> CGRect {
        let size = state.expandedSize
        return CGRect(
            x: geometry.notchRect.midX - size.width / 2,
            y: geometry.screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    // MARK: - Курсор

    /// Esc закрывает панель, открытую с клавиатуры.
    private func installEscapeMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            // Esc в окне AirDrop закрывает его, а не нашу панель.
            if MainActor.assumeIsolated({ NotchPanel.isHeldOpen }) { return event }
            var handled = false
            MainActor.assumeIsolated {
                guard let self, self.state.isExpanded else { return }
                self.collapse()
                handled = true
            }
            return handled ? nil : event
        }
    }

    private func installMouseMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleMouseMoved() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            MainActor.assumeIsolated { self?.handleMouseMoved() }
            return event
        }
    }

    private func handleMouseMoved() {
        guard !state.isExpanded, let geometry else {
            cancelHover()
            return
        }
        guard behaviour.expandOnHover else { return }
        let cursor = NSEvent.mouseLocation

        // Пока висит плашка события, горячая зона — вся она: иначе к ней
        // нельзя подвести курсор, не промахнувшись мимо выреза.
        let plate = ActivityView.size(notch: geometry.notchRect.size, activity: activity.current)
        let base = activity.current == nil
            ? geometry.notchRect
            : CGRect(origin: .zero, size: plate).offsetBy(
                dx: geometry.notchRect.midX - plate.width / 2,
                dy: geometry.screenFrame.maxY - plate.height
            )

        let hotZone = base.insetBy(dx: -hotZoneInset, dy: -hotZoneInset)
        if hotZone.contains(cursor) {
            // Плашка ведёт в свой модуль — как и клик по ней. К висящему
            // треку подводят курсор ради самого трека, а не ради вкладки,
            // на которой панель закрыли в прошлый раз.
            scheduleExpand(moduleID: activity.current?.kind.moduleID)
            return
        }
        // Кружки — такая же горячая зона, только раскрывают панель сразу на
        // своём модуле: за ними пришли ради файлов или трека, а не ради
        // вкладки, которая была открыта в прошлый раз.
        if let indicator = islandIndicator(at: cursor) {
            scheduleExpand(moduleID: indicator.moduleID)
            return
        }
        cancelHover()
    }

    /// Раскрытие с задержкой из настроек. Пока курсор не ушёл — ждём;
    /// ушёл — отменяем, иначе панель выскакивала бы вдогонку.
    private func scheduleExpand(moduleID: String?) {
        guard hoverTimer == nil else { return }
        guard behaviour.hoverDuration > 0 else {
            performExpand(moduleID: moduleID)
            return
        }
        hoverTimer = Timer.scheduledTimer(
            withTimeInterval: behaviour.hoverDuration,
            repeats: false
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.hoverTimer = nil
                self?.performExpand(moduleID: moduleID)
            }
        }
    }

    private func cancelHover() {
        hoverTimer?.invalidate()
        hoverTimer = nil
    }

    private func performExpand(moduleID: String?) {
        if let moduleID { state.select(moduleID) }
        expand()
    }

    /// Кружок под курсором. Раскладку считаем тем же `IslandPlan`, что и
    /// вёрстка, — иначе зоны разъедутся с картинкой.
    private func islandIndicator(at point: CGPoint) -> IslandIndicator? {
        guard let geometry else { return nil }
        // Плашка сдвигает кружки за свои края — зоны считаем от неё же,
        // иначе курсор ловился бы там, где кружка уже нет.
        let base = activity.current == nil
            ? geometry.notchRect.width
            : ActivityView.size(notch: geometry.notchRect.size, activity: activity.current).width
        let plan = IslandPlan.make(
            settings: settings,
            shelf: shelf,
            music: music,
            timers: timers.island,
            enabledModules: Set(state.modules.map(\.id)),
            activityKind: activity.current?.kind,
            baseWidth: base
        )
        let height = IslandMetrics.diameter

        for side in IslandSide.allCases {
            let entries = plan.indicators(on: side)
            for (index, entry) in entries.enumerated() {
                let offset = IslandMetrics.offset(
                    side: side,
                    entries: entries,
                    index: index,
                    baseWidth: base
                )
                let rect = CGRect(
                    x: geometry.notchRect.midX + offset - entry.width / 2,
                    y: geometry.notchRect.midY - height / 2,
                    width: entry.width,
                    height: height
                )
                if rect.insetBy(dx: -hotZoneInset, dy: -hotZoneInset).contains(point) {
                    return entry.indicator
                }
            }
        }
        return nil
    }

    private func expand() {
        cancelHover()
        // Раскрытие по наведению приходит само, и панель встаёт прямо под
        // курсором — а под курсором у неё кнопка play. Клик, нацеленный в
        // то, что было под панелью, попадал в неё и включал музыку. Даём
        // короткую паузу: руке она незаметна, чужой клик не крадёт.
        // Раскрытие по клику или горячей клавише — дело намеренное, там
        // ждать нечего, и `open()` включает мышь сразу.
        panel?.ignoresMouseEvents = true
        clickGraceTimer?.invalidate()
        clickGraceTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.state.isExpanded else { return }
                self.panel?.ignoresMouseEvents = false
            }
        }
        withAnimation(NotchTheme.expandAnimation) {
            // Плашка события отработала: панель показывает больше, чем она.
            // Внутри той же транзакции, что и раскрытие: снаружи она
            // пропадала рывком, пока корпус только трогался с места.
            activity.dismiss()
            state.expand()
        }
        feedback.panelDidAppear()
        startLeaveTimer()
    }

    /// Состав модулей изменился — высота панели могла поехать.
    func panelSizeDidChange() {
        rebuildPanel()
    }

    /// Открыть или закрыть панель с клавиатуры. Необязательный `moduleID`
    /// сразу переключает вкладку — так хоткей «открыть буфер» попадает
    /// прямо в нужный модуль.
    func toggleFromKeyboard(moduleID: String? = nil) {
        if let moduleID, state.modules.contains(where: { $0.id == moduleID }),
           state.selectedModuleID != moduleID || !state.isExpanded {
            state.select(moduleID)
            open()
            return
        }
        if state.isExpanded { collapse() } else { open() }
    }

    private func open() {
        clickGraceTimer?.invalidate()
        panel?.ignoresMouseEvents = false
        withAnimation(NotchTheme.expandAnimation) { state.pinOpen() }
        panel?.makeKeyAndOrderFront(nil)
        feedback.panelDidAppear()
        startLeaveTimer()
    }

    private func collapse() {
        stopLeaveTimer()
        clickGraceTimer?.invalidate()
        NotchPanel.releaseFocus()
        // Всё одной транзакцией: полка закрывается вместе с панелью
        // (иначе в следующий раз панель выедет сразу широкой), корпус
        // возвращается к обычной ширине — и то и другое по той же
        // пружине, что и само схлопывание.
        //
        // Раньше ширина обнулялась и окно сужалось сразу, до анимации:
        // при открытой полке закрытие начиналось с прыжка на двести
        // точек. Теперь схлопнутый вырез держится над настоящим вырезом
        // сам (`islandShift` в корневой вёрстке), широкое окно ему не
        // мешает — и сузить его можно спокойно, когда корпус доехал.
        withAnimation(NotchTheme.collapseAnimation) {
            music.isShelfOpen = false
            state.widthBoost = 0
            state.collapse()
        }
        panel?.ignoresMouseEvents = true
        shrinkWindowWhenSettled()
    }

    /// Окно сужается после анимации: пока корпус едет, ему нужно место.
    /// Если за это время панель успели открыть заново и снова раскрыть
    /// полку, сужение отменяется само.
    private func shrinkWindowWhenSettled() {
        DispatchQueue.main.asyncAfter(
            deadline: .now() + NotchTheme.expandSettleDuration
        ) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.state.widthBoost == 0 else { return }
                self.setLayoutBoost(0)
                self.resizeWindow(width: NotchTheme.panelWidth)
            }
        }
    }

    /// Глобальные монитора не хватает, чтобы заметить уход курсора с раскрытой
    /// панели (события уходят нам, а не мимо), поэтому пока панель открыта —
    /// опрашиваем позицию курсора напрямую.
    private func startLeaveTimer() {
        stopLeaveTimer()
        leaveTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkForLeave() }
        }
    }

    private func stopLeaveTimer() {
        leaveTimer?.invalidate()
        leaveTimer = nil
    }

    private func checkForLeave() {
        guard state.isExpanded, let panel else { return }
        // В панели что-то набирают — уводить её из-под курсора нельзя. Один
        // только статус key не в счёт: полка забирает его ради ⌘V, но
        // закрываться это мешать не должно.
        if panel.isKeyWindow, panel.firstResponder is NSTextView { return }
        // Панель держат открытой нарочно — например, пока с полки идёт
        // AirDrop: курсор уехал к окну выбора получателя, а не прочь.
        if NotchPanel.isHeldOpen { return }
        // Закреплена булавкой — закрывается только явно: Esc, кликом по
        // вырезу или той же булавкой.
        if state.isHeldOpen { return }
        let zone = panel.frame.insetBy(dx: -leaveMargin, dy: -leaveMargin)
        if !zone.contains(NSEvent.mouseLocation) {
            collapse()
        }
    }
}

// MARK: - Снимок для отладки вёрстки

extension NotchWindowController {
    /// Рендерит раскрытую панель в PNG без участия экрана и пользователя.
    /// Используется режимом `NOTCH_SNAPSHOT=<путь>`, чтобы проверять вёрстку
    /// из терминала, не требуя разрешений на запись экрана.
    func writeSnapshot(to path: String) -> Bool {
        guard let hosting = hostingView,
              let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)
        else { return false }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: URL(fileURLWithPath: path))) != nil
    }
}
