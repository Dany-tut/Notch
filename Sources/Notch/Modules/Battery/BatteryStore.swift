import Foundation
import IOKit

/// Заряд самого Мака и всего, что к нему подключено по Bluetooth.
///
/// Публичного API для наушников нет: их уровень лежит в IORegistry, который
/// система заполняет для устройств с поддержкой батарейных отчётов —
/// AirPods, мыши, клавиатуры, геймпады. Чего там нет, того мы не покажем.
@MainActor
final class BatteryStore: ObservableObject {
    struct Device: Identifiable, Equatable {
        let id: String
        let name: String
        let symbol: String
        /// Общий уровень. У AirPods — минимум из наушников, чтобы одна
        /// строка отвечала на вопрос «надолго ли хватит».
        let level: Double
        /// Отдельные уровни, если устройство их сообщает.
        var left: Double?
        var right: Double?
        var caseLevel: Double?
    }

    @Published private(set) var macLevel: Double = 0
    @Published private(set) var isCharging = false
    @Published private(set) var devices: [Device] = []

    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        reload()
        // Заряд меняется медленно: чаще раза в полминуты смотреть незачем.
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    func reload() {
        if let state = ActivityMonitors.powerState() {
            macLevel = state.percentage
            isCharging = state.isPluggedIn
        }
        devices = Self.bluetoothDevices()
    }

    /// Обход IORegistry: служба батарейных отчётов заводится на каждое
    /// подключённое устройство, которое умеет о себе рассказывать.
    private static func bluetoothDevices() -> [Device] {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("AppleDeviceManagementHIDEventService")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(iterator) }

        var result: [Device] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let properties = Self.properties(of: service) else { continue }

            let name = (properties["Product"] as? String)
                ?? (properties["DeviceAddress"] as? String)
                ?? "—"

            let left = Self.percent(properties["BatteryPercentLeft"])
            let right = Self.percent(properties["BatteryPercentRight"])
            let caseLevel = Self.percent(properties["BatteryPercentCase"])
            let single = Self.percent(properties["BatteryPercent"])

            // Пустые нули IORegistry отдаёт и для устройств без батареи —
            // такие в список не берём.
            let levels = [left, right, single].compactMap { $0 }.filter { $0 > 0 }
            guard let level = levels.min() else { continue }

            result.append(
                Device(
                    id: (properties["DeviceAddress"] as? String) ?? name,
                    name: name,
                    symbol: ActivityMonitors.symbol(forDeviceNamed: name),
                    level: level,
                    left: left.flatMap { $0 > 0 ? $0 : nil },
                    right: right.flatMap { $0 > 0 ? $0 : nil },
                    caseLevel: caseLevel.flatMap { $0 > 0 ? $0 : nil }
                )
            )
        }
        return result.sorted { $0.name < $1.name }
    }

    private static func properties(of service: io_object_t) -> [String: Any]? {
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0)
            == KERN_SUCCESS else { return nil }
        return unmanaged?.takeRetainedValue() as? [String: Any]
    }

    /// IORegistry отдаёт проценты целыми числами, а нам удобнее доля.
    private static func percent(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber else { return nil }
        return number.doubleValue / 100
    }
}
