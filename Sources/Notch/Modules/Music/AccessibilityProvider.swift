import ApplicationServices
import AppKit

/// Плеер, который читается через дерево «Универсального доступа».
///
/// Нужен для Electron-приложений вроде Яндекс Музыки: AppleScript они не
/// понимают, а `MediaRemote` на свежих macOS закрыт и отдаёт пустоту. Зато
/// свою панель они рисуют обычным DOM, и Chromium публикует её как дерево
/// доступа — там лежит всё: название, артисты, позиция, длительность и
/// состояние лайка. Кнопки оттуда же и нажимаются.
///
/// Единственное, чего в дереве нет, — обложка: она CSS-фоном, а фоны в
/// дерево не попадают.
@MainActor
final class AccessibilityProvider: NowPlayingProvider {
    let name = "Универсальный доступ"

    /// Играет или нет — спрашиваем у системы, а не у дерева.
    ///
    /// Chromium придерживает фоновые таймеры страницы, и подпись кнопки
    /// в свёрнутом окне отстаёт на десятки секунд. Ассершен «playing
    /// audio» живёт в ядре и не врёт никогда.
    private let audio: AudioActivityProvider

    /// Чей плеер читаем. Меняется вместе с выбором источника.
    var target: MusicPlayer?

    /// Один читатель на провайдера: он помнит найденную панель.
    private let reader = Reader()

    init(audio: AudioActivityProvider) {
        self.audio = audio
    }

    // MARK: - Подписи кнопок

    /// Названия элементов панели. Яндекс подписывает их для screen
    /// reader'ов на языке интерфейса, поэтому держим оба варианта: свою
    /// вёрстку он меняет часто, а эти подписи — почти никогда.
    private enum Label {
        static let pause: Set<String> = ["Пауза", "Pause"]
        static let play: Set<String> = ["Воспроизведение", "Play"]
        static let next: Set<String> = ["Следующая песня", "Next track"]
        static let previous: Set<String> = ["Предыдущая песня", "Previous track"]
        static let like: Set<String> = ["Нравится", "Like"]
        static let dislike: Set<String> = ["Не нравится", "Dislike"]
        static let timecode: Set<String> = ["Управление таймкодом", "Timecode control"]
        static let playerBar: Set<String> = ["Плеер", "Player"]
        /// Название трека и имя артиста приходят в описании ссылки с
        /// приставкой: «Трек Painted», «Артист Effin».
        static let trackPrefixes = ["Трек ", "Track "]
        static let artistPrefixes = ["Артист ", "Artist "]
        /// Панель «Моей волны» (5.104) ссылок не держит: трек в ней —
        /// бегущая строка «Артист — Трек», а с 5.104.2 — просто название,
        /// артист же уехал из панели в блок страницы над ней.
        static let artistTitleSeparator = " — "
    }

    // MARK: - Чтение

    func fetch() async -> NowPlayingInfo? {
        guard let target, let app = target.runningApp else {
            forget()
            return nil
        }
        guard AXIsProcessTrusted() else { return nil }

        let pid = app.processIdentifier
        // Обход дерева — это запросы в чужой процесс, и отвечает он не
        // мгновенно. На главном потоке такой обход подвесил бы панель,
        // поэтому уходим в фон и возвращаемся уже с готовым снимком.
        let snapshot = await reader.read(pid: pid)
        guard let snapshot else {
            forget()
            return nil
        }

        let playing = audio.isPlayingAudio(pid: pid)
        isDisliked = snapshot.isDisliked
        refreshArtwork(albumID: snapshot.albumID, player: target)
        return NowPlayingInfo(
            title: snapshot.title,
            artist: snapshot.artists.joined(separator: ", "),
            artwork: artwork?.album == snapshot.albumID ? artwork?.data : nil,
            elapsed: elapsed(snapshot.elapsed, duration: snapshot.duration, isPlaying: playing),
            duration: snapshot.duration,
            isPlaying: playing,
            source: target.displayName,
            sourceBundleID: target.bundleID,
            isFavorite: snapshot.isLiked,
            canSeek: snapshot.duration > 0
        )
    }

