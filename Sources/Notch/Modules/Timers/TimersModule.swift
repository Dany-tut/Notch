import SwiftUI

/// Часы панели: таймер, секундомер и будильники. Три режима — одна
/// вкладка: всё это про время, и держать под каждый свой рейл незачем.
///
/// Раскладка — та же, что у плеера, и это нарочно. Слева крупный круглый
/// объект на месте обложки, справа за волосяной линией — полка со
/// списком, под объектом — круглый транспорт. Модуль, живущий по чужим
/// правилам, читается как чужой, даже если каждая его деталь хороша.
struct TimersModule: NotchModule {
    let id = "timers"
    let titleKey: L10n.Key = .moduleTimers
    let symbol = "stopwatch"

    let store: TimersStore

    func makeContent() -> some View {
        TimersContent(store: store)
    }
}

private struct TimersContent: View {
    @ObservedObject var store: TimersStore
    @EnvironmentObject private var settings: AppSettings

    /// Панель ещё едет. Пока едет, свет не дышит: его кадры нужнее
    /// самому раскрытию.
    @Environment(\.notchIsSettled) private var isSettled
    @Environment(\.notchContentTopInset) private var contentTopInset
    @Environment(\.notchContentBottomInset) private var contentBottomInset

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            HStack(alignment: .center, spacing: 22) {
                dial
                shelf
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Свет выходит за поля содержимого до самых краёв корпуса: иначе
        // цветное пятно обрывается по невидимой рамке и читается
        // прямоугольником, а не светом из-под циферблата.
        .background(
            TimerGlow(tint: tint, paused: !isSettled)
                .padding(glowBleed)
                .allowsHitTesting(false)
        )
    }

    /// Цвет света: у звонка — тревожный, у покоя — тёплый и тихий.
    /// Гаснет вовсе, когда ничего не идёт: светиться остановленному
    /// секундомеру не с чего.
    private var tint: Color? {
        if store.ringing != nil { return ActivityTint.red }
        if store.isTimerRunning || store.isStopwatchRunning { return ActivityTint.orange }
        // Заведённый будильник — не повод светиться: он молчит часами, а
        // свет в панели должен означать, что прямо сейчас что-то идёт.
        return nil
    }

    private var glowBleed: EdgeInsets {
        EdgeInsets(
            top: -contentTopInset,
            leading: -NotchTheme.contentLeading,
            bottom: -contentBottomInset,
            trailing: -NotchTheme.contentPadding
        )
    }

    private var header: some View {
        HStack(spacing: 6) {
            ForEach(TimersStore.Mode.allCases) { mode in
                ModeTab(
                    title: settings.t(mode.titleKey),
                    symbol: mode.symbol,
                    isSelected: store.mode == mode
                ) {
                    withAnimation(.easeOut(duration: 0.18)) { store.mode = mode }
                }
            }

            Spacer(minLength: 0)

            // Звонок перебивает всё: пока он идёт, в шапке только он.
            if store.ringing != nil {
                Text(ringingTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ActivityTint.orange)
                PillButton(title: settings.t(.timersStopRinging), isProminent: true) {
                    store.stopRinging()
                }
            }
        }
    }

    private var ringingTitle: String {
        switch store.ringing {
        case .alarm(let alarm): return "\(settings.t(.timersAlarmRinging)) · \(alarm.text)"
        default: return settings.t(.timersDone)
        }
    }

    // MARK: - Циферблат

    private var dial: some View {
        VStack(spacing: 10) {
            Dial(
                progress: dialProgress,
                value: dialValue,
                caption: dialCaption,
                isRinging: store.ringing != nil,
                isRunning: store.isTimerRunning || store.isStopwatchRunning,
                animatesValue: store.mode == .alarm,
                tint: isDraftDial ? Color.white.opacity(0.22) : ActivityTint.orange
            )

            transport
        }
        .frame(width: 184)
    }

    /// Круг показывает не заведённое, а набранное: вкладка будильника,
    /// на которой ещё ничего не заведено.
    private var isDraftDial: Bool {
        store.mode == .alarm && nextAlarm == nil
    }

