import SwiftUI

/// Во что складывается код погоды для картинки. Словам хватает кода WMO,
/// а небу нужно меньше делений и знание, день сейчас или ночь.
enum WeatherKind: Equatable {
    case clearDay, clearNight, partlyDay, partlyNight, cloudy, fog
    case drizzle, rain, heavyRain, sleet, snow, thunder

    init(code: Int, isDay: Bool) {
        switch code {
        case 0: self = isDay ? .clearDay : .clearNight
        case 1, 2: self = isDay ? .partlyDay : .partlyNight
        case 45, 48: self = .fog
        case 51, 53, 55: self = .drizzle
        case 56, 57, 66, 67: self = .sleet
        case 61, 63, 80, 81: self = .rain
        case 65, 82: self = .heavyRain
        case 71, 73, 75, 77, 85, 86: self = .snow
        case 95, 96, 99: self = .thunder
        default: self = .cloudy
        }
    }
}

// MARK: - Общее

/// Дробная часть: фаза цикла из бегущего времени.
private func frac(_ x: Double) -> Double { x - floor(x) }

/// Детерминированный «случай» для частицы: место и скорость частицы — функция
/// её номера, а не хранимое состояние. Кадр тогда целиком выводится из
/// времени, и хранить между кадрами нечего.
private func rnd(_ index: Int, _ salt: Int) -> Double {
    var x = UInt64(bitPattern: Int64(index &* 73_856_093 ^ salt &* 19_349_663)) &+ 0x9E37_79B9_7F4A_7C15
    x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
    x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
    x ^= x >> 31
    return Double(x % 10_000) / 10_000
}

/// Цвет как три числа: небу и облакам нужно смешивать и затемнять цвета,
/// а у `Color` компоненты наружу не достать без AppKit.
private struct RGB {
    var r, g, b: Double

    func mix(_ other: RGB, _ k: Double) -> RGB {
        RGB(r: r + (other.r - r) * k, g: g + (other.g - g) * k, b: b + (other.b - b) * k)
    }

    func scaled(_ k: Double) -> RGB { RGB(r: r * k, g: g * k, b: b * k) }

    func color(_ alpha: Double = 1) -> Color {
        Color(red: r, green: g, blue: b).opacity(alpha)
    }
}

private func disc(_ c: CGPoint, _ r: Double) -> Path {
    Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
}

private func radial(_ stops: [(Color, Double)], _ c: CGPoint, _ r: Double) -> GraphicsContext.Shading {
    .radialGradient(
        Gradient(stops: stops.map { .init(color: $0.0, location: $0.1) }),
        center: c, startRadius: 0, endRadius: r
    )
}

/// Вспышка молнии: общая для неба, частиц и туч, чтобы всё светлело разом.
/// Двойной удар — так молния и выглядит.
private enum Lightning {
    static let period = 5.7

    static func intensity(_ t: Double) -> Double {
        let local = t.truncatingRemainder(dividingBy: period)
        if local < 0.09 { return 1 }
        if local > 0.17 && local < 0.27 { return 0.7 }
        return 0
    }
}

// MARK: - Небо

/// Гладкая ступенька: 0 до `a`, 1 после `b`, плавно между. Край можно
/// перевернуть (`a > b`) — тогда ступенька вниз.
private func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let k = min(max((x - a) / (b - a), 0), 1)
    return k * k * (3 - 2 * k)
}

/// Значение по опорным точкам: между соседними — линейно.
private func keyframes<T>(_ keys: [(Double, T)], at x: Double, mix: (T, T, Double) -> T) -> T {
    guard let first = keys.first else { fatalError("пустые опорные точки") }
    if x <= first.0 { return first.1 }
    for (a, b) in zip(keys, keys.dropFirst()) where x <= b.0 {
        return mix(a.1, b.1, (x - a.0) / (b.0 - a.0))
    }
    return keys[keys.count - 1].1
}

/// Где сейчас солнце: 1 — полдень, 0 — восход или закат, −1 — глубокая
/// ночь. Днём — синус от восхода к закату, после заката — полтора часа
/// сумерек до ночи.
///
/// `NOTCH_SUN=-0.1` подменяет высоту для снимка вёрстки: закат по
/// заказу за окном не устроить.
enum SunLight {
    static func level(at now: Date, sunrise: Date?, sunset: Date?, isDay: Bool) -> Double {
        if let raw = ProcessInfo.processInfo.environment["NOTCH_SUN"], let forced = Double(raw) {
            return forced
        }
        guard let sunrise, let sunset, sunset > sunrise else { return isDay ? 0.8 : -1 }
        let t = now.timeIntervalSince1970
        let rise = sunrise.timeIntervalSince1970
        let set = sunset.timeIntervalSince1970
        if t >= rise && t <= set {
            return sin(.pi * (t - rise) / (set - rise))
        }
        let distance = t > set ? t - set : rise - t
        return -min(distance / 5400, 1)
    }
}

/// Как выглядит небо: цвета, полоса у горизонта, облачность, густота и
/// оттенок туч, где солнце и насколько оно тёплое, видны ли звёзды.
private struct SkyLook {
    var top: RGB
    var bottom: RGB
    var horizon: RGB
    var horizonAlpha: Double
    var cloudTint: RGB
    /// Доля неба под облаками: 0 — чисто, 1 — сплошной покров.
    var cover: Double
    /// Густота туч: 0 — белые кучевые, 1 — грозовые.
    var darkness: Double
    /// Вытянутость облаков: перистые в ясную погоду, кучевые в облачную.
    var stretch: Double
    /// Солнце в долях панели. Днём — высоко и правее цифры: ниже и ближе
    /// его лучи засвечивали температуру. К закату опускается к низу.
    var sun: CGPoint
    var sunStrength: Double
    /// 0 — белое дневное солнце, 1 — золотое у горизонта.
    var sunWarm: Double
    var stars: Double

