import SwiftUI

struct NotchRootView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var settings: AppSettings
    /// Размер физического (или виртуального) выреза — схлопнутое состояние.
    let collapsedSize: CGSize
    let actions: PanelActions
    /// Полка и музыка нужны корню ради кружков у схлопнутого выреза.
    @ObservedObject var shelf: ShelfStore
    @ObservedObject var music: NowPlayingCoordinator
    /// Идущее время — ради кружка таймера. Сам стор тикает двадцать раз в
    /// секунду, и подписываться на него отсюда нельзя: панель
    /// перекладывалась бы вместе с сотыми.
    @ObservedObject var timers: TimerIslandState
    /// Погода — ради значка «☁︎ 14°» в строке заголовка любого модуля.
    @ObservedObject var weather: WeatherStore
    /// События, ради которых вырез ненадолго становится плашкой.
    @ObservedObject var activity: ActivityCenter
    @ObservedObject var behaviour: BehaviourSettings

    /// Плашка живёт только в схлопнутом виде: в раскрытой панели событию
    /// негде показаться, да и незачем — пользователь уже смотрит внутрь.
    private var currentActivity: NotchActivity? {
        state.isExpanded ? nil : activity.current
    }

    /// Размер корпуса, а не раскладки: начинка уже разложена по конечной
    /// ширине, корпус её только открывает.
    private var currentSize: CGSize {
        if state.isExpanded { return state.corpusSize }
        if let current = currentActivity {
            return ActivityView.size(notch: collapsedSize, activity: current)
        }
        return collapsedSize
    }

    private var currentTitle: String {
        state.isSettingsOpen
            ? settings.t(.settingsPanelTitle)
            : settings.t(state.selectedModule.titleKey)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            // Кружки лежат ПОД панелью: пока она раскрыта, её чёрный корпус
            // их закрывает, а при схлопывании они выезжают из-под неё —
            // без моргания «пропало и появилось».
            island
            panel
        }
        // Рамка — по окну. Меняется только размер корпуса внутри, поэтому
        // окно никуда не едет.
        .frame(
            width: state.expandedSize.width,
            height: state.expandedSize.height,
            alignment: .top
        )
        .environmentObject(settings)
        .environment(\.notchIsSettled, state.isSettled)
        .environment(\.notchRailMetrics, state.railMetrics)
        .environment(\.notchContentTopInset, contentTopInset)
        .environment(\.notchContentBottomInset, contentBottomInset)
        .environment(\.notchContentLeadingInset, contentLeadingInset)
        .environment(\.notchContentTrailingInset, contentTrailingInset)
        // Ширина ещё закрытой шторкой полосы справа.
        .environment(\.notchCurtainInset, max(0, state.layoutBoost - state.widthBoost))
        // Место под полку занято — значит, полка ещё должна быть в вёрстке,
        // даже если её уже гасят.
        .environment(\.notchShelfSpace, state.layoutBoost)
        .ignoresSafeArea(.all)
        // Наружу и обратно — разными пружинами: `isExpanded` здесь уже
        // новое, тело пересобирается после смены состояния.
        .animation(NotchTheme.presentation(expanding: state.isExpanded), value: state.presentation)
        .animation(NotchTheme.expandAnimation, value: state.isSettingsOpen)
        .animation(NotchTheme.expandAnimation, value: islandKey)
        .animation(NotchTheme.expandAnimation, value: currentActivity?.id)
    }

    /// Сколько содержимое вправе закрыть собой над своей рамкой.
    ///
    /// При колонке — весь отступ до кромки панели вместе со строкой
    /// заголовка: заголовок нарисован, а не нажимается, и свечение плеера
    /// спокойно проходит под ним до самого верха.
    ///
    /// При ряде сверху — только зазор под рядом. Выше кнопки, и
    /// доехавшее до кромки свечение гасило бы их: в этой раскладке рейл
    /// живёт отдельной полосой, а не поверх содержимого.
    ///
    /// При ряде снизу над содержимым нет ничего — ни кнопок, ни заголовка,
    /// — и бледить можно до самой челки.
    private var contentTopInset: CGFloat {
        contentTopPadding + (state.railPlacement.isVertical ? state.railMetrics.itemHeight : 0)
    }

    /// Отступ содержимого от левой кромки панели — вместе с рейлом, если он
    /// стоит слева. Тем, кто тянется до самой кромки, надо знать всю
    /// дорогу, а не только собственное поле.
    /// Расстояние от содержимого до кромки корпуса — рейл плюс то самое
    /// поле, которым содержимое отбито. Считать поле отдельно нельзя: при
    /// ряде кнопок снизу оно шире, чем при колонке, и фон, вылезающий по
    /// этой цифре, не доставал до левой кромки на четыре точки — у края
    /// оставалась чёрная полоса.
    private var contentLeadingInset: CGFloat {
        let rail = state.railPlacement == .leading ? state.railMetrics.thickness : 0
        return rail + contentLeadingPadding
    }

    private var contentTrailingInset: CGFloat {
        let rail = state.railPlacement == .trailing ? state.railMetrics.thickness : 0
        return rail + contentTrailingPadding
    }

    /// Отступ содержимого от верхней кромки без строки заголовка.
    ///
    /// При ряде снизу над содержимым первой идёт сама челка: полоса в её
    /// высоту закрыта железом, и всё, что туда попадёт, пропадёт. Поэтому
    /// содержимое начинается ровно под ней.
    private var contentTopPadding: CGFloat {
        switch state.railPlacement {
        case .leading, .trailing: NotchTheme.topInset
        case .top: NotchTheme.railRowGap
        case .bottom, .bottomCentered: notchBand
        }
    }

    /// Сколько содержимое вправе закрыть собой под своей рамкой.
    ///
    /// При ряде снизу — всё поле до кромки панели вместе с самим рядом:
    /// свет должен дотечь под кнопки, иначе цвет обрывается по их верхней
    /// границе и панель читается как две полосы.
    private var contentBottomInset: CGFloat {
        state.railPlacement.isBottom
            ? contentBottomPadding + state.railMetrics.itemHeight + NotchTheme.topInset
            : NotchTheme.contentPadding
    }

    /// Отступ содержимого от того, что под ним: кромки панели или ряда.
    private var contentBottomPadding: CGFloat {
        state.railPlacement.isBottom ? NotchTheme.railRowGap : NotchTheme.contentPadding
    }

    /// Полоса у верхней кромки, закрытая вырезом. Кнопкам и содержимому
    /// туда нельзя: панель висит из-под челки, и всё, что выше её нижнего
    /// края, физически не видно.
    private var notchBand: CGFloat { collapsedSize.height }

    @ViewBuilder
    private var panel: some View {
        Group {
            if state.isExpanded {
                layout
                // Начинку сразу верстаем по полной ширине панели и держим
                // так всю анимацию: пока корпус растёт, он её просто
                // открывает, как штора. Если отдать начинку растущей рамке,
                // она перекладывается на каждом кадре — и иконки разъезжаются
                // от центра к краям.
                .frame(
                    width: state.expandedSize.width,
                    height: state.expandedSize.height,
                    alignment: .topLeading
                )
                // Начинка только проявляется — не едет и не масштабируется.
                //
                // Пробовали открывать её занавесом — чёрной плитой с
                // круглой дырой, расходящейся из выреза. Плита рисуется
                // своим слоем внутри перехода, общая подрезка панели до
                // неё не доходит, и первые кадры раскрытия были чёрным
                // прямоугольником в размер конечной панели. Подрезанная
                // по форме корпуса, она превратилась в чёрный круг поверх
                // начинки — ещё хуже.
                //
                // Двигается только корпус, начинка под ним стоит на месте —
                // он её открывает, как штора. Уходит она быстрее, чем
                // корпус успевает сжаться: схлопываться должна пустая
                // коробка, иначе видно, как содержимое давят.
                .transition(
                    .asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: 0.22).delay(0.06)),
                        removal: .opacity.animation(.easeIn(duration: 0.11))
                    )
                )
            } else if let current = currentActivity {
                ActivityView(
                    activity: current,
                    notchWidth: collapsedSize.width,
                    notchHeight: collapsedSize.height
                ) {
                    if let link = current.link {
                        NSWorkspace.shared.open(link)
                        withAnimation(NotchTheme.expandAnimation) { activity.dismissByUser(current.kind) }
                        return
                    }
                    guard let moduleID = current.kind.moduleID else { return }
                    actions.openModule(moduleID)
                }
                .transition(.opacity)
            }
        }
        // Рамка — по раскладке, а не по корпусу. Корпус живёт в форме
        // (`CurtainShape`), и его ширина ничего не двигает: начинка стоит
        // по полной ширине, шторка открывает её вправо.
        .frame(width: frameSize.width, height: frameSize.height, alignment: .top)
        // Подсказки рисуются здесь, внутри корпуса: слой должен стоять
        // выше всего, что внутри подрезано своими рамками, но ниже
        // `clipShape` — за кромку панели плашке всё равно нельзя.
        .notchTooltipLayer()
        .offset(x: bodyShift)
        .background(curtain.fill(NotchTheme.background), alignment: .leading)
        .clipShape(curtain)
    }

    /// Размер, по которому раскладывается всё внутри. У раскрытой панели
    /// это полная ширина вместе с местом под полку — она не меняется,
    /// пока полка выезжает.
    ///
    /// Ширина берётся рывком, по `isCorpusWide`, и в анимации не
    /// участвует. Рамка центрируется в окне: пока она ехала, её левый
    /// край уезжал влево — и корпус, нарисованный от него, полз следом.
    /// Отсюда и было «появился, а потом дорос вправо». Теперь рамка с
    /// первого кадра стоит во всю ширину, а движется один корпус внутри
    /// неё — своей формой, от середины выреза.
    private var frameSize: CGSize {
        CGSize(
            width: state.isCorpusWide ? state.expandedSize.width : currentSize.width,
            height: state.isExpanded ? state.expandedSize.height : currentSize.height
        )
    }

    /// Сам корпус: та часть рамки, которая сейчас открыта.
    private var curtain: CurtainShape {
        CurtainShape(
            width: currentSize.width,
            center: frameSize.width / 2 + islandShift,
            topRadius: state.isExpanded || currentActivity != nil
                ? NotchTheme.topCornerRadius
                : 0,
            bottomRadius: NotchTheme.bottomCornerRadius
        )
    }

    /// Окно бывает шире корпуса — на ширину полки, — и прирос он
    /// вправо: левый край окна прибит к `notchMidX - panelWidth / 2`.
    /// Середина окна при этом уезжает от середины выреза на половину
    /// прироста, а всё внутри раскладывается по ней.
    ///
    /// Раскрытому корпусу это ровно то, что нужно: он сам той же ширины,
    /// что и окно, и встаёт от края до края. А вот схлопнутому вырезу и
    /// кружкам — нет: они должны стоять над настоящим вырезом. Поэтому
    /// их возвращаем на место сдвигом.
    ///
    /// Раньше вместо этого ширину обнуляли рывком прямо перед
    /// схлопыванием — иначе вырез уезжал вбок. С открытой полкой
    /// закрытие начиналось с прыжка на две сотни точек.
    private var islandShift: CGFloat { -state.layoutBoost / 2 }

    /// Куда встаёт корпус: пока он шире обычной панели — левым краем к
    /// краю окна (прирост отдан полке справа), как только у́же —
    /// серединой по вырезу. На схлопывании он проходит из одного в
    /// другое без разрыва.
    private var bodyShift: CGFloat {
        max(NotchTheme.panelWidth, frameSize.width) / 2
            - NotchTheme.panelWidth / 2
            + islandShift
    }

    /// Схлопнутый вырез с кружками по бокам. Кто и с какой стороны — решают
    /// настройки, показываем только тех, кому есть что сказать.
    private var plan: IslandPlan {
        IslandPlan.make(
            settings: settings,
            shelf: shelf,
            music: music,
            timers: timers,
            enabledModules: Set(state.modules.map(\.id)),
            activityKind: currentActivity?.kind,
            baseWidth: islandBaseWidth
        )
    }

    /// От чего кружки отсчитывают своё место: от выреза, а пока на нём
    /// висит плашка — от всей плашки. Закреплённый трек стоит на вырезе
    /// постоянно, и кружки, привязанные к вырезу, лежали бы под ним.
    private var islandBaseWidth: CGFloat {
        currentActivity == nil ? collapsedSize.width : currentSize.width
    }

    /// Ключ раскладки: пока он не меняется, кружки не перерисовываются.
    private var islandKey: String {
        plan.left.map(\.id).joined(separator: ",")
            + "|" + plan.right.map(\.id).joined(separator: ",")
    }

    /// Кружкам есть где быть, пока вырез схлопнут. С плашкой они не
    /// спорят: та занимает середину, а они отходят за её края — кто не
    /// поместился, того `IslandPlan` и не отдаст.
    private var isIslandVisible: Bool {
        !state.isExpanded
    }

    @ViewBuilder
    private var island: some View {
        ForEach(IslandSide.allCases) { side in
            let entries = plan.indicators(on: side)
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                let shown = isIslandVisible
                badge(for: entry.indicator)
                    // Рамка в высоту выреза: кружок встаёт ровно по его центру.
                    .frame(height: collapsedSize.height)
                    // Размытие на выезде: кружок не просто уменьшен, а ещё
                    // и расфокусирован — так он собирается в резкость уже
                    // на своём месте, а не приезжает готовым.
                    // Сильнее прежнего: размытие теперь живёт почти весь
                    // полёт, и слабое на таком пути просто не читается.
                    //
                    // Размытие стоит ниже всех и первым забирает себе
                    // `.animation`: тот правит всё, что НАД ним по
                    // цепочке, до следующего такого же. Раньше он стоял
                    // выше сдвига с масштабом — и увозил их за собой на
                    // своей короткой дорожке `easeOut(0.22)`. Пружина
                    // кружка при этом не значила ничего: сколько ей ни
                    // добавляй перелёта, кружок всё равно доезжал за две
                    // десятых и вставал намертво.
                    .blur(radius: shown ? 0 : 10)
                    .animation(
                        IslandMetrics.blurAnimation(appearing: shown, index: index),
                        value: shown
                    )
                    // Спрятанный кружок лежит ровно в центре выреза, под его
                    // корпусом, — отсюда и ощущение, что он оттуда выезжает.
                    .offset(
                        x: islandShift + (
                            shown
                                ? IslandMetrics.offset(
                                    side: side,
                                    entries: entries,
                                    index: index,
                                    baseWidth: islandBaseWidth
                                )
                                : 0
                        )
                    )
                    // Растём от той кромки, из-под которой выезжаем:
                    // при росте от центра кружок будто проявляется в
                    // воздухе, а от кромки — выдвигается из выреза.
                    .scaleEffect(
                        shown ? 1 : 0.35,
                        anchor: side == .left ? .trailing : .leading
                    )
                    .opacity(shown ? 1 : 0)
                    // Сдвиг, масштаб и прозрачность — на пружине кружка.
                    .animation(IslandMetrics.animation(appearing: shown, index: index), value: shown)
                    // Файл положили при уже схлопнутой панели — кружок
                    // проявляется на месте, без выезда.
                    .transition(
                        .scale(scale: 0.6)
                            .combined(with: .opacity)
                            .combined(with: .modifier(
                                active: IslandBlur(radius: 6),
                                identity: IslandBlur(radius: 0)
                            ))
                    )
            }
        }
    }

    @ViewBuilder
    private func badge(for indicator: IslandIndicator) -> some View {
        switch indicator {
        case .shelf: ShelfIslandTray(store: shelf)
        case .music: MusicIslandBadge(music: music)
        case .timer: TimerIslandBadge(state: timers)
        }
    }

    /// Раскладка панели: колонка сбоку или ряд сверху.
    ///
    /// Ряд сверху занимает строку заголовка, поэтому заголовок в этой
    /// раскладке едет в сам ряд — второй строки под него не заводим, иначе
    /// горизонталь перестала бы быть бесплатной по высоте.
    @ViewBuilder
    private var layout: some View {
        switch state.railPlacement {
        case .leading:
            HStack(alignment: .top, spacing: 0) {
                // Рейл лежит выше содержимого: полосы размытия у краёв
                // прокрутки доходят до самой кромки корпуса и проходят под
                // кнопками, а не обрываются по их границе.
                rail.zIndex(1)
                content(showsTitle: true)
            }
        case .trailing:
            HStack(alignment: .top, spacing: 0) {
                content(showsTitle: true)
                rail.zIndex(1)
            }
        case .top:
            VStack(alignment: .leading, spacing: 0) {
                railRow
                content(showsTitle: false)
            }
        case .bottom, .bottomCentered:
            // Ряд лежит поверх содержимого — так же, как колонка слева:
            // размытие и свет с краёв прокрутки дотекают под кнопки, а не
            // обрываются по их верхней границе. Само содержимое стоит там
            // же, где стояло: полоса под ним отдана ряду отступом.
            ZStack(alignment: .bottom) {
                content(showsTitle: false)
                    .padding(.bottom, state.railMetrics.itemHeight + NotchTheme.topInset)
                railRow
            }
        }
    }

    /// Кнопки модулей. Общие для обеих раскладок — меняется только то,
    /// во что их складывают.
    @ViewBuilder
    private func railButtons(labels: RailLabels = RailLabels.none) -> some View {
        ForEach(state.modules, id: \.id) { module in
            // Настройки — такой же режим, как модуль: пока они открыты,
            // подсветка стоит на шестерёнке, а не на вкладке под ней.
            let isSelected = !state.isSettingsOpen && module.id == state.selectedModuleID
            let title = settings.t(module.titleKey)
            RailButton(
                symbol: module.symbol,
                moduleID: module.id,
                style: settings.railIconStyle,
                isSelected: isSelected,
                // Подпись у активной стоит вместо заголовка ряда: кнопка
                // называет модуль сама, и второй раз то же слово не нужно.
                label: labels == .active && isSelected ? title : nil,
                help: title
            ) {
                state.select(module.id)
            }
            .id(module.id)
        }
    }

    // Настройки — не модуль: у них нет своей вкладки, они открывают
    // отдельное окно. Поэтому стоят в конце, отбитые от списка, — пока
    // настройка не попросит поставить их в общий ряд.
    private var settingsButton: some View {
        RailButton(
            symbol: "gearshape",
            moduleID: nil,
            style: settings.railIconStyle,
            isSelected: state.isSettingsOpen,
            label: railSettingsLabel,
            help: settings.t(.settingsPanelTitle),
            action: state.toggleSettings
        )
    }

    /// Булавка: держит панель открытой, пока её не закроют явно.
    ///
    /// Стоит у шестерёнки, а не среди модулей: это не раздел, а то, как
    /// ведёт себя вся панель. Модуля у неё нет — значит, и цвета тоже.
    private var holdButton: some View {
        RailButton(
            symbol: "pin",
            moduleID: nil,
            style: settings.railIconStyle,
            isSelected: state.isHeldOpen,
            help: settings.t(state.isHeldOpen ? .panelRelease : .panelHoldOpen),
            action: state.toggleHeldOpen
        )
    }

    /// Подпись у шестерёнки.
    ///
    /// При подписи у активной она нужна ровно тогда, когда настройки
    /// открыты: заголовка в таком ряду нет, и без неё единственное место,
    /// где панель называет себя, оказывалось бы пустым.
    private var railSettingsLabel: String? {
        switch railLabels {
        case .none: return nil
        case .active: return state.isSettingsOpen ? settings.t(.settingsPanelTitle) : nil
        }
    }

    private var rail: some View {
        VStack(spacing: state.railMetrics.spacing) {
            railButtons()
            if settings.railSettingsInline {
                settingsButton
                Spacer(minLength: 0)
                holdButton
            } else {
                Spacer(minLength: 0)
                holdButton
                settingsButton
            }
        }
        .padding(.top, NotchTheme.topInset)
        .padding(.bottom, NotchTheme.topInset)
        .padding(state.railPlacement == .trailing ? .trailing : .leading, NotchTheme.railLeading)
        .frame(width: state.railMetrics.thickness, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// Горизонтальный рейл: кнопки, за ними заголовок, шестерёнка у
    /// правого края. Один и тот же ряд стоит и сверху, и снизу — меняется
    /// только то, с какой стороны у него отбивка от кромки. Заголовок стоит сразу за кнопками, а не рядом с
    /// шестерёнкой, — иначе читался бы её подписью.
    ///
    /// По центру порядок другой: кнопки уезжают в середину панели, а
    /// заголовок — к левой кромке, на место, которое они освободили. Класть
    /// их в один `HStack` со `Spacer` по краям нельзя: тогда середина
    /// считалась бы от заголовка до шестерёнки, а не от кромки до кромки, и
    /// ряд вставал бы тем левее, чем длиннее название модуля. Поэтому
    /// подписи лежат своим слоем, а кнопки центрируются по всей ширине.
    @ViewBuilder
    private var railRow: some View {
        if state.railPlacement.isCentered {
            centeredRailRow
        } else {
            edgeRailRow
        }
    }

    private var edgeRailRow: some View {
        HStack(spacing: railGap) {
            railStrip(budget: edgeStripBudget)
            if settings.railSettingsInline { settingsButton }

            // Подписанные кнопки уже назвали модуль — второй раз в той же
            // строке заголовок читался бы как эхо.
            if railShowsTitle {
                railTitle
                    .padding(.leading, NotchTheme.contentPadding)
            }
            moduleModes
                .padding(.leading, railShowsTitle ? accessoryGap : NotchTheme.contentPadding)

            Spacer(minLength: NotchTheme.contentLeading)
            if showsWeatherBadge { weatherBadge }
            if actionsWidth > 0 {
                moduleActions
                    .padding(.trailing, accessoryGap)
            }
            if railShowsVersion { railVersion }
            holdButton
            if !settings.railSettingsInline { settingsButton }
        }
        // Сверху ряд стоит не у кромки, а под челкой: у кромки его
        // середину съело бы железо. Снизу мешать нечему — там обычное поле.
        .padding(state.railPlacement.isBottom ? .bottom : .top,
                 state.railPlacement.isBottom ? NotchTheme.topInset : notchBand)
        .padding(.horizontal, NotchTheme.railLeading)
        // Прирост под полку ряду не достаётся: он принадлежит ей одной.
        .padding(.trailing, state.layoutBoost)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Подпись у активной переезжает с кнопки на кнопку: слово выходит
        // из иконки, а не подменяется рывком.
        .animation(NotchTheme.expandAnimation, value: state.selectedModuleID)
    }

    /// Тот же ряд, но кнопки — по центру панели.
    ///
    /// Заголовок с шестерёнкой держат высоту строки сами: без кнопок в этом
    /// слое он был бы ростом с текст, и центр ряда уехал бы вверх.
    private var centeredRailRow: some View {
        ZStack {
            HStack(spacing: 0) {
                // Заголовок стоит не у самой кромки: у неё он читается
                // подписью корпуса, а не названием того, что над ним.
                // Поле то же, каким отбито содержимое.
                if railShowsTitle {
                    railTitle
                        .padding(.leading, NotchTheme.railTitleLeading - NotchTheme.railLeading)
                }
                moduleModes
                    .padding(
                        .leading,
                        railShowsTitle
                            ? accessoryGap
                            : NotchTheme.railTitleLeading - NotchTheme.railLeading
                    )
                Spacer(minLength: NotchTheme.contentLeading)
                if showsWeatherBadge { weatherBadge }
                if actionsWidth > 0 {
                    moduleActions
                        .padding(.trailing, accessoryGap)
                }
                if railShowsVersion { railVersion }
                holdButton
                if !settings.railSettingsInline { settingsButton }
            }

            HStack(spacing: railGap) {
                railStrip(budget: centeredStripBudget)
                if settings.railSettingsInline { settingsButton }
            }
            .padding(.leading, centeredRailFits ? 0 : centeredSides.left)
            .padding(.trailing, centeredRailFits ? 0 : centeredSides.right)
        }
        .frame(height: state.railMetrics.itemHeight)
        .padding(.bottom, NotchTheme.topInset)
        .padding(.horizontal, NotchTheme.railLeading)
        // Ряд считает середину по обычной ширине панели, а не по
        // раздутой: прирост корпуса отдан полке справа, и если позволить
        // ряду его делить, кнопки уезжали бы вбок на половину полки —
        // хотя открылась она совсем в другом месте.
        .padding(.trailing, state.layoutBoost)
        .frame(maxWidth: .infinity)
        .animation(NotchTheme.expandAnimation, value: state.selectedModuleID)
    }

    /// Кнопки модулей в ряду — целиком или прокруткой, если не влезли.
    private func railStrip(budget: CGFloat) -> some View {
        RailStrip(
            contentWidth: railButtonsWidth(labels: railLabels),
            budget: budget,
            selectedID: state.isSettingsOpen ? nil : state.selectedModuleID
        ) {
            HStack(spacing: railGap) {
                railButtons(labels: railLabels)
            }
        }
    }

    /// Ширина одних кнопок модулей, без шестерёнки и обвязки.
    private func railButtonsWidth(labels: RailLabels) -> CGFloat {
        let metrics = state.railMetrics
        let buttons = state.modules.reduce(CGFloat.zero) { sum, module in
            let labelled = labels == .active
                && !state.isSettingsOpen && module.id == state.selectedModuleID
            return sum + (labelled
                ? metrics.labelledWidth(settings.t(module.titleKey))
                : metrics.itemWidth)
        }
        return buttons + CGFloat(max(state.modules.count - 1, 0)) * railGap
    }

    /// Сколько ряд у кромки может отдать кнопкам: всё, что осталось после
    /// шестерёнки и обвязки модуля. Название к этому моменту уже ушло —
    /// оно жертвуется раньше, чем кнопки начинают прятаться.
    private var edgeStripBudget: CGFloat {
        let rest = railRowWidth(labels: railLabels, title: railShowsTitle)
            - railButtonsWidth(labels: railLabels)
            + (settings.railSettingsInline ? railGap : 0)
        return availableRowWidth - rest
    }

    /// Чем заняты края центрированного ряда — слева название и режимы,
    /// справа погода, действия и шестерёнка. Обвязка лежит своим слоем,
    /// и кнопкам нельзя заезжать под неё.
    private var centeredSides: (left: CGFloat, right: CGFloat) {
        let gear = (settings.railSettingsInline ? 0 : state.railMetrics.itemWidth)
            + state.railMetrics.itemWidth
        let right = [weatherBadgeWidth, actionsWidth]
            .filter { $0 > 0 }
            .reduce(gear) { $0 + $1 + accessoryGap }
        let left = (railShowsTitle ? titleWidth + accessoryGap : 0)
            + (modesWidth > 0 ? modesWidth + accessoryGap : 0)
            + NotchTheme.railTitleLeading - NotchTheme.railLeading
        return (left + NotchTheme.contentLeading, right + NotchTheme.contentLeading)
    }

    /// Ширина центрированного ряда без обвязки — и шестерёнка, если она
    /// стоит в нём же.
    private var centeredRowWidth: CGFloat {
        let inline = settings.railSettingsInline ? state.railMetrics.itemWidth + railGap : 0
        return availableRowWidth - NotchTheme.railLeading * 2 - inline
    }

    /// Влезают ли кнопки ровно посередине панели. Середина держится запасом
    /// от более широкого края с обеих сторон — иначе с одной стороны ряд
    /// заехал бы под шестерёнку.
    private var centeredRailFits: Bool {
        let sides = centeredSides
        return railButtonsWidth(labels: railLabels)
            <= centeredRowWidth - 2 * max(sides.left, sides.right)
    }

    /// Не влезли посередине — ряд сдвигается в свободную середину между
    /// краями и получает её целиком. Прокрутка начинается только там, где
    /// и этого мало: смещённый на пару десятков точек ряд лучше спрятанной
    /// кнопки.
    private var centeredStripBudget: CGFloat {
        let sides = centeredSides
        return centeredRailFits
            ? centeredRowWidth - 2 * max(sides.left, sides.right)
            : centeredRowWidth - sides.left - sides.right
    }

    /// Зазор между кнопками ряда: настройка или зазор самого размера.
    private var railGap: CGFloat {
        settings.railGap.value ?? state.railMetrics.spacing
    }

    /// Подписи, которые ряд действительно может себе позволить.
    ///
    /// Настройка говорит, чего хочет пользователь; ширина панели — что из
    /// этого влезает. Ряду, которому не хватило, приходится отступить на
    /// шаг: у активной → никаких. Обрезать ряд по кромке нельзя —
    /// пропала бы не подпись, а сама кнопка.
    private var railLabels: RailLabels {
        guard !state.railPlacement.isVertical else { return RailLabels.none }
        var mode = settings.railLabels
        while mode != RailLabels.none, railRowWidth(labels: mode) > availableRowWidth {
            guard let narrower = mode.narrower else { break }
            mode = narrower
        }
        return mode
    }

    /// Ширина, по которой раскладывается панель. Не корпуса: корпус едет,
    /// а начинка уже стоит по конечной.
    private var availableRowWidth: CGFloat {
        NotchTheme.panelWidth + state.layoutBoost
    }

    /// Название раздела в ряду — если ряду есть чем за него заплатить.
    ///
    /// Порядок жертв в тесном ряду такой: сначала уходят подписи вкладок,
    /// потом название раздела, и только оно — кнопки не уходят никогда.
    /// Название здесь наименее нужное из трёх: активная вкладка и так
    /// подсвечена, а рядом с ней стоят кнопки этого же раздела. Без этого
    /// правила `HStack` сжимал бы то, что гнётся, — и название показывало
    /// бы огрызок с многоточием, который не читается вовсе.
    private var railShowsTitle: Bool {
        guard railLabels == RailLabels.none else { return false }
        return railRowWidth(labels: railLabels) <= availableRowWidth
    }

    /// Во сколько обойдётся ряд с такими подписями.
    private func railRowWidth(labels: RailLabels, title showsTitle: Bool = true) -> CGFloat {
        let metrics = state.railMetrics
        let buttons = state.modules.reduce(CGFloat.zero) { sum, module in
            let labelled = labels == .active
                && !state.isSettingsOpen && module.id == state.selectedModuleID
            return sum + (labelled
                ? metrics.labelledWidth(settings.t(module.titleKey))
                : metrics.itemWidth)
        }
        let gaps = CGFloat(max(state.modules.count - 1, 0)) * railGap
        // Без подписей в ряду стоит заголовок — он тоже просит ширины.
        let title = showsTitle && labels == RailLabels.none
            ? titleWidth + NotchTheme.contentPadding
            : 0
        // Обвязка модуля стоит в той же строке и тоже занимает место. Её
        // ширину модуль объявляет сам: посчитать её здесь нельзя — вид
        // ещё не разложен, а решение нужно до вёрстки.
        let accessory = [modesWidth, actionsWidth, weatherBadgeWidth]
            .filter { $0 > 0 }
            .reduce(CGFloat.zero) { $0 + $1 + accessoryGap }
        // Шестерёнка есть в любой раскладке ряда: в самом ряду или у края.
        let gearTitle = settings.t(.settingsPanelTitle)
        let gear = labels == .active && state.isSettingsOpen
            ? metrics.labelledWidth(gearTitle)
            : metrics.itemWidth
        // Булавка стоит у кромки всегда, при любой раскладке шестерёнки.
        let hold = metrics.itemWidth + railGap
        return NotchTheme.railLeading * 2
            + buttons + gaps + title + accessory
            + NotchTheme.contentLeading + gear + hold
    }

    /// Ширина заголовка ряда — с разрядкой, которой он набран.
    private var titleWidth: CGFloat {
        let text = currentTitle.uppercased()
        let font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        let width = (text as NSString).size(withAttributes: [.font: font]).width
        return ceil(width) + CGFloat(text.count) * 1.4
    }

    /// Версия в строке рейла — пока открыты настройки.
    ///
    /// Раньше подпись стояла подвалом внутри панели настроек и занимала там
    /// целую строку. В ряду для неё уже есть место: между заголовком и
    /// шестерёнкой всё равно пусто.
    ///
    /// В самой строке — только номер: `v0.2.1`. Штамп сборки длиннее всего
    /// остального в ряду и набран цифрами, которые не читаются, а сверяются;
    /// ради одной такой сверки он занимал место рядом с кнопками постоянно.
    /// Теперь он в подсказке по наведению — там, где за ним и тянутся.
    private var railVersion: some View {
        Text(AppVersion.display)
            .font(.system(size: 9))
            .foregroundStyle(NotchTheme.textTertiary)
            .lineLimit(1)
            .fixedSize()
            .padding(.trailing, 6)
            .notchHelp("Notch \(AppVersion.display) · \(AppVersion.build)")
    }

    /// Версия показывается, только если ряду есть чем за неё заплатить.
    ///
    /// Она здесь наименее важная из всего: кнопки нажимают, заголовок читают,
    /// а версию сверяют раз в сборку. Поэтому при нехватке ширины уходит она,
    /// а не подпись и не кнопка, — и уходит целиком, без многоточия.
    private var railShowsVersion: Bool {
        guard state.isSettingsOpen, !state.railPlacement.isVertical else { return false }
        return railRowWidth(labels: railLabels, title: railShowsTitle)
            + versionWidth <= availableRowWidth
    }

    private var versionWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: 9)
        let width = (AppVersion.display as NSString).size(withAttributes: [.font: font]).width
        return ceil(width) + 6 + NotchTheme.contentLeading
    }

    private var railTitle: some View {
        Text(currentTitle.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.4)
            .foregroundStyle(NotchTheme.textTertiary)
            .lineLimit(1)
    }

    /// Режимы текущего модуля — слева, сразу за названием раздела: они
    /// говорят о том же, о чём и оно, только подробнее.
    ///
    /// У настроек своей обвязки нет: там вся панель — одно содержимое, и
    /// делить его не на что.
    @ViewBuilder
    private var moduleModes: some View {
        if !state.isSettingsOpen {
            state.selectedModule.erasedModes()
        }
    }

    /// Команды текущего модуля — у дальней кромки строки.
    ///
    /// Рядом с режимами они стояли одним рядом одинаковых значков, и
    /// «показать плитками» оказывалось соседом «очистить всё». Разведённые
    /// по краям строки, они разделены самым простым, что есть в вёрстке, —
    /// пустотой между ними.
    @ViewBuilder
    private var moduleActions: some View {
        if !state.isSettingsOpen {
            state.selectedModule.erasedActions()
        }
    }

    private var modesWidth: CGFloat {
        state.isSettingsOpen ? 0 : state.selectedModule.modesWidth
    }

    private var actionsWidth: CGFloat {
        state.isSettingsOpen ? 0 : state.selectedModule.actionsWidth
    }

    /// Погода в строке заголовка — пока открыт любой другой модуль.
    /// В самой погоде она повторяла бы то, что крупно стоит под ней.
    private var showsWeatherBadge: Bool {
        !state.isSettingsOpen
            && state.selectedModuleID != WeatherModule.moduleID
            && settings.isEnabled(WeatherModule.moduleID)
            && weather.current != nil
    }

    private var weatherBadgeWidth: CGFloat {
        showsWeatherBadge ? WeatherHeaderBadge.width : 0
    }

    private var weatherBadge: some View {
        WeatherHeaderBadge(store: weather) {
            state.select(WeatherModule.moduleID)
        }
        .padding(.trailing, weatherBadgeTrailing)
    }

    /// Когда погода стоит в ряду последней, от кромки её отделяет то же
    /// поле, что и снизу: ряд выше плашки, и она сидит в нём с запасом
    /// сверху и снизу. Сбоку без этой добавки она жалась бы к краю.
    private var weatherBadgeTrailing: CGFloat {
        // Версия бывает только в настройках, а там погоды в ряду нет.
        let isLast = actionsWidth == 0 && settings.railSettingsInline
        guard isLast else { return 0 }
        return max(0, (state.railMetrics.itemHeight - WeatherHeaderBadge.height) / 2)
    }

    /// Отбивка кнопок модуля от названия раздела.
    private var accessoryGap: CGFloat { 10 }

    private var isRailTrailing: Bool { state.railPlacement == .trailing }

    /// Поля содержимого по горизонтали.
    ///
    /// При колонке они несимметричны нарочно: со стороны рейла — узкое
    /// поле, с дальней кромки — широкое. При ряде поперёк колонки сбоку
    /// нет, и узкому полю не от чего отбиваться: с обеих сторон кромка
    /// корпуса, а значит и поле одно и то же — то же, каким отбито
    /// название раздела в самом ряду.
    private var contentLeadingPadding: CGFloat {
        guard state.railPlacement.isVertical else { return NotchTheme.contentPadding }
        return isRailTrailing ? NotchTheme.contentPadding : NotchTheme.contentLeading
    }

    private var contentTrailingPadding: CGFloat {
        guard state.railPlacement.isVertical else { return NotchTheme.contentPadding }
        return isRailTrailing ? NotchTheme.contentLeading : NotchTheme.contentPadding
    }

    /// Ширина, отданная полке, пока она закрывается: содержимому, кроме
    /// самого плеера, в неё раскладываться нечего.
    private var shelfReserve: CGFloat {
        let showsMusic = !state.isSettingsOpen && state.selectedModuleID == MusicModule.moduleID
        return showsMusic ? 0 : state.layoutBoost
    }

    private func content(showsTitle: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Заголовок живёт в строке той же высоты, что и кнопка рейла, и
            // центрируется в ней. Тогда он всегда на одной линии с первой
            // иконкой и не скачет от модуля к модулю.
            if showsTitle {
                HStack(spacing: accessoryGap) {
                    Text(currentTitle.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(NotchTheme.textTertiary)
                    moduleModes
                    Spacer(minLength: NotchTheme.contentLeading)
                    if showsWeatherBadge { weatherBadge }
                    moduleActions
                }
                .frame(height: state.railMetrics.itemHeight)
            }

            Group {
                if state.isSettingsOpen {
                    SettingsPanel(
                        settings: settings,
                        behaviour: behaviour,
                        actions: actions,
                        shelf: shelf,
                        music: music,
                        timers: timers
                    )
                } else {
                    ModuleContentGate(module: state.selectedModule, openSettings: actions.openSettingsWindow)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        // `showsTitle` и `contentTopInset` описывают одно и то же поле с
        // двух сторон: здесь оно ставится, там объявляется тем, кто под
        // него подлезает.
        .padding(.top, contentTopPadding)
        // Поля зеркалятся вместе с рейлом: у края панели — широкое, у
        // рейла — узкое. Иначе содержимое липнет к краю экрана.
        .padding(.leading, contentLeadingPadding)
        .padding(.trailing, contentTrailingPadding)
        // Прирост под полку — плеера и только плеера, как и у ряда кнопок.
        // Всем остальным его не достаётся: настройки, разложенные по
        // раздутой ширине, схлопывающийся корпус резал бы справа — а
        // ширина эта уже ничья, полка закрывается вместе с уходом.
        .padding(.trailing, shelfReserve)
        // Снизу содержимое упирается не в кромку, а в ряд кнопок: поле
        // там такое же, как под рядом сверху.
        .padding(.bottom, contentBottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // При ряде поперёк содержимое подрезано по своим полям.
        //
        // Свечению плеера и волне по басу нарочно позволено вылезать за
        // поля — при колонке им некуда деться, кроме как под строку
        // заголовка и вырез. Но волна ростом в три сотни точек вылезает
        // сильно дальше объявленного: при колонке это уходит под вырез и
        // не видно, а ряд кнопок она закрывала целиком — иконки тонули в
        // чёрном. Подрезка по полям оставляет вылет ровно тот, который
        // объявлен `contentTopInset`.
        .modifier(
            ClipBleed(
                active: !state.railPlacement.isVertical,
                bottom: contentBottomInset - contentBottomPadding
            )
        )
    }
}

/// Подрезка содержимого по его полям — с запасом снизу.
///
/// `clipped()` нельзя включить и выключить внутри одной цепочки
/// модификаторов, не меняя тип вида, отсюда отдельный модификатор.
/// Запас снизу — та часть панели, куда свету всё-таки можно: при ряде
/// снизу он течёт под кнопки до самой кромки.
private struct ClipBleed: ViewModifier {
    let active: Bool
    let bottom: CGFloat

    func body(content: Content) -> some View {
        if active {
            content.clipShape(BleedRect(bottom: bottom))
        } else {
            content
        }
    }
}

/// Рамка вида, опущенная вниз на столько-то точек. Подрезать по ней можно
/// и наружу: `clipShape` берёт путь, а не границы вида.
private struct BleedRect: Shape {
    let bottom: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height + bottom))
    }
}

