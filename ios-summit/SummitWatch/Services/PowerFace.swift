import Foundation
import WidgetKit

/// The slice of workout state the watch face complication is allowed to see,
/// and the channel the complication uses to arm power saver.
///
/// The widget runs in its own process, so app and extension meet in the shared
/// App Group container. This file is duplicated verbatim in `SummitWatchWidget`
/// — the two copies must stay identical.
nonisolated enum PowerFace {
    static let appGroup = "group.app.rork.eeq1re3rqvs8qh5xs7zq8"
    static let widgetKind = "SummitPowerWidget"
    private static let storageKey = "power.face.v1"

    nonisolated struct Snapshot: Codable, Sendable {
        var isPowerSaving: Bool = false
        var isWorkoutActive: Bool = false
        var batteryFraction: Double = 1
        var usesGPS: Bool = true
        var keepsScreenOn: Bool = true
        var sportTitle: String = "Ready"
        var updatedAt: Date = .now

        /// Recording time left, measured by the watch from its own battery
        /// drain. `nil` means not enough has been observed yet to say — the
        /// complication prints `--` rather than inventing a figure.
        var projectedHours: Double?

        /// Set by the complication, consumed by the app.
        var requestedPowerSaving: Bool?
        var requestedAt: Date?
    }

    private static var store: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    static func load() -> Snapshot {
        guard let data = store?.data(forKey: storageKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return Snapshot()
        }
        return snapshot
    }

    static func save(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        store?.set(data, forKey: storageKey)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    /// Called from the complication. The app picks this up on its next tick or
    /// the next time it comes forward.
    static func request(_ enabled: Bool) {
        var snapshot = load()
        snapshot.requestedPowerSaving = enabled
        snapshot.requestedAt = .now
        // Reflect it immediately so the face does not lag behind the tap.
        snapshot.isPowerSaving = enabled
        snapshot.updatedAt = .now
        save(snapshot)
    }
}
