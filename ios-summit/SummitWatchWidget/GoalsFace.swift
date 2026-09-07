import Foundation
import WidgetKit

/// The one daily goal the watch face complication is allowed to see.
///
/// The complication runs in its own process, so app and extension meet in the
/// shared App Group container. This file is duplicated verbatim in
/// `SummitWatchWidget` — the two copies must stay identical.
///
/// Only one goal is published, and it is the first the athlete set rather than
/// whichever happens to look best. A face has room for one number, and choosing
/// it for them would be the app deciding what they care about.
nonisolated enum GoalsFace {
    static let appGroup = "group.app.rork.eeq1re3rqvs8qh5xs7zq8"
    static let widgetKind = "SummitGoalsWidget"
    private static let storageKey = "goals.face.v1"

    nonisolated struct Snapshot: Codable, Sendable {
        var metric: String
        var title: String
        var symbol: String
        /// Already formatted on the phone, in the athlete's own units.
        var valueText: String
        var targetText: String
        var fraction: Double
        var streak: Int
        var updatedAt: Date

        var isMet: Bool { fraction >= 1 }
    }

    private static var store: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    /// `nil` when no goal has been set, which the complication shows as a prompt
    /// rather than as a ring stuck at zero.
    static func load() -> Snapshot? {
        guard let data = store?.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    static func save(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        store?.set(data, forKey: storageKey)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    static func clear() {
        guard store?.data(forKey: storageKey) != nil else { return }
        store?.removeObject(forKey: storageKey)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }
}
