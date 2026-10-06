import SwiftUI

/// Буфер обмена: история скопированного, клик возвращает запись в буфер.
struct ClipboardModule: NotchModule {
    let id = "clipboard"
    let titleKey: L10n.Key = .moduleClipboard
    let symbol = "tray.full"

    let store: ClipboardStore

    func makeContent() -> some View {
        ClipboardContent(store: store)
    }

    /// Поиск и переключатель вида стоят в строке заголовка, слева, сразу
    /// за названием раздела: и то и другое отвечает на вопрос, что в
    /// истории показать. Пока в ней пусто, искать нечего и показывать
    /// нечем — кнопки уходят вместе со списком.
    func makeModes() -> some View {
        ClipboardModes(store: store)
    }

    var modesWidth: CGFloat { 74 }
}

/// Режимы модуля: поиск, список, сетка.
private struct ClipboardModes: View {
    @ObservedObject var store: ClipboardStore
    @EnvironmentObject private var settings: AppSettings

    @FocusState private var isSearchFocused: Bool

    var body: some View {
        if !store.entries.isEmpty {
            HStack(spacing: 4) {
                SearchField(
                    text: $store.query,
                    isOpen: $store.isSearching,
                    placeholder: settings.t(.searchPlaceholder),
                    help: settings.t(.searchPlaceholder),
                    isFocused: $isSearchFocused
                )

                if !store.isSearching {
                    LayoutToggle(
                        isGrid: $settings.clipboardGrid,
                        listHelp: settings.t(.clipboardListMode),
                        gridHelp: settings.t(.clipboardGridMode)
                    )
                }
            }
            .animation(.snappy(duration: 0.22), value: store.isSearching)
        }
    }
}

private struct ClipboardContent: View {
    @ObservedObject var store: ClipboardStore
    @EnvironmentObject private var settings: AppSettings

    @State private var copiedID: UUID?
    /// Запись, раскрытая крупно по долгому нажатию.
    @State private var preview: ClipboardEntry?

    private var visible: [ClipboardEntry] { store.visible }

    var body: some View {
        if store.entries.isEmpty {
            EmptyState(
                symbol: "tray",
                title: settings.t(.clipboardEmptyTitle),
                hint: settings.t(.clipboardEmptyHint)
            )
        } else {
            content.overlay {
                if let preview {
                    NotchPreview(
                        text: preview.isImage ? nil : preview.text,
                        caption: preview.isImage ? preview.text : nil,
                        hint: settings.t(.previewHint),
                        image: preview.imageURL.map { url in
                            { await ClipboardThumbnail.make(for: url, size: 512) }
                        }
                    ) {
                        self.preview = nil
                    }
                }
            }
        }
    }

    /// Один список во всю высоту: поиск и переключатель вида уехали в
    /// строку заголовка, и своей строки действий у модуля больше нет.
    private var content: some View { list }

    private var list: some View {
        NotchScroll {
            VStack(spacing: 1) {
                if visible.isEmpty {
                    Text(settings.t(.searchNothingFound))
                        .font(.system(size: 11))
                        .foregroundStyle(NotchTheme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: NotchTheme.rowHeight)
                } else if settings.clipboardGrid {
                    tiles
                } else {
                    rows
                }
            }
        }
    }

    private var rows: some View {
        ForEach(visible) { entry in
            ClipboardRow(
                entry: entry,
                isCopied: copiedID == entry.id,
                copiedLabel: settings.t(.copied),
                imageLabel: settings.t(.clipboardImage),
                onCopy: { copy(entry) },
                onPreview: { preview = $0 ? entry : nil },
                onPin: { store.togglePin(entry) },
                onRemove: { store.remove(entry) }
            )
            .id(entry.id)
        }
    }

    private var tiles: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 96), spacing: 6)],
            spacing: 6
        ) {
            ForEach(visible) { entry in
                ClipboardTile(
                    entry: entry,
                    isCopied: copiedID == entry.id,
                    copiedLabel: settings.t(.copied),
                    badge: entry.isImage ? "PNG" : settings.t(.clipboardText),
                    onCopy: { copy(entry) },
                    onPreview: { preview = $0 ? entry : nil },
                    onPin: { store.togglePin(entry) },
                    onRemove: { store.remove(entry) }
                )
                .id(entry.id)
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
    }

    private func copy(_ entry: ClipboardEntry) {
        store.copy(entry)
        copiedID = entry.id
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if copiedID == entry.id { copiedID = nil }
        }
    }
}

// MARK: - Строка

private struct ClipboardRow: View {
    let entry: ClipboardEntry
    let isCopied: Bool
    let copiedLabel: String
    let imageLabel: String
    let onCopy: () -> Void
    let onPreview: (Bool) -> Void
    let onPin: () -> Void
    let onRemove: () -> Void

    @State private var isHovered = false

