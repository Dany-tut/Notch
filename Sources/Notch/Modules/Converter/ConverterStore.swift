import Foundation

/// Конвертер единиц: величина, число и две единицы — из какой и в какую.
///
/// Считает `Measurement` из Foundation, своих коэффициентов здесь нет,
/// кроме суток и недели: у `UnitDuration` они не заведены. Валют нет
/// намеренно — курс без сети не узнать, а устаревший курс хуже никакого.
@MainActor
final class ConverterStore: ObservableObject {
    private enum Keys {
        static let category = "converter.category"
        static let input = "converter.input"
        static let units = "converter.units"
    }

    @Published var category: ConverterCategory {
        didSet { defaults.set(category.rawValue, forKey: Keys.category) }
    }

    /// Набранное число — строкой, как его набрали: «1,5» в русской
    /// раскладке не должно превращаться в «1.5» под пальцами.
    @Published var input: String {
        didSet { defaults.set(input, forKey: Keys.input) }
    }

    /// Выбранные единицы по величинам: «из» и «в» через `→`. Своя пара у
    /// каждой величины — вернувшись к длине, видишь те же километры в
    /// мили, что и оставил.
    @Published private var pairs: [String: String] {
        didSet { defaults.set(pairs, forKey: Keys.units) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        category = defaults.string(forKey: Keys.category).flatMap(ConverterCategory.init(rawValue:)) ?? .length
        input = defaults.string(forKey: Keys.input) ?? "1"
        pairs = defaults.dictionary(forKey: Keys.units) as? [String: String] ?? [:]
    }

    /// Индексы в `category.units`, а не символы: у американского и
    /// имперского галлона символ один и тот же.
    var sourceIndex: Int {
        get { index(0) }
        set { setIndex(newValue, at: 0) }
    }

    var targetIndex: Int {
        get { index(1) }
        set { setIndex(newValue, at: 1) }
    }

    var source: Dimension { category.units[sourceIndex] }
    var target: Dimension { category.units[targetIndex] }

    func swap() {
        pairs[category.rawValue] = "\(targetIndex)→\(sourceIndex)"
    }

    /// Все единицы величины, кроме исходной, — для списка справа.
    func conversions(of value: Double) -> [(index: Int, unit: Dimension, value: Double)] {
        let measurement = Measurement(value: value, unit: source)
        return category.units.enumerated()
            .filter { $0.offset != sourceIndex }
            .map { ($0.offset, $0.element, measurement.converted(to: $0.element).value) }
    }

    func convert(_ value: Double) -> Double {
        Measurement(value: value, unit: source).converted(to: target).value
    }

    private func index(_ slot: Int) -> Int {
        let count = category.units.count
        let stored = pairs[category.rawValue]?.components(separatedBy: "→").compactMap { Int($0) }
        if let stored, stored.count == 2, stored.allSatisfy({ (0..<count).contains($0) }) {
            return stored[slot]
        }
        return slot == 0 ? category.defaultPair.0 : category.defaultPair.1
    }

    /// Выбрали в «из» то, что стоит в «в», — меняем их местами, а не
    /// показываем перевод километров в километры.
    private func setIndex(_ value: Int, at slot: Int) {
        var pair = [sourceIndex, targetIndex]
        if pair[1 - slot] == value { pair[1 - slot] = pair[slot] }
        pair[slot] = value
        pairs[category.rawValue] = "\(pair[0])→\(pair[1])"
    }
}

/// Величина и её единицы в том порядке, в каком они встают в списке:
/// метрические по возрастанию, затем имперские.
enum ConverterCategory: String, CaseIterable, Identifiable, Sendable {
    case length, mass, temperature, volume, speed, area, data, time

    var id: String { rawValue }

    var titleKey: L10n.Key {
        switch self {
        case .length: return .converterLength
        case .mass: return .converterMass
        case .temperature: return .converterTemperature
        case .volume: return .converterVolume
        case .speed: return .converterSpeed
        case .area: return .converterArea
        case .data: return .converterData
        case .time: return .converterTime
        }
    }

    var symbol: String {
        switch self {
        case .length: return "ruler"
        case .mass: return "scalemass"
        case .temperature: return "thermometer.medium"
        case .volume: return "drop"
        case .speed: return "gauge.with.needle"
        case .area: return "square.dashed"
        case .data: return "externaldrive"
        case .time: return "clock"
        }
    }

    var units: [Dimension] {
        switch self {
        case .length:
            return [
                UnitLength.millimeters, UnitLength.centimeters, UnitLength.meters,
                UnitLength.kilometers, UnitLength.inches, UnitLength.feet,
                UnitLength.yards, UnitLength.miles, UnitLength.nauticalMiles
            ]
        case .mass:
            return [
                UnitMass.milligrams, UnitMass.grams, UnitMass.kilograms,
                UnitMass.metricTons, UnitMass.ounces, UnitMass.pounds, UnitMass.stones
            ]
        case .temperature:
            return [UnitTemperature.celsius, UnitTemperature.fahrenheit, UnitTemperature.kelvin]
        case .volume:
            return [
                UnitVolume.milliliters, UnitVolume.liters, UnitVolume.cubicMeters,
                UnitVolume.teaspoons, UnitVolume.tablespoons, UnitVolume.fluidOunces,
                UnitVolume.cups, UnitVolume.pints, UnitVolume.gallons, UnitVolume.imperialGallons
            ]
        case .speed:
            return [
                UnitSpeed.metersPerSecond, UnitSpeed.kilometersPerHour,
                UnitSpeed.milesPerHour, UnitSpeed.knots
            ]
        case .area:
            return [
                UnitArea.squareCentimeters, UnitArea.squareMeters, UnitArea.hectares,
                UnitArea.squareKilometers, UnitArea.squareInches, UnitArea.squareFeet,
                UnitArea.acres, UnitArea.squareMiles
            ]
        case .data:
            return [
                UnitInformationStorage.bits, UnitInformationStorage.bytes,
                UnitInformationStorage.kilobytes, UnitInformationStorage.megabytes,
                UnitInformationStorage.gigabytes, UnitInformationStorage.terabytes,
                UnitInformationStorage.kibibytes, UnitInformationStorage.mebibytes,
                UnitInformationStorage.gibibytes, UnitInformationStorage.tebibytes
            ]
        case .time:
            return [
                UnitDuration.milliseconds, UnitDuration.seconds, UnitDuration.minutes,
                UnitDuration.hours, ConverterUnits.days, ConverterUnits.weeks
            ]
        }
    }

