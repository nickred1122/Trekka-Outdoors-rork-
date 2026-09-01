import ActivityKit
import Foundation

/// The live workout as the lock screen and Dynamic Island see it.
///
/// This file is deliberately duplicated, byte for byte, into the Live Activity
/// extension. An extension is a separate process with its own binary, so a type
/// crossing between them has to exist in both — and the encoded shape is the
/// contract, so the two copies must never be allowed to drift.
///
/// Everything here is a finished string rather than a raw number. The app owns
/// the unit setting and the formatters; the lock screen is a display surface and
/// should not be able to disagree with the app about what a distance reads as.
/// The one exception is the clock, which is a date so the system can tick it
/// smoothly without the app pushing an update every second.
nonisolated struct TrekkaWorkoutAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        /// When the elapsed clock should count from. Shifted forward on every
        /// resume so the running total stays correct across pauses.
        var startedAt: Date
        /// Elapsed time frozen at the moment of pausing, so a paused activity
        /// shows a still number instead of a clock that keeps running.
        var pausedElapsed: TimeInterval?

        var distanceText: String
        var distanceUnit: String
        var paceText: String
        var paceUnit: String
        var heartRateText: String
        var ascentText: String
        var ascentUnit: String

        /// Progress along the planned route, 0–1, when one is being followed.
        var routeProgress: Double?
        var nextWaypointName: String?
        var distanceToWaypointText: String?

        var isPaused: Bool { pausedElapsed != nil }
    }

    /// Fixed for the life of the workout.
    var activityTitle: String
    var activitySymbol: String
    var routeName: String?
}
