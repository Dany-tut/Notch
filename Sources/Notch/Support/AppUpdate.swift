import Foundation

/// Своя версия — из Info.plist собранного бандла. Туда её кладёт
/// `build-app.sh` из файла `VERSION` в корне репозитория: номер живёт в
/// одном месте, и тег релиза сверяется с ним же.
///
/// При запуске прямо из SwiftPM (`swift run`) плиста нет, поэтому есть
/// запасное значение — оно нарочно неправдоподобное, чтобы не выдать
/// отладочный запуск за собранную версию.
enum AppVersion {
    static let current: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }()

    /// Как версия выглядит в интерфейсе: `v0.2.1`.
    ///
    /// Отдельно от `current`, потому что в `current` лежит голый номер —
    /// с ним сравнивают теги и его печатают в имени файла. Буква «v» —
    /// дело показа, и приписывается она в одном месте, иначе половина
    /// экранов пишет «0.2.1», а половина «v0.2.1».
    static var display: String { "v" + current }

    /// Та же огранка для чужого номера — версии из релиза на GitHub.
    static func display(_ version: String) -> String {
        "v" + version.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
    }

    /// Штамп сборки: время и коммит, из которого она собрана (звёздочка —
    /// в дереве были несохранённые правки). Кладёт его `build-app.sh`.
    ///
    /// Зачем отдельно от версии: номер версии между правками не меняется,
    /// и по нему нельзя понять, ту ли сборку смотришь — старая копия в
    /// `build/Notch.app` выглядит ровно так же, как только что собранная.
    /// Штамп меняется всегда.
    ///
    /// Пусто при запуске из SwiftPM (`swift run`): плиста нет — тогда в
    /// настройках стоит «dev».
    static let build: String = {
        Bundle.main.object(forInfoDictionaryKey: "NotchBuildStamp") as? String ?? "dev"
    }()

    /// Сравниваем по числовым частям, а не строками: «0.10.0» новее «0.9.0»,
    /// хотя по алфавиту наоборот. Хвост «v» и суффиксы вроде «-beta» режем.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        parts(current).lexicographicallyPrecedes(parts(candidate))
    }

    private static func parts(_ raw: String) -> [Int] {
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        let head = trimmed.split(separator: "-", maxSplits: 1).first.map(String.init) ?? trimmed
        let numbers = head.split(separator: ".").map { Int($0) ?? 0 }
        // Дополняем до трёх разрядов, иначе «1.2» и «1.2.0» считаются разными.
        return numbers + Array(repeating: 0, count: max(0, 3 - numbers.count))
    }
}

/// Проверка обновлений по файлу на сайте. Ответ читаем ровно настолько,
/// насколько нужно: номер версии и ссылка, куда вести за загрузкой.
///
/// Файл, а не GitHub: Pro-сборка живёт в закрытом репозитории и раздаётся
/// после оплаты, а простая — с сайта. Одного адреса хватает обеим.
@MainActor
final class UpdateChecker: ObservableObject {
    /// Версия последнего релиза, если она новее текущей. Иначе nil —
    /// и в настройках просто стоит номер версии без стрелки.
    @Published private(set) var availableVersion: String?
    @Published private(set) var downloadURL: URL?

    private var lastCheck: Date?
    private var isChecking = false

    private static let endpoint = URL(string: "https://notch-mac.vercel.app/latest.json")!

    /// Дёргается при открытии настроек, поэтому не чаще раза в час:
    /// вкладки переключают часто, а релизы выходят редко.
    func checkIfNeeded() {
        if let lastCheck, Date().timeIntervalSince(lastCheck) < 3600 { return }
        guard !isChecking else { return }
        isChecking = true
        Task { await check() }
    }

    private func check() async {
        defer { isChecking = false; lastCheck = Date() }

        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData

        // Сеть недоступна, файла ещё нет — всё это не повод шуметь:
        // просто остаёмся без стрелки.
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let release = try? JSONDecoder().decode(Release.self, from: data),
              AppVersion.isNewer(release.version, than: AppVersion.current)
        else { return }

        availableVersion = release.version.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        #if PRO
        // Pro отдаётся после оплаты, поэтому ведём в «Мои заказы».
        downloadURL = URL(string: release.proUrl ?? release.url)
        #else
        downloadURL = URL(string: release.url)
        #endif
    }

    private struct Release: Decodable {
        let version: String
        let url: String
        let proUrl: String?
    }
}
