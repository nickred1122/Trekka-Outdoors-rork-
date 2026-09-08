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
        /// When the fix was taken. Optional so summaries sent by earlier watch
        /// builds still decode — those tracks simply carry no clock, and anything
        /// that needs one has to say so rather than invent it.
        var time: Date?
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
    /// Sets logged in the gym on the wrist, weight always in kilograms.
    /// Optional so summaries sent by earlier watch builds still decode.
    var strengthSets: [StrengthSetTransfer]?

    /// One set as it was actually lifted, crossing from the wrist to the phone.
    nonisolated struct StrengthSetTransfer: Codable, Sendable, Hashable {
        var id: UUID
        var exercise: String
        var reps: Int
        var weightKilograms: Double
        var loggedAt: Date
    }
}

/// The paired watch's physical screen, reported by the watch itself so the
/// phone's layout builder can offer only what that wrist can hold.
nonisolated struct WatchScreenInfo: Codable, Sendable {
    var screenWidth: Double
    var screenHeight: Double
}

/// Why a map cannot be sent to the watch at this moment.
///
/// Worth naming rather than returning a bare `false`: "no watch paired" and
/// "the watch app is not installed" need different things from the athlete, and
/// telling them the wrong one wastes their time.
nonisolated enum WatchSendBlock: Equatable, Sendable {
    case unsupported
    case notPaired
    case appNotInstalled
    case notActivated

    var message: String {
        switch self {
        case .unsupported:
            "This iPhone cannot talk to an Apple Watch."
        case .notPaired:
            "No Apple Watch is paired with this iPhone."
        case .appNotInstalled:
            "Install Trekka on your Apple Watch, then send the map again."
        case .notActivated:
            "Still connecting to your Apple Watch. Try again in a moment."
        }
    }
}

/// Where one map's journey to the watch has got to.
///
/// A file transfer is not instant and can fail long after it was handed over,
/// so the phone tracks each one rather than assuming it worked. The previous
/// version reported success the moment the transfer was queued, which is how a
/// map could appear downloaded on the phone and be absent from the wrist.
nonisolated enum WatchPackTransfer: Equatable, Sendable {
    /// Handed to the system, which will deliver it when the watch is available.
    case sending
    /// The system confirmed delivery.
    case delivered
    case failed(String)

    var isSending: Bool { self == .sending }
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

    /// What the watch says it is carrying. Reported by the watch, never
    /// inferred here, and remembered across launches so the phone can show it
    /// before the watch has had a chance to check in again.
    private(set) var watchInventory: WatchInventory?

    /// Delivery state per map, keyed by pack id.
    private(set) var packTransfers: [UUID: WatchPackTransfer] = [:]

    /// What the actual wrist can hold. The ceiling until the watch reports its
    /// size — limits only ever tighten once the width is known.
    var watchCapacity: WatchPageCapacity {
        guard let pairedWatchWidth else { return .ceiling }
        return WatchPageCapacity.forScreen(width: pairedWatchWidth)
    }

    private let watchWidthKey = "watch.screen.width"
    private let inventoryKey = "watch.inventory.v1"

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
        if let data = UserDefaults.standard.data(forKey: inventoryKey),
           let stored = try? JSONDecoder().decode(WatchInventory.self, from: data) {
            watchInventory = stored
        }
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
    ///
    /// Returns nil once the transfer is under way, or why it could not start.
    /// Delivery itself is reported later, through `packTransfers`.
    func sendMapPack(fileURL: URL, packID: UUID, name: String, sizeBytes: Int) -> WatchSendBlock? {
        guard WCSession.isSupported() else { return .unsupported }
        let session = WCSession.default
        refresh(session)

        guard session.activationState == .activated else { return .notActivated }
        guard session.isPaired else { return .notPaired }
        guard session.isWatchAppInstalled else { return .appNotInstalled }

        session.transferFile(fileURL, metadata: [
            "kind": "mapPack",
            "regionID": packID.uuidString,
            "name": name,
            "sizeBytes": sizeBytes,
        ])
        packTransfers[packID] = .sending
        return nil
    }

    /// Asks the watch to delete a stored map.
    @discardableResult
    func requestPackDeletion(packID: UUID) -> Bool {
        guard let session = activeSession(),
              let data = packID.uuidString.data(using: .utf8) else { return false }
        session.transferUserInfo(["kind": "deletePack", "payload": data])
        return true
    }

    /// Asks the watch to report what it is carrying.
    @discardableResult
    func requestInventory() -> Bool {
        guard let session = activeSession() else { return false }
        session.transferUserInfo(["kind": "inventoryRequest", "payload": Data()])
        return true
    }

    /// Maps still in flight, straight from the system's own queue.
    var outstandingTransferCount: Int {
        guard WCSession.isSupported() else { return 0 }
        let session = WCSession.default
        guard session.activationState == .activated else { return 0 }
        return session.outstandingFileTransfers.count
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
            // The watch may have changed what it holds while the phone was
            // away — it could have downloaded a map on its own, or trimmed one.
            self.requestInventory()
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

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.refresh(session)
        }
    }

    /// The outcome of a map transfer, which is the only trustworthy signal that
    /// a map actually reached the wrist.
    ///
    /// Values are read out before hopping actors: `WCSessionFileTransfer` is not
    /// safe to carry across, and all that is needed from it is the pack id.
    nonisolated func session(
        _ session: WCSession,
        didFinish fileTransfer: WCSessionFileTransfer,
        error: Error?
    ) {
        let metadata = fileTransfer.file.metadata
        guard metadata?["kind"] as? String == "mapPack",
              let regionID = metadata?["regionID"] as? String,
              let packID = UUID(uuidString: regionID) else { return }
        let failure = error?.localizedDescription

        Task { @MainActor in
            if let failure {
                self.packTransfers[packID] = .failed(failure)
            } else {
                self.packTransfers[packID] = .delivered
                // Have the watch confirm it in its own words.
                self.requestInventory()
            }
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
        case "inventory":
            guard let inventory = try? JSONDecoder().decode(WatchInventory.self, from: data) else { return }
            Task { @MainActor in
                self.applyInventory(inventory, raw: data)
            }
        default:
            break
        }
    }

    /// Takes the watch at its word about its own contents.
    ///
    /// Transfer states are reconciled against it: a map the watch is holding is
    /// delivered whatever the transfer said, and one it is not holding has no
    /// business still claiming to be delivered.
    private func applyInventory(_ inventory: WatchInventory, raw: Data) {
        watchInventory = inventory
        UserDefaults.standard.set(raw, forKey: inventoryKey)

        for (packID, state) in packTransfers {
            if inventory.hasPack(id: packID) {
                packTransfers[packID] = .delivered
            } else if state == .delivered {
                packTransfers[packID] = nil
            }
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

        let sets = (strengthSets ?? []).map { set in
            StrengthSet(
                id: set.id,
                exercise: set.exercise,
                reps: set.reps,
                weightKilograms: set.weightKilograms,
                loggedAt: set.loggedAt
            )
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
            track: track.map {
                RoutePoint(
                    latitude: $0.latitude,
                    longitude: $0.longitude,
                    elevation: $0.elevation,
                    timestamp: $0.time
                )
            },
            zoneMinutes: zones,
            strengthSets: sets
        )
    }

    private static func routeActivity(for family: WatchSportFamily?) -> RouteActivityType {
        switch family {
        case .ride: return .ride
        case .run: return .run
        case .gym: return .strength
        default: return .hike
        }
    }
}