    /// Трек в дизлайке. Отдельно от `NowPlayingInfo`: там про это поля
    /// нет, а держать ради одного плеера — разносить модель на всех.
    private(set) var isDisliked: Bool?

    // MARK: - Позиция

    /// Последняя позиция, которую дерево показало по-настоящему, и когда
    /// это было.
    private var lastReading: (seconds: TimeInterval, at: Date)?

    /// На сколько можно досчитывать позицию самим.
    ///
    /// Живое дерево меняет секунды не реже раза в секунду, так что
    /// десяти хватает на любую заминку. Дальше — это уже не заминка, а
    /// придержанная страница, и досчитывать нечего: без резкости лучше,
    /// чем с враньём. Раньше предела не было, и полоса у играющего трека
    /// спокойно доезжала до конца, пока сам трек был на середине.
    private static let maxDrift: TimeInterval = 10

    /// Позиция с поправкой на то, что страница считает её сама.
    ///
    /// Перекрытому окну Chromium придерживает таймеры, и слайдер стоит на
    /// месте, пока музыка идёт. Пока дерево показывает то же число, что и
    /// в прошлый раз, досчитываем секунды по своим часам — иначе панель
    /// показывала бы замерший прогресс у играющего трека.
    private func elapsed(
        _ reported: TimeInterval,
        duration: TimeInterval,
        isPlaying: Bool
    ) -> TimeInterval {
        defer {
            if lastReading?.seconds != reported { lastReading = (reported, Date()) }
        }
        guard isPlaying, let last = lastReading, last.seconds == reported else { return reported }
        let drift = min(Date().timeIntervalSince(last.at), Self.maxDrift)
        let grown = reported + drift
        return duration > 0 ? min(grown, duration) : grown
    }

    /// Плеер закрылся или перестал отвечать — своей версии позиции
    /// больше нет, иначе она всплывёт поверх следующего трека.
    private func forget() {
        lastReading = nil
        isDisliked = nil
        artwork = nil
        lastMiss = nil
        artworkSearch?.cancel()
        artworkSearch = nil
    }

    // MARK: - Обложка

    /// Найденная обложка и чей это был альбом. Пока альбом тот же,
    /// повторно не ищем: перебор кэша — пара тысяч файлов.
    private var artwork: (album: String, data: Data)?

    /// Альбом, обложки которого в кэше не нашлось, и когда мы смотрели.
    ///
    /// Промах — не приговор: плеер кладёт картинку на диск не в тот же
    /// миг, что показывает её у себя, и у только начавшегося трека её
    /// там ещё может не быть. Раньше пустой ответ запоминался навсегда,
    /// и обложка появлялась через раз — смотря кто успел первым.
    private var lastMiss: (album: String, at: Date, tries: Int)?

    /// Через сколько смотреть ещё раз. Достаточно редко, чтобы перебор
    /// каталога не шёл на каждом опросе, и достаточно часто, чтобы
    /// обложка догоняла трек на глазах, а не к его концу.
    private static let retryAfter: TimeInterval = 4

    /// Сколько раз пробовать. Двадцати секунд плееру хватает с запасом;
    /// не успел — значит картинку он показывает из памяти и на диск не
    /// положит вовсе, а перебирать каталог до конца трека незачем.
    private static let maxTries = 5

    /// Идущий поиск. Держим, чтобы не заводить второй на следующем
    /// опросе: полторы секунды меньше, чем перебор каталога.
    private var artworkSearch: Task<Void, Never>?

    /// Достать обложку альбома, если он сменился.
    ///
    /// Чтения с диска, поэтому в фоне: на главном потоке это заметная
    /// заминка панели на каждой смене трека.
    private func refreshArtwork(albumID: String?, player: MusicPlayer) {
        guard let albumID, let folder = player.chromiumCacheFolder else { return }
        guard artwork?.album != albumID, artworkSearch == nil else { return }
        if let lastMiss, lastMiss.album == albumID,
           lastMiss.tries >= Self.maxTries
               || Date().timeIntervalSince(lastMiss.at) < Self.retryAfter { return }
        artworkSearch = Task { [weak self] in
            let data = await Task.detached(priority: .utility) {
                ChromiumArtworkCache.artwork(albumID: albumID, folder: folder)
            }.value
            guard let self, !Task.isCancelled else { return }
            if let data {
                self.artwork = (albumID, data)
                self.lastMiss = nil
            } else {
                let tries = self.lastMiss?.album == albumID ? (self.lastMiss?.tries ?? 0) : 0
                self.lastMiss = (albumID, Date(), tries + 1)
            }
            self.artworkSearch = nil
        }
    }

