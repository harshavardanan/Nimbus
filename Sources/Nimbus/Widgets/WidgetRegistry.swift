import Foundation

@MainActor
final class WidgetRegistry: ObservableObject {
    private static let key = "nimbus.widgets.enabled.v1"
    private static let knownKey = "nimbus.widgets.known.v1"

    /// Display order in the switcher. Add new widgets here.
    let widgets: [any IslandWidget]
    @Published private(set) var enabledIDs: Set<String>

    init(nowPlaying: NowPlayingStore) {
        let all: [any IslandWidget] = [
            NowPlayingWidget(store: nowPlaying),
            TimerWidget(),
            DevicesWidget(),
            CalendarWidget(),
            WeatherWidget(),
            NotificationsWidget(),
            QuickTogglesWidget(),
            ShelfWidget(),
            ClaudeWidget(),
            ClipboardWidget(),
            SystemStatsWidget(),
        ]
        widgets = all

        let defaults = UserDefaults.standard
        let known = Set(defaults.array(forKey: Self.knownKey) as? [String] ?? [])
        var enabled: Set<String>
        if let saved = defaults.array(forKey: Self.key) as? [String] {
            enabled = Set(saved)
            // A widget added in a later version starts on if it defaults to on,
            // but one the user switched off stays off.
            for widget in all where !known.contains(widget.id) && widget.defaultEnabled {
                enabled.insert(widget.id)
            }
        } else {
            enabled = Set(all.filter(\.defaultEnabled).map(\.id))
        }
        enabledIDs = enabled.intersection(all.map(\.id))
        defaults.set(Array(enabledIDs), forKey: Self.key)
        defaults.set(all.map(\.id), forKey: Self.knownKey)
    }

    var enabled: [any IslandWidget] { widgets.filter { enabledIDs.contains($0.id) } }

    func widget(id: String) -> (any IslandWidget)? { widgets.first { $0.id == id } }
    func isEnabled(_ id: String) -> Bool { enabledIDs.contains(id) }

    func setEnabled(_ id: String, _ on: Bool) {
        if on { enabledIDs.insert(id) } else { enabledIDs.remove(id) }
        UserDefaults.standard.set(Array(enabledIDs), forKey: Self.key)
        // A switched-off widget stops working entirely (no polling, no clipboard watching).
        if let widget = widget(id: id) { on ? widget.start() : widget.stop() }
    }

    /// Screenshot helper: shows a widget for this run only, without saving the choice.
    func enableTemporarily(_ id: String) { enabledIDs.insert(id) }

    func start() { enabled.forEach { $0.start() } }
}
