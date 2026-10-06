import SwiftUI

/// Настройки внутри самой панели.
///
/// Раскладка — плитками, как в Home: у каждого переключаемого параметра своя
/// кнопка, нажатие заливает её цветом. Свитчеров нет: состояние читается
/// цветом самой плитки, поэтому не нужно связывать глазами подпись слева и
/// контрол у правого края.
///
/// Отдельное окно осталось для того, что в 640 точках не помещается —
/// правки заготовок.
struct SettingsPanel: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var behaviour: BehaviourSettings
    let actions: PanelActions
    /// Полка и музыка — ради живых кружков в разделе «Вырез»: плитка
    /// показывает тот же значок, что стоит у выреза, а не его рисунок.
    @ObservedObject var shelf: ShelfStore
    @ObservedObject var music: NowPlayingCoordinator
    /// Таймер — для того же живого кружка: плитка показывает идущее
    /// время, а не нарисованные цифры.
    @ObservedObject var timers: TimerIslandState

    /// Разделы — по тому, чем настройка управляет, а не по её природе.
    ///
    /// Объектов ровно пять: раскрытая панель, схлопнутый вырез, модули,
    /// поведение приложения и само приложение. Раньше разделов было
    /// восемь, и три из них жили ради двух плиток: строка вкладок не
    /// влезала в 640 точек и ездила вбок — до «Приватности» надо было
    /// сперва догадаться доскроллить.
    enum Section: String, CaseIterable, Identifiable {
        case appearance, notch, modules, behaviour, hotkeys, app
        var id: String { rawValue }

        var titleKey: L10n.Key {
            switch self {
            case .appearance: return .settingsTabView
            case .notch: return .settingsTabNotch
            case .modules: return .settingsTabModules
            case .behaviour: return .settingsTabBehaviour
            case .hotkeys: return .settingsTabHotkeys
            case .app: return .settingsTabApp
            }
        }
    }

    @Environment(\.notchContentTopInset) private var contentTopInset
    @State private var section: Section = .appearance
    /// Высоты строк-оверлеев: по ним список получает отступы, а полосы
    /// размытия — длину. Меряются, а не задаются числом: подписи вкладок
    /// переводятся, и в разных языках строка разной высоты.
    @Environment(\.notchContentLeadingInset) private var contentLeadingInset
    @Environment(\.notchContentTrailingInset) private var contentTrailingInset
    @Environment(\.notchContentBottomInset) private var contentBottomInset
    @State private var tabsHeight: CGFloat = 24
    @State private var footerHeight: CGFloat = 16
    @StateObject private var updates = UpdateChecker()
    /// Доступ выдают в чужом окне — Системных настройках, о котором нам
    /// никто не сообщит. Пока настройки открыты, опрашиваем систему сами.
    @StateObject private var access = AccessWatch()

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: TileMetrics.gap),
        count: 3
    )

    /// Насколько прокрутка вылезает за поля содержимого панели.
    ///
    /// Без этого сверху под заголовком и снизу под строкой версии оставались
    /// пустые поля: список кончался раньше кромки, и поле читалось как чёрная
    /// полоса. Теперь список доезжает до самой кромки панели и уходит туда
    /// размытым, а строки стоят на своих прежних местах — им возвращают
    /// отступ обратно.
    private var topBleed: CGFloat { contentTopInset }
    /// Зеркало верхнего — и берётся оттуда же, из окружения, а не из
    /// постоянной поля.
    ///
    /// Числом снизу стояло `contentPadding`, и при колонке это было верно:
    /// под списком там и правда одно поле. Но при ряде снизу под ним ещё
    /// зазор и сами кнопки, а список об этом не знал: полоса размытия
    /// вставала на сорок точек выше кромки и читалась подложкой поперёк
    /// карточек, а строка версии ложилась прямо на них.
    private var bottomBleed: CGFloat { contentBottomInset }

    /// То же самое вбок. Полоса размытия у края прокрутки — это край
    /// корпуса, а не край списка: обрезанная по ширине карточек, она
    /// читается плашкой поверх них, и видно, где она началась. Поэтому
    /// прокрутка растягивается до самых кромок панели, а строки получают
    /// свои поля обратно внутри неё.
    private var leadingBleed: CGFloat { contentLeadingInset }
    private var trailingBleed: CGFloat { contentTrailingInset }

    var body: some View {
        // Список идёт во всю высоту панели и уезжает под заголовок, под строку
        // вкладок и под строку версии, а не упирается в них. Строки лежат
        // поверх, а читаются потому, что под ними содержимое размыто
        // ступенями — плашек под ними нет.
        BlurredEdgeScrollView(
            .vertical,
            // Полоса ровно от кромки до нижней границы строки вкладок и до
            // верхней границы подвала: вся лестница радиусов укладывается в
            // то место, которое и так занято ими, а в видимые карточки не
            // заходит совсем. Дальше — резко.
            leading: topBleed + tabsHeight,
            trailing: bottomBleed + footerHeight,
            always: .both
        ) {
            VStack(alignment: .leading, spacing: TileMetrics.gap) {
                content
            }
            .padding(.top, topBleed + tabsHeight + 10)
            // Под подвалом остаётся целый зазор сетки, а не половина:
            // с восемью точками последний ряд плиток дотягивался до
            // строки «Настройки» и читался обрезанным — значение под
            // подписью уходило под неё.
            .padding(.bottom, bottomBleed + footerHeight + TileMetrics.gap * 2)
            .padding(.leading, leadingBleed)
            .padding(.trailing, trailingBleed + 4)
        }
        .scrollIndicators(.never)
        .overlay(alignment: .top) {
            tabs
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tabsHeight = $0 }
                .padding(.top, topBleed)
                .padding(.leading, leadingBleed)
                .padding(.trailing, trailingBleed)
        }
        .overlay(alignment: .bottom) {
            footer
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
                .padding(.bottom, bottomBleed)
                .padding(.leading, leadingBleed)
                .padding(.trailing, trailingBleed)
        }
        .padding(.top, -topBleed)
        .padding(.bottom, -bottomBleed)
        .padding(.leading, -leadingBleed)
        .padding(.trailing, -trailingBleed)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            updates.checkIfNeeded()
            access.start()
        }
        .onDisappear { access.stop() }
    }

    /// Подвал: одна строка с номером версии. Штамп сборки спрятан под ней
    /// подсказкой — смотрят на него редко, а стоя рядом он читался как
    /// вторая половина номера и занимал столько же места.
    ///
    /// Вышла новее — строка перестаёт быть подписью: красится, обзаводится
    /// стрелкой «скачать» и целиком становится кнопкой.
    private var footer: some View {
        Group {
            if let available = updates.availableVersion, let url = updates.downloadURL {
                UpdateFooterButton(
                    available: available,
                    hint: "\(settings.t(.settingsUpdateAvailable)): \(AppVersion.display(available))"
                ) {
                    NSWorkspace.shared.open(url)
                }
            } else if settings.railPlacement.isVertical {
                // Штамп сборки стоит прямо в строке, а не в подсказке по
                // наведению: он и заведён ради того, чтобы одним взглядом
                // понять, ту ли сборку смотришь. В тултипе для этого надо
                // сперва заподозрить, что смотришь старую, — то есть ровно
                // тогда, когда он уже не помогает.
                //
                // Подвал остался только колонке. При ряде поперёк штамп
                // переехал в сам ряд: там между заголовком и шестерёнкой
                // и так пусто, а тут он занимал целую строку ради одной
                // подписи. Новая версия — другое дело: её кнопку
                // показываем при любой раскладке, мимо неё пройти нельзя.
                Text("Notch \(AppVersion.display) · \(AppVersion.build)")
                    .font(.system(size: 10))
                    .foregroundStyle(NotchTheme.textTertiary)
                    .lineLimit(1)
                    // Те же поля, что у кнопки обновления: строка стоит на
                    // одном месте независимо от того, вышло что-то или нет.
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
            }
        }
        // Слева строка стоит, пока рейл — колонка: там под ней пусто.
        // Ряд снизу занимает ту же левую сторону заголовком модуля, и
        // версия ложилась прямо на него; у правой кромки под ней только
        // шестерёнка, а её строка не касается.
        .frame(maxWidth: .infinity, alignment: settings.railPlacement.isBottom ? .trailing : .leading)
    }

    /// Полоса разделов. Подписи переводятся, и в русском они длиннее английских:
    /// восемь штук в 640 точек уже не влезают. Поэтому каждая подпись держится
    /// в одну строку своей естественной ширины, а лишнее уезжает вбок прокруткой —
    /// иначе SwiftUI сжимает кнопки и рвёт слова посередине.
    private var tabs: some View {
        // Строка едет обычной прокруткой, без размытых краёв. Полосы стояли
        // здесь для мягкого края, но подписи ростом в 11 точек короче любой
        // разумной полосы: раздел у кромки уходил под неё целиком — оставалось
        // «Приватнос» и темнота. Мягкость тут и не нужна: под строкой список
        // и так размыт своей полосой, обрезать нечего.
        ScrollViewReader { strip in
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(Section.allCases) { candidate in
                        let isActive = candidate == section
                        Button {
                            section = candidate
                        } label: {
                            Text(settings.t(candidate.titleKey))
                                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                                .foregroundStyle(isActive ? NotchTheme.textPrimary : NotchTheme.textTertiary)
                                .lineLimit(1)
                                .fixedSize()
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background {
                                    // У выбранного раздела плашка не красится, а
                                    // размывает то, что под ней: список едет прямо
                                    // под строкой, и сплошная заливка читалась бы
                                    // как дырка в нём.
                                    if isActive {
                                        Capsule()
                                            .fill(.ultraThinMaterial)
                                            .overlay { Capsule().fill(NotchTheme.accentSelection) }
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .id(candidate)
                    }
                }
                .padding(.vertical, 1)
                // Крайние разделы не упираются в кромки: прокрутив до края,
                // получаешь подпись впритык к границе панели.
                .padding(.trailing, 10)
            }
            .scrollIndicators(.never)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Тем же движением, что и смена содержимого: строка доезжает,
            // пока новый раздел раскрывается, а не после него.
            .onChange(of: section) { _, new in
                withAnimation(NotchTheme.expandAnimation) {
                    strip.scrollTo(new, anchor: .center)
                }
            }
            // Панель открывается на том разделе, где её закрыли: строка
            // должна прийти к нему сразу, без проезда на глазах.
            .onAppear { strip.scrollTo(section, anchor: .center) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .appearance: appearance
        case .notch: notchSection
        case .modules: modules
        case .behaviour: behaviourSection
        case .hotkeys: hotkeys
        case .app: app
        }
    }

    // MARK: - Разделы

    /// Вид: как выглядит раскрытая панель и каким приложение считает вырез.
    ///
    /// Раньше рейл жил в «Основных» — не потому, что он основной, а потому
    /// что для него не завели раздела: пять плиток про рейл топили собой
    /// язык и автозапуск. Подгонка выреза пришла сюда из «Поведения» по
    /// той же причине: ширина и высота в точках — это вид, а не повадки.
    private var appearance: some View {
        VStack(alignment: .leading, spacing: TileMetrics.gap) {
            GroupTitle(settings.t(.settingsGroupRail))

            LazyVGrid(columns: columns, spacing: TileMetrics.gap) {
                MenuTile(
                    title: settings.t(.settingsRailPlacement),
                    value: settings.t(settings.railPlacement.titleKey),
                    symbol: "sidebar.left",
                    options: RailPlacement.allCases.map { ($0.id, settings.t($0.titleKey)) }
                ) { id in
                    guard let picked = RailPlacement(rawValue: id) else { return }
                    settings.railPlacement = picked
                }

                MenuTile(
                    title: settings.t(.settingsRailSize),
                    value: settings.t(settings.railSize.titleKey),
                    symbol: "arrow.up.left.and.arrow.down.right",
                    options: RailSize.allCases.map { ($0.id, settings.t($0.titleKey)) }
                ) { id in
                    guard let picked = RailSize(rawValue: id) else { return }
                    settings.railSize = picked
                }

                MenuTile(
                    title: settings.t(.settingsRailIcons),
                    value: settings.t(settings.railIconStyle.titleKey),
                    symbol: "paintpalette",
                    options: RailIconStyle.allCases.map { ($0.id, settings.t($0.titleKey)) }
                ) { id in
                    guard let picked = RailIconStyle(rawValue: id) else { return }
                    settings.railIconStyle = picked
                }

                ToggleTile(
                    title: settings.t(.settingsRailInlineGear),
                    symbol: "gearshape",
                    tint: TilePalette.teal,
                    isOn: settings.railSettingsInline,
                    onLabel: settings.t(.settingsStateOn),
                    offLabel: settings.t(.settingsStateOff)
                ) {
                    settings.railSettingsInline.toggle()
                }

                // Подписи и зазор — свойства ряда поперёк. В колонке
                // подписи негде положить, а зазор там растит высоту
                // панели: показывать эти тайлы значило бы обещать то,
                // чего раскладка не сделает.
                if !settings.railPlacement.isVertical {
                    MenuTile(
                        title: settings.t(.settingsRailLabels),
                        value: settings.t(settings.railLabels.titleKey),
                        symbol: "textformat.size",
                        options: RailLabels.allCases.map { ($0.id, settings.t($0.titleKey)) }
                    ) { id in
                        guard let picked = RailLabels(rawValue: id) else { return }
                        settings.railLabels = picked
                    }

                    MenuTile(
                        title: settings.t(.settingsRailGap),
                        value: settings.t(settings.railGap.titleKey),
                        symbol: "arrow.left.and.right",
                        options: RailGap.allCases.map { ($0.id, settings.t($0.titleKey)) }
                    ) { id in
                        guard let picked = RailGap(rawValue: id) else { return }
                        settings.railGap = picked
                    }
                }
            }

            PanelHint(settings.t(.settingsRailHint))

            GroupTitle(settings.t(.settingsGroupNotchTuning))

            LazyVGrid(columns: columns, spacing: TileMetrics.gap) {
                ToggleTile(
                    title: settings.t(.behaviourSimulatedNotch),
                    symbol: "rectangle.topthird.inset.filled",
                    tint: TilePalette.pink,
                    isOn: behaviour.forceSimulatedNotch,
                    onLabel: settings.t(.settingsStateOn),
                    offLabel: settings.t(.settingsStateOff)
                ) {
                    behaviour.forceSimulatedNotch.toggle()
                }

                ActionTile(
                    title: settings.t(.behaviourResetTuning),
                    symbol: "arrow.uturn.backward",
                    action: behaviour.resetTuning
                )
            }

            SliderTile(
                title: settings.t(.behaviourNotchWidth),
                symbol: "arrow.left.and.right",
                value: $behaviour.widthAdjust,
                range: -60...120
            )

            SliderTile(
                title: settings.t(.behaviourNotchHeight),
                symbol: "arrow.up.and.down",
                value: $behaviour.heightAdjust,
                range: -10...20
            )

            PanelHint(settings.t(.behaviourTuningHint))
        }
    }

    /// Закреплённая плашка трека стоит на вырезе постоянно. Остальные
    /// кружки она не гасит — они отходят за её края, — но собственный
    /// кружок музыки при ней не показывается: плашка и так про этот трек.
    private var isPlatePinned: Bool {
        settings.pinMusicActivity
            && settings.isActivityEnabled(.music)
            && music.info?.isPlaying == true
    }

    private func isIslandCovered(_ indicator: IslandIndicator) -> Bool {
        isPlatePinned && indicator.activityKind == .music
    }

    // MARK: - Вырез

    /// Всё, что видно, пока панель схлопнута: кружки по бокам и плашки.
    ///
    /// Раньше это были два раздела — «Остров» и «События», — и разрезаны
    /// они были по типу виджета. Чтобы убрать музыку из выреза, надо было
    /// заранее знать, кружок это или плашка; человек же думает «вырез».
    private var notchSection: some View {
        VStack(alignment: .leading, spacing: TileMetrics.gap) {
            GroupTitle(settings.t(.settingsGroupIsland))

            LazyVGrid(columns: columns, spacing: TileMetrics.gap) {
                ForEach(IslandIndicator.allCases) { indicator in
                    IslandTile(
                        settings: settings,
                        shelf: shelf,
                        music: music,
                        timers: timers,
                        indicator: indicator,
                        isCovered: isIslandCovered(indicator)
                    )
                }

                // Закрепление плашки трека стояло в «Показе»: по природе
                // это и правда мера времени. Но место у него одно с
                // кружками, и занимает оно их целиком — пока плашка висит,
                // кружкам негде быть. Настройке место там, где виден её
                // побочный эффект, а не там, где она заведена.
                if settings.isActivityEnabled(.music) {
                    PinnedMusicTile(settings: settings, music: music)
                }
            }

            PanelHint(settings.t(.settingsIslandHint))

            if isPlatePinned {
                PanelHint(settings.t(.settingsPinMusicActivityHint))
            }

            GroupTitle(settings.t(.settingsGroupBadges))

            LazyVGrid(columns: columns, spacing: TileMetrics.gap) {
                ForEach(NotchActivity.Kind.allCases) { kind in
                    ToggleTile(
                        title: settings.t(kind.titleKey),
                        symbol: kind.symbol,
                        tint: TilePalette.tint(for: kind.rawValue),
                        isOn: settings.isActivityEnabled(kind),
                        onLabel: settings.t(.settingsStateOn),
                        offLabel: settings.t(.settingsStateOff)
                    ) {
                        let enable = !settings.isActivityEnabled(kind)
                        settings.setActivityEnabled(enable, for: kind)
                        // Перехвату клавиш нужен доступ — спрашиваем сразу,
                        // а не ждём, пока пользователь сам найдёт почему
                        // «ничего не поменялось».
                        if enable, kind == .levels, !AXIsProcessTrusted() {
                            SystemAccess.requestAccessibility()
                        }
                    }
                }
            }

            PanelHint(settings.t(.settingsActivitiesHint))

            if settings.isActivityEnabled(.levels) {
                PanelHint(settings.t(.settingsLevelsHint))
            }

            GroupTitle(settings.t(.settingsGroupTiming))

            SliderTile(
                title: settings.t(.activityDuration),
                symbol: "timer",
                value: $settings.activityDuration,
                range: 1...8
            )

            // Слайдеры своих плашек: выключил повод — ушла и его мера.
            if settings.isActivityEnabled(.calendar) {
                SliderTile(
                    title: settings.t(.settingsCalendarLead),
                    symbol: "calendar.badge.clock",
                    value: $settings.calendarLeadMinutes,
                    range: 1...30
                )
            }

            if settings.isActivityEnabled(.power) {
                SliderTile(
                    title: settings.t(.activityLowBatteryThreshold),
                    symbol: "battery.25percent",
                    value: $settings.lowBatteryThreshold,
                    range: 5...50
                )
            }
        }
    }

    // MARK: - Модули

    private var modules: some View {
        VStack(alignment: .leading, spacing: TileMetrics.gap) {
            GroupTitle(settings.t(.settingsGroupModuleList))

            ModuleGrid(settings: settings, columns: columns)
            PanelHint(settings.t(.settingsModulesReorderHint))

            // Визуализатор стоял в «Поведении» — рядом с симулированным
            // вырезом и подгонкой в точках, отчего читался системной
            // настройкой. Это настройка одного модуля, и живёт она у него.
            if settings.isEnabled("music") {
                GroupTitle(settings.t(.settingsGroupMusic))

                LazyVGrid(columns: columns, spacing: TileMetrics.gap) {
                    ToggleTile(
                        title: settings.t(.musicVisualizer),
                        symbol: "waveform",
                        tint: TilePalette.pink,
                        isOn: settings.musicVisualizer,
                        onLabel: settings.t(.settingsStateOn),
                        offLabel: settings.t(.settingsStateOff)
                    ) {
                        settings.musicVisualizer.toggle()
                    }
                }
                PanelHint(settings.t(.musicVisualizerHint))
            }

            ActionTile(
                title: settings.t(.settingsOpenWindow),
                symbol: "macwindow",
                action: actions.openSettingsWindow
            )
            .frame(width: TileMetrics.singleWidth)
        }
    }

    // MARK: - Поведение

    /// Где показывать панель, когда раскрывать и когда убираться с глаз.
    private var behaviourSection: some View {
        VStack(alignment: .leading, spacing: TileMetrics.gap) {
            GroupTitle(settings.t(.settingsGroupDisplay))

            LazyVGrid(columns: columns, spacing: TileMetrics.gap) {
                MenuTile(
                    title: settings.t(.behaviourDisplay),
                    value: settings.t(behaviour.displayTarget.titleKey),
                    symbol: "display",
                    options: BehaviourSettings.DisplayTarget.allCases.map {
                        ($0.id, settings.t($0.titleKey))
                    }
                ) { id in
                    guard let picked = BehaviourSettings.DisplayTarget(rawValue: id) else { return }
                    behaviour.displayTarget = picked
                }
            }

            GroupTitle(settings.t(.settingsGroupExpand))

            LazyVGrid(columns: columns, spacing: TileMetrics.gap) {
                ToggleTile(
                    title: settings.t(.behaviourExpandOnHover),
                    symbol: "cursorarrow.motionlines",
                    tint: TilePalette.blue,
                    isOn: behaviour.expandOnHover,
                    onLabel: settings.t(.settingsStateOn),
                    offLabel: settings.t(.settingsStateOff)
                ) {
                    behaviour.expandOnHover.toggle()
                }

                ToggleTile(
                    title: settings.t(.behaviourDropToShelf),
                    symbol: "arrow.down.doc",
                    tint: TilePalette.teal,
                    isOn: behaviour.dropToShelf,
                    onLabel: settings.t(.settingsStateOn),
                    offLabel: settings.t(.settingsStateOff)
                ) {
                    behaviour.dropToShelf.toggle()
                }
            }

            PanelHint(settings.t(.behaviourDropToShelfHint))

            // Задержка — мера наведения: без наведения мерить нечего.
            if behaviour.expandOnHover {
                SliderTile(
                    title: settings.t(.behaviourHoverDuration),
                    symbol: "clock",
                    value: $behaviour.hoverDuration,
                    range: 0...1
                )
            }

            PanelHint(settings.t(.behaviourHint))

            if access.accessibility == .missing {
                PanelHint(settings.t(.accessGesturesHint))
            }

            GroupTitle(settings.t(.settingsGroupHide))

            LazyVGrid(columns: columns, spacing: TileMetrics.gap) {
                ToggleTile(
                    title: settings.t(.behaviourHideFullscreen),
                    symbol: "arrow.up.left.and.arrow.down.right",
                    tint: TilePalette.indigo,
                    isOn: behaviour.hideInFullscreen,
                    onLabel: settings.t(.settingsStateOn),
                    offLabel: settings.t(.settingsStateOff)
                ) {
                    behaviour.hideInFullscreen.toggle()
                }

                ToggleTile(
                    title: settings.t(.behaviourHideGaming),
                    symbol: "gamecontroller",
                    tint: TilePalette.orange,
                    isOn: behaviour.hideWhileGaming,
                    onLabel: settings.t(.settingsStateOn),
                    offLabel: settings.t(.settingsStateOff)
                ) {
                    behaviour.hideWhileGaming.toggle()
                }

                ToggleTile(
                    title: settings.t(.behaviourHideCapture),
                    symbol: "eye.slash",
                    tint: TilePalette.teal,
                    isOn: behaviour.hideFromScreenCapture,
                    onLabel: settings.t(.settingsStateOn),
                    offLabel: settings.t(.settingsStateOff)
                ) {
                    behaviour.hideFromScreenCapture.toggle()
                }
            }

            GroupTitle(settings.t(.settingsGroupGestures))

            LazyVGrid(columns: columns, spacing: TileMetrics.gap) {
                // Оба жеста живут над свёрнутым вырезом, а раскрытие по
                // наведению не оставляет им этого мига: курсор вошёл —
                // панель уже открыта, смахивать нечего. Пока наведение
                // включено, плитки гаснут и не дают себя нажать.
                ToggleTile(
                    title: settings.t(.behaviourSwipeToSkip),
                    symbol: "hand.draw",
                    tint: TilePalette.pink,
                    isOn: behaviour.swipeToSkip,
                    onLabel: settings.t(.settingsStateOn),
                    offLabel: settings.t(.settingsStateOff),
                    isEnabled: behaviour.gesturesReachable
                ) {
                    behaviour.swipeToSkip.toggle()
                }

                ToggleTile(
                    title: settings.t(.behaviourSwipeToToggle),
                    symbol: "arrow.up.and.down.circle",
                    tint: TilePalette.blue,
                    isOn: behaviour.swipeToToggle,
                    onLabel: settings.t(.settingsStateOn),
                    offLabel: settings.t(.settingsStateOff),
                    isEnabled: behaviour.gesturesReachable
                ) {
                    behaviour.swipeToToggle.toggle()
                }
            }

            PanelHint(settings.t(
                behaviour.gesturesReachable ? .behaviourGesturesHint : .behaviourGesturesBlocked
            ))
        }
    }

    // MARK: - Клавиши

    private var hotkeys: some View {
        VStack(alignment: .leading, spacing: TileMetrics.gap) {
            LazyVGrid(columns: columns, spacing: TileMetrics.gap) {
                ForEach(settings.hotkeyActions) { action in
                    TileSurface(fill: TilePalette.idleFill) {
                        VStack(alignment: .leading, spacing: 6) {
                            TileIcon(symbol: action.symbol, color: NotchTheme.textTertiary)
                            Spacer(minLength: 0)
                            Text(settings.hotkeyTitle(for: action))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(NotchTheme.textSecondary)
                                .lineLimit(1)
                            KeyRecorder(
                                combo: Binding(
                                    get: { settings.combo(for: action) },
                                    set: { settings.setCombo($0, for: action) }
                                ),
                                recordTitle: settings.t(.hotkeyRecord),
                                recordingTitle: settings.t(.hotkeyRecording),
                                emptyTitle: settings.t(.hotkeyNone),
                                clearTitle: settings.t(.hotkeyClear),
                                foreground: NotchTheme.textPrimary,
                                background: NotchTheme.accentSelection
                            )
                        }
                    }
                }
            }
            PanelHint(settings.t(.hotkeysHint))

            if access.accessibility == .missing {
                PanelHint(settings.t(.accessHotkeysHint))
            }
        }
    }

    // MARK: - Приложение

    /// Само приложение: язык, запуск, отклик и то, что оно хранит.
    ///
    /// «Отклик» и «Приватность» были отдельными разделами ради четырёх и
    /// двух плиток — и из-за них строка вкладок не влезала в панель.
    private var app: some View {
        VStack(alignment: .leading, spacing: TileMetrics.gap) {
            GroupTitle(settings.t(.settingsGroupBasics))

            LazyVGrid(columns: columns, spacing: TileMetrics.gap) {
                MenuTile(
                    title: settings.t(.settingsLanguage),
                    value: settings.name(for: settings.language),
                    symbol: "globe",
                    options: AppLanguage.allCases.map { ($0.id, settings.name(for: $0)) }
                ) { id in
                    guard let picked = AppLanguage(rawValue: id) else { return }
                    settings.language = picked
                }

                ToggleTile(
                    title: settings.t(.settingsLaunchAtLogin),
                    symbol: "power",
                    tint: TilePalette.green,
                    isOn: settings.launchAtLogin,
                    onLabel: settings.t(.settingsStateOn),
                    offLabel: settings.t(.settingsStateOff)
                ) {
                    settings.launchAtLogin.toggle()
                }
                // Тут тусклость на месте: настройка зависит не от соседней
                // плитки, а от системы, и спрятать её значило бы соврать,
                // что такой возможности нет вовсе.
                .disabled(!LaunchAtLogin.isAvailable)
                .opacity(LaunchAtLogin.isAvailable ? 1 : 0.4)

                ToggleTile(
                    title: settings.t(.behaviourHideMenuBar),
                    symbol: "menubar.rectangle",
                    tint: TilePalette.green,
                    isOn: behaviour.hideMenuBarIcon,
                    onLabel: settings.t(.settingsStateOn),
                    offLabel: settings.t(.settingsStateOff)
                ) {
                    behaviour.hideMenuBarIcon.toggle()
                }

                ActionTile(
                    title: settings.t(.settingsOpenWindow),
                    symbol: "macwindow",
                    action: actions.openSettingsWindow
                )
            }

            if let error = settings.launchAtLoginError {
                PanelHint(error)
            } else if !LaunchAtLogin.isAvailable {
                PanelHint(settings.t(.settingsLaunchUnavailable))
            }

            GroupTitle(settings.t(.accessGroup))

            LazyVGrid(columns: columns, spacing: TileMetrics.gap) {
                AccessTile(
                    title: settings.t(.accessAccessibility),
                    symbol: "hand.raised",
                    state: access.accessibility,
                    settings: settings
                ) {
                    SystemAccess.requestAccessibility()
                }

                AccessTile(
                    title: settings.t(.accessCalendar),
                    symbol: "calendar",
                    state: access.calendar,
                    settings: settings
                ) {
                    SystemAccess.openCalendarSettings()
                }

                ActionTile(
                    title: settings.t(.accessRevealApp),
                    symbol: "folder",
                    action: SystemAccess.revealApp
                )
            }

            PanelHint(settings.t(.accessHint))

            GroupTitle(settings.t(.settingsGroupFeedback))

            LazyVGrid(columns: columns, spacing: TileMetrics.gap) {
                ToggleTile(
                    title: settings.t(.settingsHaptics),
                    symbol: "hand.tap",
                    tint: TilePalette.pink,
                    isOn: settings.hapticsEnabled,
                    onLabel: settings.t(.settingsStateOn),
                    offLabel: settings.t(.settingsStateOff)
                ) {
                    settings.hapticsEnabled.toggle()
                }

                ToggleTile(
                    title: settings.t(.settingsSound),
                    symbol: "speaker.wave.2",
                    tint: TilePalette.blue,
                    isOn: settings.soundEnabled,
                    onLabel: settings.t(.settingsStateOn),
                    offLabel: settings.t(.settingsStateOff)
                ) {
                    settings.soundEnabled.toggle()
                }

                if settings.soundEnabled {
                    MenuTile(
                        title: settings.t(.settingsSoundChoice),
                        value: settings.name(for: settings.sound),
                        symbol: "waveform",
                        options: NotchSound.allCases.map { ($0.id, settings.name(for: $0)) }
                    ) { id in
                        guard let picked = NotchSound(rawValue: id) else { return }
                        settings.sound = picked
                        actions.previewSound(picked)
                    }
                }
            }

            if settings.soundEnabled {
                SliderTile(
                    title: settings.t(.settingsVolume),
                    symbol: "speaker.wave.3",
                    value: $settings.feedbackVolume,
                    range: 0...0.4,
                    actionTitle: settings.t(.settingsSoundPreview)
                ) {
                    actions.previewSound(settings.sound)
                }
            }

            PanelHint(settings.t(.settingsFeedbackHint))

            GroupTitle(settings.t(.settingsGroupClipboard))

            LazyVGrid(columns: columns, spacing: TileMetrics.gap) {
                ToggleTile(
                    title: settings.t(.settingsPersistClipboard),
                    symbol: "externaldrive",
                    tint: TilePalette.indigo,
                    isOn: settings.persistClipboard,
                    onLabel: settings.t(.settingsStateOn),
                    offLabel: settings.t(.settingsStateOff)
                ) {
                    settings.persistClipboard.toggle()
                }

                ActionTile(
                    title: settings.t(.settingsClearClipboard),
                    symbol: "trash",
                    tint: TilePalette.red,
                    action: actions.clearClipboardHistory
                )
            }

            PanelHint(settings.t(.settingsPersistClipboardHint))
        }
    }
}


// MARK: - Плитки

private enum TileMetrics {
    static let gap: CGFloat = 8
    static let height: CGFloat = 64
    static let radius: CGFloat = 12
    static let padding: CGFloat = 10
    /// Ширина одной плитки в трёхколоночной сетке панели.
    static let singleWidth: CGFloat = 176
}

private enum TilePalette {
    static let blue = Color(red: 0.24, green: 0.50, blue: 0.96)
    static let green = Color(red: 0.20, green: 0.68, blue: 0.38)
    static let pink = Color(red: 0.90, green: 0.32, blue: 0.53)
    static let indigo = Color(red: 0.42, green: 0.38, blue: 0.86)
    static let orange = Color(red: 0.94, green: 0.55, blue: 0.16)
    static let teal = Color(red: 0.16, green: 0.66, blue: 0.66)
    static let red = Color(red: 0.87, green: 0.30, blue: 0.27)
    static let purple = Color(red: 0.62, green: 0.36, blue: 0.90)
    static let lime = Color(red: 0.50, green: 0.70, blue: 0.16)
    static let cyan = Color(red: 0.14, green: 0.62, blue: 0.86)
    static let amber = Color(red: 0.88, green: 0.58, blue: 0.06)
    static let magenta = Color(red: 0.78, green: 0.30, blue: 0.70)
    static let lemon = Color(red: 0.78, green: 0.68, blue: 0.08)
    static let slate = Color(red: 0.38, green: 0.48, blue: 0.64)

    /// Плитка выключена — тусклая серая, как неактивная сцена в Home.
    static let idleFill = Color.white.opacity(0.07)

    static func tint(for moduleID: String) -> Color {
        switch moduleID {
        case "music": return pink
        case "clipboard": return blue
        case "trash": return red
        case "snippets": return orange
        case "shelf": return indigo
        case "translate": return teal
        case "power": return green
        case "lockScreen": return indigo
        case "audioDevice": return teal
        case "focus": return indigo
        case "brightness": return orange
        case "levels": return teal
        case "calendar": return red
        case "reminders": return cyan
        case "mirror": return purple
        case "askAI": return lime
        case "shortcuts": return amber
        case "converter": return magenta
        case "emoji": return lemon
        case "teleprompter": return slate
        case "battery": return green
        case "weather": return blue
        default: return green
        }
    }
}

/// Общая подложка плитки: одинаковый размер, радиус и отступы у всех типов.
private struct TileSurface<Content: View>: View {
    let fill: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(TileMetrics.padding)
            .frame(maxWidth: .infinity, minHeight: TileMetrics.height, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: TileMetrics.radius, style: .continuous)
                    .fill(fill)
            }
    }
}

