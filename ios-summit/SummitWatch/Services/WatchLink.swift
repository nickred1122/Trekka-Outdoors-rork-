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
    private(set) var lastInventorySentAt: Date?

    private weak var settings: WatchScreenSettings?
    private weak var routeStore: WatchRouteStore?
    private weak var dashboard: WatchDashboardStore?
    private weak var mapPacks: WatchMapPackStore?

    /// Packs whose bytes are already safely on disk but which arrived before
    /// the stores were wired up — a real case, because a file transfer wakes
    /// the app and can be delivered before any view has appeared.
    private var pendingPackIDs: [UUID] = []

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
        // Anything that changes what is stored here tells the phone, so the
        // phone can show the watch's real contents instead of its own guess
        // about what it once sent.
        mapPacks.onInventoryChanged = { [weak self] in
            self?.sendInventory()
        }

        activate()
        applyPendingContext()
        // Already-activated sessions skip the activation callback, so report
        // the screen size here too; the delegate call covers the cold start.
        sendScreenInfo()

        // Adopt anything that landed while the app was still starting up.
        let pending = pendingPackIDs
        pendingPackIDs = []
        for packID in pending {
            mapPacks.adopt(packID: packID)
        }

        sendInventory()
    }

    /// Reads whatever the phone left in the application context before launch.
    private func applyPendingContext() {
        guard WCSession.isSupported() else { return }
        apply(context: WCSession.default.receivedApplicationContext)
    }

    /// Sets the delegate and brings the session up.
    ///
    /// Called at app launch rather than when the first view appears. The
    /// difference matters: WatchConnectivity launches the watch app in the
    /// background to hand over a file, and a session with no delegate at that
    /// moment is a pack that never arrives.
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

    /// Tells the phone exactly which maps and routes are on this watch.
    ///
    /// Sent whenever the contents change and whenever the phone asks. Rides as
    /// user info so it queues until the phone is reachable — the athlete may
    /// well have downloaded a map on the wrist with the phone left at home.
    @discardableResult
    func sendInventory() -> Bool {
        guard let mapPacks else { return false }
        let inventory = mapPacks.report(routes: routeStore?.routes ?? [])
        guard let data = try? JSONEncoder().encode(inventory) else { return false }
        let sent = transfer(kind: "inventory", data: data)
        if sent { lastInventorySentAt = Date() }
        return sent
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
            self.sendInventory()
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
        let kind = userInfo["kind"] as? String
        let payload = userInfo["payload"] as? Data

        switch kind {
        case "routes":
            guard let payload,
                  let routes = try? JSONDecoder().decode([WatchRoute].self, from: payload) else { return }
            Task { @MainActor in
                self.lastRoutesAt = Date()
                self.routeStore?.upsert(routes)
                // The route list is part of what the phone is shown, so a new
                // route changes the inventory too.
                self.sendInventory()
            }
        case "inventoryRequest":
            Task { @MainActor in
                self.sendInventory()
            }
        case "deletePack":
            guard let payload,
                  let text = String(data: payload, encoding: .utf8),
                  let packID = UUID(uuidString: text) else { return }
            Task { @MainActor in
                self.mapPacks?.delete(packID: packID)
            }
        default:
            break
        }
    }

    /// An offline map pack arriving from the phone.
    ///
    /// The system hands over a URL in a temporary place it reclaims the moment
    /// this returns, and it calls here on a background thread. So the bytes are
    /// moved to their final home synchronously, before anything hops to the
    /// main actor — waiting would risk the file being reclaimed first, which is
    /// precisely how a pack goes missing after the phone said it sent one.
    ///
    /// Because the move lands the file exactly where the store looks, a pack
    /// survives even if nothing is listening yet: the next launch finds it.
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard file.metadata?["kind"] as? String == "mapPack",
              let regionID = file.metadata?["regionID"] as? String,
              let packID = UUID(uuidString: regionID) else { return }

        guard WatchMapPackStore.receive(fileURL: file.fileURL, packID: packID) else { return }

        Task { @MainActor in
            if let mapPacks = self.mapPacks {
                mapPacks.adopt(packID: packID)
            } else {
                // Nothing to adopt into yet; the bytes are safe on disk and
                // `configure` will pick this up.
                self.pendingPackIDs.append(packID)
            }
        }
    }
}
