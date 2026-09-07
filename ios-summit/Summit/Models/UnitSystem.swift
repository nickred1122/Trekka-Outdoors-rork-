import Foundation
import SwiftUI

/// Metric or imperial, chosen once and applied to every distance, height, speed
/// and pace the app prints.
///
/// Everything is stored and calculated in SI — metres, metres per second,
/// seconds per kilometre — and converted only at the moment of display, so
/// switching units can never alter a recorded workout.
///
/// Duplicated verbatim in `SummitWatch/Support/UnitSystem.swift`; the watch is a
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

    /// What the phone's own region setting implies, used before the athlete has
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

    /// A lap length the athlete typed in their own unit, back to metres.
    func metres(fromDistance value: Double) -> Double {
        self == .metric ? value * 1000 : value * Self.metresPerMile
    }

    /// Where the small unit gives way to the large one when printing.
    var shortDistanceCeiling: Double { self == .metric ? 1000 : 5280 }
}

extension EnvironmentValues {
    /// The chosen unit system, published to every screen.
    ///
    /// `Formatters` holds the same value in a static so models and helpers can
    /// convert without threading a preference through every call. A static is
    /// invisible to SwiftUI though: changing it updates the numbers but tells no
    /// view to redraw, which is exactly how a units switch ends up appearing to
    /// do nothing. Screens read this instead, so the change actually lands.
    @Entry var unitSystem: UnitSystem = .deviceDefault
}

extension View {
    /// Rebuilds this screen when the units change.
    ///
    /// Formatting happens deep inside child views and inside model helpers, so
    /// there is no single value to observe. Tying the screen's identity to a
    /// units token redraws the lot, which is cheap because it only ever happens
    /// when the athlete flips a setting. The token carries all three choices —
    /// system, mass and elevation — so any of them lands everywhere.
    func reformatsOnUnitChange(_ token: some Hashable) -> some View {
        id(token)
    }
}

/// The persisted units preference, read by every formatter on the phone.
///
/// Three choices live here: the overall system — which also drives distance,
/// speed and pace — plus independent overrides for mass and elevation, so an
/// athlete who lifts in kilograms but climbs in feet is never asked to pick one.
@Observable
final class UnitSettings {
    private static let storageKey = "units.system.v1"
    private static let massKey = "units.mass.v1"
    private static let elevationKey = "units.elevation.v1"

    private(set) var system: UnitSystem
    private var massOverride: UnitSystem?
    private var elevationOverride: UnitSystem?

    /// What weights print in — kilograms or pounds.
    var massUnits: UnitSystem { massOverride ?? system }
    /// What heights and climbs print in — metres or feet.
    var elevationUnits: UnitSystem { elevationOverride ?? system }

    /// Everything that should rebuild when any units choice changes.
    var changeToken: String {
        "\(system.rawValue)|\(massUnits.rawValue)|\(elevationUnits.rawValue)"
    }

    /// Called after a change so the watch can be brought into line.
    var onChange: ((UnitSystem) -> Void)?

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.storageKey)
        system = stored.flatMap(UnitSystem.init(rawValue:)) ?? .deviceDefault
        massOverride = UserDefaults.standard.string(forKey: Self.massKey).flatMap(UnitSystem.init(rawValue:))
        elevationOverride = UserDefaults.standard.string(forKey: Self.elevationKey).flatMap(UnitSystem.init(rawValue:))
        refreshFormatters()
    }

    /// Switches the whole app between metric and imperial.
    ///
    /// Weight and elevation follow, because the master switch is what an
    /// athlete reaches for when they mean "show me everything the other way".
    /// Any override they had set is cleared rather than left behind, which is
    /// what used to pin weight to kilograms after a switch to imperial.
    func set(_ newSystem: UnitSystem) {
        guard newSystem != system else { return }
        system = newSystem
        UserDefaults.standard.set(newSystem.rawValue, forKey: Self.storageKey)
        clearOverrides()
        refreshFormatters()
        onChange?(newSystem)
    }

    /// What weights print in. Choosing the system's own units clears the
    /// override so weight tracks the master switch again.
    func setMass(_ newSystem: UnitSystem) {
        guard newSystem != massUnits else { return }
        massOverride = newSystem == system ? nil : newSystem
        store(massOverride, forKey: Self.massKey)
        refreshFormatters()
    }

    /// What heights and climbs print in, with the same follow-the-system rule.
    func setElevation(_ newSystem: UnitSystem) {
        guard newSystem != elevationUnits else { return }
        elevationOverride = newSystem == system ? nil : newSystem
        store(elevationOverride, forKey: Self.elevationKey)
        refreshFormatters()
    }

    /// Applies a choice made on the watch without echoing it straight back.
    func applyFromWatch(_ newSystem: UnitSystem) {
        guard newSystem != system else { return }
        system = newSystem
        UserDefaults.standard.set(newSystem.rawValue, forKey: Self.storageKey)
        clearOverrides()
        refreshFormatters()
    }

    private func clearOverrides() {
        massOverride = nil
        elevationOverride = nil
        UserDefaults.standard.removeObject(forKey: Self.massKey)
        UserDefaults.standard.removeObject(forKey: Self.elevationKey)
    }

    private func store(_ value: UnitSystem?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value.rawValue, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func refreshFormatters() {
        Formatters.units = system
        Formatters.massSystem = massUnits
        Formatters.elevationSystem = elevationUnits
    }
}