private struct TileIcon: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(color)
    }
}

/// Нажатие даёт короткое сжатие — плитка отзывается на клик.
private struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Кружок у выреза — одной плиткой, как и всё остальное в настройках.
///
/// Раскладкой-картинкой это уже было: вырез посередине, карточки по бокам,
/// перетаскивание. Картинка объясняла, но жила отдельной жизнью — широкая
/// полоса посреди сетки из плиток. Здесь то же знание уложено в плитку:
/// сверху микро-вырез с живым кружком на своей стороне, снизу имя и
/// сторона. Куда встанет кружок, видно до того, как прочитано слово.
private struct IslandTile: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var shelf: ShelfStore
    @ObservedObject var music: NowPlayingCoordinator
    @ObservedObject var timers: TimerIslandState
    let indicator: IslandIndicator
    /// Вырез занят закреплённой плашкой: кружку сейчас негде встать.
    let isCovered: Bool

    /// Микро-вырез: та же форма, что у панели, только уменьшенная.
    ///
    /// Мельче было аккуратнее, но бессмысленно: стопка превью полки в
    /// двенадцать точек превращалась в серую крупу, а обложка трека — в
    /// пятно. Показываем ровно затем, чтобы это было видно.
    fileprivate static let notchWidth: CGFloat = 46
    fileprivate static let notchHeight: CGFloat = 16
    /// Место под кружок с каждой стороны. Фиксированное: иначе вырез
    /// съезжал бы от стороны к стороне и от длины трея полки.
    fileprivate static let slotWidth: CGFloat = 52

    private var isOn: Bool { settings.isIslandEnabled(indicator) }
    private var side: IslandSide { settings.islandSide(for: indicator) }
    private var tint: Color { TilePalette.tint(for: indicator.moduleID) }
    /// Плитка не врёт про состояние: перекрытый кружок на экране ровно
    /// так же отсутствует, как выключенный, — значит и плитка у него
    /// выключенная, а не цветная с погасшей картинкой.
    private var showsOn: Bool { isOn && !isCovered }

    var body: some View {
        TileSurface(fill: showsOn ? tint : TilePalette.idleFill) {
            VStack(alignment: .leading, spacing: 4) {
                preview
                    // Макет — своя кнопка внутри плитки: тап по нему
                    // переносит кружок, а не выключает модуль.
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                            if isOn {
                                settings.setIslandSide(side == .left ? .right : .left, for: indicator)
                            } else {
                                settings.setIslandEnabled(true, for: indicator)
                            }
                        }
                    }

                Spacer(minLength: 2)

                Text(settings.t(indicator.titleKey))
                    .font(.system(size: 10))
                    .foregroundStyle(showsOn ? Color.white.opacity(0.7) : NotchTheme.textTertiary)
                    .lineLimit(1)
                Text(showsOn ? settings.t(side.titleKey) : settings.t(.settingsStateOff))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(showsOn ? .white : NotchTheme.textPrimary)
                    .lineLimit(1)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: TileMetrics.radius, style: .continuous))
        .animation(.easeOut(duration: 0.2), value: isCovered)
        .onTapGesture {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                settings.setIslandEnabled(!isOn, for: indicator)
            }
        }
    }

    /// Вырез с кружком сбоку. Пустая сторона держит своё место, поэтому
    /// вырез стоит неподвижно, а переезжает только кружок.
    ///
    /// На свободной стороне — пунктирный след того же размера: видно, что
    /// место есть и туда можно переехать. Без него плитка показывала
    /// только «как сейчас», а не «как можно».
    private var preview: some View {
        HStack(alignment: .top, spacing: 2) {
            slot(.left)

            NotchShape(topRadius: 0, bottomRadius: 5)
                .fill(Color.black)
                .frame(width: Self.notchWidth, height: Self.notchHeight)

            slot(.right)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        // Перекрытый кружок гаснет так же, как выключенный: включён он или
        // нет, на экране его сейчас всё равно нет.
        .opacity(showsOn ? 1 : 0.35)
        .animation(.spring(response: 0.26, dampingFraction: 0.82), value: side)
        .animation(.easeOut(duration: 0.2), value: isCovered)
    }

    @ViewBuilder
    private func slot(_ slotSide: IslandSide) -> some View {
        HStack(spacing: 0) {
            if slotSide == .left { Spacer(minLength: 0) }
            if slotSide == side { dot } else { ghost }
            if slotSide == .right { Spacer(minLength: 0) }
        }
        .frame(width: Self.slotWidth, alignment: slotSide == .left ? .trailing : .leading)
    }

    /// Свободное место под кружок. Ширину берёт у настоящего — тогда
    /// видно не просто «сюда можно», а какого размера встанет.
    private var ghost: some View {
        Capsule()
            .strokeBorder(
                Color.white.opacity(0.35),
                style: StrokeStyle(lineWidth: 1, dash: [3, 3])
            )
            .frame(width: dotWidth * scale, height: Self.notchHeight)
    }

    /// Живой кружок, не заглушка: полка отдаёт те же превью, музыка — ту
    /// же обложку, что и у настоящего выреза. Настройка показывает не
    /// «здесь будет значок», а сам значок.
    ///
    /// Уменьшаем готовые вьюхи, а не рисуем вторую пару: иначе миниатюра
    /// со временем разойдётся с тем, что на экране.
    private var dot: some View {
        Group {
            switch indicator {
            case .shelf:
                if shelf.items.isEmpty {
                    placeholder
                } else {
                    ShelfIslandTray(store: shelf)
                        .frame(width: ShelfIslandTray.width(count: shelf.items.count))
                }
            case .music:
                MusicIslandBadge(music: music)
            case .timer:
                if timers.clock == nil {
                    placeholder
                } else {
                    TimerIslandBadge(state: timers)
                }
            }
        }
        .scaleEffect(scale, anchor: .center)
        .frame(width: dotWidth * scale, height: Self.notchHeight)
    }

    /// Во сколько раз кружок в плитке меньше настоящего: считаем от
    /// высоты выреза, чтобы пропорции остались теми же, что на экране.
    private var scale: CGFloat { Self.notchHeight / IslandMetrics.diameter }

    private var dotWidth: CGFloat {
        switch indicator {
        case .shelf:
            return shelf.items.isEmpty
                ? IslandMetrics.diameter
                : ShelfIslandTray.width(count: shelf.items.count)
        case .music:
            return MusicIslandBadge.width
        case .timer:
            return IslandMetrics.diameter
        }
    }

    /// Показывать нечего — на месте кружка значок модуля: место занято,
    /// но видно, что сейчас там пусто.
    private var placeholder: some View {
        ZStack {
            Circle().fill(NotchTheme.background)
            Image(systemName: indicator.symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(NotchTheme.textSecondary)
        }
        .frame(width: IslandMetrics.diameter, height: IslandMetrics.diameter)
        .overlay(Circle().strokeBorder(NotchTheme.islandBorder, lineWidth: IslandMetrics.border))
    }
}


/// Закреплённая плашка трека — плитка того же языка, что и кружки.
///
/// Превью тут не кружок, а сама плашка: она разъезжается во всю ширину
/// выреза, и по картинке видно, почему при ней кружкам не остаётся места.
private struct PinnedMusicTile: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var music: NowPlayingCoordinator

    private var isOn: Bool { settings.pinMusicActivity }
    private var tint: Color { TilePalette.tint(for: NotchActivity.Kind.music.rawValue) }

    /// Во всю ширину превью соседних плиток: два места под кружки плюс
    /// вырез между ними — ровно то, что плашка собой и закрывает.
    private var badgeWidth: CGFloat {
        IslandTile.slotWidth * 2 + IslandTile.notchWidth + 4
    }

    var body: some View {
        TileSurface(fill: isOn ? tint : TilePalette.idleFill) {
            VStack(alignment: .leading, spacing: 4) {
                preview

                Spacer(minLength: 2)

                Text(settings.t(.settingsPinMusicActivity))
                    .font(.system(size: 10))
                    .foregroundStyle(isOn ? Color.white.opacity(0.7) : NotchTheme.textTertiary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(isOn ? settings.t(.settingsStateOn) : settings.t(.settingsStateOff))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isOn ? .white : NotchTheme.textPrimary)
                    .lineLimit(1)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: TileMetrics.radius, style: .continuous))
        .onTapGesture {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                settings.pinMusicActivity.toggle()
            }
        }
    }

    /// Плашка — это раздувшийся вырез, поэтому и форма у неё та же.
    /// Внутри обложка и две строки текста — их не прочесть, да и не надо:
    /// читается силуэт.
    private var preview: some View {
        HStack(spacing: 4) {
            MusicIslandArtwork(music: music)
                .scaleEffect(scale, anchor: .center)
                .frame(width: IslandMetrics.diameter * scale, height: IslandTile.notchHeight)

            VStack(alignment: .leading, spacing: 2) {
                Capsule().fill(Color.white.opacity(0.75)).frame(width: 38, height: 2.5)
                Capsule().fill(Color.white.opacity(0.35)).frame(width: 24, height: 2.5)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .frame(width: badgeWidth, height: IslandTile.notchHeight + 4)
        .background {
            NotchShape(topRadius: 0, bottomRadius: 7).fill(Color.black)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .opacity(isOn ? 1 : 0.35)
    }

    private var scale: CGFloat { IslandTile.notchHeight / IslandMetrics.diameter }
}

private struct ToggleTile: View {
    let title: String
    let symbol: String
    let tint: Color
    let isOn: Bool
    let onLabel: String
    let offLabel: String
    /// Выключенная плитка не врёт про состояние: её значение — «Выкл»,
    /// даже если в настройках лежит «Вкл». Пока условие не выполнено,
    /// переключатель всё равно ничего не делает.
    var isEnabled: Bool = true
    let toggle: () -> Void

    private var showsOn: Bool { isOn && isEnabled }

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) { toggle() }
        } label: {
            TileSurface(fill: showsOn ? tint : TilePalette.idleFill) {
                VStack(alignment: .leading, spacing: 4) {
                    TileIcon(symbol: symbol, color: showsOn ? .white : NotchTheme.textTertiary)
                    Spacer(minLength: 2)
                    // Порядок и вес — как у MenuTile: сверху бледная подпись,
                    // снизу светлое значение. Иначе в одном ряду соседние
                    // плитки читаются как два разных элемента.
                    Text(title)
                        .font(.system(size: 10))
                        .foregroundStyle(showsOn ? Color.white.opacity(0.7) : NotchTheme.textTertiary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(showsOn ? onLabel : offLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(showsOn ? .white : NotchTheme.textPrimary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(TileButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }
}

/// Сетка модулей: те же плитки-переключатели, но их можно перетаскивать.
///
/// Порядок плиток здесь — это порядок вкладок в рейле, поэтому сетка не
/// показывает каталожный список, а сортирует его по `moduleOrder`.
///
/// Перетаскивание сделано своим жестом, а не системным drag-and-drop:
/// панель — неактивируемое безрамочное окно, и системная сессия
/// перетаскивания в ней ведёт себя непредсказуемо. Жест же ничего не знает
/// про окно: он двигает плитку и меняет порядок под курсором.
private struct ModuleGrid: View {
    @ObservedObject var settings: AppSettings
    let columns: [GridItem]

    private static let space = "modules.grid"

    /// Что тащим. Пока `nil`, жест — это ещё обычное нажатие.
    @State private var dragging: String?
    /// Плитка, которую сейчас держат: короткое сжатие вместо стиля кнопки.
    @State private var pressed: String?
    @State private var cursor: CGPoint = .zero
    /// Где внутри плитки её взяли: без этого плитка прыгала бы центром
    /// под курсор в момент захвата.
    @State private var grab: CGSize = .zero
    /// Порядок на время перетаскивания. В настройки он уезжает один раз —
    /// когда плитку отпустили, а не на каждом движении мыши.
    @State private var preview: [String] = []
    @State private var width: CGFloat = 0
    /// Высота ряда. Её меряют, а не берут из `TileMetrics`: там нижняя
    /// граница плитки, а настоящая выше — содержимое плитки её растит.
    /// Числом по ней считалось, над какой ячейкой курсор, и счёт ехал
    /// вниз с каждым рядом.
    @State private var cellHeight: CGFloat = TileMetrics.height

    private var columnCount: Int { max(columns.count, 1) }

    private var cellWidth: CGFloat {
        let gaps = CGFloat(columnCount - 1) * TileMetrics.gap
        return max((width - gaps) / CGFloat(columnCount), 1)
    }

    private var rowCount: Int {
        max(Int(ceil(Double(ModuleCatalog.descriptors.count) / Double(columnCount))), 1)
    }

    private func measure(_ size: CGSize) {
        width = size.width
        let gaps = CGFloat(rowCount - 1) * TileMetrics.gap
        cellHeight = max((size.height - gaps) / CGFloat(rowCount), 1)
    }

    private var descriptors: [ModuleCatalog.Descriptor] {
        ModuleCatalog.ordered(by: dragging == nil ? settings.moduleOrder : preview)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: TileMetrics.gap) {
            ForEach(Array(descriptors.enumerated()), id: \.element.id) { index, descriptor in
                tile(descriptor, at: index)
            }
        }
        .coordinateSpace(name: Self.space)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { measure($0) }
        // Жест висит на сетке, а не на плитках. На плитке он не жил: во
        // время перетаскивания плитка меняет место в сетке, SwiftUI
        // пересобирал её вместе с жестом — и обрывал его. Отпускание
        // не доходило, порядок не сохранялся, а поднятая плитка так и
        // оставалась крупнее соседей. Сетка же с места не двигается.
        .gesture(gesture)
        // Раздел закрыли посреди жеста — не оставляем висеть захват.
        .onDisappear { dragging = nil; pressed = nil }
    }

    private func tile(_ descriptor: ModuleCatalog.Descriptor, at index: Int) -> some View {
        let isDragged = dragging == descriptor.id
        return ModuleTile(
            title: settings.t(descriptor.titleKey),
            symbol: descriptor.symbol,
            tint: TilePalette.tint(for: descriptor.id),
            isOn: settings.isEnabled(descriptor.id),
            onLabel: settings.t(.settingsStateOn),
            offLabel: settings.t(.settingsStateOff),
            isDragged: isDragged,
            isPressed: pressed == descriptor.id && !isDragged
        )
        .offset(isDragged ? offset(at: index) : .zero)
        // Поднятая плитка едет поверх соседей, а не подныривает под них.
        .zIndex(isDragged ? 1 : 0)
    }

    // MARK: - Жест

    private var gesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                cursor = value.location
                guard dragging == nil else {
                    reorder()
                    return
                }
                guard let id = module(at: value.startLocation) else { return }
                pressed = id
                // Порог: клик по плитке — это всё ещё переключатель,
                // а не перетаскивание на ноль точек.
                guard hypot(value.translation.width, value.translation.height) > 6 else { return }
                begin(id, from: value.startLocation)
            }
            .onEnded { value in
                let held = pressed
                pressed = nil
                guard dragging != nil else {
                    // Клик засчитывается, только если отпустили там же, где
                    // нажали: увели палец на соседнюю плитку — ничего не
                    // переключилось, как у обычной кнопки.
                    guard let held, module(at: value.location) == held else { return }
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                        settings.setEnabled(!settings.isEnabled(held), for: held)
                    }
                    return
                }
                withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                    settings.moduleOrder = preview
                    dragging = nil
                }
            }
    }

    /// Модуль под точкой — или `nil`, если точка попала в зазор между
    /// плитками либо за конец сетки.
    private func module(at point: CGPoint) -> String? {
        let step = cellWidth + TileMetrics.gap
        let rowStep = cellHeight + TileMetrics.gap
        guard point.x >= 0, point.y >= 0 else { return nil }
        let column = Int(floor(point.x / step))
        let row = Int(floor(point.y / rowStep))
        guard column < columnCount else { return nil }
        guard point.x - CGFloat(column) * step <= cellWidth else { return nil }
        guard point.y - CGFloat(row) * rowStep <= cellHeight else { return nil }
        let order = descriptors.map(\.id)
        let index = row * columnCount + column
        return order.indices.contains(index) ? order[index] : nil
    }

    private func begin(_ id: String, from start: CGPoint) {
        let order = ModuleCatalog.ordered(by: settings.moduleOrder).map(\.id)
        preview = order
        guard let index = order.firstIndex(of: id) else { return }
        let centre = slotCentre(at: index)
        grab = CGSize(width: start.x - centre.x, height: start.y - centre.y)
        withAnimation(.spring(response: 0.24, dampingFraction: 0.8)) { dragging = id }
    }

    /// Двигает плитку в порядке под курсором — пока идёт жест, меняется
    /// только `preview`.
    private func reorder() {
        guard let dragging, let index = preview.firstIndex(of: dragging) else { return }
        let target = slotIndex(at: cursor)
        guard target != index else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            preview.move(
                fromOffsets: IndexSet(integer: index),
                toOffset: target > index ? target + 1 : target
            )
        }
    }

    // MARK: - Геометрия сетки

    private func offset(at index: Int) -> CGSize {
        let centre = slotCentre(at: index)
        return CGSize(
            width: cursor.x - centre.x - grab.width,
            height: cursor.y - centre.y - grab.height
        )
    }

    private func slotCentre(at index: Int) -> CGPoint {
        let column = index % columnCount
        let row = index / columnCount
        return CGPoint(
            x: CGFloat(column) * (cellWidth + TileMetrics.gap) + cellWidth / 2,
            y: CGFloat(row) * (cellHeight + TileMetrics.gap) + cellHeight / 2
        )
    }

    /// Номер ячейки под точкой. За кромками сетки счёт не срывается:
    /// точка слева от первой колонки — это первая колонка, а не минус одна.
    private func slotIndex(at point: CGPoint) -> Int {
        let column = Int(floor(point.x / (cellWidth + TileMetrics.gap)))
        let row = Int(floor(point.y / (cellHeight + TileMetrics.gap)))
        let clampedColumn = min(max(column, 0), columnCount - 1)
        let index = max(row, 0) * columnCount + clampedColumn
        return min(max(index, 0), preview.count - 1)
    }
}

