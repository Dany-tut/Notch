import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

/// Полка: временное хранилище файлов. Кладут перетаскиванием или ⌘V,
/// забирают перетаскиванием — файлы при этом остаются на своих местах.
struct ShelfModule: NotchModule {
    let id = "shelf"
    let titleKey: L10n.Key = .moduleShelf
    let symbol = "rectangle.portrait.on.rectangle.portrait"
    var preferredHeight: CGFloat { 248 }

    let store: ShelfStore

    func makeContent() -> some View {
        ShelfContent(store: store)
    }

    /// Вся обвязка полки стоит в строке заголовка — там же, где она у
    /// буфера. Своего ряда внизу у полки больше нет, освободившаяся
    /// высота ушла файлам. На пустой полке ни показывать, ни чистить
    /// нечего, поэтому оба набора уходят вместе с файлами.
    func makeModes() -> some View {
        ShelfModes(store: store)
    }

    func makeActions() -> some View {
        ShelfActions(store: store)
    }

    var modesWidth: CGFloat { 68 }
    var actionsWidth: CGFloat { 78 }
}

/// Режимы полки: сколько файлов и каким видом их показать.
private struct ShelfModes: View {
    @ObservedObject var store: ShelfStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        if !store.items.isEmpty {
            HStack(spacing: 6) {
                // Счётчик — цифрой без слова: он стоит вплотную к названию
                // раздела и читается как его продолжение, а «Файлов: 3» в
                // одной строке с вкладками заняло бы место самих вкладок.
                Text("\(store.items.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(NotchTheme.textTertiary)
                    .monospacedDigit()
                    .notchHelp(settings.t(.shelfCount))

                LayoutToggle(
                    isGrid: $settings.shelfGrid,
                    listHelp: settings.t(.shelfListMode),
                    gridHelp: settings.t(.shelfGridMode)
                )
            }
        }
    }
}

/// Команды полки: вставить, отправить, очистить.
///
/// В покое — три значка у правой кромки строки. Под курсором раскрывается
/// один: соседи гаснут, а подпись встаёт плашкой на их место — у той же
/// правой кромки, а не там, где случился курсор. Ряд от этого не дышит:
/// справа ничего не съезжает и дырок не остаётся, потому что плашка
/// занимает ровно то место, которое освободили погасшие.
///
/// Плашка растёт из своей середины, а не выезжает с края: край, из
/// которого она выезжала бы, — это соседняя команда, и движение читалось
/// бы как «одна кнопка превращается в другую».
private struct ShelfActions: View {
    @ObservedObject var store: ShelfStore
    @EnvironmentObject private var settings: AppSettings

    /// Под какой из команд сейчас курсор.
    @State private var hovered: Int?

    private var commands: [(symbol: String, title: String, enabled: Bool, run: () -> Void)] {
        // Выбора на полке нет — щелчок по файлу ничего не отмечает, его
        // тянут или зажимают. Поэтому из строки заголовка в AirDrop уходит
        // вся полка, а один файл — из его контекстного меню.
        let canAirDrop = ShelfAirDrop.canSend(store.items.map(\.url))
        return [
            ("doc.on.clipboard", settings.t(.shelfPaste), true, { store.paste() }),
            (
                ShelfAirDrop.symbol,
                settings.t(canAirDrop ? .shelfAirDropAll : .shelfAirDropUnavailable),
                canAirDrop,
                { ShelfAirDrop.send(store.urlsForSharing()) }
            ),
            ("trash", settings.t(.shelfClearAll), true, { store.removeAll() })
        ]
    }

