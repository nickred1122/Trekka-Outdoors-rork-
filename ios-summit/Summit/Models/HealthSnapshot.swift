import Foundation

/// A single day's aggregated health and training metrics.
nonisolated struct HealthSnapshot: Sendable, Equatable {
    var readiness: Int
    var readinessCaption: String
    var sleepSeconds: TimeInterval
    var sleepScore: Int
    var hrv: Double
    var hrvBaseline: Double
    var vo2Max: Double
    var trainingLoad: Int
    var activeCalories: Double
    var steps: Int
    var restingHeartRate: Double
    var exerciseMinutes: Double
    var flightsClimbed: Double
    var respiratoryRate: Double
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
        sleepSeconds: 0,
        sleepScore: 0,
        hrv: 0,
        hrvBaseline: 0,
        vo2Max: 0,
        trainingLoad: 0,
        activeCalories: 0,
        steps: 0,
        restingHeartRate: 0,
        exerciseMinutes: 0,
        flightsClimbed: 0,
        respiratoryRate: 0,
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

    var id: String { title }

    var fraction: Double {
        guard maxPoints > 0 else { return 0 }
        return max(0, min(1, points / maxPoints))
    }
}

/// Derives a Garmin-style readiness score and caption from recovery inputs.
nonisolated enum ReadinessCalculator {
    static func score(sleepSeconds: TimeInterval, sleepScore: Int, hrv: Double, hrvBaseline: Double, load: Int) -> Int {
        guard sleepSeconds > 0 || hrv > 0 else { return 0 }
        let sleepHours = sleepSeconds / 3600
        let sleepComponent = min(1.0, sleepHours / 8.0) * 40
        let hrvRatio = hrvBaseline > 0 ? min(1.4, hrv / hrvBaseline) : 1.0
        let hrvComponent = min(1.0, hrvRatio / 1.1) * 35
        let qualityComponent = Double(sleepScore) / 100 * 15
        let loadPenalty = max(0, Double(load) - 500) / 500 * 20
        let raw = sleepComponent + hrvComponent + qualityComponent + 10 - loadPenalty
        return max(1, min(100, Int(raw.rounded())))
    }

    /// Breaks the score into its weighted inputs so the user can see what moved it.
    static func factors(for snapshot: HealthSnapshot) -> [ReadinessFactor] {
        let hours = snapshot.sleepSeconds / 3600
        let sleepPoints = min(1.0, hours / 8.0) * 40
        let ratio = snapshot.hrvBaseline > 0 ? min(1.4, snapshot.hrv / snapshot.hrvBaseline) : 1.0
        let hrvPoints = min(1.0, ratio / 1.1) * 35
        let qualityPoints = Double(snapshot.sleepScore) / 100 * 15
        let loadPenalty = max(0, Double(snapshot.trainingLoad) - 500) / 500 * 20

        return [
            ReadinessFactor(
                title: "Sleep duration",
                detail: hours > 0 ? String(format: "%.1f h of %d h target", hours, 8) : "No sleep recorded",
                points: sleepPoints,
                maxPoints: 40,
                symbol: "moon.zzz.fill"
            ),
            ReadinessFactor(
                title: "HRV vs baseline",
                detail: snapshot.hrvBaseline > 0
                    ? String(format: "%.0f ms against a %.0f ms baseline", snapshot.hrv, snapshot.hrvBaseline)
                    : "Baseline still building",
                points: hrvPoints,
                maxPoints: 35,
                symbol: "waveform.path.ecg"
            ),
            ReadinessFactor(
                title: "Sleep quality",
                detail: snapshot.sleepScore > 0 ? "Quality score \(snapshot.sleepScore) of 100" : "No stage data",
                points: qualityPoints,
                maxPoints: 15,
                symbol: "sparkles"
            ),
            ReadinessFactor(
                title: "Training load",
                detail: loadPenalty > 0
                    ? "Load \(snapshot.trainingLoad) is above the 500 comfort ceiling"
                    : "Load \(snapshot.trainingLoad) is inside your comfort ceiling",
                points: loadPenalty,
                maxPoints: 20,
                symbol: "chart.bar.fill",
                isPenalty: true
            ),
        ]
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
}
