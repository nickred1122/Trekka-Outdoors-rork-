import Foundation
import Observation
import WatchConnectivity

/// A finished watch workout crossing back to the phone over WatchConnectivity.
/// The phone app encodes/decodes the same shape.
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

/// This watch's physical screen, so the phone can size its layout builder to
/// what the wrist can actually hold.
nonisolated struct WatchScreenInfo: Codable, Sendable {
    var screenWidth: Double
    var screenHeight: Double
}

/// The watch's end of the phone bridge.
///
/// The phone pushes the designed layout through the application context and
/// routes as background user-info transfers; finished workouts travel back
/// the other way. Everything lands in the stores the watch app already reads.
@Observable
final class WatchLink: NSObject, WCSessionDelegate {
    static let shared = WatchLink()

    private(set) var lastLayoutAt: Date?
    private(set) var lastRoutesAt: Date?
    private(set) var lastDashboardAt: Date?

    private weak var settings: WatchScreenSettings?
    private weak var routeStore: WatchRouteStore?
    private weak var dashboard: WatchDashboardStore?
    private weak var mapPacks: WatchMapPackStore?

    private override init() {
        super.init()
    }

    func configure(
        settings: WatchScreenSettings,
        routeStore: WatchRouteStore,
        dashboard: WatchDashboardStore,
        mapPacks: WatchMapPackStore
    ) {
        self.settings = settings
        self.routeStore = routeStore
        self.dashboard = dashboard
        self.mapPacks = mapPacks

        // Wrist edits mirror straight back to the phone.
        dashboard.onPreferencesChanged = { [weak self] preferences in
            self?.sendPreferences(preferences)
        }
        settings.onLocalChange = { [weak self] data in
            self?.sendSettings(data)
        }

        activate()
        applyPendingContext()
        // Already-activated sessions skip the activation callback, so report
        // the screen size here too; the delegate call covers the cold start.
        sendScreenInfo()
    }

    /// Reads whatever the phone left in the application context before launch.
    private func applyPendingContext() {
        guard WCSession.isSupported() else { return }
        apply(context: WCSession.default.receivedApplicationContext)
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        if session.activationState != .activated {
            session.activate()
        }
    }

    // MARK: - Watch → Phone

    @discardableResult
    func sendWorkout(_ summary: WorkoutSummaryTransfer) -> Bool {
        guard WCSession.isSupported() else { return false }
        let session = WCSession.default
        guard session.activationState == .activated,
              let data = try? JSONEncoder().encode(summary) else { return false }
        session.transferUserInfo(["kind": "workout", "payload": data])
        return true
    }

    /// Sends a dashboard rearranged on the wrist.
    @discardableResult
    func sendPreferences(_ preferences: DashboardPreferencesTransfer) -> Bool {
        guard let data = try? JSONEncoder().encode(preferences) else { return false }
        return transfer(kind: "preferences", data: data)
    }

    /// Sends workout-screen and behaviour changes made on the wrist.
    @discardableResult
    func sendSettings(_ data: Data) -> Bool {
        transfer(kind: "settings", data: data)
    }

    /// Tells the phone how large this screen is, so the phone's layout builder
    /// only offers shapes this wrist can hold. Rides as user info, which queues
    /// until the phone is reachable, exactly like the other watch→phone payloads.
    @discardableResult
    func sendScreenInfo() -> Bool {
        guard WCSession.isSupported() else { return false }
        let session = WCSession.default
        guard session.activationState == .activated,
              let data = try? JSONEncoder().encode(WatchScreenInfo(
                  screenWidth: WatchDisplay.size.width,
                  screenHeight: WatchDisplay.size.height
              )) else { return false }
        session.transferUserInfo(["kind": "device", "payload": data])
        return true
    }

    private func transfer(kind: String, data: Data) -> Bool {
        guard WCSession.isSupported() else { return false }
        let session = WCSession.default
        guard session.activationState == .activated else { return false }
        session.transferUserInfo(["kind": kind, "payload": data])
        return true
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        Task { @MainActor in
            self.apply(context: context)
            self.sendScreenInfo()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.apply(context: applicationContext)
        }
    }

    /// The context carries every phone-authoritative payload at once, so each
    /// key is applied independently.
    private func apply(context: [String: Any]) {
        if let data = context["layout"] as? Data {
            lastLayoutAt = Date()
            settings?.applyIncoming(data)
        }
        if let data = context["dashboard"] as? Data,
           let transfer = try? JSONDecoder().decode(DashboardTransfer.self, from: data) {
            lastDashboardAt = Date()
            dashboard?.apply(transfer)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo["payload"] as? Data else { return }
        switch userInfo["kind"] as? String {
        case "routes":
            guard let routes = try? JSONDecoder().decode([WatchRoute].self, from: data) else { return }
            Task { @MainActor in
                self.lastRoutesAt = Date()
                self.routeStore?.upsert(routes)
            }
        default:
            break
        }
    }

    /// An offline map pack arriving from the phone.
    ///
    /// The system hands over a URL in a temporary place it reclaims the moment
    /// this returns, so the file has to be taken hold of synchronously rather
    /// than after an await. It is copied here and moved into place by the store.
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard file.metadata?["kind"] as? String == "mapPack",
              let regionID = file.metadata?["regionID"] as? String,
              let packID = UUID(uuidString: regionID) else { return }

        let staged = FileManager.default.temporaryDirectory
            .appendingPathComponent("incoming-\(packID.uuidString).trekkapack")
        do {
            if FileManager.default.fileExists(atPath: staged.path) {
                try FileManager.default.removeItem(at: staged)
            }
            try FileManager.default.copyItem(at: file.fileURL, to: staged)
        } catch {
            return
        }

        Task { @MainActor in
            self.mapPacks?.ingest(fileURL: staged, packID: packID)
        }
    }
}
