import AppKit
import AudioToolbox
import Combine
import CoreAudio

/// Клавиши громкости и яркости — вместо системного окошка.
///
/// Системное окно висит посреди экрана или в углу, с ним ничего нельзя
/// сделать и через него не сменить выход звука. Мы перехватываем сами
/// клавиши (`NX_SYSDEFINED`), меняем уровень сами и показываем его
/// плашкой у выреза, а нажатие на плашку открывает музыку — там выбор
/// устройства вывода.
///
/// Перехват — активный event tap, а ему нужен «Универсальный доступ».
/// Поэтому функция включается только руками, и пока доступа нет, клавиши
/// идут системе как обычно. Всё, с чем справиться не можем (громкость у
/// HDMI-выхода без регулятора, яркость внешнего монитора), тоже отдаём
/// системе нетронутым: ничего хуже, чем было, случиться не должно.
@MainActor
final class LevelsController {
    private let center: ActivityCenter
    private let settings: AppSettings

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    /// Пока функция включена, а доступа нет — раз в несколько секунд
    /// проверяем, не выдали ли. Как только выдали, таймер уходит.
    private var trustTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    init(center: ActivityCenter, settings: AppSettings) {
        self.center = center
        self.settings = settings
    }

    func start() {
        apply()
        settings.$activityOptIn
            .dropFirst()
            .sink { [weak self] _ in
                // Отложенно: `@Published` присылает значение до записи.
                Task { @MainActor in self?.apply() }
            }
            .store(in: &cancellables)
    }

    private var wanted: Bool { settings.isActivityEnabled(.levels) }

    private func apply() {
        guard wanted else {
            removeTap()
            trustTimer?.invalidate()
            trustTimer = nil
            return
        }
        guard tap == nil else { return }
        if AXIsProcessTrusted(), installTap() {
            trustTimer?.invalidate()
            trustTimer = nil
            return
        }
        guard trustTimer == nil else { return }
        trustTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.apply() }
        }
    }

    // MARK: - Перехват

    private func installTap() -> Bool {
        let mask = CGEventMask(1 << 14) // NX_SYSDEFINED
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let controller = Unmanaged<LevelsController>.fromOpaque(refcon).takeUnretainedValue()
                // Колбэк приходит на главном цикле: tap висит на нём.
                return MainActor.assumeIsolated {
                    controller.handle(type: type, event: event)
                }
            },
            userInfo: refcon
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    private func removeTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    /// Коды из IOKit/hidsystem/ev_keymap.h.
    private enum Key: Int {
        case soundUp = 0
        case soundDown = 1
        case brightnessUp = 2
        case brightnessDown = 3
        case mute = 7
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Система выключает tap, если колбэк задумался. Включаем обратно,
        // иначе клавиши тихо вернутся к системному окну до перезапуска.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }
        let data = ns.data1
        guard let key = Key(rawValue: (data & 0xFFFF_0000) >> 16) else {
            return Unmanaged.passUnretained(event)
        }
        let isDown = ((data & 0xFF00) >> 8) == 0x0A
        // ⌥⇧ — мелкий шаг, как у системы: четверть деления.
        let fine = ns.modifierFlags.contains([.option, .shift])

        let handled: Bool = switch key {
        case .soundUp: isDown ? changeVolume(by: fine ? 1 / 64 : 1 / 16) : canControlVolume
        case .soundDown: isDown ? changeVolume(by: fine ? -1 / 64 : -1 / 16) : canControlVolume
        case .mute: isDown ? toggleMute() : canControlVolume
        case .brightnessUp: isDown ? changeBrightness(by: fine ? 1 / 64 : 1 / 16) : Brightness.isAvailable
        case .brightnessDown: isDown ? changeBrightness(by: fine ? -1 / 64 : -1 / 16) : Brightness.isAvailable
        }
        // Своё съедаем — и нажатие, и отпускание, иначе системное окно
        // всё равно вылезет на отпускании. Чужое пропускаем.
        return handled ? nil : Unmanaged.passUnretained(event)
    }

    // MARK: - Громкость

    private var canControlVolume: Bool {
        guard let device = Volume.defaultOutput() else { return false }
        return Volume.isSettable(device)
    }

    private func changeVolume(by step: Float) -> Bool {
        guard let device = Volume.defaultOutput(), Volume.isSettable(device),
              let current = Volume.get(device)
        else { return false }
        // Шаг по сетке, а не от текущего: иначе после ползунка в Пункте
        // управления уровень навсегда съезжает с ровных делений.
        let grid = abs(step)
        let snapped = (current / grid).rounded() * grid
        let next = min(max(snapped + step, 0), 1)
        Volume.set(device, next)
        if step > 0, Volume.isMuted(device) { Volume.setMuted(device, false) }
        showVolume(device)
        return true
    }

    private func toggleMute() -> Bool {
        guard let device = Volume.defaultOutput(), Volume.hasMute(device) else { return false }
        Volume.setMuted(device, !Volume.isMuted(device))
        showVolume(device)
        return true
    }

    private func showVolume(_ device: AudioDeviceID) {
        let level = Volume.get(device) ?? 0
        let muted = Volume.isMuted(device) || level == 0
        let symbol = muted ? "speaker.slash.fill"
            : level < 0.34 ? "speaker.wave.1.fill"
            : level < 0.67 ? "speaker.wave.2.fill"
            : "speaker.wave.3.fill"
        show(NotchActivity(
            kind: .levels,
            symbol: symbol,
            title: Volume.name(device) ?? settings.t(.levelsVolume),
            subtitle: muted ? settings.t(.levelsMuted) : Self.percent(level),
            progress: muted ? 0 : Double(level),
            tint: ActivityTint.teal,
            duration: 1.6
        ))
    }

    // MARK: - Яркость

    private func changeBrightness(by step: Float) -> Bool {
        guard let current = Brightness.level() else { return false }
        let grid = abs(step)
        let snapped = (current / grid).rounded() * grid
        let next = min(max(snapped + step, 0), 1)
        guard Brightness.set(next) else { return false }
        show(NotchActivity(
            kind: .levels,
            symbol: next < 0.5 ? "sun.min.fill" : "sun.max.fill",
            title: settings.t(.levelsBrightness),
            subtitle: Self.percent(next),
            progress: Double(next),
            tint: ActivityTint.orange,
            duration: 1.6
        ))
        return true
    }

    /// Плашку не показываем заново на каждое нажатие — только двигаем
    /// цифры в уже висящей и продлеваем ей время. Иначе при удержании
    /// клавиши она переигрывала бы появление двадцать раз в секунду.
    private func show(_ activity: NotchActivity) {
        if center.current?.kind == .levels {
            center.refresh(activity, extend: true)
        } else {
            center.show(activity)
        }
    }

    private static func percent(_ value: Float) -> String {
        "\(Int((value * 100).rounded())) %"
    }
}

