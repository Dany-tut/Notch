import AppKit
import SwiftUI

/// Сторона выреза, с которой висит кружок.
enum IslandSide: String, CaseIterable, Identifiable, Sendable {
    case left, right
    var id: String { rawValue }

    var titleKey: L10n.Key {
        self == .left ? .islandSideLeft : .islandSideRight
    }
}

/// Что панель показывает у схлопнутого выреза. Каждый пункт — кружок:
/// полка отдаёт превью последнего файла и число, музыка — обложку.
enum IslandIndicator: String, CaseIterable, Identifiable, Sendable {
    case shelf, music, timer
    var id: String { rawValue }

    /// Кружок ведёт в свой модуль — по нему же ищем, включён ли тот вообще.
    var moduleID: String {
        switch self {
        case .shelf: return "shelf"
        case .music: return "music"
        case .timer: return "timers"
        }
    }

    var titleKey: L10n.Key {
        switch self {
        case .shelf: return .moduleShelf
        case .music: return .moduleMusic
        case .timer: return .moduleTimers
        }
    }

    var symbol: String {
        switch self {
        case .shelf: return "rectangle.portrait.on.rectangle.portrait"
        case .music: return "music.note"
        case .timer: return "timer"
        }
    }

    var defaultSide: IslandSide {
        switch self {
        case .shelf: return .left
        case .music: return .right
        case .timer: return .right
        }
    }

    /// Плашка того же повода: пока она висит, кружок молчит — второй раз
    /// про тот же трек или звонок рассказывать нечего.
    var activityKind: NotchActivity.Kind? {
        switch self {
        case .shelf: return nil
        case .music: return .music
        case .timer: return .timer
        }
    }
}

enum IslandMetrics {
    /// Диаметр кружка и отступы. Контроллер считает по ним горячие зоны,
    /// поэтому размеры живут одним набором на всех.
    static let diameter: CGFloat = 22
    static let gap: CGFloat = 6
    static let spacing: CGFloat = 4

    /// Внутренняя разметка значков — одна на всех: полку, музыку и
    /// таймер. Раньше каждый значок отмерял отступы сам, и в ряду они
    /// стояли по-разному: у таблетки обложка прижималась к одной кромке
    /// и висела в пустоте у другой, а обводка таймера была вдвое толще
    /// соседской.
    ///
    /// `inset` — насколько содержимое утоплено от кромки, и по
    /// горизонтали ровно столько же: круглая кромка капсулы и круглая
    /// обложка внутри соосны только при равном зазоре, а лишняя точка
    /// слева видна сразу — карточка стоит не по центру торца.
    /// `innerGap` — зазор между соседними частями внутри,
    /// `border` — обводка.
    static let inset: CGFloat = 3
    static let padding: CGFloat = inset
    /// Отступ от кромки, за которой стоит не круг, а прямая фигура:
    /// цифра или ряд полосок. Круглой карточке хватает `inset` — она
    /// сама повторяет форму торца. Прямая при том же зазоре липнет к
    /// кромке: у неё углы там, где у карточки закругление.
    static let flatPadding: CGFloat = inset + 3
    static let innerGap: CGFloat = 4
    static let border: CGFloat = 1
    /// Высота содержимого: обложка, карточка полки, ряд полосок.
    static let content: CGFloat = diameter - inset * 2

    /// Скругление вложенной фигуры концентрично капсуле: радиусы
    /// отличаются ровно на расстояние между ними, иначе внутренний угол
    /// выглядит острее внешнего.
    static let contentRadius: CGFloat = diameter / 2 - inset

    /// Кружок выходит из-под выреза, когда панель уже схлопнулась: сначала
    /// ждём её анимацию, потом выезжаем, и каждый следующий — чуть позже
    /// соседа. Прячемся, наоборот, сразу, вместе с корпусом.
    ///
    /// На уезде пружина та же, что у корпуса: гладкая, без перелёта —
    /// кружки уходят под вырез вместе с ним.
    ///
    /// На выезде перелёт сильнее корпусного: кружок летит один, дольше
    /// и дальше всех, и на приземлении ему нужен отскок — иначе он
    /// просто упирается в свою точку, будто его туда поставили. Своя,
    /// более резкая пружина здесь не спорит с панелью: к моменту, когда
    /// кружок трогается, корпус уже схлопнулся, и двух движений разом
    /// не видно.
    ///
    /// `bounce` вдвое больше корпусного: на 0.24 и даже 0.38 перелёт
    /// был, но глазом не читался — кружок едет всего десяток точек, и
    /// на таком пути слабая пружина возвращает его в ноль почти без
    /// видимого хода назад. Теперь он проскакивает место, качается
    /// обратно и встаёт — и то же качание идёт по масштабу, так что на
    /// приземлении кружок ещё чуть поддаётся.
    static let badgeDelay: Double = 0.1
    static let badgeStagger: Double = 0.04
    static let badgeAnimation = Animation.spring(duration: 0.52, bounce: 0.55)

