import AppKit
import CoreImage
import SwiftUI

/// Цвет, которым панель светится справа от обложки.
///
/// Среднее по всей картинке не годится: в обложке хватает белого и теней,
/// и они утягивают его в серый — именно так выглядела первая версия.
/// Поэтому ужимаем обложку до сетки 8×8 и берём из неё самый выразительный
/// пиксель: насыщенный и не тёмный. Нам нужен не точный средний цвет, а
/// узнаваемый — тот, который человек назвал бы цветом этого альбома.
enum ArtworkColor {
    /// Ключ — хэш байтов обложки: одна и та же картинка считается один раз.
    private static var cache: [Int: Color] = [:]
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    static func dominant(_ data: Data?) -> Color? {
        guard let data, !data.isEmpty else { return nil }

        let key = data.hashValue
        if let cached = cache[key] { return cached }

        guard let color = compute(data) else { return nil }
        // Обложек за сессию бывает много, а цвет нужен только свежим:
        // кэш чистим целиком, когда он разрастается.
        if cache.count > 40 { cache.removeAll() }
        cache[key] = color
        return color
    }

    private static func compute(_ data: Data) -> Color? {
        guard let image = CIImage(data: data) else { return nil }

        // 8×8 хватает: нам нужен характер обложки, а не её детали.
        let side = 8
        let scale = CGAffineTransform(
            scaleX: CGFloat(side) / max(image.extent.width, 1),
            y: CGFloat(side) / max(image.extent.height, 1)
        )
        let small = image.transformed(by: scale)

        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        context.render(
            small,
            toBitmap: &pixels,
            rowBytes: side * 4,
            bounds: CGRect(x: 0, y: 0, width: side, height: side),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        var best: (score: CGFloat, color: NSColor)?
        var brightest: (score: CGFloat, color: NSColor)?

        for index in stride(from: 0, to: pixels.count, by: 4) {
            let color = NSColor(
                srgbRed: CGFloat(pixels[index]) / 255,
                green: CGFloat(pixels[index + 1]) / 255,
                blue: CGFloat(pixels[index + 2]) / 255,
                alpha: 1
            )
            var hue: CGFloat = 0
            var saturation: CGFloat = 0
            var brightness: CGFloat = 0
            var alpha: CGFloat = 0
            color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

            // Почти чёрное и почти белое цвета не несут: из них свечения
            // не выйдет, каким бы насыщенным ни считался их оттенок.
            guard brightness > 0.12 else { continue }
            let score = saturation * (0.3 + brightness * 0.7)
            if score > (best?.score ?? -1) { best = (score, color) }
            if brightness > (brightest?.score ?? -1) { brightest = (brightness, color) }
        }

        // Обложка целиком серая (чёрно-белое фото): выдумывать ей цвет
        // нечестно — светим её же светлым тоном.
        let picked = (best.map(\.score) ?? 0) > 0.05 ? best?.color : brightest?.color
        guard let picked else { return nil }

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        picked.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        return Color(
            capped(
                NSColor(
                    hue: hue,
                    saturation: min(saturation * 1.25, 1),
                    brightness: min(max(brightness, 0.55), 0.9),
                    alpha: 1
                )
            )
        )
    }

    /// Самая светлая яркость, которую свечению позволено набрать.
    ///
    /// Панель светится этим цветом почти в полную силу, а поверх свечения
    /// лежат белые значки — и транспорта, и ряда внизу. Жёлтая или
    /// салатовая обложка давала свет ярче самих значков: кнопки не
    /// тускнели, а пропадали. Порог считается по воспринимаемой яркости, а
    /// не по «brightness» из HSB: та у жёлтого и у синего одна, а глазу
    /// жёлтый вдвое светлее.
    private static let luminanceCap: CGFloat = 0.55

    /// Воспринимаемая яркость цвета, 0…1.
    private static func luminance(_ color: NSColor) -> CGFloat {
        guard let srgb = color.usingColorSpace(.sRGB) else { return 0 }
        return 0.2126 * srgb.redComponent
            + 0.7152 * srgb.greenComponent
            + 0.0722 * srgb.blueComponent
    }

    /// Гасит цвет до порога, не трогая оттенок и насыщенность: альбом
    /// остаётся узнаваемым по цвету, а не по светимости. Тёмным и средним
    /// обложкам это ничего не меняет — порог им не мешает.
    private static func capped(_ color: NSColor) -> NSColor {
        let lum = luminance(color)
        guard lum > luminanceCap else { return color }

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        return NSColor(
            hue: hue,
            saturation: saturation,
            brightness: brightness * luminanceCap / lum,
            alpha: alpha
        )
    }
}
