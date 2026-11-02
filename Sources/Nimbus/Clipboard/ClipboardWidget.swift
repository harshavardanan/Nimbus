import Combine
import SwiftUI

@MainActor
final class ClipboardWidget: IslandWidget {
    let store = ClipboardStore()

    let id = "clipboard"
    let title = "Clipboard history"
    let subtitle = "Last 3 text items. Drag them out or click to copy"
    let symbol = "list.clipboard"
    /// Off by default: it reads what you copy, so you choose to turn it on.
    let defaultEnabled = false
    var requestPeek: ((Double) -> Void)?

    var compactPriority: Int? { nil }
    var changes: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }

    func start() { store.start() }
    func stop() { store.stop() }
    func loadDemo() { store.loadDemo() }

    func expandedView(topInset: CGFloat) -> AnyView {
        AnyView(ClipboardExpandedView(store: store, topInset: topInset))
    }

    func expandedSize(settings: IslandSettings, closed: CGSize) -> CGSize {
        CGSize(width: settings.expandedWidth, height: settings.expandedHeight)
    }
}

struct ClipboardExpandedView: View {
    @ObservedObject var store: ClipboardStore
    let topInset: CGFloat
    @Environment(\.islandTheme) private var theme

    var body: some View {
        WidgetFrame(headline: "Clipboard · drag out or click to copy", topInset: topInset) {
            if store.items.isEmpty {
                WidgetMessage(symbol: "doc.on.clipboard", text: "Copy some text and it will appear here. Passwords from password managers are ignored.")
            } else {
                VStack(spacing: 5) {
                    ForEach(Array(store.items.enumerated()), id: \.element.id) { index, item in
                        row(item).reveal(index + 1)
                    }
                }
                .animation(.smooth(duration: 0.35), value: store.items)
            }
        }
    }

    private func row(_ item: ClipItem) -> some View {
        let copied = store.copiedID == item.id
        return Button { store.copy(item) } label: {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(theme.text.opacity(0.35))
                Text(item.text.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 12)).lineLimit(1)
                Spacer(minLength: 8)
                if copied {
                    Label("Copied", systemImage: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(red: 0.42, green: 0.86, blue: 0.58))
                        .transition(.scale.combined(with: .opacity))
                } else {
                    ShortAge(date: item.date)
                        .font(.system(size: 10)).foregroundStyle(theme.text.opacity(0.5)).lineLimit(1)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.text.opacity(copied ? 0.2 : 0.08)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        // Drag the text straight into any app instead of pasting it.
        .onDrag { NSItemProvider(object: item.text as NSString) }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: copied)
        .accessibilityLabel("Copy \(item.text)")
    }
}
