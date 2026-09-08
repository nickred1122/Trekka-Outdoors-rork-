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

    /// Where the athlete stands in relation to the route line.
    ///
    /// Measured against the line itself rather than against the nearest recorded
    /// point. Routes are simplified before they are sent to the watch, so their
    /// points can be eighty metres apart on a straight section; somebody walking
    /// exactly down the middle of the course is then forty metres from every one
    /// of them, which was enough to raise an off-course alarm on a path they had
    /// never left. Projecting onto the segment gives the distance a walker would
    /// recognise: how far sideways they are from the path.
    nonisolated struct RoutePosition: Sendable, Equatable {
        /// The route point at or before the athlete.
        var index: Int
        /// Metres from the start of the route, interpolated inside the segment.
        var travelled: Double
        /// Metres sideways from the line.
        var offLine: Double
    }

    /// Projects a coordinate onto the segment a-b.
    ///
    /// Flat-earth arithmetic in metres relative to `a`: over a segment of a few
    /// hundred metres the curvature error is far below the accuracy of the fix
    /// being projected, and this runs across the whole route once a second.
    private static func project(
        _ coordinate: CLLocationCoordinate2D,
        onto a: WatchRoutePoint,
        _ b: WatchRoutePoint
    ) -> (fraction: Double, distance: Double) {
        let latitudeScale = 111_320.0
        let longitudeScale = 111_320.0 * max(0.05, cos(a.latitude * .pi / 180))

        let bx = (b.longitude - a.longitude) * longitudeScale
        let by = (b.latitude - a.latitude) * latitudeScale
        let px = (coordinate.longitude - a.longitude) * longitudeScale
        let py = (coordinate.latitude - a.latitude) * latitudeScale

        let lengthSquared = bx * bx + by * by
        guard lengthSquared > 0.01 else {
            return (0, (px * px + py * py).squareRoot())
        }
        let fraction = min(1, max(0, (px * bx + py * by) / lengthSquared))
        let dx = px - bx * fraction
        let dy = py - by * fraction
        return (fraction, (dx * dx + dy * dy).squareRoot())
    }

    /// Finds the athlete's position along the route, preferring the stretch they
    /// were on a moment ago.
    ///
    /// `hint` is the segment matched on the previous fix. Without it, an
    /// out-and-back or a figure-of-eight matches whichever leg happens to be a
    /// metre closer, so distance remaining lurches by the length of the route
    /// each time the two legs cross. Searching the neighbourhood first makes
    /// progress move the way the athlete does; the global search still runs when
    /// the local answer is poor, which is what recovers a genuine short-cut, a
    /// restart part-way round, or a route joined at the far end.
    static func position(
        of coordinate: CLLocationCoordinate2D,
        in points: [WatchRoutePoint],
        distances: [Double],
        near hint: Int? = nil,
        window: Int = 80,
        corridor: Double = 60
    ) -> RoutePosition {
        guard points.count > 1 else {
            let offLine = points.first.map { metres(from: coordinate, to: $0) } ?? .infinity
            return RoutePosition(index: 0, travelled: 0, offLine: offLine)
        }

        let segments = 0..<(points.count - 1)

        func best(in range: Range<Int>) -> RoutePosition? {
            var bestDistance = Double.infinity
            var result: RoutePosition?
            for index in range.clamped(to: segments) {
                let projection = project(coordinate, onto: points[index], points[index + 1])
                guard projection.distance < bestDistance else { continue }
                bestDistance = projection.distance
                let start = distances.indices.contains(index) ? distances[index] : 0
                let end = distances.indices.contains(index + 1) ? distances[index + 1] : start
                result = RoutePosition(
                    index: index,
                    travelled: start + (end - start) * projection.fraction,
                    offLine: projection.distance
                )
            }
            return result
        }

        if let hint, let local = best(in: (hint - window)..<(hint + window + 1)), local.offLine <= corridor {
            return local
        }

        return best(in: segments) ?? RoutePosition(index: 0, travelled: 0, offLine: .infinity)
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
