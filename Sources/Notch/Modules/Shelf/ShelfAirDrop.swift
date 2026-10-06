import AppKit

/// Отправка с полки в AirDrop.
///
/// Окно выбора получателя — обычное окно нашего процесса. А мы — агент без
/// Dock с неактивирующей панелью: само по себе такое окно выезжает позади
/// чужого приложения и фокуса не получает. Поэтому на время отправки
/// приложение активируется, а потом фокус возвращается тому, у кого его
/// взяли.
///
/// Панель на это время держится открытой. Курсор, уехавший к окну AirDrop,
/// иначе её схлопнул бы, а схлопывание прячет и снова показывает окно
/// панели ради возврата фокуса — если система повесила выбор получателя на
/// панель, вместе с ней он бы и пропал.
@MainActor
final class ShelfAirDrop: NSObject, NSSharingServiceDelegate {
    /// Текущая отправка. Сервис держит делегата слабо, а полка, из которой
    /// нажали кнопку, при смене вкладки уходит с экрана — сессию держим мы.
    private static var current: ShelfAirDrop?

    private let service: NSSharingService
    private let urls: [URL]
    /// Ссылки, к которым удалось открыть доступ по закладке, — их и закрываем.
    private var scoped: [URL] = []
    private let previousApp: NSRunningApplication?
    private var resignObserver: NSObjectProtocol?
    /// Держит ли сессия панель открытой — отпускаем ровно один раз.
    private var isHolding = false

    private init(service: NSSharingService, urls: [URL]) {
        self.service = service
        self.urls = urls
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
    }

    /// Можно ли отправить эти файлы: AirDrop выключен, нет Wi-Fi или
    /// Bluetooth — кнопка гаснет, а не открывает пустое окно.
    static func canSend(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return false }
        return service.canPerform(withItems: urls)
    }

    static var isSending: Bool { current != nil }

    /// Значок AirDrop — те же расходящиеся волны, что у системного.
    static let symbol = "dot.radiowaves.up.forward"

    static func send(_ urls: [URL]) {
        guard current == nil, !urls.isEmpty,
              let service = NSSharingService(named: .sendViaAirDrop)
        else { return }
        let session = ShelfAirDrop(service: service, urls: urls)
        session.start()
    }

    private func start() {
        // Без песочницы закладки полки обычные, и доступ открывать не нужно —
        // вызов тогда просто вернёт false. Но если полка когда-нибудь уедет
        // в песочницу, файлы без этого AirDrop не прочтёт.
        scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
        guard service.canPerform(withItems: urls) else {
            finish()
            return
        }
        Self.current = self
        NotchPanel.holdOpen()
        isHolding = true
        service.delegate = self
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: urls)

        // Ушли из окна AirDrop в другое приложение, не отправив и не
        // закрыв его, — панель больше не держим, иначе она так и висела бы
        // открытой.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.releasePanel() }
        }
    }

    private func releasePanel() {
        guard isHolding else { return }
        isHolding = false
        NotchPanel.releaseHold()
    }

    private func finish(restoreFocus: Bool = false) {
        scoped.forEach { $0.stopAccessingSecurityScopedResource() }
        scoped = []
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        guard Self.current === self else { return }
        Self.current = nil
        releasePanel()
        if restoreFocus, NSApp.isActive { previousApp?.activate() }
    }

    // MARK: NSSharingServiceDelegate

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        finish(restoreFocus: true)
    }

    func sharingService(
        _ sharingService: NSSharingService,
        didFailToShareItems items: [Any],
        error: any Error
    ) {
        // Сюда же приходит и «Отменить» в окне выбора.
        finish(restoreFocus: true)
    }

    /// Окно, от которого система разворачивает своё. Панель не отдаём:
    /// она безрамочная, на уровне меню-бара и при схлопывании прячется —
    /// листу на ней не место. Без окна-источника выбор получателя встаёт
    /// отдельным окном по центру экрана.
    func sharingService(
        _ sharingService: NSSharingService,
        sourceWindowForShareItems items: [Any],
        sharingContentScope: UnsafeMutablePointer<NSSharingService.SharingContentScope>
    ) -> NSWindow? {
        nil
    }
}

extension NotchPanel {
    /// Сколько сейчас причин держать панель раскрытой, даже если курсор
    /// ушёл с неё. Пока счётчик больше нуля, уход курсора её не схлопывает.
    @MainActor private(set) static var holds = 0

    @MainActor static var isHeldOpen: Bool { holds > 0 }

    @MainActor static func holdOpen() { holds += 1 }

    @MainActor static func releaseHold() { holds = max(0, holds - 1) }
}
