import AppKit

/// Следит, тащат ли сейчас что-нибудь мышью, и где это «что-нибудь»
/// находится.
///
/// Обычным способом — `registerForDraggedTypes` на окне — здесь не выйдет:
/// схлопнутая панель не принимает события мыши вовсе, чтобы клики уходили
/// в меню-бар под ней. Включить их заранее нельзя, а узнать про
/// перетаскивание, не включив, — не от кого.
///
/// Поэтому спрашиваем систему сами. Нажатие кнопки ловится глобальным
/// монитором, а дальше опрос: у буфера перетаскивания растёт `changeCount`,
/// как только сессия началась, — значит, тащат, а не просто держат кнопку.
/// Отпускание проверяем по `pressedMouseButtons`, а не монитором: во время
/// сессии события забирает она сама, и `mouseUp` до нас не доходит.
@MainActor
final class DragWatcher {
    /// Перетаскивание началось или продолжается: точка — где курсор.
    var onDrag: ((CGPoint) -> Void)?
    /// Кнопку отпустили.
    var onEnd: (() -> Void)?

    private var monitor: Any?
    private var timer: Timer?
    private var baseline: Int = 0
    private var isDragging = false

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDown() }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        finish()
    }

    private func mouseDown() {
        guard timer == nil else { return }
        // Отсчёт ведём от снимка на нажатии: любое изменение после него —
        // и есть начавшаяся сессия.
        baseline = NSPasteboard(name: .drag).changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        // Кнопку отпустили — сессия кончилась, чем бы она ни была.
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            finish()
            return
        }
        if !isDragging {
            guard NSPasteboard(name: .drag).changeCount != baseline else { return }
            isDragging = true
        }
        onDrag?(NSEvent.mouseLocation)
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        guard isDragging else { return }
        isDragging = false
        onEnd?()
    }
}
