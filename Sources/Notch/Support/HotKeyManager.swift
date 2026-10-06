import AppKit
import Carbon.HIToolbox

/// Глобальные горячие клавиши через Carbon.
///
/// Carbon здесь не архаизм, а осознанный выбор: `RegisterEventHotKey` —
/// единственный способ поймать сочетание системно, не требуя разрешения
/// «Универсальный доступ», в отличие от перехвата событий.
@MainActor
final class HotKeyManager {
    /// Что делает горячая клавиша. Модулей в списке столько, сколько их
    /// включено, — поэтому не простое перечисление: набор действий
    /// собирается на ходу, из каталога модулей.
    enum Action: Hashable, Identifiable, Sendable {
        /// Открыть или закрыть панель на той вкладке, где её оставили.
        case togglePanel
        /// Открыть панель сразу на своём модуле.
        case module(String)

        var id: String { rawValue }

        /// Ключ в настройках. У модуля с префиксом — иначе идентификатор
        /// модуля мог бы совпасть с именем общего действия.
        var rawValue: String {
            switch self {
            case .togglePanel: return "togglePanel"
            case .module(let id): return "module.\(id)"
            }
        }

        init?(rawValue: String) {
            if rawValue == "togglePanel" {
                self = .togglePanel
            } else if rawValue.hasPrefix("module.") {
                self = .module(String(rawValue.dropFirst("module.".count)))
            } else {
                return nil
            }
        }

        /// Иконка рядом с записью в настройках: у модуля — его же, чтобы
        /// строку узнавали по той картинке, что стоит в рейле.
        @MainActor
        var symbol: String {
            switch self {
            case .togglePanel:
                return "keyboard"
            case .module(let id):
                return ModuleCatalog.descriptors.first { $0.id == id }?.symbol ?? "keyboard"
            }
        }
    }

    private struct Registration {
        let ref: EventHotKeyRef
        let action: Action
    }

    private var registrations: [UInt32: Registration] = [:]
    /// Номер для следующего сочетания. Carbon различает клавиши по числу,
    /// а действий теперь столько, сколько модулей, — раздаём по порядку,
    /// а не считаем от имени: хеш строки может совпасть у двух действий.
    private var nextIdentifier: UInt32 = 1
    private var handler: EventHandlerRef?
    private var onTrigger: ((Action) -> Void)?

    /// Общий реестр: Carbon-колбэк — это C-функция, объекта в неё не передать.
    private static var active: HotKeyManager?

    func start(onTrigger: @escaping (Action) -> Void) {
        self.onTrigger = onTrigger
        Self.active = self
        installHandler()
    }

    /// Перерегистрирует все сочетания. Вызывается и при старте, и при правке.
    func apply(_ combos: [Action: KeyCombo?]) {
        unregisterAll()
        for (action, combo) in combos {
            guard let combo else { continue }
            register(combo, for: action)
        }
    }

    // MARK: - Carbon

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                var id = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &id
                )
                guard status == noErr else { return status }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { HotKeyManager.active?.handle(id.id) }
                }
                return noErr
            },
            1,
            &spec,
            nil,
            &handler
        )
    }

    private func register(_ combo: KeyCombo, for action: Action) {
        let identifier = nextIdentifier
        nextIdentifier += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4E544348), id: identifier) // 'NTCH'

        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        // Сочетание может быть занято другим приложением — это не ошибка нашей
        // стороны, просто молча не регистрируем.
        guard status == noErr, let ref else { return }
        registrations[identifier] = Registration(ref: ref, action: action)
    }

    private func unregisterAll() {
        for registration in registrations.values {
            UnregisterEventHotKey(registration.ref)
        }
        registrations.removeAll()
        nextIdentifier = 1
    }

    private func handle(_ identifier: UInt32) {
        guard let registration = registrations[identifier] else { return }
        onTrigger?(registration.action)
    }
}
