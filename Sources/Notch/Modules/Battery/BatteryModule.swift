import SwiftUI

/// Батарея: заряд Мака крупно, подключённые устройства — списком.
struct BatteryModule: NotchModule {
    let id = "battery"
    let titleKey: L10n.Key = .moduleBattery
    let symbol = "batteryblock"

    let store: BatteryStore

    func makeContent() -> some View {
        BatteryContent(store: store)
    }
}

private struct BatteryContent: View {
    @ObservedObject var store: BatteryStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            mac

            if store.devices.isEmpty {
                Text(settings.t(.batteryNoDevices))
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTheme.textTertiary)
            } else {
                BlurredEdgeScrollView(.vertical, leading: 18, trailing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(store.devices) { device in
                            DeviceRow(device: device)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Заряд мог измениться, пока панель была закрыта.
        .onAppear { store.reload() }
    }

    private var mac: some View {
        HStack(spacing: 10) {
            Image(systemName: store.isCharging ? "battery.100percent.bolt" : "laptopcomputer")
                .font(.system(size: 14))
                .foregroundStyle(BatteryColor.of(store.macLevel, charging: store.isCharging))

            VStack(alignment: .leading, spacing: 4) {
                Text("\(Int(store.macLevel * 100))%")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NotchTheme.textPrimary)
                BatteryBar(level: store.macLevel, charging: store.isCharging)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct DeviceRow: View {
    let device: BatteryStore.Device

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: device.symbol)
                .font(.system(size: 12))
                .foregroundStyle(NotchTheme.textSecondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(.system(size: 12))
                    .foregroundStyle(NotchTheme.textSecondary)
                    .lineLimit(1)
                BatteryBar(level: device.level, charging: false)
            }

            Spacer(minLength: 0)

            // У наушников показываем стороны отдельно: садятся они неравномерно.
            Text(Self.detail(device))
                .font(.system(size: 11))
                .foregroundStyle(NotchTheme.textTertiary)
        }
    }

    private static func detail(_ device: BatteryStore.Device) -> String {
        var parts: [String] = []
        if let left = device.left { parts.append("L \(Int(left * 100))%") }
        if let right = device.right { parts.append("R \(Int(right * 100))%") }
        if let caseLevel = device.caseLevel { parts.append("◻︎ \(Int(caseLevel * 100))%") }
        if parts.isEmpty { parts.append("\(Int(device.level * 100))%") }
        return parts.joined(separator: "  ")
    }
}

/// Полоска заряда: цвет меняется на низком уровне, чтобы это было видно
/// боковым зрением, а не только по цифре.
private struct BatteryBar: View {
    let level: Double
    let charging: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10))
                Capsule()
                    .fill(BatteryColor.of(level, charging: charging))
                    .frame(width: proxy.size.width * min(max(level, 0), 1))
            }
        }
        .frame(height: 4)
    }
}

private enum BatteryColor {
    static func of(_ level: Double, charging: Bool) -> Color {
        if charging { return ActivityTint.green }
        if level <= 0.1 { return ActivityTint.red }
        if level <= 0.2 { return ActivityTint.orange }
        return ActivityTint.green
    }
}
