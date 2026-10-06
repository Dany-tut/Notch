import Foundation

/// Обложка из кэша самого плеера.
///
/// Electron-плеер рисует обложку CSS-фоном, и в дерево «Универсального
/// доступа» она не попадает — там из картинок только значок «18+».
/// Зато картинка, которую он уже показал, лежит у него на диске: Chromium
/// складывает ответы в свой кэш, а имя альбома зашито прямо в адрес —
/// `…/602fd025.a.24221690-1/200x200`, где `24221690` и есть `albumId`,
/// который дерево нам отдаёт ссылкой на трек.
///
/// Поэтому в сеть не ходим вовсе: ни за обложкой, ни за адресом. Это не
/// только быстрее — иначе Notch рассказывал бы Яндексу, что ты слушаешь,
/// вторым голосом поверх самого плеера.
enum ChromiumArtworkCache {
    /// Обложка альбома или nil, если плеер её ещё не скачал.
    ///
    /// Перебор каталога не из дешёвых — пара тысяч файлов, — поэтому
    /// зовётся он только на смене альбома и только не с главного потока.
    static func artwork(albumID: String, folder: String) -> Data? {
        let directory = URL.applicationSupportDirectory
            .appending(path: folder)
            .appending(path: "Cache/Cache_Data")
        guard let names = try? FileManager.default.contentsOfDirectory(
            atPath: directory.path(percentEncoded: false)
        ) else { return nil }

        // Разных размеров одной обложки в кэше лежит несколько: плеер
        // берёт мелкую в список и крупную в панель. Нужна самая большая —
        // панель растит её на всю высоту корпуса.
        var best: (side: Int, url: URL)?
        let needle = ".a.\(albumID)-"
        for name in names where name.hasSuffix("_0") {
            let file = directory.appending(path: name)
            guard let key = key(of: file), key.contains(needle),
                  let side = side(of: key), side > (best?.side ?? 0)
            else { continue }
            best = (side, file)
        }
        guard let best else { return nil }
        return image(in: best.url)
    }

    /// Адрес, по которому ответ положили в кэш. Chromium пишет его в
    /// начало файла, сразу за своим заголовком, — читать весь файл ради
    /// этого не нужно.
    private static func key(of file: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 512) else { return nil }
        // Заголовок двоичный, адрес в нём — обычный ASCII. Битые байты
        // станут заменяющим символом и на поиск подстроки не повлияют.
        let text = String(decoding: head, as: UTF8.self)
        guard let start = text.range(of: "avatars.yandex.net/get-music-content/") else {
            return nil
        }
        let tail = text[start.lowerBound...]
        let end = tail.firstIndex { !$0.isASCII || $0.isWhitespace || $0 == "\0" }
        return String(tail[..<(end ?? tail.endIndex)])
    }

    /// Сторона квадрата из хвоста адреса: `…/400x400` → 400.
    private static func side(of key: String) -> Int? {
        guard let slash = key.lastIndex(of: "/") else { return nil }
        let size = key[key.index(after: slash)...]
        guard let x = size.firstIndex(of: "x") else { return nil }
        return Int(size[..<x])
    }

    /// Тело ответа: оно идёт сразу за адресом, без своих заголовков.
    ///
    /// Где кончается картинка, спрашиваем у неё самой, а не у заголовков
    /// Chromium: те лежат в хвосте файла отдельной записью, формат
    /// которой он волен менять от версии к версии, а сигнатуры WebP, PNG
    /// и JPEG не менялись никогда.
    private static func image(in file: URL) -> Data? {
        guard let data = try? Data(contentsOf: file) else { return nil }

        if let start = data.firstRange(of: Data("RIFF".utf8)), start.lowerBound + 12 <= data.count {
            // RIFF сам говорит свою длину: четыре байта после сигнатуры,
            // и это всё, что после них, — значит плюс восемь на них самих.
            let header = data[(start.lowerBound + 4)..<(start.lowerBound + 8)]
            let size = Int(header.reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) }) + 8
            let end = start.lowerBound + size
            guard end <= data.count else { return nil }
            return data[start.lowerBound..<end]
        }
        if let start = data.firstRange(of: Data([0x89, 0x50, 0x4E, 0x47])),
           let end = data.lastRange(of: Data("IEND".utf8)) {
            // IEND — последний чанк, за ним ещё четыре байта контрольной
            // суммы, и на этом файл кончается.
            return data[start.lowerBound..<min(end.upperBound + 4, data.count)]
        }
        if let start = data.firstRange(of: Data([0xFF, 0xD8, 0xFF])),
           let end = data.lastRange(of: Data([0xFF, 0xD9])) {
            return data[start.lowerBound..<end.upperBound]
        }
        return nil
    }
}
