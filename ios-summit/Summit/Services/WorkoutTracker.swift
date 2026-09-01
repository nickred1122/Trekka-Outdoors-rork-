import Foundation
import CoreLocation
import Observation

nonisolated enum WorkoutState: Equatable, Sendable {
    case idle
    case running
    case paused
    case finished
}

nonisolated enum GPSQuality: Equatable, Sendable {
    case acquiring
    case live
    /// Fixes have stopped arriving. Nothing is recorded while this lasts —
    /// distance is never guessed to fill the gap.
    case noFix
    case denied
}

nonisolated struct LapRecord: Identifiable, Sendable, Equatable {
    let id = UUID()
    var index: Int
    var distance: Double
    var duration: TimeInterval
}

/// Drives a live workout: GPS track, distance, pace, elevation and zone time.
@Observable
final class WorkoutTracker {
    private(set) var state: WorkoutState = .idle
    private(set) var elapsed: TimeInterval = 0
    private(set) var distance: Double = 0
    private(set) var currentPace: TimeInterval = 0
    /// Only set when a real sensor supplies it; the phone alone has none.
    private(set) var heartRate: Double = 0
    private(set) var currentElevation: Double = 0
    private(set) var elevationGain: Double = 0
    private(set) var track: [RoutePoint] = []
    private(set) var laps: [LapRecord] = []
    private(set) var gpsQuality: GPSQuality = .acquiring
    private(set) var isOffRoute = false
    private(set) var distanceToNextTurn: Double = 0
    private(set) var nextWaypoint: Waypoint?
    private(set) var zoneSeconds: [Double] = [0, 0, 0, 0, 0]
    private(set) var activity: RouteActivityType = .run
    private(set) var route: PlannedRoute?

    private var timer: Task<Void, Never>?
    private var lastLapDistance: Double = 0
    private var lastLapTime: TimeInterval = 0
    private var secondsSinceFix: TimeInterval = 0
    private var recentPaceSamples: [Double] = []
    private let locationProvider = LocationProvider()

    /// Metres off the planned track before an off-route alert fires.
    private let offRouteThreshold: Double = 60

    var elapsedText: String { Formatters.duration(elapsed) }
    var heartRateZone: Int { Formatters.zone(forHeartRate: heartRate) }

    var progressAlongRoute: Double {
        guard let route, route.distance > 0 else { return 0 }
        return min(1, distance / route.distance)
    }

    func start(route: PlannedRoute?, activity: RouteActivityType) {
        self.route = route
        self.activity = activity
        state = .running
        elapsed = 0
        distance = 0
        elevationGain = 0
        track = []
        laps = []
        zoneSeconds = [0, 0, 0, 0, 0]
        lastLapDistance = 0
        lastLapTime = 0
        secondsSinceFix = 0
        heartRate = 0
        recentPaceSamples = []
        isOffRoute = false
        nextWaypoint = route?.waypoints.first
        currentElevation = route?.points.first?.elevation ?? 0
        gpsQuality = .acquiring

        locationProvider.start { [weak self] status in
            guard let self else { return }
            if status == .denied { gpsQuality = .denied }
        }
        startTimer()
    }

    func pause() {
        guard state == .running else { return }
        state = .paused
        timer?.cancel()
        timer = nil
    }

    func resume() {
        guard state == .paused else { return }
        state = .running
        startTimer()
    }

    func lap() {
        guard state == .running || state == .paused else { return }
        laps.append(
            LapRecord(
                index: laps.count + 1,
                distance: distance - lastLapDistance,
                duration: elapsed - lastLapTime
            )
        )
        lastLapDistance = distance
        lastLapTime = elapsed
    }

    /// Ends the session and returns a saveable record, or nil if nothing meaningful was captured.
    func finish() -> ActivityRecord? {
        timer?.cancel()
        timer = nil
        locationProvider.stop()
        state = .finished
        guard elapsed > 5 else { return nil }

        let average = zoneSeconds.enumerated().reduce(0.0) { partial, entry in
            partial + Double(entry.offset + 1) * entry.element
        }
        let totalZoneSeconds = zoneSeconds.reduce(0, +)
        let averageZone = totalZoneSeconds > 0 ? average / totalZoneSeconds : 3
        return ActivityRecord(
            name: sessionTitle(),
            activity: activity,
            startDate: Date().addingTimeInterval(-elapsed),
            duration: elapsed,
            distance: distance,
            elevationGain: elevationGain,
            averageHeartRate: heartRate > 0 ? heartRate : 0,
            calories: estimatedCalories(),
            trainingEffect: min(5, averageZone * (elapsed / 3_600) + 0.8),
            track: track,
            zoneMinutes: zoneSeconds.map { $0 / 60 }
        )
    }

