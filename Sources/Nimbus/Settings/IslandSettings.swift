import AppKit
import SwiftUI

struct RGBAColor: Codable, Equatable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double = 1

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }

    /// Perceived brightness, 0 (black) to 1 (white).
    var luminance: Double { 0.299 * r + 0.587 * g + 0.114 * b }

    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    init(color: Color) {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent))
    }
}

enum BackgroundStyle: String, Codable, CaseIterable, Identifiable {
    case solid, gradient, glass, artwork
    var id: String { rawValue }

    var title: String {
        switch self {
        case .solid: return "Solid"
        case .gradient: return "Gradient"
        case .glass: return "Glass"
        case .artwork: return "Album art"
        }
    }
}

/// How the island opens and closes.
enum TransitionStyle: String, Codable, CaseIterable, Identifiable {
    case classic, drop, pop, elastic, dissolve
    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .drop: return "Drop"
        case .pop: return "Pop"
        case .elastic: return "Elastic"
        case .dissolve: return "Dissolve"
        }
    }

    var blurb: String {
        switch self {
        case .classic: return "Width first, then height"
        case .drop: return "Falls down first, then widens"
        case .pop: return "Pops out with a bounce"
        case .elastic: return "Springy, overshoots and settles"
        case .dissolve: return "Quick morph, content blurs in"
        }
    }
}

enum AccentSource: String, Codable, CaseIterable, Identifiable {
    case artwork, fixed
    var id: String { rawValue }
    var title: String { self == .artwork ? "From album art" : "Fixed colour" }
}

/// Allowed ranges. Used by the sliders and to sanitise imported files.
enum SettingsLimits {
    static let notchWidthAdjust = -80.0...240.0
    static let notchHeightAdjust = -8.0...30.0
    static let compactWing = 20.0...160.0
    static let expandedWidth = 280.0...640.0
    static let expandedHeight = 120.0...320.0
    static let radius = 0.0...48.0
    static let offsetX = -400.0...400.0
    static let offsetY = 0.0...80.0
    static let opacity = 0.0...1.0
    static let gradientAngle = 0.0...360.0
    static let border = 0.0...4.0
    static let openDelay = 0.0...1.0
    static let collapseDelay = 0.0...2.0
    static let fadeDelay = 0.0...0.5
    static let response = 0.15...1.0
    static let damping = 0.4...1.0
    static let staggerDelay = 0.0...0.3
}

struct IslandSettings: Codable, Equatable {
    var presetName = "Obsidian"

    // Size and position (points)
    var notchWidthAdjust = 0.0
    var notchHeightAdjust = 0.0
    var compactWing = 60.0
    var expandedWidth = 420.0
    var expandedHeight = 168.0
    var idleRadius = 10.0
    var compactRadius = 14.0
    var expandedRadius = 28.0
    var offsetX = 0.0
    var offsetY = 0.0
    /// "auto" (notched display), "main", or a display name.
    var display = "auto"

    // Appearance
    var backgroundStyle = BackgroundStyle.solid
    var background = RGBAColor(0, 0, 0)
    var backgroundSecondary = RGBAColor(0.23, 0.08, 0.31)
    var gradientAngle = 135.0
    var backgroundOpacity = 1.0
    var textColor = RGBAColor(1, 1, 1)
    var accentSource = AccentSource.artwork
    var accent = RGBAColor(1, 0.48, 0.35)
    var showShadow = true
    var borderWidth = 0.0
    var border = RGBAColor(1, 1, 1, 0.3)
    var showWaveform = true
    var showCompactArtwork = true

    // Behaviour and motion
    var openDelay = 0.0
    var collapseDelay = 0.22
    var contentFadeDelay = 0.07
    var openResponse = 0.35
    var openDamping = 0.82
    var closeResponse = 0.28
    var closeDamping = 1.0
    var transitionStyle = TransitionStyle.classic
    /// Classic only: width grows first, then height (and the reverse on close).
    var staggerSize = true
    var staggerDelay = 0.08
    /// Artwork, text, bar and buttons appear one after another.
    var staggerContent = true

