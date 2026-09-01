import Foundation
import CoreLocation

nonisolated struct WatchRoutePoint: Codable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double
    var elevation: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

nonisolated struct WatchWaypoint: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var name: String
    var point: WatchRoutePoint
    /// Distance from the route start, in metres.
    var distanceAlongRoute: Double

    var coordinate: CLLocationCoordinate2D { point.coordinate }
}

/// A route pushed from the phone and cached on the watch for offline navigation.
nonisolated struct WatchRoute: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var name: String
    var sport: WatchSport = .trailRun
    var points: [WatchRoutePoint]
    var waypoints: [WatchWaypoint] = []
    var hasOfflineMap: Bool = true

    var coordinates: [CLLocationCoordinate2D] { points.map(\.coordinate) }

    var distance: Double { WatchRouteMath.distance(of: points) }
    var elevationGain: Double { WatchRouteMath.elevationGain(of: points) }
    var minElevation: Double { points.map(\.elevation).min() ?? 0 }
    var maxElevation: Double { points.map(\.elevation).max() ?? 0 }

    func estimatedDuration(for sport: WatchSport) -> TimeInterval {
        guard distance > 0, sport.estimatedSpeed > 0 else { return 0 }
        return distance / sport.estimatedSpeed + elevationGain * 7.2
    }
}

nonisolated enum WatchRouteMath {
    static func distance(of points: [WatchRoutePoint]) -> Double {
        guard points.count > 1 else { return 0 }
        var total: Double = 0
        for index in 1..<points.count {
            total += metres(from: points[index - 1], to: points[index])
        }
        return total
    }

    static func elevationGain(of points: [WatchRoutePoint]) -> Double {
        guard points.count > 1 else { return 0 }
        var gain: Double = 0
        for index in 1..<points.count {
            let delta = points[index].elevation - points[index - 1].elevation
            if delta > 0 { gain += delta }
        }
        return gain
    }

    /// Positive climb still between the given point on the route and its end —
    /// the elevation the athlete has yet to earn.
    static func ascentRemaining(from index: Int, in points: [WatchRoutePoint]) -> Double {
        guard points.indices.contains(index) else { return 0 }
        var gain = 0.0
        for position in (index + 1)..<points.count {
            let delta = points[position].elevation - points[position - 1].elevation
            if delta > 0 { gain += delta }
        }
        return gain
    }

    /// Descent still between the given point on the route and its end.
    static func descentRemaining(from index: Int, in points: [WatchRoutePoint]) -> Double {
        guard points.indices.contains(index) else { return 0 }
        var drop = 0.0
        for position in (index + 1)..<points.count {
            let delta = points[position - 1].elevation - points[position].elevation
            if delta > 0 { drop += delta }
        }
        return drop
    }

    static func cumulativeDistances(of points: [WatchRoutePoint]) -> [Double] {
        guard !points.isEmpty else { return [] }
        var result: [Double] = [0]
        guard points.count > 1 else { return result }
        var running: Double = 0
        for index in 1..<points.count {
            running += metres(from: points[index - 1], to: points[index])
            result.append(running)
        }
        return result
    }

    static func metres(from: WatchRoutePoint, to: WatchRoutePoint) -> Double {
        let start = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let end = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return end.distance(from: start)
    }

    static func metres(from coordinate: CLLocationCoordinate2D, to point: WatchRoutePoint) -> Double {
        let start = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let end = CLLocation(latitude: point.latitude, longitude: point.longitude)
        return end.distance(from: start)
    }

    /// Index of the route point closest to a coordinate, plus that distance.
    static func nearestIndex(to coordinate: CLLocationCoordinate2D, in points: [WatchRoutePoint]) -> (index: Int, distance: Double) {
        guard !points.isEmpty else { return (0, .infinity) }
        var bestIndex = 0
        var bestDistance = Double.infinity
        for (index, point) in points.enumerated() {
            let candidate = metres(from: coordinate, to: point)
            if candidate < bestDistance {
                bestDistance = candidate
                bestIndex = index
            }
        }
        return (bestIndex, bestDistance)
    }
}
