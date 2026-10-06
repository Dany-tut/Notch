import AppKit
import EventKit
import SwiftUI

/// Невыполненные напоминания из системных «Напоминаний».
///
/// `EKEventStore` общий с Календарём: Apple советует один долгоживущий
/// экземпляр на приложение — он держит соединение с базой и кэш, а второй
/// поднимал бы всё это заново ради тех же данных.
///
/// Читаем только пока модуль на экране: напоминания нужны, когда на них
/// смотрят, и опрашивать базу ради закрытой панели незачем.
@MainActor
final class RemindersStore: ObservableObject {
    enum Access: Equatable {
        case unknown
        case granted
        case denied
        /// Запущено не бандлом: без описания доступа в Info.plist система
        /// не спросит и в список «Напоминания» нас не добавит.
        case unavailable
    }

    /// Напоминание в том виде, в каком его рисует панель. `EKReminder`
    /// не `Sendable`, а выборка приходит с чужой очереди — поэтому в
    /// главный поток едут только значения.
    struct Item: Identifiable, Equatable, Sendable {
        let id: String
        let title: String
        let due: Date?
        /// Срок со временем, а не просто днём — тогда показываем часы.
        let hasTime: Bool
        let listID: String
        let created: Date?
    }

    struct List: Equatable {
        let title: String
        let color: Color
    }

    @Published private(set) var access: Access = .unknown
    @Published private(set) var items: [Item] = []
    @Published private(set) var lists: [String: List] = [:]
    /// Отмеченные, но ещё не сохранённые. Галочка ставится сразу, а в базу
    /// уходит через пару секунд: промахнулся — тапни ещё раз, и ничего не
    /// случилось.
    @Published private(set) var completing: Set<String> = []
    @Published var draft = ""

    private let store: EKEventStore
    private var observer: NSObjectProtocol?
    private var commitTasks: [String: Task<Void, Never>] = [:]
    /// Номер выборки: ответ, пришедший после более свежего запроса, выбрасываем.
    private var generation = 0

    private static let commitDelay: Duration = .seconds(1.8)

    private static var isProperlyBundled: Bool {
        Bundle.main.bundleIdentifier != nil
            && Bundle.main.object(forInfoDictionaryKey: "NSRemindersFullAccessUsageDescription") != nil
    }

    init(store: EKEventStore) {
        self.store = store
    }

    /// Списков среди показанных больше одного — тогда у строки есть точка
    /// цвета списка, иначе она ничего не различает.
    var showsLists: Bool {
        Set(items.map(\.listID)).count > 1
    }

    // MARK: - Видимость

    func resume() {
        refreshAccess()
        guard access == .granted else { return }
        if observer == nil {
            observer = NotificationCenter.default.addObserver(
                forName: .EKEventStoreChanged,
                object: store,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            }
        }
        reload()
    }

    /// Модуль ушёл с экрана. Отмеченное досохраняем сразу — иначе галочка,
    /// поставленная за секунду до закрытия панели, пропала бы.
    func suspend() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        for id in completing { commit(id) }
    }

    // MARK: - Доступ

    func requestAccess() {
        guard access == .unknown else { return }
        Task {
            let granted = (try? await store.requestFullAccessToReminders()) ?? false
            refreshAccess()
            if !granted, access == .unknown { access = .denied }
            if access == .granted { resume() }
        }
    }

    func refreshAccess() {
        guard Self.isProperlyBundled else {
            access = .unavailable
            return
        }
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: access = .granted
        // «Только запись» читать не даёт — для списка это тот же отказ.
        case .denied, .restricted, .writeOnly: access = .denied
        default: access = .unknown
        }
    }

    func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Действия

    /// Галочка: первый тап ставит её, второй — пока не сохранено — снимает.
    func toggle(_ item: Item) {
        if completing.contains(item.id) {
            commitTasks.removeValue(forKey: item.id)?.cancel()
            completing.remove(item.id)
            return
        }
        completing.insert(item.id)
        commitTasks[item.id] = Task { [weak self] in
            try? await Task.sleep(for: Self.commitDelay)
            guard !Task.isCancelled else { return }
            self?.commit(item.id)
        }
    }

    /// Новое напоминание в списке по умолчанию, без срока.
    func add() {
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, access == .granted,
              let list = store.defaultCalendarForNewReminders()
        else { return }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = list
        do {
            try store.save(reminder, commit: true)
            draft = ""
            reload()
        } catch {
            NSSound.beep()
        }
    }

    private func commit(_ id: String) {
        commitTasks.removeValue(forKey: id)?.cancel()
        defer { completing.remove(id) }
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        reminder.isCompleted = true
        do {
            try store.save(reminder, commit: true)
            withAnimation(.easeOut(duration: 0.25)) {
                items.removeAll { $0.id == id }
            }
        } catch {
            NSSound.beep()
        }
    }

    // MARK: - Выборка

    private func reload() {
        guard access == .granted else { return }
        generation += 1
        let current = generation

        var known: [String: List] = [:]
        for calendar in store.calendars(for: .reminder) {
            known[calendar.calendarIdentifier] = List(
                title: calendar.title,
                color: Color(cgColor: calendar.cgColor)
            )
        }
        lists = known

        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: nil
        )
        store.fetchReminders(matching: predicate, completion: Self.handler { [weak self] fetched in
            Task { @MainActor in
                guard let self, current == self.generation else { return }
                // Отмеченные, но не сохранённые остаются на месте: база о
                // галочке ещё не знает и вернёт их как невыполненные.
                self.items = fetched
            }
        })
    }

    /// Обработчик выборки собран вне главного актора: EventKit зовёт его
    /// со своей очереди, и замыкание, унаследовавшее `@MainActor`, Swift 6
    /// уронил бы проверкой изоляции.
    nonisolated private static func handler(
        _ deliver: @escaping @Sendable ([Item]) -> Void
    ) -> ([EKReminder]?) -> Void {
        { reminders in deliver(sorted((reminders ?? []).map(item))) }
    }

    nonisolated private static func item(_ reminder: EKReminder) -> Item {
        let components = reminder.dueDateComponents
        return Item(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "",
            due: components.flatMap { Calendar.current.date(from: $0) },
            hasTime: components?.hour != nil,
            listID: reminder.calendar?.calendarIdentifier ?? "",
            created: reminder.creationDate
        )
    }

    /// Со сроком — по сроку, без срока — в конце, свежие выше.
    nonisolated static func sorted(_ items: [Item]) -> [Item] {
        items.sorted { lhs, rhs in
            switch (lhs.due, rhs.due) {
            case let (l?, r?) where l != r: return l < r
            case (.some, nil): return true
            case (nil, .some): return false
            default: return (lhs.created ?? .distantPast) > (rhs.created ?? .distantPast)
            }
        }
    }
}

extension RemindersStore.Item {
    /// Просрочено: срок со временем — уже прошёл, срок днём — день позади.
    func isOverdue(now: Date = Date()) -> Bool {
        guard let due else { return false }
        return hasTime ? due < now : due < Calendar.current.startOfDay(for: now)
    }

    var isDueToday: Bool {
        guard let due else { return false }
        return Calendar.current.isDateInToday(due)
    }
}
