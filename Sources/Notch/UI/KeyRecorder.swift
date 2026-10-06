import AppKit
import SwiftUI

/// Поле записи сочетания клавиш.
///
/// Пока идёт запись, локальный монитор перехватывает нажатия до того, как
/// их увидит система меню, — иначе ⌘-сочетания уходили бы в меню окна.
struct KeyRecorder: View {
    @Binding var combo: KeyCombo?
    let recordTitle: String
    let recordingTitle: String
    let emptyTitle: String
    let clearTitle: String
    /// Цвета задаются снаружи: тот же виджет стоит и в светлом окне
    /// настроек, и на чёрной панели.
    var foreground: Color = .primary
    var background: Color = Color.primary.opacity(0.08)

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggle) {
                Text(label)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospaced()
                    .foregroundStyle(foreground)
                    .frame(minWidth: 90)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isRecording ? Color.accentColor.opacity(0.35) : background)
                    }
            }
            .buttonStyle(.plain)
            .help(recordTitle)

            if combo != nil && !isRecording {
                Button(clearTitle) { combo = nil }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
        .onDisappear(perform: stop)
    }

    private var label: String {
        if isRecording { return recordingTitle }
        return combo?.display ?? emptyTitle
    }

    private func toggle() {
        isRecording ? stop() : start()
    }

    private func start() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            guard event.type == .keyDown else { return event }

            // Esc отменяет запись, ничего не меняя.
            if event.keyCode == 53 {
                stop()
                return nil
            }
            if let captured = KeyCombo(event: event) {
                combo = captured
                stop()
            }
            // Событие дальше не пускаем: оно предназначалось нам.
            return nil
        }
    }

    private func stop() {
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
