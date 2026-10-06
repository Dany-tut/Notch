import AppKit
import Carbon.HIToolbox

/// Сочетание клавиш в виде, который переживает перезапуск.
struct KeyCombo: Codable, Equatable, Hashable {
    /// Виртуальный код клавиши (не символ: он зависит от раскладки).
    var keyCode: UInt32
    /// Маска модификаторов в терминах Carbon.
    var modifiers: UInt32

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }

        // Без модификатора это не глобальный хоткей, а перехват обычной клавиши.
        guard carbon != 0 else { return nil }
        self.keyCode = UInt32(event.keyCode)
        self.modifiers = carbon
    }

    /// Человекочитаемая запись: ⌥⇧Space.
    var display: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + Self.keyName(keyCode)
    }

    /// Имена клавиш, которые нельзя получить из раскладки.
    private static let specialNames: [UInt32: String] = [
        UInt32(kVK_Space): "Space",
        UInt32(kVK_Return): "↩",
        UInt32(kVK_Tab): "⇥",
        UInt32(kVK_Escape): "⎋",
        UInt32(kVK_Delete): "⌫",
        UInt32(kVK_LeftArrow): "←",
        UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑",
        UInt32(kVK_DownArrow): "↓"
    ]

    static func keyName(_ keyCode: UInt32) -> String {
        if let special = specialNames[keyCode] { return special }
        return layoutCharacter(keyCode)?.uppercased() ?? "Key \(keyCode)"
    }

    /// Символ клавиши в текущей раскладке — чтобы на русской показывать
    /// то же, что напечатано на клавише.
    private static func layoutCharacter(_ keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)

        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return OSStatus(paramErr)
            }
            return UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysBit),
                &deadKeys,
                characters.count,
                &length,
                &characters
            )
        }

        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }
}

extension KeyCombo {
    /// ⌥Space — открыть панель.
    static let defaultTogglePanel = KeyCombo(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(optionKey)
    )
    /// ⌥V — открыть буфер обмена.
    static let defaultClipboard = KeyCombo(
        keyCode: UInt32(kVK_ANSI_V),
        modifiers: UInt32(optionKey)
    )
}