    static func animation(appearing: Bool, index: Int) -> Animation {
        appearing
            ? badgeAnimation.delay(badgeDelay + Double(index) * badgeStagger)
            : NotchTheme.collapseAnimation
    }

    /// Резкость возвращается в конце полёта, перед приземлением: пока
    /// значок под вырезом, его всё равно не видно, а размытие, снятое в
    /// середине пути, пропадает впустую — кружок долетает уже резким, и
    /// остаётся обычный переезд.
    ///
    /// Дорожка короткая и целиком внутри полёта: кружок трогается на
    /// `badgeDelay`, встаёт на место к `badgeDelay + 0.5`. Резкость идёт
    /// с середины этого отрезка — так она успевает собраться ровно к
    /// приземлению и не тянется отдельным движением после него.
    static func blurAnimation(appearing: Bool, index: Int) -> Animation {
        appearing
            ? .easeOut(duration: 0.22)
                .delay(badgeDelay + 0.16 + Double(index) * badgeStagger)
            : .easeIn(duration: 0.12)
    }

    /// Сдвиг центра значка от центра выреза: `index` — место в своём ряду,
    /// считая от выреза наружу. Ширины разные (полка-трей шире кружка
    /// музыки), поэтому идём по соседям, а не умножаем на шаг.
    /// `baseWidth` — ширина того, от чего кружки отсчитываются: обычно
    /// самого выреза, а пока на нём висит плашка — всей плашки. Иначе
    /// кружок встал бы под ней и пропал.
    static func offset(
        side: IslandSide,
        entries: [IslandPlan.Entry],
        index: Int,
        baseWidth: CGFloat
    ) -> CGFloat {
        var distance = baseWidth / 2 + gap
        for entry in entries.prefix(index) { distance += entry.width + spacing }
        distance += entries[index].width / 2
        return side == .left ? -distance : distance
    }
}

/// Кто из индикаторов сейчас имеет что показать. Одна и та же раскладка нужна
/// и вёрстке, и контроллеру (он ловит курсор на кружках), поэтому считаем её
/// в одном месте.
@MainActor
struct IslandPlan {
    /// Значок вместе с его шириной: считаем её один раз здесь, чтобы
    /// вёрстка и горячие зоны не разошлись.
    struct Entry: Identifiable {
        let indicator: IslandIndicator
        let width: CGFloat
        var id: String { indicator.id }
    }

    let left: [Entry]
    let right: [Entry]

    /// `activityKind` и `baseWidth` — про плашку на вырезе: чей повод она
    /// показывает и какой ширины. Раньше плашка просто гасила кружки —
    /// закреплённый трек висит постоянно, и вместе с ним пропадал идущий
    /// секундомер, про который больше негде было узнать. Теперь кружки
    /// отходят за её края; кому там не хватило места — тот и прячется.
    static func make(
        settings: AppSettings,
        shelf: ShelfStore,
        music: NowPlayingCoordinator,
        timers: TimerIslandState,
        enabledModules: Set<String>,
        activityKind: NotchActivity.Kind? = nil,
        baseWidth: CGFloat
    ) -> IslandPlan {
        let active = IslandIndicator.allCases.filter { indicator in
            guard settings.isIslandEnabled(indicator),
                  enabledModules.contains(indicator.moduleID) else { return false }
            if let activityKind, indicator.activityKind == activityKind { return false }
            switch indicator {
            case .shelf: return !shelf.items.isEmpty
            case .music: return music.info?.isPlaying == true
            case .timer: return timers.clock != nil
            }
        }
        let entries = active.map { indicator in
            Entry(indicator: indicator, width: width(of: indicator, shelf: shelf, timers: timers))
        }
        return IslandPlan(
            left: fit(entries.filter { settings.islandSide(for: $0.indicator) == .left },
                      baseWidth: baseWidth),
            right: fit(entries.filter { settings.islandSide(for: $0.indicator) == .right },
                       baseWidth: baseWidth)
        )
    }

