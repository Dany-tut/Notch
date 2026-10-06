import SwiftUI

/// Погода: сейчас — крупно слева, сутки по часам — лентой справа, неделя
/// — рядом снизу.
struct WeatherModule: NotchModule {
    static let moduleID = "weather"

    let id = WeatherModule.moduleID
    let titleKey: L10n.Key = .moduleWeather
    let symbol = "cloud.sun"

    let store: WeatherStore

    func makeContent() -> some View {
        WeatherContent(store: store)
    }

    func makeModes() -> some View {
        WeatherModes(store: store)
    }

    func makeActions() -> some View {
        WeatherActions(store: store)
    }

    /// Потолок подписи места: длинное название обрезается, а не
    /// выдавливает кнопки ряда.
    static let modesLimit: CGFloat = 96

    var modesWidth: CGFloat { Self.modesLimit }
    var actionsWidth: CGFloat { 22 }
}

// MARK: - Строка заголовка

/// Место — сразу за названием раздела: это и подпись, и вход в поиск.
///
/// Само поле поиска сюда не встаёт: при ряде кнопок по центру слева от
/// них остаётся место под название раздела и одно короткое слово, а поле
/// шириной в полторы сотни точек наезжало бы на кнопки. Оно живёт в
/// содержимом модуля, над результатами.
private struct WeatherModes: View {
    @ObservedObject var store: WeatherStore
    @EnvironmentObject private var settings: AppSettings
    @State private var isHovered = false

