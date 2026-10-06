import AppKit
import SwiftUI

/// Размер рейла: три пресета вместо свободного числа.
///
/// Свободное число здесь вредно. Высота панели считается по рейлу
/// (`NotchState.railHeight`), и ползунок позволил бы растянуть её до края
/// экрана, ничего при этом не показав: место ушло бы в воздух между
/// кнопками. Три шага покрывают реальную нужду — мелкий экран, обычный и
/// 5K, где тринадцать точек уже не разглядеть.
enum RailSize: String, CaseIterable, Identifiable {
    case small, medium, large

    var id: String { rawValue }

    var titleKey: L10n.Key {
        switch self {
        case .small: return .railSizeSmall
        case .medium: return .railSizeMedium
        case .large: return .railSizeLarge
        }
    }

    var metrics: RailMetrics {
        switch self {
        case .small: RailMetrics(itemHeight: 24, itemWidth: 26, iconSize: 11, spacing: 2)
        case .medium: RailMetrics(itemHeight: 28, itemWidth: 30, iconSize: 13, spacing: 2)
        // Зазор у крупного меньше остальных: девять кнопок по 34 точки уже
        // сами задают высоту панели, и воздух между ними растил бы её
        // впустую — панель пухнет, а разглядеть в ней нечего.
        case .large: RailMetrics(itemHeight: 34, itemWidth: 36, iconSize: 16, spacing: 1)
        }
    }
}

/// Где стоит рейл.
///
/// Сверху он не стоит панели ни одной точки высоты: ряд садится ровно в ту
/// строку, где иначе живёт заголовок модуля, а заголовок уезжает в неё же,
/// следом за кнопками. Взамен содержимому достаётся вся ширина — те самые
/// точки, которые вертикальный рейл забирает себе.
///
/// Снизу — тот же обмен, только зеркальный: строку заголовка наверху не
/// рисуем вовсе, и освободившаяся высота уходит ряду у нижней кромки.
/// Ближе к руке — панель висит под вырезом, и курсор приходит сверху вниз;
/// зато содержимое теперь упирается в кнопки, а не в пустое поле.
///
/// Платит за это сканирование. Девять иконок в колонку читаются списком:
/// глаз идёт по одной оси, и позиция каждой запоминается. Тот же ряд по
/// горизонтали — полоска, где всё выглядит одинаково. Поэтому по умолчанию
/// рейл всё-таки слева.
///
/// Снизу по центру — тот же нижний ряд, только кнопки съезжают в середину
/// панели, под вырез. Курсор приходит оттуда же, откуда панель выезжает, и
/// путь до кнопок становится самым коротким из всех раскладок. Заголовок
/// при этом уходит к левой кромке, а шестерёнка остаётся у правой: центр
/// принадлежит одним модулям, иначе «по центру» оказалось бы центром
/// строки, а не центром панели.
enum RailPlacement: String, CaseIterable, Identifiable {
    case leading, trailing, top, bottom, bottomCentered

    var id: String { rawValue }

    /// Колонка сбоку — или ряд поперёк. От этого зависит и раскладка, и то,
    /// участвует ли рейл в высоте панели.
    var isVertical: Bool { self == .leading || self == .trailing }

    /// Ряд у нижней кромки — с любым выравниванием кнопок. Вся вёрстка
    /// вокруг него (поля содержимого, вылет света под кнопки) одинакова:
    /// центрирование меняет только сам ряд.
    var isBottom: Bool { self == .bottom || self == .bottomCentered }

    /// Кнопки в середине ряда, а не у кромки.
    var isCentered: Bool { self == .bottomCentered }

    var titleKey: L10n.Key {
        switch self {
        case .leading: return .railPlacementLeading
        case .trailing: return .railPlacementTrailing
        case .top: return .railPlacementTop
        case .bottom: return .railPlacementBottom
        case .bottomCentered: return .railPlacementBottomCentered
        }
    }
}

/// Подписи у кнопок горизонтального ряда.
///
/// В колонке подписей не бывает: рейл шириной в кнопку, слову там негде
/// лечь. Поперёк ширина есть — но не бесконечная, и в этом вся развилка.
///
/// `active` называет только текущий модуль: ряд растёт на одно слово, а
/// место всегда подписано. Заголовок из ряда при этом уходит — он повторял
/// бы ту же строку в полуметре правее.
///
/// Подписать всех разом ряд не умеет: девять таблеток по сотне точек в
/// панель шириной 640 не влезают, и такой ряд всё равно тут же отступал
/// на шаг назад — к подписи у активной. Настройка обещала то, чего почти
/// никогда не происходило, поэтому режима больше нет.
enum RailLabels: String, CaseIterable, Identifiable {
    case none, active

