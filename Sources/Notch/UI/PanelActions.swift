import Foundation

/// Действия, которые панель не может выполнить сама: они живут в приложении
/// (окно настроек, звук, хранилище буфера). Собраны в один тип, чтобы не
/// тащить через панель половину зависимостей.
@MainActor
struct PanelActions {
    var openSettingsWindow: () -> Void
    var clearClipboardHistory: () -> Void
    var previewSound: (NotchSound) -> Void
    /// Раскрыть панель на нужном модуле — по клику на плашке события.
    var openModule: (String) -> Void
}
