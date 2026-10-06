import ServiceManagement

/// Автозапуск через `SMAppService`.
///
/// Работает только для настоящего бандла: из голого бинарника регистрировать
/// нечего, поэтому в режиме разработки переключатель будет недоступен.
@MainActor
enum LaunchAtLogin {
    static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Возвращает текст ошибки, если система отказала — молча глотать нельзя,
    /// пользователь должен понимать, почему переключатель не включился.
    @discardableResult
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