    var id: String { rawValue }

    var titleKey: L10n.Key {
        switch self {
        case .none: return .railLabelsNone
        case .active: return .railLabelsActive
        }
    }

    /// На шаг уже: чем жертвует ряд, которому не хватило ширины.
    var narrower: RailLabels? {
        switch self {
        case .active: return RailLabels.none
        case .none: return nil
        }
    }
}

/// Как нарисованы иконки рейла.
///
/// Контур — прежний вид: заливка только у активной. В двух других заливка
/// у всех, а тон делит символ на главное и второстепенное — у «Субтонов»
/// это два оттенка белого, у «Цветных» — цвет модуля и его полутон.
enum RailIconStyle: String, CaseIterable, Identifiable {
    case outline, subtones, color

    var id: String { rawValue }

    var titleKey: L10n.Key {
        switch self {
        case .outline: return .railIconsOutline
        case .subtones: return .railIconsSubtones
        case .color: return .railIconsColor
        }
    }
}

/// Цвет модуля для цветных иконок рейла — те же тона, что у плиток модулей
/// в настройках, чтобы кнопка и плитка узнавались друг в друге.
enum ModuleTint {
    static func color(for moduleID: String) -> Color? {
        switch moduleID {
        case "music": return Color(red: 0.96, green: 0.42, blue: 0.62)
        case "clipboard": return Color(red: 0.38, green: 0.62, blue: 1.00)
        case "trash": return Color(red: 0.95, green: 0.42, blue: 0.40)
        case "snippets", "notes": return Color(red: 0.98, green: 0.76, blue: 0.30)
        case "shelf": return Color(red: 0.58, green: 0.55, blue: 1.00)
        case "translate": return Color(red: 0.30, green: 0.80, blue: 0.78)
        case "calendar": return Color(red: 0.98, green: 0.45, blue: 0.42)
        case "reminders": return Color(red: 0.36, green: 0.80, blue: 0.98)
        case "mirror": return Color(red: 0.80, green: 0.54, blue: 1.00)
        case "askAI": return Color(red: 0.74, green: 0.90, blue: 0.34)
        case "timers": return Color(red: 0.98, green: 0.62, blue: 0.26)
        case "shortcuts": return Color(red: 1.00, green: 0.71, blue: 0.12)
        case "converter": return Color(red: 0.93, green: 0.45, blue: 0.86)
        case "emoji": return Color(red: 0.96, green: 0.88, blue: 0.30)
        case "teleprompter": return Color(red: 0.60, green: 0.72, blue: 0.88)
        case "battery", "system", "apps": return Color(red: 0.40, green: 0.84, blue: 0.52)
        // Погода рисуется своими цветами — солнце жёлтое, облако белое.
        default: return nil
        }
    }
}

/// Зазор между кнопками горизонтального ряда.
///
/// Три шага, а не ползунок, — по той же причине, что и у размера рейла:
/// свободное число позволило бы растянуть ряд в ничто.
///
/// Колонки это не касается. Там зазор идёт в высоту панели, и «просторно»
/// означало бы полосу в полтораста точек воздуха между иконками.
enum RailGap: String, CaseIterable, Identifiable {
    case tight, normal, loose

    var id: String { rawValue }

    /// `nil` — оставить зазор самого размера рейла.
    var value: CGFloat? {
        switch self {
        case .tight: return nil
        case .normal: return 8
        case .loose: return 16
        }
    }

    var titleKey: L10n.Key {
        switch self {
        case .tight: return .railGapTight
        case .normal: return .railGapNormal
        case .loose: return .railGapLoose
        }
    }
}

/// Размеры одной кнопки рейла и зазора между ними.
struct RailMetrics: Equatable {
    let itemHeight: CGFloat
    let itemWidth: CGFloat
    let iconSize: CGFloat
    let spacing: CGFloat

    /// Толщина рейла поперёк: кнопка плюс отступы с обеих сторон.
    var thickness: CGFloat { itemWidth + NotchTheme.railLeading * 2 }

    /// Кегль подписи у кнопки. Крупный рейл её не увеличивает: иконка в
    /// шестнадцать точек и слово в пятнадцать читались бы как заголовок,
    /// а это всё-таки кнопка.
    var labelSize: CGFloat { min(13, max(11, iconSize - 1)) }

    /// Поле по бокам подписанной кнопки и зазор между иконкой и словом.
    var labelPadding: CGFloat { 10 }
    var labelSpacing: CGFloat { 6 }

