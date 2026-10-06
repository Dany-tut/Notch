import SwiftUI

/// Переключатель вида — список или карточки, как в Finder.
///
/// Стоит в строке заголовка, рядом с названием раздела: выбор вида
/// относится ко всему списку, а не к отдельной записи, и у всех модулей
/// он лежит в одном месте — искать его по разным углам панели незачем.
struct LayoutToggle: View {
    @Binding var isGrid: Bool
    let listHelp: String
    let gridHelp: String

    var body: some View {
        HStack(spacing: 2) {
            option(symbol: "list.bullet", grid: false, help: listHelp)
            option(symbol: "square.grid.2x2", grid: true, help: gridHelp)
        }
    }

    private func option(symbol: String, grid: Bool, help: String) -> some View {
        LayoutOption(symbol: symbol, isOn: isGrid == grid, help: help) {
            isGrid = grid
        }
    }
}

private struct LayoutOption: View {
    let symbol: String
    let isOn: Bool
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isOn ? NotchTheme.textPrimary : NotchTheme.textTertiary)
                .frame(width: 22, height: 20)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isOn || isHovered ? NotchTheme.accentSelection : .clear)
                }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .notchHelp(help)
    }
}
