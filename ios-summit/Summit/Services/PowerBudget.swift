import Foundation

/// Mirrors the wrist-side explanation of power saver so both devices describe
/// the same trade in the same words.
///
/// Deliberately carries no battery-life arithmetic. Only the watch can measure
/// its own drain, and that measurement never reaches the phone, so quoting
/// hours here would mean printing a constant and calling it a forecast. The
/// figure belongs on the wrist, where it is observed.
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
            detail: "The optical sensor is switched off, so heart rate, zones and training effect show -- until power saver is turned off. They are not filled in from pace.",
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
            detail: "Navigation maths runs every 2 seconds. Timer, distance and laps keep full accuracy.",
            symbol: "gauge.with.dots.needle.33percent"
        ),
        Change(
            title: "Quieter haptics",
            detail: "Only lap and navigation alerts buzz.",
            symbol: "hand.tap"
        ),
    ]
}
