import AppKit

/// Следит за тем, не пора ли убрать панель с глаз: полноэкранное приложение
/// или игра.
///
/// Системного уведомления «кто-то ушёл в фуллскрин» нет, поэтому смотрим на
/// окна переднего приложения через `CGWindowList` — списка окон хватает без
/// разрешения на запись экрана, имена окон нам не нужны.
@MainActor
final class PanelVisibility {
    private let behaviour: BehaviourSettings
    /// Вызывается только при смене решения, а не на каждой проверке.
    private let onChange: (Bool) -> Void

    private(set) var shouldHide = false
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    init(behaviour: BehaviourSettings, onChange: @escaping (Bool) -> Void) {
        self.behaviour = behaviour
        self.onChange = onChange
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification
        ] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.evaluate() }
            }
            observers.append(token)
        }

        // Переход в фуллскрин не сопровождается ни активацией приложения, ни
        // сменой Space, поэтому вдобавок редкий опрос.
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        evaluate()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver(_:))
        observers.removeAll()
    }

    /// Пересчитать решение немедленно — например, после смены настройки.
    func evaluate() {
        let hide = computeShouldHide()
        guard hide != shouldHide else { return }
        shouldHide = hide
        onChange(hide)
    }

    private func computeShouldHide() -> Bool {
        guard behaviour.hideInFullscreen || behaviour.hideWhileGaming else { return false }
        guard let front = NSWorkspace.shared.frontmostApplication else { return false }
        // Собственная панель фронтом не считается.
        guard front.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return shouldHide
        }

        if behaviour.hideWhileGaming, isGame(front) { return true }
        if behaviour.hideInFullscreen, isFullscreen(pid: front.processIdentifier) { return true }
        return false
    }

    /// Игра — по категории из `Info.plist` самого приложения.
    private func isGame(_ app: NSRunningApplication) -> Bool {
        guard let url = app.bundleURL,
              let bundle = Bundle(url: url),
              let category = bundle.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
        else { return false }
        // Подкатегории вида public.app-category.action-games тоже игры.
        return category.hasPrefix("public.app-category.") && category.hasSuffix("games")
    }

    /// Окно переднего приложения размером во весь экран и без меню-бара над
    /// ним — значит, фуллскрин.
    private func isFullscreen(pid: pid_t) -> Bool {
        guard let screen = NotchGeometry.screen(for: behaviour) else { return false }
        guard let infos = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return false }

        for info in infos {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  let raw = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: raw as CFDictionary)
            else { continue }

            // Сравниваем только размеры: координаты CGWindow идут от левого
            // верхнего угла главного экрана, а нам важно лишь «во весь экран».
            if bounds.width >= screen.frame.width - 1,
               bounds.height >= screen.frame.height - 1 {
                return true
            }
        }
        return false
    }
}