    private var dialProgress: Double {
        switch store.mode {
        case .timer:
            return store.timerProgress
        case .stopwatch:
            // Кольцо секундомера — это стрелка: один оборот в минуту.
            // Долю от «всего времени» тут показать не из чего.
            return store.stopwatch.truncatingRemainder(dividingBy: 60) / 60
        case .alarm:
            // Полный круг — сутки: дальше суток будильник и не заводят.
            // Пока ничего не заведено, круг показывает набранное справа —
            // иначе он стоял бы пустым ровно тогда, когда на него и
            // смотрят.
            guard let next = store.alarms.compactMap(store.nextFire(for:)).min()
                ?? store.nextFire(hour: store.draftHour, minute: store.draftMinute)
            else { return 0 }
            let left = next.timeIntervalSinceNow
            return max(0, min(1, 1 - left / (24 * 3600)))
        }
    }

    private var dialValue: String {
        switch store.mode {
        case .timer: return TimeFormat.clock(store.remaining)
        case .stopwatch: return TimeFormat.precise(store.stopwatch)
        case .alarm:
            guard let alarm = nextAlarm else { return store.draftText }
            return alarm.text
        }
    }

    private var dialCaption: String {
        switch store.mode {
        case .timer:
            if store.ringing != nil { return settings.t(.timersDone) }
            return store.isTimerRunning ? settings.t(.timersLeft) : settings.t(.timersReady)
        case .stopwatch:
            return store.laps.isEmpty
                ? settings.t(.timersStopwatch)
                : "\(settings.t(.timersLap)) \(store.laps.count + 1)"
        case .alarm:
            guard let alarm = nextAlarm, let next = store.nextFire(for: alarm) else {
                // Круг показывает набранное — и подпись говорит про него
                // же: время видно, а звонка ещё нет.
                return settings.t(.timersAlarmNotSet)
            }
            return TimeFormat.until(next)
        }
    }

    /// Ближайший заведённый — он же тот, что показывает циферблат.
    private var nextAlarm: TimersStore.Alarm? {
        store.alarms
            .compactMap { alarm in store.nextFire(for: alarm).map { ($0, alarm) } }
            .min { $0.0 < $1.0 }?.1
    }

    @ViewBuilder
    private var transport: some View {
        switch store.mode {
        case .timer:
            HStack(spacing: 4) {
                RoundButton(
                    symbol: store.isTimerRunning ? "pause.fill" : "play.fill",
                    size: 15,
                    isProminent: true
                ) {
                    store.toggleTimer()
                }
                .disabled(store.remaining <= 0)
                RoundButton(symbol: "arrow.counterclockwise", size: 12) { store.resetTimer() }
                // «+1» убран: ряд встал по три кнопки, как у секундомера,
                // а минуту всё равно набирают пресетом.
                RoundButton(title: "+5", size: 12) { store.addToTimer(300) }
            }
        case .stopwatch:
            HStack(spacing: 4) {
                RoundButton(
                    symbol: store.isStopwatchRunning ? "pause.fill" : "play.fill",
                    size: 15,
                    isProminent: true
                ) {
                    store.toggleStopwatch()
                }
                RoundButton(symbol: "flag", size: 12) { store.lap() }
                    .disabled(!store.isStopwatchRunning)
                RoundButton(symbol: "arrow.counterclockwise", size: 12) { store.resetStopwatch() }
                    .disabled(store.stopwatch == 0 && store.laps.isEmpty)
            }
        case .alarm:
            // У будильника транспорта нет: заводят его на полке, а
            // выключают там же. Подпись держит место, чтобы циферблат
            // не подпрыгивал при смене режима.
            Text(alarmSummary)
                .font(.system(size: 11))
                .foregroundStyle(NotchTheme.textTertiary)
                .frame(height: 42)
        }
    }

    private var alarmSummary: String {
        let active = store.alarms.filter(\.isOn).count
        guard active > 0 else { return settings.t(.timersNoAlarmsHint) }
        return "\(settings.t(.timersActiveAlarms)): \(active)"
    }

    // MARK: - Полка

    @ViewBuilder
    private var shelf: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch store.mode {
            case .timer: PresetShelf(store: store)
            case .stopwatch: LapShelf(store: store)
            case .alarm: AlarmShelf(store: store)
            }
        }
        // Ширина полки постоянна, как у колонки плеера: отдай её
        // содержимому — и длинная подпись растянула бы модуль шире
        // панели, выпихнув рейл за край окна.
        .frame(width: 330, alignment: .leading)
        // Полка стоит вровень с циферблатом по центру: прижатая к верху,
        // она висела бы над пустотой, пока круг занимает всю высоту.
        .frame(maxHeight: .infinity, alignment: .center)
    }
}

// MARK: - Циферблат

