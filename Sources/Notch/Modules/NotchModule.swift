import SwiftUI

/// Модуль панели: одна вкладка в левом рейле плюс её содержимое.
///
/// Всё, что умеет панель, приходит сюда. Ядро ничего не знает о конкретных
/// модулях — добавление нового модуля не требует правок панели.
@MainActor
protocol NotchModule: Identifiable {
    /// Стабильный идентификатор для сохранения выбранной вкладки и порядка.
    var id: String { get }
    /// Ключ заголовка над содержимым. Не строка — заголовок переводится.
    var titleKey: L10n.Key { get }
    /// SF Symbol для рейла.
    var symbol: String { get }
    /// Сколько высоты модуль хотел бы занять. Панель берёт максимум по всем.
    var preferredHeight: CGFloat { get }

    associatedtype Content: View
    @ViewBuilder func makeContent() -> Content

    /// Обвязка модуля, которую панель ставит в строку заголовка.
    ///
    /// Раньше такая строка была у каждого модуля своя, внизу его
    /// содержимого. Но строка заголовка уже нарисована и почти пуста: от
    /// названия раздела до кнопок панели тянется поле, за которое никто не
    /// платит высотой. Переехав туда, обвязка перестала стоить модулю
    /// целый ряд.
    ///
    /// Слотов два, и делятся они не по важности, а по смыслу. `Modes` —
    /// как раздел показать: поиск, список или плитки, сколько всего
    /// записей. Они стоят слева, сразу за названием раздела, и читаются
    /// его продолжением — тем же, чем и заголовок, только подробнее.
    /// `Actions` — что с разделом сделать: вставить, отправить, очистить.
    /// Они уходят к правой кромке, подальше от режимов.
    ///
    /// Смешивать их в одну кучу нельзя, и это выяснилось на практике:
    /// значки одного размера подряд читаются одним рядом, и «показать
    /// плитками» оказывается соседом «очистить всё» — двух кнопок, у
    /// которых общего только размер.
    associatedtype Modes: View = EmptyView
    @ViewBuilder func makeModes() -> Modes

    associatedtype Actions: View = EmptyView
    @ViewBuilder func makeActions() -> Actions

    /// Во сколько обойдутся эти наборы. Ряду вкладок нужно знать ширину до
    /// вёрстки — он по ней решает, влезают ли подписи и название раздела.
    var modesWidth: CGFloat { get }
    var actionsWidth: CGFloat { get }
}

extension NotchModule {
    var preferredHeight: CGFloat { NotchTheme.defaultPanelHeight }
    /// Стирание типа, чтобы панель могла держать разнородные модули в одном массиве.
    func erasedContent() -> AnyView { AnyView(makeContent()) }

    func makeModes() -> EmptyView { EmptyView() }
    func makeActions() -> EmptyView { EmptyView() }
    var modesWidth: CGFloat { 0 }
    var actionsWidth: CGFloat { 0 }
    func erasedModes() -> AnyView { AnyView(makeModes()) }
    func erasedActions() -> AnyView { AnyView(makeActions()) }
}

/// Заглушка для модулей, до которых ещё не дошли руки.
struct PlaceholderModule: NotchModule {
    let id: String
    let titleKey: L10n.Key
    let symbol: String

    func makeContent() -> some View {
        PlaceholderContent(symbol: symbol)
    }
}

