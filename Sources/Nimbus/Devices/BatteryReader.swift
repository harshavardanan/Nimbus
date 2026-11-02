import Foundation
import IOKit.ps

struct BatteryDevice: Identifiable, Equatable {
    enum Kind { case mac, airpods, headphones, mouse, keyboard, trackpad, controller, iphone, ipad, watch, other }

    var id: String
    var name: String
    /// 0...100
    var level: Int
    var isCharging: Bool
    var kind: Kind
    /// When a synced device last reported; nil for devices read live.
    var updated: Date?

    var symbol: String {
        switch kind {
        case .mac: return "laptopcomputer"
        case .airpods: return "airpods"
        case .headphones: return "headphones"
        case .mouse: return "computermouse.fill"
        case .keyboard: return "keyboard"
        case .trackpad: return "rectangle.and.hand.point.up.left.filled"
        case .controller: return "gamecontroller.fill"
        case .iphone: return "iphone"
        case .ipad: return "ipad"
        case .watch: return "applewatch"
        case .other: return "dot.radiowaves.left.and.right"
        }
    }
}

/// Reads batteries. Kept free of UI so the parsing can be tested on its own.
enum BatteryReader {
    // MARK: This Mac and accessories (IOKit power sources)

    /// Every power source macOS knows about: the Mac's own battery, plus keyboards, mice,
    /// trackpads, AirPods, game controllers and UPS units that report a charge level.
    static func readPowerSources() -> [BatteryDevice] {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return [] }

        var devices: [BatteryDevice] = []
        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let current = desc[kIOPSCurrentCapacityKey] as? Int
            else { continue }
            let maximum = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            guard maximum > 0 else { continue }

            let level = min(100, max(0, current * 100 / maximum))
            let charging = desc[kIOPSIsChargingKey] as? Bool ?? false