/// Круг на месте обложки: снаружи — дуга пройденного, внутри — цифры.
private struct Dial: View {
    let progress: Double
    let value: String
    let caption: String
    let isRinging: Bool
    let isRunning: Bool
    /// Подменять значение размытием. Только для будильника: у таймера
    /// цифры меняются двадцать раз в секунду, и переход на каждом тике
    /// превратил бы циферблат в кашу.
    var animatesValue: Bool = false
    /// Цвет дуги. Набранный, но не заведённый будильник рисуется бледным:
    /// оранжевое кольцо читается как «поставлено», а оно ещё нет.
    var tint: Color = ActivityTint.orange

    private let side: CGFloat = 142
    fileprivate static let valueFont = Font.system(size: 29, weight: .semibold, design: .rounded)

    /// Ход виден по толщине кольца: на паузе оно худеет до волоска, на
    /// ходу наливается. Так состояние читается боковым зрением, без
    /// разглядывания кнопки транспорта.
    private var line: CGFloat { isRunning || isRinging ? 9 : 4.5 }

    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(isRunning ? 0.10 : 0.07), lineWidth: line)

            // Пустую дугу не рисуем вовсе: круглая кромка в ноль длиной
            // оставляла точку наверху, и остановленный таймер выглядел
            // так, будто он чуть-чуть прошёл.
            Circle()
                .trim(from: 0, to: progress < 0.004 ? 0 : min(progress, 1))
                .stroke(
                    isRinging ? ActivityTint.red : tint,
                    style: StrokeStyle(lineWidth: line, lineCap: .round)
                )
                // Полдень наверху: кольцо, начинающееся справа, читается
                // как случайное.
                .rotationEffect(.degrees(-90))

            VStack(spacing: 3) {
                // Будильник набирают руками, и время в круге меняется
                // знак за знаком. У таймера и секундомера цифры бегут
                // сами — там обычная строка: она умеет сжиматься под
                // «1:05:00», а посимвольная — нет.
                if animatesValue {
                    RollingText(text: value, font: Self.valueFont, duration: 0.22)
                        .foregroundStyle(NotchTheme.textPrimary)
                } else {
                    Text(value)
                        .font(Self.valueFont)
                        .monospacedDigit()
                        .foregroundStyle(NotchTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Text(caption)
                    .font(.system(size: 10))
                    .foregroundStyle(NotchTheme.textTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 22)
        }
        .frame(width: side, height: side)
        // Звонок дышит кольцом, а не миганием: мигание в панели у края
        // экрана читается как сбой отрисовки.
        .scaleEffect(pulse ? 1.04 : 1)
        .animation(
            isRinging
                ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                : .easeOut(duration: 0.2),
            value: pulse
        )
        .onChange(of: isRinging) { _, ringing in pulse = ringing }
        .onAppear { pulse = isRinging }
        // Дугу не дёргаем скачком: на пуске и сбросе она доезжает.
        .animation(.easeOut(duration: isRunning ? 0.1 : 0.3), value: progress)
        // Толщина меняется мягко: рывок читался бы как перерисовка.
        .animation(.easeOut(duration: 0.28), value: isRunning)
        .animation(.easeOut(duration: 0.28), value: isRinging)
    }
}

// MARK: - Полки

private struct PresetShelf: View {
    @ObservedObject var store: TimersStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ShelfTitle(text: settings.t(.timersPresets))

            let columns = Array(
                repeating: GridItem(.flexible(), spacing: 6),
                count: 3
            )
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(TimersStore.presets, id: \.self) { minutes in
                    let seconds = TimeInterval(minutes * 60)
                    let isSelected = Int(store.duration) == minutes * 60
                    PillButton(
                        title: "\(minutes) \(settings.t(.timersMinutesShort))",
                        isSelected: isSelected,
                        fills: true
                    ) {
                        // Первый клик выбирает длительность, второй по уже
                        // выбранной кнопке — запускает её с начала.
                        store.setDuration(seconds)
                        if isSelected { store.startTimer() }
                    }
                }
            }

            Text(settings.t(.timersPresetsHint))
                .font(.system(size: 11))
                .foregroundStyle(NotchTheme.textTertiary)
                .lineLimit(2)

            FocusSoundPicker(store: store)
                .padding(.top, 2)
        }
    }
}

/// Фоновый звук: значки звуков и громкость. Выбор без идущего таймера
/// только запоминается — звучать он начнёт с пуском.
private struct FocusSoundPicker: View {
    @ObservedObject var store: TimersStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ShelfTitle(text: settings.t(.timersSound))

