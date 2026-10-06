import SwiftUI

/// Состояние панели: раскрыта или нет, какой модуль выбран.
@MainActor
final class NotchState: ObservableObject {
    enum Presentation: Equatable {
        case collapsed
        case expanded
    }

    @Published private(set) var presentation: Presentation = .collapsed
    /// Панель открыта горячей клавишей: курсор может быть где угодно,
    /// поэтому по уходу мыши её закрывать нельзя.
    @Published private(set) var isPinned = false
    /// Панель закреплена булавкой в рейле: уход курсора её не закрывает.
    /// Не то же, что `isPinned`: тот ставится и при открытии кликом, а
    /// здесь — только по явной просьбе, и снимается с закрытием панели.
    @Published private(set) var isHeldOpen = false
    @Published private(set) var selectedModuleID: String = ""
    @Published private(set) var modules: [any NotchModule] = []
    /// Настройки занимают область содержимого вместо модуля.
    @Published private(set) var isSettingsOpen = false

    /// Панель стоит на месте: ни раскрытия, ни схлопывания. Пока движение
    /// идёт, содержимое гасит всё, что рисуется каждый кадр, — иначе
    /// свечение и волна отбирают кадры у самой анимации, и раскрытие
    /// дёргается.
    @Published private(set) var isSettled = true
    private var settleTask: Task<Void, Never>?

    /// На сколько модуль попросил расширить корпус. Сейчас этим пользуется
    /// только полка плеера. Не настройка и не свойство модуля: ширина
    /// меняется на ходу, и окно должно успевать за ней.
    ///
    /// Ширин две, и это главное здесь. `layoutBoost` — та, по которой
    /// раскладываются окно и начинка; она меняется рывком, без анимации,
    /// чтобы содержимое встало по конечной ширине с первого же кадра.
    /// `widthBoost` — ширина самого корпуса, и едет только она: корпус
    /// открывает готовую начинку, как штора.
    ///
    /// Раньше ширина была одна и анимировалась. От этого панель
    /// перекладывалась каждый кадр: кнопки, полоса и обложка разъезжались
    /// от середины, полка проявлялась поверх этой возни — и открытие
    /// читалось как рябь, а не как движение.
    @Published var layoutBoost: CGFloat = 0
    @Published var widthBoost: CGFloat = 0

    /// Корпус уже взял полную ширину. Ставится рывком, до пружины: тогда
    /// в пути остаётся одна высота, и раскрытие читается как штора,
    /// падающая сверху вниз.
    ///
    /// Пока ширина ехала вместе с высотой, корпус рос от левого края
    /// вправо — прирост отдан правой стороне, — и движение читалось как
    /// выезд вбок, а не как раскрытие из выреза.
    ///
    /// Снимается отметка тоже рывком, но уже после схлопывания: корпус
    /// к тому времени сам сжался до выреза и стоит на своём месте, так
    /// что смена раскладки под ним ничего не двигает.
    @Published private(set) var isCorpusWide = false

    private let settings: AppSettings
    private let allModules: [any NotchModule]

    init(modules: [any NotchModule], settings: AppSettings) {
        precondition(!modules.isEmpty, "Панель без модулей не имеет смысла")
        self.allModules = modules
        self.settings = settings
        reloadModules()
    }

    /// Одна высота на все состояния раскрытой панели: максимум из того,
    /// что просят видимые модули, настройки и сам рейл. Постоянство тут
    /// важнее плотности — иначе переключение вкладки или настроек двигает
    /// корпус, и панель дёргается на глазах.
    var expandedSize: CGSize {
        let requested = max(
            NotchTheme.settingsPanelHeight,
            modules.map(\.preferredHeight).max() ?? NotchTheme.defaultPanelHeight
        )
        return CGSize(
            width: NotchTheme.panelWidth + layoutBoost,
            height: max(requested, railHeight) + horizontalRailExtra
        )
    }

    /// Размер корпуса — то, что видно и что едет. От `expandedSize`
    /// отличается только шириной: высота у раскрытой панели одна.
    var corpusSize: CGSize {
        CGSize(width: NotchTheme.panelWidth + widthBoost, height: expandedSize.height)
    }

    var railMetrics: RailMetrics { settings.railSize.metrics }
    var railPlacement: RailPlacement { settings.railPlacement }

    /// Высота самого выреза. Ставит её контроллер по геометрии экрана:
    /// панель висит из-под челки, и верхняя полоса шириной с неё закрыта
    /// железом — рисовать туда можно, видно не будет.
    @Published var notchHeight: CGFloat = NotchGeometry.fallbackSize.height