            if desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType {
                devices.append(BatteryDevice(
                    id: "mac", name: "This Mac", level: level, isCharging: charging, kind: .mac, updated: nil
                ))
            } else {
                let name = (desc[kIOPSNameKey] as? String) ?? "Accessory"
                let id = (desc[kIOPSPowerSourceIDKey] as? Int).map { "power-\($0)" } ?? "power-\(name)"
                devices.append(BatteryDevice(
                    id: id, name: name, level: level, isCharging: charging,
                    kind: kind(name: name, minorType: nil), updated: nil
                ))
            }
        }
        return devices
    }

    /// Keyboards, mice, trackpads and so on that macOS lists as accessory power sources.
    /// `pmset -g accps` reads the same list the Bluetooth menu uses, which the public IOKit
    /// calls leave out. Lines look like `-Keychron K3 Max (id=47651011)\t38%; `.
    static func readAccessories() -> [BatteryDevice] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "accps"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return parseAccessories(String(decoding: data, as: UTF8.self))
    }

    static func parseAccessories(_ text: String) -> [BatteryDevice] {
        guard let pattern = try? NSRegularExpression(pattern: #"^\s*-(.+?)\s+\(id=(\d+)\)\s+(\d+)%;\s*(.*)$"#) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            let line = String(line)
            guard let m = pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let name = Range(m.range(at: 1), in: line), let id = Range(m.range(at: 2), in: line),
                  let level = Range(m.range(at: 3), in: line), let rest = Range(m.range(at: 4), in: line),
                  let percent = Int(line[level])
            else { return nil }
            let n = String(line[name])
            if n.hasPrefix("InternalBattery") { return nil } // the Mac itself comes from IOKit
            let status = line[rest].lowercased()
            return BatteryDevice(
                id: "power-\(line[id])", name: n, level: min(100, percent),
                isCharging: status.contains("charging") && !status.contains("discharging"),
                kind: kind(name: n, minorType: nil), updated: nil
            )
        }
    }

    /// The Mac's battery plus every accessory, without duplicates.
    static func readAllPower() -> [BatteryDevice] {
        var devices = readPowerSources()
        let known = Set(devices.map { $0.name.lowercased() })
        devices += readAccessories().filter { !known.contains($0.name.lowercased()) }
        return devices
    }

    // MARK: Bluetooth (system_profiler)

    /// system_profiler takes a second or more, so call this off the main thread.
    static func readBluetooth() -> [BatteryDevice] { parseBluetooth(readBluetoothData()) }

    static func readBluetoothData() -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return Data() }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return data
    }

    /// What kind of thing each connected Bluetooth device is, by lowercased name. Devices that
    /// don't report a battery still say "Keyboard" or "Mouse", which picks the right icon.
    static func parseBluetoothKinds(_ data: Data) -> [String: BatteryDevice.Kind] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]] else { return [:] }
        var kinds: [String: BatteryDevice.Kind] = [:]
        for section in sections {
            for entry in section["device_connected"] as? [[String: Any]] ?? [] {
                for (name, value) in entry {
                    guard let props = value as? [String: Any] else { continue }
                    let k = kind(name: name, minorType: props["device_minorType"] as? String)
                    if k != .other { kinds[name.lowercased()] = k }
                }
            }
        }
        return kinds
    }

    /// Understands the `device_connected` list; devices with no battery fields are skipped.
    static func parseBluetooth(_ data: Data) -> [BatteryDevice] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]]
        else { return [] }

        var devices: [BatteryDevice] = []
        for section in sections {
            let connected = section["device_connected"] as? [[String: Any]] ?? []
            for entry in connected {
                for (name, value) in entry {
                    guard let props = value as? [String: Any] else { continue }
                    let main = percent(props["device_batteryLevelMain"])
                    let left = percent(props["device_batteryLevelLeft"])
                    let right = percent(props["device_batteryLevelRight"])
                    let pods = [left, right].compactMap { $0 }
                    // Earbuds report each bud; the weaker one is the number that matters.
                    guard let level = main ?? pods.min() else { continue }

                    let address = props["device_address"] as? String ?? name
                    devices.append(BatteryDevice(
                        id: address, name: name, level: level, isCharging: false,
                        kind: kind(name: name, minorType: props["device_minorType"] as? String),
                        updated: nil
                    ))
                }
            }
        }
        return devices
    }

    /// "85%" -> 85
    static func percent(_ value: Any?) -> Int? {
        guard let text = value as? String else { return nil }
        let digits = text.filter(\.isNumber)
        guard let n = Int(digits), (0...100).contains(n) else { return nil }
        return n
    }

    static func kind(name: String, minorType: String?) -> BatteryDevice.Kind {
        let n = name.lowercased()
        let t = (minorType ?? "").lowercased()
        if n.contains("airpods") { return .airpods }
        if t.contains("mouse") || n.contains("mouse") || n.contains("mx master") || n.contains("mx anywhere") { return .mouse }
        if t.contains("keyboard") || n.contains("keyboard") || n.contains("keychron") || n.contains("mx keys") { return .keyboard }
        if t.contains("trackpad") || n.contains("trackpad") { return .trackpad }
        if t.contains("headphone") || t.contains("headset") || n.contains("headphone") || n.contains("buds") { return .headphones }
        if n.contains("controller") || n.contains("gamepad") || n.contains("dualsense") || n.contains("dualshock") { return .controller }
        return .other
    }
}

// MARK: iPhone and iPad via a synced folder

extension BatteryReader {
    /// Where "Save File" puts things by default: the Shortcuts folder in iCloud Drive.
    /// On a Mac that folder is the Shortcuts app's iCloud container.
    static var defaultSyncFolder: String {
        let mobile = NSHomeDirectory() + "/Library/Mobile Documents"
        let candidates = [
            mobile + "/iCloud~is~workflow~my~workflows/Documents",
            mobile + "/com~apple~CloudDocs/Shortcuts",
        ]
        let listable = candidates.first { (try? FileManager.default.contentsOfDirectory(atPath: $0)) != nil }
        return listable ?? candidates[0]
    }

