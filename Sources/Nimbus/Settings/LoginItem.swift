import ServiceManagement
import SwiftUI

/// "Open Nimbus when I log in", using the system's own login item list.
struct GeneralSettingsSection: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled
    @State private var needsApproval = SMAppService.mainApp.status == .requiresApproval
    @State private var failed = false

    var body: some View {
        Section("General") {
            Toggle("Open Nimbus when I log in", isOn: Binding(
                get: { enabled },
                set: { setLoginItem($0) }
            ))
            if needsApproval {
                Text("macOS needs you to approve it: open System Settings → General → Login Items and switch Nimbus on.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if failed {
                Text("Couldn't change this. Move Nimbus into your Applications folder and try again.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: refresh)
    }

    private func setLoginItem(_ on: Bool) {
        failed = false
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            failed = true
        }
        refresh()
    }

    private func refresh() {
        let status = SMAppService.mainApp.status
        enabled = status == .enabled || status == .requiresApproval
        needsApproval = status == .requiresApproval
    }
}