    /// Кому хватило места от края плашки до края окна. Идём от выреза
    /// наружу и обрываем на первом, кто не влез: кружок, вылезший за
    /// панель, всё равно обрежется по её кромке.
    private static func fit(_ entries: [Entry], baseWidth: CGFloat) -> [Entry] {
        var budget = (NotchTheme.panelWidth - baseWidth) / 2 - IslandMetrics.gap
        var kept: [Entry] = []
        for entry in entries {
            let need = entry.width + (kept.isEmpty ? 0 : IslandMetrics.spacing)
            guard need <= budget else { break }
            budget -= need
            kept.append(entry)
        }
        return kept
    }

    private static func width(
        of indicator: IslandIndicator,
        shelf: ShelfStore,
        timers: TimerIslandState
    ) -> CGFloat {
        switch indicator {
        case .shelf: return ShelfIslandTray.width(count: shelf.items.count)
        case .music: return MusicIslandBadge.width
        case .timer: return IslandMetrics.diameter
        }
    }

    func indicators(on side: IslandSide) -> [Entry] {
        side == .left ? left : right
    }
}

// MARK: - Кружки

/// Полка: трей с превью — последние файлы в ряд и число рядом:
/// в ряд влезают не все, а знать, сколько их, нужно.
struct ShelfIslandTray: View {
    @ObservedObject var store: ShelfStore

    /// Больше трёх превью в ряду уже не читаются — сливаются в кашу.
    static let maxVisible = 3
    /// Квадрат: превью кадрируется в 1:1, иначе в ряду пляшут пропорции.
    /// Меньше капсулы на три точки сверху и снизу — карточка не упирается
    /// в кромку, а лежит внутри.
    static let card: CGFloat = IslandMetrics.content
    /// Насколько карточка утоплена в капсулу сверху и снизу.
    static let inset: CGFloat = IslandMetrics.inset
    /// Скругление концентрично капсуле: у вложенных фигур радиусы
    /// отличаются ровно на расстояние между ними, иначе внутренний угол
    /// выглядит острее внешнего и карточка читается вставленной, а не
    /// лежащей внутри. У капсулы радиус — половина высоты, значит здесь
    /// он на `inset` меньше. Для квадрата в 16 точек это ровно круг —
    /// тот же, что у обложки в таблетке музыки: остров держит одну форму.
    static let radius: CGFloat = IslandMetrics.contentRadius
    /// Карточки стояли внахлёст, и сосед срезал скруглённый угол своей
    /// прямой гранью: в ряду получались два обрубка и один квадратик.
    /// Теперь между ними зазор — у каждой карточки видны все четыре угла.
    static let gap: CGFloat = 2
    static let padding: CGFloat = IslandMetrics.padding
    /// Зазор между рядом и числом и ширина самого числа: ширину трея
    /// контроллер считает без вёрстки, поэтому размеры заданы явно.
    static let countGap: CGFloat = IslandMetrics.innerGap
    static let digit: CGFloat = 7

    static func width(count: Int) -> CGFloat {
        let shown = min(max(count, 1), maxVisible)
        let row = CGFloat(shown) * card + CGFloat(shown - 1) * gap
        let digits = CGFloat(String(max(count, 1)).count)
        return row + countGap + digits * digit
            + padding + IslandMetrics.flatPadding + 3
    }

    /// Последние файлы: свежий лежит сверху стопки, то есть правее всех.
    private var shown: [ShelfItem] {
        Array(store.items.suffix(Self.maxVisible))
    }

    var body: some View {
        HStack(spacing: Self.countGap) {
            HStack(spacing: Self.gap) {
                ForEach(shown) { item in
                    ShelfIslandCard(item: item)
                }
            }

            Text("\(store.items.count)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NotchTheme.textPrimary)
                .monospacedDigit()
        }
        .padding(.leading, Self.padding)
        .padding(.trailing, IslandMetrics.flatPadding)
        .frame(
            width: Self.width(count: store.items.count),
            height: IslandMetrics.diameter
        )
        .background {
            Capsule().fill(NotchTheme.background)
        }
        .overlay(Capsule().strokeBorder(NotchTheme.islandBorder, lineWidth: IslandMetrics.border))
        .animation(NotchTheme.expandAnimation, value: store.items.count)
    }
}

/// Одно превью в ряду. Квадрат со скруглением: картинка кадрируется по
/// короткой стороне, светлая рамка обводит её и на светлом скриншоте.
private struct ShelfIslandCard: View {
    let item: ShelfItem

    @State private var thumbnail: NSImage?

