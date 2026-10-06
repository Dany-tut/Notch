import SwiftUI

/// Опрашивает провайдеров по очереди и отдаёт первое, что ответило.
///
/// Порядок неслучаен: `MediaRemote` видит любой источник, поэтому идёт
/// первым; AppleScript — запасной путь на случай закрытого доступа.
/// Если источник выбран руками, очередь не нужна: спрашиваем и двигаем
/// только его.
@MainActor
final class NowPlayingCoordinator: ObservableObject {
    @Published private(set) var info: NowPlayingInfo?
    /// Какой провайдер ответил последним — видно в «О программе».
    @Published private(set) var activeProvider: String = "—"

    /// Чем управляют кнопки. Выбор живёт между запусками.
    @Published var source: MusicSource {
        didSet {
            guard source != oldValue else { return }
            defaults.set(source.storageValue, forKey: Keys.source)
            appleScript.target = source.bundleID
            poll()
        }
    }

    /// Выбранный плеер не запущен — панель предложит его открыть.
    @Published private(set) var selectedIsRunning = false

    /// Плейлисты медиатеки. Читаем по первому открытию вкладки, а не на
    /// каждом опросе: список меняется раз в месяц, а запрос — перебор
    /// плейлистов.
    @Published private(set) var playlists: [MusicPlaylist] = []

    /// Полка раскрыта. Живёт только в памяти: состояние панели, а не
    /// настройка.
    @Published var isShelfOpen = false

    /// Скриптуемый плеер запущен, но система не пускает нас к нему:
    /// без Автоматизации трек и обложка не читаются ничем.
    @Published private(set) var needsAutomation = false

    /// Пересчитываем на каждом опросе: разрешение могут выдать в любой
    /// момент, а без перечитывания предупреждение висит до перезапуска.
    @Published private(set) var isTrusted = MediaKeys.isTrusted

    private enum Keys {
        static let source = "music.source"
        static let lastTrack = "music.lastTrack"
    }

    private let defaults: UserDefaults
    private let appleScript = AppleScriptProvider()
    /// Один на всех: через него уходят команды и от выбранного плеера, и
    /// из автоматического режима, поэтому держим его отдельным полем, а
    /// не выуживаем из очереди провайдеров.
    private let mediaRemote = MediaRemoteProvider()
    /// Тот же MediaRemote, но через системный perl — ему данные отдают.
    /// Держит поток открытым сам, поэтому живёт отдельным полем: его
    /// запускают и спрашивают не так, как остальных.
    private let adapter = MediaRemoteAdapterProvider()
    private let audio: AudioActivityProvider
    /// Плееры, которые читаются через дерево «Универсального доступа».
    /// Один на всех: кто именно читается, задаётся его `target`.
    private let accessibility: AccessibilityProvider
    private let providers: [any NowPlayingProvider]
    private var timer: Timer?
    /// Опрос идёт в задаче, и тик таймера может прийти, пока прошлый ещё
    /// не ответил. Тогда его просто пропускаем: очередь из запросов к
    /// плееру не нужна никому.
    private var pollTask: Task<Void, Never>?
    private let interval: TimeInterval = 1.5

    /// Настройки нужны ради станций: их список — не свойство плеера, а
    /// то, что пользователь принёс ссылками, и полка без него не знает,
    /// есть ли ей что показать.
    private let settings: AppSettings

    init(settings: AppSettings, defaults: UserDefaults = .standard) {
        self.settings = settings
        self.defaults = defaults
        let stored = defaults.string(forKey: Keys.source) ?? "auto"
        self.source = MusicSource(storageValue: stored)
        self.audio = AudioActivityProvider(mediaRemote: mediaRemote)
        self.accessibility = AccessibilityProvider(audio: audio)
        // Дерево доступа спрашиваем раньше, чем ассершен «playing audio»:
        // тот знает только, что звук идёт, а это — что именно играет.
        // Адаптер — после плееров, которых мы читаем сами: у тех есть
        // избранное, плейлисты и адресные команды. Но раньше ассершена
        // «playing audio»: тот знает только имя приложения.
        providers = [mediaRemote, appleScript, accessibility, adapter, audio]
        appleScript.target = source.bundleID
        // Плеер после перезапуска системы стоит, а панель уже должна знать,
        // что возобновлять: иначе первое нажатие play опять будет вслепую.
        if let stored = defaults.string(forKey: Keys.lastTrack) {
            let parts = stored.components(separatedBy: "\u{1F}")
            if parts.count == 2, !parts[0].isEmpty {
                appleScript.resumeTarget = (title: parts[0], artist: parts[1])
            }
        }
    }

