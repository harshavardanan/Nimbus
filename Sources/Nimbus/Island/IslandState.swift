import AppKit
import Combine
import SwiftUI

enum IslandMode: Equatable {
    case idle
    case compact
    case expanded
}

@MainActor
final class IslandState: ObservableObject {
    @Published var isHovering = false {
        didSet {
            // Opening by hover lands on whatever is live, e.g. a running timer.
            if isHovering, !oldValue, !isPeeking, let live = liveWidget { selectedID = live.id }
            retarget()
        }
    }
    @Published var metrics: NotchMetrics { didSet { retarget() } }
    @Published var selectedID: String? { didSet { retarget() } }
    @Published private(set) var isPeeking = false { didSet { retarget() } }
    /// Settings window preview: pins the island in one mode with a demo track.
    @Published var previewMode: IslandMode? {
        didSet {
            nowPlaying.setDemo(previewMode != nil)
            retarget()
        }
    }
    /// The size actually drawn. It trails `targetSize` so width and height can move in stages.
    @Published private(set) var shownSize: CGSize = .zero
    /// Used by the Pop style: the whole island scales and fades around size changes.
    @Published private(set) var islandScale: CGFloat = 1
    @Published private(set) var islandOpacity: Double = 1

    let nowPlaying: NowPlayingStore
    let settingsStore: SettingsStore
    let registry: WidgetRegistry
    var openSettings: () -> Void = {}

    private var bag = Set<AnyCancellable>()
    private var lastMode: IslandMode = .idle
    private var lastSelection: String?
    private var sizeTask: Task<Void, Never>?
    private var peekTask: Task<Void, Never>?

    init(
        metrics: NotchMetrics, nowPlaying: NowPlayingStore,
        settingsStore: SettingsStore, registry: WidgetRegistry
    ) {
        self.metrics = metrics
        self.nowPlaying = nowPlaying
        self.settingsStore = settingsStore
        self.registry = registry

        // Redraw whenever anything the island shows changes.
        nowPlaying.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        settingsStore.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        registry.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)