    // MARK: - Команды

    func send(_ command: TransportCommand) {
        guard let pid = target?.runningApp?.processIdentifier else { return }
        Task { [reader] in
            switch command {
            case .playPause: await reader.press(pid: pid, any: Label.pause.union(Label.play))
            case .next: await reader.press(pid: pid, any: Label.next)
            case .previous: await reader.press(pid: pid, any: Label.previous)
            }
        }
    }

    func seek(to seconds: TimeInterval) {
        guard let pid = target?.runningApp?.processIdentifier else { return }
        // Своя позиция сразу: слайдер в чужом окне ответит новым числом
        // не раньше следующего опроса, а полоса не должна отскакивать.
        lastReading = (seconds, Date())
        Task { [reader] in await reader.setSlider(pid: pid, to: seconds) }
    }

    func toggleLike() {
        guard let pid = target?.runningApp?.processIdentifier else { return }
        Task { [reader] in await reader.press(pid: pid, any: Label.like) }
    }

    func toggleDislike() {
        guard let pid = target?.runningApp?.processIdentifier else { return }
        Task { [reader] in await reader.press(pid: pid, any: Label.dislike) }
    }

    // MARK: - Обход дерева

    /// Снимок панели плеера.
    private struct Snapshot: Sendable {
        var title = ""
        /// Номер альбома из адреса ссылки на трек. По нему находится
        /// обложка, которую плеер уже скачал себе.
        var albumID: String?
        var artists: [String] = []
        var elapsed: TimeInterval = 0
        var duration: TimeInterval = 0
        var isLiked: Bool?
        var isDisliked: Bool?
    }

