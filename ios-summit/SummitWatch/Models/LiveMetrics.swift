import Foundation

/// Every live value the workout engine tracks, updated once per second.
///
/// This is a plain value type so views can diff it cheaply and so laps can
/// snapshot it without any shared mutable state.
nonisolated struct LiveMetrics: Sendable, Equatable {
    var startDate: Date = .now
    var elapsed: TimeInterval = 0
    var movingTime: TimeInterval = 0

    var distance: Double = 0
    var lapDistance: Double = 0
    var lapElapsed: TimeInterval = 0
    var lapCount: Int = 1

    var currentSpeed: Double = 0
    var maxSpeed: Double = 0
    var bestPace: TimeInterval = 0

    var heartRate: Double = 0
    var averageHeartRate: Double = 0
    var maxHeartRate: Double = 0
    var isHeartRateEstimated: Bool = true

    var calories: Double = 0
    var trainingEffect: Double = 0
    var power: Double = 0
    var cadence: Double = 0
    var averageCadence: Double = 0

    var ascent: Double = 0
    var descent: Double = 0
    var altitude: Double = 0
    var grade: Double = 0
    var verticalSpeed: Double = 0

    var zoneSeconds: [TimeInterval] = [0, 0, 0, 0, 0]

    var remainingDistance: Double = 0
    /// How far along the loaded course the athlete has reached, in metres.
    /// Measured by projecting the current fix onto the course, so it stays
    /// honest even after a detour.
    var courseDistance: Double = 0
    var distanceToWaypoint: Double = 0
    var nextWaypointName: String = "—"
    var etaSeconds: TimeInterval = 0
    var offCourseMetres: Double = 0
    /// Set once the athlete has been off the line long enough to be real, not
    /// just GPS drift under tree cover.
    var isOffCourse: Bool = false

    var batteryFraction: Double = 1

    /// Signal strength 0-3 and whether the receiver is still reporting, mirrored
    /// here so both can be placed on a data screen like any other metric.
    var gpsBars: Int = 0
    var isGPSLive: Bool = false
    /// The receiver's own error estimate for the last usable fix, in metres.
    var horizontalAccuracy: Double = 0

    /// Athlete maximum heart rate used for zone maths.
    static var maxHeartRateCeiling: Double = 188

    var pace: TimeInterval {
        currentSpeed > 0.35 ? 1000 / currentSpeed : 0
    }

    var averagePace: TimeInterval {
        distance > 50 && movingTime > 0 ? movingTime / (distance / 1000) : 0
    }

    var lapPace: TimeInterval {
        lapDistance > 30 && lapElapsed > 0 ? lapElapsed / (lapDistance / 1000) : 0
    }

    var averageSpeed: Double {
        movingTime > 0 ? distance / movingTime : 0
    }

    /// Pace normalised for the current gradient, so climbs read comparably to flats.
    var gradeAdjustedPace: TimeInterval {
        let base = pace
        guard base > 0 else { return 0 }
        let factor = 1 + (grade / 100) * 2.6
        return base / max(0.45, factor)
    }

    var strideLength: Double {
        cadence > 20 ? currentSpeed * 60 / cadence : 0
    }

    var percentMaxHeartRate: Double {
        guard LiveMetrics.maxHeartRateCeiling > 0 else { return 0 }
        return heartRate / LiveMetrics.maxHeartRateCeiling
    }

    var heartRateZone: Int {
        LiveMetrics.zone(for: heartRate)
    }

    static func zone(for bpm: Double) -> Int {
        guard bpm > 0 else { return 1 }
        let percent = bpm / maxHeartRateCeiling
        switch percent {
        case ..<0.60: return 1
        case ..<0.70: return 2
        case ..<0.80: return 3
        case ..<0.90: return 4
        default: return 5
        }
    }

    /// Lower and upper bpm bounds for a zone, used by the zone page.
    static func zoneRange(_ zone: Int) -> ClosedRange<Int> {
        let bounds: [Double] = [0.50, 0.60, 0.70, 0.80, 0.90, 1.0]
        let index = max(0, min(4, zone - 1))
        let lower = Int((bounds[index] * maxHeartRateCeiling).rounded())
        let upper = Int((bounds[index + 1] * maxHeartRateCeiling).rounded())
        return lower...upper
    }
}

/// A completed lap, split either automatically per kilometre or by button press.
nonisolated struct WatchLap: Identifiable, Sendable, Equatable {
    var id: UUID = UUID()
    var index: Int
    var duration: TimeInterval
    var distance: Double
    var averageHeartRate: Double
    var ascent: Double
    var isAutomatic: Bool

    var pace: TimeInterval {
        distance > 30 ? duration / (distance / 1000) : 0
    }
}

/// A recorded GPS breadcrumb used by the map and elevation pages.
nonisolated struct WatchTrackPoint: Sendable, Equatable {
    var latitude: Double
    var longitude: Double
    var altitude: Double
    var distance: Double
}
