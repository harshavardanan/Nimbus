import AppKit
import SwiftUI

/// Settings for talking to your other devices through Shortcuts.
struct SyncSettingsSection: View {
    @ObservedObject var sync: SyncCenter
    @ObservedObject var timer: TimerStore

    private static let shortcuts: [(name: String, detail: String)] = [
        ("Nimbus Pomodoro", "Asks how many minutes, then starts a focus session on your Mac"),
        ("Nimbus Timer", "Starts a Clock timer on your phone and shows the countdown in the island"),
        ("Nimbus Pause", "Pauses the Pomodoro on your Mac"),
        ("Nimbus Skip", "Skips to the next Pomodoro stage"),
    ]

    var body: some View {
        Section("Shortcuts through iCloud (alternative)") {
            Toggle("Accept commands from my devices", isOn: $sync.config.acceptCommands)
            Text("The Wi-Fi link above is faster and simpler. These versions use an iCloud folder instead. Shortcuts on your iPhone or iPad can start and pause the Pomodoro, show a phone timer here, or send a message to the island. They talk through your iCloud folder, so only your own devices can. Commands are a short fixed list and can't run anything else.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(Self.shortcuts, id: \.name) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name)
                        Text(item.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Add") { if let url = ShortcutFiles.url(item.name) { NSWorkspace.shared.open(url) } }
                        .disabled(ShortcutFiles.url(item.name) == nil)
                    Button("AirDrop") {
                        if let url = ShortcutFiles.url(item.name) {
                            NSSharingService(named: .sendViaAirDrop)?.perform(withItems: [url])
                        }
                    }
                    .disabled(ShortcutFiles.url(item.name) == nil)
                }
            }
        }
    }
}
