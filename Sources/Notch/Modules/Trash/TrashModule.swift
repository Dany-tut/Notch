import SwiftUI

/// Корзина: сколько в ней лежит, что именно, и две операции —
/// открыть в Finder и очистить. Плюс приём файлов перетаскиванием.
struct TrashModule: NotchModule {
    let id = "trash"
    let titleKey: L10n.Key = .moduleTrash
    let symbol = "trash"

    let store: TrashStore

    func makeContent() -> some View {
        TrashContent(store: store)
    }
}

private struct TrashContent: View {
    @ObservedObject var store: TrashStore
    @EnvironmentObject private var settings: AppSettings

    @State private var isTargeted = false
    @State private var isConfirmingEmpty = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.items.isEmpty {
                EmptyState(
                    symbol: "trash",
                    title: settings.t(.trashEmptyTitle),
                    hint: settings.t(.trashEmptyHint)
                )
            } else {
                list
                toolbar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    NotchTheme.textTertiary,
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
                .opacity(isTargeted ? 1 : 0)
        }
        .dropDestination(for: URL.self) { urls, _ in
            store.moveToTrash(urls) > 0
        } isTargeted: { isTargeted = $0 }
    }

    private var list: some View {
        ScrollView(.vertical) {
            VStack(spacing: 1) {
                ForEach(store.items) { item in
                    TrashRow(item: item)
                }
            }
        }
        .scrollIndicators(.never)
        .frame(maxHeight: .infinity)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text("\(settings.t(.trashCount)): \(store.items.count)")
                .font(.system(size: 11))
                .foregroundStyle(NotchTheme.textTertiary)

            Spacer(minLength: 0)

            TrashButton(title: settings.t(.trashReveal)) { store.revealInFinder() }

            // Очистка необратима, поэтому кнопка сначала превращается
            // в явное подтверждение, а не спрашивает системным диалогом
            // поверх панели.
            if isConfirmingEmpty {
                TrashButton(title: settings.t(.trashCancel)) { isConfirmingEmpty = false }
                TrashButton(title: settings.t(.trashConfirmEmpty), isDestructive: true) {
                    store.empty()
                    isConfirmingEmpty = false
                }
            } else {
                TrashButton(title: settings.t(.trashEmpty)) { isConfirmingEmpty = true }
            }
        }
    }
}

private struct TrashRow: View {
    let item: TrashItem

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 16, height: 16)

            Text(item.name)
                .font(.system(size: 12))
                .foregroundStyle(NotchTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: NotchTheme.rowHeight)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isHovered ? NotchTheme.accentSelection.opacity(0.6) : .clear)
        }
        .onHover { isHovered = $0 }
    }
}

private struct TrashButton: View {
    let title: String
    var isDestructive = false
    let action: () -> Void

    @State private var isHovered = false

    private var foreground: Color {
        if isDestructive { return isHovered ? .red : .red.opacity(0.75) }
        return isHovered ? NotchTheme.textPrimary : NotchTheme.textTertiary
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(foreground)
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
