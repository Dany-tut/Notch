import SwiftUI

/// Кто сейчас говорит от имени выреза.
///
/// Одна активность на экране: очередь не копим, более важная перебивает
/// менее важную, равная по важности — заменяет и продлевает показ. Так
/// плашка не превращается в ленту уведомлений.
@MainActor
final class ActivityCenter: ObservableObject {
    @Published private(set) var current: NotchActivity?

    private let settings: AppSettings
    private var timer: Timer?

    init(settings: AppSettings) {
        self.settings = settings
    }

    /// Показать событие. Выключенные в настройках виды молча отбрасываем —
    /// проверять это в каждом источнике было бы лишней работой.
    func show(_ activity: NotchActivity) {
        guard settings.isActivityEnabled(activity.kind) else { return }

        if let current, current.kind != activity.kind,
           current.kind.priority > activity.kind.priority {
            return
        }


        self.current = activity
        scheduleDismissal(after: activity.duration)
    }

    /// Обновить показанное, не начиная показ заново: прогресс зарядки или
    /// позиция в треке меняются часто, а плашка должна оставаться той же.
    func update(_ activity: NotchActivity) {
        guard let current, current.isSameSubject(as: activity) else { return }
        // Тот же разговор — значит и плашка та же: личность переносим со
        // старой, меняются только её значения.
        var next = activity
        next.id = current.id
        self.current = next
    }

    /// Та же плашка с новыми цифрами: обратный отсчёт до встречи меняет
    /// приписку, и `update` по ней уже не узнаёт своё. Узнаём по виду и
    /// названию; срок показа не трогаем.
    ///
    /// `extend` — продлить показ на срок новой: громкость держат клавишей,
    /// и плашка должна висеть, пока её двигают.
    func refresh(_ activity: NotchActivity, extend: Bool = false) {
        guard let current, current.kind == activity.kind,
              extend || current.title == activity.title
        else { return }
        var next = activity
        next.id = current.id
        self.current = next
        if extend { scheduleDismissal(after: activity.duration) }
    }

    /// Какие плашки пользователь убрал сам, нажав на них. Долгая плашка
    /// (встреча) возвращается, если её перебила короткая, — но не после
    /// того, как по ней уже перешли.
    private(set) var dismissedByUser: Set<NotchActivity.Kind> = []

    func dismissByUser(_ kind: NotchActivity.Kind) {
        dismissedByUser.insert(kind)
        dismiss(kind: kind)
    }

    func forgetUserDismissal(_ kind: NotchActivity.Kind) {
        dismissedByUser.remove(kind)
    }

    func dismiss(kind: NotchActivity.Kind? = nil) {
        if let kind, current?.kind != kind { return }
        timer?.invalidate()
        timer = nil
        current = nil
    }

    private func scheduleDismissal(after duration: TimeInterval) {
        timer?.invalidate()
        timer = nil
        guard duration > 0 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                withAnimation(NotchTheme.expandAnimation) { self?.current = nil }
            }
        }
    }
}
