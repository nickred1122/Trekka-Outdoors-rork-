import Foundation
import MapKit

/// How the planner joins two points you place on the map.
///
/// The three snapping modes ask Apple's routing service for a real line along
/// ground you can actually travel; `direct` draws the straight line you asked
/// for and says so.
nonisolated enum RouteSnapMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case foot
    case bike
    case road
    case direct

    var id: String { rawValue }

    var title: String {
        switch self {
        case .foot: "Foot"
        case .bike: "Bike"
        case .road: "Road"
        case .direct: "Direct"
        }
    }

    var symbol: String {
        switch self {
        case .foot: "figure.walk"
        case .bike: "bicycle"
        case .road: "road.lanes"
        case .direct: "line.diagonal"
        }
    }

    var summary: String {
        switch self {
        case .foot: "Follows trails, paths and pavements"
        case .bike: "Follows cycleways and bike-friendly roads"
        case .road: "Follows driveable roads"
        case .direct: "Straight lines — off-trail and cross-country"
        }
    }

    var transportType: MKDirectionsTransportType? {
        switch self {
        case .foot: .walking
        case .bike: .cycling
        case .road: .automobile
        case .direct: nil
        }
    }

    /// The mode that suits an activity when the planner opens.
    static func `default`(for activity: RouteActivityType) -> RouteSnapMode {
        switch activity {
        case .run, .hike: .foot
        case .ride: .bike
        }
    }
}

/// The geometry joining two placed nodes, and whether it is real routed ground.
nonisolated struct SnappedLeg: Sendable {
    /// Coordinates from the start node to the end node, inclusive.
    var coordinates: [RoutePoint]
    /// True when Apple's routing service returned a line along real ways.
    var isSnapped: Bool
    /// Set only when snapping was asked for and could not be delivered, so the
    /// planner can say why this stretch is a straight line.
    var failureReason: String?

    var isStraightFallback: Bool { !isSnapped && failureReason != nil }
}

/// Snaps planned segments onto real roads and trails using MapKit directions.
///
/// Nothing here fabricates a path. When the routing service has no way between
/// two points — remote backcountry, a closed area, or no connection — the leg
/// falls back to a straight line that is explicitly marked as one, so a plan
/// never implies a trail that may not exist.
@MainActor
final class RouteSnapService {
    static let shared = RouteSnapService()

    /// Resolved legs, so dragging a node back and forth or flipping modes does
    /// not hammer the routing service.
    private var cache: [Key: SnappedLeg] = [:]
    /// Serialises requests; MapKit throttles callers that burst.
    private var pending: Task<Void, Never>?
    private var lastRequestAt: Date?

    /// MapKit throttles hard when directions are requested in a burst, and a
    /// throttled request comes back as a straight line. Spacing them out costs a
    /// moment on a long stroke and is the difference between a route that
    /// follows the trails and one that cuts across fields.
    private let minimumRequestGap: TimeInterval = 0.35
    private let cacheLimit = 400
    /// How many times a throttled leg is retried before giving up on it.
    private let throttleRetryLimit = 2

    private init() {}

    private struct Key: Hashable {
        let startLat: Int
        let startLon: Int
        let endLat: Int
        let endLon: Int
        let mode: RouteSnapMode

        init(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, mode: RouteSnapMode) {
            // ~1 m resolution: fine enough that a redraw hits the cache, coarse
            // enough that float noise does not miss it.
            startLat = Int((from.latitude * 100_000).rounded())
            startLon = Int((from.longitude * 100_000).rounded())
            endLat = Int((to.latitude * 100_000).rounded())
            endLon = Int((to.longitude * 100_000).rounded())
            self.mode = mode
        }
    }

