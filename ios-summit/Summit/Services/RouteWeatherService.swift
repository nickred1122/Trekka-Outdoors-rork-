import Foundation
import CoreLocation
import WeatherKit

/// The forecast for one hour at one point on a route.
nonisolated struct RouteHourForecast: Identifiable, Sendable, Hashable {
    var date: Date
    var temperature: Double
    var apparentTemperature: Double
    var windSpeed: Double
    var windDirection: Double
    var precipitationChance: Double
    var symbolName: String
    var conditionText: String
    var isDaylight: Bool

    var id: Date { date }
}

/// What the weather means for a particular outing, rather than a raw forecast.
nonisolated struct RouteWeather: Sendable, Equatable {
    /// The forecast at the start of the route.
    var hours: [RouteHourForecast]
    /// Conditions at the far end, when the route is long enough for them to
    /// differ. A ridge ten kilometres away can be in cloud while the car park is
    /// in sun, and that is exactly the thing worth knowing before setting off.
    var summitHours: [RouteHourForecast]
    /// True when start and far end were forecast separately.
    var hasSeparateSummit: Bool
    var summitPlaceLabel: String
    var fetchedAt: Date

    var now: RouteHourForecast? { hours.first }

    /// The kindest few hours to be out in, inside the next two days.
    ///
    /// Scored on rain first, then wind, then daylight — the order in which they
    /// actually ruin a day on the hill.
    var bestWindow: RouteWeatherWindow? {
        RouteWeatherWindow.best(in: hours)
    }
}

/// A stretch of hours worth recommending.
nonisolated struct RouteWeatherWindow: Sendable, Equatable {
    var start: Date
    var end: Date
    var precipitationChance: Double
    var windSpeed: Double
    var isFullyDaylight: Bool

    /// Finds the best three-hour stretch in the forecast.
    ///
    /// Returns nil rather than a bad recommendation when nothing on offer is
    /// actually pleasant — telling someone that 90% rain and a gale is their
    /// best window is worse than saying nothing.
    static func best(in hours: [RouteHourForecast]) -> RouteWeatherWindow? {
        let span = 3
        guard hours.count >= span else { return nil }

        var best: (score: Double, window: RouteWeatherWindow)?
        for index in 0...(hours.count - span) {
            let slice = Array(hours[index..<(index + span)])
            let rain = slice.map(\.precipitationChance).max() ?? 0
            let wind = slice.map(\.windSpeed).max() ?? 0
            let daylight = slice.allSatisfy(\.isDaylight)

            // Rain dominates, wind matters, darkness is a real penalty but not a
            // disqualification — head torches exist.
            var score = rain * 100 + wind * 1.5
            if !daylight { score += 25 }
            // A tie between now and tomorrow should resolve towards now.
            score += Double(index) * 0.4

            if best == nil || score < best!.score {
                best = (
                    score,
                    RouteWeatherWindow(
                        start: slice[0].date,
                        end: slice[span - 1].date.addingTimeInterval(3600),
                        precipitationChance: rain,
                        windSpeed: wind,
                        isFullyDaylight: daylight
                    )
                )
            }
        }

        guard let best, best.window.precipitationChance < 0.6 else { return nil }
        return best.window
    }
}

nonisolated enum RouteWeatherError: LocalizedError, Equatable {
    case noCoordinates
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .noCoordinates: "This route has no coordinates to forecast for."
        case .unavailable(let reason): reason
        }
    }
}

/// Fetches the forecast for a planned route from Apple's weather service.
///
/// Named for what it does rather than `WeatherService`, which is WeatherKit's
/// own type — the two would otherwise shadow each other in every file that
/// imports both.
///
/// Forecasts are cached for the hour, because a forecast does not change faster
/// than that and the service is rate-limited per app.
@MainActor
final class RouteWeatherService {
    static let shared = RouteWeatherService()

    private var cache: [UUID: RouteWeather] = [:]
    private let cacheLifetime: TimeInterval = 3600

