import Foundation

/// A single day's aggregated health and training metrics.
nonisolated struct HealthSnapshot: Sendable, Equatable {
    var readiness: Int
    var readinessCaption: String
    /// How much of the readiness score was backed by real measurements, 0 to 1.
    ///
    /// Shown to the athlete rather than hidden, because a score built on one
    /// input out of three deserves less trust than one built on all of them.
    var readinessCoverage: Double = 0
    var sleepSeconds: TimeInterval
    var sleepScore: Int
    /// Last night stage by stage. Empty when no tracker recorded stages.
    var sleepNight: SleepNight = .empty
    var hrv: Double
    var hrvBaseline: Double
    var vo2Max: Double
    var trainingLoad: Int
    var activeCalories: Double
    var steps: Int
    var restingHeartRate: Double
    /// The athlete's own recent average resting rate, so today can be read
    /// against it rather than against a population figure.
    var restingBaseline: Double = 0
    var exerciseMinutes: Double
    var flightsClimbed: Double
    var respiratoryRate: Double
    /// The athlete's own 30-day average breathing rate, so tonight can be read
    /// against it. A rate sitting above your own normal is one of the earliest
    /// signals of illness there is.
    var respiratoryBaseline: Double = 0
    var bodyMass: Double
    var sleepTrend: [Double]
    var hrvTrend: [Double]
    var vo2Trend: [Double]
    var loadTrend: [Double]
    var caloriesTrend: [Double]
    var stepsTrend: [Double]
    var restingTrend: [Double]
    var exerciseTrend: [Double]
    var flightsTrend: [Double]
    var respiratoryTrend: [Double]
    var bodyMassTrend: [Double]
    var zoneMinutes: [Double]

    var sleepText: String {
        let hours = Int(sleepSeconds) / 3600
        let minutes = (Int(sleepSeconds) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }

    static let empty = HealthSnapshot(
        readiness: 0,
        readinessCaption: "No data yet",
        readinessCoverage: 0,
        sleepSeconds: 0,
        sleepScore: 0,
        sleepNight: .empty,
        hrv: 0,
        hrvBaseline: 0,
        vo2Max: 0,
        trainingLoad: 0,
        activeCalories: 0,
        steps: 0,
        restingHeartRate: 0,
        restingBaseline: 0,
        exerciseMinutes: 0,
        flightsClimbed: 0,
        respiratoryRate: 0,
        respiratoryBaseline: 0,
        bodyMass: 0,
        sleepTrend: [],
        hrvTrend: [],
        vo2Trend: [],
        loadTrend: [],
        caloriesTrend: [],
        stepsTrend: [],
        restingTrend: [],
        exerciseTrend: [],
        flightsTrend: [],
        respiratoryTrend: [],
        bodyMassTrend: [],
        zoneMinutes: [0, 0, 0, 0, 0]
    )
}

/// One weighted contributor to the readiness score, used by the drill-down.
nonisolated struct ReadinessFactor: Identifiable, Sendable {
    var title: String
    var detail: String
    var points: Double
    var maxPoints: Double
    var symbol: String
    /// Penalties are drawn in red and read as a negative contribution.
    var isPenalty: Bool = false
    /// False when the data behind this input is missing.
    ///
    /// This distinction is the whole point: an unmeasured input is not a zero.
    /// A row that says "not measured" is honest; a bar sitting empty because the
    /// watch was on charge is a lie about the athlete's recovery.
    var isMeasured: Bool = true

    var id: String { title }

    var fraction: Double {
        guard maxPoints > 0, isMeasured else { return 0 }
        return max(0, min(1, points / maxPoints))
    }
}

/// Derives a readiness score and caption from recovery inputs.
///
/// The score is built from the inputs that were actually measured, weighted
/// against each other, then scaled to a hundred. That normalisation is the
/// important part: an athlete who does not wear the watch to bed used to be told
/// they were "depleted", because a missing night was scored as forty points of
/// missing sleep rather than as an unknown. A score is now only produced when
/// enough is known to justify one, and `coverage` says how much that was.
nonisolated enum ReadinessCalculator {
    /// How far resting heart rate has to rise above its own baseline before it
    /// counts as a warning. Below this it is ordinary night-to-night noise.
    private static let restingDriftThreshold: Double = 3

    /// How far breathing rate has to rise above its own baseline to count.
    ///
    /// A breath a minute over your own normal is noise; two is the signal that
    /// tends to show up a day before you feel ill.
    private static let respiratoryDriftThreshold: Double = 1.5

    /// Relative weights of the positive inputs. They do not have to add to a
    /// hundred — the score is scaled by whatever was measured.
    private static let sleepWeight: Double = 40
    private static let hrvWeight: Double = 35
    private static let qualityWeight: Double = 15

    /// The least of the positive weight that has to be measured before a score is
    /// worth showing at all. Sleep quality on its own is not readiness.
    private static let minimumCoverage: Double = 0.4

    /// A readiness score and how much of it was actually measured.
    nonisolated struct Result: Sendable, Equatable {
        var score: Int
        /// The share of the positive weight backed by real data, 0 to 1.
        var coverage: Double

        static let unknown = Result(score: 0, coverage: 0)
    }

    /// A raised resting heart rate is the oldest and most reliable overtraining
    /// signal there is — it climbs before you feel tired, and it climbs when you
    /// are coming down with something. Measured against your own recent average
    /// rather than any population figure.
    static func restingPenalty(resting: Double, baseline: Double) -> Double {
        guard resting > 0, baseline > 0 else { return 0 }
        let drift = resting - baseline
        guard drift > restingDriftThreshold else { return 0 }
        // Five beats over baseline is a rest day; the scale saturates there.
        return min(1, (drift - restingDriftThreshold) / 5) * 15
    }

    /// A raised breathing rate is the other early illness signal, and it is in
    /// Health already for anybody wearing a watch overnight.
    static func respiratoryPenalty(rate: Double, baseline: Double) -> Double {
        guard rate > 0, baseline > 0 else { return 0 }
        let drift = rate - baseline
        guard drift > respiratoryDriftThreshold else { return 0 }
        // Three breaths a minute over your own normal saturates the scale.
        return min(1, (drift - respiratoryDriftThreshold) / 3) * 10
    }

    /// The sleep target readiness measures against.
    ///
    /// Eight hours is the default because most training plans assume it, but an
    /// athlete who has set their own nightly target is measured against that —
    /// scoring a settled six-hour sleeper against somebody else's eight is a
    /// permanent penalty they can do nothing about.
    static func sleepTargetHours(_ goal: Double?) -> Double {
        guard let goal, goal >= 4, goal <= 12 else { return 8 }
        return goal
    }

    static func result(
        sleepSeconds: TimeInterval,
        sleepScore: Int,
        hrv: Double,
        hrvBaseline: Double,
        load: Int,
        restingHeartRate: Double = 0,
        restingBaseline: Double = 0,
        respiratoryRate: Double = 0,
        respiratoryBaseline: Double = 0,
        sleepGoalHours: Double? = nil
    ) -> Result {
        var earned: Double = 0
        var available: Double = 0

        // Sleep duration, against the athlete's own target.
        if sleepSeconds > 0 {
            let target = sleepTargetHours(sleepGoalHours)
            earned += min(1, sleepSeconds / 3600 / target) * sleepWeight
            available += sleepWeight
        }

        // HRV only counts when there is a baseline to read it against. A raw
        // millisecond figure means nothing on its own — healthy athletes sit
        // anywhere from 20 ms to 150 ms — and the old code handed out 32 of 35
        // points for free whenever the baseline was missing.
        if hrv > 0, hrvBaseline > 0 {
            let ratio = min(1.4, hrv / hrvBaseline)
            earned += min(1, ratio / 1.1) * hrvWeight
            available += hrvWeight
        }

        if sleepScore > 0 {
            earned += Double(sleepScore) / 100 * qualityWeight
            available += qualityWeight
        }

        let total = sleepWeight + hrvWeight + qualityWeight
        let coverage = available / total
        guard available > 0, coverage >= minimumCoverage else { return .unknown }

        // Scaled by what was measured rather than by everything that could have
        // been, so a missing input widens the uncertainty instead of pretending
        // to be a bad night.
        let positive = earned / available * 100

        let penalties = loadPenalty(load)
            + restingPenalty(resting: restingHeartRate, baseline: restingBaseline)
            + respiratoryPenalty(rate: respiratoryRate, baseline: respiratoryBaseline)

        let score = max(1, min(100, Int((positive - penalties).rounded())))
        return Result(score: score, coverage: min(1, coverage))
    }

    static func loadPenalty(_ load: Int) -> Double {
        max(0, Double(load) - 500) / 500 * 20
    }

    /// Breaks the score into its weighted inputs so the user can see what moved it.
    ///
    /// Unmeasured inputs are marked as such rather than shown at zero. An empty
    /// bar and a missing measurement look identical, and conflating them is how
    /// somebody who left the watch on charge gets told they are exhausted.
    static func factors(for snapshot: HealthSnapshot, sleepGoalHours: Double? = nil) -> [ReadinessFactor] {
        let hours = snapshot.sleepSeconds / 3600
        let target = sleepTargetHours(sleepGoalHours)
        let hasSleep = snapshot.sleepSeconds > 0
        let hasHRV = snapshot.hrv > 0 && snapshot.hrvBaseline > 0
        let sleepPoints = min(1.0, hours / target) * sleepWeight
        let ratio = hasHRV ? min(1.4, snapshot.hrv / snapshot.hrvBaseline) : 0
        let hrvPoints = hasHRV ? min(1.0, ratio / 1.1) * hrvWeight : 0
        let qualityPoints = Double(snapshot.sleepScore) / 100 * qualityWeight
        let load = loadPenalty(snapshot.trainingLoad)

        return [
            ReadinessFactor(
                title: "Sleep duration",
                detail: hasSleep
                    ? String(format: "%.1f h of your %.1f h target", hours, target)
                    : "Not measured last night",
                points: sleepPoints,
                maxPoints: sleepWeight,
                symbol: "moon.zzz.fill",
                isMeasured: hasSleep
            ),
            ReadinessFactor(
                title: "HRV vs baseline",
                detail: hasHRV
                    ? String(format: "%.0f ms against a %.0f ms baseline", snapshot.hrv, snapshot.hrvBaseline)
                    : (snapshot.hrv > 0 ? "Baseline still building" : "Not measured last night"),
                points: hrvPoints,
                maxPoints: hrvWeight,
                symbol: "waveform.path.ecg",
                isMeasured: hasHRV
            ),
            ReadinessFactor(
                title: "Sleep quality",
                detail: snapshot.sleepScore > 0 ? "Quality score \(snapshot.sleepScore) of 100" : "No stage data",
                points: qualityPoints,
                maxPoints: qualityWeight,
                symbol: "sparkles",
                isMeasured: snapshot.sleepScore > 0
            ),
            ReadinessFactor(
                title: "Training load",
                detail: load > 0
                    ? "Load \(snapshot.trainingLoad) is above the 500 comfort ceiling"
                    : "Load \(snapshot.trainingLoad) is inside your comfort ceiling",
                points: load,
                maxPoints: 20,
                symbol: "chart.bar.fill",
                isPenalty: true
            ),
            ReadinessFactor(
                title: "Resting heart rate",
                detail: restingDetail(for: snapshot),
                points: restingPenalty(
                    resting: snapshot.restingHeartRate,
                    baseline: snapshot.restingBaseline
                ),
                maxPoints: 15,
                symbol: "heart.fill",
                isPenalty: true
            ),
        ]
    }

    private static func restingDetail(for snapshot: HealthSnapshot) -> String {
        guard snapshot.restingHeartRate > 0 else { return "No resting rate recorded" }
        guard snapshot.restingBaseline > 0 else { return "Baseline still building" }
        let drift = snapshot.restingHeartRate - snapshot.restingBaseline
        if drift > restingDriftThreshold {
            return String(
                format: "%.0f bpm, %.0f above your %.0f bpm baseline",
                snapshot.restingHeartRate,
                drift,
                snapshot.restingBaseline
            )
        }
        return String(
            format: "%.0f bpm, in line with your %.0f bpm baseline",
            snapshot.restingHeartRate,
            snapshot.restingBaseline
        )
    }

    static func caption(for score: Int) -> String {
        switch score {
        case 85...100: "Peaking — chase a personal best"
        case 70..<85: "Primed — go hard today"
        case 50..<70: "Steady — moderate effort suits you"
        case 30..<50: "Strained — keep it aerobic"
        case 1..<30: "Depleted — prioritise recovery"
        default: "Connect Health to see readiness"
        }
    }

    /// How much the score should be trusted, said plainly.
    ///
    /// A number with no hedge invites more confidence than a partial night's
    /// data can support, and hiding the hedge is how a fitness app ends up
    /// telling somebody they are exhausted because their watch was charging.
    static func confidence(coverage: Double) -> String? {
        guard coverage > 0 else { return nil }
        if coverage >= 0.99 { return nil }
        if coverage >= 0.6 {
            return "Based on most of your overnight data — one input was missing."
        }
        return "Based on part of your overnight data, so treat it loosely. Wearing your watch overnight gives it sleep and HRV to work with."
    }
}
