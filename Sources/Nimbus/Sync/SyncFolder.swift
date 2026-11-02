import Foundation

/// The folder iPhone Shortcuts write into. Everything Nimbus syncs (battery, timers, commands)
/// lives here as small `nimbus-*.json` files.
enum SyncFolder {
    static var path: String {
        // NIMBUS_SYNC_FOLDER lets tests point at a scratch folder instead of iCloud Drive.
        if let override = ProcessInfo.processInfo.environment["NIMBUS_SYNC_FOLDER"] { return override }
        if let data = UserDefaults.standard.data(forKey: "nimbus.devices.config.v1"),
           let config = try? JSONDecoder().decode(DevicesConfig.self, from: data),
           !config.syncFolder.isEmpty {
            return config.syncFolder
        }
        return BatteryReader.defaultSyncFolder
    }

    /// The shared Shortcuts folder holds other shortcuts' files, so only `nimbus*` ones are ours there.
    static var onlyNimbusFiles: Bool {
        if ProcessInfo.processInfo.environment["NIMBUS_SYNC_FOLDER"] != nil { return false }
        if let data = UserDefaults.standard.data(forKey: "nimbus.devices.config.v1"),
           let config = try? JSONDecoder().decode(DevicesConfig.self, from: data),
           !config.syncFolder.isEmpty {
            return false
        }
        return true
    }
}

/// The signed Shortcuts shipped with Nimbus. Inside the app they sit in Resources; when run
/// from source they are in the repo's `Shortcuts` folder.
enum ShortcutFiles {
    static func url(_ name: String) -> URL? {
        if let bundled = Bundle.main.url(forResource: name, withExtension: "shortcut") { return bundled }
        let local = URL(fileURLWithPath: "Shortcuts/\(name).shortcut")
        return FileManager.default.fileExists(atPath: local.path) ? local : nil
    }
}
