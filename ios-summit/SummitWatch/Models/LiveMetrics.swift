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
    /// Seconds the clock was stopped, by hand or by auto-pause.
    var pausedTime: TimeInterval = 0
    /// Steps taken during this workout, accumulated from HealthKit.
    var steps: Double = 0

    /// The lap in progress.
    var lapAscent: Double = 0
    var lapHeartRate: Double = 0

    /// The lap just completed — the one an athlete compares the current one
    /// against. Zero until the first lap is banked.
    var lastLapDuration: TimeInterval = 0
    var lastLapDistance: Double = 0
    var lastLapAscent: Double = 0
    var lastLapHeartRate: Double = 0

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
    /// Highest and lowest ground reached so far. Optional because sea level is
    /// a real altitude, so zero cannot double as "not measured yet".
    var maxAltitude: Double?
    var minAltitude: Double?

    var zoneSeconds: [TimeInterval] = [0, 0, 0, 0, 0]

    var remainingDistance: Double = 0
    /// Positive climb still between the athlete and the end of the course.
    var remainingAscent: Double = 0
    /// Descent still to come on the course.
    var remainingDescent: Double = 0
    /// Total climb of the loaded course, end to end.
    var routeAscent: Double = 0
    /// Straight-line distance back to where the workout began — the number that
    /// matters when the weather turns and the plan is abandoned.
    var distanceToStart: Double = 0
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

    /// Next sunrise and sunset, computed from the GPS fix. nil with no fix, or
    /// inside the polar day and night where the event does not happen.
    var sunrise: Date?
    var sunset: Date?

    /// Direction of travel in degrees, and the last known position. Mirrored
    /// here so a bearing or a grid reference can sit on a data screen — reading
    /// a position aloud is how a rescue party is given somewhere to go.
    var bearing: Double = 0
    var latitude: Double = 0
    var longitude: Double = 0
    var hasPosition: Bool = false

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

    /// Pace of the lap just completed.
    var lastLapPace: TimeInterval {
        lastLapDistance > 30 && lastLapDuration > 0
            ? lastLapDuration / (lastLapDistance / 1000)
            : 0
    }

    /// Mean lap time so far, across laps already banked plus the one running.
    var averageLapTime: TimeInterval {
        lapCount > 0 ? elapsed / Double(lapCount) : 0
    }

    /// Time spent in the zone the heart is in right now.
    var timeInCurrentZone: TimeInterval {
        let index = heartRateZone - 1
        guard zoneSeconds.indices.contains(index) else { return 0 }
        return zoneSeconds[index]
    }

    /// Time to the next waypoint at the current speed; 0 when still or none.
    var timeToWaypointSeconds: TimeInterval {
        currentSpeed > 0.4 && distanceToWaypoint > 0 ? distanceToWaypoint / currentSpeed : 0
    }

    /// How much of the loaded course has been covered.
    var routeProgressFraction: Double {
        let total = courseDistance + remainingDistance
        guard total > 0 else { return 0 }
        return min(1, courseDistance / total)
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