    /// Работа с чужим деревом.
    ///
    /// Отдельный актор, а не набор функций: все вызовы сюда синхронные и
    /// идут в другой процесс, звать их с главного потока нельзя — панель
    /// вставала бы на каждый неотвеченный запрос. Заодно он помнит, где
    /// нашёл панель плеера: путь до неё — это шесть сотен узлов, а сама
    /// панель — полсотни, и искать её заново каждые полторы секунды
    /// стоит приложению процентов десяти процессора.
    private actor Reader {
        /// Найденная панель и чья она. Ссылка живёт, пока страница не
        /// подменит узел; перестала отвечать — ищем заново.
        private var cached: (pid: pid_t, bar: AXUIElement)?

        /// Панель выбранного плеера: из памяти, если та ещё отвечает.
        private func bar(pid: pid_t) -> AXUIElement? {
            if let cached, cached.pid == pid, isAlive(cached.bar) { return cached.bar }
            guard let found = Self.playerBar(pid: pid) else {
                cached = nil
                return nil
            }
            cached = (pid, found)
            return found
        }

        /// Узел ещё тот самый: отвечает и всё ещё подписан «Плеер».
        /// Chromium переиспользует ссылки, и мёртвая молча отдаёт ошибку.
        private func isAlive(_ element: AXUIElement) -> Bool {
            Self.isPlayerBarLabel(element)
        }

        /// Подпись «Плеер»: старая панель кладёт её в `AXTitle`, панель
        /// «Моей волны» (5.104) — в `AXDescription`.
        private static func isPlayerBarLabel(_ element: AXUIElement) -> Bool {
            Label.playerBar.contains(string(element, kAXTitleAttribute) ?? "")
                || Label.playerBar.contains(string(element, kAXDescriptionAttribute) ?? "")
        }

        /// Сколько ждать ответа на один запрос. Electron отвечает не
        /// всегда, и без своего срока обход встаёт насмерть.
        private static let messagingTimeout: Float = 0.4

        /// Глубина и число узлов. Дерево страницы — это весь DOM, и без
        /// предела обход уходит в десятки тысяч узлов.
        private static let maxDepth = 24
        private static let maxNodes = 8_000

        func read(pid: pid_t) -> Snapshot? {
            guard let bar = bar(pid: pid) else { return nil }
            var snapshot = Snapshot()
            var found = false
            var marquee: String?
            var firstText: String?
            Self.walk(bar) { element in
                let role = Self.string(element, kAXRoleAttribute)
                let description = Self.string(element, kAXDescriptionAttribute) ?? ""

                if role == "AXLink" {
                    if let title = Self.strip(description, Label.trackPrefixes), snapshot.title.isEmpty {
                        snapshot.title = title
                        snapshot.albumID = Self.albumID(of: element)
                        found = true
                    } else if let artist = Self.strip(description, Label.artistPrefixes) {
                        snapshot.artists.append(artist)
                    }
                }
                if role == kAXStaticTextRole,
                   let text = Self.string(element, kAXValueAttribute), !text.isEmpty {
                    if firstText == nil { firstText = text }
                    if marquee == nil, text.contains(Label.artistTitleSeparator) { marquee = text }
                }
                if role == kAXSliderRole, Label.timecode.contains(description) {
                    snapshot.elapsed = Self.number(element, kAXValueAttribute) ?? 0
                    snapshot.duration = Self.number(element, kAXMaxValueAttribute) ?? 0
                    found = true
                }
                if role == kAXCheckBoxRole {
                    if Label.like.contains(description) {
                        snapshot.isLiked = Self.number(element, kAXValueAttribute) == 1
                    } else if Label.dislike.contains(description) {
                        snapshot.isDisliked = Self.number(element, kAXValueAttribute) == 1
                    }
                }
            }
            // Ссылки на трек нет — значит, это панель «Моей волны», и трек
            // берём из бегущей строки. Делим по первому тире: в названиях
            // треков оно встречается куда чаще, чем в именах артистов.
            if snapshot.title.isEmpty, let marquee,
               let range = marquee.range(of: Label.artistTitleSeparator) {
                snapshot.title = String(marquee[range.upperBound...])
                if snapshot.artists.isEmpty {
                    snapshot.artists = [String(marquee[..<range.lowerBound])]
                }
            }
            // 5.104.2: в панели только название, без тире и без ссылок.
            // Единственный текст в ней — оно и есть.
            if snapshot.title.isEmpty, let firstText {
                snapshot.title = firstText
            }
            // Артиста в такой панели нет — он лежит в блоке страницы рядом,
            // ссылками «Артист …». Ищем у родителя панели, не во всём окне:
            // в карусели «Моей волны» такие же ссылки у чужих треков.
            if !snapshot.title.isEmpty, snapshot.artists.isEmpty,
               let parent = Self.parent(of: bar) {
                Self.walk(parent) { element in
                    guard Self.string(element, kAXRoleAttribute) == "AXLink",
                          let artist = Self.strip(
                              Self.string(element, kAXDescriptionAttribute) ?? "",
                              Label.artistPrefixes
                          ),
                          !snapshot.artists.contains(artist)
                    else { return }
                    snapshot.artists.append(artist)
                }
            }
            // Панель нашлась, но пустая — так выглядит плеер, которому
            // ещё нечего играть. Это не ответ, а его отсутствие.
            return found ? snapshot : nil
        }

        func press(pid: pid_t, any labels: Set<String>) {
            guard let bar = bar(pid: pid) else { return }
            var target: AXUIElement?
            Self.walk(bar) { element in
                guard target == nil, labels.contains(Self.string(element, kAXDescriptionAttribute) ?? "")
                else { return }
                target = element
            }
            guard let target else { return }
            AXUIElementPerformAction(target, kAXPressAction as CFString)
        }

        func setSlider(pid: pid_t, to seconds: TimeInterval) {
            guard let bar = bar(pid: pid) else { return }
            var slider: AXUIElement?
            Self.walk(bar) { element in
                guard slider == nil,
                      Self.string(element, kAXRoleAttribute) == kAXSliderRole,
                      Label.timecode.contains(Self.string(element, kAXDescriptionAttribute) ?? "")
                else { return }
                slider = element
            }
            guard let slider else { return }
            AXUIElementSetAttributeValue(
                slider,
                kAXValueAttribute as CFString,
                NSNumber(value: seconds) as CFTypeRef
            )
        }

        /// Корень приложения, разбуженный для чтения содержимого окна.
        ///
        /// Electron держит DOM вне дерева доступа, пока об этом никто не
        /// спросил: иначе каждая страница стоила бы ему лишней работы.
        /// Спрашивают атрибутом `AXManualAccessibility` — без него в
        /// дереве видны только кнопки заголовка окна.
        private static func root(pid: pid_t) -> AXUIElement {
            let root = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(root, messagingTimeout)
            AXUIElementSetAttributeValue(
                root,
                "AXManualAccessibility" as CFString,
                kCFBooleanTrue
            )
            return root
        }

        /// Регион панели плеера — по подписи, а не по месту в дереве.
        ///
        /// Разметку страницы Яндекс меняет с каждым обновлением, а
        /// «Плеер» в `AXTitle` — это его же подпись для screen reader'ов,
        /// и держится она куда дольше классов вида `PlayerBar_root__cXUnU`.
        private static func playerBar(pid: pid_t) -> AXUIElement? {
            var bar: AXUIElement?
            Self.walk(Self.root(pid: pid)) { element in
                guard bar == nil,
                      Self.string(element, kAXRoleAttribute) == kAXGroupRole,
                      Self.isPlayerBarLabel(element)
                else { return }
                bar = element
            }
            return bar
        }

        /// Обход с пределами по глубине, числу узлов и времени. Предел по
        /// времени — не про скорость: неотвечающее окно способно тянуть
        /// каждый запрос до таймаута, и обход не кончится никогда.
        private static func walk(_ element: AXUIElement, _ visit: (AXUIElement) -> Void) {
            var seen = 0
            let deadline = Date().addingTimeInterval(2)
            func step(_ element: AXUIElement, _ depth: Int) {
                guard depth <= maxDepth, seen < maxNodes, Date() < deadline else { return }
                seen += 1
                visit(element)
                for child in Self.children(of: element) { step(child, depth + 1) }
            }
            step(element, 0)
        }

        private static func parent(of element: AXUIElement) -> AXUIElement? {
            var raw: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                element,
                kAXParentAttribute as CFString,
                &raw
            ) == .success, let raw, CFGetTypeID(raw) == AXUIElementGetTypeID()
            else { return nil }
            return (raw as! AXUIElement)
        }

