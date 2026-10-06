import Foundation

/// Эмодзи: поиск по-русски и по-английски, недавние сверху.
@MainActor
final class EmojiStore: ObservableObject {
    struct Entry: Identifiable, Hashable {
        let emoji: String
        let category: EmojiCategory
        /// Английское название — его и показываем под курсором.
        let name: String
        /// Всё, по чему ищем, одной строкой в нижнем регистре.
        let keywords: String

        var id: String { emoji }
    }

    private enum Keys {
        static let recent = "emoji.recent"
    }

    /// Сколько недавних держим: два ряда сетки.
    static let recentLimit = 32

    @Published var query = ""
    @Published var isSearching = false {
        didSet { if !isSearching { query = "" } }
    }
    @Published private(set) var recent: [String]

    /// Все эмодзи по разделам. Строится один раз, при первом показе
    /// модуля: названия из `CFStringTransform` недёшевы, а тысяча их на
    /// каждый символ запроса — тем более.
    private(set) lazy var entries: [Entry] = Self.buildEntries()
    private lazy var byEmoji: [String: Entry] = Dictionary(
        entries.map { ($0.emoji, $0) },
        uniquingKeysWith: { first, _ in first }
    )

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        recent = defaults.stringArray(forKey: Keys.recent) ?? []
    }

    func entries(in category: EmojiCategory) -> [Entry] {
        entries.filter { $0.category == category }
    }

    var recentEntries: [Entry] {
        recent.compactMap { byEmoji[$0] }
    }

    func entry(for emoji: String) -> Entry? { byEmoji[emoji] }

    /// Совпадение по началу любого слова: «сер» находит «сердце», но не
    /// «серьёзно» внутри «несерьёзно». Найденное в начале названия — выше.
    func search(_ text: String) -> [Entry] {
        let needle = text.lowercased().trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return [] }
        if needle.unicodeScalars.contains(where: \.properties.isEmojiPresentation) {
            return entries.filter { $0.emoji == needle }
        }
        let words = needle.split(separator: " ").map(String.init)
        return entries
            .filter { entry in words.allSatisfy { Self.matches(entry.keywords, prefix: $0) } }
            .sorted { lhs, rhs in
                let l = lhs.keywords.hasPrefix(needle)
                let r = rhs.keywords.hasPrefix(needle)
                return l && !r
            }
    }

    func use(_ emoji: String) {
        var list = recent.filter { $0 != emoji }
        list.insert(emoji, at: 0)
        recent = Array(list.prefix(Self.recentLimit))
        defaults.set(recent, forKey: Keys.recent)
    }

    private static func matches(_ keywords: String, prefix: String) -> Bool {
        var range = keywords.startIndex..<keywords.endIndex
        while let found = keywords.range(of: prefix, range: range) {
            if found.lowerBound == keywords.startIndex
                || !keywords[keywords.index(before: found.lowerBound)].isLetter {
                return true
            }
            range = found.upperBound..<keywords.endIndex
        }
        return false
    }

    // MARK: - Названия

    private static func buildEntries() -> [Entry] {
        let english = Locale(identifier: "en")
        let russian = Locale(identifier: "ru")
        var seen = Set<String>()
        var result: [Entry] = []
        for category in EmojiCategory.allCases {
            for emoji in category.emoji where seen.insert(emoji).inserted {
                var name = unicodeName(emoji)
                var extra = EmojiData.russian[emoji] ?? ""
                if category == .flags, let region = regionCode(of: emoji) {
                    name = english.localizedString(forRegionCode: region) ?? name
                    extra = [russian.localizedString(forRegionCode: region), region]
                        .compactMap { $0 }
                        .joined(separator: " ")
                }
                result.append(Entry(
                    emoji: emoji,
                    category: category,
                    name: name,
                    keywords: "\(name) \(extra)".lowercased()
                ))
            }
        }
        return result
    }

    /// «GRINNING FACE» → «grinning face». Служебные знаки склейки и
    /// вариантов в названии не нужны: «woman zero width joiner laptop»
    /// никто не ищет.
    private static func unicodeName(_ emoji: String) -> String {
        let string = NSMutableString(string: emoji)
        CFStringTransform(string, nil, kCFStringTransformToUnicodeName, false)
        let skipped: Set<String> = ["ZERO WIDTH JOINER", "VARIATION SELECTOR-16", "COMBINING ENCLOSING KEYCAP"]
        let names = (string as String)
            .components(separatedBy: "\\N{")
            .compactMap { part -> String? in
                guard let end = part.firstIndex(of: "}") else { return part.isEmpty ? nil : part }
                let name = String(part[..<end])
                return skipped.contains(name) ? nil : name
            }
        return names.joined(separator: " ").lowercased()
    }

    private static func regionCode(of flag: String) -> String? {
        let letters = flag.unicodeScalars.compactMap { scalar -> Character? in
            guard (0x1F1E6...0x1F1FF).contains(scalar.value),
                  let ascii = Unicode.Scalar(scalar.value - 0x1F1E6 + 0x41) else { return nil }
            return Character(ascii)
        }
        return letters.count == 2 ? String(letters) : nil
    }
}