            HStack(spacing: 4) {
                ForEach(FocusSound.allCases) { sound in
                    SoundChip(
                        symbol: sound.symbol,
                        isSelected: store.focusSound == sound,
                        isPlaying: store.focusSound == sound && sound != .off && store.isTimerRunning
                    ) {
                        store.focusSound = sound
                    }
                    .notchHelp(settings.t(sound.titleKey))
                }

                Slider(value: $store.focusVolume, in: 0...1)
                    .controlSize(.mini)
                    .tint(ActivityTint.orange)
                    .padding(.leading, 6)
                    .disabled(store.focusSound == .off)
                    .opacity(store.focusSound == .off ? 0.35 : 1)
                    .notchHelp(settings.t(.timersSoundVolume))
            }
        }
    }
}

private struct SoundChip: View {
    let symbol: String
    let isSelected: Bool
    /// Звук выбран и звучит прямо сейчас — значок чуть дышит, чтобы было
    /// видно, откуда шум в наушниках.
    let isPlaying: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                .foregroundStyle(isSelected ? ActivityTint.orange : (isHovered ? NotchTheme.textPrimary : NotchTheme.textSecondary))
                .frame(width: 28, height: 24)
                .background {
                    Squircle().fill(
                        isSelected
                            ? ActivityTint.orange.opacity(0.16)
                            : Color.white.opacity(isHovered ? 0.09 : 0.05)
                    )
                }
                .contentShape(Squircle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct LapShelf: View {
    @ObservedObject var store: TimersStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ShelfTitle(text: settings.t(.timersLaps))

            if store.laps.isEmpty {
                Text(settings.t(.timersNoLaps))
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTheme.textTertiary)
            } else {
                BlurredEdgeScrollView(.vertical, leading: 18, trailing: 12) {
                    VStack(spacing: 1) {
                        ForEach(Array(store.laps.enumerated()), id: \.offset) { index, lap in
                            HStack(spacing: 10) {
                                Text("\(store.laps.count - index)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(NotchTheme.textTertiary)
                                    .frame(width: 18, alignment: .trailing)
                                Text(TimeFormat.precise(lap))
                                    .font(.system(size: 13))
                                    .monospacedDigit()
                                    .foregroundStyle(NotchTheme.textSecondary)
                                Spacer(minLength: 0)
                            }
                            .frame(height: 24)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
    }
}

private struct AlarmShelf: View {
    @ObservedObject var store: TimersStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AlarmDialer(store: store)

            // Пока ничего не заведено, правая половина — только набор:
            // про пустоту уже сказано под циферблатом, а пустой список с
            // разделителем сказал бы то же во второй раз.
            if !store.alarms.isEmpty {
                Divider().overlay(Color.white.opacity(0.08))

                BlurredEdgeScrollView(.vertical, leading: 18, trailing: 12) {
                    VStack(spacing: 1) {
                        ForEach(store.alarms) { alarm in
                            AlarmRow(store: store, alarm: alarm)
                        }
                    }
                }
                .scrollIndicators(.never)
                // Список не тянет полку вниз: набор времени стоит на
                // месте, сколько бы будильников ни завели.
                .frame(maxHeight: 96)
            }
        }
    }
}

/// Набор времени: крупные цифры, дорожка суток под ними и кнопка,
/// которая называет, что именно заведёт.
///
/// Раньше тут стояли два числа со стрелками по пять точек: чтобы
/// добраться от 08:00 до 21:30, надо было щёлкнуть двадцать раз, а
/// набранное время читалось мельче, чем строка уже заведённого. Теперь
/// цифру тянут — как ручку громкости, — и то же самое можно ткнуть
/// сразу на дорожке суток.
private struct AlarmDialer: View {
    @ObservedObject var store: TimersStore
    @EnvironmentObject private var settings: AppSettings

    /// Какую половину времени сейчас крутят. Выбирается кликом и держится:
    /// колесо работает по всей карточке, и без выбранной половины было бы
    /// непонятно, что именно оно меняет.
    @State private var focus: DraftPart = .hour
    @State private var isHovering = false
    /// Накопленная прокрутка: у трекпада события приходят долями точки,
    /// и шаг по каждому превратил бы лёгкое касание в перелёт на час.
    @State private var wheel: CGFloat = 0

    /// Сколько точек колеса на один шаг.
    private static let pointsPerStep: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                DraftDigits(store: store, part: .hour, focus: $focus)
                Text(":")
                    .font(Self.digits)
                    .foregroundStyle(NotchTheme.textTertiary)
                DraftDigits(store: store, part: .minute, focus: $focus)

                Text(settings.t(.timersAlarmDragHint))
                    .font(.system(size: 10))
                    .foregroundStyle(NotchTheme.textTertiary)
                    .padding(.leading, 8)

                Spacer(minLength: 0)
            }
            // Подложка выбранной половины шире самой цифры на свои поля,
            // и из-за них первая цифра стояла правее полосы и кнопки.
            // Сдвигаем ряд на эти же поля: по левому краю выстраиваются
            // цифры, а не их подложка.
            .padding(.leading, -DraftDigits.inset)

            DayTrack(store: store)

            PillButton(
                title: String(format: settings.t(.timersAlarmSetAt), store.draftText),
                fills: true,
                tint: ActivityTint.orange,
                isLarge: true
            ) {
                store.addDraftAlarm()
            }
        }
        // Колесо ловим, пока курсор над карточкой. Границу считает сам
        // `onHover`: сверять координаты события с рамкой пришлось бы
        // через экранные координаты панели, а ответ у SwiftUI уже есть.
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .modifier(ScrollWheel(isActive: isHovering) { delta in
            wheel += delta
            let steps = Int((wheel / Self.pointsPerStep).rounded(.towardZero))
            guard steps != 0 else { return }
            wheel -= CGFloat(steps) * Self.pointsPerStep
            // Вверх — вперёд по времени, как и при протяжке цифр.
            store.setDraft(minutesOfDay: store.draft + steps * focus.step)
        })
    }