/// Кнопки ряда, которым не хватило ширины.
///
/// Пока ряд влезает, это просто `HStack`. Не влез — лишние кнопки уходят
/// за край под фейд и доезжают прокруткой. Убирать их нельзя: модуль,
/// которого не видно, всё равно включён, и до него должно быть можно
/// добраться отсюда же, а не через настройки.
///
/// Фейд стоит только с той стороны, где что-то спрятано: у нетронутого
/// ряда левый край резкий, первая кнопка видна целиком.
///
/// Колесо мыши крутит вертикально, а ряд горизонтальный — поэтому над
/// полосой вертикальная дельта переводится в горизонтальную сама. Трекпад
/// и так даёт горизонталь и проходит как есть.
private struct RailStrip<Content: View>: View {
    /// Ширина всех кнопок разом — считается до вёрстки, как и весь ряд.
    let contentWidth: CGFloat
    /// Сколько ряд может отдать кнопкам.
    let budget: CGFloat
    /// Кнопка, которую держать в виду: выбранный модуль не должен
    /// оказаться под фейдом.
    let selectedID: String?
    @ViewBuilder var content: () -> Content

    @State private var position = ScrollPosition(idType: String.self)
    @State private var edges = Edges()
    @State private var wheelMonitor: Any?

    private struct Edges: Equatable {
        var offset: CGFloat = 0
        var maxOffset: CGFloat = 0
        var leading: Bool { offset > 1 }
        var trailing: Bool { offset < maxOffset - 1 }
    }

