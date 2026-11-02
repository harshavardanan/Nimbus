import Combine
import SwiftUI

/// One thing the island can show. Adding a widget means writing one of these
/// and adding it to `WidgetRegistry.init`; the Settings toggle appears on its own.
@MainActor
protocol IslandWidget: AnyObject {
    var id: String { get }
    var title: String { get }
    var subtitle: String { get }
    /// SF Symbol used by the widget switcher and the Settings list.
    var symbol: String { get }
    var defaultEnabled: Bool { get }

    /// Non-nil while the widget has something live to show in the compact island
    /// (music playing, timer running). The highest priority wins.
    var compactPriority: Int? { get }
    /// Fires when state that affects the island's mode or size changes.
    var changes: AnyPublisher<Void, Never> { get }
    /// Set by the island: ask it to pop out for a few seconds (timer done, low battery).
    var requestPeek: ((Double) -> Void)? { get set }

    /// While true the island stays open even when the pointer leaves (e.g. you are typing).
    var holdsIslandOpen: Bool { get }
    /// While true the island window takes keyboard focus.
    var wantsKeyboard: Bool { get }

    func start()
    func stop()
    /// Fills the widget with sample data for screenshots (`NIMBUS_WIDGET=<id>`).
    func loadDemo()
    func compactView(settings: IslandSettings) -> AnyView
    func expandedView(topInset: CGFloat) -> AnyView
    func expandedSize(settings: IslandSettings, closed: CGSize) -> CGSize
}

extension IslandWidget {
    var holdsIslandOpen: Bool { false }
    var wantsKeyboard: Bool { false }
    func start() {}
    func stop() {}
    func loadDemo() {}
    func compactView(settings: IslandSettings) -> AnyView { AnyView(EmptyView()) }
}