    init(kind: WeatherKind, light e: Double) {
        let blend = { (a: RGB, b: RGB, k: Double) in a.mix(b, k) }

        // Ясное небо по высоте солнца: ночь → синие сумерки → закат →
        // золотой час → день.
        top = keyframes([
            (-1, RGB(r: 0.02, g: 0.03, b: 0.09)),
            (-0.45, RGB(r: 0.05, g: 0.07, b: 0.2)),
            (-0.12, RGB(r: 0.14, g: 0.17, b: 0.42)),
            (0.12, RGB(r: 0.2, g: 0.36, b: 0.72)),
            (0.45, RGB(r: 0.12, g: 0.4, b: 0.84))
        ], at: e, mix: blend)
        bottom = keyframes([
            (-1, RGB(r: 0.07, g: 0.1, b: 0.24)),
            (-0.45, RGB(r: 0.2, g: 0.23, b: 0.48)),
            (-0.12, RGB(r: 0.58, g: 0.45, b: 0.62)),
            (0.12, RGB(r: 0.86, g: 0.7, b: 0.6)),
            (0.45, RGB(r: 0.42, g: 0.65, b: 0.94))
        ], at: e, mix: blend)
        horizon = keyframes([
            (-1, RGB(r: 0.1, g: 0.12, b: 0.3)),
            (-0.4, RGB(r: 0.5, g: 0.36, b: 0.62)),
            (-0.1, RGB(r: 1, g: 0.52, b: 0.36)),
            (0.12, RGB(r: 1, g: 0.72, b: 0.42)),
            (0.45, RGB(r: 0.7, g: 0.82, b: 1))
        ], at: e, mix: blend)
        horizonAlpha = keyframes([(-1, 0.0), (-0.4, 0.55), (-0.1, 0.9), (0.12, 0.7), (0.45, 0.15)], at: e) { $0 + ($1 - $0) * $2 }
        cloudTint = keyframes([
            (-1, RGB(r: 0.5, g: 0.55, b: 0.75)),
            (-0.3, RGB(r: 0.78, g: 0.66, b: 0.86)),
            (-0.05, RGB(r: 1, g: 0.7, b: 0.6)),
            (0.15, RGB(r: 1, g: 0.86, b: 0.74)),
            (0.45, RGB(r: 1, g: 1, b: 1))
        ], at: e, mix: blend)

        let clearSky = kind == .clearDay || kind == .clearNight
        let partly = kind == .partlyDay || kind == .partlyNight
        // Ночные облака — тёмные силуэты, днём — белые.
        let nightDark = (1 - smooth(-0.6, 0.1, e)) * 0.7

        switch kind {
        case .clearDay, .clearNight:
            (cover, darkness, stretch) = (0.34, nightDark, 3.4)
        case .partlyDay, .partlyNight:
            (cover, darkness, stretch) = (0.5, 0.08 + nightDark, 1.3)
        case .cloudy: (cover, darkness, stretch) = (0.85, 0.5, 1.1)
        case .fog: (cover, darkness, stretch) = (0.95, 0.42, 2.4)
        case .drizzle: (cover, darkness, stretch) = (0.88, 0.6, 1.2)
        case .rain: (cover, darkness, stretch) = (0.92, 0.72, 1.1)
        case .heavyRain: (cover, darkness, stretch) = (1, 0.82, 1)
        case .sleet: (cover, darkness, stretch) = (0.9, 0.62, 1.1)
        case .snow: (cover, darkness, stretch) = (0.86, 0.4, 1.2)
        case .thunder: (cover, darkness, stretch) = (1, 0.9, 1)
        }

        if !clearSky && !partly {
            // Под тучами неба не видно — оно серое, того оттенка, какой
            // даёт погода, и темнеет вместе с солнцем. Закат пробивается
            // только полосой у горизонта.
            let gray: (RGB, RGB)
            switch kind {
            case .fog: gray = (RGB(r: 0.34, g: 0.4, b: 0.5), RGB(r: 0.5, g: 0.55, b: 0.62))
            case .drizzle: gray = (RGB(r: 0.26, g: 0.31, b: 0.4), RGB(r: 0.44, g: 0.49, b: 0.57))
            case .rain, .sleet: gray = (RGB(r: 0.18, g: 0.22, b: 0.3), RGB(r: 0.32, g: 0.37, b: 0.46))
            case .heavyRain: gray = (RGB(r: 0.11, g: 0.13, b: 0.18), RGB(r: 0.21, g: 0.24, b: 0.3))
            case .snow: gray = (RGB(r: 0.42, g: 0.48, b: 0.58), RGB(r: 0.6, g: 0.64, b: 0.7))
            case .thunder: gray = (RGB(r: 0.1, g: 0.1, b: 0.16), RGB(r: 0.22, g: 0.21, b: 0.3))
            default: gray = (RGB(r: 0.27, g: 0.32, b: 0.4), RGB(r: 0.45, g: 0.49, b: 0.55))
            }
            let daylight = 0.28 + 0.72 * smooth(-0.5, 0.25, e)
            top = gray.0.scaled(daylight)
            bottom = gray.1.scaled(daylight)
            horizonAlpha *= 0.35
            darkness = min(1, darkness + (1 - daylight) * 0.45)
        }

        let sunBase: Double = clearSky ? 1 : (partly ? 0.85 : 0)
        sunStrength = sunBase * smooth(-0.06, 0.08, e)
        sunWarm = 1 - smooth(0.04, 0.4, e)
        sun = Self.sunPosition(light: e)
        stars = (clearSky ? 1 : (partly ? 0.5 : 0)) * smooth(-0.15, -0.55, e)
    }

    /// Солнце в долях неба: днём высоко и правее цифры, к закату ниже.
    static func sunPosition(light e: Double) -> CGPoint {
        CGPoint(x: 0.34, y: 0.1 + (1 - smooth(0, 0.5, e)) * 0.74)
    }
}

/// Солнце в долях неба — для тех, кто рисует поверх него.
enum WeatherSun {
    static func position(at now: Date, sunrise: Date?, sunset: Date?, isDay: Bool) -> CGPoint {
        SkyLook.sunPosition(light: SunLight.level(at: now, sunrise: sunrise, sunset: sunset, isDay: isDay))
    }
}

