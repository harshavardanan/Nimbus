import Combine
import Foundation

struct DevicesConfig: Codable, Equatable {
    var popOutOnLow = true
    var lowThreshold = 20
    /// Folder the iPhone Shortcut writes into. Empty means the iCloud Drive default.
    var syncFolder = ""
}

@MainActor
final class DevicesStore: ObservableObject {
    private static let configKey = "nimbus.devices.config.v1"

    @Published private(set) var devices: [BatteryDevice] = []
    /// Shown in the widget heading for a few seconds after a low-battery pop-out.
    @Published private(set) var alert: String?
    @Published var config: DevicesConfig { didSet { save() } }

    var onLow: (() -> Void)?

    private var power: [BatteryDevice] = []
    private var bluetooth: [BatteryDevice] = []
    private var synced: [BatteryDevice] = []
    private var kinds: [String: BatteryDevice.Kind] = [:]
    private var notified = Set<String>()
    private var pollTask: Task<Void, Never>?
    private var alertTask: Task<Void, Never>?
    private var lastBluetoothRead = Date.distantPast
    private var isDemo = false
    private var bag = Set<AnyCancellable>()

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.configKey),
           let saved = try? JSONDecoder().decode(DevicesConfig.self, from: data) {
            config = saved
        } else {
            config = DevicesConfig()
        }
        // Devices that report over Wi-Fi show up the moment they do.
        SyncCenter.shared.$networkDevices
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.publish() }
            .store(in: &bag)
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: Polling

    /// The Mac battery is cheap, so it is read every 30 s; Bluetooth (slower) every 60 s.
    func start() {
        guard pollTask == nil, !isDemo else { return }
        pollTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                await self?.refresh(includeBluetooth: tick % 2 == 0)
                tick += 1
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    /// Called when the widget opens, so the numbers are fresh without polling faster.
    func refreshIfStale() {
        guard !isDemo, Date().timeIntervalSince(lastBluetoothRead) > 20 else { return }
        Task { await refresh(includeBluetooth: true) }
    }

    private func refresh(includeBluetooth: Bool) async {
        power = await Task.detached(priority: .utility) { BatteryReader.readAllPower() }.value
        synced = BatteryReader.readSyncFolder(syncFolderPath, onlyNimbusFiles: usesDefaultFolder)
        if includeBluetooth {
            lastBluetoothRead = Date()
            let data = await Task.detached(priority: .utility) { BatteryReader.readBluetoothData() }.value
            bluetooth = BatteryReader.parseBluetooth(data)
            kinds = BatteryReader.parseBluetoothKinds(data)
        }
        publish()
    }

    private func publish() {
        guard !isDemo else { return }
        // This Mac first, then the weakest battery first.
        // system_profiler only fills gaps: anything IOKit already reported by name is skipped.
        let power = power.map { device -> BatteryDevice in
            var d = device
            if d.kind == .other, let hint = kinds[d.name.lowercased()] { d.kind = hint }
            return d
        }
        let known = Set(power.map { $0.name.lowercased() })
        let extra = bluetooth.filter { !known.contains($0.name.lowercased()) }
        let mac = power.filter { $0.kind == .mac }
        // A Wi-Fi report replaces a file for the same device when it is newer.
        var reported = Dictionary(synced.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        for device in SyncCenter.shared.networkDevices.values where (reported[device.name]?.updated ?? .distantPast) < (device.updated ?? .distantFuture) {
            reported[device.name] = device
        }
        let rest = (power.filter { $0.kind != .mac } + extra + Array(reported.values)).sorted { $0.level < $1.level }
        devices = mac + rest
        checkLow()
    }

    /// The shared Shortcuts folder holds other files too, so only `nimbus*.json` is read there.
    var usesDefaultFolder: Bool { SyncFolder.onlyNimbusFiles }

    var syncFolderPath: String { SyncFolder.path }

    func syncStatus() -> String {
        BatteryReader.syncStatus(syncFolderPath, onlyNimbusFiles: usesDefaultFolder)
    }

    /// Writes an example file so you can check the folder is being read without a phone.
    func writeTestFile() {
        let folder = URL(fileURLWithPath: syncFolderPath)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let json = #"{"name": "iPhone", "level": 82, "kind": "iphone"}"#
        try? json.write(to: folder.appendingPathComponent("nimbus-test.json"), atomically: true, encoding: .utf8)
        Task { await refresh(includeBluetooth: false) }
    }

    // MARK: Low battery

    /// Pops out once per device per charge: re-armed after it charges or recovers.
    private func checkLow() {
        for device in devices {
            // A phone that hasn't reported for hours says nothing about its battery now.
            if let updated = device.updated, Date().timeIntervalSince(updated) > 6 * 3600 { continue }
            if device.isCharging || device.level > config.lowThreshold + 5 {
                notified.remove(device.id)
            } else if device.level <= config.lowThreshold, !notified.contains(device.id) {
                notified.insert(device.id)
                setAlert("\(device.name) battery low · \(device.level)%")
                if config.popOutOnLow { onLow?() }
            }
        }
    }

    private func setAlert(_ text: String) {
        alert = text
        alertTask?.cancel()
        alertTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.alert = nil
        }
    }

    /// Screenshot helper (`NIMBUS_WIDGET=devices`): fixed sample values, no polling.
    func loadDemo() {
        isDemo = true
        pollTask?.cancel()
        devices = [
            BatteryDevice(id: "mac", name: "This Mac", level: 91, isCharging: true, kind: .mac, updated: nil),
            BatteryDevice(id: "mouse", name: "MX Master 2S", level: 15, isCharging: false, kind: .mouse, updated: nil),
            BatteryDevice(id: "kb2", name: "Keychron K3 Max", level: 38, isCharging: false, kind: .keyboard, updated: nil),
            BatteryDevice(id: "pods", name: "AirPods", level: 47, isCharging: false, kind: .airpods, updated: nil),
            BatteryDevice(id: "kb", name: "iPhone", level: 78, isCharging: false, kind: .iphone, updated: Date().addingTimeInterval(-300)),
        ]
        if ProcessInfo.processInfo.environment["NIMBUS_ALERT"] != nil { setAlert("Mouse battery low · 15%") }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: Self.configKey)
    }
}