    var body: some View {
        if !store.items.isEmpty {
            HStack(spacing: 6) {
                ForEach(Array(commands.enumerated()), id: \.offset) { index, command in
                    Button {
                        if command.enabled { command.run() }
                    } label: {
                        // Гаснет только значок, а не кнопка целиком.
                        // Полностью прозрачную кнопку SwiftUI перестаёт
                        // считать нажимаемой: наведение ей оставляет —
                        // его ведёт зона слежения, — а щелчок проходит
                        // мимо. Раскрытая команда от этого нажималась
                        // ровно никогда: подпись показывалась, а «очистить
                        // полку» ничего не чистило. Поэтому кнопка держит
                        // подложку, которой курсору достаточно, а тает
                        // внутри неё сам значок.
                        Color.black.opacity(0.001)
                            .frame(width: 22, height: 20)
                            .overlay {
                                Image(systemName: command.symbol)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(NotchTheme.textTertiary)
                                    .opacity(hovered == nil ? (command.enabled ? 1 : 0.4) : 0)
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    // Погасший значок курсор всё-таки ловит: плашка над ним
                    // прозрачна для мыши, и ведёт её по командам он. Иначе
                    // с раскрытой «Вставить» до «Очистить» пришлось бы
                    // выходить из ряда и заходить заново.
                    .onHover { hovering in
                        if hovering {
                            hovered = index
                        } else if hovered == index {
                            hovered = nil
                        }
                    }
                }
            }
            // Плашка — накладкой поверх ряда, а не внутри него: значки
            // держат свои места и размеры, и от наведения в строке не
            // двигается ничего. Росли бы они по-настоящему — значок уезжал
            // бы из-под курсора, наведение слетало, подпись схлопывалась,
            // значок возвращался, и так по кругу.
            .overlay(alignment: .trailing) { openCommand }
            .animation(.snappy(duration: 0.2), value: hovered)
        }
    }

    @ViewBuilder private var openCommand: some View {
        if let hovered, commands.indices.contains(hovered) {
            let command = commands[hovered]
            HStack(spacing: 5) {
                Image(systemName: command.symbol)
                    .font(.system(size: 10, weight: .medium))
                Text(command.title)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
            .fixedSize()
            .foregroundStyle(command.enabled ? NotchTheme.textPrimary : NotchTheme.textTertiary)
            .padding(.horizontal, 9)
            .frame(height: 20)
            .background { Capsule().fill(NotchTheme.accentSelection) }
            .allowsHitTesting(false)
            .transition(.scale(scale: 0.86, anchor: .center).combined(with: .opacity))
        }
    }
}

private struct ShelfContent: View {
    @ObservedObject var store: ShelfStore
    @EnvironmentObject private var settings: AppSettings

    @State private var isTargeted = false
    @State private var pasteMonitor: Any?
    /// Запись, раскрытая крупно на время зажатия.
    @State private var preview: ShelfItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.items.isEmpty {
                VStack(spacing: 8) {
                    EmptyState(
                        symbol: "tray.and.arrow.down",
                        title: settings.t(.shelfEmptyTitle),
                        hint: settings.t(.shelfEmptyHint)
                    )
                    ShelfButton(title: settings.t(.shelfPaste)) { store.paste() }
                        .padding(.bottom, 6)
                }
            } else {
                if settings.shelfGrid { tiles } else { rows }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay {
            if let preview {
                NotchPreview(
                    caption: preview.name,
                    hint: settings.t(.previewHint),
                    image: { await ShelfThumbnail.make(for: preview.url, size: 512) }
                ) {
                    self.preview = nil
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    NotchTheme.textTertiary,
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
                .opacity(isTargeted ? 1 : 0)
        }
        // Принимаем и списком файлов, и одиночным файлом.
        .dropDestination(for: URL.self) { urls, _ in
            store.add(urls)
            return !urls.isEmpty
        } isTargeted: { isTargeted = $0 }
        // Панель не активирующая: пока фокус клавиатуры у чужого приложения,
        // ⌘V уйдёт туда. Поэтому забираем фокус сразу, как только вкладку
        // открыли, — иначе курсор на рейле, а не на полке, и вставка уходит
        // мимо. При схлопывании панель фокус возвращает.
        .onHover { hovering in
            if hovering { NotchPanel.focusForTyping() }
        }
        .onAppear {
            NotchPanel.focusForTyping()
            startListeningForPaste()
        }
        .onDisappear(perform: stopListeningForPaste)
    }

    /// Ловим ⌘V (и ⌃V — так жмут по привычке с Windows) и съедаем событие,
    /// чтобы оно не ушло дальше по цепочке. Сравниваем по коду клавиши, а не
    /// по символу: в русской раскладке на той же клавише «м».
    private func startListeningForPaste() {
        guard pasteMonitor == nil else { return }
        pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard event.keyCode == 9,
                  flags == .command || flags == .control else { return event }
            let handled = MainActor.assumeIsolated { store.paste() }
            return handled ? nil : event
        }
    }

    private func stopListeningForPaste() {
        if let pasteMonitor { NSEvent.removeMonitor(pasteMonitor) }
        pasteMonitor = nil
    }

    private var tiles: some View {
        NotchScroll {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 6)], spacing: 6) {
                ForEach(store.items) { item in
                    ShelfTile(
                        item: item,
                        onPreview: { preview = $0 ? item : nil },
                        onRemove: { store.remove([item.id]) }
                    )
                    .contextMenu { ShelfItemMenu(store: store, item: item) }
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 2)
        }
    }

    /// Список: у документа с длинным именем плитка показывает огрызок,
    /// а строка — имя целиком. Перетаскивание и удаление те же.
    private var rows: some View {
        NotchScroll {
            VStack(spacing: 1) {
                ForEach(store.items) { item in
                    ShelfRow(
                        item: item,
                        onPreview: { preview = $0 ? item : nil },
                        onRemove: { store.remove([item.id]) }
                    )
                    .contextMenu { ShelfItemMenu(store: store, item: item) }
                }
            }
            .padding(.vertical, 2)
        }
    }

}

/// Правый щелчок по файлу полки: отправить его одного или убрать.
private struct ShelfItemMenu: View {
    let store: ShelfStore
    let item: ShelfItem
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Button {
            ShelfAirDrop.send(store.urlsForSharing([item.id]))
        } label: {
            Label(settings.t(.shelfAirDrop), systemImage: ShelfAirDrop.symbol)
        }
        .disabled(!ShelfAirDrop.canSend([item.url]))

        Button {
            NSWorkspace.shared.activateFileViewerSelecting([item.url])
        } label: {
            Label(settings.t(.shelfReveal), systemImage: "folder")
        }

        Divider()

        Button(role: .destructive) {
            store.remove([item.id])
        } label: {
            Label(settings.t(.shelfRemove), systemImage: "xmark")
        }
    }
}

private struct ShelfTile: View {
    let item: ShelfItem
    let onPreview: (Bool) -> Void
    let onRemove: () -> Void

