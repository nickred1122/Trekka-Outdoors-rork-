import Foundation

// MARK: - Wire formats
//
// Duplicated verbatim from the phone target so both ends encode and decode the
// same JSON. Keep the property names identical on both sides.

nonisolated struct SyncTrackPoint: Codable, Sendable, Hashable {
    var latitude: Double
    var longitude: Double
    var elevation: Double
}

/// One resolved dashboard tile: the headline value plus its seven-day history.
nonisolated struct MetricReadingTransfer: Codable, Sendable, Hashable, Identifiable {
    var metric: String
    var displayValue: String
    var unit: String?
    var suffix: String?
    var series: [Double]
    var insight: String

    var id: String { metric }
}

/// One daily goal, resolved against today on the phone.
///
/// The numbers travel already formatted because the phone is the only device
/// that knows how the athlete has asked to read them — so the wrist can never
/// print a goal in kilometres that the phone shows in miles.
nonisolated struct MetricGoalTransfer: Codable, Sendable, Hashable, Identifiable {
    var metric: String
    var target: Double
    var value: Double
    var targetText: String
    var valueText: String
    var streak: Int
    var daysMetThisWeek: Int

    var id: String { metric }

    var fraction: Double {
        guard target > 0 else { return 0 }
        return min(1, max(0, value / target))
    }

    var isMet: Bool { target > 0 && value >= target }

    var progressText: String { "\(valueText) of \(targetText)" }
}

/// Which tiles the dashboard shows and in what order.
nonisolated struct DashboardPreferencesTransfer: Codable, Sendable, Equatable {
    var order: [String]
    var hidden: [String]
    var showsReadinessRing: Bool
    var showsZoneChart: Bool
    var showsRecentActivity: Bool

    static let standard = DashboardPreferencesTransfer(
        order: WatchDashboardMetric.allCases.map(\.rawValue),
        hidden: [WatchDashboardMetric.restingHeartRate.rawValue, WatchDashboardMetric.pace.rawValue],
        showsReadinessRing: true,
        showsZoneChart: true,
        showsRecentActivity: true
    )
}

/// A completed workout, trimmed down for the wrist.
nonisolated struct ActivityTransfer: Codable, Sendable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var activity: String
    var startDate: Date
    var duration: TimeInterval
    var distance: Double
    var elevationGain: Double
    var averageHeartRate: Double
    var calories: Double
    var trainingEffect: Double
    var zoneMinutes: [Double]
    var track: [SyncTrackPoint]

    var averagePace: TimeInterval {
        guard distance > 100 else { return 0 }
        return duration / (distance / 1000)
    }

    var routePoints: [WatchRoutePoint] {
        track.map { WatchRoutePoint(latitude: $0.latitude, longitude: $0.longitude, elevation: $0.elevation) }
    }
}

/// The whole Today dashboard as the watch renders it.
nonisolated struct DashboardTransfer: Codable, Sendable {
    var preferences: DashboardPreferencesTransfer
    var readings: [MetricReadingTransfer]
    var readiness: Int
    var readinessCaption: String
    var readinessSuggestion: String
    var sleepText: String
    var hrv: Double
    var hrvBaseline: Double
    var restingHeartRate: Double
    var trainingLoad: Int
    var zoneMinutes: [Double]
    var hasHealthData: Bool
    var activities: [ActivityTransfer]
    /// Optional so a dashboard stored on the watch before goals existed still
    /// decodes rather than being thrown away as unreadable.
    var goals: [MetricGoalTransfer]?
    var sentAt: Date
}