    var body: some View {
        if let place = store.place, !store.isSearching {
            Button { store.isSearching = true } label: {
                HStack(spacing: 4) {
                    if place.isCurrentLocation {
                        Image(systemName: "location.fill")
                            .font(.system(size: 8))
                    }
                    Text(place.name)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .foregroundStyle(isHovered ? NotchTheme.textPrimary : NotchTheme.textSecondary)
                .padding(.horizontal, 6)
                .frame(height: 20)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovered ? NotchTheme.accentSelection : .clear)
                }
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .notchHelp(settings.t(.weatherChangePlace))
            .frame(maxWidth: WeatherModule.modesLimit, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// «Где я сейчас» — у дальней кромки: это действие, а не подпись.
private struct WeatherActions: View {
    @ObservedObject var store: WeatherStore
    @EnvironmentObject private var settings: AppSettings
    @State private var isHovered = false

    var body: some View {
        Button(action: store.useCurrentLocation) {
            Image(systemName: store.place?.isCurrentLocation == true ? "location.fill" : "location")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isHovered ? NotchTheme.textPrimary : NotchTheme.textTertiary)
                .frame(width: 22, height: 20)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovered ? NotchTheme.accentSelection : .clear)
                }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .notchHelp(settings.t(.weatherUseLocation))
    }
}

// MARK: - Содержимое

private struct WeatherContent: View {
    @ObservedObject var store: WeatherStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.notchIsSettled) private var isSettled
    /// Лента часов пролистана — тогда и слева нужен фейд.
    @State private var hoursScrolled = false
    @Environment(\.notchContentTopInset) private var contentTopInset
    @Environment(\.notchContentBottomInset) private var contentBottomInset
    @Environment(\.notchContentLeadingInset) private var contentLeadingInset
    @Environment(\.notchContentTrailingInset) private var contentTrailingInset

    var body: some View {
        Group {
            if store.isSearching {
                WeatherSearchResults(store: store)
            } else if store.place == nil {
                placePrompt
            } else if let current = store.current {
                forecast(current)
            } else {
                pending
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { store.refreshIfStale() }
    }

    // Места нет — объясняем, откуда его взять, и даём оба пути сразу.
    private var placePrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "cloud.sun.fill")
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 26))
            Text(settings.t(.weatherPickPlaceTitle))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NotchTheme.textPrimary)
            if store.status == .locationDenied {
                Text(settings.t(.weatherLocationDenied))
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTheme.textTertiary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 8) {
                PromptButton(symbol: "location.fill", title: settings.t(.weatherUseLocation)) {
                    store.useCurrentLocation()
                }
                PromptButton(symbol: "magnifyingglass", title: settings.t(.weatherSearchCity)) {
                    store.isSearching = true
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var pending: some View {
        VStack(spacing: 8) {
            switch store.status {
            case .failed:
                Text(settings.t(.weatherFailed))
                    .font(.system(size: 12))
                    .foregroundStyle(NotchTheme.textSecondary)
                PromptButton(symbol: "arrow.clockwise", title: settings.t(.weatherRetry)) {
                    store.refresh()
                }
            case .locationDenied:
                Text(settings.t(.weatherLocationDenied))
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTheme.textTertiary)
                    .multilineTextAlignment(.center)
                PromptButton(symbol: "magnifyingglass", title: settings.t(.weatherSearchCity)) {
                    store.isSearching = true
                }
            default:
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func forecast(_ current: WeatherStore.Current) -> some View {
        let kind = WeatherKind(code: current.code, isDay: current.isDay)
        return VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                // Отступ внутри колонки, а не снаружи: цифры отходят от
                // кромки, а лента часов остаётся где стояла.
                now(current, kind: kind)
                    .padding(.leading, 14)
                    .frame(width: 160, alignment: .leading)
                hourly
            }
            .frame(maxHeight: .infinity)
            weekly
        }
        // Погода идёт за цифрами до самых кромок корпуса: обрезанный по
        // полям содержимого дождь читался бы как окошко, а не как небо.
        .background(
            WeatherBackdrop(
                kind: kind,
                isDay: current.isDay,
                sunrise: store.days.first?.sunrise,
                sunset: store.days.first?.sunset,
                paused: !isSettled
            )
                .padding(backdropBleed)
        )
        .overlayPreferenceValue(WeatherCardFramesKey.self) { anchors in
            GeometryReader { proxy in
                WeatherGlassRain(
                    kind: kind,
                    cards: anchors.map { proxy[$0] },
                    paused: !isSettled,
                    sunPoint: sunPoint(in: proxy.size, isDay: current.isDay)
                )
                // Слой с каплями тянется вниз до кромки корпуса: иначе
                // сорвавшаяся с плитки капля обрезалась ровно по её низу.
                .padding(.bottom, -contentBottomInset)
            }
        }
    }

    /// Солнце в координатах содержимого: небо вылезает за поля до кромок
    /// корпуса, и доли солнца считаются от всего неба, а не от полей.
    private func sunPoint(in size: CGSize, isDay: Bool) -> CGPoint {
        let share = WeatherSun.position(
            at: Date(), sunrise: store.days.first?.sunrise, sunset: store.days.first?.sunset, isDay: isDay
        )
        let width = size.width + contentLeadingInset + contentTrailingInset
        let height = size.height + contentTopInset + contentBottomInset
        return CGPoint(x: -contentLeadingInset + width * share.x, y: -contentTopInset + height * share.y)
    }

    private var backdropBleed: EdgeInsets {
        EdgeInsets(
            top: -contentTopInset,
            leading: -contentLeadingInset,
            bottom: -contentBottomInset,
            trailing: -contentTrailingInset
        )
    }

    /// Цифра — главное на панели, как в «Погоде» на iPhone: крупная и
    /// тонкая, без значка рядом. Погоду показывает само небо за ней.
    private func now(_ current: WeatherStore.Current, kind: WeatherKind) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(WeatherFormat.temperature(current.temperature))
                .font(.system(size: 58, weight: .thin))
                .foregroundStyle(NotchTheme.textPrimary)
                .monospacedDigit()
            Text(settings.t(WeatherCondition.key(for: current.code)))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NotchTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(highLow)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NotchTheme.textPrimary.opacity(0.85))
                .monospacedDigit()
            Text("\(String(format: settings.t(.weatherFeelsLike), WeatherFormat.temperature(current.apparent))) · \(String(format: settings.t(.weatherWind), Int(current.wind.rounded())))")
                .font(.system(size: 10))
                .foregroundStyle(NotchTheme.textPrimary.opacity(0.7))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        // На светлом небе белому тексту нужна тень, иначе он тонет.
        .shadow(color: .black.opacity(0.28), radius: 4, y: 1)
        .padding(.leading, 10)
    }

    /// «Макс. 33° Мин. 26°» — сегодняшний день из прогноза.
    private var highLow: String {
        guard let today = store.days.first else { return "" }
        return "↑\(WeatherFormat.temperature(today.high))  ↓\(WeatherFormat.temperature(today.low))"
    }

    /// Лента часов — прямо на небе, без подложки: рядом с текущей погодой
    /// карточка лишь дробила бы верх на плашки.
    ///
    /// Края прокрутки растворяются маской с обеих сторон, а не затемнением:
    /// тёмная полоса на светлом небе читалась бы как грязь. Слева — потому
    /// что пролистанный час иначе обрывается о кромку на полуслове.
    private var hourly: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 2) {
                ForEach(Array(store.hours.enumerated()), id: \.element.id) { index, hour in
                    HourCell(
                        hour: hour,
                        label: index == 0
                            ? settings.t(.weatherNow)
                            : WeatherFormat.hour(hour.time, in: store.timeZone)
                    )
                }
            }
            .padding(.trailing, 24)
        }
        .scrollIndicators(.never)
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.x > 1 } action: { _, scrolled in
            withAnimation(.easeOut(duration: 0.2)) { hoursScrolled = scrolled }
        }
        .mask {
            HStack(spacing: 0) {
                // Слева гасим, только когда есть что прятать: нетронутая
                // лента стоит у самого края, и «Сейчас» должно быть резким.
                LinearGradient(
                    colors: [hoursScrolled ? .clear : .black, .black],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: 28)
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 28)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }

    private var weekly: some View {
        let low = store.days.map(\.low).min() ?? 0
        let high = store.days.map(\.high).max() ?? 1
        return HStack(spacing: 6) {
            ForEach(Array(store.days.enumerated()), id: \.element.id) { index, day in
                // «Сегодня» в плитку шириной в восемь десятков точек не
                // влезает — сегодняшний день отмечен цветом подписи.
                DayCell(
                    day: day,
                    label: WeatherFormat.weekday(day.date, in: store.timeZone, language: settings.language),
                    isToday: index == 0,
                    range: low...max(high, low + 1)
                )
            }
        }
        .frame(height: 64)
    }
}