    func clamped() -> IslandSettings {
        func c(_ v: Double, _ r: ClosedRange<Double>) -> Double { min(max(v, r.lowerBound), r.upperBound) }
        var s = self
        s.notchWidthAdjust = c(s.notchWidthAdjust, SettingsLimits.notchWidthAdjust)
        s.notchHeightAdjust = c(s.notchHeightAdjust, SettingsLimits.notchHeightAdjust)
        s.compactWing = c(s.compactWing, SettingsLimits.compactWing)
        s.expandedWidth = c(s.expandedWidth, SettingsLimits.expandedWidth)
        s.expandedHeight = c(s.expandedHeight, SettingsLimits.expandedHeight)
        s.idleRadius = c(s.idleRadius, SettingsLimits.radius)
        s.compactRadius = c(s.compactRadius, SettingsLimits.radius)
        s.expandedRadius = c(s.expandedRadius, SettingsLimits.radius)
        s.offsetX = c(s.offsetX, SettingsLimits.offsetX)
        s.offsetY = c(s.offsetY, SettingsLimits.offsetY)
        s.gradientAngle = c(s.gradientAngle, SettingsLimits.gradientAngle)
        s.backgroundOpacity = c(s.backgroundOpacity, SettingsLimits.opacity)
        s.borderWidth = c(s.borderWidth, SettingsLimits.border)
        s.openDelay = c(s.openDelay, SettingsLimits.openDelay)
        s.collapseDelay = c(s.collapseDelay, SettingsLimits.collapseDelay)
        s.contentFadeDelay = c(s.contentFadeDelay, SettingsLimits.fadeDelay)
        s.openResponse = c(s.openResponse, SettingsLimits.response)
        s.closeResponse = c(s.closeResponse, SettingsLimits.response)
        s.openDamping = c(s.openDamping, SettingsLimits.damping)
        s.closeDamping = c(s.closeDamping, SettingsLimits.damping)
        s.staggerDelay = c(s.staggerDelay, SettingsLimits.staggerDelay)
        return s
    }
}

// MARK: Presets

enum ThemePreset: String, CaseIterable, Identifiable {
    case obsidian = "Obsidian"
    case glass = "Glass"
    case aurora = "Aurora"
    case paper = "Paper"

    var id: String { rawValue }

    var blurb: String {
        switch self {
        case .obsidian: return "Pure black, merges with the notch"
        case .glass: return "Translucent, blurs the wallpaper"
        case .aurora: return "Tints itself from the album art"
        case .paper: return "Light card with dark text"
        }
    }

    /// Changes the look only; size, position and motion are left alone.
    func apply(to s: inout IslandSettings) {
        s.presetName = rawValue
        s.borderWidth = 0
        s.backgroundOpacity = 1
        s.showShadow = true
        s.textColor = RGBAColor(1, 1, 1)
        s.accentSource = .artwork
        switch self {
        case .obsidian:
            s.backgroundStyle = .solid
            s.background = RGBAColor(0, 0, 0)
        case .glass:
            s.backgroundStyle = .glass
            s.background = RGBAColor(0.08, 0.09, 0.12, 0.45)
            s.borderWidth = 1
            s.border = RGBAColor(1, 1, 1, 0.3)
        case .aurora:
            s.backgroundStyle = .artwork
            s.background = RGBAColor(0, 0, 0)
        case .paper:
            s.backgroundStyle = .solid
            s.background = RGBAColor(0.96, 0.95, 0.92)
            s.textColor = RGBAColor(0.1, 0.1, 0.11)
            s.accentSource = .fixed
            s.accent = RGBAColor(0.85, 0.36, 0.2)
            s.borderWidth = 1
            s.border = RGBAColor(0, 0, 0, 0.12)
        }
    }
}

enum MotionStyle: String, CaseIterable, Identifiable {
    case snappy = "Snappy"
    case smooth = "Smooth"
    case bouncy = "Bouncy"
    case gentle = "Gentle"

    var id: String { rawValue }

    func apply(to s: inout IslandSettings) {
        switch self {
        case .snappy: (s.openResponse, s.openDamping, s.closeResponse, s.closeDamping) = (0.25, 0.85, 0.2, 1.0)
        case .smooth: (s.openResponse, s.openDamping, s.closeResponse, s.closeDamping) = (0.35, 0.82, 0.28, 1.0)
        case .bouncy: (s.openResponse, s.openDamping, s.closeResponse, s.closeDamping) = (0.45, 0.55, 0.3, 0.8)
        case .gentle: (s.openResponse, s.openDamping, s.closeResponse, s.closeDamping) = (0.6, 0.9, 0.5, 1.0)
        }
    }
}