    fileprivate static let digits = Font.system(size: 34, weight: .semibold, design: .rounded)
}

/// Половина времени: часы или минуты.
private enum DraftPart {
    case hour, minute

    /// Шаг: час целиком, минуты пятёрками — будильник на 07:23 никому не
    /// нужен.
    var step: Int { self == .hour ? 60 : TimersStore.draftStep }
}

/// Часы или минуты крупно. Клик выбирает половину под колесо, протяжка
/// вверх-вниз меняет значение сразу.
private struct DraftDigits: View {
    @ObservedObject var store: TimersStore
    let part: DraftPart
    @Binding var focus: DraftPart

    /// Поля подложки по бокам цифры.
    static let inset: CGFloat = 6

    /// Сколько точек протяжки на один шаг. Меньше — и значение убегает
    /// от руки, больше — тянуть приходится через весь модуль.
    private static let pointsPerStep: CGFloat = 9

    /// Начало жеста: считаем от него, а не складываем приращения, —
    /// иначе округление на каждом кадре уводит время в сторону.
    @State private var anchor: Int?
    @State private var isHovered = false

    private var value: Int { part == .hour ? store.draftHour : store.draftMinute }
    private var isFocused: Bool { focus == part }

    var body: some View {
        digits
            .foregroundStyle(NotchTheme.textPrimary)
            .padding(.horizontal, Self.inset)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(fill))
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onTapGesture { focus = part }
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        let from = anchor ?? store.draft
                        if anchor == nil {
                            anchor = from
                            focus = part
                        }
                        let steps = Int((-value.translation.height / Self.pointsPerStep).rounded())
                        store.setDraft(minutesOfDay: from + steps * part.step)
                    }
                    .onEnded { _ in anchor = nil }
            )
            .onHover { hovering in
                isHovered = hovering
                if hovering { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }

    /// Цифра не подменяется рывком: старая расплывается и гаснет, новая
    /// собирается из размытия. И расплывается ровно та, что изменилась:
    /// с 08 на 09 десятки стоят на месте.
    private var digits: some View {
        RollingText(text: String(format: "%02d", value), font: AlarmDialer.digits)
    }

    /// Выбранная половина держит подложку постоянно: по ней видно, что
    /// сейчас изменит колесо.
    private var fill: Double {
        if anchor != nil { return 0.12 }
        if isFocused { return 0.09 }
        return isHovered ? 0.05 : 0
    }
}

/// Строка, в которой подменяется только то, что вправду изменилось.
///
/// Каждый знак живёт своей ячейкой и своей личностью: при 12:40 → 13:40
/// расплывается одна двойка, а не всё время целиком. Подмена всей строки
/// читалась как перерисовка — глаз ловил движение там, где ничего не
/// произошло.
///
/// Ячейка — `ZStack`: уходящий и приходящий знак стоят друг на друге, и
/// соседние цифры не разъезжаются, пока идёт переход.
private struct RollingText: View {
    let text: String
    let font: Font
    var duration: Double = 0.18

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, character in
                ZStack {
                    Text(String(character))
                        .id(character)
                        .transition(.blurReplace)
                }
            }
        }
        .font(font)
        .monospacedDigit()
        .animation(.easeOut(duration: duration), value: text)
    }
}

