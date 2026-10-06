import AppKit
import SwiftUI

/// Быстрые команды: список, поиск, запуск щелчком и избранное сверху.
struct ShortcutsModule: NotchModule {
    static let moduleID = "shortcuts"
    static let railSymbol = "square.2.layers.3d"

    let id = ShortcutsModule.moduleID
    let titleKey: L10n.Key = .moduleShortcuts
    let symbol = ShortcutsModule.railSymbol
    var preferredHeight: CGFloat { 248 }

    let store: ShortcutsStore

    func makeContent() -> some View {
        ShortcutsContent(store: store)
    }

    func makeModes() -> some View {
        ShortcutsModes(store: store)
    }

    func makeActions() -> some View {
        ShortcutsActions(store: store)
    }

    var modesWidth: CGFloat { 30 }
    var actionsWidth: CGFloat { 22 }
}

// MARK: - Строка заголовка

private struct ShortcutsModes: View {
    @ObservedObject var store: ShortcutsStore
    @EnvironmentObject private var settings: AppSettings
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        if !store.shortcuts.isEmpty {
            SearchField(
                text: $store.query,
                isOpen: $store.isSearching,
                placeholder: settings.t(.searchPlaceholder),
                help: settings.t(.searchPlaceholder),
                isFocused: $isSearchFocused
            )
        }
    }
}

/// «Обновить» — список берётся из кэша, и команду, только что созданную в
/// приложении Быстрые команды, можно подтянуть, не дожидаясь, пока он
/// залежится.
private struct ShortcutsActions: View {
    @ObservedObject var store: ShortcutsStore
    @EnvironmentObject private var settings: AppSettings
    @State private var isHovered = false

    var body: some View {
        Button(action: store.refresh) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isHovered ? NotchTheme.textPrimary : NotchTheme.textTertiary)
                .rotationEffect(.degrees(store.isLoading ? 360 : 0))
                .animation(
                    store.isLoading ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default,
                    value: store.isLoading
                )
                .frame(width: 22, height: 20)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovered ? NotchTheme.accentSelection : .clear)
                }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .notchHelp(settings.t(.shortcutsRefresh))
    }
}

// MARK: - Содержимое

private struct ShortcutsContent: View {
    @ObservedObject var store: ShortcutsStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // Список читается, только пока модуль на экране, — панель
            // вынимает содержимое и при сворачивании, и при смене вкладки.
            .onAppear { store.resume() }
            .onDisappear { store.suspend() }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .idle:
            ProgressView().controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            EmptyState(
                symbol: "exclamationmark.circle",
                title: settings.t(.shortcutsFailedTitle),
                hint: settings.t(.shortcutsFailedHint)
            )
        case .loaded:
            if store.shortcuts.isEmpty {
                VStack(spacing: 8) {
                    EmptyState(
                        symbol: ShortcutsModule.railSymbol,
                        title: settings.t(.shortcutsEmptyTitle),
                        hint: settings.t(.shortcutsEmptyHint)
                    )
                    OpenAppButton(title: settings.t(.shortcutsOpenApp))
                        .padding(.bottom, 6)
                }
            } else {
                list
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        let items = store.visible
        if items.isEmpty {
            EmptyState(
                symbol: "magnifyingglass",
                title: settings.t(.shortcutsNoResults),
                hint: store.query
            )
        } else {
            NotchScroll {
                VStack(spacing: 1) {
                    ForEach(items) { shortcut in
                        ShortcutRow(
                            shortcut: shortcut,
                            isFavorite: store.isFavorite(shortcut),
                            run: store.runs[shortcut.id],
                            onRun: { store.run(shortcut) },
                            onToggleFavorite: {
                                withAnimation(.snappy(duration: 0.22)) { store.toggleFavorite(shortcut) }
                            }
                        )
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private struct ShortcutRow: View {
    let shortcut: ShortcutsStore.Shortcut
    let isFavorite: Bool
    let run: ShortcutsStore.RunState?
    let onRun: () -> Void
    let onToggleFavorite: () -> Void

    @EnvironmentObject private var settings: AppSettings
    @State private var isHovered = false

    private var tint: Color { ModuleTint.color(for: ShortcutsModule.moduleID) ?? NotchTheme.textPrimary }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isFavorite ? "star.fill" : ShortcutsModule.railSymbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isFavorite ? tint : NotchTheme.textTertiary)
                .frame(width: 18, height: 18)

            Text(shortcut.name)
                .font(.system(size: 12))
                .foregroundStyle(isHovered ? NotchTheme.textPrimary : NotchTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            status

            // Звезда — только под курсором: в покое у строки нет ничего,
            // кроме имени и состояния запуска.
            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "star.slash" : "star")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(NotchTheme.textTertiary)
                    .frame(width: 18, height: 18)
                    .background(Squircle().fill(NotchTheme.accentSelection))
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
            .allowsHitTesting(isHovered)
            .notchHelp(settings.t(isFavorite ? .shortcutsUnpin : .shortcutsPin))
        }
        .padding(.horizontal, 8)
        .frame(height: NotchTheme.rowHeight)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isHovered ? NotchTheme.accentSelection.opacity(0.6) : .clear)
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(perform: onRun)
        .contextMenu {
            Button {
                onRun()
            } label: {
                Label(settings.t(.shortcutsRun), systemImage: "play")
            }
            Button(action: onToggleFavorite) {
                Label(
                    settings.t(isFavorite ? .shortcutsUnpin : .shortcutsPin),
                    systemImage: isFavorite ? "star.slash" : "star"
                )
            }
        }
        .animation(.snappy(duration: 0.2), value: run)
    }

    @ViewBuilder private var status: some View {
        switch run {
        case .running:
            ProgressView()
                .controlSize(.mini)
                .frame(width: 16, height: 16)
                .notchHelp(settings.t(.shortcutsRunning))
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(ActivityTint.green)
                .transition(.scale.combined(with: .opacity))
        case .failed(let message):
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(ActivityTint.red)
                .notchHelp(message.isEmpty ? settings.t(.shortcutsRunFailed) : message)
                .transition(.scale.combined(with: .opacity))
        case nil:
            EmptyView()
        }
    }
}

/// Пустой список — значит, команд ещё нет: ведём туда, где их делают.
private struct OpenAppButton: View {
    let title: String

    var body: some View {
        Button(title) {
            let url = URL(fileURLWithPath: "/System/Applications/Shortcuts.app")
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(NotchTheme.textPrimary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Capsule().fill(NotchTheme.accentSelection))
    }
}