    @EnvironmentObject private var settings: AppSettings

    @State private var isHovered = false
    @State private var thumbnail: NSImage?

    private var icon: NSImage {
        thumbnail ?? NSWorkspace.shared.icon(forFile: item.url.path)
    }

    /// Тип файла для капсулы: расширение, а если его нет — слово.
    private var badge: String {
        let ext = item.url.pathExtension.lowercased()
        guard ext.isEmpty else { return ext }
        return settings.t(item.url.hasDirectoryPath ? .shelfFolder : .shelfFile)
    }

    var body: some View {
        // Плитка та же, что в буфере: кадр во всю карточку, а тип — капсулой
        // поверх него. Имя целиком показывает список и превью по зажатию.
        // Кадр кладём поверх пустой подложки и режем уже по ней: картинка,
        // растянутая «по большей стороне», сама по себе шире плитки и наружу
        // её бы вынесло — ярлык тогда висит выше края кадра, а не у него.
        Color.clear
            .overlay {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    // Превью растягиваем на всю плитку, а нарисованную иконку
                    // типа — нет: она квадратная и на весь кадр читается как
                    // заплатка.
                    .aspectRatio(contentMode: thumbnail == nil ? .fit : .fill)
                    .padding(thumbnail == nil ? 12 : 0)
            }
            .frame(height: 76)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(3)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(NotchTheme.accentSelection.opacity(isHovered ? 1 : 0.45))
        }
        .overlay(alignment: .bottomLeading) {
            TileBadge(text: badge)
        }
        // Крестик поверх карточки: в раскладке места не занимает, поэтому
        // сетка от наведения не дёргается.
        .overlay(alignment: .topTrailing) {
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(NotchTheme.textSecondary)
                    .frame(width: 16, height: 16)
                    .background {
                        Squircle()
                            .fill(NotchTheme.background)
                            .overlay(Squircle().fill(NotchTheme.accentSelection))
                    }
            }
            .buttonStyle(.plain)
            .offset(x: 5, y: -5)
            .opacity(isHovered ? 1 : 0)
            .allowsHitTesting(isHovered)
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .task(id: item.url) { thumbnail = await ShelfThumbnail.make(for: item.url) }
        // Тащим наружу сам файл, а не копию — оригинал остаётся на месте.
        .draggable(item.url) {
            Image(nsImage: icon).resizable().frame(width: 36, height: 36)
        }
        // Зажатие показывает файл крупно: имя «Снимок экрана 14.02.11»
        // не говорит, что на кадре, а открывать ради этого Просмотр — долго.
        .holdToPreview(onPreview: onPreview)
    }
}

private struct ShelfRow: View {
    let item: ShelfItem
    let onPreview: (Bool) -> Void
    let onRemove: () -> Void

    @State private var isHovered = false
    @State private var thumbnail: NSImage?

    private var icon: NSImage {
        thumbnail ?? NSWorkspace.shared.icon(forFile: item.url.path)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)

            Text(item.name)
                .font(.system(size: 12))
                .foregroundStyle(isHovered ? NotchTheme.textPrimary : NotchTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(NotchTheme.textTertiary)
                    .frame(width: 18, height: 18)
                    .background(Squircle().fill(NotchTheme.accentSelection))
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
            .allowsHitTesting(isHovered)
        }
        .padding(.horizontal, 8)
        .frame(height: NotchTheme.rowHeight)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isHovered ? NotchTheme.accentSelection.opacity(0.6) : .clear)
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .task(id: item.url) { thumbnail = await ShelfThumbnail.make(for: item.url) }
        // Тащим наружу сам файл, а не копию — оригинал остаётся на месте.
        .draggable(item.url) {
            Image(nsImage: icon).resizable().frame(width: 36, height: 36)
        }
        // Зажатие показывает файл крупно: имя «Снимок экрана 14.02.11»
        // не говорит, что на кадре, а открывать ради этого Просмотр — долго.
        .holdToPreview(onPreview: onPreview)
    }
}

private struct ShelfButton: View {
    let title: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(isHovered ? NotchTheme.textPrimary : NotchTheme.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background {
                    Capsule().fill(isHovered ? NotchTheme.accentSelection : .clear)
                }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
