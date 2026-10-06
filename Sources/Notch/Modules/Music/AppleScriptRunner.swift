import Foundation

/// Выполняет AppleScript в стороне от главного потока.
///
/// Один вопрос к Music — это Apple Event туда и обратно, и стоит он около
/// 25 мс; вместе с обложкой тик доходит до полусотни. Раньше
/// опрос шёл прямо на главном потоке раз в полторы секунды, и каждый такой
/// тик съедал несколько кадров: панель дёргалась на ровном месте, и вина
/// выглядела как вина анимаций, хотя кривые были ни при чём.
///
/// Очередь последовательная намеренно: `NSAppleScript` не потокобезопасен,
/// да и спрашивать плеер в несколько голосов незачем.
final class AppleScriptRunner: @unchecked Sendable {
    struct Outcome {
        let descriptor: NSAppleEventDescriptor?
        /// Код ошибки AppleScript. По нему панель отличает запрет доступа
        /// от молчащего плеера.
        let errorCode: Int?
    }

    private let queue = DispatchQueue(label: "com.dany.notch.applescript", qos: .utility)
    /// Скомпилированные скрипты: текст от опроса к опросу один и тот же,
    /// а компиляция — заметная часть первого вызова.
    private var compiled: [String: NSAppleScript] = [:]

    func run(_ source: String) async -> Outcome {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: execute(source))
            }
        }
    }

    /// Без ожидания ответа: командам транспорта он не нужен, а ждать их
    /// значит держать опрос.
    func fire(_ source: String) {
        queue.async { [self] in _ = execute(source) }
    }

    private func execute(_ source: String) -> Outcome {
        let script: NSAppleScript
        if let cached = compiled[source] {
            script = cached
        } else {
            guard let fresh = NSAppleScript(source: source) else {
                return Outcome(descriptor: nil, errorCode: nil)
            }
            compiled[source] = fresh
            script = fresh
        }

        var error: NSDictionary?
        let descriptor = script.executeAndReturnError(&error)
        guard let error else { return Outcome(descriptor: descriptor, errorCode: nil) }
        return Outcome(descriptor: nil, errorCode: error[NSAppleScript.errorNumber] as? Int)
    }
}
