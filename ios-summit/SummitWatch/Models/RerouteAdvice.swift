import Foundation
import CoreLocation

/// Cheap geodesy for the navigation loop.
///
/// These run once or twice a second against hundreds of points, so they use a
/// flat-earth approximation instead of `CLLocation.distance(from:)`. At the
/// scale of a route corridor the error is well under a metre.
nonisolated enum GeoMath {
    static func metres(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let latitudeScale = 111_320.0
        let longitudeScale = 111_320.0 * max(0.05, cos(from.latitude * .pi / 180))
        let dx = (to.longitude - from.longitude) * longitudeScale
        let dy = (to.latitude - from.latitude) * latitudeScale
        return (dx * dx + dy * dy).squareRoot()
    }

    /// True bearing in degrees, 0 = north, clockwise.
    static func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let fromLatitude = from.latitude * .pi / 180
        let toLatitude = to.latitude * .pi / 180
        let deltaLongitude = (to.longitude - from.longitude) * .pi / 180

        let y = sin(deltaLongitude) * cos(toLatitude)
        let x = cos(fromLatitude) * sin(toLatitude)
            - sin(fromLatitude) * cos(toLatitude) * cos(deltaLongitude)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }
}

/// How to get back on a route after wandering off it.
///
/// There is no routing server on a mountain, so this never invents new trail.
/// It either points straight at the nearest point of the course, or walks you
/// back along the ground you already covered — which is known-passable by
/// definition, and is usually the safer answer in steep terrain.
nonisolated struct RerouteAdvice: Sendable, Equatable {
    enum Strategy: String, Sendable {
        /// Head straight for the closest point on the route.
        case direct
        /// Retrace your own breadcrumbs to where you left the route.
        case backtrack

        var title: String {
            switch self {
            case .direct: "Rejoin route"
            case .backtrack: "Retrace your steps"
            }
        }

        var symbol: String {
            switch self {
            case .direct: "arrow.turn.up.right"
            case .backtrack: "arrow.uturn.backward"
            }
        }
    }

    var strategy: Strategy
    /// The path to follow back, starting at the athlete's position.
    var guidance: [WatchRoutePoint]
    /// Length of that path in metres.
    var distance: Double
    /// True bearing to the next step of the path.
    var bearing: Double
    /// Index on the route where the path rejoins it.
    var rejoinIndex: Int

    var target: WatchRoutePoint? { guidance.last }

    var coordinates: [CLLocationCoordinate2D] { guidance.map(\.coordinate) }

    /// Bearing relative to where the athlete is currently facing.
    func relativeBearing(heading: Double) -> Double {
        (bearing - heading + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Plain-language turn hint for the current heading.
    func turnHint(heading: Double) -> String {
        let relative = relativeBearing(heading: heading)
        switch relative {
        case ..<20, 340...: return "Straight ahead"
        case ..<70: return "Bear right"
        case ..<110: return "Turn right"
        case ..<160: return "Sharp right"
        case ..<200: return "Turn around"
        case ..<250: return "Sharp left"
        case ..<290: return "Turn left"
        default: return "Bear left"
        }
    }
}
