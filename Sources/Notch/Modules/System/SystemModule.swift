import SwiftUI

/// Система: процессор, память, сеть, диск — четыре плитки с графиком
/// за последнюю минуту.
struct SystemModule: NotchModule {
    let id = "system"
    let titleKey: L10n.Key = .moduleSystem
    let symbol = "gauge.with.dots.needle.33percent"

    let store: SystemStore

    func makeContent() -> some View {
        SystemContent(store: store)
    }
}

private struct SystemContent: View {
    @ObservedObject var store: SystemStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(spacing: 10) {
            // Не сетка: плитки должны занять всю высоту панели поровну, а
            // ряды `LazyVGrid` тянуться не умеют — каждый ровно по
            // содержимому, и половина панели осталась бы пустой.
            HStack(spacing: 10) {
                MetricTile(
                    symbol: "cpu",
                    title: settings.t(.systemCPU),
                    value: percent(store.cpu),
                    detail: settings.t(.systemLoad),
                    level: store.cpu,
                    history: store.cpuHistory
                )
                MetricTile(
                    symbol: "memorychip",
                    title: settings.t(.systemMemory),
                    value: percent(store.memory),
                    detail: "\(Self.size(store.memoryUsed)) / \(Self.size(store.memoryTotal))",
                    level: store.memory,
                    history: store.memoryHistory
                )
            }
            HStack(spacing: 10) {
                MetricTile(
                    symbol: "network",
                    title: settings.t(.systemNetwork),
                    value: Self.rate(store.download),
                    detail: "↑ \(Self.rate(store.upload))",
                    // У сети нет потолка, по которому считать долю: полоску
                    // ведём от самого быстрого мгновения за минуту — так
                    // видно всплеск, а не абсолютную скорость.
                    level: Self.share(store.download + store.upload, in: store.networkHistory),
                    history: store.networkHistory.map { Self.share($0, in: store.networkHistory) }
                )
                MetricTile(
                    symbol: "internaldrive",
                    title: settings.t(.systemDisk),
                    value: percent(diskShare),
                    detail: "\(Self.size(store.diskTotal - min(store.diskUsed, store.diskTotal))) \(settings.t(.systemFree))",
                    level: diskShare,
                    // Свободное место за минуту не меняется, поэтому и
                    // история ровная: заливка встаёт на уровень занятого
                    // и стоит — плитке так же, как памяти, есть что
                    // показать высотой.
                    history: Array(repeating: diskShare, count: SystemStore.historyLength)
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Опрос идёт только пока модуль открыт.
        .onAppear { store.resume() }
        .onDisappear { store.suspend() }
    }

    private var diskShare: Double {
        guard store.diskTotal > 0 else { return 0 }
        return min(Double(store.diskUsed) / Double(store.diskTotal), 1)
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    /// Доля от пика в истории. Пустая или ровная история — ноль: делить
    /// не на что, и полоска честно пустая.
    private static func share(_ value: Double, in history: [Double]) -> Double {
        guard let peak = history.max(), peak > 0 else { return 0 }
        return min(value / peak, 1)
    }

    private static func size(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private static func rate(_ bytesPerSecond: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        // Иначе ноль у него выходит словом — «Zero KB», — а в ряду цифр
        // это читается как сбой, а не как тишина на линии.
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: Int64(max(bytesPerSecond, 0))) + "/s"
    }
}

/// Плитка одного показателя: значение крупно, график за спиной.
private struct MetricTile: View {
    let symbol: String
    let title: String
    let value: String
    let detail: String
    let level: Double
    let history: [Double]

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // График занимает всю плитку, а не полоску у низа: тогда
            // высота заливки сама по себе значит уровень, и ровные
            // показатели — память, диск — читаются как налитый стакан,
            // а не как обрубок графика под цифрами.
            ZStack {
                SparklineFill(values: history)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.22), tint.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                // Линия по верху заливки: градиент сам по себе размазан,
                // а форму показателя держит именно кромка.
                SparklineLine(values: history)
                    .stroke(tint.opacity(0.85), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: symbol)
                        .font(.system(size: 11))
                        .foregroundStyle(tint)
                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(NotchTheme.textSecondary)
                    Spacer(minLength: 0)
                }
                Text(value)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(NotchTheme.textPrimary)
                    .monospacedDigit()
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(NotchTheme.textTertiary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        // Линия идёт до самых краёв, и половина её толщины иначе
        // вылезает за скругление плитки.
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Цвет по нагрузке: спокойный до двух третей, дальше предупреждает.
    private var tint: Color {
        if level >= 0.9 { return ActivityTint.red }
        if level >= 0.66 { return ActivityTint.orange }
        return ActivityTint.green
    }
}

/// Общая геометрия графика: точки и сглаженная кривая по ним. Фигуры
/// ниже рисуют одно и то же — заливку и линию по её кромке, — и считать
/// её дважды незачем.
private enum SparklineGeometry {
    static func points(_ values: [Double], in rect: CGRect) -> [CGPoint] {
        guard values.count > 1 else { return [] }

        let step = rect.width / CGFloat(SystemStore.historyLength - 1)
        // Короткую историю прижимаем к правому краю: свежая точка всегда
        // у правого края, а график растёт справа налево.
        let offset = rect.width - step * CGFloat(values.count - 1)

        return values.enumerated().map { index, value in
            CGPoint(
                x: offset + step * CGFloat(index),
                y: rect.maxY - rect.height * CGFloat(min(max(value, 0), 1))
            )
        }
    }

    /// Кривая Катмулла — Рома кубическими кривыми Безье: каждый отрезок
    /// ведут соседние точки, поэтому на пиках нет углов. Управляющие
    /// точки прижимаем к рамке — иначе сглаживание выносит линию за
    /// верх плитки там, где всплеск упёрся в сто процентов.
    static func curve(through points: [CGPoint], in rect: CGRect) -> Path {
        var path = Path()
        appendCurve(to: &path, through: points, in: rect, startingSubpath: true)
        return path
    }

    /// Дописывает кривую в готовый путь. Заливке нужно именно это:
    /// `addPath` начал бы новый подпуть, и замыкание срезало бы её по
    /// диагонали от правого низа к первой точке.
    static func appendCurve(to path: inout Path, through points: [CGPoint], in rect: CGRect, startingSubpath: Bool) {
        guard let first = points.first else { return }
        if startingSubpath {
            path.move(to: first)
        } else {
            path.addLine(to: first)
        }
        guard points.count > 1 else { return }

        for index in 0..<(points.count - 1) {
            let p0 = points[max(index - 1, 0)]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = points[min(index + 2, points.count - 1)]

            // Шестая часть расстояния до через-точки — привычное
            // натяжение: линия мягкая, но ещё идёт по данным.
            let control1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6,
                y: clamp(p1.y + (p2.y - p0.y) / 6, in: rect)
            )
            let control2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6,
                y: clamp(p2.y - (p3.y - p1.y) / 6, in: rect)
            )
            path.addCurve(to: p2, control1: control1, control2: control2)
        }
    }

    private static func clamp(_ y: CGFloat, in rect: CGRect) -> CGFloat {
        min(max(y, rect.minY), rect.maxY)
    }
}

/// Замкнутая область под кривой. Пустая история — пустая фигура, а не
/// прямая по нулю: так видно, что данных ещё нет.
private struct SparklineFill: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        let points = SparklineGeometry.points(values, in: rect)
        guard let first = points.first, let last = points.last else { return Path() }

        var path = Path()
        path.move(to: CGPoint(x: first.x, y: rect.maxY))
        SparklineGeometry.appendCurve(to: &path, through: points, in: rect, startingSubpath: false)
        path.addLine(to: CGPoint(x: last.x, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Сама кривая поверх заливки: она и держит форму, заливка лишь тень.
private struct SparklineLine: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        SparklineGeometry.curve(through: SparklineGeometry.points(values, in: rect), in: rect)
    }
}
