import AppKit

/// Size of the closed island. On notched MacBooks this matches the hardware
/// cutout exactly; elsewhere it is a simulated pill at the top of the screen.
struct NotchMetrics: Equatable {
    var size: CGSize
    var hasHardwareNotch: Bool

    static let fallback = NotchMetrics(size: CGSize(width: 190, height: 24), hasHardwareNotch: false)

    static func current(for screen: NSScreen) -> NotchMetrics {
        let inset = screen.safeAreaInsets.top
        guard inset > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea
        else { return .fallback }

        let width = screen.frame.width - left.width - right.width
        return NotchMetrics(size: CGSize(width: width, height: inset), hasHardwareNotch: true)
    }

    /// Prefer the notched built-in display, then the main screen.
    static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }
}