    private let fade: CGFloat = 28

    var body: some View {
        if contentWidth <= budget {
            content()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                content()
                    .scrollTargetLayout()
            }
            .scrollPosition($position, anchor: .center)
            .frame(width: max(budget, 0))
            .onScrollGeometryChange(for: Edges.self) { geometry in
                Edges(
                    offset: geometry.contentOffset.x,
                    maxOffset: max(0, geometry.contentSize.width - geometry.containerSize.width)
                )
            } action: { _, new in
                edges = new
            }
            .mask {
                HStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                        .frame(width: edges.leading ? fade : 0)
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: edges.trailing ? fade : 0)
                }
                .animation(.easeOut(duration: 0.15), value: edges.leading)
                .animation(.easeOut(duration: 0.15), value: edges.trailing)
            }
            .onAppear { reveal(selectedID, animated: false) }
            .onChange(of: selectedID) { _, id in reveal(id, animated: true) }
            .onHover { inside in inside ? startWheel() : stopWheel() }
            .onDisappear(perform: stopWheel)
        }
    }

    private func reveal(_ id: String?, animated: Bool) {
        guard let id else { return }
        if animated {
            withAnimation(NotchTheme.expandAnimation) { position.scrollTo(id: id, anchor: .center) }
        } else {
            position.scrollTo(id: id, anchor: .center)
        }
    }

    private func startWheel() {
        guard wheelMonitor == nil else { return }
        wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { event in
            // Горизонталь трекпада ScrollView ведёт сам.
            guard abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) else { return event }
            let step = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 12
            let target = min(max(edges.offset - step, 0), edges.maxOffset)
            MainActor.assumeIsolated { position.scrollTo(x: target) }
            return nil
        }
    }

    private func stopWheel() {
        if let wheelMonitor { NSEvent.removeMonitor(wheelMonitor) }
        wheelMonitor = nil
    }
}

