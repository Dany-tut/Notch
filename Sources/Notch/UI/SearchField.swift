import SwiftUI

/// Поиск в строке заголовка: свёрнутый — иконка рядом с переключателем
/// вида, развёрнутый — поле фиксированной ширины. Так он не занимает место,
/// пока не нужен, и открывается одним кликом вместо жеста прокрутки.
///
/// Ширина у развёрнутого именно фиксированная, а не «во всю строку»:
/// строку он теперь делит с названием раздела и рядом вкладок, и поле,
/// растущее до упора, выдавливало бы их из неё.
struct SearchField: View {
    @Binding var text: String
    @Binding var isOpen: Bool
    let placeholder: String
    let help: String
    /// Ширина развёрнутого поля вместе с иконкой и крестиком.
    var width: CGFloat = 150
    @FocusState.Binding var isFocused: Bool

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            Button(action: toggle) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 22, height: 20)
            }
            .buttonStyle(.plain)
            .notchHelp(isOpen ? nil : help)

            if isOpen {
                TextField(placeholder, text: $text)
                    .focused($isFocused)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTheme.textPrimary)
                    .onTapGesture { NotchPanel.focusForTyping() }
                    .onExitCommand { close() }

                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(NotchTheme.textTertiary)
                        .frame(width: 18, height: 20)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: isOpen ? width : 22, alignment: .leading)
        .frame(height: 20)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isOpen || isHovered ? NotchTheme.accentSelection : .clear)
        }
        .onHover { isHovered = $0 }
    }

    private var iconColor: Color {
        isOpen || isHovered ? NotchTheme.textPrimary : NotchTheme.textTertiary
    }

    private func toggle() {
        if isOpen {
            close()
        } else {
            isOpen = true
            NotchPanel.focusForTyping()
            isFocused = true
        }
    }

    private func close() {
        isFocused = false
        text = ""
        isOpen = false
    }
}
