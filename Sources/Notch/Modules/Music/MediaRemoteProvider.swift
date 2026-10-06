import AppKit

/// Приватный `MediaRemote`: видит любой источник, включая браузеры.
///
/// С macOS 15.4 Apple закрыла его entitlement'ом, и тогда все вызовы
/// возвращают пустоту. Провайдер это переживает — просто отдаёт nil,
/// и координатор уходит к следующему.
///
/// Читать и отправлять — разные права, и это проверено: на macOS 26
/// `MRMediaRemoteGetNowPlayingInfo` отдаёт пустоту, а команда из
/// `MRMediaRemoteSendCommand` доходит и переключает плеер. Поэтому
/// провайдер остаётся целью для команд даже когда данные пришли от
/// другого.
///
/// Чего по ответу вызова знать нельзя — дошло ли до кого-нибудь: он
/// равен `true` и когда сессии Now Playing нет вовсе.
@MainActor
final class MediaRemoteProvider: NowPlayingProvider {
    let name = "MediaRemote"

    private typealias GetInfo = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    private typealias GetPlaying = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
    private typealias SendCommand = @convention(c) (Int32, [String: Any]?) -> Bool

    private let handle: UnsafeMutableRawPointer?
    private var latest: NowPlayingInfo?
    private var isPlaying = false

    /// Коды команд MediaRemote.
    private enum Command: Int32 {
        case togglePlayPause = 2
        case next = 4
        case previous = 5
    }

    init() {
        handle = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
            RTLD_NOW
        )
    }

    /// Запрашивает свежие данные асинхронно и отдаёт последние известные:
    /// колбэчный API не ложится на синхронный `fetch()`.
    func fetch() async -> NowPlayingInfo? {
        refresh()
        return latest
    }

    func send(_ command: TransportCommand) {
        _ = deliver(command)
    }

    /// Та же отправка, но с ответом: удалось ли вообще дозвониться.
    ///
    /// `false` значит «канала нет» — символа не нашлось. Это не обещание,
    /// что плеер послушался: команда уходит владельцу сессии Now Playing,
    /// и если сессии нет, переключать нечего, а вызов всё равно считается
    /// принятым.
    @discardableResult
    func deliver(_ command: TransportCommand) -> Bool {
        guard let handle, let sym = dlsym(handle, "MRMediaRemoteSendCommand") else { return false }
        let call = unsafeBitCast(sym, to: SendCommand.self)
        let code: Command = switch command {
        case .playPause: .togglePlayPause
        case .next: .next
        case .previous: .previous
        }
        return call(code.rawValue, nil)
    }

    private func refresh() {
        guard let handle else { return }

        if let sym = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") {
            let call = unsafeBitCast(sym, to: GetPlaying.self)
            call(DispatchQueue.main) { [weak self] playing in
                MainActor.assumeIsolated { self?.isPlaying = playing }
            }
        }

        guard let sym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") else { return }
        let call = unsafeBitCast(sym, to: GetInfo.self)
        call(DispatchQueue.main) { [weak self] raw in
            MainActor.assumeIsolated { self?.apply(raw) }
        }
    }

    private func apply(_ raw: [String: Any]) {
        guard !raw.isEmpty else {
            latest = nil
            return
        }
        let title = raw["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
        guard !title.isEmpty else {
            latest = nil
            return
        }
        latest = NowPlayingInfo(
            title: title,
            artist: raw["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? "",
            album: raw["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? "",
            artwork: raw["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data,
            elapsed: raw["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? TimeInterval ?? 0,
            duration: raw["kMRMediaRemoteNowPlayingInfoDuration"] as? TimeInterval ?? 0,
            isPlaying: isPlaying,
            source: ""
        )
    }
}