/// Колесо мыши поверх SwiftUI: своего события у него нет, а тянуть ради
/// этого весь модуль в AppKit незачем. Монитор живёт, только пока курсор
/// над нужным местом, и событие пропускает дальше — прокрутка списка под
/// ним не ломается.
struct ScrollWheel: ViewModifier {
    let isActive: Bool
    let onScroll: (CGFloat) -> Void

    @State private var monitors: [Any] = []

    func body(content: Content) -> some View {
        content
            .onChange(of: isActive) { _, active in
                if active { install() } else { remove() }
            }
            .onDisappear(perform: remove)
    }

    /// Два монитора, как у жестов над вырезом: панель — непринимающее
    /// окно, и колесо над ней уходит приложению под ней. Одно и то же
    /// событие попадает ровно в один из двух — какой именно, решает
    /// система.
    private func install() {
        guard monitors.isEmpty else { return }
        let local = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { event in
            MainActor.assumeIsolated { onScroll(event.scrollingDeltaY) }
            return event
        }
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel]) { event in
            MainActor.assumeIsolated { onScroll(event.scrollingDeltaY) }
        }
        monitors = [local, global].compactMap { $0 }
    }

    private func remove() {
        monitors.forEach(NSEvent.removeMonitor(_:))
        monitors = []
    }
}

/// Сутки одной линией: от полуночи до полуночи, засечки на шести,
/// двенадцати и восемнадцати. Ткнуть в неё — то же, что набрать время,
/// только сразу и приблизительно, а цифрами потом довести.
private struct DayTrack: View {
    @ObservedObject var store: TimersStore

    /// Место под полосу — по самой толстой: полоса растёт в обе стороны
    /// от своей оси, и кнопка под ней не шевелится, пока ведут.
    private static let height: CGFloat = 26
    /// Толщина в покое и под рукой. Ручки нет вовсе: на такой полосе
    /// кружок читался как посторонняя деталь, а край заливки и так
    /// показывает время точнее, чем он.
    private static let line: CGFloat = 7
    private static let draggingLine: CGFloat = 14

    @State private var isDragging = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let fraction = Double(store.draft) / 1440
            let thickness = isDragging ? Self.draggingLine : Self.line

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: thickness)

                Capsule()
                    .fill(ActivityTint.orange)
                    .frame(width: max(width * fraction, thickness), height: thickness)

                // Засечки на шести, двенадцати и восемнадцати —
                // единственное, по чему на голой полосе видно, утро это
                // или вечер. На залитой части они тёмные, на пустой —
                // светлые: иначе половина из них пропадает.
                ForEach([0.25, 0.5, 0.75], id: \.self) { mark in
                    Rectangle()
                        .fill(
                            mark <= fraction
                                ? Color.black.opacity(0.28)
                                : Color.white.opacity(0.18)
                        )
                        .frame(width: 1.5, height: thickness - 4)
                        .offset(x: width * mark)
                }
            }
            .frame(height: Self.height)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.18), value: isDragging)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard width > 0 else { return }
                        isDragging = true
                        let raw = Double(value.location.x / width) * 1440
                        let step = Double(TimersStore.draftStep)
                        store.setDraft(minutesOfDay: Int((raw / step).rounded() * step))
                    }
                    .onEnded { _ in isDragging = false }
            )
            .onHover { hovering in
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        }
        .frame(height: Self.height)
    }
}

private struct ShelfTitle: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(NotchTheme.textTertiary)
    }
}

private struct AlarmRow: View {
    @ObservedObject var store: TimersStore
    let alarm: TimersStore.Alarm

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Text(alarm.text)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(alarm.isOn ? NotchTheme.textPrimary : NotchTheme.textTertiary)

