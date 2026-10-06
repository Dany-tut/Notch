import AppKit

/// Жесты над вырезом: смахнуть вбок — сменить трек, вниз — раскрыть панель,
/// вверх — убрать её или прогнать плашку события.
///
/// Схлопнутая панель не принимает события мыши (иначе клики не доходили бы
/// до меню-бара), поэтому слушаем прокрутку глобально и сами проверяем, что
/// курсор над вырезом. Глобальный монитор только наблюдает — событие идёт
/// дальше своим ходом.
@MainActor
final class GestureMonitor {
    /// Что случилось. Решение, как на это ответить, принимает панель.
    enum Gesture {
        case skipForward
        case skipBackward
        case open
        case close
    }

    private let behaviour: BehaviourSettings
    private let zone: () -> CGRect?
    private let onGesture: (Gesture) -> Void

    private var monitors: [Any] = []
    private var accumulatedX: CGFloat = 0
    private var accumulatedY: CGFloat = 0
    /// Один жест на одно движение: пока палец не оторвали, второй раз не
    /// срабатываем, иначе один свайп пролистывал бы пол-альбома.
    private var isArmed = true

    /// Сколько нужно проехать, чтобы это считалось жестом, а не дрожанием.
    private let threshold: CGFloat = 28

    init(
        behaviour: BehaviourSettings,
        zone: @escaping () -> CGRect?,
        onGesture: @escaping (Gesture) -> Void
    ) {
        self.behaviour = behaviour
        self.zone = zone
        self.onGesture = onGesture
    }

    func start() {
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }
        monitors = [global, local].compactMap { $0 }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor(_:))
        monitors.removeAll()
    }

    private func handle(_ event: NSEvent) {
        guard behaviour.swipeToSkipActive || behaviour.swipeToToggleActive else { return }

        // Палец оторвали — можно ловить следующий жест.
        if event.phase == .ended || event.phase == .cancelled {
            reset()
            return
        }
        if event.phase == .began { reset() }

        guard let zone = zone(), zone.contains(NSEvent.mouseLocation) else {
            reset()
            return
        }
        guard isArmed else { return }

        accumulatedX += event.scrollingDeltaX
        accumulatedY += event.scrollingDeltaY

        if behaviour.swipeToSkipActive, abs(accumulatedX) > threshold,
           abs(accumulatedX) > abs(accumulatedY) {
            // Естественная прокрутка: содержимое едет за пальцем, поэтому
            // смахивание влево (дельта отрицательная) — это «дальше».
            fire(accumulatedX < 0 ? .skipForward : .skipBackward)
            return
        }

        if behaviour.swipeToToggleActive, abs(accumulatedY) > threshold,
           abs(accumulatedY) >= abs(accumulatedX) {
            fire(accumulatedY < 0 ? .open : .close)
        }
    }

    private func fire(_ gesture: Gesture) {
        isArmed = false
        accumulatedX = 0
        accumulatedY = 0
        onGesture(gesture)
    }

    private func reset() {
        isArmed = true
        accumulatedX = 0
        accumulatedY = 0
    }
}
