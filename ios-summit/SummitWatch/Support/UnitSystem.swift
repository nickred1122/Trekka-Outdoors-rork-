import Foundation

/// Metric or imperial, chosen once and applied to every distance, height, speed
/// and pace the watch prints.
///
/// Everything is stored and calculated in SI — metres, metres per second,
/// seconds per kilometre — and converted only at the moment of display, so
/// switching units can never alter a recorded workout.
///
/// Duplicated verbatim from `Summit/Models/UnitSystem.swift`; the watch is a
/// separate binary, so the two copies must stay identical.
nonisolated enum UnitSystem: String, Codable, CaseIterable, Sendable, Identifiable {
    case metric
    case imperial

    var id: String { rawValue }

    var title: String {
        switch self {
        case .metric: "Metric"
        case .imperial: "Imperial"
        }
    }

    var subtitle: String {
        switch self {
        case .metric: "Kilometres, metres, km/h"
        case .imperial: "Miles, feet, mph"
        }
    }

    var symbol: String {
        switch self {
        case .metric: "ruler"
        case .imperial: "ruler.fill"
        }
    }

    /// What the watch's own region setting implies, used before the athlete has
    /// ever chosen for themselves.
    static var deviceDefault: UnitSystem {
        Locale.current.measurementSystem == .metric ? .metric : .imperial
    }

    // MARK: - Unit names

    /// Long distances: a workout total, a route length.
    var distanceUnit: String { self == .metric ? "km" : "mi" }
    /// Short distances: metres to the next turn, how far off course.
    var shortDistanceUnit: String { self == .metric ? "m" : "ft" }
    var elevationUnit: String { self == .metric ? "m" : "ft" }
    var speedUnit: String { self == .metric ? "km/h" : "mph" }
    var paceUnit: String { self == .metric ? "/km" : "/mi" }
    var verticalSpeedUnit: String { self == .metric ? "m/h" : "ft/h" }
    /// Used where a rate is printed per unit of distance, e.g. metres per km.
    var perDistanceUnit: String { self == .metric ? "m/km" : "ft/mi" }
    var massUnit: String { self == .metric ? "kg" : "lb" }

    // MARK: - Conversion

    private static let metresPerMile: Double = 1609.344
    private static let feetPerMetre: Double = 3.280_839_895
    private static let mphPerMetrePerSecond: Double = 2.236_936
    private static let poundsPerKilogram: Double = 2.204_622_6

    /// Metres to the large unit — kilometres or miles.
    func distance(fromMetres metres: Double) -> Double {
        self == .metric ? metres / 1000 : metres / Self.metresPerMile
    }

    /// Metres to the small unit — metres or feet.
    func shortDistance(fromMetres metres: Double) -> Double {
        self == .metric ? metres : metres * Self.feetPerMetre
    }

    /// Heights and vertical gain use the small unit in both systems.
    func elevation(fromMetres metres: Double) -> Double {
        shortDistance(fromMetres: metres)
    }

    /// Metres per second to km/h or mph.
    func speed(fromMetresPerSecond value: Double) -> Double {
        self == .metric ? value * 3.6 : value * Self.mphPerMetrePerSecond
    }

    /// Seconds per kilometre to seconds per kilometre or per mile.
    func pace(fromSecondsPerKm value: TimeInterval) -> TimeInterval {
        self == .metric ? value : value * (Self.metresPerMile / 1000)
    }

    /// Health stores weight in kilograms; imperial prints pounds.
    func mass(fromKilograms value: Double) -> Double {
        self == .metric ? value : value * Self.poundsPerKilogram
    }

    /// A lap length the athlete set in their own unit, back to metres.
    func metres(fromDistance value: Double) -> Double {
        self == .metric ? value * 1000 : value * Self.metresPerMile
    }

    /// Where the small unit gives way to the large one when printing.
    var shortDistanceCeiling: Double { self == .metric ? 1000 : 5280 }
}
