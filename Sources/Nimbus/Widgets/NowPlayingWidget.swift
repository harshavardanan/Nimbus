import Combine
import SwiftUI

@MainActor
final class NowPlayingWidget: IslandWidget {
    let store: NowPlayingStore

    let id = "nowplaying"
    let title = "Now playing"
    let subtitle = "Music and Spotify"
    let symbol = "music.note"
    let defaultEnabled = true
    var requestPeek: ((Double) -> Void)?

    init(store: NowPlayingStore) { self.store = store }

    var compactPriority: Int? { store.isPlaying ? 50 : nil }
    // IslandState already observes the store's track and playing state.
    var changes: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }

    func start() { store.start() }
    func stop() { store.stop() }

    func compactView(settings: IslandSettings) -> AnyView {
        AnyView(CompactView(store: store, settings: settings))
    }

    func expandedView(topInset: CGFloat) -> AnyView {
        AnyView(NowPlayingExpandedView(store: store, topInset: topInset))
    }

    func expandedSize(settings: IslandSettings, closed: CGSize) -> CGSize {
        if store.track != nil { return CGSize(width: settings.expandedWidth, height: settings.expandedHeight) }
        return CGSize(width: max(closed.width + 100, 280), height: closed.height + 52)
    }
}