            if let next = store.nextFire(for: alarm) {
                Text(TimeFormat.until(next))
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTheme.textTertiary)
            }

            Spacer(minLength: 0)

            // Удаление появляется по наведению: строка с постоянным
            // крестиком читается как список ошибок, а не будильников.
            if isHovered {
                Button {
                    store.removeAlarm(alarm)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(NotchTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }

            Toggle("", isOn: Binding(
                get: { alarm.isOn },
                set: { store.setAlarm(alarm, on: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            // Системная синева выбивалась из тёплой палитры модуля.
            .tint(ActivityTint.orange)
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isHovered ? NotchTheme.accentSelection.opacity(0.6) : .clear)
        }
        .onHover { isHovered = $0 }
    }
}

/// Число со стрелками вверх-вниз. Вместо поля ввода: панель не берёт
/// фокус клавиатуры, и печатать в неё нечем.
private struct Wheel: View {
    @Binding var value: Int
    let range: Range<Int>
    var step: Int = 1

    var body: some View {
        HStack(spacing: 3) {
            Text(String(format: "%02d", value))
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(NotchTheme.textPrimary)
                .frame(width: 30)

            VStack(spacing: 2) {
                arrow("chevron.up", by: step)
                arrow("chevron.down", by: -step)
            }
        }
    }

    private func arrow(_ symbol: String, by delta: Int) -> some View {
        Button {
            shift(by: delta)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(NotchTheme.textSecondary)
                .frame(width: 16, height: 11)
                .background {
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .fill(NotchTheme.accentSelection)
                }
        }
        .buttonStyle(.plain)
    }

    /// По кругу: после 23 часов идёт 0, а не упор в край.
    private func shift(by delta: Int) {
        let span = range.count
        let index = (value - range.lowerBound + delta + span) % span
        value = range.lowerBound + index
    }
}

// MARK: - Мелочи

private struct ModeTab: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .medium))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(isSelected ? NotchTheme.textPrimary : NotchTheme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule().fill(
                    isSelected
                        ? NotchTheme.accentSelection
                        : (isHovered ? NotchTheme.accentSelection.opacity(0.5) : .clear)
                )
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// Круглая кнопка транспорта — та же, что у плеера: значок в кружке,
/// который проявляется под курсором.
private struct RoundButton: View {
    var symbol: String?
    var title: String?
    let size: CGFloat
    var isProminent = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    init(
        symbol: String,
        size: CGFloat,
        isProminent: Bool = false,
        action: @escaping () -> Void
    ) {
        self.symbol = symbol
        self.size = size
        self.isProminent = isProminent
        self.action = action
    }

    init(title: String, size: CGFloat, action: @escaping () -> Void) {
        self.title = title
        self.size = size
        self.action = action
    }

    private var diameter: CGFloat { isProminent ? 42 : 38 }

    var body: some View {
        Button(action: action) {
            Group {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: size))
                } else {
                    Text(title ?? "").font(.system(size: size, weight: .medium))
                }
            }
            .foregroundStyle(foreground)
            .frame(width: diameter, height: diameter)
            .background {
                if isProminent {
                    Squircle().fill(isEnabled ? ActivityTint.orange : Color.white.opacity(0.08))
                } else if isHovered, isEnabled {
                    Squircle().fill(Color.white.opacity(0.09))
                }
            }
            .contentShape(Squircle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var foreground: Color {
        guard isEnabled else { return NotchTheme.textTertiary }
        if isProminent { return NotchTheme.background }
        return isHovered ? NotchTheme.textPrimary : NotchTheme.textSecondary
    }
}

private struct PillButton: View {
    let title: String
    var isProminent = false
    var isSelected = false
    /// Занять всю отведённую ширину — для сетки пресетов, где кнопки
    /// должны стоять колонками, а не по своей ширине.
    var fills = false
    /// Залить цветом модуля, как круглый «пуск»: для главного действия
    /// вкладки. Серая плашка среди оранжевого кольца и оранжевой кнопки
    /// читалась как выключенная.
    var tint: Color?
    /// Главное действие вкладки: вдвое выше обычной таблетки и крупнее
    /// буквами. Среди набора времени в тридцать четыре точки обычная
    /// кнопка читалась подписью, а не кнопкой.
    var isLarge = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: isLarge ? 13 : 11, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(foreground)
                .padding(.horizontal, 12)
                .padding(.vertical, isLarge ? 14 : 5)
                .frame(maxWidth: fills ? .infinity : nil)
        }
        .buttonStyle(PillSurface(fill: fill(pressed:)))
        .onHover { isHovered = $0 }
    }

    private var foreground: Color {
        guard isEnabled else { return NotchTheme.textTertiary }
        return tint == nil ? NotchTheme.textPrimary : NotchTheme.background
    }

    /// Наведение притемняет, нажатие подсвечивает: под курсором кнопка
    /// уходит вглубь, под пальцем — отзывается вспышкой. Наоборот
    /// (светлее на наведении) она выглядела уже нажатой, ещё не будучи.
    private func fill(pressed: Bool) -> Color {
        if !isEnabled { return Color.white.opacity(0.05) }
        if let tint {
            if pressed { return tint.mix(with: .white, by: 0.22) }
            return isHovered ? tint.mix(with: .black, by: 0.16) : tint
        }
        if isProminent || isSelected {
            return pressed ? Color.white.opacity(0.22) : NotchTheme.accentSelection
        }
        if pressed { return Color.white.opacity(0.18) }
        return Color.white.opacity(isHovered ? 0.04 : 0.07)
    }
}