    func start() {
        guard timer == nil else { return }
        adapter.start()
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    /// Плеер, выбранный руками, — nil в автоматическом режиме.
    var selectedPlayer: MusicPlayer? {
        source.bundleID.flatMap(MusicPlayer.player(for:))
    }

    func send(_ command: TransportCommand) {
        // Нажали — дерево поменялось: следующий опрос читает его заново.
        lastTree = nil
        // Иконка переключается под пальцем, не дожидаясь источника.
        if case .playPause = command, let playing = info?.isPlaying {
            info?.isPlaying = !playing
            holdPlayback(!playing)
        }
        if let player = selectedPlayer {
            send(command, to: player)
        } else if let player = scriptablePlayerOfCurrentSource {
            // Источник известен по имени и умеет разговаривать — обращаемся
            // к нему напрямую. Медиа-клавиша тут не годится: её ловит
            // владелец сессии Now Playing, а у молчащего плеера её нет.
            send(command, to: player)
        } else if let provider = providers.first(where: { $0.name == activeProvider }) {
            // Команду шлём тому, кто сейчас отвечает за данные.
            provider.send(command)
        } else if case .playPause = command,
                  let player = MusicPlayer.scriptable.first(where: { $0.isRunning }) {
            // Не играет ничего и клавишу поймать некому — но рядом открыт
            // плеер, которому можно сказать словами.
            send(command, to: player)
        } else {
            // Не ответил никто — медиа-клавишами: их поймает владелец
            // сессии Now Playing.
            MediaKeys.send(command)
        }
        // Состояние меняется не мгновенно — даём источнику успеть.
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            poll()
        }
    }

    /// Плеер, который сейчас показан в панели, если с ним можно говорить
    /// по AppleScript.
    private var scriptablePlayerOfCurrentSource: MusicPlayer? {
        guard let bundleID = info?.sourceBundleID,
              let player = MusicPlayer.player(for: bundleID),
              player.scriptName != nil,
              player.isRunning
        else { return nil }
        return player
    }

    /// Нужно ли просить «Универсальный доступ»: без него медиа-клавиши
    /// не дойдут. Скриптуемому плееру они не нужны — там и не просим.
    var needsAccessibility: Bool {
        !isTrusted && !controlsBySript
    }

    /// Звёздочка: у плеера есть избранное и трек читается. Иначе кнопку
    /// не показываем — нажимать её было бы некуда.
    var canFavorite: Bool { info?.isFavorite != nil }

    func toggleFavorite() {
        guard let info, let value = info.isFavorite,
              let bundleID = info.sourceBundleID,
              let player = MusicPlayer.player(for: bundleID)
        else { return }
        // Отмечаем сразу: ответ плеера придёт через опрос, а звёздочка
        // должна загораться под пальцем, а не через полторы секунды.
        self.info?.isFavorite = !value
        lastTree = nil
        if player.usesAccessibility {
            accessibility.toggleLike()
        } else {
            appleScript.setFavorite(!value, on: player)
        }
    }

    /// Дизлайк: у плееров, которые читаются деревом, он живёт рядом с
    /// лайком и означает «больше это не ставить». Остальные про такое не
    /// знают — там кнопки нет.
    var canDislike: Bool { accessibility.isDisliked != nil && isCurrentSourceAccessible }

    var isDisliked: Bool { accessibility.isDisliked ?? false }

