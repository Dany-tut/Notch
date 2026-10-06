import AppKit

/// Читает и двигает плееры, которые умеют говорить по AppleScript.
///
/// Видно только их — зато без приватных API и без риска, что Apple
/// однажды всё закроет.
@MainActor
final class AppleScriptProvider: NowPlayingProvider {
    let name = "AppleScript"

    /// Пользователь прибил источник к конкретному плееру — работаем
    /// только с ним. nil — спрашиваем всех по очереди.
    var target: String?

    /// Последняя ошибка AppleScript. Нужна, чтобы отличить «плеер молчит»
    /// от «нам запретили Автоматизацию»: во втором случае помочь может
    /// только пользователь, и об этом надо сказать вслух.
    private(set) var lastErrorCode: Int?

    /// Плеер ответил и сказал, что стоит. Это не то же самое, что молчание:
    /// молчит — значит не достучались, стоит — значит играть нечему.
    private(set) var answeredStopped = false

    /// Система отказала в отправке Apple Events этому приложению.
    var isDenied: Bool {
        lastErrorCode == -1743 || lastErrorCode == -1744
    }

    /// Плеер, который ответил в прошлый раз, — его и спрашиваем первым.
    private var preferred: MusicPlayer?
    private var artworkCache: (key: String, data: Data)?
    private let runner = AppleScriptRunner()

    /// Что играло последним. У остановленного плеера `current track` не
    /// существует, и `play` ему нечего возобновлять — поэтому помним сами
    /// и просим этот трек по имени.
    var resumeTarget: (title: String, artist: String)?

    func fetch() async -> NowPlayingInfo? {
        answeredStopped = false
        for player in candidates where player.isRunning {
            if let info = await read(player) {
                preferred = player
                return info
            }
        }
        preferred = nil
        return nil
    }

    func send(_ command: TransportCommand) {
        guard let player = current else { return }
        send(command, to: player)
    }

    /// Команда конкретному плееру.
    ///
    /// Отдельно от `send(_:)` затем, что источник бывает известен точнее,
    /// чем догадка «первый запущенный»: панель показывает иконку Music —
    /// значит и команду ждут от Music.
    func send(_ command: TransportCommand, to player: MusicPlayer) {
        guard let scriptName = player.scriptName else { return }
        // У остановленного Music и `playpause`, и `play` молча не делают
        // ничего: ставить на паузу нечего, продолжать тоже — текущего трека
        // нет, ошибки при этом не возникает. Поэтому состояние проверяем
        // сами, а завести просим ровно тот трек, который панель показывала
        // последней. Раньше здесь стоял первый трек медиатеки — и play
        // включал случайную песню вместо той, которую человек видел.
        let body = switch command {
        case .playPause:
            """
            if player state is playing then
                pause
            else
                play
                if player state is not playing then
                    \(resumeBody)
                end if
            end if
            """
        // У остановленного плеера перематывать нечего, а `next track`
        // его именно что заводит — с первого трека медиатеки. Случайный
        // скролл над вырезом так включал музыку на весь дом.
        case .next: "if player state is not stopped then next track"
        case .previous: "if player state is not stopped then previous track"
        }
        runner.fire("""
        tell application "\(scriptName)"
            try
                \(body)
            end try
        end tell
        """)
    }

    /// Чем заводить остановленный плеер: ищем в медиатеке ровно тот трек,
    /// который панель показывала последним. Не нашли — молчим. Заиграть не
    /// тем хуже, чем не заиграть вовсе: второе человек понимает сразу,
    /// первое выглядит как самоволие приложения.
    private var resumeBody: String {
        guard let resumeTarget, !resumeTarget.title.isEmpty else { return "" }
        let title = Self.escaped(resumeTarget.title)
        let artist = Self.escaped(resumeTarget.artist)
        return """
        try
                        set matches to (every track of library playlist 1 whose name is "\(title)" and artist is "\(artist)")
                        if matches is not {} then play item 1 of matches
                    end try
        """
    }

    /// Имя трека уезжает внутрь строкового литерала AppleScript, а в нём
    /// встречаются и кавычки, и обратная косая.
    private static func escaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Умеем ли мы вообще говорить с выбранным плеером.
    var canHandleTarget: Bool {
        guard let target else { return true }
        return MusicPlayer.player(for: target)?.scriptName != nil
    }

    private var candidates: [MusicPlayer] {
        if let target {
            guard let player = MusicPlayer.player(for: target), player.scriptName != nil else { return [] }
            return [player]
        }
        guard let preferred else { return MusicPlayer.scriptable }
        return [preferred] + MusicPlayer.scriptable.filter { $0.bundleID != preferred.bundleID }
    }

    private var current: MusicPlayer? {
        candidates.first { $0.isRunning } ?? (target == nil ? preferred : nil)
    }

    // MARK: - Чтение