// MARK: - CoreAudio

private enum Volume {
    static func defaultOutput() -> AudioDeviceID? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        return status == noErr && device != 0 ? device : nil
    }

    private static var volumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    static func isSettable(_ device: AudioDeviceID) -> Bool {
        var address = volumeAddress
        guard AudioHardwareServiceHasProperty(device, &address) else { return false }
        var settable = DarwinBoolean(false)
        return AudioHardwareServiceIsPropertySettable(device, &address, &settable) == noErr
            && settable.boolValue
    }

    static func get(_ device: AudioDeviceID) -> Float? {
        var address = volumeAddress
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioHardwareServiceGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    static func set(_ device: AudioDeviceID, _ value: Float) {
        var address = volumeAddress
        var value = Float32(value)
        AudioHardwareServiceSetPropertyData(
            device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value
        )
    }

    static func hasMute(_ device: AudioDeviceID) -> Bool {
        var address = muteAddress
        return AudioObjectHasProperty(device, &address)
    }

    static func isMuted(_ device: AudioDeviceID) -> Bool {
        var address = muteAddress
        guard AudioObjectHasProperty(device, &address) else { return false }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return value != 0
    }

    static func setMuted(_ device: AudioDeviceID, _ muted: Bool) {
        var address = muteAddress
        var value = UInt32(muted ? 1 : 0)
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    static func name(_ device: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr else {
            return nil
        }
        return name?.takeRetainedValue() as String?
    }
}

// MARK: - Яркость встроенного экрана

/// Публичного API для яркости нет, а у `DisplayServices` — есть, и им
/// пользуется сама система. Работаем только со встроенным экраном:
/// внешние мониторы живут по DDC, и клавиши к ним система не применяет.
@MainActor
private enum Brightness {
    private typealias Get = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias Set = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias Changed = @convention(c) (CGDirectDisplayID, Double) -> Void

    private static let handle = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW
    )

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: type)
    }

    private static var builtIn: CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count = UInt32(0)
        guard CGGetOnlineDisplayList(16, &ids, &count) == .success else { return nil }
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    static var isAvailable: Bool { level() != nil }

    static func level() -> Float? {
        guard let display = builtIn, let call = symbol("DisplayServicesGetBrightness", as: Get.self) else {
            return nil
        }
        var value = Float(0)
        return call(display, &value) == 0 ? value : nil
    }

    static func set(_ value: Float) -> Bool {
        guard let display = builtIn, let call = symbol("DisplayServicesSetBrightness", as: Set.self) else {
            return false
        }
        guard call(display, value) == 0 else { return false }
        // Сообщаем системе, иначе ползунок в Пункте управления остаётся
        // на старом месте.
        symbol("DisplayServicesBrightnessChanged", as: Changed.self)?(display, Double(value))
        return true
    }
}
