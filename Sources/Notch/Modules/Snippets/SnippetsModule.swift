import SwiftUI

/// Заготовки: список часто вставляемых строк. Клик копирует значение.
struct SnippetsModule: NotchModule {
    let id = "snippets"
    let titleKey: L10n.Key = .moduleSnippets
    let symbol = "pin"

    let store: SnippetStore
    let clipboard: ClipboardStore

    func makeContent() -> some View {
        SnippetsContent(store: store, clipboard: clipboard)
    }
}

private struct SnippetsContent: View {
    @ObservedObject var store: SnippetStore
    @ObservedObject var clipboard: ClipboardStore
    @EnvironmentObject private var settings: AppSettings

    @State private var copiedID: UUID?

    var body: some View {
        if store.snippets.isEmpty {
            EmptyState(
                symbol: "pin",
                title: settings.t(.snippetsEmptyTitle),
                hint: settings.t(.snippetsEmptyHint)
            )
        } else {
            NotchScroll {
                VStack(spacing: 1) {
                    ForEach(store.snippets) { snippet in
                        SnippetRow(
                            snippet: snippet,
                            isCopied: copiedID == snippet.id,
                            copiedLabel: settings.t(.copied)
                        ) {
                            copy(snippet)
                        }
                    }
                }
            }
        }
    }

    private func copy(_ snippet: Snippet) {
        clipboard.copy(snippet.value)
        copiedID = snippet.id
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if copiedID == snippet.id { copiedID = nil }
        }
    }
}

private struct SnippetRow: View {
    let snippet: Snippet
    let isCopied: Bool
    let copiedLabel: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: snippet.symbol.isEmpty ? "at" : snippet.symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTheme.textTertiary)
                    .frame(width: 16)

                Text(snippet.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NotchTheme.textSecondary)
                    .frame(width: 120, alignment: .leading)

                Text(isCopied ? copiedLabel : snippet.value)
                    .font(.system(size: 12))
                    .foregroundStyle(isCopied ? NotchTheme.textPrimary : NotchTheme.textSecondary)
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let hint: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(NotchTheme.textTertiary)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NotchTheme.textSecondary)
            Text(hint)
                .font(.system(size: 11))
                .foregroundStyle(NotchTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
