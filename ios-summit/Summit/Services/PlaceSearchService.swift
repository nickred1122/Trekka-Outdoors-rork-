import Foundation
import MapKit

/// A place the athlete can jump the map to.
nonisolated struct PlaceResult: Identifiable, Sendable, Hashable {
    let id = UUID()
    let name: String
    /// Where it is, and what it is part of — "Snowdonia, Wales" rather than a
    /// bare name that could be one of six places.
    let context: String
    let centre: CLLocationCoordinate2D
    /// Half the ground the place covers, in metres, from the search result's own
    /// bounding region. A national park comes back far larger than a trailhead,
    /// and the square should open at roughly the right size for what was asked.
    let radiusMetres: Double

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: PlaceResult, rhs: PlaceResult) -> Bool { lhs.id == rhs.id }
}

/// Finds places by name so an area download does not have to start with panning
/// across an ocean.
///
/// Uses Apple's own local search, which already knows national parks, states,
/// counties, towns and trailheads. It needs a connection — but so does every
/// download this screen exists to start, so nothing is lost by relying on it.
@MainActor
@Observable
final class PlaceSearchService {
    static let shared = PlaceSearchService()

    private(set) var results: [PlaceResult] = []
    private(set) var isSearching = false
    /// Set when a search came back with nothing, so the screen can say so rather
    /// than showing an empty list that looks like a stuck spinner.
    private(set) var foundNothing = false

    private var task: Task<Void, Never>?

    func search(_ query: String, near centre: CLLocationCoordinate2D?) {
        task?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.count >= 2 else {
            results = []
            isSearching = false
            foundNothing = false
            return
        }

        isSearching = true
        foundNothing = false

        task = Task { [weak self] in
            // Typing "Yosemite" fires eight searches without this; Apple's API
            // is rate limited and the intermediate answers are worthless.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await self?.run(trimmed, near: centre)
        }
    }

    func clear() {
        task?.cancel()
        results = []
        isSearching = false
        foundNothing = false
    }

    private func run(_ query: String, near centre: CLLocationCoordinate2D?) async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        // Addresses and points of interest both matter here: a national park is
        // an address-shaped result, a trailhead is a point of interest.
        request.resultTypes = [.address, .pointOfInterest]
        if let centre {
            // Biased towards where the athlete is looking, but wide enough that
            // searching for somewhere on the far side of the country still works.
            request.region = MKCoordinateRegion(
                center: centre,
                latitudinalMeters: 2_000_000,
                longitudinalMeters: 2_000_000
            )
        }

        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            guard !Task.isCancelled else { return }
            results = response.mapItems.prefix(8).compactMap(Self.result(from:))
            foundNothing = results.isEmpty
        } catch {
            guard !Task.isCancelled else { return }
            // A cancelled search is not a failure worth reporting — the athlete
            // simply kept typing.
            if (error as? MKError)?.code != .loadingThrottled {
                EventLog.shared.warning(
                    "Place search",
                    "Could not search for \u{201c}\(query)\u{201d}",
                    detail: error.localizedDescription
                )
            }
            results = []
            foundNothing = true
        }
        isSearching = false
    }

    private static func result(from item: MKMapItem) -> PlaceResult? {
        guard let name = item.name, !name.isEmpty else { return nil }
        let coordinate = item.placemark.coordinate
        guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }

        let placemark = item.placemark
        let context = [placemark.subAdministrativeArea, placemark.administrativeArea, placemark.country]
            .compactMap { $0 }
            .filter { !$0.isEmpty && $0 != name }
            .prefix(2)
            .joined(separator: ", ")

        return PlaceResult(
            name: name,
            context: context,
            centre: coordinate,
            radiusMetres: radius(for: item)
        )
    }

    /// The radius that best fits a result, from the region MapKit hands back.
    ///
    /// Clamped at both ends: a shop comes back with a region metres across, and
    /// a country comes back with one the size of a continent. Neither is a
    /// sensible square to open with.
    ///
    /// The ceiling is the *region* limit rather than the close-detail one on
    /// purpose. Searching for a state used to hand back a radius silently cut to
    /// 60 km, so the square opened over the middle of it and the athlete had no
    /// way to know the answer had been trimmed. The picker decides what to do
    /// with a large answer; the search's job is to report the real size.
    private static func radius(for item: MKMapItem) -> Double {
        let region = item.placemark.region as? CLCircularRegion
        let raw = region?.radius ?? 6_000
        return min(max(raw, 2_000), AreaDownloadLimits.maxRegionRadiusMetres)
    }
}

/// The sizes a hand-picked area is allowed to be.
///
/// Separate from the view so the drawing gesture, the slider and a place search
/// all clamp to the same numbers rather than three that drifted apart.
nonisolated enum AreaDownloadLimits {
    static let minRadiusMetres: Double = 1_000
    /// 120 km across. Beyond this the planner has already dropped every zoom
    /// level that shows a path, so the download would be a coloured blur.
    static let maxRadiusMetres: Double = 60_000

    /// The smallest a region download is worth being. Below this, close detail
    /// covers the same ground and actually shows the paths.
    static let minRegionRadiusMetres: Double = 20_000
    /// 600 km across — larger than all but a handful of states, and the point
    /// at which even road-atlas zoom levels stop fitting on a phone.
    static let maxRegionRadiusMetres: Double = 300_000
}