    func toggleDislike() {
        guard canDislike else { return }
        lastTree = nil
        accessibility.toggleDislike()
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            poll()
        }
    }

    /// Панель показывает сейчас тот самый плеер, чьё дерево мы читаем.
    private var isCurrentSourceAccessible: Bool {
        guard let bundleID = info?.sourceBundleID else { return false }
        return accessibility.target?.bundleID == bundleID
    }

    /// Перемотка. Позицию показываем свою до тех пор, пока плеер не
    /// догонит: опрос идёт раз в полторы секунды, и без этого полоса
    /// отскакивает назад сразу после того, как её отпустили.
    func seek(to seconds: TimeInterval) {
        guard let info, info.canSeek, info.duration > 0 else { return }
        let target = min(max(seconds, 0), info.duration)
        self.info?.elapsed = target
        holdPosition(target)

        // Системная сессия про этот же плеер — перематываем через неё.
        // Ползунок в дереве доступа у Electron пишется, но пока окно не на
        // экране, страница новое значение не подхватывает: полоса в дереве
        // встаёт куда надо, а звук идёт дальше с прежнего места.
        //
        // Electron-плеер перематываем сессией, даже если поток адаптера
        // сейчас про него молчит: на смене трека название в потоке на миг
        // пустеет. Яндекс 5.104 запись в ползунок не слушает вовсе, так
        // что запасной путь через дерево вёл в пустоту — и полоса «не
        // двигалась», хотя жест доходил.
        if activeProvider == adapter.name
            || (adapter.currentBundleID != nil && adapter.currentBundleID == info.sourceBundleID)
            || (isCurrentSourceAccessible && adapter.isAvailable) {
            adapter.seek(to: target)
        } else if isCurrentSourceAccessible {
            accessibility.seek(to: target)
        } else if let bundleID = info.sourceBundleID, let player = MusicPlayer.player(for: bundleID) {
            appleScript.seek(to: target, on: player)
        } else {
            appleScript.seek(to: target)
        }

        Task {
            try? await Task.sleep(for: .milliseconds(350))
            poll()
        }
    }

    /// До какого момента верить своей позиции, а не ответу плеера, и
    /// какой именно она была. Секунды с небольшим хватает: за это время
    /// плеер успевает переставить головку и ответить уже новым числом.
    private var heldPosition: (value: TimeInterval, until: Date)?

    private func holdPosition(_ value: TimeInterval) {
        heldPosition = (value, Date().addingTimeInterval(1.2))
    }

    /// Играет или стоит — по нашей версии, и до какого момента ей верить.
    private var heldPlayback: (value: Bool, until: Date)?

    /// Три секунды: столько система держит ассершен «playing audio» после
    /// того, как плеер уже встал. Меньше — иконка успевает мигнуть назад.
    private func holdPlayback(_ value: Bool) {
        heldPlayback = (value, Date().addingTimeInterval(3))
    }

    func toggleShelf() {
        isShelfOpen.toggle()
        guard isShelfOpen else { return }
        refreshPlaylists()
    }

    /// Плейлисты есть только у того, с кем мы разговариваем словами:
    /// Spotify своей библиотеки наружу не отдаёт вовсе.
    var canBrowsePlaylists: Bool {
        guard let bundleID = info?.sourceBundleID ?? selectedPlayer?.bundleID else {
            return MusicPlayer.scriptable.contains { $0.isRunning }
        }
        return MusicPlayer.player(for: bundleID)?.scriptName != nil
    }

    func play(_ playlist: MusicPlaylist) {
        appleScript.play(playlistID: playlist.id)
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            poll()
        }
    }

    /// Запустить станцию по ссылке. Ссылку понимает только Music, и
    /// открываем её именно в нём — независимо от того, кто играет сейчас.
    func play(_ station: MusicStation) {
        guard station.isPlayable else { return }
        appleScript.play(stationURL: station.url)
        Task {
            try? await Task.sleep(for: .seconds(2))
            poll()
        }
    }

    /// Станция по тому, что играет сейчас. Жмём пункт меню живого Music,
    /// поэтому нужен «Универсальный доступ» — без него молча ничего не
    /// произойдёт, и предлагать такую кнопку нечестно.
    var canStartStation: Bool {
        isTrusted && MusicPlayer.player(for: "com.apple.Music")?.isRunning == true
    }

    /// Полке есть что показать: плейлисты, станции или хотя бы кнопка
    /// «станция по этой песне». Нет — не показываем и кнопку полки.
    var hasShelfContent: Bool {
        canBrowsePlaylists || canStartStation || settings.musicStations.contains(where: \.isPlayable)
    }

    func startStationFromCurrentTrack() {
        guard canStartStation else { return }
        appleScript.startStationFromCurrentTrack()
        Task {
            try? await Task.sleep(for: .seconds(2))
            poll()
        }
    }

    private func refreshPlaylists() {
        Task { playlists = await appleScript.playlists() }
    }

    func requestAccessibility() {
        MediaKeys.requestTrust()
    }

    /// Путь к бандлу — его показываем в подсказке, чтобы в списке
    /// «Универсального доступа» искали не по имени, а по файлу.
    var accessibilityBundlePath: String { MediaKeys.bundleURL.path }

    func revealAccessibilityBundle() {
        MediaKeys.revealBundle()
    }

    func resetAccessibility() {
        MediaKeys.resetTrust()
    }

    /// Отдельный список — «Автоматизация», не «Универсальный доступ»:
    /// галочку напротив Notch пользователь ставит там.
    func openAutomationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Выбранный плеер слушается AppleScript — значит, обходимся без
    /// синтеза клавиш и без разрешений.
    private var controlsBySript: Bool {
        selectedPlayer?.scriptName != nil
    }

    private func send(_ command: TransportCommand, to player: MusicPlayer) {
        guard let app = player.runningApp else {
            // Плеер закрыт: «play» читаем как просьбу его открыть.
            if case .playPause = command { player.launch() }
            return
        }
        if player.scriptName != nil {
            appleScript.send(command, to: player)
        } else if player.usesAccessibility, accessibility.target?.bundleID == player.bundleID {
            // Нажимаем его же кнопку в его же окне. Чужой сессии Now
            // Playing тут не нужно — промахнуться некуда.
            accessibility.send(command)
        } else {
            sendWithoutScript(command, to: app)
        }
    }

    /// Плеер, с которым нельзя поговорить словами: Electron-приложения
    /// вроде Яндекс Музыки.
    ///
    /// Такой плеер регистрируется в `MPRemoteCommandCenter` и ждёт
    /// команду от системной сессии Now Playing. Поэтому сначала идём в
    /// сессию через `MediaRemote`, а когда канала нет — шлём обычную
    /// медиа-клавишу: её система отдаёт владельцу сессии, то есть ему же.
    ///
    /// Адресную клавишу тут не шлём вовсе: `postToPid` кладёт событие в
    /// очередь процесса, а из своей очереди такой плеер медиа-клавиш не
    /// читает — уходило бы в пустоту.
    private func sendWithoutScript(_ command: TransportCommand, to app: NSRunningApplication) {
        guard mediaRemote.deliver(command) else {
            MediaKeys.send(command)
            return
        }
    }

    private func poll() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            await self?.performPoll()
            self?.pollTask = nil
        }
    }

    /// Трек-заглушка для проверки вёрстки. Поля берём из
    /// `NOTCH_FAKE_NOWPLAYING` — «Название|Исполнитель|Альбом», любое
    /// поле можно опустить, тогда встанет образец. Обложку кладём
    /// файлом в `NOTCH_FAKE_ARTWORK`: без неё панель рисует иконку
    /// приложения, а цветного свечения из-под обложки не возникает
    /// вовсе — проверять его на заглушке было нечем.
    private static func fakeInfo() -> NowPlayingInfo {
        let env = ProcessInfo.processInfo.environment
        // «1» — это «включи заглушку», а не название трека.
        let raw = env["NOTCH_FAKE_NOWPLAYING"] ?? ""
        let fields = (raw == "1" ? "" : raw)
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        func field(_ index: Int, or fallback: String) -> String {
            guard index < fields.count, !fields[index].isEmpty else { return fallback }
            return fields[index]
        }

        let artwork = env["NOTCH_FAKE_ARTWORK"]
            .flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) }

        return NowPlayingInfo(
            title: field(0, or: "Мотылёк"),
            artist: field(1, or: "M'Dee"),
            album: field(2, or: "Гороскоп FM"),
            artwork: artwork,
            elapsed: 12,
            duration: 193,
            isPlaying: true,
            source: "Music",
            // Заглушка знает про избранное: иначе звёздочки в панели нет,
            // и на снимке не видно, как транспорт стоит с ней рядом.
            isFavorite: false,
            canSeek: true
        )
    }

    private func performPoll() async {
        isTrusted = MediaKeys.isTrusted
        // Чьё дерево читать. В автоматическом режиме — первый запущенный:
        // выбора нет, а спрашивать сразу всех незачем.
        accessibility.target = selectedPlayer?.usesAccessibility == true
            ? selectedPlayer
            : MusicPlayer.accessible.first { $0.isRunning }

        // Проверка вёрстки плеера, когда играть нечему.
        if ProcessInfo.processInfo.environment["NOTCH_FAKE_NOWPLAYING"] != nil {
            info = Self.fakeInfo()
            activeProvider = "Заглушка"
            selectedIsRunning = true
        } else if let player = selectedPlayer {
            await poll(player)
        } else {
            await pollAll()
        }

        applyHeldPosition()
        applyHeldPlayback()
        rememberTrack()
        updateAutomationWarning()
        // Показывать стало нечего — закрываем полку сами: кнопки,
        // которой её закрыть, на панели уже нет.
        if isShelfOpen, !hasShelfContent {
            withAnimation(NotchTheme.expandAnimation) { isShelfOpen = false }
        }
    }

    /// Пока держим свою позицию — подменяем ею то, что ответил плеер.
    /// Если плеер уже ответил числом около нашего, отпускаем: дальше он
    /// считает сам.
    private func applyHeldPosition() {
        guard let held = heldPosition, info != nil else { return }
        guard Date() < held.until else {
            heldPosition = nil
            return
        }
        if abs((info?.elapsed ?? 0) - held.value) < 2 {
            heldPosition = nil
            return
        }
        info?.elapsed = held.value
    }

    /// То же, что с позицией, но для «играет»: держим свой ответ, пока
    /// источник не согласится. Источник тут — системный ассершен «playing
    /// audio», а его снимают не в момент паузы, а через пару секунд после.
    ///
    /// Согласился — отпускаем сразу, не дожидаясь конца срока: дальше он
    /// знает лучше нас. Не согласился за три секунды — значит команда не
    /// дошла, и врать о ней панель больше не должна.
    private func applyHeldPlayback() {
        guard let held = heldPlayback, info != nil else { return }
        guard Date() < held.until else {
            heldPlayback = nil
            return
        }
        if info?.isPlaying == held.value {
            heldPlayback = nil
            return
        }
        info?.isPlaying = held.value
    }

    /// Дерево доступа Electron-плеера — самый дорогой вопрос в опросе:
    /// сотни обращений к чужому процессу, и платит за них не только Notch,
    /// но и сам плеер. Когда трек и позицию и так отдаёт системная сессия,
    /// от дерева нужен только лайк — его хватает спрашивать раз в шесть
    /// секунд, а не на каждом тике.
    private var lastTree: (info: NowPlayingInfo?, at: Date, bundleID: String?)?
    private static let treeInterval: TimeInterval = 6

    private func fetchTree(session: NowPlayingInfo?) async -> NowPlayingInfo? {
        let target = accessibility.target?.bundleID
        let covered = session?.sourceBundleID != nil && session?.sourceBundleID == target
        if covered, let lastTree, lastTree.bundleID == target,
           Date().timeIntervalSince(lastTree.at) < Self.treeInterval {
            return lastTree.info
        }
        let found = await accessibility.fetch()
        lastTree = (found, Date(), target)
        return found
    }

    private func pollAll() async {
        selectedIsRunning = false
        let fromAdapter = await adapter.fetch()
        // Играет то, с чем мы сами не разговариваем, — браузер, чужой
        // плеер. Тогда адаптер главный: иначе на паузе стоящий Music или
        // Яндекс перебьют вкладку, из которой реально идёт звук.
        if let fromAdapter, fromAdapter.isPlaying,
           fromAdapter.sourceBundleID.flatMap(MusicPlayer.player(for:)) == nil {
            info = fromAdapter
            activeProvider = adapter.name
            return
        }
        for provider in providers {
            let fetched = provider.name == accessibility.name
                ? await fetchTree(session: fromAdapter)
                : await provider.fetch()
            guard let found = fetched else { continue }
            // Music держит ассершен «playing audio», даже когда просто
            // открыт. Если он только что сам сказал «стою», не верим звуку.
            if provider.name == audio.name, deniesAudioClaim(found) { continue }
            info = enrich(found, with: fromAdapter)
            activeProvider = provider.name
            return
        }
        info = nil
        activeProvider = "—"
    }

    /// Свой провайдер плеера знает про избранное и умеет адресные команды,
    /// а системная сессия — точнее про сам трек: дерево доступа у Electron
    /// замирает, пока окно не на экране, и полчаса показывает старое
    /// название. Поэтому трек и позицию берём у сессии, если она про тот
    /// же плеер, а остальное — у своего провайдера.
    private func enrich(_ found: NowPlayingInfo, with session: NowPlayingInfo?) -> NowPlayingInfo {
        guard let session, let bundleID = found.sourceBundleID,
              session.sourceBundleID == bundleID
        else { return found }
        var merged = found
        merged.title = session.title
        merged.artist = session.artist
        if !session.album.isEmpty { merged.album = session.album }
        if session.duration > 0 {
            merged.duration = session.duration
            merged.elapsed = session.elapsed
        }
        merged.isPlaying = session.isPlaying
        // Обложку своего провайдера не трогаем, если трек тот же: у Music
        // она крупнее. Трек сменился — своя обложка уже чужая.
        if session.artwork != nil, found.title != session.title || found.artwork == nil {
            merged.artwork = session.artwork
        }
        return merged
    }

    /// Трек, который панель видела последним, — им же play и заводит
    /// остановленный плеер. Пустую заглушку не запоминаем: в ней нет
    /// названия, а искать в медиатеке нечего.
    private func rememberTrack() {
        guard let info, !info.title.isEmpty else { return }
        guard appleScript.resumeTarget?.title != info.title
                || appleScript.resumeTarget?.artist != info.artist
        else { return }
        appleScript.resumeTarget = (title: info.title, artist: info.artist)
        defaults.set("\(info.title)\u{1F}\(info.artist)", forKey: Keys.lastTrack)
    }

    /// Звук приписан плееру, который умеет говорить и только что сказал,
    /// что стоит. Верить тут надо плееру.
    private func deniesAudioClaim(_ found: NowPlayingInfo) -> Bool {
        guard appleScript.answeredStopped, let bundleID = found.sourceBundleID else { return false }
        return MusicPlayer.player(for: bundleID)?.scriptName != nil
    }

    /// Запрет виден только тогда, когда спрашивать есть кого: если ни
    /// один скриптуемый плеер не запущен, предупреждать не о чем.
    private func updateAutomationWarning() {
        let scriptablePlayerRunning = MusicPlayer.scriptable.contains { $0.isRunning }
        needsAutomation = scriptablePlayerRunning && appleScript.isDenied
    }

    /// Опрос прибитого плеера. Скриптуемого читаем целиком, остальному
    /// показываем хотя бы иконку и то, идёт ли из него звук.
    private func poll(_ player: MusicPlayer) async {
        guard let app = player.runningApp else {
            selectedIsRunning = false
            info = nil
            activeProvider = "—"
            return
        }
        selectedIsRunning = true

        let fromAdapter = await adapter.fetch()
        if player.usesAccessibility, let found = await fetchTree(session: fromAdapter) {
            info = enrich(found, with: fromAdapter)
            activeProvider = accessibility.name
            return
        }

        if player.scriptName != nil {
            if let found = await appleScript.fetch() {
                info = enrich(found, with: fromAdapter)
                activeProvider = appleScript.name
                return
            }
            // Плеер ответил «стою» — это ответ, а не молчание. Показывать
            // «играет, названия не даёт» тут было враньём: панель говорила
            // «Playing» над остановленным плеером.
            if appleScript.answeredStopped {
                info = nil
                activeProvider = appleScript.name
                return
            }
        }

        // Сам плеер ничего не сказал, но системная сессия про него знает.
        if let fromAdapter, fromAdapter.sourceBundleID == player.bundleID {
            info = fromAdapter
            activeProvider = adapter.name
            return
        }

        info = NowPlayingInfo(
            title: "",
            artist: "",
            isPlaying: audio.isPlayingAudio(pid: app.processIdentifier),
            source: player.displayName,
            sourceBundleID: player.bundleID
        )
        activeProvider = player.scriptName != nil ? appleScript.name : audio.name
    }
}
