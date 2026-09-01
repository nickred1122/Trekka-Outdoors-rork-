import CoreLocation
import Foundation
import Observation

/// Where the athlete is, for maps that are being *read* rather than recorded.
///
/// Deliberately separate from the workout tracker: opening a route to look at it
/// should not spin up a workout-grade GPS session. This asks for a coarser fix,
/// and stops as soon as the last map using it goes away.
///
/// Trekka's own map renderer draws everything itself, so unlike Apple's map view
/// it has no built-in notion of "you". This is where that comes from.
@Observable
final class MapLocationService {
    static let shared = MapLocationService()

    /// Nil until a fix arrives, so callers can tell "not yet" from "here".
    private(set) var coordinate: CLLocationCoordinate2D?
    private(set) var status: CLAuthorizationStatus = .notDetermined

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private lazy var relay: LocationRelay = {
        let relay = LocationRelay()
        relay.owner = self
        return relay
    }()
    /// How many maps are on screen. The fix stops when the last one leaves.
    @ObservationIgnored private var readers = 0

    private init() {
        // Ten metres is plenty to put a dot on a map being browsed, and costs a
        // fraction of the battery that navigation-grade accuracy would.
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 10
        manager.delegate = relay
        status = manager.authorizationStatus
    }

    /// True when no amount of asking will help, so the UI can say why.
    var isDenied: Bool {
        status == .denied || status == .restricted
    }

    var isAuthorized: Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }

    func start() {
        readers += 1
        guard readers == 1 else { return }
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.startUpdatingLocation()
    }

    func stop() {
        readers = max(0, readers - 1)
        guard readers == 0 else { return }
        manager.stopUpdatingLocation()
    }

    /// Prompts the first time the athlete asks to be located, so the button
    /// opens the permission sheet rather than appearing to do nothing.
    func requestAccess() {
        guard status == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    fileprivate func apply(latitude: Double, longitude: Double) {
        coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    fileprivate func apply(status newStatus: CLAuthorizationStatus) {
        status = newStatus
        // Permission granted while a map was already waiting: start now rather
        // than making the athlete tap the button a second time.
        if isAuthorized, readers > 0 {
            manager.startUpdatingLocation()
        }
    }
}

/// Carries delegate callbacks, which arrive off the main actor, back onto it.
private nonisolated final class LocationRelay: NSObject, CLLocationManagerDelegate {
    weak var owner: MapLocationService?

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let latitude: Double = last.coordinate.latitude
        let longitude: Double = last.coordinate.longitude
        Task { @MainActor [owner] in
            owner?.apply(latitude: latitude, longitude: longitude)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status: CLAuthorizationStatus = manager.authorizationStatus
        Task { @MainActor [owner] in
            owner?.apply(status: status)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A single failed fix is not worth surfacing; the next one usually
        // succeeds, and the map stays usable without one either way.
    }
}