/// Кнопка рейла.
///
/// Активная — залитая: у символа берётся `.fill`-вариант, если он у него
/// есть. У кого его нет (`music.note`, `calendar`), активность достаётся
/// весом штриха и белым цветом — плашка под иконкой одна и та же, и вдвоём
/// с контрастом они читаются не хуже заливки.
private struct RailButton: View {
    let symbol: String
    /// У шестерёнки модуля нет — и цвета тоже.
    let moduleID: String?
    let style: RailIconStyle
    let isSelected: Bool
    /// Слово рядом с иконкой — или ничего. Кнопка от этого меняет ширину,
    /// но не высоту: ряд остаётся ростом в одну кнопку при любом наборе.
    var label: String?
    var help: String?
    let action: () -> Void

    @Environment(\.notchRailMetrics) private var metrics
    @State private var isHovered = false

    /// Заливка есть — берём её. Нет — берём вес. В тоновых стилях залиты
    /// все кнопки: активную там выделяет плашка и яркость, а не заливка.
    private var filled: String? {
        if style == .outline { return isSelected ? SymbolFill.filled(symbol) : nil }
        return SymbolFill.filled(symbol)
    }

    /// У залитого секундомера корпус — второй слой символа. Обычный тон
    /// делает его полупрозрачным, и иконка читалась мутным пятном. Поэтому
    /// в тоновых стилях он нарисован сам: корпус яркий, две стрелки тёмные.
    private var isInvertedTones: Bool { symbol == "stopwatch" }

