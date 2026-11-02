import Combine
import SwiftUI

@MainActor
final class NotificationsWidget: IslandWidget {
    let store = NotificationsStore.shared

    let id = "notifications"
    let title = "Notifications"
    let subtitle = "Nimbus's own alerts: calendar, timer, battery"
    let symbol = "bell.fill"
    let defaultEnabled = true
    var requestPeek: ((Double) -> Void)? {
        didSet { store.onBanner = requestPeek }
    }

    var compactPriority: Int? { nil }
    var changes: AnyPublisher<Void, Never> { store.objectWillChange.map { _ in () }.eraseToAnyPublisher() }

    func loadDemo() { store.loadDemo() }

    func expandedView(topInset: CGFloat) -> AnyView {
        AnyView(NotificationsExpandedView(store: store, topInset: topInset))
    }

    /// A banner is a slim card; opening the widget by hand shows the history.
    func expandedSize(settings: IslandSettings, closed: CGSize) -> CGSize {
        if store.banner != nil { return CGSize(width: 380, height: closed.height + 34) }
        return CGSize(width: settings.expandedWidth, height: min(settings.expandedHeight, 150))
    }
}

struct NotificationsExpandedView: View {
    @ObservedObject var store: NotificationsStore
    let topInset: CGFloat
    @Environment(\.islandTheme) private var theme

    var body: some View {
        Group {
            if let banner = store.banner {
                bannerView(banner)
            } else {
                WidgetFrame(headline: "Notifications", topInset: topInset) { history }
            }
        }
        .animation(.smooth(duration: 0.35), value: store.banner?.id)
    }

    private func bannerView(_ note: NoteItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: note.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.onText)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.accent))
            VStack(alignment: .leading, spacing: 1) {
                Text(note.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(note.line).font(.system(size: 12)).foregroundStyle(theme.text.opacity(0.7)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 10)
        .transition(.opacity.combined(with: .offset(y: -6)))
    }

    @ViewBuilder
    private var history: some View {
        if store.items.isEmpty {
            WidgetMessage(symbol: "bell.slash", text: "Nothing yet. Calendar reminders, finished timers and low batteries show up here.")
        } else {
            VStack(spacing: 4) {
                ForEach(store.items.prefix(3)) { note in
                    HStack(spacing: 10) {
                        Image(systemName: note.symbol).font(.system(size: 11)).frame(width: 16)
                            .foregroundStyle(theme.accent)
                        Text(note.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 8)
                        ShortAge(date: note.date)
                            .font(.system(size: 10)).foregroundStyle(theme.text.opacity(0.55)).lineLimit(1)
                    }
                    .padding(.vertical, 3)
                }
                HStack {
                    Spacer()
                    Button("Clear") { store.clear() }
                        .buttonStyle(PressableStyle())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.text.opacity(0.6))
                }
            }
            .reveal(1)
        }
    }
}
