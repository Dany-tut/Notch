import AppKit
import SwiftUI

/// Обычное окно настроек. Приложение — агент без Dock, поэтому при показе
/// окна его приходится активировать вручную, иначе оно откроется без фокуса.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let settings: AppSettings
    private let snippets: SnippetStore
    private let music: NowPlayingCoordinator
    private let clipboard: ClipboardStore
    private let feedback: Feedback
    private var window: NSWindow?

    init(
        settings: AppSettings,
        snippets: SnippetStore,
        music: NowPlayingCoordinator,
        clipboard: ClipboardStore,
        feedback: Feedback
    ) {
        self.settings = settings
        self.snippets = snippets
        self.music = music
        self.clipboard = clipboard
        self.feedback = feedback
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.contentView = NSHostingView(
                rootView: SettingsView(
                    settings: settings,
                    snippets: snippets,
                    music: music,
                    clipboard: clipboard,
                    feedback: feedback
                )
            )
            window.isReleasedWhenClosed = false
            window.center()
            window.delegate = self
            self.window = window
        }

        window?.title = settings.t(.settingsTitle)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Заголовок окна — не SwiftUI, поэтому обновляем его отдельно.
    func refreshTitle() {
        window?.title = settings.t(.settingsTitle)
    }
}
