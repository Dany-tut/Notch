import Darwin
import Foundation

/// Нагрузка машины: процессор, память, сеть, диск.
///
/// Всё считается из ядра напрямую — ни разрешений, ни сети, ни сторонних
/// процессов. Значения снимаются раз в секунду и только пока модуль виден:
/// опрос `host_statistics` дешёвый, но круглосуточно гонять его в фоне
/// ради панели, на которую никто не смотрит, незачем.
@MainActor
final class SystemStore: ObservableObject {
    /// Сколько точек держим в графике. Секунда на точку — минута истории.
    nonisolated static let historyLength = 60

    @Published private(set) var cpu: Double = 0
    @Published private(set) var cpuHistory: [Double] = []

    /// Доля занятой памяти и она же в байтах — цифру человек читает в
    /// гигабайтах, а полоску видит долей.
    @Published private(set) var memory: Double = 0
    @Published private(set) var memoryUsed: UInt64 = 0
    @Published private(set) var memoryTotal: UInt64 = ProcessInfo.processInfo.physicalMemory
    @Published private(set) var memoryHistory: [Double] = []

    /// Байт в секунду. История хранит сумму обеих сторон: в графике важен
    /// сам всплеск, а куда он шёл — видно по цифрам рядом.
    @Published private(set) var download: Double = 0
    @Published private(set) var upload: Double = 0
    @Published private(set) var networkHistory: [Double] = []

    @Published private(set) var diskUsed: UInt64 = 0
    @Published private(set) var diskTotal: UInt64 = 0

    private var timer: Timer?
    private var previousCPU: (busy: UInt64, total: UInt64)?
    private var previousNetwork: (received: UInt64, sent: UInt64, at: Date)?
    /// Сколько раз модуль попросил свежие данные. Считаем, а не держим
    /// флаг: панель успевает показать новый модуль раньше, чем прежний
    /// уйдёт, и одиночный флаг гасил бы уже запущенный опрос.
    private var viewers = 0

    // MARK: - Жизненный цикл

    /// Модуль появился на экране.
    func resume() {
        viewers += 1
        guard timer == nil else { return }
        reload()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    /// Модуль ушёл. Историю не чистим: вернутся — график будет с прошлым,
    /// пусть и с разрывом.
    func suspend() {
        viewers = max(viewers - 1, 0)
        guard viewers == 0 else { return }
        timer?.invalidate()
        timer = nil
        // Дельты считаются от прошлого снимка, а он теперь просрочен:
        // за время простоя счётчики ушли далеко, и первая же точка после
        // возврата была бы столбом во весь график.
        previousCPU = nil
        previousNetwork = nil
    }

    func reload() {
        updateCPU()
        updateMemory()
        updateNetwork()
        updateDisk()
    }

    // MARK: - Процессор

    private func updateCPU() {
        guard let ticks = Self.cpuTicks() else { return }
        defer { previousCPU = ticks }
        guard let previous = previousCPU else { return }

        let total = ticks.total &- previous.total
        let busy = ticks.busy &- previous.busy
        guard total > 0 else { return }
        cpu = min(max(Double(busy) / Double(total), 0), 1)
        push(cpu, to: &cpuHistory)
    }

    private static func cpuTicks() -> (busy: UInt64, total: UInt64)? {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size
            / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info_data_t()
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        guard status == KERN_SUCCESS else { return nil }

        let user = UInt64(info.cpu_ticks.0)
        let system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)
        return (busy: user + system + nice, total: user + system + nice + idle)
    }

    // MARK: - Память

    /// Занятой считаем то же, что и «Мониторинг системы»: активные,
    /// закреплённые и сжатые страницы. Кэш файлов сюда не идёт — система
    /// отдаст его по первому требованию, и пугать им человека нечестно.
    private func updateMemory() {
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size
            / MemoryLayout<integer_t>.size)
        var stats = vm_statistics64_data_t()
        let status = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        guard status == KERN_SUCCESS else { return }

        let page = UInt64(vm_kernel_page_size)
        let used = (UInt64(stats.active_count)
            + UInt64(stats.wire_count)
            + UInt64(stats.compressor_page_count)) * page

        memoryUsed = used
        guard memoryTotal > 0 else { return }
        memory = min(Double(used) / Double(memoryTotal), 1)
        push(memory, to: &memoryHistory)
    }

    // MARK: - Сеть

    private func updateNetwork() {
        guard let counters = Self.networkCounters() else { return }
        let now = Date()
        defer { previousNetwork = (counters.received, counters.sent, now) }
        guard let previous = previousNetwork else { return }

        let elapsed = now.timeIntervalSince(previous.at)
        guard elapsed > 0.1 else { return }
        // Счётчики интерфейса сбрасываются вместе с самим интерфейсом —
        // при переключении Wi-Fi дельта уходит в минус. Такую точку
        // пропускаем, иначе в графике появится провал на пустом месте.
        let received = counters.received >= previous.received
            ? Double(counters.received - previous.received) / elapsed
            : 0
        let sent = counters.sent >= previous.sent
            ? Double(counters.sent - previous.sent) / elapsed
            : 0

        download = received
        upload = sent
        push(received + sent, to: &networkHistory)
    }

    /// Сумма по всем физическим интерфейсам. Петлю пропускаем: в ней
    /// ходит разговор машины с самой собой, а не трафик.
    private static func networkCounters() -> (received: UInt64, sent: UInt64)? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard interface.ifa_addr?.pointee.sa_family == UInt8(AF_LINK) else { continue }
            let name = String(cString: interface.ifa_name)
            guard !name.hasPrefix("lo") else { continue }
            guard let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            received += UInt64(data.pointee.ifi_ibytes)
            sent += UInt64(data.pointee.ifi_obytes)
        }
        return (received, sent)
    }

    // MARK: - Диск

    private func updateDisk() {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]) else { return }

        // «Важное» свободное место — то же число, что показывает Finder:
        // в него входит то, что система готова вычистить ради нас.
        let total = UInt64(values.volumeTotalCapacity ?? 0)
        let free = UInt64(values.volumeAvailableCapacityForImportantUsage ?? 0)
        diskTotal = total
        diskUsed = total > free ? total - free : 0
    }

    // MARK: - История

    private func push(_ value: Double, to history: inout [Double]) {
        history.append(value)
        if history.count > Self.historyLength {
            history.removeFirst(history.count - Self.historyLength)
        }
    }
}
