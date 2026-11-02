import Combine
import SwiftUI

@MainActor
final class SystemStatsWidget: IslandWidget {
    let store = SystemStatsStore()

    let id = "stats"
    let title = "System stats"
    let subtitle = "CPU, memory and network speed"
    let symbol = "cpu"
    let defaultEnabled = false
    var requestPeek: ((Double) -> Void)?

    var compactPriority: Int? { nil }
    var changes: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }

    func loadDemo() { store.loadDemo() }

    func expandedView(topInset: CGFloat) -> AnyView {
        AnyView(SystemStatsExpandedView(store: store, topInset: topInset))
    }

    func expandedSize(settings: IslandSettings, closed: CGSize) -> CGSize {
        CGSize(width: settings.expandedWidth, height: min(settings.expandedHeight, 138))
    }
}

struct SystemStatsExpandedView: View {
    @ObservedObject var store: SystemStatsStore
    let topInset: CGFloat
    @Environment(\.islandTheme) private var theme

    var body: some View {
        WidgetFrame(headline: "System", topInset: topInset) {
            VStack(spacing: 9) {
                meter("CPU", store.cpu, Color(red: 0.38, green: 0.65, blue: 0.98)).reveal(1)
                meter("Memory", store.memory, Color(red: 1.0, green: 0.82, blue: 0.4)).reveal(2)
                HStack(spacing: 10) {
                    Text("Network").frame(width: 56, alignment: .leading).foregroundStyle(theme.text.opacity(0.7))
                    Image(systemName: "arrow.down").font(.system(size: 9, weight: .bold))
                    Text(SystemStatsStore.rate(store.down)).monospacedDigit()
                    Image(systemName: "arrow.up").font(.system(size: 9, weight: .bold)).padding(.leading, 6)
                    Text(SystemStatsStore.rate(store.up)).monospacedDigit()
                    Spacer(minLength: 0)
                }
                .font(.system(size: 11))
                .reveal(3)
            }
        }
        // Sampling only runs while this view is on screen.
        .onAppear { store.startSampling() }
        .onDisappear { store.stopSampling() }
    }

    private func meter(_ title: String, _ value: Double, _ color: Color) -> some View {
        HStack(spacing: 10) {
            Text(title).frame(width: 56, alignment: .leading).foregroundStyle(theme.text.opacity(0.7))
            Capsule().fill(theme.text.opacity(0.15)).frame(height: 6)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Capsule().fill(color).frame(width: geo.size.width * value)
                            .animation(.smooth(duration: 0.6), value: value)
                    }
                }
            Text("\(Int((value * 100).rounded()))%")
                .monospacedDigit().frame(width: 36, alignment: .trailing)
                .contentTransition(.numericText())
        }
        .font(.system(size: 11))
    }
}
