import AppKit

/// Окно панели.
///
/// Ключевые свойства:
/// - `.nonactivatingPanel` — клик по панели не отбирает фокус у активного приложения;
/// - уровень выше меню-бара, чтобы панель перекрывала вырез;
/// - живёт на всех Spaces и поверх полноэкранных приложений;
/// - прозрачное и безрамочное: всю отрисовку делает SwiftUI.
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
    }

    // Безрамочное окно по умолчанию не может стать key — нам это нужно
    // для будущего поиска/ввода внутри модулей.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

extension NotchPanel {
    /// Панель не активирующая, поэтому клик по текстовому полю сам по себе
    /// не даёт ей фокус клавиатуры — просим его явно.
    @MainActor
    static func focusForTyping() {
        guard let panel = NSApp.windows.compactMap({ $0 as? NotchPanel }).first,
              !panel.isKeyWindow else { return }
        panel.makeKeyAndOrderFront(nil)
    }

    /// Отдаёт фокус обратно приложению, из которого мы его забрали. Отказаться
    /// от статуса key иначе нельзя, поэтому прячем панель и тут же показываем:
    /// key возвращается прежнему окну, а панель остаётся на экране.
    @MainActor
    static func releaseFocus() {
        guard let panel = NSApp.windows.compactMap({ $0 as? NotchPanel }).first,
              panel.isKeyWindow else { return }
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }
}