    /// Залитый смайлик из SF Symbols в этой системе рисуется тем же
    /// контуром, что и обычный, — среди залитых соседей он выглядел
    /// чужим. Поэтому залитый нарисован сам: сплошной круг с прорезями.
    private var isSmiley: Bool { symbol == "face.smiling" }

    private var weight: Font.Weight {
        guard style == .outline, isSelected else { return .medium }
        return filled == nil ? .bold : .medium
    }

    /// Цвет модуля — только в цветном стиле и только у модулей.
    private var tint: Color? {
        guard style == .color, let moduleID else { return nil }
        return ModuleTint.color(for: moduleID)
    }

    /// Погода в цветном стиле рисуется родными цветами символа.
    private var isMulticolor: Bool { style == .color && moduleID == WeatherModule.moduleID }

    @ViewBuilder
    private var icon: some View {
        let image = Image(systemName: filled ?? symbol)
            .font(.system(size: metrics.iconSize, weight: weight))
        switch style {
        case .outline:
            if isSmiley, isSelected {
                SmileyGlyph(size: metrics.iconSize, fill: NotchTheme.textPrimary)
            } else {
                image
            }
        case .subtones:
            if isSmiley {
                SmileyGlyph(size: metrics.iconSize, fill: isSelected ? NotchTheme.textPrimary : NotchTheme.textSecondary)
            } else if isInvertedTones {
                StopwatchGlyph(size: metrics.iconSize, fill: isSelected ? NotchTheme.textPrimary : NotchTheme.textSecondary)
            } else {
                image.symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? NotchTheme.textPrimary : NotchTheme.textSecondary)
            }
        case .color:
            if isInvertedTones, let tint {
                StopwatchGlyph(size: metrics.iconSize, fill: tint.opacity(isSelected ? 1 : 0.9))
            } else if isMulticolor {
                image.symbolRenderingMode(.multicolor)
                    .opacity(isSelected ? 1 : 0.85)
            } else if isSmiley, let tint {
                SmileyGlyph(size: metrics.iconSize, fill: tint.opacity(isSelected ? 1 : 0.9))
            } else if let tint {
                image.symbolRenderingMode(.palette)
                    .foregroundStyle(tint.opacity(isSelected ? 1 : 0.9), tint.opacity(isSelected ? 0.55 : 0.4))
            } else {
                image.symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? NotchTheme.textPrimary : NotchTheme.textSecondary)
            }
        }
    }

    /// Плашка активной кнопки. В цветном стиле она тонируется цветом модуля.
    private var selectionTint: Color {
        if style == .color, let tint { return tint.opacity(0.22) }
        if isMulticolor { return Color(red: 0.35, green: 0.70, blue: 1.0).opacity(0.2) }
        return NotchTheme.accentSelection
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: label == nil ? 0 : metrics.labelSpacing) {
                icon

                if let label {
                    Text(label)
                        .font(.system(size: metrics.labelSize, weight: .medium))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
                .foregroundStyle(isSelected ? NotchTheme.textPrimary : NotchTheme.textSecondary)
                .padding(.horizontal, label == nil ? 0 : metrics.labelPadding)
                .frame(minWidth: metrics.itemWidth, minHeight: metrics.itemHeight)
                .frame(height: metrics.itemHeight)
                // Заливка кнопки размывает то, что под ней, а не красит
                // поверх. Тем же приёмом набрана плашка выбранного раздела
                // в настройках: ряд стоит прямо на содержимом — на обложке,
                // на полосе прокрутки, — и сплошная заливка читалась бы
                // дыркой в нём. Размытая узнаётся стеклом: видно, что под
                // кнопкой что-то есть, но разглядывать там нечего.
                .background {
                    let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
                    if isSelected {
                        shape.fill(.ultraThinMaterial)
                            .overlay { shape.fill(selectionTint) }
                    } else if isHovered {
                        shape.fill(.ultraThinMaterial)
                            .overlay { shape.fill(NotchTheme.accentSelection.opacity(0.5)) }
                    }
                }
        }
        .buttonStyle(.plain)
        .notchHelp(help)
        .onHover { isHovered = $0 }
    }
}

