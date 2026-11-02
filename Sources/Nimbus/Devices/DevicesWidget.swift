import AppKit
import Combine
import SwiftUI

@MainActor
final class DevicesWidget: IslandWidget {
    let store = DevicesStore()

    let id = "devices"
    let title = "Devices battery"
    let subtitle = "This Mac, keyboards, mice, AirPods, iPhone via a Shortcut"
    let symbol = "battery.100"
    let defaultEnabled = true
    var requestPeek: ((Double) -> Void)?

    init() {
        store.onLow = { [weak self] in self?.requestPeek?(6) }
    }

    /// Batteries are glanceable on demand; they never claim the compact island.
    var compactPriority: Int? { nil }
    var changes: AnyPublisher<Void, Never> { store.objectWillChange.map { _ in () }.eraseToAnyPublisher() }

    func start() { store.start() }
    func stop() { store.stop() }
    func loadDemo() { store.loadDemo() }

    func compactView(settings: IslandSettings) -> AnyView { AnyView(EmptyView()) }

    func expandedView(topInset: CGFloat) -> AnyView {
        AnyView(DevicesExpandedView(store: store, topInset: topInset))
    }

    func expandedSize(settings: IslandSettings, closed: CGSize) -> CGSize {
        // Four or more devices need two rows, which needs the taller island.
        let height = store.devices.count > 3 ? settings.expandedHeight : min(settings.expandedHeight, 138)
        return CGSize(width: settings.expandedWidth, height: height)
    }
}

/// Green above 50, amber 21 to 50, red at 20 or below.
private func levelColor(_ level: Int) -> Color {
    if level > 50 { return Color(red: 0.29, green: 0.87, blue: 0.5) }
    if level > 20 { return Color(red: 1.0, green: 0.82, blue: 0.4) }
    return Color(red: 0.97, green: 0.44, blue: 0.44)
}

struct DevicesExpandedView: View {
    @ObservedObject var store: DevicesStore
    let topInset: CGFloat

    @Environment(\.islandTheme) private var theme
    @State private var appeared = false

    private let alertColor = Color(red: 0.97, green: 0.44, blue: 0.44)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text((store.alert ?? "Devices").uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(store.alert == nil ? theme.text.opacity(0.6) : alertColor)
                .lineLimit(1)
                .contentTransition(.opacity)
                .animation(.smooth(duration: 0.3), value: store.alert)
                .staggered(appeared, index: 0, enabled: theme.staggerContent)

            if store.devices.isEmpty {
                Text("No devices with battery information")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.text.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if store.devices.count <= 2 {
                    HStack(spacing: 8) {
                        ForEach(Array(store.devices.enumerated()), id: \.element.id) { index, device in
                            DeviceTile(device: device, appeared: appeared, isAlerting: alerting(device))
                                .staggered(appeared, index: index + 1, enabled: theme.staggerContent)
                        }
                        Spacer(minLength: 0)
                    }
                } else {
                    // Three or more: a grid that scrolls vertically (sideways swipes switch widgets).
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                            ForEach(Array(store.devices.enumerated()), id: \.element.id) { index, device in
                                MiniDeviceTile(device: device, appeared: appeared, isAlerting: alerting(device))
                                    .staggered(appeared, index: min(index + 1, 6), enabled: theme.staggerContent)
                            }
                        }
                    }
                }
            }
        }
        .padding(.top, topInset + 2)
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
        .animation(.smooth(duration: 0.35), value: store.devices)
        .onAppear {
            appeared = true
            store.refreshIfStale()
        }
    }
}

private extension DevicesExpandedView {
    func alerting(_ device: BatteryDevice) -> Bool {
        store.alert != nil && device.level <= store.config.lowThreshold
    }
}

/// One line of name, one line of percentage and a thin bar, for when there are many devices.
private struct MiniDeviceTile: View {
    let device: BatteryDevice
    let appeared: Bool
    let isAlerting: Bool
    @Environment(\.islandTheme) private var theme

    var body: some View {
        let color = levelColor(device.level)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: device.symbol).font(.system(size: 9))
                Text(device.name).lineLimit(1)
                if let updated = device.updated {
                    Spacer(minLength: 0)
                    ShortAge(date: updated).font(.system(size: 8)).opacity(0.55).lineLimit(1)
                }
            }
            .font(.system(size: 9))
            .foregroundStyle(theme.text.opacity(0.75))

            HStack(spacing: 6) {
                HStack(spacing: 1) {
                    Text("\(device.level)%").font(.system(size: 14, weight: .semibold).monospacedDigit())
                        .contentTransition(.numericText())
                    if device.isCharging {
                        Image(systemName: "bolt.fill").font(.system(size: 8)).foregroundStyle(color)
                    }
                }
                Capsule().fill(theme.text.opacity(0.18)).frame(height: 3)
                    .overlay(alignment: .leading) {
                        GeometryReader { geo in
                            Capsule().fill(color)
                                .frame(width: appeared ? geo.size.width * Double(device.level) / 100 : 0)
                                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.25), value: appeared)
                        }
                    }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(theme.text.opacity(0.08)))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(color, lineWidth: isAlerting ? 1.5 : 0)
        }
        .help("\(device.name): \(device.level)%")
        .accessibilityElement()
        .accessibilityLabel("\(device.name), \(device.level) percent\(device.isCharging ? ", charging" : "")")
    }
}

