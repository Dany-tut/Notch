import AppKit
import IOKit.pwr_mgt

/// Последний рубеж: узнаём хотя бы, какое приложение сейчас издаёт звук.
///
/// Метаданные трека без `MediaRemote` недоступны, но система публикует
/// power-assertion «Playing audio» с pid процесса — это публичный API.
/// Показываем имя и иконку приложения, а управляем медиа-клавишами.
@MainActor
final class AudioActivityProvider: NowPlayingProvider {
    let name = "AudioActivity"

    /// Читать данные этот провайдер умеет сам, а двигать плеер — нет:
    /// для команд нужен канал в сессию Now Playing.
    private let mediaRemote: MediaRemoteProvider

    init(mediaRemote: MediaRemoteProvider) {
        self.mediaRemote = mediaRemote
    }

    /// Системные службы держат такие же ассершены — они нам не источник.
    private static let ignoredBundleIDs: Set<String> = [
        "com.apple.audio.coreaudiod",
        "com.apple.powerd"
    ]

    func fetch() async -> NowPlayingInfo? {
        guard let app = playingApplication() else { return nil }
        return NowPlayingInfo(
            title: "",
            artist: "",
            isPlaying: true,
            source: app.localizedName ?? "",
            sourceBundleID: app.bundleIdentifier
        )
    }

    /// Кто играет — знаем, но говорить с ним умеем только через систему.
    ///
    /// Сначала сессия Now Playing напрямую: её слушают и Electron-плееры,
    /// которым нечего сказать по AppleScript. Клавиша — на случай, когда
    /// канала нет: ей нужен «Универсальный доступ», а сессии — нет.
    func send(_ command: TransportCommand) {
        guard mediaRemote.deliver(command) else {
            MediaKeys.send(command)
            return
        }
    }

    /// Издаёт ли звук конкретный процесс — так понимаем, играет ли
    /// выбранный вручную плеер, который метаданных не отдаёт.
    func isPlayingAudio(pid: pid_t) -> Bool {
        audioPIDs().contains(pid)
    }

    private func playingApplication() -> NSRunningApplication? {
        for pid in audioPIDs() {
            guard let app = NSRunningApplication(processIdentifier: pid),
                  let bundleID = app.bundleIdentifier,
                  bundleID != Bundle.main.bundleIdentifier,
                  !Self.ignoredBundleIDs.contains(bundleID)
            else { continue }
            return app
        }
        return nil
    }

    private func audioPIDs() -> Set<pid_t> {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
              let byProcess = unmanaged?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
        else { return [] }

        var pids: Set<pid_t> = []
        for (pidNumber, assertions) in byProcess {
            let holdsAudio = assertions.contains { assertion in
                let title = (assertion["AssertName"] as? String) ?? ""
                return title.range(of: "playing audio", options: .caseInsensitive) != nil
            }
            if holdsAudio { pids.insert(pid_t(truncating: pidNumber)) }
        }
        return pids
    }
}