/// Залитый смайлик для рейла: сплошной круг, глаза и улыбка прорезаны
/// до фона. Размеры — доли кегля, как у секундомера.
private struct SmileyGlyph: View {
    let size: CGFloat
    let fill: Color

    var body: some View {
        let s = size * 1.18
        Canvas { ctx, _ in
            let r = s * 0.44
            let c = CGPoint(x: s / 2, y: s / 2)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(fill))
            ctx.blendMode = .destinationOut
            let eye = CGSize(width: s * 0.10, height: s * 0.15)
            for dx in [-0.16, 0.16] {
                let rect = CGRect(x: c.x + s * dx - eye.width / 2, y: c.y - s * 0.17, width: eye.width, height: eye.height)
                ctx.fill(Path(ellipseIn: rect), with: .color(.black))
            }
            var smile = Path()
            smile.addArc(center: CGPoint(x: c.x, y: c.y + s * 0.02), radius: s * 0.22,
                         startAngle: .degrees(25), endAngle: .degrees(155), clockwise: false)
            ctx.stroke(smile, with: .color(.black), style: StrokeStyle(lineWidth: max(1.2, s * 0.085), lineCap: .round))
        }
        .compositingGroup()
        .frame(width: s, height: s)
    }
}

/// Секундомер для тоновых стилей рейла: яркий корпус с головкой и боковой
/// кнопкой, на нём две тёмные стрелки — минутная длиннее, часовая короче.
///
/// У символа из SF Symbols стрелка одна, и перекрасить её отдельно от
/// корпуса можно только палитрой, а вторую стрелку не добавить вовсе.
/// Размеры — доли кегля, так что иконка растёт вместе с рейлом и стоит
/// вровень с соседними символами.
private struct StopwatchGlyph: View {
    let size: CGFloat
    let fill: Color
    var hands: Color = .black

