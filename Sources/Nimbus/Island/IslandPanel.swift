import AppKit

/// Borderless, transparent window that floats above the menu bar on every Space
/// and never takes focus from the app you are working in.
final class IslandPanel: NSPanel {
    init(frame: NSRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        // Click-through until the pointer is over the island (see IslandController).
        ignoresMouseEvents = true
    }

    /// Only true while a widget needs the keyboard (Ask Claude); otherwise the panel never takes focus.
    var allowsKey = false

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}
