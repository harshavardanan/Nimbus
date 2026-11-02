import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ShelfWidget: IslandWidget {
    let store = ShelfStore()

    let id = "shelf"
    let title = "File shelf"
    let subtitle = "Park files on the notch, drag them out later"
    let symbol = "tray.and.arrow.down.fill"
    let defaultEnabled = true
    var requestPeek: ((Double) -> Void)?

    var compactPriority: Int? { nil }
    var changes: AnyPublisher<Void, Never> { store.objectWillChange.map { _ in () }.eraseToAnyPublisher() }

    func loadDemo() { store.loadDemo() }

    func expandedView(topInset: CGFloat) -> AnyView {
        AnyView(ShelfExpandedView(store: store, topInset: topInset))
    }

    func expandedSize(settings: IslandSettings, closed: CGSize) -> CGSize {
        CGSize(width: settings.expandedWidth, height: min(settings.expandedHeight, 140))
    }
}

struct ShelfExpandedView: View {
    @ObservedObject var store: ShelfStore
    let topInset: CGFloat
    @Environment(\.islandTheme) private var theme
    @State private var isTargeted = false

    var body: some View {
        WidgetFrame(headline: store.items.isEmpty ? "File shelf" : "File shelf · \(store.items.count)", topInset: topInset) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isTargeted ? theme.accent : theme.text.opacity(0.3),
                        style: StrokeStyle(lineWidth: isTargeted ? 2 : 1.5, dash: [6, 5])
                    )
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(theme.accent.opacity(isTargeted ? 0.15 : 0)))

                if store.items.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc")
                            .symbolEffect(.bounce, value: isTargeted)
                        Text(isTargeted ? "Release to park" : "Drop files here")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(theme.text.opacity(0.7))
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(store.items) { item in chip(item) }
                        }
                        .padding(.horizontal, 10)
                    }
                }
            }
            .scaleEffect(isTargeted ? 1.02 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.65), value: isTargeted)
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                load(providers)
                return true
            }
            .reveal(1)
        }
    }

    /// A parked file: drag it out to use it, or tap the cross to let go of it.
    private func chip(_ item: ShelfItem) -> some View {
        VStack(spacing: 3) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable().frame(width: 30, height: 30)
            Text(item.name).font(.system(size: 9)).lineLimit(1).frame(width: 58)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.text.opacity(0.1)))
        .overlay(alignment: .topTrailing) {
            Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { store.remove(item) } } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.text.opacity(0.7))
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: -4)
            .accessibilityLabel("Remove \(item.name)")
        }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider(object: item.url as NSURL) }
        .transition(.scale.combined(with: .opacity))
        .accessibilityLabel(item.name)
    }

    private func load(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                guard let data = data as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { store.add([url]) }
                }
            }
        }
    }
}
