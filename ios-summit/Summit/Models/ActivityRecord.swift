import Foundation

/// A completed workout, either recorded in-app or read from HealthKit.
nonisolated struct ActivityRecord: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var activity: RouteActivityType
    var startDate: Date
    var duration: TimeInterval
    var distance: Double
    var elevationGain: Double
    var averageHeartRate: Double
    var calories: Double
    var trainingEffect: Double
    var track: [RoutePoint] = []
    var zoneMinutes: [Double] = [0, 0, 0, 0, 0]

    var averagePace: TimeInterval {
        guard distance > 100 else { return 0 }
        return duration / (distance / 1000)
    }
}

nonisolated enum Formatters {
    /// The athlete's chosen units. Set once at launch by `UnitSettings` and
    /// again whenever they change it, so every call site converts consistently
    /// without having to thread a preference through the whole view tree.
    static var units: UnitSystem = .deviceDefault

    /// A workout or route length, in kilometres or miles.
    static func distance(_ metres: Double) -> String {
        guard metres.isFinite else { return "--" }
        return String(format: "%.1f", units.distance(fromMetres: metres))
    }

    static func preciseDistance(_ metres: Double) -> String {
        guard metres.isFinite else { return "--" }
        return String(format: "%.2f", units.distance(fromMetres: metres))
    }

    /// Distance with its unit attached, e.g. `12.4 km` or `7.7 mi`.
    static func distanceWithUnit(_ metres: Double) -> String {
        "\(distance(metres)) \(units.distanceUnit)"
    }

    /// Metres to the next turn, or how far off the line — small unit.
    static func shortDistance(_ metres: Double) -> String {
        guard metres.isFinite else { return "--" }
        return "\(Int(units.shortDistance(fromMetres: metres).rounded()))"
    }

    /// Metres per second as km/h or mph.
    static func speed(_ metresPerSecond: Double) -> String {
        guard metresPerSecond.isFinite, metresPerSecond >= 0 else { return "--" }
        return String(format: "%.1f", units.speed(fromMetresPerSecond: metresPerSecond))
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    static func compactDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    /// Pace as minutes per kilometre or per mile, e.g. "5:42".
    ///
    /// The stored value is always seconds per kilometre; the conversion happens
    /// here so no caller has to remember which unit it is holding.
    static func pace(_ secondsPerKm: TimeInterval) -> String {
        guard secondsPerKm.isFinite, secondsPerKm > 0 else { return "--:--" }
        let converted = units.pace(fromSecondsPerKm: secondsPerKm)
        guard converted < 5400 else { return "--:--" }
        let minutes = Int(converted) / 60
        let seconds = Int(converted) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Height or vertical gain, in metres or feet.
    static func elevation(_ metres: Double) -> String {
        guard metres.isFinite else { return "--" }
        return "\(Int(units.elevation(fromMetres: metres).rounded()))"
    }

    static func integer(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    /// Heart-rate zone 1-5 from a percentage of max heart rate.
    static func zone(forHeartRate bpm: Double, maxHeartRate: Double = 188) -> Int {
        guard bpm > 0 else { return 1 }
        let percent = bpm / maxHeartRate
        switch percent {
        case ..<0.60: return 1
        case ..<0.70: return 2
        case ..<0.80: return 3
        case ..<0.90: return 4
        default: return 5
        }
    }
}
