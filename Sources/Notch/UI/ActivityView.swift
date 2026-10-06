import SwiftUI

/// Плашка события у схлопнутого выреза.
///
/// Вырез остаётся выrömрезом: содержимое разложено по его бокам — иконка слева,
/// текст справа. Под камеру ничего не заезжает, поэтому плашка одинаково
/// выглядит и на настоящем нотче, и на нарисованном.
struct ActivityView: View {
    let activity: NotchActivity
    /// Ширина самого выреза: между «ушами» оставляем ровно её.
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let onTap: () -> Void

    /// Уши разной ширины: слева длинное название, справа короткая приписка
    /// вроде процента заряда. Ширина не фиксированная, а по тексту: у
    /// «Adele» и «When We Were Young» запросы разные, и общая мерка режет
    /// то одно, то другое. Снизу держим минимум — чтобы короткое событие
    /// не съёживалось в огрызок.
    static let minLeadingEar: CGFloat = 148
    static let minTrailingEar: CGFloat = 112
    /// Потолок один на оба уха — ширина панели: шире плашки просто нет
    /// окна, она уедет под обрез. Внутри этого запаса текст не режем
    /// вовсе, а если двоим тесно — сначала ужимаем исполнителя: название
    /// трека важнее. Что не влезло и после этого, уходит под многоточие:
    /// мельчить буквы ради длинного названия — значит сделать нечитаемой
    /// всю плашку, включая короткие.
    static let maxPlateWidth: CGFloat = NotchTheme.panelWidth
    /// Обложка и зазор до названия — их место в левом ухе занято всегда.
    private static let iconWidth: CGFloat = 22
    private static let iconSpacing: CGFloat = 7

    static func ears(for activity: NotchActivity?, notchWidth: CGFloat) -> (leading: CGFloat, trailing: CGFloat) {
        let wantLeading = activity.map {
            max(minLeadingEar, iconWidth + iconSpacing + width(of: $0.title, size: 11, weight: .semibold))
        } ?? minLeadingEar
        // Сколько приписке нужно на самом деле и сколько она просит с
        // запасом: пока не тесно, ухо держит минимум — короткое «84 %» не
        // должно липнуть к вырезу.
        let subtitleWidth = activity?.subtitle.flatMap { subtitle -> CGFloat? in
            subtitle.isEmpty ? nil : width(of: subtitle, size: 11, weight: .regular)
        }
        let wantTrailing = subtitleWidth.map { max(minTrailingEar, $0) } ?? minTrailingEar

        let budget = maxPlateWidth - notchWidth - horizontalInset * 2
        guard wantLeading + wantTrailing > budget else {
            return (wantLeading, wantTrailing)
        }
        // Тесно — режем приписку: сначала отдаём название всё, что оно
        // просит, а исполнителю остаётся хвост бюджета. Ниже его
        // собственной строки не опускаемся, а вот минимум ухо тут уже не
        // держит: запас, оставленный «на всякий случай», уходит названию —
        // из-за него длинные названия уезжали под многоточие, пока справа
        // рядом с «Summer Walker» стояло пустое место.
        let floor = min(wantTrailing, subtitleWidth ?? minTrailingEar)
        let trailing = max(floor, min(wantTrailing, budget - wantLeading))
        return (max(minLeadingEar, budget - trailing), trailing)
    }

    /// Меряем тем же шрифтом, каким рисуем, и добавляем волосок: округление
    /// вниз обрезает последнюю букву многоточием на ровном месте.
    private static func width(of text: String, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        let measured = (text as NSString)
            .size(withAttributes: [.font: font])
            .width
        return ceil(measured) + 1
    }

    /// Плашка чуть выше выреза — так видно, что это не просто нотч.
    static let extraHeight: CGFloat = 6
    /// Отступы по краям: обложка слева и приписка справа не должны липнуть
    /// к границам плашки. Их закладываем в саму ширину — иначе уши
    /// фиксированной ширины съедают отступ и содержимое снова встаёт
    /// вплотную.
    static let horizontalInset: CGFloat = 12

    static func size(notch: CGSize, activity: NotchActivity?) -> CGSize {
        let ears = ears(for: activity, notchWidth: notch.width)
        return CGSize(
            width: notch.width + ears.leading + ears.trailing + horizontalInset * 2,
            height: notch.height + extraHeight
        )
    }

    private var ears: (leading: CGFloat, trailing: CGFloat) {
        Self.ears(for: activity, notchWidth: notchWidth)
    }

