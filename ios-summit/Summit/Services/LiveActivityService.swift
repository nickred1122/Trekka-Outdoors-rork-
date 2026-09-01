import ActivityKit
import Foundation

/// Puts the running workout on the lock screen and in the Dynamic Island.
///
/// The phone spends most of a workout in a pocket. This is the surface that
/// makes it useful anyway: distance, pace and heart rate readable without
/// unlocking anything, and the route you are following shown as real progress
/// rather than a notification.
///
/// Updates are deliberately rare. iOS gives a Live Activity a small budget of
/// updates and throttles an app that burns through it, so the clock is handed to
/// the system to tick on its own and everything else is pushed roughly every ten
/// seconds — or immediately when something actually happens, like a pause or a
/// new waypoint, because those are the moments a stale card would be wrong.
@MainActor
final class LiveActivityService {
    static let shared = LiveActivityService()

    private var activity: Activity<TrekkaWorkoutAttributes>?
    private var lastPush: Date?
    private var lastWaypointName: String?

    /// Long enough to stay well inside the system's budget for a session of
    /// several hours, short enough that a glance is never badly out of date.
    private let minimumGap: TimeInterval = 10

    private init() {}

    /// Whether the device and the user's settings allow this at all.
    ///
    /// Live Activities can be switched off per app in Settings, and are absent
    /// on older hardware, so this is asked rather than assumed.
    var isAvailable: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    var isRunning: Bool { activity != nil }

    // MARK: - Lifecycle

    func start(activity kind: RouteActivityType, route: PlannedRoute?) {
        guard isAvailable, self.activity == nil else { return }

        let attributes = TrekkaWorkoutAttributes(
            activityTitle: kind.rawValue,
            activitySymbol: kind.symbol,
            routeName: route?.name
        )
        let initial = TrekkaWorkoutAttributes.ContentState(
            startedAt: Date(),
            pausedElapsed: nil,
            distanceText: Formatters.distance(0),
            distanceUnit: Formatters.units.distanceUnit,
            paceText: "--:--",
            paceUnit: Formatters.units.paceUnit,
            heartRateText: "--",
            ascentText: "0",
            ascentUnit: Formatters.units.elevationUnit,
            routeProgress: route == nil ? nil : 0,
            nextWaypointName: route?.waypoints.first?.name,
            distanceToWaypointText: nil
        )

        do {
            self.activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: initial, staleDate: nil),
                pushType: nil
            )
            lastPush = Date()
            lastWaypointName = initial.nextWaypointName
        } catch {
            // A refused request is not worth interrupting a workout over. The
            // session records exactly the same either way.
            self.activity = nil
        }
    }

    /// Pushes the current numbers, subject to the update budget.
    ///
    /// - Parameter force: bypasses the throttle for a change the athlete caused
    ///   and would expect to see straight away.
    func update(from tracker: WorkoutTracker, force: Bool = false) {
        guard let activity else { return }

        let waypointName = tracker.nextWaypoint?.name
        let waypointChanged = waypointName != lastWaypointName
        let isDue = lastPush.map { Date().timeIntervalSince($0) >= minimumGap } ?? true
        guard force || waypointChanged || isDue else { return }

        lastPush = Date()
        lastWaypointName = waypointName

        let state = TrekkaWorkoutAttributes.ContentState(
            // Recomputed on every push rather than stored once, so the system's
            // own clock is pulled back into line with the recorded elapsed time
            // instead of drifting away from it over a long day.
            startedAt: Date().addingTimeInterval(-tracker.elapsed),
            pausedElapsed: tracker.state == .paused ? tracker.elapsed : nil,
            distanceText: Formatters.distance(tracker.distance),
            distanceUnit: Formatters.units.distanceUnit,
            paceText: Formatters.pace(tracker.currentPace),
            paceUnit: Formatters.units.paceUnit,
            heartRateText: tracker.heartRate > 0 ? Formatters.integer(tracker.heartRate) : "--",
            ascentText: Formatters.elevation(tracker.elevationGain),
            ascentUnit: Formatters.units.elevationUnit,
            routeProgress: tracker.route == nil ? nil : tracker.progressAlongRoute,
            nextWaypointName: waypointName,
            distanceToWaypointText: tracker.nextWaypoint == nil
                ? nil
                : "\(Formatters.shortDistance(tracker.distanceToNextTurn)) \(Formatters.units.shortDistanceUnit)"
        )

        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    func end() {
        guard let activity else { return }
        self.activity = nil
        lastPush = nil
        lastWaypointName = nil
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
