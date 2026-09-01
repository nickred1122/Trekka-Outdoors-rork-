import Foundation
import CoreLocation

/// A latitude/longitude box.
///
/// What survives of the old offline-map model: the elevation tile service still
/// needs to know the ground a route covers in order to fetch a profile for it.
nonisolated struct RegionBounds: Codable, Hashable, Sendable {
    var minLatitude: Double
    var maxLatitude: Double
    var minLongitude: Double
    var maxLongitude: Double

    var latitudeSpan: Double { maxLatitude - minLatitude }
    var longitudeSpan: Double { maxLongitude - minLongitude }

    var centre: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
    }

    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        coordinate.latitude >= minLatitude && coordinate.latitude <= maxLatitude
            && coordinate.longitude >= minLongitude && coordinate.longitude <= maxLongitude
    }

    var widthKilometres: Double {
        max(0, longitudeSpan * 111.0 * cos(centre.latitude * .pi / 180))
    }

    var heightKilometres: Double {
        max(0, latitudeSpan * 111.0)
    }

    /// Grows the box by a margin in metres on every side.
    func padded(byMetres metres: Double) -> RegionBounds {
        let latPad = metres / 111_000
        let lonPad = metres / (111_000 * max(0.2, cos(centre.latitude * .pi / 180)))
        return RegionBounds(
            minLatitude: minLatitude - latPad,
            maxLatitude: maxLatitude + latPad,
            minLongitude: minLongitude - lonPad,
            maxLongitude: maxLongitude + lonPad
        )
    }

    /// Tight box around a set of route points.
    static func around(_ points: [RoutePoint]) -> RegionBounds? {
        guard let first = points.first else { return nil }
        var bounds = RegionBounds(
            minLatitude: first.latitude,
            maxLatitude: first.latitude,
            minLongitude: first.longitude,
            maxLongitude: first.longitude
        )
        for point in points.dropFirst() {
            bounds.minLatitude = min(bounds.minLatitude, point.latitude)
            bounds.maxLatitude = max(bounds.maxLatitude, point.latitude)
            bounds.minLongitude = min(bounds.minLongitude, point.longitude)
            bounds.maxLongitude = max(bounds.maxLongitude, point.longitude)
        }
        return bounds
    }
}
