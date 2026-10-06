import SwiftUI

/// Конвертер единиц: величина сверху, слева «из» и «в», справа — то же
/// число во всех единицах величины. Щелчок по любому значению копирует.
struct ConverterModule: NotchModule {
    static let moduleID = "converter"
    static let railSymbol = "ruler"

    let id = ConverterModule.moduleID
    let titleKey: L10n.Key = .moduleConverter
    let symbol = ConverterModule.railSymbol
    var preferredHeight: CGFloat { 248 }

    let store: ConverterStore
    let clipboard: ClipboardStore

    func makeContent() -> some View {
        ConverterContent(store: store, clipboard: clipboard)
    }
}

private struct ConverterContent: View {
    @ObservedObject var store: ConverterStore
    let clipboard: ClipboardStore
    @EnvironmentObject private var settings: AppSettings

    @FocusState private var isFocused: Bool
    /// Что только что скопировано: индекс единицы в списке, `-1` — итог
    /// слева. Галочка держится секунду и гаснет.
    @State private var copied: Int?

    private var format: ConverterFormat { ConverterFormat(language: settings.language) }
    private var value: Double? { format.parse(store.input) }
    private var tint: Color { ModuleTint.color(for: ConverterModule.moduleID) ?? NotchTheme.textPrimary }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            categories

            HStack(alignment: .top, spacing: 16) {
                pair.frame(width: 214)
                list
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Панель не активирующая: без ключевого окна набранное ушло бы в
        // приложение под ней.
        .onAppear {
            NotchPanel.focusForTyping()
            isFocused = true
        }
    }

    // MARK: - Величины

    private var categories: some View {
        HStack(spacing: 4) {
            ForEach(ConverterCategory.allCases) { category in
                CategoryChip(
                    title: settings.t(category.titleKey),
                    symbol: category.symbol,
                    isSelected: store.category == category,
                    tint: tint
                ) {
                    withAnimation(.snappy(duration: 0.22)) { store.category = category }
                }
            }
        }
    }

    // MARK: - Из и в

    private var pair: some View {
        VStack(spacing: 4) {
            UnitCard {
                TextField("0", text: $store.input)
                    .focused($isFocused)
                    .textFieldStyle(.plain)
                    .font(Self.valueFont)
                    .foregroundStyle(value == nil && !store.input.isEmpty ? ActivityTint.red : NotchTheme.textPrimary)
                    .onTapGesture { NotchPanel.focusForTyping() }
            } menu: {
                UnitMenu(
                    units: store.category.units,
                    selected: store.sourceIndex,
                    format: format
                ) { store.sourceIndex = $0 }
            }

            Button {
                withAnimation(.snappy(duration: 0.2)) { store.swap() }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(NotchTheme.textTertiary)
                    .frame(width: 26, height: 18)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .notchHelp(settings.t(.converterSwap))

            UnitCard(highlight: tint.opacity(0.14)) {
                Button {
                    copy(-1, store.convert(value ?? 0), store.target)
                } label: {
                    HStack(spacing: 6) {
                        Text(value.map { format.number(store.convert($0)) } ?? "—")
                            .font(Self.valueFont)
                            .foregroundStyle(NotchTheme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Spacer(minLength: 0)
                        CopyMark(isCopied: copied == -1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(value == nil)
                .notchHelp(settings.t(.converterCopyHint))
            } menu: {
                UnitMenu(
                    units: store.category.units,
                    selected: store.targetIndex,
                    format: format
                ) { store.targetIndex = $0 }
            }

            Text(format.name(store.target))
                .font(.system(size: 10))
                .foregroundStyle(NotchTheme.textTertiary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 4)
        }
    }

    // MARK: - Все единицы

    @ViewBuilder
    private var list: some View {
        if let value {
            NotchScroll {
                VStack(spacing: 1) {
                    ForEach(store.conversions(of: value), id: \.index) { item in
                        ConversionRow(
                            number: format.number(item.value),
                            symbol: format.symbol(item.unit),
                            name: format.name(item.unit),
                            isTarget: item.index == store.targetIndex,
                            isCopied: copied == item.index,
                            tint: tint
                        ) {
                            copy(item.index, item.value, item.unit)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        } else {
            EmptyState(
                symbol: "number",
                title: settings.t(.converterEnterNumber),
                hint: settings.t(.converterEnterNumberHint)
            )
        }
    }

    private func copy(_ index: Int, _ value: Double, _ unit: Dimension) {
        clipboard.copy(format.copyText(value, unit))
        copied = index
        Task {
            try? await Task.sleep(for: .seconds(1.1))
            if copied == index { copied = nil }
        }
    }

    fileprivate static let valueFont = Font.system(size: 22, weight: .semibold, design: .rounded)
}

/// Величина: значок, а у выбранной — ещё и название. Восемь подписанных
/// таблеток в ряд не помещаются, восемь значков с одной подписью — да.
private struct CategoryChip: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let tint: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .medium))
                if isSelected {
                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .foregroundStyle(isSelected ? tint : (isHovered ? NotchTheme.textPrimary : NotchTheme.textSecondary))
            .padding(.horizontal, isSelected ? 10 : 8)
            .frame(height: 24)
            .background {
                Capsule().fill(
                    isSelected
                        ? tint.opacity(0.16)
                        : (isHovered ? NotchTheme.accentSelection.opacity(0.5) : .clear)
                )
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .notchHelp(isSelected ? nil : title)
    }
}

/// Карточка «число + единица». Одна на поле ввода и на итог: строки
/// должны стоять одна под другой одинаковыми, иначе пара не читается
/// парой.
private struct UnitCard<Value: View, Trailing: View>: View {
    var highlight: Color = Color.white.opacity(0.06)
    @ViewBuilder let value: () -> Value
    @ViewBuilder let menu: () -> Trailing

    var body: some View {
        HStack(spacing: 8) {
            value()
                .frame(maxWidth: .infinity, alignment: .leading)
            menu()
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
        .background(highlight, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct UnitMenu: View {
    let units: [Dimension]
    let selected: Int
    let format: ConverterFormat
    let onSelect: (Int) -> Void

    var body: some View {
        // Своя подпись вместо Menu(title:) — по той же причине, что и у
        // языков в переводчике: шрифт до системного заголовка не доходит.
        Menu {
            ForEach(Array(units.enumerated()), id: \.offset) { index, unit in
                Button("\(format.name(unit)) (\(format.symbol(unit)))") { onSelect(index) }
            }
        } label: {
            HStack(spacing: 3) {
                Text(format.symbol(units[selected]))
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(NotchTheme.textSecondary)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

private struct ConversionRow: View {
    let number: String
    let symbol: String
    let name: String
    let isTarget: Bool
    let isCopied: Bool
    let tint: Color
    let action: () -> Void

    @EnvironmentObject private var settings: AppSettings
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(number)
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(isTarget ? tint : NotchTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(NotchTheme.textSecondary)
                    .lineLimit(1)
                    .fixedSize()

                Spacer(minLength: 8)

                if isCopied || isHovered {
                    CopyMark(isCopied: isCopied)
                } else {
                    Text(name)
                        .font(.system(size: 11))
                        .foregroundStyle(NotchTheme.textTertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHovered ? NotchTheme.accentSelection.opacity(0.6) : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .notchHelp(settings.t(.converterCopyHint))
    }
}

/// Значок копирования, на секунду сменяющийся галочкой.
private struct CopyMark: View {
    let isCopied: Bool

    var body: some View {
        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(isCopied ? ActivityTint.green : NotchTheme.textTertiary)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 16)
    }
}