    private var icon: NSImage {
        thumbnail ?? NSWorkspace.shared.icon(forFile: item.url.path)
    }

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fill)
            .frame(width: ShelfIslandTray.card, height: ShelfIslandTray.card)
            .clipShape(RoundedRectangle(cornerRadius: ShelfIslandTray.radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ShelfIslandTray.radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            }
            .task(id: item.url) {
                thumbnail = await ShelfThumbnail.make(for: item.url, size: 48)
            }
    }
}

/// Музыка: таблетка — обложка и живой эквалайзер рядом.
///
/// Кружок с одной обложкой молчал о главном: играет ли что-то прямо
/// сейчас. Полоски отвечают на это без единой буквы, а названия трека в
/// таблетке нет нарочно — она бы дышала шириной на каждой смене песни и
/// толкала соседей.
struct MusicIslandBadge: View {
    @ObservedObject var music: NowPlayingCoordinator

    /// Обложка ровно такая же, как карточка на полке, и отступы те же:
    /// значки стоят в одном ряду и меряются одной линейкой.
    private static let cover: CGFloat = IslandMetrics.content

    /// Полоскам у кромки нужно больше воздуха, чем цифре: они узкие и
    /// светлые, и рядом с чёрным полем за капсулой при общем отступе
    /// кажутся выпавшими за край. Прибавки в пару точек не хватало —
    /// ряд всё равно читался прижатым к правому торцу.
    private static let trailing: CGFloat = IslandMetrics.flatPadding + 4

    /// Ширина постоянная: контроллер считает по ней горячую зону, а
    /// вёрстка — место соседям.
    static let width: CGFloat = IslandMetrics.padding + cover
        + IslandMetrics.innerGap + MusicIslandBars.width + trailing

    private var tint: Color {
        ArtworkColor.dominant(music.info?.artwork) ?? NotchTheme.textPrimary
    }

    var body: some View {
        HStack(spacing: IslandMetrics.innerGap) {
            MusicIslandArtwork(music: music, size: Self.cover, bordered: false)
            MusicIslandBars(tint: tint, isPlaying: music.info?.isPlaying == true)
        }
        .padding(.leading, IslandMetrics.padding)
        .padding(.trailing, Self.trailing)
        .frame(width: Self.width, height: IslandMetrics.diameter)
        .background { Capsule().fill(NotchTheme.background) }
        .overlay(Capsule().strokeBorder(NotchTheme.islandBorder, lineWidth: IslandMetrics.border))
    }
}

/// Обложка трека, а если её нет — иконка ноты. Отдельно от таблетки:
/// тем же кружком закрытая плашка показывает трек в настройках.
struct MusicIslandArtwork: View {
    @ObservedObject var music: NowPlayingCoordinator
    var size: CGFloat = IslandMetrics.diameter
    var bordered: Bool = true

    private var artwork: NSImage? {
        music.info?.artwork.flatMap(ArtworkImage.image)
    }

    var body: some View {
        ZStack {
            // Чёрная подложка, как у выреза: без неё прозрачный кружок
            // растворяется в обоях, а белая нотка на светлых — тем более.
            Circle().fill(NotchTheme.background)

            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(NotchTheme.textPrimary)
            }
        }
        .frame(width: size, height: size)
        .overlay {
            if bordered {
                Circle().strokeBorder(NotchTheme.islandBorder, lineWidth: IslandMetrics.border)
            }
        }
    }
}

/// Три полоски, которые дышат, пока играет музыка.
///
/// Анимация своя у каждой полоски и чуть разной длины — иначе они ходят
/// строем и читаются как одна мигающая деталь.
///
/// Дышат они средствами Core Animation, а не SwiftUI. `repeatForever` в
/// SwiftUI гонит перерисовку всего окна на каждом кадре: пока играла
/// музыка, три полоски в две точки шириной держали процесс на 15–25 %
/// процессора — ровно то, за что ругают соседние приложения для выреза.
/// Слой с `CABasicAnimation` крутит сервер отрисовки, а приложение в это
/// время спит.
struct MusicIslandBars: NSViewRepresentable {
    let tint: Color
    let isPlaying: Bool

    fileprivate static let bar: CGFloat = 2
    fileprivate static let gap: CGFloat = 2
    /// Самая длинная полоска — во всю высоту содержимого, вровень с
    /// обложкой рядом; остальные короче её.
    fileprivate static let heights: [CGFloat] = [
        IslandMetrics.content, IslandMetrics.content * 0.55, IslandMetrics.content * 0.8
    ]
    fileprivate static let rest: CGFloat = 0.34

