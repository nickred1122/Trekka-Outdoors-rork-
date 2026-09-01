import Foundation
import CoreLocation

/// A stored coordinate that survives encoding to disk.
nonisolated struct RoutePoint: Codable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double
    var elevation: Double
    /// When this fix was recorded. Only set on tracks the app captured live, so
    /// the route written to Apple Health carries real times rather than guesses.
    /// Optional so routes saved before this existed still decode.
    var timestamp: Date?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(latitude: Double, longitude: Double, elevation: Double = 0, timestamp: Date? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.elevation = elevation
        self.timestamp = timestamp
    }

    init(coordinate: CLLocationCoordinate2D, elevation: Double = 0, timestamp: Date? = nil) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.elevation = elevation
        self.timestamp = timestamp
    }
}

/// A named point of interest along a route.
nonisolated struct Waypoint: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var name: String
    var note: String
    var point: RoutePoint
    /// Distance from the route start, in metres.
    var distanceAlongRoute: Double

    var coordinate: CLLocationCoordinate2D { point.coordinate }
    var elevation: Double { point.elevation }
}

nonisolated enum RouteSource: String, Codable, CaseIterable, Sendable {
    case mine = "My Routes"
    case imported = "Imported"
    case shared = "Shared"
}

nonisolated enum RouteActivityType: String, Codable, CaseIterable, Sendable {
    case run = "Trail Run"
    case ride = "Ride"
    case hike = "Hike"

    var symbol: String {
        switch self {
        case .run: "figure.run"
        case .ride: "bicycle"
        case .hike: "figure.hiking"
        }
    }

    /// Rough moving speed in metres per second, used for time estimates.
    var estimatedSpeed: Double {
        switch self {
        case .run: 2.9
        case .ride: 5.6
        case .hike: 1.3
        }
    }
}

/// A planned route with its track, waypoints and offline map state.
nonisolated struct PlannedRoute: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var source: RouteSource = .mine
    var activity: RouteActivityType = .run
    var points: [RoutePoint]
    var waypoints: [Waypoint] = []
    var createdAt: Date = Date()
    var isOfflineDownloaded: Bool = false
    var isSyncedToWatch: Bool = false

    var coordinates: [CLLocationCoordinate2D] { points.map(\.coordinate) }

    /// Total route length in metres.
    var distance: Double {
        RouteMath.distance(of: points)
    }

    /// Cumulative positive elevation change in metres.
    var elevationGain: Double {
        RouteMath.elevationGain(of: points)
    }

    var minElevation: Double { points.map(\.elevation).min() ?? 0 }
    var maxElevation: Double { points.map(\.elevation).max() ?? 0 }

    var estimatedDuration: TimeInterval {
        guard distance > 0 else { return 0 }
        // Naismith-style correction: add time for climbing.
        return distance / activity.estimatedSpeed + elevationGain * 7.2
    }

    /// Approximate size of the offline topo pack covering this route.
    var offlineMapSizeMB: Int {
        max(8, Int((distance / 1000) * 2.5) + 12)
    }
}

nonisolated enum RouteMath {
    static func distance(of points: [RoutePoint]) -> Double {
        guard points.count > 1 else { return 0 }
        var total: Double = 0
        for index in 1..<points.count {
            let previous = CLLocation(latitude: points[index - 1].latitude, longitude: points[index - 1].longitude)
            let current = CLLocation(latitude: points[index].latitude, longitude: points[index].longitude)
            total += current.distance(from: previous)
        }
        return total
    }

    static func elevationGain(of points: [RoutePoint]) -> Double {
        guard points.count > 1 else { return 0 }
        var gain: Double = 0
        for index in 1..<points.count {
            let delta = points[index].elevation - points[index - 1].elevation
            if delta > 0 { gain += delta }
        }
        return gain
    }

    /// Cumulative distance in metres at each point index.
    static func cumulativeDistances(of points: [RoutePoint]) -> [Double] {
        guard !points.isEmpty else { return [] }
        var result: [Double] = [0]
        guard points.count > 1 else { return result }
        var running: Double = 0
        for index in 1..<points.count {
            let previous = CLLocation(latitude: points[index - 1].latitude, longitude: points[index - 1].longitude)
            let current = CLLocation(latitude: points[index].latitude, longitude: points[index].longitude)
            running += current.distance(from: previous)
            result.append(running)
        }
        return result
    }

    /// Shortest distance in metres from a coordinate to the route track.
    static func distanceFromTrack(_ coordinate: CLLocationCoordinate2D, points: [RoutePoint]) -> Double {
        guard !points.isEmpty else { return .infinity }
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return points.reduce(Double.infinity) { partial, point in
            min(partial, location.distance(from: CLLocation(latitude: point.latitude, longitude: point.longitude)))
        }
    }
}
