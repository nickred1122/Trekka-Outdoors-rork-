import Foundation

/// Compact string formatting for the watch's tiny metric cells.
nonisolated enum WatchFormat {
    /// The athlete's chosen units, mirrored here by `WatchScreenSettings` so
    /// every cell converts the same way without threading a preference through
    /// each view.
    static var units: UnitSystem = .deviceDefault

    /// `1:04:22` or `4:22`.
    static func duration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// `1h 04m` or `22m`.
    static func compactDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "--" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    /// Kilometres or miles, two decimals.
    static func distance(_ metres: Double) -> String {
        guard metres.isFinite else { return "--" }
        return String(format: "%.2f", units.distance(fromMetres: metres))
    }

    /// Small distances stay in metres or feet until they get long enough to
    /// deserve the big unit.
    static func shortDistance(_ metres: Double) -> String {
        guard metres.isFinite else { return "--" }
        let small = units.shortDistance(fromMetres: metres)
        if small < units.shortDistanceCeiling { return "\(Int(small.rounded()))" }
        return String(format: "%.1f", units.distance(fromMetres: metres))
    }

    /// The unit `shortDistance` will actually have printed for this length —
    /// small below the ceiling, large above it — so a caller labelling the value
    /// separately never mismatches it.
    static func shortDistanceUnit(_ metres: Double) -> String {
        guard metres.isFinite else { return units.shortDistanceUnit }
        return units.shortDistance(fromMetres: metres) < units.shortDistanceCeiling
            ? units.shortDistanceUnit
            : units.distanceUnit
    }

    /// Height or vertical gain, in metres or feet.
    static func elevation(_ metres: Double) -> String {
        guard metres.isFinite else { return "--" }
        return "\(Int(units.elevation(fromMetres: metres).rounded()))"
    }

    /// Minutes per kilometre or per mile as `5:42`.
    ///
    /// The engine always works in seconds per kilometre; conversion happens here
    /// so no caller has to know which unit it is holding.
    static func pace(_ secondsPerKm: TimeInterval) -> String {
        guard secondsPerKm.isFinite, secondsPerKm > 0 else { return "--:--" }
        let converted = units.pace(fromSecondsPerKm: secondsPerKm)
        guard converted < 5400 else { return "--:--" }
        let minutes = Int(converted) / 60
        let seconds = Int(converted) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Metres per second rendered as km/h or mph.
    static func speed(_ metresPerSecond: Double) -> String {
        guard metresPerSecond.isFinite, metresPerSecond >= 0 else { return "--" }
        return String(format: "%.1f", units.speed(fromMetresPerSecond: metresPerSecond))
    }

    static func integer(_ value: Double) -> String {
        guard value.isFinite else { return "--" }
        return "\(Int(value.rounded()))"
    }

    static func decimal(_ value: Double, places: Int = 1) -> String {
        guard value.isFinite else { return "--" }
        return String(format: "%.\(places)f", value)
    }

    static func signedDecimal(_ value: Double, places: Int = 1) -> String {
        guard value.isFinite else { return "--" }
        let formatted = String(format: "%.\(places)f", abs(value))
        if value > 0.05 { return "+\(formatted)" }
        if value < -0.05 { return "-\(formatted)" }
        return formatted
    }

    static func clock(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }

    static func percent(_ fraction: Double) -> String {
        guard fraction.isFinite else { return "--" }
        return "\(Int((fraction * 100).rounded()))"
    }

    /// The compass point a bearing falls in: N, NE, E, SE, S, SW, W, NW.
    ///
    /// Eight points rather than sixteen, because "NNE" on a wrist at a glance is
    /// three characters of noise. Nobody navigates off the difference between
    /// north-northeast and northeast without stopping to look properly.
    static func cardinal(_ degrees: Double) -> String {
        guard degrees.isFinite else { return "--" }
        let points: [String] = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let normalised: Double = (degrees.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        // Each point owns 45 degrees centred on itself, so north runs from
        // 337.5 round to 22.5 rather than starting at zero.
        let index: Int = Int((normalised / 45).rounded()) % points.count
        return points[index]
    }

    /// A bearing written the way it is read aloud: "NE 042".
    static func bearing(_ degrees: Double) -> String {
        guard degrees.isFinite else { return "--" }
        let normalised: Double = (degrees.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        return String(format: "%@ %03d", cardinal(normalised), Int(normalised.rounded()) % 360)
    }
}