    /// Сколько высоты горизонтальный ряд добавляет панели сверх обычной
    /// вёрстки.
    ///
    /// Раньше ряд считался бесплатным: он садился в строку заголовка, и
    /// высота не менялась. Но строка заголовка при колонке живёт ровно под
    /// челкой — её самой там не видно, а вот кнопки в ней потерять нельзя.
    /// Поэтому горизонтальный ряд уходит ниже выреза, а панель отдаёт ему
    /// разницу: модуль должен получить ту же высоту, что и при колонке.
    private var horizontalRailExtra: CGFloat {
        switch railPlacement {
        case .leading, .trailing:
            return 0
        case .top:
            // Сверху: вместо `topInset` — полоса выреза, и под рядом зазор.
            return notchHeight + NotchTheme.railRowGap - NotchTheme.topInset
        case .bottom, .bottomCentered:
            // Снизу: сверху та же полоса вместо строки заголовка, а снизу
            // ряд с зазором вместо обычного поля.
            return notchHeight + NotchTheme.railRowGap - NotchTheme.contentPadding
        }
    }

    /// Сколько высоты требует сам рейл: модули плюс булавка и кнопка
    /// настроек внизу.
    ///
    /// Ряд сверху не требует ничего: он садится в строку заголовка, которая
    /// в панели есть при любой раскладке. Поэтому высоту диктует только
    /// колонка — и только когда она длиннее содержимого.
    private var railHeight: CGFloat {
        guard railPlacement.isVertical else { return 0 }
        let metrics = railMetrics
        let count = CGFloat(modules.count + 2)
        let items = count * metrics.itemHeight
        let gaps = max(count - 1, 0) * metrics.spacing
        return NotchTheme.topInset * 2 + items + gaps
    }

    var selectedModule: any NotchModule {
        modules.first(where: { $0.id == selectedModuleID }) ?? modules[0]
    }

    var isExpanded: Bool { presentation == .expanded }

    /// Пересобирает видимый список по настройкам: сначала порядок, затем отсев
    /// выключенных. Если всё выключено, оставляем первый — пустой рейл бесполезен.
    func reloadModules() {
        let order = settings.moduleOrder
        let ranked = allModules.enumerated().sorted { lhs, rhs in
            let l = order.firstIndex(of: lhs.element.id) ?? (order.count + lhs.offset)
            let r = order.firstIndex(of: rhs.element.id) ?? (order.count + rhs.offset)
            return l < r
        }.map(\.element)

        let visible = ranked.filter { settings.isEnabled($0.id) }
        modules = visible.isEmpty ? [ranked[0]] : visible

        let preferred = settings.lastModuleID ?? selectedModuleID
        selectedModuleID = modules.contains(where: { $0.id == preferred })
            ? preferred
            : modules[0].id
    }

    func expand() {
        guard presentation != .expanded else { return }
        widenCorpus()
        presentation = .expanded
        beginMotion()
    }

    func collapse() {
        isPinned = false
        isHeldOpen = false
        guard presentation != .collapsed else { return }
        presentation = .collapsed
        beginMotion()
    }

    func pinOpen() {
        isPinned = true
        guard presentation != .expanded else { return }
        widenCorpus()
        presentation = .expanded
        beginMotion()
    }

    /// Ширина раскладки берётся вне анимации — иначе рамка едет вместе
    /// с корпусом, а она центрируется в окне: её левый край уползает, и
    /// корпус ползёт следом.
    private func widenCorpus() {
        setCorpusWide(true)
    }

    /// Панель схлопнулась и отстоялась — раскладке больше незачем быть
    /// широкой.
    private func narrowCorpusIfCollapsed() {
        guard presentation == .collapsed else { return }
        setCorpusWide(false)
    }

    private func setCorpusWide(_ value: Bool) {
        guard isCorpusWide != value else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { isCorpusWide = value }
    }

    /// Отмечаем движение и сами же снимаем отметку, когда пружина
    /// успокоится. Перезапуск посреди пути безопасен: прошлое ожидание
    /// снимается, и отметка снимется по последнему движению.
    private func beginMotion() {
        settleTask?.cancel()
        isSettled = false
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(NotchTheme.expandSettleDuration))
            guard !Task.isCancelled else { return }
            self?.isSettled = true
            self?.narrowCorpusIfCollapsed()
        }
    }

    func select(_ id: String) {
        isSettingsOpen = false
        selectedModuleID = id
        settings.lastModuleID = id
    }

    func toggleHeldOpen() {
        isHeldOpen.toggle()
    }

    func toggleSettings() {
        isSettingsOpen.toggle()
    }
}