        private static func children(of element: AXUIElement) -> [AXUIElement] {
            var raw: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                element,
                kAXChildrenAttribute as CFString,
                &raw
            ) == .success, let array = raw as? [AXUIElement] else { return [] }
            return array
        }

        private static func string(_ element: AXUIElement, _ key: String) -> String? {
            var raw: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, key as CFString, &raw) == .success,
                  let text = raw as? String
            else { return nil }
            return text
        }

        /// Номер альбома из адреса ссылки: у неё `AXURL` вида
        /// `music-application://desktop/album/track?albumId=…&trackId=…`.
        /// Ссылка тут не для перехода — только за этим номером.
        private static func albumID(of element: AXUIElement) -> String? {
            var raw: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                element,
                kAXURLAttribute as CFString,
                &raw
            ) == .success, let url = raw as? NSURL,
                  let components = URLComponents(string: url.absoluteString ?? "")
            else { return nil }
            return components.queryItems?.first { $0.name == "albumId" }?.value
        }

        private static func number(_ element: AXUIElement, _ key: String) -> Double? {
            var raw: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, key as CFString, &raw) == .success,
                  let value = raw as? NSNumber
            else { return nil }
            return value.doubleValue
        }

        /// «Трек Painted» → «Painted». Хвостовые пробелы Яндекс в этих
        /// подписях оставляет свои.
        private static func strip(_ text: String, _ prefixes: [String]) -> String? {
            for prefix in prefixes where text.hasPrefix(prefix) {
                let value = String(text.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : value
            }
            return nil
        }
    }
}
