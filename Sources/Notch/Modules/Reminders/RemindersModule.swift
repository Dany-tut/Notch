import SwiftUI

/// Напоминания: невыполненное по сроку, галочка и быстрое добавление.
struct RemindersModule: NotchModule {
    let id = "reminders"
    let titleKey: L10n.Key = .moduleReminders
    let symbol = "checklist"
    var preferredHeight: CGFloat { 248 }

    let store: RemindersStore

    func makeContent() -> some View {
        RemindersContent(store: store)
    }
}

private struct RemindersContent: View {
    @ObservedObject var store: RemindersStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        content
            // Видимость модуля и есть его `onAppear`/`onDisappear`: панель
            // вынимает содержимое и при сворачивании, и при смене вкладки.
            .onAppear { store.resume() }
            .onDisappear { store.suspend() }
    }

    @ViewBuilder
    private var content: some View {
        switch store.access {
        case .unknown:
            VStack(spacing: 8) {
                Image(systemName: "checklist")
                    .font(.system(size: 20))
                    .foregroundStyle(NotchTheme.textTertiary)
                Text(settings.t(.remindersAskTitle))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NotchTheme.textSecondary)
                PromptButton(title: settings.t(.remindersAskButton)) { store.requestAccess() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .denied:
            VStack(spacing: 8) {
                EmptyState(
                    symbol: "exclamationmark.circle",
                    title: settings.t(.remindersDeniedTitle),
                    hint: settings.t(.remindersDeniedHint)
                )
                PromptButton(title: settings.t(.remindersOpenSettings)) {
                    store.openSystemSettings()
                }
                .padding(.bottom, 6)
            }
        case .unavailable:
            EmptyState(
                symbol: "exclamationmark.circle",
                title: settings.t(.remindersUnbundledTitle),
                hint: settings.t(.remindersUnbundledHint)
            )
        case .granted:
            VStack(spacing: 8) {
                list
                AddField(store: store)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private var list: some View {
        if store.items.isEmpty {
            EmptyState(
                symbol: "checkmark.circle",
                title: settings.t(.remindersEmptyTitle),
                hint: settings.t(.remindersEmptyHint)
            )
        } else {
            BlurredEdgeScrollView(.vertical, leading: 18, trailing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(store.items) { item in
                        ReminderRow(
                            item: item,
                            list: store.showsLists ? store.lists[item.listID] : nil,
                            isDone: store.completing.contains(item.id)
                        ) {
                            store.toggle(item)
                        }
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
            .frame(maxHeight: .infinity)
        }
    }
}

private struct ReminderRow: View {
    let item: RemindersStore.Item
    let list: RemindersStore.List?
    let isDone: Bool
    let toggle: () -> Void
    @EnvironmentObject private var settings: AppSettings
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { toggle() }
            } label: {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(isDone ? tint : NotchTheme.textTertiary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .notchHelp(settings.t(isDone ? .remindersUndo : .remindersComplete))

            Text(item.title)
                .font(.system(size: 12))
                .foregroundStyle(isDone ? NotchTheme.textTertiary : NotchTheme.textPrimary)
                .strikethrough(isDone, color: NotchTheme.textTertiary)
                .lineLimit(1)

            Spacer(minLength: 4)

            if let due = dueLabel {
                Text(due)
                    .font(.system(size: 10, weight: overdue ? .semibold : .regular))
                    .foregroundStyle(overdue ? ActivityTint.red : NotchTheme.textTertiary)
                    .lineLimit(1)
            }

            if let list {
                Circle()
                    .fill(list.color)
                    .frame(width: 6, height: 6)
                    .notchHelp(list.title)
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 24)
        .opacity(isDone ? 0.6 : 1)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovered ? Color.white.opacity(0.05) : .clear)
        }
        .onHover { isHovered = $0 }
    }

    private var overdue: Bool { !isDone && item.isOverdue() }

    private var tint: Color { ModuleTint.color(for: "reminders") ?? NotchTheme.textPrimary }

    /// «Сегодня 14:00», «Завтра», «12 окт.» — коротко, чтобы строка не
    /// уступала место сроку.
    private var dueLabel: String? {
        guard let due = item.due else { return nil }
        let calendar = Calendar.current
        let time = item.hasTime ? due.formatted(date: .omitted, time: .shortened) : nil
        let day: String
        if calendar.isDateInToday(due) {
            day = settings.t(.remindersToday)
        } else if calendar.isDateInTomorrow(due) {
            day = settings.t(.remindersTomorrow)
        } else if calendar.isDateInYesterday(due) {
            day = settings.t(.remindersYesterday)
        } else {
            var style = Date.FormatStyle().day().month(.abbreviated)
            if !calendar.isDate(due, equalTo: Date(), toGranularity: .year) { style = style.year() }
            day = due.formatted(style)
        }
        return [day, time].compactMap { $0 }.joined(separator: " ")
    }
}

/// Поле внизу: Return — и напоминание в списке по умолчанию.
private struct AddField: View {
    @ObservedObject var store: RemindersStore
    @EnvironmentObject private var settings: AppSettings
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NotchTheme.textTertiary)
            TextField(settings.t(.remindersAddPlaceholder), text: $store.draft)
                .focused($isFocused)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(NotchTheme.textPrimary)
                .onTapGesture { NotchPanel.focusForTyping() }
                .onSubmit { store.add() }
        }
        .padding(.horizontal, 10)
        .frame(height: NotchTheme.rowHeight)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.06))
        }
    }
}

/// Кнопка под пустым состоянием — такая же, как у Календаря и Зеркала.
private struct PromptButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(NotchTheme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(NotchTheme.accentSelection))
    }
}