    /// Сколько места занимает кнопка с этим словом.
    ///
    /// Считаем до вёрстки: ряду нужно знать, влезет ли он, ещё до того как
    /// SwiftUI начнёт его раскладывать. Иначе подписи обрезались бы по
    /// кромке панели, а не отменялись.
    @MainActor
    func labelledWidth(_ title: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: labelSize, weight: .medium)
        let width = (title as NSString)
            .size(withAttributes: [.font: font])
            .width
        return labelPadding * 2 + iconSize + labelSpacing + ceil(width)
    }

    static let `default` = RailSize.medium.metrics
}

/// Залитый вариант символа — если он вообще есть.
///
/// У SF Symbols заливка есть не у всех. Из наших девяти её нет у
/// `music.note` и `calendar`; `timer` и `battery.75percent` заливки тоже не
/// имеют, поэтому заменены на `stopwatch` и `batteryblock` — те же
/// предметы, но с парой.
///
/// Вешать `.symbolVariant(.fill)` на весь рейл нельзя: у кнопок без пары он
/// тихо ничего не сделает, и рейл поедет — часть строк потяжелеет, часть
/// нет, и это читается как баг, а не как стиль. Поэтому спрашиваем систему
/// и честно знаем, у кого заливки нет: таким активность достаётся весом
/// штриха и белым цветом.
@MainActor
enum SymbolFill {
    private static var cache: [String: String?] = [:]

    static func filled(_ symbol: String) -> String? {
        if let known = cache[symbol] { return known }
        let candidate = symbol + ".fill"
        let resolved = NSImage(systemSymbolName: candidate, accessibilityDescription: nil) != nil
            ? candidate
            : nil
        cache[symbol] = resolved
        return resolved
    }
}

/// Размеры рейла нужны не только самому рейлу: содержимое выравнивается по
/// строке заголовка, а та ростом с кнопку.
private struct NotchRailMetricsKey: EnvironmentKey {
    static let defaultValue = RailMetrics.default
}

/// Насколько содержимое отбито от верхней кромки панели.
///
/// Нужно тем, кто вылезает за свои поля до самой кромки: свечению в плеере
/// и таймерах, прокрутке в настройках. При колонке это отступ плюс строка
/// заголовка, при ряде сверху — только отступ: заголовок там уехал в сам
/// ряд, и бледить вверх больше некуда, иначе накроет кнопки.
private struct NotchContentTopInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = NotchTheme.topInset + RailMetrics.default.itemHeight
}

/// Насколько содержимое отбито от нижней кромки панели.
///
/// Зеркало верхнего: при ряде снизу свету нужно дотечь до самой кромки,
/// под кнопки, — иначе цвет обрывается по их верхней границе и панель
/// читается как две полосы.
private struct NotchContentBottomInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = NotchTheme.contentPadding
}

/// Насколько содержимое отбито от боковых кромок панели.
///
/// Нужно тому, что должно дотянуться до самого края корпуса, а не до своих
/// полей: полосам размытия у краёв прокрутки. Полоса, обрезанная по ширине
/// содержимого, читается как плашка поверх списка — видно, где она началась
/// и где кончилась. Дотянувшись до кромок, она перестаёт быть предметом и
/// становится тем, чем и задумана: краем, за которым список тает.
///
/// В отступ входит и рейл: он стоит выше полосы и остаётся резким, а
/// затемнение проходит под ним.
private struct NotchContentLeadingInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = RailMetrics.default.thickness + NotchTheme.contentLeading
}

private struct NotchContentTrailingInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = NotchTheme.contentPadding
}

extension EnvironmentValues {
    var notchContentLeadingInset: CGFloat {
        get { self[NotchContentLeadingInsetKey.self] }
        set { self[NotchContentLeadingInsetKey.self] = newValue }
    }

    var notchContentTrailingInset: CGFloat {
        get { self[NotchContentTrailingInsetKey.self] }
        set { self[NotchContentTrailingInsetKey.self] = newValue }
    }

    var notchRailMetrics: RailMetrics {
        get { self[NotchRailMetricsKey.self] }
        set { self[NotchRailMetricsKey.self] = newValue }
    }

    var notchContentTopInset: CGFloat {
        get { self[NotchContentTopInsetKey.self] }
        set { self[NotchContentTopInsetKey.self] = newValue }
    }

    var notchContentBottomInset: CGFloat {
        get { self[NotchContentBottomInsetKey.self] }
        set { self[NotchContentBottomInsetKey.self] = newValue }
    }
}
