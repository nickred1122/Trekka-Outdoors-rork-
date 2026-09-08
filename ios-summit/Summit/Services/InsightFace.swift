import Foundation
import WidgetKit

/// The observation the iPhone home-screen widget is allowed to see.
///
/// The widget runs in its own process, so the app and the extension meet in the
/// shared App Group container. This file is duplicated verbatim in
/// `SummitLiveActivity` — the two copies must stay identical.
///
/// Only what is already measured travels: the headline line is formatted on the
/// phone, in the athlete's own units, so the widget never has to work anything
/// out and can never disagree with the app about a number.
nonisolated enum InsightFace {
    static let appGroup = "group.app.rork.eeq1re3rqvs8qh5xs7zq8"
    static let widgetKind = "SummitInsightWidget"
    private static let storageKey = "insight.face.v1"

    /// How an observation reads, kept as a string rather than sharing the app's
    /// own enum so the extension needs none of the app's model layer.
    nonisolated enum Tone: String, Codable, Sendable {
        case positive
        case neutral
        case caution
    }

    nonisolated struct Line: Codable, Sendable, Identifiable {
        var id: String
        var title: String
        var detail: String
        var symbol: String
        var tone: Tone
    }

    nonisolated struct Snapshot: Codable, Sendable {
        /// Newest first, and never more than three: a widget that lists
        /// everything gets read as wallpaper.
        var lines: [Line]
        var updatedAt: Date

        var headline: Line? { lines.first }
    }

    private static var store: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    /// `nil` when the phone has nothing honest to say yet, which the widget shows
    /// as a prompt rather than as an empty card.
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