    var body: some View {
        HStack(spacing: 0) {
            leading
                .frame(width: ears.leading, alignment: .leading)
            Color.clear
                .frame(width: notchWidth)
            trailing
                .frame(width: ears.trailing, alignment: .trailing)
        }
        .frame(height: notchHeight, alignment: .center)
        .padding(.horizontal, Self.horizontalInset)
        // Рамку растягиваем на всю высоту плашки — на те самые
        // `extraHeight` ниже выреза. Иначе нижний край, к которому
        // цепляется прогресс, совпадает с нижним краем выреза, и линия
        // уходит под остров: на настоящем нотче её не видно вовсе.
        .frame(height: notchHeight + Self.extraHeight, alignment: .top)
        .background(alignment: .topLeading) { artworkGlow }
        .overlay(alignment: .bottom) { progressLine }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    /// Слева — то, ради чего плашка появилась: иконка и название.
    private var leading: some View {
        HStack(spacing: Self.iconSpacing) {
            icon
            // Длинному названию не хватит и полной ширины окна: шире
            // панели плашке некуда расти, а мельчить буквы ради одного
            // трека — значит сделать нечитаемыми все остальные. Поэтому
            // то, что не влезло, не режем, а показываем по очереди:
            // строка неспешно проезжает туда и обратно, тая на краях.
            MarqueeText(
                text: activity.title,
                width: ears.leading - Self.iconWidth - Self.iconSpacing,
                textWidth: Self.width(of: activity.title, size: 11, weight: .semibold)
            )
        }
    }

    /// Цвет обложки, разлитый вокруг неё.
    ///
    /// Слабое пятно, чуть шире самой обложки: это отсвет от неё, а не
    /// подсветка строки. Вдоль названия он гаснет раньше, чем доходит до
    /// текста, — иначе читался бы как вторая подложка под плашкой.
    /// Края всё так же мягкие, без различимой границы.
    ///
    /// Только у обложки: выдумывать сияние батарее или наушникам незачем —
    /// их цвет наш, а не их.
    private static let glowWidth: CGFloat = 74
    private static let glowHeight: CGFloat = 46

    @ViewBuilder
    private var artworkGlow: some View {
        if activity.artwork != nil {
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            activity.tint.opacity(0.55),
                            activity.tint.opacity(0.23),
                            activity.tint.opacity(0)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: Self.glowWidth / 2
                    )
                )
                .frame(width: Self.glowWidth, height: Self.glowHeight)
                .blur(radius: 11)
                .offset(
                    x: Self.horizontalInset + Self.iconWidth / 2 - Self.glowWidth / 2,
                    y: notchHeight / 2 - Self.glowHeight / 2
                )
                .allowsHitTesting(false)
        }
    }

    /// Обложка вытесняет иконку: она говорит о треке больше, чем нота.
    @ViewBuilder
    private var icon: some View {
        if let data = activity.artwork, let image = ArtworkImage.image(data) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: Self.iconWidth, height: Self.iconWidth)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            Image(systemName: activity.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(activity.tint)
                .frame(width: Self.iconWidth, height: Self.iconWidth)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(activity.tint.opacity(0.18))
                }
        }
    }

    /// Справа — приписка: исполнитель, процент, «Подключено».
    @ViewBuilder
    private var trailing: some View {
        if let subtitle = activity.subtitle {
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(NotchTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    /// Прогресс — рельса по самому низу плашки, вплотную к краю: в высоту
    /// выреза полноценный индикатор не помещается, а полоска ниже выреза —
    /// единственное место, которое остров не закрывает.
    ///
    /// Ни отступов по бокам, ни зазора снизу: с ними линия висит в воздухе
    /// посреди этой полоски и читается как промах вёрстки, а не как край.
    /// По краям её подрезают скруглённые углы корпуса — плашку обрезает
    /// общая форма, и линия садится точно по её обводу. Дорожка под
    /// заполнением нужна по той же причине: она показывает, где у линии
    /// конец, иначе короткий прогресс выглядит просто крашеным углом.
    @ViewBuilder
    private var progressLine: some View {
        if let progress = activity.progress {
            GeometryReader { proxy in
                Rectangle()
                    .fill(activity.tint)
                    .frame(width: proxy.size.width * min(max(progress, 0), 1))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 2.5)
            .background(activity.tint.opacity(0.16))
        }
    }
}

/// Строка, которая не влезла в своё ухо: вместо многоточия она едет
/// справа налево по кругу.
///
/// Едет в одну сторону, а не туда-обратно: качели заставляют возвращаться
/// взглядом к уже прочитанному, а круг читается как одна бесконечная
/// строка. За хвостом идёт вторая копия — пока первая уезжает, вторая
/// входит справа, и в момент стыка кадр подменяется на исходный: шва
/// не видно.
///
/// Едет силами Core Animation, а не SwiftUI: `repeatForever` в SwiftUI
/// перекладывает всё окно на каждом кадре, и закреплённая плашка с
/// длинным названием держала бы процессор занятым, пока висит. Слой
/// двигает сервер отрисовки, приложение в это время спит.
///
/// Ширину меряем снаружи, той же меркой, что и уши: `GeometryReader`
/// внутри плашки схлопнул бы её высоту, а лишний слой ради числа, которое
/// уже посчитано, тут ни к чему.
private struct MarqueeText: View {
    let text: String
    /// Место под строку в ухе — за вычетом обложки и зазора.
    let width: CGFloat
    let textWidth: CGFloat

    private var overflows: Bool { textWidth > width }

    var body: some View {
        if overflows {
            MarqueeLayer(text: text, width: max(width, 0), textWidth: textWidth)
                .frame(width: max(width, 0), height: 14)
        } else {
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NotchTheme.textPrimary)
                .lineLimit(1)
                .frame(width: max(width, 0), alignment: .leading)
        }
    }
}

private struct MarqueeLayer: NSViewRepresentable {
    let text: String
    let width: CGFloat
    let textWidth: CGFloat

    /// Скорость подобрана под чтение: быстрее — и глаз не успевает за
    /// строкой, медленнее — движение начинает мозолить глаз в углу экрана.
    static let speed: CGFloat = 26
    /// Пауза перед стартом: название сначала нужно прочитать с начала,
    /// а уже потом догонять хвост.
    static let dwell: Double = 1.6
    /// Разрыв между копиями: без него конец названия упирается в его же
    /// начало и читается как одно слово.
    static let gap: CGFloat = 44
    /// Ширина растворения на краях: жёсткий обрез читается как ошибка
    /// вёрстки, мягкий — как продолжение строки.
    static let fade: CGFloat = 12

    func makeNSView(context: Context) -> View { View() }

    func updateNSView(_ view: View, context: Context) {
        view.configure(text: text, width: width, textWidth: textWidth)
    }

    final class View: NSView {
        private let strip = CALayer()
        private let copies = [CATextLayer(), CATextLayer()]
        private let mask = CAGradientLayer()
        private var current: String?

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.masksToBounds = true
            copies.forEach(strip.addSublayer)
            layer?.addSublayer(strip)
            mask.startPoint = CGPoint(x: 0, y: 0.5)
            mask.endPoint = CGPoint(x: 1, y: 0.5)
            layer?.mask = mask
        }

        required init?(coder: NSCoder) { fatalError() }

        override var isFlipped: Bool { true }

        func configure(text: String, width: CGFloat, textWidth: CGFloat) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
            let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
            let string = NSAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: NSColor.white
            ])
            let height = ceil(font.ascender - font.descender) + 1
            let cycle = textWidth + MarqueeLayer.gap
            for (index, copy) in copies.enumerated() {
                copy.string = string
                copy.contentsScale = scale
                copy.frame = CGRect(x: CGFloat(index) * cycle, y: 0, width: textWidth, height: height)
            }
            strip.frame = CGRect(x: 0, y: (bounds.height - height) / 2, width: cycle * 2, height: height)
            mask.frame = bounds
            let edge = NSNumber(value: Double(MarqueeLayer.fade / max(width, 1)))
            mask.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
            mask.locations = [0, edge, NSNumber(value: 1 - edge.doubleValue), 1]
            CATransaction.commit()

            // Новый трек — строка возвращается в начало и трогается заново:
            // иначе название меняется на полпути.
            guard text != current else { return }
            current = text
            strip.removeAnimation(forKey: "travel")
            let travel = CABasicAnimation(keyPath: "position.x")
            travel.fromValue = strip.position.x
            travel.toValue = strip.position.x - cycle
            // Ход ровный: круг замкнут, и любая плавность на концах выдала
            // бы место стыка.
            travel.duration = Double(cycle / MarqueeLayer.speed)
            travel.repeatCount = .infinity
            travel.beginTime = CACurrentMediaTime() + MarqueeLayer.dwell
            travel.fillMode = .backwards
            strip.add(travel, forKey: "travel")
        }

        override func layout() {
            super.layout()
            if let current {
                let text = current
                self.current = nil
                // Перекладываем по новым границам и перезапускаем ход.
                configure(text: text, width: bounds.width, textWidth: copies[0].frame.width)
            }
        }
    }
}