/// Живое небо модуля — как в «Погоде» на iPhone: на всю панель, с
/// облаками, которые плывут, солнцем у цифры, закатом, дождём, снегом и
/// звёздами.
///
/// Небо рисует шейдер (Metal): облака — это шумовая плотность с
/// освещением, а не фигуры. Частицы поверх — `Canvas` по времени, без
/// состояния: частица — функция своего номера и секунды.
struct WeatherBackdrop: View {
    let kind: WeatherKind
    let isDay: Bool
    var sunrise: Date?
    var sunset: Date?
    var paused: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let look = SkyLook(
                kind: kind,
                light: SunLight.level(at: timeline.date, sunrise: sunrise, sunset: sunset, isDay: isDay)
            )
            // Время шейдеру — от начала часа: в числе с плавающей точкой
            // полная дата съедает дробную часть, и облака дёргаются.
            let skyTime = t.truncatingRemainder(dividingBy: 3600)
            let flash = kind == .thunder ? Lightning.intensity(t) : 0
            GeometryReader { proxy in
                ZStack {
                    Rectangle()
                        .fill(.black)
                        .colorEffect(ShaderLibrary.bundle(.module).weatherSky(
                            .float2(proxy.size),
                            .float(skyTime),
                            .color(look.top.color()),
                            .color(look.bottom.color()),
                            .color(look.horizon.color(look.horizonAlpha)),
                            .color(look.cloudTint.color()),
                            .float(look.cover),
                            .float(look.darkness),
                            .float(look.stretch),
                            .float2(look.sun),
                            .float(look.sunStrength),
                            .float(look.sunWarm),
                            .float(flash)
                        ))
                    Canvas { context, size in
                        if look.stars > 0 {
                            stars(in: &context, size: size, t: t, count: Int(80 * look.stars), alpha: look.stars)
                        }
                        particles(in: &context, size: size, t: t, flash: flash)
                    }
                }
            }
        }
        // Сверху — вырез, панель срастается с ним чистым чёрным. Небо,
        // дошедшее до кромки, выдало бы стык.
        .mask(
            LinearGradient(
                stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.18)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .allowsHitTesting(false)
    }

    private func particles(in context: inout GraphicsContext, size: CGSize, t: Double, flash: Double) {
        switch kind {
        case .drizzle:
            rain(in: &context, size: size, t: t, count: 50, length: 8, speed: 0.6, alpha: 0.3)
        case .rain:
            rain(in: &context, size: size, t: t, count: 110, length: 14, speed: 0.95, alpha: 0.38)
        case .heavyRain:
            rain(in: &context, size: size, t: t, count: 180, length: 20, speed: 1.3, alpha: 0.42)
        case .sleet:
            rain(in: &context, size: size, t: t, count: 60, length: 11, speed: 0.85, alpha: 0.32)
            snow(in: &context, size: size, t: t, count: 45)
        case .snow:
            snow(in: &context, size: size, t: t, count: 110)
        case .thunder:
            rain(in: &context, size: size, t: t, count: 130, length: 16, speed: 1.1, alpha: 0.4)
            bolt(in: &context, size: size, t: t, flash: flash)
        default:
            break
        }
    }

    /// Косой дождь: штрихи летят сверху вниз со сносом влево. Ближние
    /// капли длиннее и ярче дальних — так у дождя появляется глубина.
    private func rain(in context: inout GraphicsContext, size: CGSize, t: Double,
                      count: Int, length: Double, speed: Double, alpha: Double) {
        // Ветер не постоянный. Порывы: наклон плавно растёт и спадает за
        // несколько секунд, частоты несоизмеримы — ритм не угадывается.
        let gust = 0.3 + 0.22 * sin(t * 0.31) + 0.12 * sin(t * 0.83 + 1.7) + 0.06 * sin(t * 2.1 + 0.4)
        for i in 0..<count {
            let depth = rnd(i, 6)
            let v = (0.75 + 0.5 * rnd(i, 2)) * (0.7 + 0.6 * depth)
            let phase = frac(t * speed * v + rnd(i, 3))
            let len = length * (0.6 + 0.8 * depth)
            let y = phase * (size.height + len) - len
            // По высоте идут волны ветра: в разных местах панели капли
            // наклонены по-разному. Мелкие и дальние сносит сильнее —
            // крупная капля тяжелее и падает прямее.
            let local = 0.09 * sin(y * 0.018 + t * 1.3 + rnd(i, 7) * 2) + 0.05 * sin(y * 0.05 - t * 2.2)
            let drift = (gust + local) * (1.25 - 0.5 * depth)
            let x = rnd(i, 1) * (size.width + 80) - phase * (size.height + len) * drift
            var path = Path()
            path.move(to: CGPoint(x: x + len * drift, y: y))
            path.addLine(to: CGPoint(x: x, y: y + len))
            context.stroke(
                path,
                with: .linearGradient(
                    Gradient(colors: [.white.opacity(0), .white.opacity(alpha * (0.4 + 0.6 * depth))]),
                    startPoint: CGPoint(x: x + len * drift, y: y),
                    endPoint: CGPoint(x: x, y: y + len)
                ),
                style: StrokeStyle(lineWidth: 0.6 + 0.9 * depth, lineCap: .round)
            )
        }
    }


    /// Снег с глубиной: ближние хлопья крупные и размытые, дальние — мелкие
    /// и резкие; все качаются, каждое в своём ритме.
    private func snow(in context: inout GraphicsContext, size: CGSize, t: Double, count: Int) {
        for i in 0..<count {
            let depth = rnd(i, 6)
            let phase = frac(t * (0.04 + 0.06 * depth) + rnd(i, 3))
            let r = 0.8 + 2.6 * depth
            let x = rnd(i, 1) * size.width + sin(t * (0.5 + 0.6 * rnd(i, 2)) + rnd(i, 7) * 10) * (6 + 8 * depth)
            let y = phase * (size.height + 8) - 4
            let c = CGPoint(x: x, y: y)
            context.fill(disc(c, r * (1 + depth)), with: radial([
                (.white.opacity(0.9), 0),
                (.white.opacity(0.75 - 0.4 * depth), 0.45 - 0.25 * depth),
                (.white.opacity(0), 1)
            ], c, r * (1 + depth)))
        }
    }

    /// Звёзды мерцают каждая в своём ритме; самые яркие — с крестиком.
    private func stars(in context: inout GraphicsContext, size: CGSize, t: Double, count: Int, alpha fade: Double) {
        for i in 0..<count {
            let x = rnd(i, 1) * size.width
            let y = rnd(i, 2) * size.height * 0.8
            let twinkle = (sin(t * (0.8 + 1.6 * rnd(i, 3)) + rnd(i, 4) * 20) + 1) / 2
            let alpha = (0.15 + 0.6 * twinkle) * (0.4 + 0.6 * rnd(i, 5)) * fade
            let r = 0.5 + 0.9 * rnd(i, 6)
            context.fill(disc(CGPoint(x: x, y: y), r), with: .color(.white.opacity(alpha)))
            if rnd(i, 7) > 0.92 {
                let arm = 3 + 3 * twinkle
                var cross = Path()
                cross.move(to: CGPoint(x: x - arm, y: y)); cross.addLine(to: CGPoint(x: x + arm, y: y))
                cross.move(to: CGPoint(x: x, y: y - arm)); cross.addLine(to: CGPoint(x: x, y: y + arm))
                context.stroke(cross, with: .color(.white.opacity(alpha * 0.6)), lineWidth: 0.6)
            }
        }
    }

    /// Молния: ветвистая ломаная из-под туч, у каждого удара своя, в своём
    /// месте. Между ударами её нет — только отсвет в тучах от шейдера.
    private func bolt(in context: inout GraphicsContext, size: CGSize, t: Double, flash: Double) {
        guard flash > 0 else { return }
        let strike = Int(t / Lightning.period)
        let start = CGPoint(x: size.width * (0.15 + 0.7 * rnd(strike, 1)), y: size.height * 0.12)
        let step = size.height * 0.07

        var points = [start]
        var point = start
        for i in 0..<10 {
            point = CGPoint(x: point.x + (rnd(strike, i + 10) - 0.5) * step * 1.4, y: point.y + step)
            points.append(point)
        }
        var main = Path()
        main.addLines(points)

        var branch = Path()
        var tip = points[4]
        branch.move(to: tip)
        let side: Double = rnd(strike, 40) > 0.5 ? 1 : -1
        for i in 0..<4 {
            tip = CGPoint(x: tip.x + side * step * (0.6 + 0.6 * rnd(strike, i + 30)), y: tip.y + step * 0.8)
            branch.addLine(to: tip)
        }

        context.drawLayer { layer in
            layer.blendMode = .plusLighter
            layer.addFilter(.blur(radius: 6))
            layer.stroke(main, with: .color(RGB(r: 0.72, g: 0.66, b: 1).color(flash)), lineWidth: 7)
            layer.stroke(branch, with: .color(RGB(r: 0.72, g: 0.66, b: 1).color(0.6 * flash)), lineWidth: 4)
        }
        var core = context
        core.blendMode = .plusLighter
        core.stroke(main, with: .color(.white.opacity(flash)),
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        core.stroke(branch, with: .color(.white.opacity(0.7 * flash)),
                    style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
    }
}

// MARK: - Дождь на стекле

/// Где стоят стеклянные плитки дней — чтобы дождь знал, обо что биться.
struct WeatherCardFramesKey: PreferenceKey {
    static let defaultValue: [Anchor<CGRect>] = []
    static func reduce(value: inout [Anchor<CGRect>], nextValue: () -> [Anchor<CGRect>]) {
        value.append(contentsOf: nextValue())
    }
}

/// Стекло плитки: размытое небо за ней, светлая кромка и блик сверху.
struct WeatherGlass: View {
    var cornerRadius: CGFloat = 10

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            shape.fill(.ultraThinMaterial)
            shape.fill(LinearGradient(
                colors: [.white.opacity(0.10), .white.opacity(0.02)],
                startPoint: .top, endPoint: .bottom
            ))
            shape.strokeBorder(LinearGradient(
                colors: [.white.opacity(0.3), .white.opacity(0.05)],
                startPoint: .top, endPoint: .bottom
            ), lineWidth: 0.6)
        }
        .environment(\.colorScheme, .dark)
    }
}

