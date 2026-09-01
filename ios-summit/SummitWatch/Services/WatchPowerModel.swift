import Foundation

/// Battery arithmetic derived from what this watch actually does, not from
/// published figures for an average one.
///
/// Nothing here predicts anything until the battery has been watched falling
/// for long enough to measure a rate. Watch models, battery age, temperature
/// and how cold your wrist is all move the real number by hours, so a figure
/// borrowed from a spec sheet would be a guess wearing the clothes of a
/// measurement — and it would be wrong on exactly the freezing all-day walk
/// where it mattered most.
nonisolated enum PowerBudget {
    /// The shortest span of observation that can produce an honest rate.
    static let minimumObservation: TimeInterval = 300
    /// The smallest fall in charge worth extrapolating from. The gauge itself
    /// is quantised, so anything less is mostly rounding.
    static let minimumDrop: Double = 0.02

    /// One battery reading.
    nonisolated struct Sample: Sendable, Equatable, Codable {
        var fraction: Double
        var at: Date
    }

    /// Charge lost per hour across the samples collected so far, or `nil` while
    /// there is not yet enough evidence to say.
    static func drainPerHour(from samples: [Sample]) -> Double? {
        guard let first = samples.first, let last = samples.last else { return nil }
        let seconds = last.at.timeIntervalSince(first.at)
        let drop = first.fraction - last.fraction
        guard seconds >= minimumObservation, drop >= minimumDrop else { return nil }
        let rate = drop / (seconds / 3600)
        return rate.isFinite && rate > 0 ? rate : nil
    }

    /// Hours of recording left at the measured rate.
    static func remainingHours(batteryFraction: Double, drainPerHour: Double?) -> Double? {
        guard let drainPerHour, drainPerHour > 0 else { return nil }
        let charge = min(max(batteryFraction, 0), 1)
        let hours = charge / drainPerHour
        return hours.isFinite ? hours : nil
    }

    /// `~9h 20m`, or `--` while the rate is still being measured.
    ///
    /// The tilde is deliberate: this is an observation extrapolated forward, not
    /// a promise about the rest of the day.
    static func label(hours: Double?) -> String {
        guard let hours, hours.isFinite, hours > 0 else { return "--" }
        if hours < 1 { return "~\(Int((hours * 60).rounded()))m" }
        let whole = Int(hours)
        let minutes = Int(((hours - Double(whole)) * 60).rounded())
        return minutes >= 5 ? "~\(whole)h \(minutes)m" : "~\(whole)h"
    }

    /// What the watch is doing to the battery right now, e.g. `12%/h`.
    static func drainLabel(_ drainPerHour: Double?) -> String {
        guard let drainPerHour, drainPerHour > 0 else { return "--" }
        return "\(Int((drainPerHour * 100).rounded()))%/h"
    }

    /// The measured difference between two modes, once both have been observed.
    static func gainLabel(batteryFraction: Double, normal: Double?, saving: Double?) -> String {
        guard let normalHours = remainingHours(batteryFraction: batteryFraction, drainPerHour: normal),
              let savingHours = remainingHours(batteryFraction: batteryFraction, drainPerHour: saving) else {
            return "--"
        }
        let gain = savingHours - normalHours
        guard gain > 0.15 else { return "--" }
        return gain < 1 ? "+\(Int((gain * 60).rounded()))m" : "+\(String(format: "%.1f", gain))h"
    }
}

/// The exact trade the athlete makes when power saver is on.
///
/// Every line here maps to something the app really does, so the screen is not
/// making promises the sensors do not keep.
nonisolated enum PowerSaverPlan {
    nonisolated struct Change: Identifiable, Sendable {
        var id: String { title }
        var title: String
        var detail: String
        var symbol: String
    }

    static let changes: [Change] = [
        Change(
            title: "Heart rate stops",
            detail: "The optical sensor is switched off, so heart rate, zones and training effect show -- until you turn power saver back off. They are not filled in from pace.",
            symbol: "heart.slash"
        ),
        Change(
            title: "GPS eased off",
            detail: "Fixes every 25 m instead of every 5 m, at coarser accuracy. Distance stays usable; tight switchbacks are drawn more roughly.",
            symbol: "location.slash"
        ),
        Change(
            title: "Map and compass hidden",
            detail: "Map redraws are the most expensive thing on the watch, so those pages step aside during the workout.",
            symbol: "map"
        ),
        Change(
            title: "Lighter refresh",
            detail: "Navigation maths runs every 2 seconds. The timer, distance and laps keep full accuracy.",
            symbol: "gauge.with.dots.needle.33percent"
        ),
        Change(
            title: "Quieter haptics",
            detail: "Only lap and navigation alerts buzz. Milestone taps wait until you are back on full power.",
            symbol: "hand.tap"
        ),
    ]

    static let unchanged: [String] = [
        "Elapsed and moving time",
        "Distance, pace and elevation",
        "Laps and splits",
        "The breadcrumb trail home",
        "The workout still saves to Health",
    ]
}
