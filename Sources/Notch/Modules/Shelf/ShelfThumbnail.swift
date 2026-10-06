import AppKit
import QuickLookThumbnailing

/// Превью файла для полки. У скриншота иконка «PNG» не говорит ничего —
/// показываем сам кадр. Считаем в фоне и мелко: в плитку больше не влезет.
enum ShelfThumbnail {
    static func make(for url: URL, size: CGFloat = 72) async -> NSImage? {
        await Task.detached(priority: .utility) {
            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: CGSize(width: size, height: size),
                scale: 2,
                representationTypes: .thumbnail
            )
            let generated = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            guard let generated else { return nil }
            return NSImage(cgImage: generated.cgImage, size: generated.contentRect.size)
        }.value
    }
}
