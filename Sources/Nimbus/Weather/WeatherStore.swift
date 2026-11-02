import Foundation

struct WeatherConfig: Codable, Equatable {
    var city = ""
    var fahrenheit = false
}

struct HourPoint: Identifiable, Equatable {
    var id: Date { time }
    var time: Date
    var temp: Int
    var code: Int
}

struct WeatherSnapshot: Equatable {
    var place: String
    var temp: Int
    var code: Int
    var isDay: Bool
    var high: Int
    var low: Int
    var hours: [HourPoint]
}

/// Current conditions from Open-Meteo (no API key). Only the city name you type is sent.
@MainActor
final class WeatherStore: ObservableObject {
    enum State: Equatable { case needsCity, loading, ready, failed(String) }

    private static let configKey = "nimbus.weather.config.v1"

    @Published private(set) var state = State.needsCity
    @Published private(set) var snapshot: WeatherSnapshot?
    @Published var config: WeatherConfig { didSet { save() } }

    private var pollTask: Task<Void, Never>?
    private var lastFetch = Date.distantPast
    private var resolved: (city: String, lat: Double, lon: Double, name: String)?
    private var isDemo = false

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.configKey),
           let saved = try? JSONDecoder().decode(WeatherConfig.self, from: data) {
            config = saved
        } else {
            config = WeatherConfig()
        }
    }

    func start() {
        guard pollTask == nil, !isDemo else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.fetch()
                try? await Task.sleep(for: .seconds(30 * 60))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refreshIfStale() {
        guard !isDemo, Date().timeIntervalSince(lastFetch) > 10 * 60 else { return }
        Task { await fetch() }
    }

    /// After the city or units change in Settings.
    func reload() {
        resolved = nil
        Task { await fetch() }
    }

    // MARK: Fetching

    private func fetch() async {
        guard !isDemo else { return }
        // NIMBUS_CITY lets tests try a city without saving it.
        let city = (ProcessInfo.processInfo.environment["NIMBUS_CITY"] ?? config.city).trimmingCharacters(in: .whitespaces)
        guard !city.isEmpty else {
            state = .needsCity
            snapshot = nil
            return
        }
        if snapshot == nil { state = .loading }
        do {
            if resolved?.city != city { resolved = try await geocode(city) }
            guard let place = resolved else { return }
            snapshot = try await forecast(place)
            lastFetch = Date()
            state = .ready
        } catch {
            state = .failed((error as? WeatherError)?.message ?? "Couldn't load the weather.")
        }
    }

    private struct WeatherError: Error { let message: String }

    private func geocode(_ city: String) async throws -> (city: String, lat: Double, lon: Double, name: String) {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [.init(name: "name", value: city), .init(name: "count", value: "1")]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        struct Result: Decodable { var name: String; var latitude: Double; var longitude: Double }
        struct Response: Decodable { var results: [Result]? }
        guard let hit = try JSONDecoder().decode(Response.self, from: data).results?.first
        else { throw WeatherError(message: "Couldn't find \"\(city)\".") }
        return (city, hit.latitude, hit.longitude, hit.name)
    }

    private func forecast(_ place: (city: String, lat: Double, lon: Double, name: String)) async throws -> WeatherSnapshot {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(place.lat)),
            .init(name: "longitude", value: String(place.lon)),
            .init(name: "current", value: "temperature_2m,weather_code,is_day"),
            .init(name: "hourly", value: "temperature_2m,weather_code"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "2"),
            .init(name: "temperature_unit", value: config.fahrenheit ? "fahrenheit" : "celsius"),
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)

        struct Current: Decodable { var temperature_2m: Double; var weather_code: Int; var is_day: Int }
        struct Hourly: Decodable { var time: [String]; var temperature_2m: [Double]; var weather_code: [Int] }
        struct Daily: Decodable { var temperature_2m_max: [Double]; var temperature_2m_min: [Double] }
        struct Response: Decodable { var current: Current; var hourly: Hourly; var daily: Daily }
        let r = try JSONDecoder().decode(Response.self, from: data)

        // Open-Meteo returns local times without an offset, so parse them in the place's zone.
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let now = Date()
        var hours: [HourPoint] = []
        for (i, text) in r.hourly.time.enumerated() {
            guard let t = formatter.date(from: text), t > now.addingTimeInterval(-3600) else { continue }
            hours.append(HourPoint(time: t, temp: Int(r.hourly.temperature_2m[i].rounded()), code: r.hourly.weather_code[i]))
        }
        // Every second hour reads better than every hour in a small island.
        let picked = hours.enumerated().filter { $0.offset % 2 == 0 }.prefix(4).map(\.element)

        return WeatherSnapshot(
            place: place.name,
            temp: Int(r.current.temperature_2m.rounded()),
            code: r.current.weather_code,
            isDay: r.current.is_day == 1,
            high: Int((r.daily.temperature_2m_max.first ?? 0).rounded()),
            low: Int((r.daily.temperature_2m_min.first ?? 0).rounded()),
            hours: Array(picked)
        )
    }

    func loadDemo() {
        isDemo = true
        let now = Date()
        snapshot = WeatherSnapshot(
            place: "Chennai", temp: 18, code: 2, isDay: true, high: 21, low: 12,
            hours: (0..<4).map { HourPoint(time: now.addingTimeInterval(Double($0) * 7200), temp: [19, 21, 20, 17][$0], code: [2, 1, 3, 61][$0]) }
        )
        state = .ready
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: Self.configKey)
    }
}

/// WMO weather codes as used by Open-Meteo.
enum WeatherCode {
    static func symbol(_ code: Int, isDay: Bool = true) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 80...82: return "cloud.heavyrain.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    static func text(_ code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog"
        case 51...57: return "Drizzle"
        case 61...67: return "Rain"
        case 71...77, 85, 86: return "Snow"
        case 80...82: return "Showers"
        case 95...99: return "Thunderstorm"
        default: return "Cloudy"
        }
    }
}
