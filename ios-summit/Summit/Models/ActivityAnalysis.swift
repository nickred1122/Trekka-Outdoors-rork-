import Foundation
import CoreLocation

/// One kilometre or mile of a recorded activity.
nonisolated struct ActivitySplit: Identifiable, Hashable, Sendable {
    /// 1-based, so the first split is "1" the way a lap counter reads.
    var index: Int
    /// Ground covered in this split. The last one is usually a part split.
    var distance: Double
    var duration: TimeInterval
    var elevationGain: Double
    var elevationLoss: Double

    var id: Int { index }

    /// Seconds per kilometre, the unit every pace formatter here expects.
    var pace: TimeInterval {
        guard distance > 1 else { return 0 }
        return duration / (distance / 1_000)
    }

    /// A part split cannot be compared with a whole one, so the UI marks it.
    var isPartial: Bool
}

/// Everything worth knowing about a finished activity that is not already a
/// stored field — derived from the recorded track rather than guessed.
///
/// A saved workout carries far more than the six numbers a summary usually
/// shows. The track holds a timestamped elevation profile, which is enough for
/// real splits, a descent total, the high and low point, and where the fastest
/// and steepest ground actually was.
nonisolated struct ActivityAnalysis: Sendable {
    var splits: [ActivitySplit] = []
    var elevationLoss: Double = 0
    var highestPoint: Double = 0
    var lowestPoint: Double = 0
    /// Nil when the track has no usable timestamps.
    var fastestSplit: ActivitySplit?
    var slowestSplit: ActivitySplit?
    /// The steepest sustained climb found, as a percentage grade.
    var steepestGrade: Double = 0
    var movingTime: TimeInterval = 0

    var hasSplits: Bool { splits.count > 1 }
    var hasElevation: Bool { highestPoint > lowestPoint }

    /// Below this the fix is noise rather than a real step, and letting it
    /// through turns GPS jitter into fictional climbing.
    private static let elevationNoiseFloor: Double = 1.0
    /// A gap longer than this is a pause, a lost signal or a stop for a gate;
    /// counting it as movement would ruin both moving time and pace.
    private static let stationaryGap: TimeInterval = 20

    static func analyse(track: [RoutePoint], splitDistance: Double) -> ActivityAnalysis {
        var result = ActivityAnalysis()
        guard track.count > 1, splitDistance > 0 else { return result }

        let elevations = track.map(\.elevation).filter { $0 != 0 }
        if let high = elevations.max(), let low = elevations.min() {
            result.highestPoint = high
            result.lowestPoint = low
        }

        var splits: [ActivitySplit] = []
        var splitDistanceSoFar: Double = 0
        var splitDuration: TimeInterval = 0
        var splitGain: Double = 0
        var splitLoss: Double = 0
        var totalLoss: Double = 0
        var movingTime: TimeInterval = 0
        var steepest: Double = 0

        /// Timestamps are optional on stored points: routes saved before the
        /// app recorded them, and anything imported from Health without a
        /// route series, have none. Splits need real times, so without them
        /// the whole splits section stands down rather than inventing pace.
        let hasTimes = track.contains { $0.timestamp != nil }

        for index in 1..<track.count {
            let previous = track[index - 1]
            let current = track[index]

            let step = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
                .distance(from: CLLocation(latitude: current.latitude, longitude: current.longitude))
            guard step.isFinite, step >= 0 else { continue }

            var stepTime: TimeInterval = 0
            if let start = previous.timestamp, let end = current.timestamp {
                let gap = end.timeIntervalSince(start)
                if gap > 0 {
                    stepTime = gap
                    if gap <= stationaryGap, step > 0.5 { movingTime += gap }
                }
            }

            let rise = current.elevation - previous.elevation
            if abs(rise) >= elevationNoiseFloor, previous.elevation != 0, current.elevation != 0 {
                if rise > 0 { splitGain += rise } else { splitLoss += -rise; totalLoss += -rise }
                if step > 20 {
                    let grade = abs(rise) / step * 100
                    // Anything past this is a cliff, not a path: it is a bad
                    // altimeter reading, and letting it through would report a
                    // grade no athlete actually climbed.
                    if grade.isFinite, grade < 45 { steepest = max(steepest, grade) }
                }
            }

            splitDistanceSoFar += step
            splitDuration += stepTime

            // A single long step can span a whole split boundary, so the
            // overshoot is carried forward rather than being swallowed.
            while splitDistanceSoFar >= splitDistance {
                let overshoot = splitDistanceSoFar - splitDistance
                let share = splitDistanceSoFar > 0
                    ? (splitDistance / splitDistanceSoFar)
                    : 1
                let countedDuration = splitDuration * share

                splits.append(
                    ActivitySplit(
                        index: splits.count + 1,
                        distance: splitDistance,
                        duration: countedDuration,
                        elevationGain: splitGain * share,
                        elevationLoss: splitLoss * share,
                        isPartial: false
                    )
                )

                splitDuration -= countedDuration
                splitGain *= (1 - share)
                splitLoss *= (1 - share)
                splitDistanceSoFar = overshoot
            }
        }

        // Whatever is left over is a real part of the outing and worth showing,
        // as long as it is long enough to mean something.
        if splitDistanceSoFar > splitDistance * 0.1 {
            splits.append(
                ActivitySplit(
                    index: splits.count + 1,
                    distance: splitDistanceSoFar,
                    duration: splitDuration,
                    elevationGain: splitGain,
                    elevationLoss: splitLoss,
                    isPartial: true
                )
            )
        }

        result.elevationLoss = totalLoss
        result.steepestGrade = steepest
        result.movingTime = movingTime
        result.splits = hasTimes ? splits : []

        // Only whole splits are ranked: a 200 m tail is always the "fastest"
        // by pace if you let it compete, which tells the athlete nothing.
        let whole = result.splits.filter { !$0.isPartial && $0.pace > 0 }
        if whole.count > 1 {
            result.fastestSplit = whole.min { $0.pace < $1.pace }
            result.slowestSplit = whole.max { $0.pace < $1.pace }
        }

        return result
    }
}
