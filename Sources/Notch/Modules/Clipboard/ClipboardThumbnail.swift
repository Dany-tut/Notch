import AppKit
import ImageIO

/// Превью картинки из истории буфера.
///
/// Скриншот в буфере — это кадр экрана целиком: пара тысяч пикселей по
/// стороне. Рисовать его в плитке 96 на 76 нельзя — панель начинает
/// заикаться на прокрутке. Поэтому уменьшаем при чтении, средствами
/// ImageIO: он разворачивает файл сразу в нужный размер, а не грузит
/// полный кадр ради того, чтобы его ужать.
enum ClipboardThumbnail {
    private static let cache = NSCache<NSString, NSImage>()

    static func make(for url: URL, size: CGFloat = 256) async -> NSImage? {
        let key = "\(url.path)@\(Int(size))" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let image = await Task.detached(priority: .utility) { () -> NSImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: size * 2
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            else { return nil }
            return NSImage(cgImage: cg, size: CGSize(width: cg.width, height: cg.height))
        }.value

        if let image { cache.setObject(image, forKey: key) }
        return image
    }
}
