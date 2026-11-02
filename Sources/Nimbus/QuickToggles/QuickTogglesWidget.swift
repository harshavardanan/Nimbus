import Combine
import SwiftUI

@MainActor
final class QuickTogglesWidget: IslandWidget {
    let store = QuickTogglesStore()

    let id = "toggles"
    let title = "Quick toggles"
    let subtitle = "Keep awake, mute, Focus"
    let symbol = "switch.2"
    let defaultEnabled = true
    var requestPeek: ((Double) -> Void)?

    /// While the Mac is being kept awake the compact island says so.
    var compactPriority: Int? { store.isAwake ? 30 : nil }
    var changes: AnyPublisher<Void, Never> { store.objectWillChange.map { _ in () }.eraseToAnyPublisher() }

    func stop() {}
    func loadDemo() { store.loadDemo() }

    func compactView(settings: IslandSettings) -> AnyView { AnyView(AwakeCompactView(store: store)) }

    func expandedView(topInset: CGFloat) -> AnyView {
        AnyView(QuickTogglesExpandedView(store: store, topInset: topInset))
    }

    func expandedSize(settings: IslandSettings, closed: CGSize) -> CGSize {
        CGSize(width: settings.expandedWidth, height: min(settings.expandedHeight, 130))
    }
}

struct AwakeCompactView: View {
    @ObservedObject var store: QuickTogglesStore

    var body: some View {
        HStack {
            Image(systemName: "cup.and.saucer.fill").font(.system(size: 11)).foregroundStyle(.orange)
            Spacer(minLength: 0)
            Text("Awake").font(.system(size: 11, weight: .semibold)).foregroundStyle(.orange)
        }
        .padding(.horizontal, 14)
        .frame(maxHeight: .infinity)
    }
}

struct QuickTogglesExpandedView: View {
    @ObservedObject var store: QuickTogglesStore
    let topInset: CGFloat
    @Environment(\.islandTheme) private var theme

    var body: some View {
        WidgetFrame(headline: store.focusMessage ?? "Quick toggles", topInset: topInset) {
            HStack(spacing: 10) {
                tile("cup.and.saucer.fill", "Awake", detail: awakeDetail, on: store.isAwake, tint: .orange, action: store.toggleAwake)
                    .reveal(1)
                tile(store.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", store.isMuted ? "Muted" : "Sound",
                     detail: nil, on: store.isMuted, tint: .red, action: store.toggleMute)
                    .reveal(2)
                tile("moon.fill", "Focus", detail: "Runs a Shortcut", on: false, tint: .indigo, action: store.runFocusShortcut)
                    .reveal(3)
            }
        }
        .onAppear { store.refreshMute() }
    }

    private var awakeDetail: String? {
        guard let since = store.awakeSince else { return "Off" }
        let minutes = Int(Date().timeIntervalSince(since) / 60)
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
    }

    private func tile(
        _ symbol: String, _ title: String, detail: String?, on: Bool, tint: Color, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(on ? Color.black : theme.text)
                Text(title).font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(on ? Color.black : theme.text)
                if let detail {
                    Text(detail).font(.system(size: 9))
                        .foregroundStyle((on ? Color.black : theme.text).opacity(0.65))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(on ? tint : theme.text.opacity(0.1)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: on)
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

struct TogglesSettingsSection: View {
    @ObservedObject var store: QuickTogglesStore

    var body: some View {
        Section("Quick toggles") {
            TextField("Focus Shortcut name", text: $store.config.focusShortcut)
            Text("macOS has no public switch for Do Not Disturb. Make a Shortcut with that name in the Shortcuts app (for example \"Set Focus\") and the Focus tile will run it.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