private struct DeviceTile: View {
    let device: BatteryDevice
    let appeared: Bool
    let isAlerting: Bool

    @Environment(\.islandTheme) private var theme
    @State private var pulse = false

    var body: some View {
        let color = levelColor(device.level)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: device.symbol).font(.system(size: 9))
                Text(device.name).lineLimit(1)
            }
            .font(.system(size: 10))
            .foregroundStyle(theme.text.opacity(0.75))

            HStack(spacing: 2) {
                Text("\(device.level)%")
                    .font(.system(size: 18, weight: .semibold).monospacedDigit())
                    .contentTransition(.numericText())
                if device.isCharging {
                    Image(systemName: "bolt.fill").font(.system(size: 10)).foregroundStyle(color)
                }
                if let updated = device.updated {
                    Spacer(minLength: 0)
                    ShortAge(date: updated).font(.system(size: 9)).opacity(0.55).lineLimit(1)
                }
            }

            Capsule()
                .fill(theme.text.opacity(0.18))
                .frame(height: 4)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Capsule()
                            .fill(color)
                            .frame(width: appeared ? geo.size.width * Double(device.level) / 100 : 0)
                            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.25), value: appeared)
                            .animation(.smooth(duration: 0.4), value: device.level)
                    }
                }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(width: 88, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.text.opacity(0.08)))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(levelColor(device.level), lineWidth: isAlerting ? 1.5 : 0)
                .opacity(isAlerting ? (pulse ? 1 : 0.3) : 0)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityElement()
        .accessibilityLabel("\(device.name), \(device.level) percent\(device.isCharging ? ", charging" : "")")
    }
}

// MARK: Settings

struct DevicesSettingsSection: View {
    @ObservedObject var store: DevicesStore
    @State private var copied = false
    @State private var status: String?

    private static let manualSteps = """
    On your iPhone, open Shortcuts and make a shortcut called "Nimbus Sync":
    1. Get Battery Level
    2. Get Device Details: Device Name, then another Get Device Details: Device Model
    3. Text: {"name": "<Device Name>", "level": <Battery Level>, "kind": "<Device Model>"}
    4. Set Name: nimbus-device-<Device Name>.json
    5. Save File: the default Shortcuts folder in iCloud Drive, Ask Where to Save off, Overwrite on
    Then add a Personal automation (for example Time of Day every hour) that runs "Nimbus Sync" with Run Immediately on.
    """

    private var shortcutURL: URL? { ShortcutFiles.url("Nimbus Sync") }

    var body: some View {
        Section("Devices battery") {
            Toggle("Pop out when a battery is low", isOn: $store.config.popOutOnLow)
            Stepper("Low battery at \(store.config.lowThreshold)%", value: $store.config.lowThreshold, in: 5...40, step: 5)
            Text("Reads this Mac and connected Bluetooth devices. Some accessories, like many Logitech and Keychron ones, don't report a level to macOS.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("iPhone and iPad") {
            Text("Add the Nimbus Sync shortcut once. It reaches your iPhone through iCloud, then run it there (or let an automation run it) to send the battery level here.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Add shortcut to Shortcuts") {
                    if let url = shortcutURL { NSWorkspace.shared.open(url) }
                }
                .disabled(shortcutURL == nil)
                Button("Send via AirDrop…") {
                    if let url = shortcutURL { NSSharingService(named: .sendViaAirDrop)?.perform(withItems: [url]) }
                }
                .disabled(shortcutURL == nil)
            }
            LabeledContent("Sync folder") {
                Text(store.syncFolderPath).font(.caption).lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Choose folder…", action: chooseFolder)
                Button("Open folder") { NSWorkspace.shared.open(URL(fileURLWithPath: store.syncFolderPath)) }
                Button("Write test file") { store.writeTestFile() }
                Button("Check sync") { status = store.syncStatus() }
            }
            if let status {
                Text(status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            DisclosureGroup("Make the shortcut by hand instead") {
                Text(Self.manualSteps).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Button(copied ? "Copied" : "Copy these steps") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Self.manualSteps, forType: .string)
                    copied = true
                }
            }
            Text("In the default Shortcuts folder Nimbus reads only files starting with \"nimbus\"; in a folder you choose it reads every .json file, one per device. macOS may ask permission to read iCloud Drive the first time. Charging state isn't available from Shortcuts, and a phone is only as fresh as its last run.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: store.syncFolderPath).deletingLastPathComponent()
        if panel.runModal() == .OK, let url = panel.url {
            store.config.syncFolder = url.path
            SyncCenter.shared.restart()
        }
    }
}
