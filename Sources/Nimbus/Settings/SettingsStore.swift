import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private static let key = "nimbus.settings.v1"

    @Published var settings: IslandSettings {
        didSet { save() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = Self.decode(data) {
            settings = decoded.clamped()
        } else {
            settings = IslandSettings()
        }
    }

    func apply(_ preset: ThemePreset) {
        var s = settings
        preset.apply(to: &s)
        settings = s
    }

    /// Back to factory defaults for everything.
    func resetAll() { settings = IslandSettings() }

    /// Size, position and shape only.
    func resetSize() {
        let d = IslandSettings()
        var s = settings
        s.notchWidthAdjust = d.notchWidthAdjust
        s.notchHeightAdjust = d.notchHeightAdjust
        s.compactWing = d.compactWing
        s.expandedWidth = d.expandedWidth
        s.expandedHeight = d.expandedHeight
        s.idleRadius = d.idleRadius
        s.compactRadius = d.compactRadius
        s.expandedRadius = d.expandedRadius
        s.offsetX = d.offsetX
        s.offsetY = d.offsetY
        settings = s
    }

    func export(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: url, options: .atomic)
    }

    func importSettings(from url: URL) throws {
        let data = try Data(contentsOf: url)
        guard let decoded = Self.decode(data) else { throw CocoaError(.fileReadCorruptFile) }
        settings = decoded.clamped()
    }

    /// Saved values are layered over the defaults, so settings added in a newer version
    /// don't make an older save fail to load.
    private static func decode(_ data: Data) -> IslandSettings? {
        guard let defaults = try? JSONEncoder().encode(IslandSettings()),
              var merged = try? JSONSerialization.jsonObject(with: defaults) as? [String: Any],
              let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        merged.merge(saved) { _, new in new }
        guard let combined = try? JSONSerialization.data(withJSONObject: merged) else { return nil }
        return try? JSONDecoder().decode(IslandSettings.self, from: combined)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
