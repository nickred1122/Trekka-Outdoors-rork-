import Foundation
import Observation
import WatchConnectivity

/// A finished watch workout crossing back to the phone over WatchConnectivity.
///
/// The watch app encodes the same shape, so this decodes natively on the other end.
nonisolated struct WorkoutSummaryTransfer: Codable, Sendable {
    nonisolated struct TrackPoint: Codable, Sendable {
        var latitude: Double
        var longitude: Double
        var elevation: Double
    }

    var id: UUID
    var sport: String
    var routeName: String?
    var startDate: Date
    var duration: TimeInterval
    var distance: Double
    var ascent: Double
    var calories: Double
    var averageHeartRate: Double
    var maxHeartRate: Double
    var trainingEffect: Double
    var zoneSeconds: [Double]
    var track: [TrackPoint]
}

/// The paired watch's physical screen, reported by the watch itself so the
/// phone's layout builder can offer only what that wrist can hold.
nonisolated struct WatchScreenInfo: Codable, Sendable {
    var screenWidth: Double
    var screenHeight: Double
}

/// The phone's end of the watch bridge.
///
/// Layouts ride in the application context (always-latest wins), routes travel
/// as background user-info transfers that queue until the watch is reachable,
/// and finished watch workouts arrive as user info going the other way.
@Observable
final class WatchLink: NSObject, WCSessionDelegate {
    static let shared = WatchLink()

    private(set) var isPaired = false
    private(set) var isWatchAppInstalled = false
    private(set) var isReachable = false
    private(set) var lastWorkout: WorkoutSummaryTransfer?
    private(set) var lastDashboardPushAt: Date?
    private(set) var lastWatchEditAt: Date?
    private(set) var lastWatchEditSummary: String?
    /// The paired watch's screen width in points, once the watch has reported
    /// it. nil until the first sync, and remembered across launches.
    private(set) var pairedWatchWidth: Double?

    /// What the actual wrist can hold. The ceiling until the watch reports its
    /// size — limits only ever tighten once the width is known.
    var watchCapacity: WatchPageCapacity {
        guard let pairedWatchWidth else { return .ceiling }
        return WatchPageCapacity.forScreen(width: pairedWatchWidth)
    }

    private let watchWidthKey = "watch.screen.width"

    /// Set by the app root so finished watch workouts land in the activity store.
    var onWorkout: ((ActivityRecord) -> Void)?
    /// Dashboard edits made on the watch.
    var onPreferences: ((DashboardPreferencesTransfer) -> Void)?
    /// Watch screen/behaviour edits made on the watch, as the shared layout document.
    var onWatchSettings: ((Data) -> Void)?

    /// The application context is a single dictionary that replaces wholesale,
    /// so every payload it carries is merged here before sending.
    private var contextValues: [String: Any] = [:]

    private override init() {
        super.init()
        pairedWatchWidth = UserDefaults.standard.object(forKey: watchWidthKey) as? Double
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        refresh(session)
    }

    // MARK: - Phone → Watch

    @discardableResult
    func sendLayout(_ data: Data) -> Bool {
        updateContext(key: "layout", data: data)
    }

    /// Mirrors the Today dashboard — preferences, tile readings, recovery and history.
    @discardableResult
    func sendDashboard(_ transfer: DashboardTransfer) -> Bool {
        guard let data = try? JSONEncoder().encode(transfer) else { return false }
        let sent = updateContext(key: "dashboard", data: data)
        if sent { lastDashboardPushAt = .now }
        return sent
    }

    @discardableResult
    private func updateContext(key: String, data: Data) -> Bool {
        contextValues[key] = data
        contextValues["sentAt"] = Date()
        guard let session = activeSession() else { return false }
        do {
            try session.updateApplicationContext(contextValues)
            return true
        } catch {
            return false
        }
    }

    /// Ships an offline map pack as a background file transfer. Packs are far too
    /// large for the application context, and a file transfer survives the phone
    /// going back in a pocket mid-send.
    @discardableResult
    func sendMapPack(fileURL: URL, regionID: String, name: String, sizeBytes: Int) -> Bool {
        guard let session = activeSession() else { return false }
        session.transferFile(fileURL, metadata: [
            "kind": "mapPack",
            "regionID": regionID,
            "name": name,
            "sizeBytes": sizeBytes,
        ])
        return true
    }

    @discardableResult
    func sendRoutes(_ routes: [WatchRouteTransfer]) -> Bool {
        guard let session = activeSession(), let data = try? JSONEncoder().encode(routes) else { return false }
        session.transferUserInfo(["kind": "routes", "payload": data])
        return true
    }

    private func activeSession() -> WCSession? {
        guard WCSession.isSupported() else { return nil }
        let session = WCSession.default
        guard session.activationState == .activated, session.isWatchAppInstalled else { return nil }
        return session
    }

    private func refresh(_ session: WCSession) {
        isPaired = session.isPaired
        isWatchAppInstalled = session.isWatchAppInstalled
        isReachable = session.isReachable
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.refresh(session)
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.refresh(session)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo["payload"] as? Data else { return }

        switch userInfo["kind"] as? String {
        case "workout":
            guard let summary = try? JSONDecoder().decode(WorkoutSummaryTransfer.self, from: data) else { return }
            Task { @MainActor in
                self.lastWorkout = summary
                self.onWorkout?(summary.asActivityRecord())
            }
        case "preferences":
            guard let prefs = try? JSONDecoder().decode(DashboardPreferencesTransfer.self, from: data) else { return }
            Task { @MainActor in
                self.noteWatchEdit("Dashboard rearranged on your watch")
                self.onPreferences?(prefs)
            }
        case "settings":
            Task { @MainActor in
                self.noteWatchEdit("Workout screens edited on your watch")
                self.onWatchSettings?(data)
            }
        case "device":
            guard let info = try? JSONDecoder().decode(WatchScreenInfo.self, from: data) else { return }
            Task { @MainActor in
                self.pairedWatchWidth = info.screenWidth
                UserDefaults.standard.set(info.screenWidth, forKey: self.watchWidthKey)
            }
        default:
            break
        }
    }

    private func noteWatchEdit(_ summary: String) {
        lastWatchEditAt = .now
        lastWatchEditSummary = summary
    }
}

extension WorkoutSummaryTransfer {
    /// Turns the watch payload into a storable phone-side activity.
    func asActivityRecord() -> ActivityRecord {
        let profile = WatchSportProfile(rawValue: sport)

        var zones = [Double](repeating: 0, count: 5)
        for (index, seconds) in zoneSeconds.enumerated() where zones.indices.contains(index) {
            zones[index] = seconds / 60
        }

        return ActivityRecord(
            id: id,
            name: routeName ?? "\(profile?.title ?? sport) · Watch",
            activity: Self.routeActivity(for: profile?.family),
            startDate: startDate,
            duration: duration,
            distance: distance,
            elevationGain: ascent,
            averageHeartRate: averageHeartRate,
            calories: calories,
            trainingEffect: trainingEffect,
            track: track.map { RoutePoint(latitude: $0.latitude, longitude: $0.longitude, elevation: $0.elevation) },
            zoneMinutes: zones
        )
    }

    private static func routeActivity(for family: WatchSportFamily?) -> RouteActivityType {
        switch family {
        case .ride: return .ride
        case .run: return .run
        default: return .hike
        }
    }
}