/// Поиск города — на месте прогноза: поле сверху, найденное под ним.
private struct WeatherSearchResults: View {
    @ObservedObject var store: WeatherStore
    @EnvironmentObject private var settings: AppSettings
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            field
            if store.candidates.isEmpty {
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTheme.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                BlurredEdgeScrollView(.vertical, leading: 12, trailing: 12) {
                    VStack(spacing: 2) {
                        ForEach(store.candidates) { candidate in
                            CandidateRow(candidate: candidate) { store.choose(candidate) }
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .task {
            // Поле появляется вместе с содержимым, а панель становится
            // ключевой не сразу — фокус до этого момента теряется.
            NotchPanel.focusForTyping()
            try? await Task.sleep(for: .milliseconds(80))
            isFocused = true
        }
    }

    private var field: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NotchTheme.textSecondary)
            TextField(settings.t(.weatherSearchPlaceholder), text: $store.query)
                .focused($isFocused)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(NotchTheme.textPrimary)
                .onTapGesture { NotchPanel.focusForTyping() }
                .onExitCommand { store.closeSearch() }
                .onSubmit {
                    if let first = store.candidates.first { store.choose(first) }
                }
            // Отмена возвращает к прогнозу — если место уже было.
            if store.place != nil {
                Button(action: store.closeSearch) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(NotchTheme.textTertiary)
                        .frame(width: 18, height: 20)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: NotchTheme.rowHeight)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var hint: String {
        if store.isLookingUp { return settings.t(.weatherSearching) }
        return store.query.trimmingCharacters(in: .whitespaces).count < 2
            ? settings.t(.weatherSearchHint)
            : settings.t(.weatherNoResults)
    }
}

private struct CandidateRow: View {
    let candidate: WeatherStore.Candidate
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTheme.textTertiary)
                    .frame(width: 16)
                Text(candidate.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NotchTheme.textPrimary)
                Text(candidate.region)
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTheme.textTertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: NotchTheme.rowHeight)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHovered ? NotchTheme.accentSelection : .clear)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct PromptButton: View {
    let symbol: String
    let title: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 10, weight: .medium))
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(NotchTheme.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background {
                Capsule().fill(Color.white.opacity(isHovered ? 0.16 : 0.09))
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct HourCell: View {
    let hour: WeatherStore.Hour
    let label: String

    var body: some View {
        VStack(spacing: 5) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(NotchTheme.textPrimary.opacity(0.75))
            WeatherIcon(code: hour.code, isDay: hour.isDay, size: 15)
                .frame(height: 18)
            Text(WeatherFormat.temperature(hour.temperature))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NotchTheme.textPrimary)
                .monospacedDigit()
            // Вероятность осадков — только когда она что-то значит.
            Text(hour.precipitation >= 20 ? "\(hour.precipitation)%" : " ")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(WeatherFormat.rainTint)
                .monospacedDigit()
        }
        .frame(width: 42)
    }
}

/// День недели: иконка и полоска температур на общей шкале недели — так
/// сразу видно, какой день холоднее, без сравнения цифр.
private struct DayCell: View {
    let day: WeatherStore.Day
    let label: String
    let isToday: Bool
    let range: ClosedRange<Double>

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 10, weight: isToday ? .semibold : .medium))
                    .foregroundStyle(isToday ? NotchTheme.textPrimary : NotchTheme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                WeatherIcon(code: day.code, isDay: true, size: 12)
            }
            TemperatureBar(low: day.low, high: day.high, range: range)
            HStack {
                Text(WeatherFormat.temperature(day.low))
                    .foregroundStyle(NotchTheme.textTertiary)
                Spacer(minLength: 0)
                Text(WeatherFormat.temperature(day.high))
                    .foregroundStyle(NotchTheme.textPrimary)
            }
            .font(.system(size: 11, weight: .semibold))
            .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WeatherGlass())
        // Дождь переднего плана бьётся о плитки — ему нужно знать, где они.
        .anchorPreference(key: WeatherCardFramesKey.self, value: .bounds) { [$0] }
    }
}