    var body: some View {
        let s = size * 1.18
        Canvas { ctx, _ in
            let r = s * 0.40
            let c = CGPoint(x: s / 2, y: s * 0.57)
            // корпус
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(fill))
            // головка и ножка
            let crown = CGRect(x: c.x - s * 0.09, y: c.y - r - s * 0.13, width: s * 0.18, height: s * 0.08)
            ctx.fill(Path(roundedRect: crown, cornerRadius: s * 0.03), with: .color(fill))
            ctx.fill(Path(CGRect(x: c.x - s * 0.035, y: crown.maxY - 0.5, width: s * 0.07, height: s * 0.07)), with: .color(fill))
            // боковая кнопка под 45°
            var side = ctx
            side.translateBy(x: c.x + r * 0.707, y: c.y - r * 0.707)
            side.rotate(by: .degrees(45))
            side.fill(Path(roundedRect: CGRect(x: -s * 0.06, y: -s * 0.12, width: s * 0.12, height: s * 0.14), cornerRadius: s * 0.03), with: .color(fill))
            // стрелки
            let w = max(1.2, s * 0.085)
            var minute = Path(); minute.move(to: c); minute.addLine(to: CGPoint(x: c.x, y: c.y - r * 0.70))
            ctx.stroke(minute, with: .color(hands), style: StrokeStyle(lineWidth: w, lineCap: .round))
            let angle = Angle.degrees(60).radians
            var hour = Path(); hour.move(to: c)
            hour.addLine(to: CGPoint(x: c.x + sin(angle) * r * 0.45, y: c.y - cos(angle) * r * 0.45))
            ctx.stroke(hour, with: .color(hands), style: StrokeStyle(lineWidth: w, lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - w * 0.75, y: c.y - w * 0.75, width: w * 1.5, height: w * 1.5)), with: .color(hands))
        }
        .frame(width: s, height: s)
    }
}