    static let width: CGFloat = CGFloat(heights.count) * bar
        + CGFloat(heights.count - 1) * gap

    func makeNSView(context: Context) -> BarsView { BarsView() }

    func updateNSView(_ view: BarsView, context: Context) {
        view.update(color: NSColor(tint).cgColor, playing: isPlaying)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: BarsView, context: Context) -> CGSize? {
        CGSize(width: Self.width, height: IslandMetrics.diameter)
    }

    final class BarsView: NSView {
        private var bars: [CALayer] = []
        private var playing = false

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            for _ in MusicIslandBars.heights {
                let bar = CALayer()
                bar.cornerRadius = MusicIslandBars.bar / 2
                bar.transform = CATransform3DMakeScale(1, MusicIslandBars.rest, 1)
                layer?.addSublayer(bar)
                bars.append(bar)
            }
        }

        required init?(coder: NSCoder) { fatalError() }

        override var isFlipped: Bool { true }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for (index, bar) in bars.enumerated() {
                let height = MusicIslandBars.heights[index]
                let x = CGFloat(index) * (MusicIslandBars.bar + MusicIslandBars.gap)
                bar.bounds = CGRect(x: 0, y: 0, width: MusicIslandBars.bar, height: height)
                bar.position = CGPoint(x: x + MusicIslandBars.bar / 2, y: bounds.midY)
            }
            CATransaction.commit()
        }

        func update(color: CGColor, playing: Bool) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            bars.forEach { $0.backgroundColor = color }
            CATransaction.commit()

            guard playing != self.playing else { return }
            self.playing = playing
            for (index, bar) in bars.enumerated() {
                if playing {
                    let breathe = CABasicAnimation(keyPath: "transform.scale.y")
                    breathe.fromValue = MusicIslandBars.rest
                    breathe.toValue = 1
                    breathe.duration = 0.44 + Double(index) * 0.11
                    breathe.autoreverses = true
                    breathe.repeatCount = .infinity
                    breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    bar.add(breathe, forKey: "breathe")
                } else {
                    // Оседают плавно, с того места, где их застала пауза.
                    let current = bar.presentation()?.value(forKeyPath: "transform.scale.y") as? CGFloat
                        ?? MusicIslandBars.rest
                    bar.removeAnimation(forKey: "breathe")
                    let settle = CABasicAnimation(keyPath: "transform.scale.y")
                    settle.fromValue = current
                    settle.toValue = MusicIslandBars.rest
                    settle.duration = 0.2
                    settle.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    bar.add(settle, forKey: "settle")
                }
            }
        }
    }
}


/// Таймер: кружок с числом и дугой, которая по нему заполняется.
///
/// Полного времени тут нет нарочно: «24:17» на кружке не прочесть, а
/// главное на ходу — не секунды, а сколько осталось и много ли прошло.
/// Число говорит первое, дуга — второе. Секунды появляются сами, когда
/// до конца меньше минуты: там они и становятся главным.
struct TimerIslandBadge: View {
    @ObservedObject var state: TimerIslandState

    /// Дуга идёт внутри обводки, не вместо неё: обводка у всех значков
    /// одна и та же, и таймер не должен выделяться в ряду толщиной
    /// собственного контура.
    private static let ring: CGFloat = 2

    var body: some View {
        ZStack {
            Circle().fill(NotchTheme.background)

            Circle().strokeBorder(NotchTheme.islandBorder, lineWidth: IslandMetrics.border)

            Circle()
                .inset(by: IslandMetrics.border + Self.ring / 2)
                .trim(from: 0, to: state.progress)
                .stroke(
                    ActivityTint.orange,
                    style: StrokeStyle(lineWidth: Self.ring, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                // Доля приезжает редкими ступеньками (см. `TimerIslandState`),
                // и без сглаживания дуга дёргалась бы рывками.
                .animation(.linear(duration: 0.4), value: state.progress)

            // Тот же кегль, что у числа на полке: два числа в одном ряду
            // должны читаться одинаково.
            Text(state.short ?? "")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(NotchTheme.textPrimary)
                .padding(.horizontal, IslandMetrics.inset + Self.ring)
        }
        .frame(width: IslandMetrics.diameter, height: IslandMetrics.diameter)
    }
}


/// Размытие как часть перехода: `.blur` сам по себе в `AnyTransition` не
/// заворачивается, поэтому оборачиваем его модификатором.
struct IslandBlur: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        content.blur(radius: radius)
    }
}
