import AppKit
import SwiftUI

/// Switch on the Wi-Fi link and create the iPhone Shortcuts that use it.
struct WiFiSettingsSection: View {
    @ObservedObject var sync: SyncCenter
    @State private var files: [String: URL] = [:]
    @State private var message: String?
    @State private var working = false

    private static let order = ["Nimbus Sync", "Nimbus Timer", "Nimbus Pomodoro", "Nimbus Pause", "Nimbus Skip"]
    private static let details = [
        "Nimbus Sync": "Sends this device's battery level",
        "Nimbus Timer": "Starts a Clock timer and shows it here",
        "Nimbus Pomodoro": "Starts a focus session on this Mac",
        "Nimbus Pause": "Pauses the Pomodoro",
        "Nimbus Skip": "Skips to the next stage",
    ]

    private var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nimbus/Shortcuts")
    }

    var body: some View {
        Section("Connect your iPhone over Wi-Fi (instant)") {
            Toggle("Let my devices connect to this Mac", isOn: Binding(
                get: { sync.config.serverEnabled },
                set: { sync.setServer(enabled: $0); files = [:]; message = nil }
            ))

            if sync.config.serverEnabled {
                LabeledContent("Status") { Text(sync.serverStatus).foregroundStyle(.secondary) }
                LabeledContent("Address") {
                    HStack {
                        Text(sync.serverAddress).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(sync.serverAddress, forType: .string)
                        }
                    }
                }

                if let ip = sync.lanAddress {
                    LabeledContent("If that name doesn't work") {
                        Text(ip).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }

                HStack {
                    Button(working ? "Creating…" : "Create iPhone shortcuts", action: build).disabled(working)
                    if !files.isEmpty {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(Array(files.values)) }
                    }
                }

                ForEach(Self.order.filter { files[$0] != nil }, id: \.self) { name in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(name)
                            Text(Self.details[name] ?? "").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Add") { if let url = files[name] { NSWorkspace.shared.open(url) } }
                        Button("AirDrop") {
                            if let url = files[name] { NSSharingService(named: .sendViaAirDrop)?.perform(withItems: [url]) }
                        }
                    }
                }

                Button("Make a new private token…") {
                    sync.regenerateToken()
                    files = [:]
                    message = "Shortcuts you made before no longer work. Create them again."
                }
            }

            Text("Off until you switch it on. Your iPhone sends small web requests to this Mac, so both must be on the same Wi-Fi. Every request needs a private token that is built into the shortcuts Nimbus creates, and Nimbus only accepts a short fixed list of things (a battery level, a timer, Pomodoro controls). The connection isn't encrypted, so use it on networks you trust, like home. The first time, macOS may ask if Nimbus can accept connections.")
                .font(.caption).foregroundStyle(.secondary)
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func build() {
        working = true
        message = nil
        let base = sync.serverAddress, token = sync.token, folder = folder
        Task {
            let result = await Task.detached { () -> Result<[String: URL], Error> in
                Result { try ShortcutBuilder.build(base: base, token: token, into: folder) }
            }.value
            working = false
            switch result {
            case .success(let made):
                files = made
                message = "Add each shortcut on this Mac and it reaches your iPhone through iCloud, or AirDrop it straight to the phone."
            case .failure(let error):
                message = error.localizedDescription
            }
        }
    }
}