    private func read(_ player: MusicPlayer) async -> NowPlayingInfo? {
        guard let scriptName = player.scriptName else { return nil }
        // Поля разделяем символом, который не встретится в названии трека.
        // Каждое поле читаем отдельно и под `try`: у радиопотоков и
        // Apple Music-станций части свойств нет, и одна такая ошибка
        // раньше рушила весь запрос — панель оставалась пустой.
        //
        // Имена переменных — полные. Короткое `st` здесь не годится:
        // AppleScript держит `st`, `nd`, `rd`, `th` под порядковые
        // числительные («1st item»), и `set st to ...` не компилируется
        // вовсе. Скрипт падал ещё до обращения к плееру, а молчал так же,
        // как отказ в доступе, — из-за этого панель и пустовала.
        // «Избранное» у Music называется то `loved`, то `favorited`: свойство
        // переименовали вместе с переездом «Любимого» в «Избранное», и на
        // разных версиях живо то одно, то другое. Спрашиваем оба и отдаём
        // пустую строку, если не ответило ни одно, — тогда панель знает,
        // что звёздочке тут не место.
        let script = """
        tell application "\(scriptName)"
            if player state is stopped then return ""
            set playerStateText to (player state as text)
            set trackName to ""
            set trackArtist to ""
            set trackAlbum to ""
            set trackPosition to 0
            set trackDuration to 0
            try
                set trackName to (name of current track) as text
            end try
            try
                set trackArtist to (artist of current track) as text
            end try
            try
                set trackAlbum to (album of current track) as text
            end try
            try
                set trackDuration to (duration of current track) as real
            end try
            try
                set trackPosition to player position
            end try
            set trackFavorite to ""
            try
                set trackFavorite to (favorited of current track) as text
            end try
            if trackFavorite is "" then
                try
                    set trackFavorite to (loved of current track) as text
                end try
            end if
            return trackName & "\u{1F}" & trackArtist & "\u{1F}" & trackAlbum & "\u{1F}" & trackPosition & "\u{1F}" & trackDuration & "\u{1F}" & playerStateText & "\u{1F}" & trackFavorite
        end tell
        """
        guard let raw = await run(script) else { return nil }
        guard !raw.isEmpty else {
            answeredStopped = true
            return nil
        }

        let parts = raw.components(separatedBy: "\u{1F}")
        guard parts.count >= 6 else { return nil }
        let favorite = parts.count >= 7 ? Self.boolean(parts[6]) : nil

        let rawDuration = Self.number(parts[4])
        let duration = player.durationInMilliseconds ? rawDuration / 1000 : rawDuration

        return NowPlayingInfo(
            title: parts[0],
            artist: parts[1],
            album: parts[2],
            artwork: await artwork(for: player, key: parts[0] + parts[1]),
            elapsed: Self.number(parts[3]),
            duration: duration,
            isPlaying: parts[5].lowercased().contains("playing"),
            source: player.displayName,
            sourceBundleID: player.bundleID,
            isFavorite: favorite,
            canSeek: true
        )
    }

    /// Переключить «избранное» у текущего трека.
    func setFavorite(_ value: Bool, on player: MusicPlayer) {
        guard let scriptName = player.scriptName else { return }
        runner.fire("""
        tell application "\(scriptName)"
            try
                set favorited of current track to \(value)
            on error
                try
                    set loved of current track to \(value)
                end try
            end try
        end tell
        """)
    }

    /// Встать на секунду. У Music и Spotify позиция в секундах — в
    /// миллисекундах у Spotify только длительность.
    func seek(to seconds: TimeInterval, on player: MusicPlayer) {
        guard let scriptName = player.scriptName else { return }
        runner.fire("""
        tell application "\(scriptName)"
            try
                set player position to \(String(format: "%.2f", max(seconds, 0)))
            end try
        end tell
        """)
    }

    func seek(to seconds: TimeInterval) {
        guard let player = current else { return }
        seek(to: seconds, on: player)
    }

    /// Плейлисты медиатеки.
    ///
    /// Альбомов отдельным списком плееры не отдают: их пришлось бы
    /// собирать перебором всей библиотеки, а это секунды ожидания на
    /// каждой большой медиатеке. Плейлисты же читаются одним запросом.
    /// Пустые пропускаем — это, как правило, папки, играть в них нечего.
    func playlists(limit: Int = 40) async -> [MusicPlaylist] {
        guard let player = current, let scriptName = player.scriptName else { return [] }

        let script = """
        tell application "\(scriptName)"
            set rows to ""
            try
                repeat with aPlaylist in (get every user playlist)
                    try
                        set trackCount to (count of tracks of aPlaylist)
                        if trackCount > 0 then
                            set rows to rows & (persistent ID of aPlaylist) & "\u{1E}" & (name of aPlaylist) & "\u{1E}" & trackCount & "\u{1D}"
                        end if
                    end try
                end repeat
            end try
            return rows
        end tell
        """

        guard let raw = await run(script), !raw.isEmpty else { return [] }

        return raw.components(separatedBy: "\u{1D}").prefix(limit).compactMap { row in
            let fields = row.components(separatedBy: "\u{1E}")
            guard fields.count >= 3, !fields[0].isEmpty else { return nil }
            return MusicPlaylist(id: fields[0], name: fields[1], count: Int(fields[2]) ?? 0)
        }
    }

