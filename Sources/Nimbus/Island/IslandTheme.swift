import AppKit
import SwiftUI

/// Colours the island views read from the environment.
struct IslandTheme {
    var text: Color
    var accent: Color
    /// Readable colour for content drawn on top of `text` (e.g. the play button glyph).
    var onText: Color
    var staggerContent: Bool

    static let standard = IslandTheme(text: .white, accent: .orange, onText: .black, staggerContent: true)
}

private struct IslandThemeKey: EnvironmentKey {
    static let defaultValue = IslandTheme.standard
}

extension EnvironmentValues {
    var islandTheme: IslandTheme {
        get { self[IslandThemeKey.self] }
        set { self[IslandThemeKey.self] = newValue }
    }
}

/// Blurs whatever is behind the window (the wallpaper).
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct IslandBackground: View {
    let settings: IslandSettings
    let accent: Color
    let shape: NotchShape

    var body: some View {
        ZStack {
            fill
                .clipShape(shape)
                .opacity(settings.backgroundOpacity)
            if settings.borderWidth > 0 {
                shape.stroke(settings.border.color, lineWidth: settings.borderWidth)
            }
        }
    }

    @ViewBuilder
    private var fill: some View {
        switch settings.backgroundStyle {
        case .solid:
            settings.background.color
        case .gradient:
            LinearGradient(
                colors: [settings.background.color, settings.backgroundSecondary.color],
                startPoint: Self.point(settings.gradientAngle, start: true),
                endPoint: Self.point(settings.gradientAngle, start: false)
            )
        case .glass:
            ZStack {
                VisualEffectBackground()
                settings.background.color
            }
        case .artwork:
            LinearGradient(
                colors: [settings.background.color, accent.opacity(0.55)],
                startPoint: .top, endPoint: .bottomTrailing
            )
        }
    }

    private static func point(_ degrees: Double, start: Bool) -> UnitPoint {
        let r = degrees * .pi / 180
        let dx = cos(r) / 2, dy = sin(r) / 2
        return start ? UnitPoint(x: 0.5 - dx, y: 0.5 - dy) : UnitPoint(x: 0.5 + dx, y: 0.5 + dy)
    }
}