    /// Переводы строк в одну строку, иначе список прыгает по высоте.
    private var preview: String {
        guard !entry.isImage else { return "\(imageLabel) · \(entry.text)" }
        return entry.text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 10) {
                icon

                Text(isCopied ? copiedLabel : preview)
                    .font(.system(size: 12))
                    .foregroundStyle(isCopied ? NotchTheme.textPrimary : NotchTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())

            // Место под кнопки занято всегда — они лишь проявляются.
            // Иначе при наведении строка меняет ширину текста и «прыгает».
            HStack(spacing: 4) {
                RowAction(symbol: entry.isPinned ? "pin.slash" : "pin", action: onPin)
                RowAction(symbol: "xmark", action: onRemove)
            }
            .opacity(isHovered ? 1 : 0)
            .allowsHitTesting(isHovered)
        }
        .padding(.horizontal, 8)
        .frame(height: NotchTheme.rowHeight)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isHovered ? NotchTheme.accentSelection.opacity(0.6) : .clear)
        }
        .onHover { isHovered = $0 }
        .clipboardGestures(entry: entry, onCopy: onCopy, onPreview: onPreview)
    }

    /// У картинки вместо значка — она сама: строка списка тем и отличается
    /// от карточки, что кадр в ней маленький, но он есть.
    @ViewBuilder private var icon: some View {
        if entry.isImage, let url = entry.imageURL {
            ClipboardThumbnailView(url: url, corner: 4)
                .frame(width: 22, height: 16)
        } else {
            Image(systemName: entry.isPinned ? "pin.fill" : "doc.on.clipboard")
                .font(.system(size: 10))
                .foregroundStyle(NotchTheme.textTertiary)
                .frame(width: 16)
        }
    }
}

// MARK: - Карточка

private struct ClipboardTile: View {
    let entry: ClipboardEntry
    let isCopied: Bool
    let copiedLabel: String
    /// Что написано в капсуле поверх кадра: «PNG» или «Текст».
    let badge: String
    let onCopy: () -> Void
    let onPreview: (Bool) -> Void
    let onPin: () -> Void
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(height: 76)
        .padding(3)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(NotchTheme.accentSelection.opacity(isHovered ? 1 : 0.45))
        }
        // Кнопки поверх карточки: в раскладке места не занимают, поэтому
        // сетка от наведения не дёргается.
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 3) {
                TileAction(symbol: entry.isPinned ? "pin.slash" : "pin", action: onPin)
                TileAction(symbol: "xmark", action: onRemove)
            }
            .offset(x: 4, y: -4)
            .opacity(isHovered ? 1 : 0)
            .allowsHitTesting(isHovered)
        }
        // Ярлык слева, закреплённость — справа: на узкой плитке они иначе
        // налезают друг на друга.
        .overlay(alignment: .bottomLeading) {
            if !isCopied { TileBadge(text: badge) }
        }
        .overlay(alignment: .bottomTrailing) {
            if entry.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(NotchTheme.textSecondary)
                    .padding(7)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .clipboardGestures(entry: entry, onCopy: onCopy, onPreview: onPreview)
    }

    @ViewBuilder private var content: some View {
        if isCopied {
            Text(copiedLabel)
                .font(.system(size: 11))
                .foregroundStyle(NotchTheme.textPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if entry.isImage, let url = entry.imageURL {
            ClipboardThumbnailView(url: url, corner: 8)
        } else {
            Text(entry.text)
                .font(.system(size: 10))
                .foregroundStyle(NotchTheme.textSecondary)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(5)
                // Снизу место под капсулу: текст не должен уходить под неё.
                .padding(.bottom, 14)
        }
    }
}

// MARK: - Общие жесты

/// Клик копирует, зажатие показывает крупно, перетаскивание отдаёт запись
/// наружу: картинку — файлом, текст — строкой. Жесты одни и те же в списке
/// и в сетке, поэтому живут модификатором, а не копией в каждой.
private struct ClipboardGestures: ViewModifier {
    let entry: ClipboardEntry
    let onCopy: () -> Void
    let onPreview: (Bool) -> Void

    func body(content: Content) -> some View {
        dragging(content)
            .holdToPreview(onTap: onCopy, onPreview: onPreview)
    }

    @ViewBuilder private func dragging(_ content: Content) -> some View {
        if let url = entry.imageURL {
            content.draggable(url) {
                ClipboardThumbnailView(url: url, corner: 6)
                    .frame(width: 64, height: 48)
            }
        } else {
            content.draggable(entry.text) {
                Text(entry.text)
                    .font(.system(size: 11))
                    .lineLimit(2)
                    .padding(6)
                    .frame(maxWidth: 160)
                    .background(NotchTheme.accentSelection)
            }
        }
    }
}

private extension View {
    func clipboardGestures(
        entry: ClipboardEntry,
        onCopy: @escaping () -> Void,
        onPreview: @escaping (Bool) -> Void
    ) -> some View {
        modifier(ClipboardGestures(entry: entry, onCopy: onCopy, onPreview: onPreview))
    }
}

/// Кадр записи. Грузится в фоне и уменьшённым — полноразмерный скриншот
/// в плитке стоил бы прокрутке кадров.
private struct ClipboardThumbnailView: View {
    let url: URL
    let corner: CGFloat

    @State private var image: NSImage?

    var body: some View {
        Color.clear
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.medium)
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 11))
                        .foregroundStyle(NotchTheme.textTertiary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .task(id: url) { image = await ClipboardThumbnail.make(for: url) }
    }
}

// MARK: - Кнопки

private struct RowAction: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(NotchTheme.textTertiary)
                .frame(width: 18, height: 18)
                .background(Squircle().fill(NotchTheme.accentSelection))
        }
        .buttonStyle(.plain)
    }
}

private struct TileAction: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
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
    }
}
