import AppKit
import SwiftUI

/// Зажатие открывает превью прямо под курсором.
///
/// Обычный `onLongPressGesture` вместе с кликом сообщает о срабатывании
/// только когда кнопку отпустили: «зажал» читалось как «нажал и зря подождал».
/// Поэтому отсчёт ведём сами — по сообщениям о нажатии и отпускании, —
/// а недостижимый порог в десять секунд нужен лишь затем, чтобы эти
/// сообщения приходили.
private struct HoldPreview: ViewModifier {
    let onTap: (() -> Void)?
    /// Показать или убрать превью. Оно живёт ровно столько, сколько кнопка
    /// зажата: отпустил — свернулось, отдельного клика на закрытие нет.
    let onPreview: (Bool) -> Void

    @EnvironmentObject private var settings: AppSettings

    @State private var hold: Task<Void, Never>?
    /// Превью уже открылось — значит, отпускание не должно считаться кликом.
    @State private var previewed = false

    static let duration: Duration = .milliseconds(350)

    func body(content: Content) -> some View {
        content
            .onTapGesture {
                guard !previewed else { previewed = false; return }
                onTap?()
            }
            .onLongPressGesture(minimumDuration: 10, maximumDistance: 6) {
                // Не случится: порог недостижим.
            } onPressingChanged: { pressing in
                hold?.cancel()
                guard pressing else {
                    hold = nil
                    // Флаг не гасим: клик придёт следом за этим же
                    // отпусканием, и копировать по нему нечего.
                    if previewed { withAnimation(.easeOut(duration: 0.14)) { onPreview(false) } }
                    return
                }
                previewed = false
                hold = Task {
                    try? await Task.sleep(for: Self.duration)
                    guard !Task.isCancelled else { return }
                    previewed = true
                    Feedback.tick(settings)
                    withAnimation(.easeOut(duration: 0.16)) { onPreview(true) }
                }
            }
            .onDisappear { hold?.cancel() }
    }
}

extension View {
    /// Клик и зажатие на одной карточке: первое действует, второе показывает.
    func holdToPreview(
        onTap: (() -> Void)? = nil,
        onPreview: @escaping (Bool) -> Void
    ) -> some View {
        modifier(HoldPreview(onTap: onTap, onPreview: onPreview))
    }
}

/// Крупное превью поверх содержимого модуля.
///
/// Не открывает файл и не зовёт чужое окно: показывает то же самое, что и
/// плитка, но во всю панель. Закрывается любым кликом — держать ради этого
/// отдельную кнопку не за что.
struct NotchPreview: View {
    /// Текст записи. У файла и картинки его нет — там кадр.
    var text: String?
    /// Подпись под кадром: имя файла или размер картинки.
    var caption: String?
    let hint: String
    /// Чем грузить кадр. Разные модули берут его по-разному: картинку
    /// буфера читает ImageIO, файл полки — QuickLook.
    var image: (() async -> NSImage?)?
    let onClose: () -> Void

    @State private var loaded: NSImage?

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let text {
                    ScrollView(.vertical) {
                        Text(text)
                            .font(.system(size: 12))
                            .foregroundStyle(NotchTheme.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .scrollIndicators(.never)
                } else if let loaded {
                    Image(nsImage: loaded)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let caption {
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Text(hint)
                .font(.system(size: 10))
                .foregroundStyle(NotchTheme.textTertiary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NotchTheme.background.opacity(0.94))
        .contentShape(Rectangle())
        .onTapGesture(perform: onClose)
        .transition(.opacity)
        .task {
            guard let image else { return }
            loaded = await image()
        }
    }
}
