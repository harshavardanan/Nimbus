import Combine
import SwiftUI

@MainActor
final class WeatherWidget: IslandWidget {
    let store = WeatherStore()

    let id = "weather"
    let title = "Weather"
    let subtitle = "Current conditions from Open-Meteo"
    let symbol = "cloud.sun.fill"
    let defaultEnabled = true
    var requestPeek: ((Double) -> Void)?

    var compactPriority: Int? { nil }
    var changes: AnyPublisher<Void, Never> { store.objectWillChange.map { _ in () }.eraseToAnyPublisher() }

    func start() { store.start() }
    func stop() { store.stop() }
    func loadDemo() { store.loadDemo() }

    func expandedView(topInset: CGFloat) -> AnyView {
        AnyView(WeatherExpandedView(store: store, topInset: topInset))
    }

    func expandedSize(settings: IslandSettings, closed: CGSize) -> CGSize {
        CGSize(width: settings.expandedWidth, height: settings.expandedHeight)
    }
}

struct WeatherExpandedView: View {
    @ObservedObject var store: WeatherStore
    let topInset: CGFloat
    @Environment(\.islandTheme) private var theme

    var body: some View {
        WidgetFrame(headline: store.snapshot?.place ?? "Weather", topInset: topInset) {
            switch store.state {
            case .needsCity:
                WidgetMessage(symbol: "location.magnifyingglass", text: "Type your city in Settings, under Widgets. Nothing else is shared.")
            case .loading:
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                WidgetMessage(symbol: "exclamationmark.triangle", text: message)
            case .ready:
                if let snap = store.snapshot { content(snap) }
            }
        }
        .onAppear { store.refreshIfStale() }
    }

    private func content(_ s: WeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Image(systemName: WeatherCode.symbol(s.code, isDay: s.isDay))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 34))
                    .frame(width: 44)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(s.temp)°").font(.system(size: 30, weight: .semibold)).contentTransition(.numericText())
                    Text("\(WeatherCode.text(s.code))  ·  H \(s.high)°  L \(s.low)°")
                        .font(.system(size: 12)).foregroundStyle(theme.text.opacity(0.7))
                }
                Spacer(minLength: 0)
            }
            .reveal(1)

            HStack {
                ForEach(s.hours) { hour in
                    VStack(spacing: 2) {
                        Text(hour.time.formatted(.dateTime.hour()))
                            .font(.system(size: 10)).foregroundStyle(theme.text.opacity(0.6))
                        Image(systemName: WeatherCode.symbol(hour.code))
                            .symbolRenderingMode(.multicolor).font(.system(size: 12))
                        Text("\(hour.temp)°").font(.system(size: 11, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .reveal(2)
        }
        .animation(.smooth(duration: 0.4), value: s)
    }
}

struct WeatherSettingsSection: View {
    @ObservedObject var store: WeatherStore

    var body: some View {
        Section("Weather") {
            TextField("City", text: $store.config.city)
                .onSubmit { store.reload() }
            Picker("Units", selection: $store.config.fahrenheit) {
                Text("Celsius").tag(false)
                Text("Fahrenheit").tag(true)
            }
            .pickerStyle(.segmented)
            .onChange(of: store.config.fahrenheit) { _, _ in store.reload() }
            Text("Press Return after typing a city. Only the city name is sent to Open-Meteo, no location or account.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
