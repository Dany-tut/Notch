import AppKit

/// Отправка системных медиа-клавиш.
///
/// Это обход закрытого `MediaRemote`: читать, что играет, мы у системы не
/// можем, но нажать «пауза» — можем. Клавишу получает то приложение,
/// которое владеет сессией Now Playing, то есть любой источник, включая
/// браузер. Требует разрешения «Универсальный доступ».
@MainActor
enum MediaKeys {
    /// Коды из IOKit/hidsystem/ev_keymap.h.
    private enum Code: Int32 {
        case playPause = 16
        case next = 19
        case previous = 20
    }

    static func send(_ command: TransportCommand) {
        let code = code(for: command)
        post(code, isDown: true, pid: nil)
        post(code, isDown: false, pid: nil)
    }

    /// Адресная отправка конкретному приложению.
    ///
    /// Нужна, когда плеер выбран руками: обычная медиа-клавиша уходит
    /// владельцу сессии Now Playing, а это может быть совсем другой
    /// источник. Приложение должно слушать события само — не все умеют.
    static func send(_ command: TransportCommand, to pid: pid_t) {
        let code = code(for: command)
        post(code, isDown: true, pid: pid)
        post(code, isDown: false, pid: pid)
    }

    private static func code(for command: TransportCommand) -> Code {
        switch command {
        case .playPause: .playPause
        case .next: .next
        case .previous: .previous
        }
    }

    /// Разрешён ли нам синтез событий. Без этого нажатия молча не дойдут.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Показывает системный запрос на «Универсальный доступ».
    ///
    /// Системный диалог показывается только один раз за всю жизнь записи в
    /// TCC. Если его уже отклоняли, он молча не появится — поэтому следом
    /// открываем нужный раздел настроек.
    static func requestTrust() {
        NSApp.activate(ignoringOtherApps: true)
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let granted = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        guard !granted else { return }

        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
        if let url { NSWorkspace.shared.open(url) }
    }

    /// Файл, который система запомнила в списке. Именно его надо искать в
    /// «Универсальном доступе»: одноимённых строк там может быть несколько,
    /// а считается только эта.
    static var bundleURL: URL { Bundle.main.bundleURL }

    /// Открывает Finder на бандле — оттуда его можно перетащить в список.
    static func revealBundle() {
        NSWorkspace.shared.activateFileViewerSelecting([bundleURL])
    }

    /// Убирает запись из TCC целиком.
    ///
    /// Нужно, когда строка в настройках включена, а доступа всё равно нет:
    /// ad-hoc подпись меняется при каждой сборке, и старая запись перестаёт
    /// совпадать с приложением. После сброса система спросит заново.
    static func resetTrust() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task.arguments = ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? "com.dany.notch"]
        try? task.run()
        task.waitUntilExit()
        requestTrust()
    }

    private static func post(_ code: Code, isDown: Bool, pid: pid_t?) {
        // Формат NX_SYSDEFINED: состояние клавиши упаковано в data1.
        let state: Int32 = isDown ? 0xA : 0xB
        let data1 = Int((code.rawValue << 16) | (state << 8))
        let flags = NSEvent.ModifierFlags(rawValue: UInt(isDown ? 0xA00 : 0xB00))

        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        ) else { return }

        if let pid {
            event.cgEvent?.postToPid(pid)
        } else {
            event.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
