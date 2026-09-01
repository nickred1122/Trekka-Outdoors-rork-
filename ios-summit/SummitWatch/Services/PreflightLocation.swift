import Foundation
import CoreLocation
import Observation

/// Warms the GPS receiver on the setup screen, before a workout starts.
///
/// A cold receiver takes anywhere from a few seconds to well over a minute to
/// settle, and until now the athlete found that out only after tapping Start —
/// either by watching a held clock, or worse, by recording a first kilometre
/// that wandered through the neighbours' gardens. Listening here means the fix
/// is already good by the time the workout begins, and the athlete can see that
/// it is rather than guessing.
///
/// It also genuinely speeds the fix up: the receiver is warm and has current
/// ephemeris by the time recording starts, instead of beginning from cold.
@Observable
final class PreflightLocation: NSObject, CLLocationManagerDelegate {
    /// Best accuracy seen so far, in metres. Zero means nothing yet.
    private(set) var accuracy: Double = 0
    private(set) var isDenied = false
    /// Whether the receiver is currently listening.
    private(set) var isRunning = false

    private let manager = CLLocationManager()

    /// Good enough to start a workout on: matches the engine's own trusted
    /// threshold, so a lock shown here means the same thing the recorder means.
    private static let lockedAccuracy: Double = 20

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .fitness
    }

    var isLocked: Bool {
        accuracy > 0 && accuracy <= Self.lockedAccuracy
    }

    /// Three bars at the same thresholds the live workout badge uses, so the
    /// signal does not appear to change the instant recording begins.
    var bars: Int {
        guard accuracy > 0 else { return 0 }
        if accuracy < 8 { return 3 }
        if accuracy < 20 { return 2 }
        return 1
    }

    /// What the receiver is doing, in words worth reading mid-warm-up.
    var statusText: String {
        if isDenied { return "Location access is off" }
        guard accuracy > 0 else { return "Searching for satellites" }
        let value = WatchFormat.shortDistance(accuracy)
        let unit = WatchFormat.shortDistanceUnit(accuracy)
        return isLocked ? "Accurate to \(value) \(unit)" : "Weak signal · \(value) \(unit)"
    }

    func start() {
        guard !isRunning else { return }
        switch manager.authorizationStatus {
        case .denied, .restricted:
            isDenied = true
            return
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
        isDenied = false
        isRunning = true
        manager.startUpdatingLocation()
    }

    /// Stopped the moment the screen goes away. The receiver is the single
    /// most expensive thing on the watch, and leaving it running behind a
    /// screen nobody is looking at would cost the athlete real hours.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        manager.stopUpdatingLocation()
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        let best: Double? = locations
            .map(\.horizontalAccuracy)
            .filter { $0 > 0 }
            .min()
        guard let best else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Always the newest reading rather than the best ever seen: a fix
            // that has degraded since should say so, not keep showing the good
            // number it managed a minute ago.
            self.accuracy = best
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Expected under tree cover and in canyons; the next fix usually lands.
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch status {
            case .denied, .restricted:
                self.isDenied = true
                self.stop()
            case .authorizedWhenInUse, .authorizedAlways:
                self.isDenied = false
                if self.isRunning { manager.startUpdatingLocation() }
            default:
                break
            }
        }
    }
}