private struct TemperatureBar: View {
    let low: Double
    let high: Double
    let range: ClosedRange<Double>

    var body: some View {
        GeometryReader { proxy in
            let span = range.upperBound - range.lowerBound
            let start = (low - range.lowerBound) / span
            let end = (high - range.lowerBound) / span
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(
                        colors: [WeatherFormat.tint(for: low), WeatherFormat.tint(for: high)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(width: max(proxy.size.width * (end - start), 4))
                    .offset(x: proxy.size.width * start)
            }
        }
        .frame(height: 3)
    }
}

// MARK: - Общее

struct WeatherIcon: View {
    let code: Int
    let isDay: Bool
    var size: CGFloat

    var body: some View {
        Image(systemName: WeatherCondition.symbol(for: code, isDay: isDay))
            .symbolRenderingMode(.multicolor)
            .font(.system(size: size))
    }
}

/// Коды погоды WMO, которыми отвечает Open-Meteo: символ и название.
enum WeatherCondition {
    static func symbol(for code: Int, isDay: Bool) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55: return "cloud.drizzle.fill"
        case 56, 57, 66, 67: return "cloud.sleet.fill"
        case 61, 63: return "cloud.rain.fill"
        case 65: return "cloud.heavyrain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 80, 81, 82: return isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    static func key(for code: Int) -> L10n.Key {
        switch code {
        case 0: return .weatherClear
        case 1: return .weatherMostlyClear
        case 2: return .weatherPartlyCloudy
        case 3: return .weatherOvercast
        case 45, 48: return .weatherFog
        case 51, 53, 55: return .weatherDrizzle
        case 56, 57, 66, 67: return .weatherFreezingRain
        case 61, 63: return .weatherRain
        case 65: return .weatherHeavyRain
        case 71, 73, 75, 77: return .weatherSnow
        case 80, 81, 82: return .weatherShowers
        case 85, 86: return .weatherSnowShowers
        case 95, 96, 99: return .weatherThunder
        default: return .weatherOvercast
        }
    }
}

enum WeatherFormat {
    static let rainTint = Color(red: 0.6, green: 0.85, blue: 1.0)

    static func temperature(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        // «−0°» читается как ошибка округления, а не как погода.
        return rounded == 0 ? "0°" : "\(rounded)°"
    }

    static func hour(_ date: Date, in zone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return String(format: "%02d", calendar.component(.hour, from: date))
    }

    static func weekday(_ date: Date, in zone: TimeZone, language: AppLanguage) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.locale = Locale(identifier: language.resolved == .russian ? "ru_RU" : "en_US")
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: date).capitalized
    }

    /// Цвет по температуре: от холодного синего к жаркому оранжевому.
    static func tint(for temperature: Double) -> Color {
        switch temperature {
        case ..<(-10): return Color(red: 0.55, green: 0.62, blue: 1.0)
        case ..<0: return Color(red: 0.45, green: 0.72, blue: 1.0)
        case ..<10: return Color(red: 0.40, green: 0.82, blue: 0.85)
        case ..<20: return Color(red: 0.55, green: 0.85, blue: 0.45)
        case ..<28: return Color(red: 0.98, green: 0.78, blue: 0.30)
        default: return Color(red: 0.96, green: 0.50, blue: 0.25)
        }
    }
}

/// Погода в строке заголовка любого модуля: «☁︎ 14°». Нажатие открывает
/// сам модуль погоды.
struct WeatherHeaderBadge: View {
    @ObservedObject var store: WeatherStore
    let action: () -> Void
    @State private var isHovered = false

    /// Ширина для расчёта ряда: иконка, отбивка и до трёх знаков.
    static let width: CGFloat = 50
    static let height: CGFloat = 20

    var body: some View {
        if let current = store.current {
            Button(action: action) {
                HStack(spacing: 4) {
                    WeatherIcon(code: current.code, isDay: current.isDay, size: 10)
                    Text(WeatherFormat.temperature(current.temperature))
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(isHovered ? NotchTheme.textPrimary : NotchTheme.textSecondary)
                }
                .padding(.horizontal, 6)
                .frame(height: Self.height)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovered ? NotchTheme.accentSelection : .clear)
                }
                .fixedSize()
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .notchHelp(store.place?.name)
        }
    }
}
