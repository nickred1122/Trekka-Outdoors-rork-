import Foundation

/// Formatting only.
///
/// The complication does not run while a workout does, so it can measure
/// nothing itself. The watch app observes its own battery drain and writes the
/// finished figure into the shared container; this file just prints it. When
/// the watch has not yet measured a rate, the answer is `--` rather than a
/// number derived from spec-sheet constants that may be hours out on a cold day.
///
/// Duplicated verbatim from the label helper in
/// `SummitWatch/Services/WatchPowerModel.swift` — keep both copies in step.
nonisolated enum PowerBudget {
    /// `~9h 20m`, or `--` while the watch is still measuring.
    static func label(hours: Double?) -> String {
        guard let hours, hours.isFinite, hours > 0 else { return "--" }
        if hours < 1 { return "~\(Int((hours * 60).rounded()))m" }
        let whole = Int(hours)
        let minutes = Int(((hours - Double(whole)) * 60).rounded())
        return minutes >= 5 ? "~\(whole)h \(minutes)m" : "~\(whole)h"
    }
}
