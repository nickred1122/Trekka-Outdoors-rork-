import Foundation
import CoreLocation

/// Names a framed map area after the place it covers, using Apple's reverse
/// geocoder.
///
/// This is a convenience, never a claim: if the lookup fails or there is no
/// signal, callers fall back to describing the box by its size. Results are
/// cached by a coarse coordinate key so panning around does not re-ask for
/// ground that was already named.
actor AreaNameService {
    static let shared = AreaNameService()

    private let geocoder = CLGeocoder()
    private var cache: [String: String] = [:]

    /// A place name for a coordinate, or `nil` when none could be found.
    func name(for coordinate: CLLocationCoordinate2D) async -> String? {
        let key = String(format: "%.2f,%.2f", coordinate.latitude, coordinate.longitude)
        if let cached = cache[key] { return cached }

        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let placemarks = try? await geocoder.reverseGeocodeLocation(location),
              let placemark = placemarks.first else { return nil }

        // Prefer the most specific label that still describes an area rather
        // than a street address.
        let candidates = [
            placemark.subLocality,
            placemark.locality,
            placemark.subAdministrativeArea,
            placemark.administrativeArea,
        ]
        guard let found = candidates.compactMap({ $0 }).first(where: { !$0.isEmpty }) else {
            return nil
        }
        cache[key] = found
        return found
    }
}
