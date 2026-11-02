import Darwin
import Foundation

/// CPU, memory and network readings. Sampling runs only while the widget is on screen.
@MainActor
final class SystemStatsStore: ObservableObject {
    @Published private(set) var cpu = 0.0
    @Published private(set) var memory = 0.0
    @Published private(set) var down = 0.0   // bytes per second
    @Published private(set) var up = 0.0

    private var timer: Timer?
    private var lastTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?
    private var lastNet: (down: UInt64, up: UInt64, at: Date)?

    func startSampling() {
        guard timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
    }

    func stopSampling() {
        timer?.invalidate()
        timer = nil
        lastTicks = nil
        lastNet = nil
    }

    private func sample() {
        if let value = Self.cpuTicks() {
            if let last = lastTicks {
                let user = Double(value.user &- last.user), system = Double(value.system &- last.system)
                let idle = Double(value.idle &- last.idle), nice = Double(value.nice &- last.nice)
                let total = user + system + idle + nice
                if total > 0 { cpu = (user + system + nice) / total }
            }
            lastTicks = value
        }
        memory = Self.memoryUsed()

        let net = Self.networkBytes()
        let now = Date()
        if let last = lastNet {
            let dt = now.timeIntervalSince(last.at)
            if dt > 0 {
                down = Double(net.down >= last.down ? net.down - last.down : 0) / dt
                up = Double(net.up >= last.up ? net.up - last.up : 0) / dt
            }
        }
        lastNet = (net.down, net.up, now)
    }

    // MARK: Readings

    private static func cpuTicks() -> (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return (info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3)
    }

    /// Active + wired + compressed pages, as a share of installed memory.
    private static func memoryUsed() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let page = Double(sysconf(_SC_PAGESIZE))
        let used = Double(stats.active_count) + Double(stats.wire_count) + Double(stats.compressor_page_count)
        return min(1, used * page / Double(ProcessInfo.processInfo.physicalMemory))
    }

    /// Total bytes in and out across the Wi-Fi and Ethernet interfaces.
    private static func networkBytes() -> (down: UInt64, up: UInt64) {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return (0, 0) }
        defer { freeifaddrs(head) }

        var down: UInt64 = 0, up: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = cursor {
            let name = String(cString: ifa.pointee.ifa_name)
            if name.hasPrefix("en"), let addr = ifa.pointee.ifa_addr,
               addr.pointee.sa_family == UInt8(AF_LINK), let data = ifa.pointee.ifa_data {
                let stats = data.assumingMemoryBound(to: if_data.self).pointee
                down += UInt64(stats.ifi_ibytes)
                up += UInt64(stats.ifi_obytes)
            }
            cursor = ifa.pointee.ifa_next
        }
        return (down, up)
    }

    func loadDemo() {
        cpu = 0.34; memory = 0.62; down = 4_200_000; up = 310_000
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var value = bytesPerSecond, i = 0
        while value >= 1000, i < units.count - 1 { value /= 1000; i += 1 }
        return String(format: value < 10 && i > 0 ? "%.1f %@" : "%.0f %@", value, units[i])
    }
}
