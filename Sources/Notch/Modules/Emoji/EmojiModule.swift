import SwiftUI

/// Эмодзи: сетка по разделам, поиск в строке заголовка, недавние сверху.
/// Щелчок копирует.
struct EmojiModule: NotchModule {
    static let moduleID = "emoji"
    static let railSymbol = "face.smiling"

    let id = EmojiModule.moduleID
    let titleKey: L10n.Key = .moduleEmoji
    let symbol = EmojiModule.railSymbol
    var preferredHeight: CGFloat { 248 }

    let store: EmojiStore
    let clipboard: ClipboardStore

    func makeContent() -> some View {
        EmojiContent(store: store, clipboard: clipboard)
    }

    func makeModes() -> some View {
        EmojiModes(store: store)
    }

    var modesWidth: CGFloat { 30 }
}

// MARK: - Строка заголовка

private struct EmojiModes: View {
    @ObservedObject var store: EmojiStore
    @EnvironmentObject private var settings: AppSettings
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        SearchField(
            text: $store.query,
            isOpen: $store.isSearching,
            placeholder: settings.t(.emojiSearch),
            help: settings.t(.emojiSearch),
            isFocused: $isSearchFocused
        )
    }
}

// MARK: - Содержимое

private struct EmojiContent: View {
    @ObservedObject var store: EmojiStore
    let clipboard: ClipboardStore
    @EnvironmentObject private var settings: AppSettings

    @State private var hovered: EmojiStore.Entry?
    @State private var copied: String?

    private static let recentSection = "recent"

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 6) {
                header(proxy: proxy)
                grid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Ряд разделов слева и строка состояния справа: что под курсором или
    /// что только что скопировано.
    private func header(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 2) {
            if store.query.isEmpty {
                if !store.recent.isEmpty {
                    SectionButton(symbol: "clock", help: settings.t(.emojiRecent)) {
                        withAnimation(.snappy(duration: 0.3)) { proxy.scrollTo(Self.recentSection, anchor: .top) }
                    }
                }
                ForEach(EmojiCategory.allCases) { category in
                    SectionButton(symbol: category.symbol, help: settings.t(category.titleKey)) {
                        withAnimation(.snappy(duration: 0.3)) { proxy.scrollTo(category.rawValue, anchor: .top) }
                    }
                }
            }

            Spacer(minLength: 8)

            status
        }
        .frame(height: 22)
    }

    @ViewBuilder
    private var status: some View {
        if let copied {
            HStack(spacing: 5) {
                Text(copied).font(.system(size: 13))
                Text(settings.t(.copied))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ActivityTint.green)
            }
            .transition(.opacity)
        } else if let hovered {
            HStack(spacing: 5) {
                Text(hovered.emoji).font(.system(size: 13))
                Text(hovered.name)
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: 240, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var grid: some View {
        if !store.query.isEmpty {
            let found = store.search(store.query)
            if found.isEmpty {
                EmptyState(
                    symbol: "magnifyingglass",
                    title: settings.t(.emojiNoResults),
                    hint: store.query
                )
            } else {
                NotchScroll {
                    cells(found, section: "search")
                        .padding(.vertical, 2)
                }
            }
        } else {
            NotchScroll {
                LazyVStack(alignment: .leading, spacing: 6, pinnedViews: []) {
                    if !store.recent.isEmpty {
                        section(settings.t(.emojiRecent), id: Self.recentSection, entries: store.recentEntries)
                    }
                    ForEach(EmojiCategory.allCases) { category in
                        section(settings.t(category.titleKey), id: category.rawValue, entries: store.entries(in: category))
                    }
                }
                .padding(.bottom, 4)
            }
        }
    }

    private func section(_ title: String, id: String, entries: [EmojiStore.Entry]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(NotchTheme.textTertiary)
                .padding(.leading, 4)
                .padding(.top, 2)
            cells(entries, section: id)
        }
        .id(id)
    }

    private func cells(_ entries: [EmojiStore.Entry], section: String) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 30, maximum: 34), spacing: 2)], spacing: 2) {
            ForEach(entries) { entry in
                EmojiCell(entry: entry, isHovered: hovered == entry) { isHovering in
                    if isHovering { hovered = entry } else if hovered == entry { hovered = nil }
                } onTap: {
                    copy(entry)
                }
            }
        }
    }

    private func copy(_ entry: EmojiStore.Entry) {
        clipboard.copy(entry.emoji)
        // Недавние переставляем не сразу: сетка под курсором сдвинулась бы
        // ровно в момент щелчка, и второй щелчок попал бы не туда.
        withAnimation(.easeOut(duration: 0.15)) { copied = entry.emoji }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.easeOut(duration: 0.2)) {
                if copied == entry.emoji { copied = nil }
            }
            store.use(entry.emoji)
        }
    }
}

private struct SectionButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isHovered ? NotchTheme.textPrimary : NotchTheme.textTertiary)
                .frame(width: 24, height: 22)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovered ? NotchTheme.accentSelection : .clear)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .notchHelp(help)
    }
}

private struct EmojiCell: View {
    let entry: EmojiStore.Entry
    let isHovered: Bool
    let onHover: (Bool) -> Void
    let onTap: () -> Void

    var body: some View {
        Text(entry.emoji)
            .font(.system(size: 20))
            .frame(width: 30, height: 30)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHovered ? NotchTheme.accentSelection : .clear)
            }
            .scaleEffect(isHovered ? 1.12 : 1)
            .animation(.snappy(duration: 0.14), value: isHovered)
            .contentShape(Rectangle())
            .onHover(perform: onHover)
            .onTapGesture(perform: onTap)
    }
}
