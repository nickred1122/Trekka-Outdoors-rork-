import Foundation

// MARK: - Wire formats
//
// These structs are duplicated verbatim in the watch target so both ends encode
// and decode the same JSON. Keep the property names identical on both sides.

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

/// Which tiles the dashboard shows and in what order.
nonisolated struct DashboardPreferencesTransfer: Codable, Sendable, Equatable {
    var order: [String]
    var hidden: [String]
    var showsReadinessRing: Bool
    var showsZoneChart: Bool
    var showsRecentActivity: Bool
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
}

/// The whole Today dashboard as the watch renders it: preferences, readings,
/// recovery numbers and recent history.
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
    var sentAt: Date
}

/// The coaching line that accompanies a readiness score.
nonisolated enum ReadinessAdvice {
    static func suggestion(for readiness: Int) -> String {
        switch readiness {
        case 85...100: "Threshold intervals or a hard climb. Your body can absorb it."
        case 70..<85: "A solid tempo effort — 40 to 60 minutes in zone 3."
        case 50..<70: "Easy aerobic hour. Keep your heart rate under zone 3."
        case 30..<50: "Zone 2 only, or walk it. Skip the intervals today."
        case 1..<30: "Rest, mobility or a gentle walk. Nothing structured."
        default: "Connect Apple Health on iPhone to get a readiness score."
        }
    }
}

// MARK: - Builders

/// Turns the phone's live state into the payload the watch mirrors.
enum WatchSyncPayloads {
    /// Tracks are downsampled and history capped so the payload stays well
    /// inside the WatchConnectivity application-context budget.
    private static let maxActivities = 14
    private static let maxTrackPoints = 40

    static func dashboard(
        settings: DashboardSettings,
        health: HealthService,
        store: RouteStore
    ) -> DashboardTransfer {
        let snapshot = health.snapshot
        let activities = (store.recentActivities + health.healthActivities)
            .sorted { $0.startDate > $1.startDate }
        let readings = MetricReadings.build(snapshot: snapshot, activities: activities)

        let storeZones = store.weeklyZoneMinutes
        let zones = storeZones.contains(where: { $0 > 0 }) ? storeZones : snapshot.zoneMinutes

        return DashboardTransfer(
            preferences: settings.preferencesTransfer,
            readings: DashboardMetric.allCases.compactMap { metric in
                guard let reading = readings[metric] else { return nil }
                return MetricReadingTransfer(
                    metric: metric.rawValue,
                    displayValue: reading.displayValue,
                    unit: reading.unit,
                    suffix: reading.suffix,
                    series: reading.series,
                    insight: reading.insight
                )
            },
            readiness: snapshot.readiness,
            readinessCaption: snapshot.readinessCaption,
            readinessSuggestion: ReadinessAdvice.suggestion(for: snapshot.readiness),
            sleepText: snapshot.sleepText,
            hrv: snapshot.hrv,
            hrvBaseline: snapshot.hrvBaseline,
            restingHeartRate: snapshot.restingHeartRate,
            trainingLoad: snapshot.trainingLoad,
            zoneMinutes: zones,
            hasHealthData: health.hasHealthData,
            activities: activities.prefix(maxActivities).map(transfer(for:)),
            sentAt: .now
        )
    }

    private static func transfer(for activity: ActivityRecord) -> ActivityTransfer {
        ActivityTransfer(
            id: activity.id,
            name: activity.name,
            activity: activity.activity.rawValue,
            startDate: activity.startDate,
            duration: activity.duration,
            distance: activity.distance,
            elevationGain: activity.elevationGain,
            averageHeartRate: activity.averageHeartRate,
            calories: activity.calories,
            trainingEffect: activity.trainingEffect,
            zoneMinutes: activity.zoneMinutes,
            track: downsample(activity.track)
        )
    }

    /// Keeps the shape of a track recognisable while dropping most of its points.
    private static func downsample(_ points: [RoutePoint]) -> [SyncTrackPoint] {
        guard !points.isEmpty else { return [] }
        guard points.count > maxTrackPoints else {
            return points.map { SyncTrackPoint(latitude: $0.latitude, longitude: $0.longitude, elevation: $0.elevation) }
        }
        let stride = Double(points.count - 1) / Double(maxTrackPoints - 1)
        return (0..<maxTrackPoints).map { step in
            let point = points[min(points.count - 1, Int((Double(step) * stride).rounded()))]
            return SyncTrackPoint(latitude: point.latitude, longitude: point.longitude, elevation: point.elevation)
        }
    }
}
