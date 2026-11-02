import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var island: IslandController?
    private var settingsWindow: SettingsWindowController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let island = IslandController()
        let settingsWindow = SettingsWindowController(state: island.state)
        island.state.openSettings = { [weak settingsWindow] in settingsWindow?.show() }
        AppActions.openSettings = { [weak settingsWindow] in settingsWindow?.show() }
        island.start()
        // NIMBUS_DUMP=<file> writes the live state once a second, so tests can check behaviour.
        if let out = ProcessInfo.processInfo.environment["NIMBUS_DUMP"] {
            Task { @MainActor in
                while true {
                    try? Self.dump(island.state).write(toFile: out, atomically: true, encoding: .utf8)
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
        // NIMBUS_BUILD_SHORTCUTS=<folder> creates the Wi-Fi shortcuts there and reports the result.
        if let folder = ProcessInfo.processInfo.environment["NIMBUS_BUILD_SHORTCUTS"] {
            let base = SyncCenter.shared.serverAddress, token = SyncCenter.shared.token
            let report = (try? ShortcutBuilder.build(base: base, token: token, into: URL(fileURLWithPath: folder)))
                .map { "built: " + $0.keys.sorted().joined(separator: ", ") } ?? "build FAILED"
            try? report.write(toFile: folder + "/report.txt", atomically: true, encoding: .utf8)
        }
        if let out = ProcessInfo.processInfo.environment["NIMBUS_DIAG"],
           let devices = island.state.registry.widget(id: "devices") as? DevicesWidget {
            try? devices.store.syncStatus().write(toFile: out, atomically: true, encoding: .utf8)
        }
        self.island = island
        self.settingsWindow = settingsWindow
        installStatusItem()
        welcomeFirstTimeUsers()

        // Handy for screenshots: NIMBUS_SETTINGS=1 opens the window at launch.
        if ProcessInfo.processInfo.environment["NIMBUS_SETTINGS"] != nil { settingsWindow.show() }
        if ProcessInfo.processInfo.environment["NIMBUS_ABOUT"] != nil { showAbout() }
    }

    private static func dump(_ state: IslandState) -> String {
        var lines: [String] = []
        if let timer = (state.registry.widget(id: "timer") as? TimerWidget)?.store {
            lines.append("timer stage=\(timer.stage.rawValue) phase=\(timer.phase) minutes=\(timer.selectedMinutes) remaining=\(Int(timer.remaining()))")
            lines.append("remote " + (timer.remote.map { "\($0.device)/\($0.label) remaining=\(Int($0.remaining()))" } ?? "none"))
        }
        let notes = NotificationsStore.shared.items.map(\.title)
        lines.append("notifications \(notes.count): " + notes.prefix(5).joined(separator: " | "))
        if let devices = (state.registry.widget(id: "devices") as? DevicesWidget)?.store.devices {
            lines.append("devices " + devices.map { "\($0.name)=\($0.level)" }.joined(separator: ", "))
        }
        lines.append("mode \(state.mode) selected=\(state.selectedWidget?.id ?? "-") live=\(state.liveWidget?.id ?? "-")")
        return lines.joined(separator: "\n")
    }

    /// Nimbus has no Dock icon, so the first time it runs, say where it is.
    private func welcomeFirstTimeUsers() {
        let key = "nimbus.welcomed.v1"
        guard !UserDefaults.standard.bool(forKey: key),
              ProcessInfo.processInfo.environment["NIMBUS_DEMO"] == nil else { return }
        UserDefaults.standard.set(true, forKey: key)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            NotificationsStore.shared.post(
                symbol: "sparkles", title: "Welcome to Nimbus",
                line: "Move your mouse over the notch to open me"
            )
        }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "rectangle.topthird.inset.filled",
            accessibilityDescription: "Nimbus"
        )

        let menu = NSMenu()
        let about = NSMenuItem(title: "About Nimbus", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Nimbus", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    /// The standard About window, with the developer credit.
    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let center = NSMutableParagraphStyle()
        center.alignment = .center
        let credits = NSMutableAttributedString(
            string: "Developed by Harshavardanan\n",
            attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .paragraphStyle: center]
        )
        credits.append(NSAttributedString(
            string: "github.com/harshavardanan/Nimbus",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .link: URL(string: "https://github.com/harshavardanan/Nimbus") as Any,
                .paragraphStyle: center,
            ]
        ))
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Nimbus", .credits: credits])
    }

    @objc private func openSettings() {
        settingsWindow?.show()
    }
}