    /// Reads the folder's `.json` files, one per device. In the shared Shortcuts folder only files
    /// starting with "nimbus" count, so other shortcuts' files are never touched.
    static func readSyncFolder(_ path: String, onlyNimbusFiles: Bool) -> [BatteryDevice] {
        let folder = URL(fileURLWithPath: path)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        return files.filter { url in
            url.pathExtension.lowercased() == "json"
                && (!onlyNimbusFiles || url.lastPathComponent.lowercased().hasPrefix("nimbus"))
        }.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return parseSync(data, modified: modified, fallbackName: url.deletingPathExtension().lastPathComponent)
        }
    }

    /// A plain-language report of what Nimbus sees in the sync folder, for Settings and debugging.
    /// It lists file names only, never their contents.
    static func syncStatus(_ path: String, onlyNimbusFiles: Bool) -> String {
        let fm = FileManager.default
        var lines = ["Folder: \(path)"]
        guard fm.fileExists(atPath: path) else {
            return lines.joined(separator: "\n") + "\nThe folder doesn't exist, or macOS hasn't allowed Nimbus to see it. Check System Settings → Privacy & Security → Files and Folders (or Full Disk Access) for Nimbus."
        }
        guard let names = try? fm.contentsOfDirectory(atPath: path) else {
            return lines.joined(separator: "\n") + "\nThe folder exists but Nimbus can't read it. Allow Nimbus in System Settings → Privacy & Security."
        }
        let json = names.filter { $0.lowercased().hasSuffix(".json") }
        let relevant = onlyNimbusFiles ? json.filter { $0.lowercased().hasPrefix("nimbus") } : json
        let placeholders = names.filter { $0.hasSuffix(".icloud") }
        lines.append("Files in folder: \(names.count), JSON files: \(json.count), read by Nimbus: \(relevant.count)")
        lines.append("Names: " + (names.isEmpty ? "(empty)" : names.prefix(10).joined(separator: ", ")))
        if !placeholders.isEmpty { lines.append("Still downloading from iCloud: \(placeholders.count)") }
        if relevant.isEmpty && !json.isEmpty && onlyNimbusFiles {
            lines.append("None start with \"nimbus\". Re-add the Nimbus Sync shortcut, or make the file name start with nimbus-device-.")
        }
        let devices = readSyncFolder(path, onlyNimbusFiles: onlyNimbusFiles)
        lines.append("Readable devices: " + (devices.isEmpty ? "none" : devices.map { "\($0.name) \($0.level)%" }.joined(separator: ", ")))
        return lines.joined(separator: "\n")
    }

    /// Accepts what Shortcuts tends to write: numbers or text, "level" or "battery",
    /// a percentage (82) or a fraction (0.82). Returns nil if there is no usable level.
    static func parseSync(_ data: Data, modified: Date?, fallbackName: String) -> BatteryDevice? {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let dict = Dictionary(uniqueKeysWithValues: raw.map { ($0.key.lowercased(), $0.value) })

        func number(_ value: Any?) -> Double? {
            if let n = value as? NSNumber { return n.doubleValue }
            if let t = value as? String {
                return Double(t.trimmingCharacters(in: CharacterSet(charactersIn: "% ")))
            }
            return nil
        }
        guard var level = number(dict["level"] ?? dict["battery"] ?? dict["batterylevel"]) else { return nil }
        if level > 0, level < 1 { level *= 100 } // 0.82 means 82%
        guard (0...100).contains(level.rounded()) else { return nil }

        let name = (dict["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? fallbackName
        let charging: Bool = {
            if let b = dict["charging"] as? Bool { return b }
            if let t = (dict["charging"] as? String)?.lowercased() { return ["true", "yes", "1"].contains(t) }
            return false
        }()
        let kindText = ((dict["kind"] ?? dict["type"]) as? String ?? name).lowercased()
        let kind: BatteryDevice.Kind = kindText.contains("ipad") ? .ipad
            : kindText.contains("watch") ? .watch
            : kindText.contains("pod") ? .airpods
            : .iphone

        return BatteryDevice(
            id: "sync-\(name)", name: name, level: Int(level.rounded()),
            isCharging: charging, kind: kind, updated: modified
        )
    }
}
