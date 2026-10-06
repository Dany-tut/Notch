import SwiftUI

/// Подсказки при наведении — свои, а не системные.
///
/// `.help()` рисует жёлтую плашку системы: она приходит отдельным окном
/// поверх панели, живёт по своим таймингам и в чёрном корпусе читается
/// как чужая. Здесь та же роль, но своим слоем внутри панели: плашка
/// нарисована тем же чёрным по белому, что и всё остальное.
///
/// Слой один на всю панель, а не по плашке на кнопку. Кнопка только
/// сообщает наверх, что у неё есть что сказать и где она стоит
/// (`anchorPreference`), а рисует корень — иначе подсказку подрезала бы
/// первая же прокрутка или строка со своим `clipShape`.

/// Что показать и над чем. `Anchor` переводится в координаты того, кто
/// рисует слой, — поэтому положение считается уже в корне.
struct NotchTooltipItem {
    let text: String
    let anchor: Anchor<CGRect>
}

private struct NotchTooltipKey: PreferenceKey {
    static let defaultValue: [NotchTooltipItem] = []

    /// Наведение бывает вложенным: кнопка внутри строки, у которой тоже
    /// есть подсказка. Побеждает последняя — самая глубокая, то есть та,
    /// на которой действительно стоит курсор.
    static func reduce(value: inout [NotchTooltipItem], nextValue: () -> [NotchTooltipItem]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    /// Подсказка у этого элемента. Пустая или `nil` — подсказки нет.
    func notchHelp(_ text: String?) -> some View {
        modifier(NotchHelpModifier(text: text))
    }

    /// Слой, в котором подсказки рисуются. Ставится один раз в корне.
    func notchTooltipLayer() -> some View {
        modifier(NotchTooltipLayer())
    }
}

private struct NotchHelpModifier: ViewModifier {
    let text: String?

    /// Задержка перед показом — примерно системная. Без неё подсказки
    /// вспыхивают по дороге курсора через рейл.
    private static let delay: Duration = .milliseconds(450)

    @State private var isVisible = false
    @State private var pending: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .anchorPreference(key: NotchTooltipKey.self, value: .bounds) { anchor in
                guard isVisible, let text, !text.isEmpty else { return [] }
                return [NotchTooltipItem(text: text, anchor: anchor)]
            }
            .onHover { hovering in
                pending?.cancel()
                guard hovering else {
                    isVisible = false
                    return
                }
                pending = Task { @MainActor in
                    try? await Task.sleep(for: Self.delay)
                    guard !Task.isCancelled else { return }
                    isVisible = true
                }
            }
            // Кнопка может уехать из-под курсора сама — сменой модуля или
            // схлопыванием панели. `onHover` про это не сообщает, поэтому
            // гасим подсказку вместе с исчезновением её хозяина.
            .onDisappear {
                pending?.cancel()
                isVisible = false
            }
    }
}

private struct NotchTooltipLayer: ViewModifier {
    @Environment(\.notchCurtainInset) private var curtainInset

    @State private var size: CGSize = .zero

    /// Зазор между плашкой и элементом.
    private let gap: CGFloat = 6
    /// Насколько близко плашка вправе подойти к кромке панели.
    private let margin: CGFloat = 8

    func body(content: Content) -> some View {
        content.overlayPreferenceValue(NotchTooltipKey.self) { items in
            GeometryReader { proxy in
                if let item = items.last {
                    let target = proxy[item.anchor]
                    let origin = place(target: target, in: proxy.size)
                    NotchTooltipBubble(text: item.text)
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
                        .offset(x: origin.x, y: origin.y)
                        // Пока не измерена — не показываем: иначе первый
                        // кадр плашка стоит в левом верхнем углу.
                        .opacity(size == .zero ? 0 : 1)
                        .transition(.opacity)
                }
            }
            // Подсказка не ловит курсор: она стоит ровно там, где он, и
            // перехватив его, гасила бы сама себя.
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.12), value: items.last?.text)
        }
    }

    /// Плашка встаёт под элементом и по его середине. Не влезает снизу —
    /// переезжает наверх; не влезает вбок — прижимается к полям.
    ///
    /// Правый край считается по видимой части: пока полка выезжает,
    /// часть ширины ещё закрыта шторкой корпуса, и подсказка, встав по
    /// раскладке, оказалась бы за ней.
    private func place(target: CGRect, in bounds: CGSize) -> CGPoint {
        let visibleWidth = bounds.width - curtainInset
        let below = target.maxY + gap
        let above = target.minY - gap - size.height
        let y = below + size.height + margin <= bounds.height ? below : max(above, margin)
        let x = min(
            max(target.midX - size.width / 2, margin),
            max(visibleWidth - size.width - margin, margin)
        )
        return CGPoint(x: x, y: y)
    }
}

private struct NotchTooltipBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(NotchTheme.textPrimary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(white: 0.16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
            }
    }
}