    /// Пара по умолчанию — индексы в `units`: то, что переводят чаще всего.
    var defaultPair: (Int, Int) {
        switch self {
        case .length: return (3, 7)       // км → мили
        case .mass: return (2, 5)         // кг → фунты
        case .temperature: return (0, 1)  // °C → °F
        case .volume: return (1, 8)       // л → галлоны
        case .speed: return (1, 2)        // км/ч → мили/ч
        case .area: return (1, 5)         // м² → кв. футы
        case .data: return (4, 8)         // ГБ → ГиБ
        case .time: return (3, 2)         // часы → минуты
        }
    }
}

/// Единицы, которых нет в Foundation.
enum ConverterUnits {
    static let days = UnitDuration(symbol: "d", converter: UnitConverterLinear(coefficient: 86_400))
    static let weeks = UnitDuration(symbol: "wk", converter: UnitConverterLinear(coefficient: 604_800))
}

/// Числа и подписи единиц на языке интерфейса.
///
/// Разбор нарочно прощает: «1,5» и «1.5» — одно и то же в любом языке,
/// пробелы между разрядами пропускаются. Человек набирает число так, как
/// привык, а не так, как велит раскладка.
struct ConverterFormat {
    let locale: Locale
    let isRussian: Bool

    init(language: AppLanguage) {
        isRussian = language.resolved == .russian
        // Системная локаль, если её язык совпал с языком интерфейса:
        // у неё правильные разделители именно этого человека. Иначе —
        // типичная для языка.
        let code = isRussian ? "ru" : "en"
        locale = Locale.current.language.languageCode?.identifier == code
            ? Locale.current
            : Locale(identifier: isRussian ? "ru_RU" : "en_US")
    }

    func parse(_ text: String) -> Double? {
        let cleaned = text
            .filter { !$0.isWhitespace && $0 != "'" }
            .replacingOccurrences(of: "−", with: "-")
        guard !cleaned.isEmpty else { return nil }
        // Разделитель дробной части — последняя точка или запятая; всё,
        // что перед ней из тех же знаков, считаем разрядами.
        guard let mark = cleaned.lastIndex(where: { $0 == "," || $0 == "." }) else {
            return Double(cleaned)
        }
        let whole = cleaned[..<mark].filter { $0 != "," && $0 != "." }
        let fraction = cleaned[cleaned.index(after: mark)...]
        // «1,000» в английском — тысяча, а не единица: три цифры после
        // единственной запятой там читаются разрядами.
        if !isRussian, cleaned[mark] == ",", fraction.count == 3, !whole.isEmpty {
            return Double(whole + fraction)
        }
        return Double("\(whole.isEmpty ? "0" : String(whole)).\(fraction)")
    }

    /// Около семи значащих цифр, но только за счёт дробной части:
    /// дальше идёт шум деления, а не точность. Целую часть не режем —
    /// 12 345 678 байт не должны стать 12 345 680.
    func number(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        let magnitude = abs(value)
        // Совсем крошечное и огромное — в научной записи: восемь нулей
        // после запятой не читаются.
        if magnitude != 0, magnitude < 1e-6 || magnitude >= 1e15 {
            formatter.numberStyle = .scientific
            formatter.exponentSymbol = "e"
            formatter.maximumFractionDigits = 4
        } else {
            let digits = magnitude == 0 ? 0 : Int(floor(log10(magnitude)))
            formatter.maximumFractionDigits = min(max(6 - digits, 0), 10)
        }
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// Короткое обозначение: «км» по-русски, «km» по-английски. Короткий
    /// стиль `MeasurementFormatter` по-английски пишет «hour» и «stone» —
    /// там берём символ самой единицы.
    func symbol(_ unit: Dimension) -> String {
        if unit.symbol == ConverterUnits.days.symbol { return isRussian ? "сут" : "d" }
        if unit.symbol == ConverterUnits.weeks.symbol { return isRussian ? "нед" : "wk" }
        guard isRussian else {
            return unit.isEqual(UnitVolume.imperialGallons) ? "imp gal" : unit.symbol
        }
        let formatter = MeasurementFormatter()
        formatter.locale = locale
        formatter.unitStyle = .short
        return formatter.string(from: unit)
    }

    /// Полное название — «километры», «метры в секунду».
    func name(_ unit: Dimension) -> String {
        if unit.symbol == ConverterUnits.days.symbol { return isRussian ? "сутки" : "days" }
        if unit.symbol == ConverterUnits.weeks.symbol { return isRussian ? "недели" : "weeks" }
        let formatter = MeasurementFormatter()
        formatter.locale = locale
        formatter.unitStyle = .long
        return formatter.string(from: unit)
    }

    /// То, что уходит в буфер: число и обозначение.
    func copyText(_ value: Double, _ unit: Dimension) -> String {
        "\(number(value)) \(symbol(unit))"
    }
}
