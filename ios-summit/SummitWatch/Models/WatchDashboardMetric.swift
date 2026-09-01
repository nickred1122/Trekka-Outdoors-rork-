import SwiftUI

/// The dashboard tiles, mirroring the phone's metric set one for one.
///
/// Raw values match the phone's `DashboardMetric` so preferences and readings
/// cross the WatchConnectivity bridge unchanged.
nonisolated enum WatchDashboardMetric: String, CaseIterable, Codable, Identifiable, Sendable, Hashable {
    case sleep
    case hrv
    case vo2Max
    case load
    case calories
    case steps
    case restingHeartRate
    case distance
    case elevation
    case pace
    case exercise
    case flights
    case respiratoryRate
    case bodyMass

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleep: "Sleep"
        case .hrv: "HRV"
        case .vo2Max: "VO₂ Max"
        case .load: "Load"
        case .calories: "Calories"
        case .steps: "Steps"
        case .restingHeartRate: "Rest HR"
        case .distance: "Distance"
        case .elevation: "Ascent"
        case .pace: "Avg Pace"
        case .exercise: "Exercise"
        case .flights: "Flights"
        case .respiratoryRate: "Breathing"
        case .bodyMass: "Weight"
        }
    }

    /// Trekka's own mark for the metric, mirroring the phone's set exactly.
    var glyph: TrekkaGlyph {
        switch self {
        case .sleep: .sleep
        case .hrv: .hrv
        case .vo2Max: .vo2
        case .load: .load
        case .calories: .calories
        case .steps: .steps
        case .restingHeartRate: .heart
        case .distance: .distance
        case .elevation: .elevation
        case .pace: .pace
        case .exercise: .gym
        case .flights: .elevation
        case .respiratoryRate: .hrv
        case .bodyMass: .load
        }
    }

    var symbol: String {
        switch self {
        case .sleep: "moon.zzz.fill"
        case .hrv: "waveform.path.ecg"
        case .vo2Max: "figure.run"
        case .load: "chart.bar.fill"
        case .calories: "flame.fill"
        case .steps: "shoeprints.fill"
        case .restingHeartRate: "heart.fill"
        case .distance: "point.topleft.down.to.point.bottomright.curvepath.fill"
        case .elevation: "mountain.2.fill"
        case .pace: "stopwatch.fill"
        case .exercise: "figure.mixed.cardio"
        case .flights: "figure.stairs"
        case .respiratoryRate: "lungs.fill"
        case .bodyMass: "scalemass.fill"
        }
    }

    var tint: Color {
        switch self {
        case .sleep: Color(red: 0.55, green: 0.45, blue: 0.95)
        case .hrv: WatchTheme.zoneColors[1]
        case .vo2Max: WatchTheme.accent
        case .load: WatchTheme.highlight
        case .calories: WatchTheme.zoneColors[3]
        case .steps: WatchTheme.zoneColors[1]
        case .restingHeartRate: WatchTheme.danger
        case .distance: WatchTheme.zoneColors[0]
        case .elevation: WatchTheme.accent
        case .pace: WatchTheme.highlight
        case .exercise: WatchTheme.zoneColors[2]
        case .flights: WatchTheme.zoneColors[0]
        case .respiratoryRate: WatchTheme.zoneColors[1]
        case .bodyMass: WatchTheme.textPrimary.opacity(0.8)
        }
    }

    /// What window the headline number covers.
    var periodLabel: String {
        switch self {
        case .sleep: "Last night"
        case .hrv, .restingHeartRate: "7-day average"
        case .vo2Max: "Latest reading"
        case .load: "Rolling 7 days"
        case .calories, .steps: "Today"
        case .distance, .elevation, .pace: "This week"
        case .exercise, .flights: "Today"
        case .respiratoryRate: "7-day average"
        case .bodyMass: "Latest reading"
        }
    }
}

/// The activity kinds a synced workout can carry; raw values match the phone.
nonisolated enum WatchActivityKind: String, Codable, Sendable, CaseIterable {
    case run = "Trail Run"
    case ride = "Ride"
    case hike = "Hike"

    var symbol: String {
        switch self {
        case .run: "figure.run"
        case .ride: "bicycle"
        case .hike: "figure.hiking"
        }
    }

    var tint: Color {
        switch self {
        case .run: WatchTheme.accent
        case .ride: WatchTheme.zoneColors[1]
        case .hike: WatchTheme.highlight
        }
    }
}
