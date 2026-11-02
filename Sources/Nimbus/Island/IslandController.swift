import AppKit
import Combine
import SwiftUI

@MainActor
final class IslandController {
    private static let hoverSlop: CGFloat = 8

    let state: IslandState
    private let settingsStore = SettingsStore.shared
    private let panel: IslandPanel
    private var screen: NSScreen
    private var monitors: [Any] = []
    private var bag = Set<AnyCancellable>()
    private var openTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?
    private var demoLocked = false

    init() {
        let screen = Self.resolveScreen(SettingsStore.shared.settings.display)
        self.screen = screen
        let nowPlaying = NowPlayingStore()
        state = IslandState(
            metrics: NotchMetrics.current(for: screen),
            nowPlaying: nowPlaying,
            settingsStore: SettingsStore.shared,
            registry: WidgetRegistry(nowPlaying: nowPlaying)
        )
        panel = IslandPanel(frame: .zero)

        let host = NSHostingView(rootView: IslandView(state: state))
        host.sizingOptions = []
        panel.contentView = host
    }

    func start() {
        reposition()
        panel.orderFrontRegardless()
        state.registry.start()
        SyncCenter.shared.start()

        // NIMBUS_DEMO=compact|expanded pins the island in one state (screenshots).
        if let demo = ProcessInfo.processInfo.environment["NIMBUS_DEMO"] {
            demoLocked = true
            state.isHovering = demo == "expanded"
            panel.ignoresMouseEvents = false
        } else {
            installMouseMonitors()
        }

        // NIMBUS_WIDGET=timer selects a widget (and runs a demo timer) for screenshots.
        if let id = ProcessInfo.processInfo.environment["NIMBUS_WIDGET"] {
            state.registry.enableTemporarily(id)
            state.selectedID = id
            state.registry.widget(id: id)?.loadDemo()
        }

        // NIMBUS_ENABLE_ALL=1 shows every widget for this run (not saved), to check the icon layout.
        if ProcessInfo.processInfo.environment["NIMBUS_ENABLE_ALL"] != nil {
            state.registry.widgets.forEach { state.registry.enableTemporarily($0.id) }
        }

        // NIMBUS_SELECT=<id> opens on a widget with its real data (no sample values).
        if let id = ProcessInfo.processInfo.environment["NIMBUS_SELECT"] { state.selectedID = id }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshScreen() }
        }

        // Keyboard focus and "stay open while typing" follow the selected widget.
        state.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                self.updateKeyboardFocus()
                if !self.state.holdsOpen { self.pointerMoved() }
            }
            .store(in: &bag)

        // Size, offset and display changes from the settings window apply live.
        settingsStore.$settings
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshScreen() }
            .store(in: &bag)
    }

    // MARK: Placement

    /// "auto" prefers the notched display, "main" the primary one, anything else is a display name.
    static func resolveScreen(_ choice: String) -> NSScreen {
        switch choice {
        case "auto":
            break
        case "main":
            if let main = NSScreen.screens.first { return main }
        default:
            if let match = NSScreen.screens.first(where: { $0.localizedName == choice }) { return match }
        }
        return NotchMetrics.preferredScreen() ?? NSScreen.screens[0]
    }

    private func refreshScreen() {
        screen = Self.resolveScreen(settingsStore.settings.display)
        state.metrics = NotchMetrics.current(for: screen)
        reposition()
    }

    /// Big enough for the largest island, its shadow and the user's offsets.
    private var panelSize: CGSize {
        let s = settingsStore.settings
        let closed = state.closedSize
        return CGSize(
            width: max(s.expandedWidth, closed.width + s.compactWing * 2, 300) + 80,
            height: max(s.expandedHeight, closed.height + 52) + 70
        )
    }

    private func reposition() {
        let s = settingsStore.settings
        let size = panelSize
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2 + s.offsetX,
            y: screen.frame.maxY - size.height - s.offsetY,
            width: size.width,
            height: size.height
        )
        panel.setFrame(frame, display: true)
    }

    // MARK: Hover

    /// Opens the island. Dragging a file onto the notch lands on the File shelf.
    private func open(dragging: Bool) {
        state.isHovering = true
        if dragging, state.registry.isEnabled("shelf"), Self.dragHasFiles() { state.selectedID = "shelf" }
    }

    private static func dragHasFiles() -> Bool {
        NSPasteboard(name: .drag).canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }

    private var swipeTotal: CGFloat = 0
    private var lastSwipe = Date.distantPast

    /// Returns true when the scroll was used to switch widgets, so it isn't also scrolled.
    private func handleScroll(overPanel: Bool, dx: CGFloat, dy: CGFloat, phase: NSEvent.Phase) -> Bool {
        guard state.mode == .expanded, overPanel, abs(dx) > abs(dy) * 1.5 else { return false }
        if phase == .began { swipeTotal = 0 }
        swipeTotal += dx
        if abs(swipeTotal) > 40, Date().timeIntervalSince(lastSwipe) > 0.4 {
            state.selectAdjacent(swipeTotal < 0 ? 1 : -1)
            lastSwipe = Date()
            swipeTotal = 0
        }
        return true
    }

    /// Gives the window keyboard focus only while a widget (Ask Claude) wants to type.
    private func updateKeyboardFocus() {
        if state.wantsKeyboard, !panel.allowsKey {
            panel.allowsKey = true
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else if !state.wantsKeyboard, panel.allowsKey {
            panel.allowsKey = false
            panel.resignKey()
            NSApp.deactivate()
        }
    }

    /// Global monitors miss events aimed at our own window, so we need both.
    private func installMouseMonitors() {
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            MainActor.assumeIsolated { self?.pointerMoved(dragging: event.type == .leftMouseDragged) }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            MainActor.assumeIsolated { self?.pointerMoved(dragging: event.type == .leftMouseDragged) }
            return event
        }
        // Two-finger sideways swipe over the open island flips between widgets.
        let scroll = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            // Pull out plain values first; the event itself can't cross into the main-actor closure.
            let overPanel = event.window is IslandPanel
            let (dx, dy, phase) = (event.scrollingDeltaX, event.scrollingDeltaY, event.phase)
            let consumed = MainActor.assumeIsolated { self?.handleScroll(overPanel: overPanel, dx: dx, dy: dy, phase: phase) } ?? false
            return consumed ? nil : event
        }
        monitors = [global, local, scroll].compactMap { $0 }
    }

    private func pointerMoved(dragging: Bool = false) {
        guard !demoLocked else { return }
        let size = state.targetSize
        let frame = panel.frame
        let hit = CGRect(
            x: frame.midX - size.width / 2,
            y: frame.maxY - size.height,
            width: size.width,
            height: size.height + 4 // include the very top pixel row of the screen
        ).insetBy(dx: -Self.hoverSlop, dy: -Self.hoverSlop)

        let inside = hit.contains(NSEvent.mouseLocation)
        panel.ignoresMouseEvents = !inside

        if inside {
            collapseTask?.cancel()
            collapseTask = nil
            guard !state.isHovering, openTask == nil else { return }
            let delay = settingsStore.settings.openDelay
            if delay <= 0 {
                open(dragging: dragging)
            } else {
                openTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled else { return }
                    self?.open(dragging: dragging)
                    self?.openTask = nil
                }
            }
        } else {
            openTask?.cancel()
            openTask = nil
            guard state.isHovering, collapseTask == nil, !state.holdsOpen else { return }
            let delay = settingsStore.settings.collapseDelay
            collapseTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self?.state.isHovering = false
                self?.collapseTask = nil
            }
        }
    }
}