    func reset() {
        timer?.cancel()
        timer = nil
        locationProvider.stop()
        state = .idle
        route = nil
    }

    // MARK: - Tick loop

    private func startTimer() {
        timer?.cancel()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, state == .running else { continue }
                tick()
            }
        }
    }

    private func tick() {
        elapsed += 1

        if let location = locationProvider.consumeLatest() {
            gpsQuality = .live
            secondsSinceFix = 0
            appendLive(location)
        } else if gpsQuality != .denied {
            secondsSinceFix += 1
            // Without a fix the track simply pauses. Inventing movement here
            // would put distance you never covered into Apple Health.
            if secondsSinceFix > 4 { gpsQuality = .noFix }
        }

        // Zone time is only credited when a real heart rate is available.
        if heartRate > 0 {
            zoneSeconds[max(0, min(4, heartRateZone - 1))] += 1
        }
        updateNavigation()
    }

    /// Feeds in a heart rate from a paired sensor or the watch.
    func updateHeartRate(_ bpm: Double) {
        guard bpm > 0 else { return }
        heartRate = bpm
    }

    private func appendLive(_ location: CLLocation) {
        // A barometric altitude is only trustworthy when CoreLocation vouches
        // for it; otherwise hold the last known height rather than guess.
        let elevation = location.verticalAccuracy > 0 ? location.altitude : currentElevation
        let point = RoutePoint(
            coordinate: location.coordinate,
            elevation: elevation,
            timestamp: location.timestamp
        )
        if let last = track.last {
            let step = CLLocation(latitude: last.latitude, longitude: last.longitude).distance(from: location)
            if step > 0.5 {
                distance += step
                recordPace(step: step)
            }
            if elevation > last.elevation { elevationGain += elevation - last.elevation }
        }
        currentElevation = elevation
        track.append(point)
    }

    private func recordPace(step: Double) {
        guard step > 0 else { return }
        let secondsPerKm = 1_000 / step
        recentPaceSamples.append(secondsPerKm)
        if recentPaceSamples.count > 20 { recentPaceSamples.removeFirst() }
        currentPace = recentPaceSamples.reduce(0, +) / Double(recentPaceSamples.count)
    }

    private func updateNavigation() {
        guard let route, let last = track.last else { return }
        let deviation = RouteMath.distanceFromTrack(last.coordinate, points: route.points)
        isOffRoute = deviation > offRouteThreshold
        let upcoming = route.waypoints
            .filter { $0.distanceAlongRoute > distance }
            .min { $0.distanceAlongRoute < $1.distanceAlongRoute }
        nextWaypoint = upcoming
        distanceToNextTurn = max(0, (upcoming?.distanceAlongRoute ?? route.distance) - distance)
    }

    private func estimatedCalories() -> Double {
        let minutes = elapsed / 60
        let base: Double = switch activity {
        case .run: 12.5
        case .ride: 9.5
        case .hike: 7.5
        }
        return minutes * base + elevationGain * 0.9
    }

    private func sessionTitle() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let period = switch hour {
        case 4..<11: "Morning"
        case 11..<15: "Midday"
        case 15..<19: "Afternoon"
        default: "Evening"
        }
        if let route { return "\(period) · \(route.name)" }
        return "\(period) \(activity.rawValue)"
    }
}

/// Thin CoreLocation wrapper that buffers the newest fix for the tracker to drain.
private nonisolated final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let lock = NSLock()
    private var latest: CLLocation?
    private var statusHandler: (@MainActor @Sendable (CLAuthorizationStatus) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .fitness
        manager.distanceFilter = 5
    }

    func start(statusHandler: @escaping @MainActor @Sendable (CLAuthorizationStatus) -> Void) {
        self.statusHandler = statusHandler
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
        lock.lock()
        latest = nil
        lock.unlock()
    }

    /// Returns and clears the newest fix, if one arrived since the last call.
    func consumeLatest() -> CLLocation? {
        lock.lock()
        defer { lock.unlock() }
        let value = latest
        latest = nil
        return value
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0, location.horizontalAccuracy < 100 else { return }
        lock.lock()
        latest = location
        lock.unlock()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let handler = statusHandler
        Task { @MainActor in
            handler?(status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A transient failure just means no new fix this tick; the tracker keeps its last position.
    }
}