/// Плитка модуля: вид как у `ToggleTile`, но без кнопки — нажатие и
/// перетаскивание разбирает один жест сетки.
private struct ModuleTile: View {
    let title: String
    let symbol: String
    let tint: Color
    let isOn: Bool
    let onLabel: String
    let offLabel: String
    let isDragged: Bool
    let isPressed: Bool

    var body: some View {
        TileSurface(fill: isOn ? tint : TilePalette.idleFill) {
            VStack(alignment: .leading, spacing: 4) {
                TileIcon(symbol: symbol, color: isOn ? .white : NotchTheme.textTertiary)
                Spacer(minLength: 2)
                Text(title)
                    .font(.system(size: 10))
                    .foregroundStyle(isOn ? Color.white.opacity(0.7) : NotchTheme.textTertiary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(isOn ? onLabel : offLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isOn ? .white : NotchTheme.textPrimary)
                    .lineLimit(1)
            }
        }
        .scaleEffect(isDragged ? 1.04 : (isPressed ? 0.97 : 1))
        .shadow(color: .black.opacity(isDragged ? 0.35 : 0), radius: 10, y: 5)
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isPressed)
    }
}

private struct ActionTile: View {
    let title: String
    let symbol: String
    var tint: Color = .white
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            TileSurface(fill: isHovered ? Color.white.opacity(0.13) : TilePalette.idleFill) {
                VStack(alignment: .leading, spacing: 4) {
                    TileIcon(symbol: symbol, color: tint == .white ? NotchTheme.textTertiary : tint)
                    Spacer(minLength: 2)
                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(NotchTheme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .buttonStyle(TileButtonStyle())
        .onHover { isHovered = $0 }
    }
}

/// Разрешение системы: та же плитка, но состояние в ней — не наше, а
/// системное, и нажатие ведёт в Системные настройки, а не меняет его тут.
private struct AccessTile: View {
    let title: String
    let symbol: String
    let state: SystemAccess.State
    let settings: AppSettings
    let action: () -> Void

    @State private var isHovered = false

    private var label: String {
        switch state {
        case .granted: settings.t(.accessGranted)
        case .missing: settings.t(.accessMissing)
        case .unavailable: settings.t(.accessUnavailable)
        }
    }

    var body: some View {
        Button(action: action) {
            TileSurface(fill: isHovered ? Color.white.opacity(0.13) : TilePalette.idleFill) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 0) {
                        TileIcon(
                            symbol: symbol,
                            color: state == .granted ? NotchTheme.textTertiary : TilePalette.orange
                        )
                        Spacer(minLength: 4)
                        // Галочка вместо цветной точки: цвет в панели значит
                        // «требует действия», а выданный доступ не требует.
                        if state == .granted {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(NotchTheme.textTertiary)
                        }
                    }
                    Spacer(minLength: 2)
                    Text(title)
                        .font(.system(size: 10))
                        .foregroundStyle(NotchTheme.textTertiary)
                        .lineLimit(1)
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(NotchTheme.textPrimary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(TileButtonStyle())
        .onHover { isHovered = $0 }
        .disabled(state == .unavailable)
    }
}

/// Выбор из списка: та же плитка, но вместо состояния — текущее значение.
private struct MenuTile: View {
    let title: String
    let value: String
    let symbol: String
    let options: [(id: String, label: String)]
    let onPick: (String) -> Void

    var body: some View {
        Menu {
            ForEach(options, id: \.id) { option in
                Button(option.label) { onPick(option.id) }
            }
        } label: {
            TileSurface(fill: TilePalette.idleFill) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 0) {
                        TileIcon(symbol: symbol, color: NotchTheme.textTertiary)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(NotchTheme.textTertiary)
                    }
                    Spacer(minLength: 2)
                    Text(title)
                        .font(.system(size: 10))
                        .foregroundStyle(NotchTheme.textTertiary)
                        .lineLimit(1)
                    Text(value)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(NotchTheme.textPrimary)
                        .lineLimit(1)
                }
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }
}

/// Громкость — широкая плитка: ползунку нужна длина, в колонку он не влезает.
private struct SliderTile: View {
    let title: String
    let symbol: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    /// Кнопка справа нужна не всем ползункам — у громкости это «Проиграть».
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        TileSurface(fill: TilePalette.idleFill) {
            HStack(spacing: 12) {
                TileIcon(symbol: symbol, color: NotchTheme.textTertiary)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NotchTheme.textSecondary)
                Slider(value: $value, in: range)
                    .controlSize(.small)
                    .tint(TilePalette.blue)
                if let actionTitle, let action {
                    Button(action: action) {
                            Text(actionTitle)
                            .font(.system(size: 11))
                            .foregroundStyle(NotchTheme.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background { Capsule().fill(NotchTheme.accentSelection) }
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, minHeight: TileMetrics.height - TileMetrics.padding * 2)
        }
    }
}

/// Заголовок группы внутри раздела.
///
/// Раньше раздел был одной сеткой плиток с подсказкой внизу, и подсказка
/// почти всегда относилась к одной плитке, а стояла под всеми. Заголовок
/// делит раздел на кучки по три-четыре плитки — столько глаз берёт разом, —
/// и каждая подсказка встаёт под своей кучкой.
///
/// Набран той же строчной прописной, что и заголовок модуля в рейле: это
/// одна и та же роль — имя того, что под ним.
private struct GroupTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.4)
            .foregroundStyle(NotchTheme.textTertiary)
            .lineLimit(1)
            // Сверху воздуха больше, чем снизу: заголовок принадлежит
            // тому, что под ним, а не предыдущей кучке.
            .padding(.top, 6)
    }
}

private struct PanelHint: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(NotchTheme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Стрелка «скачать» рядом с версией.
private struct UpdateFooterButton: View {
    let available: String
    let hint: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 11))
                // Обе версии в одной строке: куда приедешь — и откуда.
                // Один номер вместо двух читался бы как «уже стоит».
                Text("Notch \(AppVersion.display) \u{2192} \(AppVersion.display(available))")
                    .font(.system(size: 10))
            }
            .foregroundStyle(NotchTheme.accentUpdate.opacity(isHovered ? 1 : 0.85))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background {
                Capsule().fill(isHovered ? NotchTheme.accentSelection : .clear)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        // Штамп сборки не теряется и здесь: подсказка говорит и что вышло,
        // и что сейчас стоит.
        .notchHelp("\(hint) · \(AppVersion.build)")
    }
}