    private init() {}

    /// The forecast for a route, from cache when it is still fresh.
    func weather(for route: PlannedRoute) async throws -> RouteWeather {
        if let cached = cache[route.id],
           Date().timeIntervalSince(cached.fetchedAt) < cacheLifetime {
            return cached
        }

        guard let start = route.points.first else { throw RouteWeatherError.noCoordinates }

        // The far end only gets its own forecast when it is far enough away, or
        // high enough above the start, for the weather there to genuinely
        // differ. Below that it is the same forecast twice and a wasted call.
        let far = farPoint(of: route)
        let startLocation = CLLocation(latitude: start.latitude, longitude: start.longitude)

        do {
            let service = WeatherKit.WeatherService.shared
            let startWeather = try await service.weather(for: startLocation, including: .hourly)
            let startHours = Self.map(startWeather.forecast)

            var summitHours: [RouteHourForecast] = []
            var hasSeparate = false
            if let far {
                let farLocation = CLLocation(latitude: far.latitude, longitude: far.longitude)
                let farWeather = try await service.weather(for: farLocation, including: .hourly)
                summitHours = Self.map(farWeather.forecast)
                hasSeparate = true
            }

            let result = RouteWeather(
                hours: startHours,
                summitHours: summitHours,
                hasSeparateSummit: hasSeparate,
                summitPlaceLabel: Self.summitLabel(for: route),
                fetchedAt: Date()
            )
            cache[route.id] = result
            return result
        } catch {
            throw RouteWeatherError.unavailable(
                "The forecast could not be loaded. Check your connection and try again."
            )
        }
    }

    func cached(for route: PlannedRoute) -> RouteWeather? {
        guard let cached = cache[route.id],
              Date().timeIntervalSince(cached.fetchedAt) < cacheLifetime else { return nil }
        return cached
    }

    /// The point on the route whose weather is most likely to differ from the
    /// start: the highest one, or failing that the furthest away.
    private func farPoint(of route: PlannedRoute) -> RoutePoint? {
        guard let start = route.points.first, route.points.count > 2 else { return nil }
        let startLocation = CLLocation(latitude: start.latitude, longitude: start.longitude)

        let highest = route.points.max { $0.elevation < $1.elevation }
        if let highest, highest.elevation - start.elevation > 250 { return highest }

        let furthest = route.points.max { first, second in
            startLocation.distance(from: CLLocation(latitude: first.latitude, longitude: first.longitude))
                < startLocation.distance(from: CLLocation(latitude: second.latitude, longitude: second.longitude))
        }
        guard let furthest else { return nil }
        let separation = startLocation.distance(
            from: CLLocation(latitude: furthest.latitude, longitude: furthest.longitude)
        )
        // Under five kilometres the two forecasts come from the same grid square
        // anyway, so there is nothing to learn from asking twice.
        return separation > 5000 ? furthest : nil
    }

    private static func summitLabel(for route: PlannedRoute) -> String {
        guard let start = route.points.first,
              let highest = route.points.max(by: { $0.elevation < $1.elevation }) else { return "Far end" }
        return highest.elevation - start.elevation > 250 ? "High point" : "Far end"
    }

    private static func map(_ forecast: [HourWeather]) -> [RouteHourForecast] {
        let now = Date().addingTimeInterval(-1800)
        return forecast
            .filter { $0.date >= now }
            .prefix(48)
            .map { hour in
                RouteHourForecast(
                    date: hour.date,
                    temperature: hour.temperature.converted(to: .celsius).value,
                    apparentTemperature: hour.apparentTemperature.converted(to: .celsius).value,
                    windSpeed: hour.wind.speed.converted(to: .kilometersPerHour).value,
                    windDirection: hour.wind.direction.converted(to: .degrees).value,
                    precipitationChance: hour.precipitationChance,
                    symbolName: hour.symbolName,
                    conditionText: hour.condition.description,
                    isDaylight: hour.isDaylight
                )
            }
    }
}
