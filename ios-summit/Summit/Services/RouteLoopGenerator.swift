import Foundation
import CoreLocation

/// A loop the generator managed to route, and how close it landed.
nonisolated struct GeneratedLoop: Sendable {
    var nodes: [CLLocationCoordinate2D]
    var legs: [SnappedLeg]
    var distance: Double
    /// Share of the loop that follows real routed ways rather than straight
    /// lines. A low number means the area has little mapped path network, and
    /// the planner says so rather than pretending the loop is walkable.
    var snappedFraction: Double

    var isMostlyRouted: Bool { snappedFraction > 0.6 }
}

/// Builds a loop of roughly a chosen length that starts and finishes in the
/// same place.
///
/// This is the one thing a planner cannot do by drawing: you know you want ten
/// kilometres from the front door, and you do not much mind where it goes. The
/// shape is a rough circle sent out on a bearing, with its corners snapped onto
/// real paths — then the radius is corrected and the whole thing routed again,
/// because snapped ground is always longer than the straight polygon through it
/// and by an amount that depends entirely on the local path network.
///
/// Nothing is fabricated. Corners that cannot be reached by a real way fall back
/// to straight lines exactly as they do anywhere else in the planner, and the
/// result reports how much of itself is genuinely routed so the athlete can
/// judge it before saving.
@MainActor
enum RouteLoopGenerator {
    /// Corners in the loop. Four gives a shape that reads as a circuit rather
    /// than an out-and-back, without costing so many routing calls that the
    /// search takes all day.
    private static let corners = 4
    /// How many times the radius is corrected before settling.
    private static let maximumPasses = 4
    /// Close enough to stop early: within this share of the target.
    private static let tolerance = 0.06

    /// Routes a loop from `start` of about `targetMetres`, heading out on
    /// `bearingDegrees`.
    ///
    /// - Parameter onProgress: fraction complete, for the planner's progress
    ///   line. Each pass is several routing calls and takes a moment.
    static func loop(
        from start: CLLocationCoordinate2D,
        targetMetres: Double,
        bearingDegrees: Double,
        mode: RouteSnapMode,
        onProgress: @MainActor (Double) -> Void
    ) async -> GeneratedLoop? {
        guard targetMetres > 500 else { return nil }

        // A circle of circumference `target` has this radius. The real routed
        // line is always longer than the polygon through the same corners, so
        // this is only ever a starting guess.
        var radius = targetMetres / (2 * .pi)
        var best: GeneratedLoop?

        for pass in 0..<maximumPasses {
            onProgress(Double(pass) / Double(maximumPasses))

            let nodes = ring(around: start, radius: radius, bearingDegrees: bearingDegrees)
            var legs: [SnappedLeg] = []
            for index in 0..<(nodes.count - 1) {
                let leg = await RouteSnapService.shared.leg(
                    from: nodes[index],
                    to: nodes[index + 1],
                    mode: mode
                )
                legs.append(leg)
                if Task.isCancelled { return best }
            }

            let points = assemble(legs)
            let distance = RouteMath.distance(of: points)
            guard distance > 0 else { continue }

            let routed = legs.filter(\.isSnapped).reduce(0.0) { $0 + RouteMath.distance(of: $1.coordinates) }
            let candidate = GeneratedLoop(
                nodes: nodes,
                legs: legs,
                distance: distance,
                snappedFraction: distance > 0 ? routed / distance : 0
            )

            // Keep whichever pass landed closest to what was asked for.
            if best == nil || abs(distance - targetMetres) < abs(best!.distance - targetMetres) {
                best = candidate
            }

            let error = (distance - targetMetres) / targetMetres
            if abs(error) <= tolerance { break }

            // Correct the radius by the miss, damped so a wildly long first
            // pass does not send the next one collapsing into a point.
            let correction = targetMetres / distance
            radius *= (1 + (correction - 1) * 0.8)
            radius = max(120, radius)
        }

        onProgress(1)
        return best
    }

    /// Corner coordinates of the loop, starting and finishing at `start`.
    ///
    /// The ring is centred one radius out along the bearing, so the loop leaves
    /// in the direction asked for rather than surrounding the athlete.
    private static func ring(
        around start: CLLocationCoordinate2D,
        radius: Double,
        bearingDegrees: Double
    ) -> [CLLocationCoordinate2D] {
        let centre = coordinate(from: start, distanceMetres: radius, bearingDegrees: bearingDegrees)
        // The start sits on the ring at the bearing back towards itself, so the
        // corners are spread from there and the loop closes cleanly.
        let startAngle = bearingDegrees + 180

        var result: [CLLocationCoordinate2D] = [start]
        for index in 1..<corners {
            let angle = startAngle + (360.0 / Double(corners)) * Double(index)
            result.append(coordinate(from: centre, distanceMetres: radius, bearingDegrees: angle))
        }
        result.append(start)
        return result
    }

    /// Joins resolved legs into one continuous track without duplicating the
    /// shared point at each junction.
    private static func assemble(_ legs: [SnappedLeg]) -> [RoutePoint] {
        guard let first = legs.first?.coordinates.first else { return [] }
        var points: [RoutePoint] = [first]
        for leg in legs {
            points.append(contentsOf: leg.coordinates.dropFirst())
        }
        return points
    }

    /// A point a given distance and bearing from another, on a spherical Earth.
    static func coordinate(
        from origin: CLLocationCoordinate2D,
        distanceMetres: Double,
        bearingDegrees: Double
    ) -> CLLocationCoordinate2D {
        let earthRadius: Double = 6_371_000
        let angular = distanceMetres / earthRadius
        let bearing = bearingDegrees * .pi / 180
        let latitude = origin.latitude * .pi / 180
        let longitude = origin.longitude * .pi / 180

        let newLatitude = asin(
            sin(latitude) * cos(angular) + cos(latitude) * sin(angular) * cos(bearing)
        )
        let newLongitude = longitude + atan2(
            sin(bearing) * sin(angular) * cos(latitude),
            cos(angular) - sin(latitude) * sin(newLatitude)
        )

        return CLLocationCoordinate2D(
            latitude: newLatitude * 180 / .pi,
            // Wrapped, so a loop that crosses the date line does not fly around
            // the world.
            longitude: ((newLongitude * 180 / .pi) + 540).truncatingRemainder(dividingBy: 360) - 180
        )
    }
}