    /// Запустить плейлист. По идентификатору, а не по имени: имена
    /// повторяются, и «играй Любимое» попадало бы в первое попавшееся.
    func play(playlistID: String) {
        guard let player = current, let scriptName = player.scriptName else { return }
        runner.fire("""
        tell application "\(scriptName)"
            try
                play (first playlist whose persistent ID is "\(playlistID)")
            end try
        end tell
        """)
    }

    /// Запустить станцию по ссылке Apple Music.
    ///
    /// `open location` — единственная дверь к станциям: объектами их нет
    /// ни в плейлистах, ни в `radio tuner playlists`. Ссылку Music
    /// открывает у себя, а не в браузере. Станция от ссылки заводится
    /// сама; страница плейлиста — нет, поэтому следом, выждав загрузку,
    /// подталкиваем `play`, но только если плеер так и не тронулся.
    func play(stationURL: String) {
        let escaped = stationURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        guard !escaped.isEmpty else { return }
        runner.fire("""
        tell application "Music"
            try
                activate
                open location "\(escaped)"
                delay 1.5
                if player state is not playing then play
            end try
        end tell
        """)
    }

    /// Станция по текущему треку — пунктом «Песня → Создать станцию».
    ///
    /// Своей команды у этого действия нет, поэтому жмём меню живого
    /// приложения через «Универсальный доступ». Пункт ищем перебором, а
    /// не по номеру: и номер, и название разъезжаются от версии к версии
    /// и от языка к языку. Меню сперва открываем — до этого AX отдаёт
    /// пункты недостроенными и сообщает, что они выключены.
    func startStationFromCurrentTrack() {
        // Меню бывает только у активного приложения, поэтому Music
        // придётся вывести вперёд. Кто стоял впереди до этого —
        // запоминаем и возвращаем: панель открывают из чужого окна, и
        // уехавший фокус читался бы как поломка.
        let previous = NSWorkspace.shared.frontmostApplication
        runner.fire("""
        tell application "Music" to activate
        delay 0.2
        tell application "System Events"
            tell process "Music"
                set opened to false
                set clicked to false
                repeat with barItem in menu bar items of menu bar 1
                    try
                        click barItem
                        set opened to true
                        repeat with item_ in menu items of menu 1 of barItem
                            try
                                set label to name of item_
                                if label is not missing value then
                                    if label is "Создать станцию" or label is "Create Station" then
                                        click item_
                                        set clicked to true
                                        exit repeat
                                    end if
                                end if
                            end try
                        end repeat
                        if clicked then exit repeat
                        key code 53
                        set opened to false
                    end try
                end repeat
                if opened and not clicked then key code 53
            end tell
        end tell
        """)

        guard let previous, previous.bundleIdentifier != "com.apple.Music" else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            previous.activate()
        }
    }

    /// Число из AppleScript приходит в формате системы: на русской
    /// машине это «122,73», и `Double("122,73")` — nil. Из-за этого
    /// длительность падала в ноль, а вместе с ней пропадала полоса
    /// прогресса. Разделитель приводим к точке руками.
    /// `true`/`false` от AppleScript; пустая строка — плеер про избранное
    /// не знает вовсе.
    private static func boolean(_ text: String) -> Bool? {
        switch text.lowercased() {
        case "true": return true
        case "false": return false
        default: return nil
        }
    }

    private static func number(_ text: String) -> Double {
        Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    /// Обложку тянем только при смене трека — запрос тяжёлый.
    private func artwork(for player: MusicPlayer, key: String) async -> Data? {
        if let cached = artworkCache, cached.key == key { return cached.data }

        // У Spotify обложка лежит по ссылке, у Music — бинарём в треке.
        let data: Data?
        switch player.bundleID {
        case "com.spotify.client":
            guard let url = await run("tell application \"Spotify\" to return artwork url of current track"),
                  let remote = URL(string: url) else { return nil }
            data = try? Data(contentsOf: remote)
        case "com.apple.Music":
            let descriptor = await runDescriptor("""
            tell application "Music"
                if (count of artworks of current track) is 0 then return missing value
                return data of artwork 1 of current track
            end tell
            """)
            data = descriptor?.data
        default:
            return nil
        }

        guard let data, !data.isEmpty else { return nil }
        artworkCache = (key, data)
        return data
    }

    // MARK: - Запуск скриптов

    @discardableResult
    private func run(_ source: String) async -> String? {
        await runDescriptor(source)?.stringValue
    }

    private func runDescriptor(_ source: String) async -> NSAppleEventDescriptor? {
        // Скрипт уходит на свою очередь; главный поток при этом свободен,
        // и анимации панели не спотыкаются об ожидание ответа плеера.
        let outcome = await runner.run(source)
        lastErrorCode = outcome.errorCode
        return outcome.descriptor
    }
}
