import EventKit
import SwiftUI

/// Календарь: сетка месяца с числами слева, встречи выбранного дня справа.
struct CalendarModule: NotchModule {
    let id = "calendar"
    let titleKey: L10n.Key = .moduleCalendar
    let symbol = "calendar"

    let store: CalendarStore

    func makeContent() -> some View {
        CalendarContent(store: store)
    }
}

private struct CalendarContent: View {
    @ObservedObject var store: CalendarStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        content
            // Разрешение могли выдать в Системных настройках, пока панель
            // была закрыта — спрашиваем систему при каждом показе модуля.
            .onAppear { store.refreshAccess() }
    }

    @ViewBuilder
    private var content: some View {
        switch store.access {
        case .unknown:
            requestPrompt
        case .denied:
            VStack(spacing: 8) {
                EmptyState(
                    symbol: "calendar.badge.exclamationmark",
                    title: settings.t(.calendarDeniedTitle),
                    hint: settings.t(.calendarDeniedHint)
                )
                PromptButton(title: settings.t(.calendarOpenSettings)) {
                    store.openSystemSettings()
                }
                .padding(.bottom, 6)
            }
        case .unavailable:
            EmptyState(
                symbol: "calendar.badge.exclamationmark",
                title: settings.t(.calendarUnbundledTitle),
                hint: settings.t(.calendarUnbundledHint)
            )
        case .granted:
            month
        }
    }

    private var month: some View {
        HStack(alignment: .top, spacing: 14) {
            MonthGrid(store: store)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            DayPane(store: store)
                .frame(width: 168, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var requestPrompt: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.system(size: 20))
                .foregroundStyle(NotchTheme.textTertiary)
            Text(settings.t(.calendarAskTitle))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NotchTheme.textSecondary)
            PromptButton(title: settings.t(.calendarAskButton)) { store.requestAccess() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

/// Лента недель: шапка с месяцем и днями недели, под ней — непрерывная
/// прокрутка. Месяц в шапке берётся от той недели, что сейчас наверху.
private struct MonthGrid: View {
    @ObservedObject var store: CalendarStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.notchContentBottomInset) private var bottomInset

    /// Лента считается один раз: пересобирать её под прокруткой нельзя —
    /// список уехал бы из-под курсора.
    private let weeks = CalendarGrid.weeks(back: 18, forward: 18)
    /// Положение ленты. Кнопки и первый показ пишут в него неделю, обратно его
    /// не читает никто: с двусторонним связыванием лента дёргалась сама от
    /// себя — прокрутка писала верхнюю неделю, та меняла месяц в шапке, месяц
    /// догружал встречи, от новых встреч неделя с подписью месяца меняла
    /// высоту, и SwiftUI заново подтягивал прокрутку к записанной неделе.
    ///
    /// Прыжки идут через `ScrollPosition`, а не через `ScrollViewReader`:
    /// внутри прокрутки лежит пять копий содержимого — резкая и четыре
    /// размытых, — и `scrollTo` по `.id` видел бы каждую неделю пятью
    /// кандидатами. `ScrollPosition` адресует по слою целей прокрутки, а он
    /// у копий выключен, поэтому цель остаётся одна.
    ///
    /// Стартовая неделя стоит прямо в инициализаторе, а не проставляется
    /// потом через `.onAppear`: на самом первом кадре прокрутка ещё не
    /// прыгнула, и первый отчёт о видимости приходил с верха всей
    /// 36-месячной ленты (полтора года назад) — шапка на мгновение
    /// показывала дату полуторагодовой давности, пока `.onAppear` не
    /// подоспевал следом. Заданная сразу позиция такого кадра не оставляет.
    @State private var position: ScrollPosition

    init(store: CalendarStore) {
        self.store = store
        // Якорь чуть ниже верха, не впритык — тот же, что у прыжков: у
        // кромки полоса размытия ложится на подпись месяца.
        _position = State(initialValue: ScrollPosition(
            id: CalendarGrid.startOfWeek(Date()),
            anchor: UnitPoint(x: 0.5, y: 0.12)
        ))
    }

    /// Месяц, с которого прыгнули — шагом по месяцам или «Сегодня». Сразу
    /// после прыжка `onScrollTargetVisibilityChange` иногда ещё раз
    /// присылает ту же неделю, что была ДО него: сетка её уже не
    /// показывает, а обработчик об этом не знает и переписывает шапку
    /// обратно. Фильтруем строго этот, старый месяц — не ждём точно
    /// названную цель: при таком ожидании один непойманный отчёт (сетка
    /// проскочила цель без остановки, вкладку переключили посреди анимации)
    /// вешал бы фильтр навсегда, и шапка застывала бы до перезапуска.
    /// Здесь же любой ДРУГОЙ отчёт — хоть цель, хоть перелёт мимо неё —
    /// сам снимает фильтр.
    @State private var staleMonth: Date?

    private var calendar: Calendar { .current }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            weekdays
            strip
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(MonthFormat.title(store.month))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NotchTheme.textPrimary)
                .animation(nil, value: store.month)
            Spacer(minLength: 0)
            // «Сегодня» появляется, только когда с него ушли — постоянная
            // кнопка в шапке отнимала бы место у названия месяца.
            if !calendar.isDate(store.month, equalTo: Date(), toGranularity: .month) {
                Button(settings.t(.calendarToday)) { goToToday() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(NotchTheme.textSecondary)
            }
            StepButton(symbol: "chevron.left") { step(-1) }
            StepButton(symbol: "chevron.right") { step(1) }
        }
    }

    private var weekdays: some View {
        HStack(spacing: 0) {
            ForEach(Array(CalendarGrid.weekdaySymbols().enumerated()), id: \.offset) { _, symbol in
                Text(symbol.uppercased())
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(NotchTheme.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var strip: some View {
        // Та же прокрутка, что у встреч дня и в настройках: у краёв не
        // градиент-маска с «дыркой», а лестница размытия. Снизу полоса стоит
        // всегда — лента уезжает под ряд кнопок до кромки корпуса. Сверху
        // растёт с прокруткой: над лентой лежит строка дней недели, и на
        // нетронутой ленте первая неделя должна читаться целиком.
        BlurredEdgeScrollView(
            .vertical,
            leading: 14,
            trailing: bottomInset + 16,
            always: .trailing,
            // Цель прокрутки метит только резкая копия — внутри `content`,
            // который зовут пять раз, ставить `.scrollTargetLayout()` нельзя:
            // подробности у объявления флага в `BlurredEdgeScrollView`.
            scrollTarget: true
        ) {
            LazyVStack(spacing: 1) {
                ForEach(weeks, id: \.self) { week in
                    WeekRow(store: store, week: week)
                        .id(week)
                }
            }
            // Последняя неделя должна доезжать выше ряда кнопок, иначе до
            // неё не долистать: она всегда оставалась бы под ним.
            .padding(.bottom, bottomInset + 8)
        }
        .scrollIndicators(.never)
        // Месяц шапки — по верхней видимой неделе, читая прокрутку и
        // ничего в неё не записывая.
        .onScrollTargetVisibilityChange(idType: Date.self) { visible in
            guard let top = visible.min() else { return }
            // По середине недели: иначе в последние дни месяца шапка
            // отставала на месяц от того, что видно.
            let middle = calendar.date(byAdding: .day, value: 3, to: top) ?? top
            if let stale = staleMonth {
                if calendar.isDate(middle, equalTo: stale, toGranularity: .month) { return }
                staleMonth = nil
            }
            guard !calendar.isDate(middle, equalTo: store.month, toGranularity: .month) else { return }
            store.show(month: middle)
        }
        .scrollPosition($position, anchor: .top)
        // Список уезжает под ряд кнопок до самой кромки корпуса, а не
        // упирается в него: так он читается продолжающимся, как в настройках.
        .padding(.bottom, -bottomInset)
        .frame(maxHeight: .infinity)
    }

    /// Шаг по месяцам: наверх встаёт неделя с первым числом — у шага по
    /// месяцам другой цели и нет.
    private func step(_ months: Int) {
        let base = calendar.date(byAdding: .month, value: months, to: store.month) ?? store.month
        jump(to: CalendarGrid.startOfWeek(CalendarGrid.startOfMonth(base)))
    }

    /// «Сегодня» ведёт на неделю сегодняшнего дня, а не на начало его месяца:
    /// от кнопки ждут сегодняшнее число на виду. Месяц, с которого уходим,
    /// запоминаем до вызова `goToToday()` — он меняет `store.month` сразу,
    /// а `jump` должен отфильтровать именно ПРЕЖНЕЕ значение, а не новое.
    private func goToToday() {
        let leaving = store.month
        store.goToToday()
        jump(to: CalendarGrid.startOfWeek(Date()), from: leaving)
    }

    private func jump(to week: Date, from leaving: Date? = nil) {
        staleMonth = leaving ?? store.month
        // Не совсем к кромке: якорь чуть ниже верха — иначе неделя, к
        // которой прыгнули, встаёт прямо под полосу размытия, и подпись
        // месяца (если она у этой недели есть) читается сквозь размытие.
        withAnimation(.easeOut(duration: 0.2)) {
            position.scrollTo(id: week, anchor: UnitPoint(x: 0.5, y: 0.12))
        }
    }
}

/// Одна неделя ленты. Неделя, в которую попало первое число, несёт подпись
/// месяца — без неё лента превращалась в поток чисел без границ.
private struct WeekRow: View {
    @ObservedObject var store: CalendarStore
    let week: Date

    private var calendar: Calendar { .current }

    private var days: [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: week) }
    }

    /// Колонка, в которую попало первое число месяца.
    private var monthStartColumn: Int? {
        days.firstIndex { calendar.component(.day, from: $0) == 1 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let column = monthStartColumn {
                monthLabel(MonthFormat.monthOnly(days[column]), column: column)
            }
            // Клетки выравниваются по верху, а не по центру. С выравниванием
            // по центру — оно у `HStack` по умолчанию — высота клетки зависела
            // от того, сколько в ней плашек: день с плашкой и хвостом «+4»
            // выше дня с одной плашкой, и числа в ряду расходились по высоте.
            // Отсюда и «цифры скачут»: не сетка косая, а ряд центровал клетки
            // разного роста.
            HStack(alignment: .top, spacing: 2) {
                ForEach(days, id: \.self) { day in
                    DayCell(
                        day: day,
                        isToday: calendar.isDateInToday(day),
                        isSelected: calendar.isDate(day, inSameDayAs: store.selectedDay),
                        events: store.events(on: day),
                        height: 34
                    )
                    // Ровно та высота, из которой клетка считает, сколько
                    // плашек поместится: иначе подсветка выбранного дня была
                    // ростом по содержимому и в ряду стояла своей высоты.
                    .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34)
                    .contentShape(Rectangle())
                    .onTapGesture { store.select(day: day) }
                }
            }
            .frame(height: 34)
        }
    }

    /// Подпись стоит над колонкой первого числа, а не с левого края: у края
    /// она читалась как месяц всей недели, и «Октябрь» над 28 сентября
    /// выдавал сегодняшний день за 28 октября. Колонки те же, что у дней, —
    /// тот же зазор и равная ширина; `minWidth: 0` не даёт подписи
    /// растолкать свою колонку, текст просто выходит за неё по бокам.
    /// Год в подписи не нужен: он стоит в шапке, а в ленте повторялся бы у
    /// каждого месяца.
    private func monthLabel(_ title: String, column: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<7, id: \.self) { index in
                Group {
                    if index == column {
                        Text(title)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(NotchTheme.textTertiary)
                            .lineLimit(1)
                            .fixedSize()
                    } else {
                        Color.clear
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity)
            }
        }
        .frame(height: 13)
        .padding(.top, 3)
    }
}

