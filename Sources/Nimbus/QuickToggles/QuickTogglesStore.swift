import AppKit
import IOKit.pwr_mgt

struct TogglesConfig: Codable, Equatable {
    var focusShortcut = "Nimbus Focus"
}

@MainActor
final class QuickTogglesStore: ObservableObject {
    private static let configKey = "nimbus.toggles.config.v1"

    @Published private(set) var isAwake = false
    @Published private(set) var awakeSince: Date?
    @Published private(set) var isMuted = false
    @Published private(set) var focusMessage: String?
    @Published var config: TogglesConfig { didSet { save() } }

    private var assertion: IOPMAssertionID = 0

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.configKey),
           let saved = try? JSONDecoder().decode(TogglesConfig.self, from: data) {
            config = saved
        } else {
            config = TogglesConfig()
        }
    }

    // MARK: Keep awake

    func toggleAwake() { isAwake ? stopAwake() : startAwake() }

    private func startAwake() {
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Nimbus keep awake" as CFString, &assertion
        )
        guard result == kIOReturnSuccess else { return }
        isAwake = true
        awakeSince = Date()
    }

    func stopAwake() {
        if isAwake { IOPMAssertionRelease(assertion) }
        isAwake = false
        awakeSince = nil
    }

    // MARK: Mute

    func refreshMute() {
        isMuted = Self.runAppleScript("output muted of (get volume settings)") == "true"
    }

    func toggleMute() {
        _ = Self.runAppleScript("set volume output muted \(isMuted ? "false" : "true")")
        refreshMute()
    }

    private static func runAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil ? result?.stringValue : nil
    }

    // MARK: Focus (Do Not Disturb)

    /// macOS has no public switch for Do Not Disturb, so this runs a Shortcut you create.
    func runFocusShortcut() {
        let name = config.focusShortcut
        Task {
            let ok = await Task.detached { () -> Bool in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
                process.arguments = ["run", name]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                do { try process.run() } catch { return false }
                process.waitUntilExit()
                return process.terminationStatus == 0
            }.value
            focusMessage = ok ? "Ran \"\(name)\"" : "Create a Shortcut named \"\(name)\""
            try? await Task.sleep(for: .seconds(3))
            focusMessage = nil
        }
    }

    func loadDemo() {
        isAwake = true
        awakeSince = Date().addingTimeInterval(-47 * 60)
        isMuted = false
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: Self.configKey)
    }
}