    /// Resolves the line between two points, snapping when the mode asks for it.
    func leg(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        mode: RouteSnapMode
    ) async -> SnappedLeg {
        guard let transportType = mode.transportType else {
            return SnappedLeg(coordinates: Self.straightLine(from: start, to: end), isSnapped: false)
        }

        let key = Key(from: start, to: end, mode: mode)
        if let cached = cache[key] { return cached }

        // A hop of a few metres is shorter than the road graph's own resolution;
        // routing it would bend the line onto a nearby centreline for no gain.
        let separation = CLLocation(latitude: start.latitude, longitude: start.longitude)
            .distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
        guard separation > 15 else {
            return SnappedLeg(coordinates: Self.straightLine(from: start, to: end), isSnapped: false)
        }

        await throttle()

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end))
        request.transportType = transportType
        request.requestsAlternateRoutes = false

        var attempt = 0
        while true {
            do {
                let response = try await MKDirections(request: request).calculate()
                guard let route = response.routes.first, route.polyline.pointCount > 1 else {
                    return fallback(
                        from: start,
                        to: end,
                        key: key,
                        reason: "No \(mode.title.lowercased()) route here",
                        isPermanent: true
                    )
                }
                let coordinates = Self.coordinates(of: route.polyline)
                let leg = SnappedLeg(coordinates: coordinates.map { RoutePoint(coordinate: $0) }, isSnapped: true)
                store(leg, for: key)
                return leg
            } catch {
                // Being told "too fast" is not being told "no road here". Backing
                // off and asking again is what turns a burst of straight lines
                // into the trails the athlete actually drew along.
                if Self.isThrottled(error), attempt < throttleRetryLimit {
                    attempt += 1
                    try? await Task.sleep(for: .seconds(Double(attempt) * 0.8))
                    continue
                }
                return fallback(
                    from: start,
                    to: end,
                    key: key,
                    reason: Self.reason(for: error, mode: mode),
                    isPermanent: Self.isPermanent(error)
                )
            }
        }
    }

    private static func isThrottled(_ error: Error) -> Bool {
        (error as? MKError)?.code == .loadingThrottled
    }

    /// True only when asking again could not possibly help.
    ///
    /// Ground with no path on it will still have no path in a minute. A throttle,
    /// a dropped connection or a server wobble is a different thing entirely, and
    /// remembering those as failures would strand the leg as a straight line for
    /// the rest of the session.
    private static func isPermanent(_ error: Error) -> Bool {
        guard let mkError = error as? MKError else { return false }
        switch mkError.code {
        case .directionsNotFound, .placemarkNotFound:
            return true
        default:
            return false
        }
    }

    /// Clears remembered legs, used when the planner starts a fresh route.
    func reset() {
        cache.removeAll(keepingCapacity: true)
    }

    // MARK: - Helpers

    private func fallback(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        key: Key,
        reason: String,
        isPermanent: Bool
    ) -> SnappedLeg {
        let leg = SnappedLeg(
            coordinates: Self.straightLine(from: start, to: end),
            isSnapped: false,
            failureReason: reason
        )
        // Only a permanent "there is no route here" is worth remembering. A
        // transient failure must stay uncached so the next attempt — nudging the
        // node, flipping the mode, coming back with signal — can still snap.
        if isPermanent {
            store(leg, for: key)
        }
        return leg
    }

    private func store(_ leg: SnappedLeg, for key: Key) {
        if cache.count >= cacheLimit { cache.removeAll(keepingCapacity: true) }
        cache[key] = leg
    }

    private func throttle() async {
        if let lastRequestAt {
            let elapsed = Date().timeIntervalSince(lastRequestAt)
            if elapsed < minimumRequestGap {
                try? await Task.sleep(for: .seconds(minimumRequestGap - elapsed))
            }
        }
        lastRequestAt = Date()
    }

    private static func reason(for error: Error, mode: RouteSnapMode) -> String {
        guard let mkError = error as? MKError else {
            return "Routing unavailable — straight line"
        }
        switch mkError.code {
        case .loadingThrottled:
            return "Routing busy — straight line for now"
        case .directionsNotFound:
            return "No \(mode.title.lowercased()) route here"
        case .placemarkNotFound:
            return "Nothing to snap to nearby"
        case .serverFailure:
            return "Routing offline — straight line"
        default:
            return "Routing unavailable — straight line"
        }
    }

    /// Evenly spaced points along the great-circle-ish straight line, so an
    /// unsnapped leg still has enough samples to profile elevation against.
    static func straightLine(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) -> [RoutePoint] {
        let metres = CLLocation(latitude: start.latitude, longitude: start.longitude)
            .distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
        let steps = max(1, min(120, Int(metres / 25)))
        return (0...steps).map { step in
            let t = Double(step) / Double(steps)
            return RoutePoint(
                latitude: start.latitude + (end.latitude - start.latitude) * t,
                longitude: start.longitude + (end.longitude - start.longitude) * t
            )
        }
    }

    private static func coordinates(of polyline: MKPolyline) -> [CLLocationCoordinate2D] {
        let count = polyline.pointCount
        var result = [CLLocationCoordinate2D](
            repeating: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            count: count
        )
        polyline.getCoordinates(&result, range: NSRange(location: 0, length: count))
        return result
    }
}
