import AppKit
import SwiftUI

/// Заметка на полях: поле, которое помнит написанное и не спрашивает,
/// куда это сохранить.
struct NotesModule: NotchModule {
    let id = "notes"
    let titleKey: L10n.Key = .moduleNotes
    let symbol = "square.and.pencil"

    let store: NotesStore

    func makeContent() -> some View {
        NotesContent(store: store)
    }

    /// Копировать и очистить — в строке заголовка: обе кнопки про весь
    /// текст целиком, а не про место, где стоит курсор.
    func makeAccessory() -> some View {
        NotesAccessory(store: store)
    }

    var accessoryWidth: CGFloat { 52 }
}

private struct NotesAccessory: View {
    @ObservedObject var store: NotesStore
    @EnvironmentObject private var settings: AppSettings

    @State private var didCopy = false

    var body: some View {
        if !store.text.isEmpty {
            HStack(spacing: 2) {
                NotesButton(
                    symbol: didCopy ? "checkmark" : "doc.on.doc",
                    help: settings.t(.notesCopy)
                ) {
                    let board = NSPasteboard.general
                    board.clearContents()
                    board.setString(store.text, forType: .string)
                    didCopy = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.2))
                        didCopy = false
                    }
                }
                NotesButton(symbol: "trash", help: settings.t(.notesClear)) {
                    store.clear()
                }
            }
        }
    }
}

private struct NotesButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isHovered ? NotchTheme.textPrimary : NotchTheme.textTertiary)
                .frame(width: 22, height: 20)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovered ? NotchTheme.accentSelection : .clear)
                }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .notchHelp(help)
    }
}

private struct NotesContent: View {
    @ObservedObject var store: NotesStore
    @EnvironmentObject private var settings: AppSettings

    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
                // Подсказка лежит под полем: у `TextEditor` своего
                // placeholder нет, а пустое чёрное поле ничего не говорит
                // о том, что в него можно писать.
            if store.text.isEmpty {
                Text(settings.t(.notesPlaceholder))
                    .font(.system(size: 12))
                    .foregroundStyle(NotchTheme.textTertiary)
                    // Ровно по первой букве набора: `TextEditor`
                    // держит свой внутренний отступ, и подсказка
                    // должна встать на её место, а не рядом с кареткой.
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $store.text)
                .focused($isFocused)
                .font(.system(size: 12))
                .foregroundStyle(NotchTheme.textPrimary)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        // Счётчик лежит внутри поля, в дальнем углу. Строкой под полем он
        // отнимал у поля высоту — и пустую, пока в заметке ничего нет:
        // снизу оставался зазор шире, чем поля панели по остальным
        // сторонам, будто поле не дотянулось до низа.
        .overlay(alignment: .bottomTrailing) {
            Text(counter)
                .font(.system(size: 10))
                .foregroundStyle(NotchTheme.textTertiary)
                .monospacedDigit()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .allowsHitTesting(false)
        }
        // Панель не активирующая: без этого набранное уходит в то
        // приложение, которое было впереди. Полка забирает фокус ровно
        // так же — и ради того же.
        .onHover { hovering in
            if hovering { NotchPanel.focusForTyping() }
        }
        .onAppear {
            NotchPanel.focusForTyping()
            isFocused = true
        }
    }

    /// Строки и знаки: в заметке на полях чаще всего считают именно их.
    private var counter: String {
        guard !store.text.isEmpty else { return "" }
        let lines = store.text.split(separator: "\n", omittingEmptySubsequences: false).count
        return "\(lines) · \(store.text.count)"
    }
}
