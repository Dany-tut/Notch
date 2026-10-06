import AppKit

/// Now Playing любого источника — браузера, Electron-плеера, чего угодно —
/// через системный perl.
///
/// Нашему процессу `MediaRemote` данных не отдаёт (закрыт entitlement'ом
/// с macOS 15.4), а `/usr/bin/perl` подписан как `com.apple.perl5` и
/// проходит. Скрипт из `Vendor/MediaRemoteAdapter` грузит в perl наш
/// framework, подписывается на уведомления MediaRemote и печатает каждое
/// изменение строкой JSON. Мы держим этот поток открытым и складываем
/// последнее состояние в память — `fetch()` ничего не спрашивает, а
/// только читает его. Опроса нет: пока ничего не меняется, perl спит.
///
/// Если в бандле нет скрипта (запуск из `swift run`) или perl упал слишком
/// много раз подряд, провайдер молча отдаёт nil — координатор идёт дальше.
@MainActor
final class MediaRemoteAdapterProvider: NowPlayingProvider {
    let name = "MediaRemote Adapter"

    private var process: Process?
    private var buffer = Data()
    /// Последнее состояние целиком: поток шлёт разницу, и собирать её надо
    /// поверх того, что уже было.
    private var state: [String: Any] = [:]
    /// Когда пришло последнее состояние — от него досчитываем позицию.
    private var receivedAt = Date()
    /// Декодированная обложка и то, из какой строки она получена: base64
    /// приходит в каждом полном снимке, а раскладывать картинку заново на
    /// каждую паузу незачем.
    private var artwork: (raw: String, data: Data)?
    private var restarts = 0
    private static let maxRestarts = 5

    private let script: URL?
    private let framework: URL?

    init(bundle: Bundle = .main) {
        script = bundle.url(forResource: "mediaremote-adapter", withExtension: "pl")
        framework = bundle.privateFrameworksURL
            .map { $0.appendingPathComponent("MediaRemoteAdapter.framework") }
            .flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
        // perl — отдельный процесс и сам с нами не умирает: пока в потоке
        // тихо, он не узнает, что читать его некому.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    var isAvailable: Bool { script != nil && framework != nil }

    func start() {
        guard process == nil, isAvailable, restarts <= Self.maxRestarts else { return }
        killOrphans()
        let task = makeProcess(["stream", "--debounce=150"])
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            Task { @MainActor in self?.consume(chunk) }
        }
        task.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.restartLater() }
        }
        do {
            try task.run()
            process = task
        } catch {
            restarts = Self.maxRestarts + 1
        }
    }

    func stop() {
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
    }

    /// Поток от прошлого запуска, который убили без `willTerminate`
    /// (`kill`, падение, пересборка). Сам он умрёт только на следующей
    /// смене трека — от записи в закрытую трубу, — а до тех пор висит
    /// сиротой. Узнаём его по родителю `launchd` и нашему скрипту.
    private func killOrphans() {
        guard let script else { return }
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-axo", "pid=,ppid=,command="]
        let pipe = Pipe()
        ps.standardOutput = pipe
        guard (try? ps.run()) != nil else { return }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        ps.waitUntilExit()
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            // Строго наш запуск: perl с нашим скриптом первым аргументом.
            // Иначе под раздачу попадёт, например, чей-то `grep` по имени
            // скрипта.
            guard fields.count == 3, fields[1] == "1",
                  fields[2].hasPrefix("/usr/bin/perl \(script.path) "),
                  let pid = pid_t(fields[0])
            else { continue }
            kill(pid, SIGTERM)
        }
    }

    /// perl упал — поднимаем снова, но не бесконечно: если адаптер на этой
    /// системе не работает вовсе, крутить его в цикле значит жечь батарею.
    private func restartLater() {
        process = nil
        state = [:]
        restarts += 1
        guard restarts <= Self.maxRestarts else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2 * Double(self?.restarts ?? 1)))
            self?.start()
        }
    }

    private func consume(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            apply(line: Data(line))
        }
    }

    private func apply(line: Data) {
        guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              message["type"] as? String == "data",
              let payload = message["payload"] as? [String: Any]
        else { return }
        // Раз поток ожил — значит адаптер работает, и прошлые падения
        // можно простить.
        restarts = 0
        if message["diff"] as? Bool == true {
            for (key, value) in payload {
                if value is NSNull { state.removeValue(forKey: key) } else { state[key] = value }
            }
        } else {
            state = payload
        }
        receivedAt = Date()
    }

    func fetch() async -> NowPlayingInfo? {
        guard let title = state["title"] as? String, !title.isEmpty else { return nil }
        let bundleID = state["bundleIdentifier"] as? String
        let playing = state["playing"] as? Bool ?? false
        let duration = state["duration"] as? Double ?? 0
        return NowPlayingInfo(
            title: title,
            artist: state["artist"] as? String ?? "",
            album: state["album"] as? String ?? "",
            artwork: decodedArtwork(),
            elapsed: elapsed(playing: playing, duration: duration),
            duration: duration,
            isPlaying: playing,
            source: bundleID.flatMap(Self.appName(for:)) ?? "",
            sourceBundleID: bundleID,
            canSeek: duration > 0
        )
    }

    /// Позиция приходит снимком на момент `timestamp`, а поток молчит, пока
    /// ничего не меняется. Поэтому досчитываем сами: сколько прошло с
    /// момента снимка, умноженное на скорость.
    private func elapsed(playing: Bool, duration: Double) -> Double {
        let base = state["elapsedTime"] as? Double ?? 0
        guard playing else { return base }
        let rate = state["playbackRate"] as? Double ?? 1
        let stamp = (state["timestamp"] as? String).flatMap(Self.parseDate) ?? receivedAt
        let value = base + Date().timeIntervalSince(stamp) * rate
        return duration > 0 ? min(max(value, 0), duration) : max(value, 0)
    }

    private func decodedArtwork() -> Data? {
        guard let raw = state["artworkData"] as? String, !raw.isEmpty else { return nil }
        if let artwork, artwork.raw == raw { return artwork.data }
        guard let data = Data(base64Encoded: raw) else { return nil }
        artwork = (raw, data)
        return data
    }

    /// Какой плеер сейчас в сессии — даже если он стоит на паузе.
    var currentBundleID: String? {
        guard let title = state["title"] as? String, !title.isEmpty else { return nil }
        return state["bundleIdentifier"] as? String
    }

    // MARK: - Команды

    /// Коды `MRCommand`: 2 — play/pause, 4 — следующий, 5 — предыдущий.
    func send(_ command: TransportCommand) {
        let code = switch command {
        case .playPause: "2"
        case .next: "4"
        case .previous: "5"
        }
        runOnce(["send", code])
    }

    /// Адаптер ждёт позицию в микросекундах.
    func seek(to seconds: TimeInterval) {
        runOnce(["seek", String(Int64(seconds * 1_000_000))])
        state["elapsedTime"] = seconds
        state["timestamp"] = nil
        receivedAt = Date()
    }

    private func runOnce(_ arguments: [String]) {
        guard isAvailable else { return }
        let task = makeProcess(arguments)
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
    }

    private func makeProcess(_ arguments: [String]) -> Process {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        task.arguments = [script?.path ?? "", framework?.path ?? ""] + arguments
        return task
    }

    // MARK: - Разное

    private static func appName(for bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }

    private static func parseDate(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }
}