/// Передний план дождя: капли падают на плитки и разбиваются о кромку,
/// по стеклу стекают струйки, на стекле сидят мелкие капли. Под снегом
/// на плитках лежит шапка. Остальные капли летят за плитками — это фон.
struct WeatherGlassRain: View {
    let kind: WeatherKind
    let cards: [CGRect]
    var paused: Bool
    /// Где солнце в координатах плиток — чтобы каждая грелась со своей
    /// стороны. Считает модуль: он знает, насколько небо вылезает за поля.
    var sunPoint: CGPoint = .zero

    private var intensity: Double {
        switch kind {
        case .drizzle: return 0.5
        case .rain: return 1
        case .heavyRain: return 1.7
        case .thunder: return 1.2
        case .sleet: return 0.6
        default: return 0
        }
    }

    /// Когда панель открыли. Содержимое модуля при сворачивании уходит из
    /// дерева целиком, поэтому каждое открытие — новый отсчёт: иней,
    /// наросший за прошлый взгляд, успел растаять.
    @State private var openedAt = Date()

    /// За сколько секунд плитка промерзает целиком. Медленно нарочно:
    /// иней должен нарастать, пока смотришь, а не выскакивать.
    private static let freezeDuration: Double = 80

    private var freezes: Bool { kind == .snow || kind == .sleet }
    private var sunny: Bool { kind == .clearDay || kind == .partlyDay }