/// Подложка таблетки. Живёт стилем, а не в разметке: нажатие видно
/// только отсюда — `Button` наружу его не отдаёт.
private struct PillSurface: ButtonStyle {
    let fill: (Bool) -> Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background { Capsule().fill(fill(configuration.isPressed)) }
            .contentShape(Capsule())
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Свет из-под циферблата. Тот же приём, что у плеера: пятно живёт
/// справа, а левый край и верхняя полоса гасятся в чёрный — там панель
/// срастается с вырезом, и любой цвет выдал бы стык.
private struct TimerGlow: View {
    let tint: Color?
    var paused: Bool = false

    /// Периоды нарочно несоизмеримы и разные по осям: пятно ходит по
    /// незамкнутой петле, а не качается по отрезку туда-сюда. Качание
    /// глаз опознаёт за пару секунд и дальше видит механизм, а не свет.
    private let breathPeriod: Double = 9
    private let driftXPeriod: Double = 13
    private let driftYPeriod: Double = 19.5
    private let morphPeriod: Double = 7.5
    private let turnPeriod: Double = 23

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: paused)) { timeline in
            GeometryReader { geometry in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let wave: (Double, Double) -> CGFloat = { period, offset in
                    CGFloat(sin(time / period * 2 * .pi + offset))
                }

                let breath = wave(breathPeriod, 0)

                ZStack {
                    if let tint {
                        blob(
                            tint: tint,
                            strength: 0.24,
                            bounds: geometry.size,
                            center: UnitPoint(
                                x: 0.30 + wave(driftXPeriod, 0.9) * 0.10,
                                y: 0.56 + wave(driftYPeriod, 0) * 0.12
                            ),
                            radius: geometry.size.width * (0.40 + breath * 0.05),
                            squash: wave(morphPeriod, 0.3),
                            turn: wave(turnPeriod, 0)
                        )
                        blob(
                            tint: tint,
                            strength: 0.18,
                            bounds: geometry.size,
                            center: UnitPoint(
                                x: 0.96 + wave(driftYPeriod, 2.1) * 0.10,
                                y: 0.74 + wave(driftXPeriod, 0.4) * 0.18
                            ),
                            radius: geometry.size.width * (0.46 - breath * 0.05),
                            squash: wave(morphPeriod, 2.4),
                            turn: wave(turnPeriod, 1.7)
                        )
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black.opacity(0.6), location: 0.12),
                                .init(color: .black.opacity(0), location: 0.34)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                }
                .animation(.easeInOut(duration: 0.6), value: tint)
            }
        }
    }

    /// Пятно, а не круг. Два отличия от обычного радиального градиента.
    ///
    /// Первое — плато: к центру заливка не сходится в точку, а выходит
    /// на ровную яркость и держит её почти до середины радиуса. Именно
    /// схождение в точку и выдавало «пиковый» центр — свет из-под
    /// матового корпуса так не выглядит.
    ///
    /// Второе — форма: пятно сплющивается по одной оси, вытягивается по
    /// другой и медленно поворачивается, причём на своих периодах. Круг,
    /// даже едущий, остаётся кругом; бабл меняет силуэт.
    private func blob(
        tint: Color,
        strength: Double,
        bounds: CGSize,
        center: UnitPoint,
        radius: CGFloat,
        squash: CGFloat,
        turn: CGFloat
    ) -> some View {
        RadialGradient(
            stops: [
                .init(color: tint.opacity(strength), location: 0),
                .init(color: tint.opacity(strength * 0.94), location: 0.34),
                .init(color: tint.opacity(strength * 0.68), location: 0.55),
                .init(color: tint.opacity(strength * 0.32), location: 0.74),
                .init(color: tint.opacity(strength * 0.10), location: 0.88),
                .init(color: tint.opacity(0), location: 1)
            ],
            center: .center,
            startRadius: 0,
            endRadius: radius
        )
        .frame(width: radius * 2, height: radius * 2)
        .scaleEffect(x: 1 + squash * 0.28, y: 1 - squash * 0.22)
        .rotationEffect(.radians(Double(turn) * .pi / 3))
        .position(x: center.x * bounds.width, y: center.y * bounds.height)
    }
}