private struct DayCell: View {
    let day: Date
    let isToday: Bool
    let isSelected: Bool
    let events: [EKEvent]
    let height: CGFloat

    private var number: String {
        String(Calendar.current.component(.day, from: day))
    }

    private var numberColor: Color {
        isToday || isSelected ? NotchTheme.textPrimary : NotchTheme.textSecondary
    }

    /// Сколько плашек поместится: на число уходит 16 pt, каждая встреча —
    /// 11 pt со своим зазором. Считаем по месту, а не по числу строк.
    private var capacity: Int {
        max(Int((height - 16) / 11), 0)
    }

    private var fillOpacity: Double {
        if isSelected { return 0.12 }
        return isToday ? 0.06 : 0
    }

    private var shown: [EKEvent] { Array(events.prefix(capacity)) }
    private var hidden: Int { events.count - shown.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            // Сегодня — просто белое полужирное число: кружок вокруг него
            // спорил с подсветкой выбранной клетки, и в ряду было два пятна.
            Text(number)
                .font(.system(size: 12, weight: isToday ? .semibold : .regular))
                .foregroundStyle(numberColor)
                .frame(height: 16)
                .frame(maxWidth: .infinity, alignment: .center)

            ForEach(shown, id: \.eventIdentifier) { event in
                EventChip(event: event)
            }
            // Хвост показываем только если он и правда есть: «+0» в клетке
            // читалось бы как встреча, которой нет.
            if hidden > 0, capacity > 0 {
                Text("+\(hidden)")
                    .font(.system(size: 9))
                    .foregroundStyle(NotchTheme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if capacity == 0, !events.isEmpty {
                // Клетка совсем низкая — остаются точки, как в мини-сетке.
                HStack(spacing: 2) {
                    ForEach(0..<min(events.count, 3), id: \.self) { _ in
                        Circle()
                            .fill(NotchTheme.textSecondary)
                            .frame(width: 2.5, height: 2.5)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
        .padding(.top, 1)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            // Выбранный день и сегодня — одна и та же плашка, разной силы:
            // круг вокруг числа спорил с ней и делал в ряду два пятна.
            RoundedRectangle(cornerRadius: 5)
                .fill(fillOpacity > 0 ? NotchTheme.textPrimary.opacity(fillOpacity) : .clear)
        )
    }
}

/// Плашка встречи в клетке: цвет календаря заливкой, название поверх.
private struct EventChip: View {
    let event: EKEvent

    private var tint: Color { Color(nsColor: event.calendar?.color ?? .systemGray) }

    var body: some View {
        Text(event.title ?? "—")
            .font(.system(size: 9, weight: .medium))
            // Текст по цвету календаря: на светлых заливках чёрный читается,
            // на тёмных — нет, поэтому берём сам цвет и осветляем подложку.
            .foregroundStyle(NotchTheme.textPrimary)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 10)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(tint.opacity(0.45))
            )
    }
}

private struct StepButton: View {
    let symbol: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(hovering ? NotchTheme.textPrimary : NotchTheme.textSecondary)
                .frame(width: 16, height: 16)
                .background(Squircle().fill(hovering ? NotchTheme.accentSelection : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Правая колонка: дата выбранного дня и её встречи.
private struct DayPane: View {
    @ObservedObject var store: CalendarStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.notchContentBottomInset) private var bottomInset

    private var events: [EKEvent] { store.events(on: store.selectedDay) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(MonthFormat.day(store.selectedDay))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NotchTheme.textPrimary)

            if events.isEmpty {
                Text(settings.t(.calendarDayEmpty))
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTheme.textTertiary)
                Spacer(minLength: 0)
            } else {
                // Полоса снизу стоит всегда — список уезжает под ряд кнопок
                // до самой кромки корпуса, и подложка нужна им постоянно.
                // Сверху над списком не лежит ничего, поэтому там полоса
                // растёт с прокруткой: на нетронутом списке первая встреча
                // резкая целиком, а уезжая вверх — тает. Раньше тут стоял
                // градиент-маска на постоянные десять точек, и первая встреча
                // была приглушена всегда: отсюда и «фейд перекрывает сверху».
                BlurredEdgeScrollView(
                    .vertical,
                    leading: 18,
                    trailing: bottomInset + 16,
                    always: .trailing
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(events, id: \.eventIdentifier) { event in
                            EventRow(event: event)
                        }
                    }
                    .padding(.trailing, 2)
                    // Поле, которое отняло растягивание вниз, содержимое
                    // получает обратно внутри прокрутки: последняя встреча
                    // доезжает выше ряда кнопок, а за кромку уходит полоса.
                    .padding(.bottom, bottomInset + 8)
                }
                .scrollIndicators(.never)
                .padding(.bottom, -bottomInset)
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct EventRow: View {
    let event: EKEvent
    @EnvironmentObject private var settings: AppSettings

    private var meeting: MeetingLink.Found? { MeetingLink.find(in: event) }

    var body: some View {
        HStack(spacing: 8) {
            // Полоска цвета календаря вместо кружка: она же отбивает строку
            // от соседней, так что разделители не нужны.
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(nsColor: event.calendar?.color ?? .systemGray))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 1) {
                Text(event.title ?? "—")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NotchTheme.textPrimary)
                    .lineLimit(1)
                Text(event.isAllDay ? settings.t(.calendarAllDay) : EventFormat.range(event))
                    .font(.system(size: 10))
                    .foregroundStyle(NotchTheme.textTertiary)
            }
            Spacer(minLength: 0)

            // Кнопка появляется, только если во встрече правда есть ссылка:
            // пустая «Подключиться» раздражала бы сильнее, чем её отсутствие.
            if let meeting {
                PromptButton(title: settings.t(.calendarJoin)) {
                    NSWorkspace.shared.open(meeting.url)
                }
                .notchHelp(meeting.service)
            }
        }
        .frame(minHeight: NotchTheme.rowHeight)
    }
}

private enum MonthFormat {
    /// «сентябрь 2026»
    static func title(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("LLLLyyyy")
        return formatter.string(from: date).capitalizedFirst
    }

    /// «октябрь» — подпись месяца внутри ленты.
    static func monthOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("LLLL")
        return formatter.string(from: date).capitalizedFirst
    }

    /// «вторник, 22 сентября»
    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return formatter.string(from: date).capitalizedFirst
    }
}

private extension String {
    /// Месяц и день недели во многих языках приходят со строчной буквы —
    /// в заголовке это читается как опечатка.
    var capitalizedFirst: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}

private enum EventFormat {
    /// «10:40 – 11:10»
    static func range(_ event: EKEvent) -> String {
        guard let start = event.startDate else { return "" }
        let time = DateFormatter()
        time.locale = .current
        time.timeStyle = .short
        time.dateStyle = .none

        var result = time.string(from: start)
        if let end = event.endDate {
            result += " – \(time.string(from: end))"
        }
        return result
    }
}

private struct PromptButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(NotchTheme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(NotchTheme.accentSelection))
    }
}