private struct PlaceholderContent: View {
    @EnvironmentObject private var settings: AppSettings
    let symbol: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(NotchTheme.textTertiary)
            Text(settings.t(.comingSoon))
                .font(.system(size: 12))
                .foregroundStyle(NotchTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Полный набор модулей в порядке по умолчанию.
@MainActor
enum ModuleCatalog {
    static func all(
        snippets: SnippetStore,
        clipboard: ClipboardStore,
        shelf: ShelfStore,
        calendar: CalendarStore,
        reminders: RemindersStore,
        mirror: MirrorStore,
        trash: TrashStore,
        music: NowPlayingCoordinator,
        battery: BatteryStore,
        timers: TimersStore,
        notes: NotesStore,
        system: SystemStore,
        weather: WeatherStore,
        apps: AppsStore,
        shortcuts: ShortcutsStore,
        converter: ConverterStore,
        emoji: EmojiStore
    ) -> [any NotchModule] {
        var modules: [any NotchModule] = [
            MusicModule(coordinator: music),
            ClipboardModule(store: clipboard),
            TrashModule(store: trash),
            SnippetsModule(store: snippets, clipboard: clipboard),
            NotesModule(store: notes),
            ShelfModule(store: shelf),
            CalendarModule(store: calendar),
            RemindersModule(store: reminders),
            MirrorModule(store: mirror),
            WeatherModule(store: weather),
            TimersModule(store: timers),
            BatteryModule(store: battery),
            SystemModule(store: system),
            AppsModule(store: apps),
            ShortcutsModule(store: shortcuts),
            ConverterModule(store: converter, clipboard: clipboard),
            EmojiModule(store: emoji, clipboard: clipboard)
        ]
        #if PRO
        ProCatalog.install(into: &modules, clipboard: clipboard)
        #endif
        return modules
    }

    /// Описание модуля без его содержимого — для списка в настройках.
    struct Descriptor: Identifiable, Hashable {
        let id: String
        let titleKey: L10n.Key
        let symbol: String
    }

    /// Дескрипторы в пользовательском порядке.
    ///
    /// Неизвестные `order` модули не теряются и не всплывают наверх: они
    /// встают следом за известными, в каталожном порядке. Так добавленный
    /// в новой версии модуль появляется в конце ряда, а не посередине
    /// чужой раскладки.
    static func ordered(by order: [String]) -> [Descriptor] {
        descriptors.enumerated().sorted { lhs, rhs in
            let l = order.firstIndex(of: lhs.element.id) ?? (order.count + lhs.offset)
            let r = order.firstIndex(of: rhs.element.id) ?? (order.count + rhs.offset)
            return l < r
        }.map(\.element)
    }

    static let descriptors: [Descriptor] = {
        var list = baseDescriptors
        #if PRO
        ProCatalog.install(into: &list)
        #endif
        return list
    }()

    private static let baseDescriptors: [Descriptor] = [
        .init(id: "music", titleKey: .moduleMusic, symbol: "music.note"),
        .init(id: "clipboard", titleKey: .moduleClipboard, symbol: "tray.full"),
        .init(id: "trash", titleKey: .moduleTrash, symbol: "trash"),
        .init(id: "snippets", titleKey: .moduleSnippets, symbol: "pin"),
        .init(id: "notes", titleKey: .moduleNotes, symbol: "square.and.pencil"),
        .init(id: "shelf", titleKey: .moduleShelf, symbol: "rectangle.portrait.on.rectangle.portrait"),
        .init(id: "calendar", titleKey: .moduleCalendar, symbol: "calendar"),
        .init(id: "reminders", titleKey: .moduleReminders, symbol: "checklist"),
        .init(id: "mirror", titleKey: .moduleMirror, symbol: "web.camera"),
        .init(id: WeatherModule.moduleID, titleKey: .moduleWeather, symbol: "cloud.sun"),
        .init(id: "timers", titleKey: .moduleTimers, symbol: "stopwatch"),
        .init(id: "battery", titleKey: .moduleBattery, symbol: "batteryblock"),
        .init(id: "system", titleKey: .moduleSystem, symbol: "gauge.with.dots.needle.33percent"),
        .init(id: "apps", titleKey: .moduleApps, symbol: "square.grid.2x2"),
        .init(id: ShortcutsModule.moduleID, titleKey: .moduleShortcuts, symbol: ShortcutsModule.railSymbol),
        .init(id: ConverterModule.moduleID, titleKey: .moduleConverter, symbol: ConverterModule.railSymbol),
        .init(id: EmojiModule.moduleID, titleKey: .moduleEmoji, symbol: EmojiModule.railSymbol)
    ]
}