    var body: some View {
        if intensity > 0 || freezes || sunny {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                // Сколько времени плитки под этой погодой: иней, вода и
                // солнечное тепло набираются, пока смотришь.
                // NOTCH_EFFECT_SECONDS=10 — всё набирается за десять секунд:
                // показать эффект целиком, не ожидая минуту.
                let fast = ProcessInfo.processInfo.environment["NOTCH_EFFECT_SECONDS"].flatMap(Double.init)
                let exposure = { (duration: Double) in
                    smooth(0, 1, (timeline.date.timeIntervalSince(openedAt) - 1.5) / (fast ?? duration))
                }
                let frost = freezes ? exposure(Self.freezeDuration) : 0
                let wet = intensity > 0 ? exposure(70) : 0
                let warmth = sunny ? exposure(60) : 0
                Canvas { context, _ in
                    for (index, card) in cards.enumerated() {
                        if intensity > 0 {
                            soak(on: card, index: index, wet: wet, t: t, in: &context)
                            beads(on: card, index: index, wet: wet, t: t, in: &context)
                            rivulets(on: card, index: index, wet: wet, t: t, in: &context)
                            impacts(on: card, index: index, t: t, in: &context)
                        }
                        if warmth > 0 {
                            sunlit(on: card, index: index, warmth: warmth, sun: sunPoint, t: t, in: &context)
                        }
                        if frost > 0 {
                            self.frost(on: card, index: index, progress: frost, t: t, in: &context)
                        }
                        if freezes {
                            snowCap(on: card, index: index, t: t, in: &context)
                        }
                    }
                }
            }
            .allowsHitTesting(false)
            .onAppear {
                // NOTCH_EXPOSED=60 — будто на панель смотрят уже минуту:
                // иней, вода и тепло для снимка вёрстки без ожидания.
                let head = ProcessInfo.processInfo.environment["NOTCH_EXPOSED"].flatMap(Double.init) ?? 0
                openedAt = Date().addingTimeInterval(-head)
            }
        }
    }

    // MARK: Вода

    /// Стекло напитывается водой: запотевает, темнеет, как мокрое, а у
    /// нижней кромки собирается полоска воды с бликом и лёгкой волной.
    private func soak(on card: CGRect, index: Int, wet: Double, t: Double, in ctx: inout GraphicsContext) {
        guard wet > 0 else { return }
        var inside = ctx
        inside.clip(to: glass(card))
        inside.fill(glass(card), with: .color(.black.opacity(0.08 * wet)))

        // Запотевание — пятнами, как дыхание на стекле, а не ровной плёнкой.
        inside.drawLayer { layer in
            layer.addFilter(.blur(radius: 4))
            for k in 0..<18 {
                let id = index * 29 + k + 11000
                let c = CGPoint(x: card.minX + card.width * rnd(id, 1), y: card.minY + card.height * rnd(id, 2))
                layer.fill(disc(c, 4 + 6 * rnd(id, 3)),
                           with: .color(RGB(r: 0.82, g: 0.9, b: 1).color((0.05 + 0.06 * rnd(id, 4)) * wet)))
            }
        }

        // Вода у нижней кромки: растёт с намоканием и чуть колышется.
        let depth = 1 + 3.5 * wet
        var pool = Path()
        pool.move(to: CGPoint(x: card.minX, y: card.maxY))
        var x = card.minX
        var surface: [CGPoint] = []
        while x <= card.maxX {
            let y = card.maxY - depth + 0.6 * sin(x * 0.12 + t * 1.6 + Double(index)) * wet
            surface.append(CGPoint(x: x, y: y))
            pool.addLine(to: CGPoint(x: x, y: y))
            x += 2
        }
        pool.addLine(to: CGPoint(x: card.maxX, y: card.maxY))
        pool.closeSubpath()
        inside.fill(pool, with: .linearGradient(
            Gradient(colors: [RGB(r: 0.75, g: 0.86, b: 1).color(0.28 * wet), RGB(r: 0.6, g: 0.75, b: 0.95).color(0.16 * wet)]),
            startPoint: CGPoint(x: card.midX, y: card.maxY - depth), endPoint: CGPoint(x: card.midX, y: card.maxY)
        ))
        var line = Path()
        line.addLines(surface)
        inside.stroke(line, with: .color(.white.opacity(0.5 * wet)), lineWidth: 0.6)
    }

    // MARK: Солнце

    /// Плитки на солнце нагреваются и ловят свет: теплеют, у них загорается
    /// кромка со стороны солнца, по ним изредка скользит блик, а на углу
    /// к солнцу стекло раскладывает свет в маленькую радугу.
    ///
    /// Сторона у каждой плитки своя: солнце стоит над панелью, и левым
    /// плиткам оно светит справа, правым — слева. Кто ближе к солнцу, тот
    /// и греется сильнее.
    private func sunlit(on card: CGRect, index: Int, warmth: Double, sun: CGPoint, t: Double,
                        in ctx: inout GraphicsContext) {
        var inside = ctx
        inside.clip(to: glass(card))
        var light = inside
        light.blendMode = .plusLighter

        let center = CGPoint(x: card.midX, y: card.midY)
        let dx = sun.x - center.x
        let dy = sun.y - center.y
        let distance = max(hypot(dx, dy), 1)
        let ux = dx / distance
        let uy = dy / distance
        // Ближние к солнцу плитки греются сильнее дальних.
        let near = 0.55 + 0.45 * smooth(420, 60, distance)
        let heat = warmth * near
        let facing = CGPoint(x: center.x + ux * card.width * 0.5, y: center.y + uy * card.height * 0.5)
        let away = CGPoint(x: center.x - ux * card.width * 0.5, y: center.y - uy * card.height * 0.5)

        // Тепло — со стороны солнца.
        light.fill(glass(card), with: .linearGradient(
            Gradient(colors: [RGB(r: 1, g: 0.82, b: 0.5).color(0.22 * heat), RGB(r: 1, g: 0.8, b: 0.5).color(0)]),
            startPoint: facing, endPoint: away
        ))

        // Кромка, обращённая к солнцу.
        light.drawLayer { layer in
            layer.addFilter(.blur(radius: 1))
            layer.stroke(glass(card), with: .linearGradient(
                Gradient(colors: [RGB(r: 1, g: 0.9, b: 0.7).color(0.65 * heat), RGB(r: 1, g: 0.9, b: 0.7).color(0)]),
                startPoint: facing,
                endPoint: CGPoint(x: center.x - ux * card.width * 0.1, y: center.y - uy * card.height * 0.1)
            ), lineWidth: 1.4)
        }

        // Блик: у каждой плитки свой случайный ритм — стекло ловит солнце
        // само по себе, а не по очереди, как по команде.
        let id = index * 19 + 13000
        let period = 7 + 9 * rnd(id, 1)
        let raw = t / period + rnd(id, 2)
        let sweep = frac(raw)
        let cycle = Int(raw)
        if sweep < 0.12, rnd(id &* 7 + cycle, 3) > 0.25 {
            let q = sweep / 0.12
            // Идёт от солнечной стороны к дальней.
            let fromRight = ux > 0
            let x = fromRight
                ? card.maxX + 30 - (card.width + 60) * q
                : card.minX - 30 + (card.width + 60) * q
            var band = Path()
            band.move(to: CGPoint(x: x - 10, y: card.maxY))
            band.addLine(to: CGPoint(x: x + 8, y: card.minY))
            band.addLine(to: CGPoint(x: x + 22, y: card.minY))
            band.addLine(to: CGPoint(x: x + 4, y: card.maxY))
            band.closeSubpath()
            light.drawLayer { layer in
                layer.addFilter(.blur(radius: 5))
                layer.fill(band, with: .color(.white.opacity(0.24 * heat * sin(q * .pi))))
            }
        }

        // Радуга на углу к солнцу: стекло как призма.
        let corner = CGPoint(x: ux < 0 ? card.minX + 10 : card.maxX - 10, y: card.minY + 10)
        let toward = atan2(uy, ux)
        light.drawLayer { layer in
            layer.addFilter(.blur(radius: 1.2))
            let colors = [RGB(r: 1, g: 0.3, b: 0.3), RGB(r: 1, g: 0.85, b: 0.3), RGB(r: 0.3, g: 1, b: 0.5), RGB(r: 0.3, g: 0.6, b: 1)]
            for (k, tint) in colors.enumerated() {
                var arc = Path()
                arc.addArc(center: corner, radius: 7 + Double(k) * 1.3,
                           startAngle: .radians(toward - 0.6), endAngle: .radians(toward + 0.6), clockwise: false)
                layer.stroke(arc, with: .color(tint.color(0.4 * heat * (0.8 + 0.2 * sin(t * 0.9 + Double(index))))), lineWidth: 1.1)
            }
        }
    }

    // MARK: Иней

    /// Плитка промерзает: сверху вниз опускается неровный фронт инея,
    /// стекло за ним мутнеет и холодеет, от кромки растут ледяные
    /// «папоротники», в замёрзшем поблёскивают искры. Всё неярко — цифры
    /// под инеем должны читаться.
    private func frost(on card: CGRect, index: Int, progress: Double, t: Double,
                       in ctx: inout GraphicsContext) {
        var inside = ctx
        inside.clip(to: glass(card))
        let seed = Double(index) * 3.7

        // Фронт инея: ниже по мере промерзания, с неровным краем.
        let reach = card.minY - 6 + (card.height + 14) * progress
        let front = { (x: Double) -> Double in
            reach + 4 * sin(x * 0.19 + seed) + 2.5 * sin(x * 0.61 + seed * 1.7)
        }
        var region = Path()
        region.move(to: CGPoint(x: card.minX, y: card.minY))
        var x = card.minX
        while x <= card.maxX {
            region.addLine(to: CGPoint(x: x, y: front(x)))
            x += 2
        }
        region.addLine(to: CGPoint(x: card.maxX, y: front(card.maxX)))
        region.addLine(to: CGPoint(x: card.maxX, y: card.minY))
        region.closeSubpath()

        inside.drawLayer { layer in
            // Мягкий фронт: иней не режет стекло линией, а наползает.
            layer.addFilter(.blur(radius: 5))
            layer.fill(region, with: .linearGradient(
                Gradient(colors: [
                    RGB(r: 0.88, g: 0.94, b: 1).color(0.32),
                    RGB(r: 0.82, g: 0.9, b: 1).color(0.2)
                ]),
                startPoint: CGPoint(x: card.midX, y: card.minY),
                endPoint: CGPoint(x: card.midX, y: max(reach, card.minY + 1))
            ))
        }

        // Кромка промерзает сильнее середины — холод идёт от края.
        inside.drawLayer { layer in
            layer.addFilter(.blur(radius: 2.2))
            layer.clip(to: region)
            layer.stroke(
                Path(roundedRect: card.insetBy(dx: 1, dy: 1), cornerRadius: 9, style: .continuous),
                with: .color(.white.opacity(0.3 * progress)), lineWidth: 3
            )
        }

        // Ледяные узоры: у каждой плитки свои, растут вместе с фронтом.
        var crystals = Path()
        for k in 0..<5 {
            let id = index * 31 + k
            let rootX = card.minX + card.width * (k < 2 ? (k == 0 ? 0.02 : 0.98) : 0.15 + 0.7 * rnd(id, 1))
            let root = CGPoint(x: rootX, y: card.minY + (k < 2 ? 3 : 0))
            // Из углов — наискосок внутрь, с верхней кромки — вниз.
            let baseAngle = k == 0 ? 0.95 : (k == 1 ? .pi - 0.95 : .pi / 2 + (rnd(id, 2) - 0.5) * 0.8)
            let grown = (progress * 1.35 - rnd(id, 3) * 0.25) * card.height * 0.9
            fern(from: root, angle: baseAngle, length: card.height * (0.55 + 0.35 * rnd(id, 4)),
                 grown: grown, id: id, into: &crystals)
        }
        // Узор — только намёком: размытый и тусклый. Резкие яркие линии
        // читались паутиной поверх плитки, а иней на стекле мягкий.
        inside.drawLayer { layer in
            layer.addFilter(.blur(radius: 2))
            layer.stroke(crystals, with: .color(RGB(r: 0.9, g: 0.95, b: 1).color(0.16)),
                         style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        }

        // Основа инея — матовые пятна изморози: наползают вместе с фронтом
        // и сливаются в мутное стекло.
        inside.drawLayer { layer in
            layer.addFilter(.blur(radius: 3.5))
            layer.clip(to: region)
            for k in 0..<26 {
                let id = index * 43 + k + 9000
                let c = CGPoint(x: card.minX + card.width * rnd(id, 1),
                                y: card.minY + card.height * rnd(id, 2))
                let r = 3 + 5 * rnd(id, 3)
                layer.fill(disc(c, r), with: .color(RGB(r: 0.92, g: 0.96, b: 1).color(0.06 + 0.08 * rnd(id, 4))))
            }
        }

        // Искры в замёрзшем: мигают по одной, как грань льда на свету.
        var sparkle = inside
        sparkle.blendMode = .plusLighter
        for k in 0..<6 {
            let id = index * 17 + k + 7000
            let p = CGPoint(x: card.minX + 4 + (card.width - 8) * rnd(id, 1),
                            y: card.minY + 3 + (card.height - 6) * rnd(id, 2))
            guard p.y < front(p.x) - 4 else { continue }
            let glint = pow(max(0, sin(t * (0.7 + 0.6 * rnd(id, 3)) + rnd(id, 4) * 20)), 24)
            guard glint > 0.02 else { continue }
            let arm = 2.5 * glint + 0.5
            var cross = Path()
            cross.move(to: CGPoint(x: p.x - arm, y: p.y)); cross.addLine(to: CGPoint(x: p.x + arm, y: p.y))
            cross.move(to: CGPoint(x: p.x, y: p.y - arm)); cross.addLine(to: CGPoint(x: p.x, y: p.y + arm))
            sparkle.stroke(cross, with: .color(.white.opacity(0.9 * glint)), lineWidth: 0.6)
            sparkle.fill(disc(p, 0.7), with: .color(.white.opacity(glint)))
        }
    }

    /// Ледяной «папоротник»: ствол чуть виляет, от него через шаг под
    /// шестьдесят градусов — так растёт лёд, у него шестигранная решётка —
    /// расходятся веточки, короче к концу. Рисуется только выросшая часть:
    /// `grown` — сколько точек вдоль ствола лёд уже прошёл.
    private func fern(from root: CGPoint, angle: Double, length: Double, grown: Double,
                      id: Int, into path: inout Path) {
        guard grown > 0 else { return }
        let step = 3.0
        var point = root
        var heading = angle
        var travelled = 0.0
        path.move(to: point)
        var i = 0
        while travelled < min(length, grown) {
            heading += (rnd(id &* 7 + i, 5) - 0.5) * 0.25
            let next = CGPoint(x: point.x + cos(heading) * step, y: point.y + sin(heading) * step)
            path.addLine(to: next)
            travelled += step
            if i % 2 == 1 {
                // Веточки по обе стороны; растут, когда ствол ушёл дальше.
                let left = min(length - travelled, 12) * (1 - travelled / length)
                let twig = min(left, max(0, (grown - travelled) * 0.6))
                if twig > 0.5 {
                    for side in [-1.0, 1.0] {
                        let a = heading + side * .pi / 3
                        path.move(to: next)
                        path.addLine(to: CGPoint(x: next.x + cos(a) * twig, y: next.y + sin(a) * twig))
                    }
                    path.move(to: next)
                }
            }
            point = next
            i += 1
        }
    }

    private func glass(_ card: CGRect) -> Path {
        Path(roundedRect: card, cornerRadius: 10, style: .continuous)
    }

    /// Капля на стекле: тёмный край преломления, светлое тело и блик.
    private func bead(at c: CGPoint, radius r: Double, alpha: Double, in ctx: inout GraphicsContext) {
        ctx.fill(disc(CGPoint(x: c.x + r * 0.25, y: c.y + r * 0.35), r), with: .color(.black.opacity(0.16 * alpha)))
        ctx.fill(disc(c, r), with: radial([
            (RGB(r: 0.85, g: 0.92, b: 1).color(0.12 * alpha), 0),
            (RGB(r: 0.85, g: 0.92, b: 1).color(0.45 * alpha), 1)
        ], c, r))
        ctx.fill(disc(CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.35), r * 0.35), with: .color(.white.opacity(0.9 * alpha)))
    }

    /// Капля-слеза: голова радиусом `radius` в точке `c`, хвост длиной
    /// `stretch` радиусов уходит против `direction` — туда, откуда капля
    /// пришла. Свет тот же, что у сидящей капли: тёмный край, светлое
    /// тело, блик на голове.
    private func teardrop(at c: CGPoint, radius r: Double, stretch: Double, direction: Double,
                          alpha: Double, in ctx: inout GraphicsContext) {
        let back = direction + .pi
        let tip = CGPoint(x: c.x + cos(back) * r * (1 + stretch), y: c.y + sin(back) * r * (1 + stretch))
        let side = direction + .pi / 2
        let left = CGPoint(x: c.x + cos(side) * r, y: c.y + sin(side) * r)
        let right = CGPoint(x: c.x - cos(side) * r, y: c.y - sin(side) * r)
        let bulge = r * (0.45 + 0.3 * stretch)
        var drop = Path()
        drop.move(to: tip)
        drop.addQuadCurve(to: left, control: CGPoint(x: left.x + cos(back) * bulge, y: left.y + sin(back) * bulge))
        drop.addArc(center: c, radius: r, startAngle: .radians(side), endAngle: .radians(side + .pi), clockwise: false)
        drop.addQuadCurve(to: tip, control: CGPoint(x: right.x + cos(back) * bulge, y: right.y + sin(back) * bulge))
        drop.closeSubpath()

        var shadow = ctx
        shadow.translateBy(x: r * 0.25, y: r * 0.35)
        shadow.fill(drop, with: .color(.black.opacity(0.16 * alpha)))
        ctx.fill(drop, with: .linearGradient(
            Gradient(colors: [RGB(r: 0.85, g: 0.92, b: 1).color(0.12 * alpha), RGB(r: 0.85, g: 0.92, b: 1).color(0.5 * alpha)]),
            startPoint: tip, endPoint: CGPoint(x: c.x + cos(direction) * r, y: c.y + sin(direction) * r)
        ))
        ctx.fill(disc(CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.3), r * 0.35), with: .color(.white.opacity(0.9 * alpha)))
    }

    /// Мелкие капли, осевшие на стекле: стоят и изредка пропадают.
    private func beads(on card: CGRect, index: Int, wet: Double, t: Double, in ctx: inout GraphicsContext) {
        var inside = ctx
        inside.clip(to: glass(card))
        // Мокнущее стекло собирает капли: их всё больше, и они крупнее.
        let count = Int((6 + 10 * wet) * intensity) + 2
        for k in 0..<count {
            let id = index * 97 + k
            let life = frac(t / (6 + 6 * rnd(id, 1)) + rnd(id, 2))
            let cycle = Int(t / (6 + 6 * rnd(id, 1)) + rnd(id, 2))
            let x = card.minX + 4 + (card.width - 8) * rnd(id &* 31 + cycle, 3)
            let y = card.minY + 4 + (card.height - 8) * rnd(id &* 31 + cycle, 4)
            let alpha = min(1, life * 8) * min(1, (1 - life) * 8)
            bead(at: CGPoint(x: x, y: y), radius: (0.6 + 1.0 * rnd(id, 5)) * (1 + 0.25 * wet), alpha: alpha, in: &inside)
        }
    }

    /// Струйки: капля набирается, срывается и бежит вниз, ускоряясь и
    /// виляя, а за ней остаётся мокрый след. У нижней кромки она уходит
    /// со стекла и падает дальше.
    private func rivulets(on card: CGRect, index: Int, wet: Double, t: Double, in ctx: inout GraphicsContext) {
        let count = max(1, Int(((1.4 + 2.6 * wet) * intensity).rounded()))
        for k in 0..<count {
            let id = index * 53 + k + 500
            let period = 3.2 + 3 * rnd(id, 1)
            let raw = t / period + rnd(id, 2)
            let phase = frac(raw)
            let cycle = Int(raw)
            let x0 = card.minX + 6 + (card.width - 12) * rnd(id &* 17 + cycle, 3)
            let y0 = card.minY + 3 + card.height * 0.35 * rnd(id &* 17 + cycle, 4)
            let wiggle = rnd(id &* 17 + cycle, 5) * 6

            // Ход струйки: капля набирается (до 0.25), бежит вниз (до 0.7),
            // повисает под нижней кромкой и набухает (до 0.84), срывается
            // и падает (до конца).
            if phase < 0.25 {
                var inside = ctx
                inside.clip(to: glass(card))
                bead(at: CGPoint(x: x0, y: y0), radius: 0.6 + 1.3 * (phase / 0.25), alpha: 1, in: &inside)
                continue
            }
            let bottom = card.maxY - 1.5
            let span = bottom - y0
            let s = min((phase - 0.25) / 0.45, 1)
            let travel = s * s * span
            let path = { (d: Double) -> CGPoint in
                CGPoint(x: x0 + sin(d * 0.28 + wiggle) * 1.3, y: y0 + d)
            }
            let head = path(travel)
            let edgeX = path(span).x

            var inside = ctx
            inside.clip(to: glass(card))
            // Мокрый след. После срыва капли он подсыхает.
            let fallProgress = phase > 0.84 ? (phase - 0.84) / 0.16 : 0
            var trail = Path()
            trail.move(to: path(0))
            var d = 0.0
            while d < travel {
                d = min(d + 2, travel)
                trail.addLine(to: path(d))
            }
            inside.stroke(trail, with: .linearGradient(
                Gradient(colors: [.white.opacity(0.04), .white.opacity(0.22 * (1 - 0.6 * fallProgress))]),
                startPoint: path(0), endPoint: head
            ), lineWidth: 1.1)

            if phase < 0.7 {
                // Бегущая капля — слеза: голова внизу, хвост по следу.
                let heading = path(travel + 1)
                let direction = atan2(heading.y - head.y, heading.x - head.x)
                teardrop(at: head, radius: 2.1, stretch: 1.0 + 1.1 * s, direction: direction, alpha: 1, in: &inside)
            } else if phase < 0.84 {
                // Повисла под кромкой: набухает, и перемычка к стеклу
                // вытягивается — вот-вот оторвётся.
                let h = (phase - 0.7) / 0.14
                let r = 2.1 + 0.8 * h
                let c = CGPoint(x: edgeX, y: card.maxY + 0.5 + 3.5 * h * h + r * 0.4)
                let stretch = max((c.y - bottom) / r - 1, 0.3)
                teardrop(at: c, radius: r, stretch: stretch, direction: .pi / 2, alpha: 1, in: &ctx)
            } else {
                // Сорвалась: падает с ускорением, вытягиваясь в полёте, до
                // самого низа панели. На кромке остаётся капелька и сохнет.
                let f = fallProgress
                let r = 2.6 - 0.6 * f
                let c = CGPoint(x: edgeX, y: card.maxY + 5 + 80 * f * f)
                let alpha = f < 0.75 ? 1 : 1 - (f - 0.75) / 0.25
                teardrop(at: c, radius: r, stretch: 0.8 + 2.2 * f, direction: .pi / 2, alpha: alpha, in: &ctx)
                bead(at: CGPoint(x: edgeX, y: bottom), radius: 1.3 * (1 - f), alpha: 1 - f, in: &inside)
            }
        }
    }

    /// Капли переднего плана: падают на верхнюю кромку плитки и разлетаются
    /// брызгами — несколько капель по параболам и короной у места удара.
    private func impacts(on card: CGRect, index: Int, t: Double, in ctx: inout GraphicsContext) {
        let count = Int(6 * intensity) + 2
        for k in 0..<count {
            let id = index * 71 + k + 900
            let period = 0.7 + 0.9 * rnd(id, 1)
            let raw = t / period + rnd(id, 2)
            let phase = frac(raw)
            let cycle = Int(raw)
            let seed = id &* 13 + cycle
            let x = card.minX + 3 + (card.width - 6) * rnd(seed, 3)
            let top = card.minY

            if phase < 0.28 {
                let q = phase / 0.28
                let y = top - 60 + 60 * q * q
                var streak = Path()
                streak.move(to: CGPoint(x: x + 3, y: y - 14))
                streak.addLine(to: CGPoint(x: x, y: y))
                ctx.stroke(streak, with: .linearGradient(
                    Gradient(colors: [RGB(r: 0.8, g: 0.9, b: 1).color(0), RGB(r: 0.85, g: 0.93, b: 1).color(0.6 * min(1, q * 2))]),
                    startPoint: CGPoint(x: x + 3, y: y - 14), endPoint: CGPoint(x: x, y: y)
                ), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                continue
            }
            guard phase < 0.62 else { continue }
            let s = (phase - 0.28) / 0.34
            let fade = 1 - s

            // Корона — сплющенное кольцо брызг у места удара.
            ctx.stroke(
                Path(ellipseIn: CGRect(x: x - 7 * s, y: top - 1.2, width: 14 * s, height: 2.4)),
                with: .color(.white.opacity(0.45 * fade)), lineWidth: 0.7
            )
            // Брызги. У края плитки их сносит наружу — капля бьётся о
            // кромку и отскакивает вбок.
            let edge = (x - card.minX) < 10 ? -1.0 : ((card.maxX - x) < 10 ? 1.0 : 0)
            // Брызги мелкие и низкие — капля не взрывается, а отскакивает
            // бисером, как на стекле в «Погоде» у iPhone.
            for j in 0..<5 {
                let vx = (rnd(seed, j + 10) - 0.5) * 26 + edge * 12
                let vy = 9 + 9 * rnd(seed, j + 20)
                let px = x + vx * s
                let py = top - vy * s + 30 * s * s
                ctx.fill(disc(CGPoint(x: px, y: py), 0.35 + 0.5 * fade),
                         with: .color(RGB(r: 0.88, g: 0.94, b: 1).color(0.85 * fade)))
            }
        }
    }

    /// Снег, осевший на верхней кромке: неровная шапка с тенью под ней.
    private func snowCap(on card: CGRect, index: Int, t: Double, in ctx: inout GraphicsContext) {
        let radius = 10.0
        // Кромка плитки сверху — вместе со скруглёнными углами: снег лежит
        // на ней, а не парит ровным бруском над плиткой.
        let edge = { (x: Double) -> Double in
            let left = card.minX + radius - x
            let right = x - (card.maxX - radius)
            let into = max(left, right, 0)
            return card.minY + radius - sqrt(max(radius * radius - into * into, 0))
        }
        // Толщина: холмистая по середине и сходящая на нет на углах — на
        // скруглении снег не держится и съезжает.
        let seed = Double(index) * 7.3
        let depth = { (x: Double) -> Double in
            let fromLeft = (x - card.minX) / (radius * 1.8)
            let fromRight = (card.maxX - x) / (radius * 1.8)
            let taper = smooth(0, 1, min(fromLeft, fromRight))
            let hills = 1 + 0.22 * sin(x * 0.21 + seed) + 0.12 * sin(x * 0.53 + seed * 2)
            return 3.6 * hills * taper
        }

        let from = card.minX + 1.5
        let to = card.maxX - 1.5
        var top: [CGPoint] = []
        var x = from
        while x <= to {
            top.append(CGPoint(x: x, y: edge(x) - depth(x)))
            x += 1
        }
        var cap = Path()
        cap.addLines(top)
        x = to
        while x >= from {
            // Низ чуть заходит на плитку — снег лежит, а не касается.
            cap.addLine(to: CGPoint(x: x, y: edge(x) + 0.8))
            x -= 1
        }
        cap.closeSubpath()

        // Тень от снега на стекле под ним.
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 1.6))
            var line = Path()
            line.addLines(top.map { CGPoint(x: $0.x, y: edge($0.x) + 1.4) })
            layer.stroke(line, with: .color(RGB(r: 0.1, g: 0.15, b: 0.3).color(0.35)), lineWidth: 1.6)
        }

        ctx.drawLayer { layer in
            // Лёгкое размытие — край сугроба мягкий, а не вырезанный.
            layer.addFilter(.blur(radius: 0.45))
            layer.fill(cap, with: .linearGradient(
                Gradient(colors: [.white, RGB(r: 0.93, g: 0.96, b: 1).color(), RGB(r: 0.72, g: 0.8, b: 0.94).color()]),
                startPoint: CGPoint(x: card.midX, y: card.minY - 4.5),
                endPoint: CGPoint(x: card.midX, y: card.minY + 1)
            ))
            var ridge = Path()
            ridge.addLines(top)
            layer.stroke(ridge, with: .color(.white.opacity(0.9)), lineWidth: 0.7)
        }

        // Комочки скатываются с углов: едут по скруглению вниз и срываются.
        for side in 0..<2 {
            let id = index * 5 + side + 3000
            let period = 4 + 4 * rnd(id, 1)
            let phase = frac(t / period + rnd(id, 2))
            guard phase < 0.55 else { continue }
            let q = phase / 0.55
            let direction: Double = side == 0 ? -1 : 1
            let cornerX = side == 0 ? card.minX + radius : card.maxX - radius
            let point: CGPoint
            if q < 0.5 {
                // По дуге угла, ускоряясь.
                let a = (q / 0.5) * (q / 0.5) * .pi / 2
                point = CGPoint(x: cornerX + direction * sin(a) * (radius + 1.2),
                                y: card.minY + radius - cos(a) * (radius + 1.2))
            } else {
                // Сорвался и падает, чуть отлетая от плитки.
                let f = (q - 0.5) / 0.5
                point = CGPoint(x: cornerX + direction * (radius + 1.2 + 4 * f),
                                y: card.minY + radius + 34 * f * f)
            }
            let alpha = q < 0.8 ? 1 : 1 - (q - 0.8) / 0.2
            ctx.fill(disc(point, 1.3), with: .color(.white.opacity(0.95 * alpha)))
        }
    }
}