        // These publish *before* the value changes; hop to the next turn to read the new one.
        func void<P: Publisher>(_ p: P) -> AnyPublisher<Void, Never> where P.Failure == Never {
            p.dropFirst().map { _ in () }.eraseToAnyPublisher()
        }
        var changes: [AnyPublisher<Void, Never>] = [
            void(nowPlaying.$track),
            void(nowPlaying.$isPlaying),
            void(settingsStore.$settings),
            void(registry.$enabledIDs),
        ]
        changes += registry.widgets.map(\.changes)
        Publishers.MergeMany(changes)
            .handleEvents(receiveOutput: { [weak self] in self?.objectWillChange.send() })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.retarget() }
            .store(in: &bag)

        for widget in registry.widgets {
            let id = widget.id
            widget.requestPeek = { [weak self] seconds in self?.peek(id, seconds: seconds) }
        }

        shownSize = targetSize
        lastMode = mode
        lastSelection = selectedWidget?.id
    }

    // MARK: Widgets

    /// The enabled widget with the highest compact priority, if any is live.
    var liveWidget: (any IslandWidget)? {
        registry.enabled
            .compactMap { widget in widget.compactPriority.map { (widget, $0) } }
            .max { $0.1 < $1.1 }?
            .0
    }

    var selectedWidget: (any IslandWidget)? {
        let enabled = registry.enabled
        return enabled.first { $0.id == selectedID } ?? liveWidget ?? enabled.first
    }

    var holdsOpen: Bool { mode == .expanded && (selectedWidget?.holdsIslandOpen ?? false) }
    var wantsKeyboard: Bool { mode == .expanded && (selectedWidget?.wantsKeyboard ?? false) }

    /// Switches to the next (or previous) enabled widget, wrapping around. Used by swipes.
    func selectAdjacent(_ delta: Int) {
        let list = registry.enabled
        guard list.count > 1, let current = selectedWidget,
              let index = list.firstIndex(where: { $0.id == current.id }) else { return }
        selectedID = list[(index + delta + list.count) % list.count].id
    }

    /// Pops the island open on a widget for a few seconds (timer finished, low battery).
    func peek(_ id: String, seconds: Double) {
        guard registry.isEnabled(id) else { return }
        peekTask?.cancel()
        selectedID = id
        isPeeking = true
        peekTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.isPeeking = false
        }
    }

    // MARK: Derived layout

    var settings: IslandSettings { settingsStore.settings }

    var mode: IslandMode {
        if let previewMode { return previewMode }
        if isHovering || isPeeking { return .expanded }
        if liveWidget != nil { return .compact }
        return .idle
    }

    /// Hardware notch size plus the user's adjustment.
    var closedSize: CGSize {
        CGSize(
            width: max(40, metrics.size.width + settings.notchWidthAdjust),
            height: max(14, metrics.size.height + settings.notchHeightAdjust)
        )
    }

    var targetSize: CGSize {
        let closed = closedSize
        let s = settings
        switch mode {
        case .idle:
            return closed
        case .compact:
            return CGSize(width: closed.width + s.compactWing * 2, height: closed.height)
        case .expanded:
            return selectedWidget?.expandedSize(settings: s, closed: closed)
                ?? CGSize(width: max(closed.width + 100, 280), height: closed.height + 52)
        }
    }

    var bottomRadius: CGFloat {
        switch mode {
        case .idle: return settings.idleRadius
        case .compact: return settings.compactRadius
        case .expanded: return settings.expandedRadius
        }
    }

    var theme: IslandTheme {
        let s = settings
        let accent = s.accentSource == .artwork ? nowPlaying.accent : s.accent.color
        return IslandTheme(
            text: s.textColor.color,
            accent: accent,
            onText: s.textColor.luminance > 0.5 ? .black : .white,
            staggerContent: s.staggerContent
        )
    }

    /// Open and close use separate springs. Reduce Motion falls back to a short ease.
    var animation: Animation {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            return .easeInOut(duration: 0.12)
        }
        let s = settings
        switch s.transitionStyle {
        case .elastic: return .spring(response: 0.5, dampingFraction: 0.45)
        case .dissolve: return .easeInOut(duration: 0.28)
        case .pop: return .spring(response: 0.42, dampingFraction: 0.55)
        case .classic, .drop:
            switch mode {
            case .expanded: return .spring(response: s.openResponse, dampingFraction: s.openDamping)
            default: return .spring(response: s.closeResponse, dampingFraction: s.closeDamping)
            }
        }
    }

    // MARK: Size morph

    private enum Axis { case width, height }

    /// Moves `shownSize` to `targetSize` in the way the chosen transition style asks for.
    /// Slider tweaks (same mode, same widget) always apply instantly.
    func retarget() {
        let target = targetSize
        let current = mode
        let selection = selectedWidget?.id
        defer { lastMode = current; lastSelection = selection }
        guard target != shownSize else { return }

        sizeTask?.cancel()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        if current == lastMode && selection == lastSelection && !reduceMotion {
            shownSize = target
            return
        }
        // Switching widgets inside the expanded island morphs both sides together.
        if reduceMotion || (current == lastMode && current == .expanded) {
            withAnimation(animation) { shownSize = target }
            return
        }

        let opening = target.width * target.height >= shownSize.width * shownSize.height
        let style = settings.transitionStyle
        let anim = animation

        switch style {
        case .classic:
            if settings.staggerSize {
                stagger(first: opening ? .width : .height, to: target, anim: anim)
            } else {
                withAnimation(anim) { shownSize = target }
            }
        case .drop:
            stagger(first: opening ? .height : .width, to: target, anim: anim)
        case .elastic, .dissolve:
            withAnimation(anim) { shownSize = target }
        case .pop:
            pop(opening: opening, to: target)
        }
    }

    /// Animates one axis now and the other after the stagger delay.
    private func stagger(first: Axis, to target: CGSize, anim: Animation) {
        let delay = Duration.milliseconds(Int(max(settings.staggerDelay, 0.04) * 1000))
        withAnimation(anim) {
            if first == .width { shownSize.width = target.width } else { shownSize.height = target.height }
        }
        sizeTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            withAnimation(anim) {
                if first == .width { self.shownSize.height = target.height } else { self.shownSize.width = target.width }
            }
        }
    }

    /// Opening: jump to size, then bounce up from a smaller scale.
    /// Closing: shrink and fade, swap to the small size, then fade back in.
    private func pop(opening: Bool, to target: CGSize) {
        if opening {
            shownSize = target
            islandScale = 0.55
            islandOpacity = 0.4
            withAnimation(.spring(response: 0.42, dampingFraction: 0.5)) {
                islandScale = 1
                islandOpacity = 1
            }
        } else {
            withAnimation(.easeIn(duration: 0.15)) {
                islandScale = 0.7
                islandOpacity = 0
            }
            sizeTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled, let self else { return }
                self.shownSize = target
                self.islandScale = 0.85
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    self.islandScale = 1
                    self.islandOpacity = 1
                }
            }
        }
    }

    /// Plays the current open and close animation once, for the Settings preview.
    func replayTransition(finished: @escaping () -> Void) {
        Task { [weak self] in
            guard let self else { return }
            self.previewMode = .idle
            try? await Task.sleep(for: .milliseconds(700))
            self.previewMode = .expanded
            try? await Task.sleep(for: .milliseconds(1800))
            self.previewMode = .idle
            try? await Task.sleep(for: .milliseconds(900))
            finished()
        }
    }
}
