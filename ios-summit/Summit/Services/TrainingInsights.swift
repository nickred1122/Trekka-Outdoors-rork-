import Foundation

/// How an observation should read: something going well, something neutral, or
/// something worth easing off for.
nonisolated enum InsightTone: Sendable, Hashable {
    case positive
    case neutral
    case caution
}

/// One thing worth telling the athlete about their own recorded training.
nonisolated struct TrainingInsight: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var detail: String
    var symbol: String
    var tone: InsightTone

    /// The line handed to the writing model, and the only thing it is allowed
    /// to talk about.
    var fact: String { "\(title): \(detail)" }
}

/// Works out what the athlete's own data actually says.
///
/// Every figure here is computed from recorded workouts and Apple Health —
/// nothing is estimated, and an observation is only produced when the data
/// behind it exists. This is deliberately separate from anything to do with
/// Apple Intelligence: the numbers are arithmetic, and a language model is only
/// ever allowed to phrase them afterwards.
nonisolated enum InsightEngine {
    private static let window: TimeInterval = 7 * 24 * 60 * 60

    static func insights(
        activities: [ActivityRecord],
        snapshot: HealthSnapshot,
        day: DayNutrition,
        goals: NutritionGoals,
        now: Date = .now
    ) -> [TrainingInsight] {
        let recent = activities.filter { now.timeIntervalSince($0.startDate) <= window && $0.startDate <= now }
        let previous = activities.filter {
            let age = now.timeIntervalSince($0.startDate)
            return age > window && age <= window * 2
        }

        var insights: [TrainingInsight] = []

        if let volume = volumeInsight(recent: recent, previous: previous) {
            insights.append(volume)
        }
        if let consistency = consistencyInsight(recent: recent, now: now) {
            insights.append(consistency)
        }
        if let resting = restingInsight(snapshot: snapshot) {
            insights.append(resting)
        }
        if let sleep = sleepInsight(snapshot: snapshot) {
            insights.append(sleep)
        }
        if let climbing = climbingInsight(recent: recent) {
            insights.append(climbing)
        }
        if let longest = longestInsight(recent: recent) {
            insights.append(longest)
        }
        if let fuel = fuelInsight(day: day, goals: goals, snapshot: snapshot) {
            insights.append(fuel)
        }

        return insights
    }

    // MARK: - Training

    private static func volumeInsight(recent: [ActivityRecord], previous: [ActivityRecord]) -> TrainingInsight? {
        guard !recent.isEmpty else { return nil }

        let time = recent.reduce(0) { $0 + $1.duration }
        let distance = recent.reduce(0) { $0 + $1.distance }
        guard time > 0 else { return nil }

        var detail = "\(Formatters.compactDuration(time)) across \(recent.count) \(recent.count == 1 ? "session" : "sessions")"
        if distance > 100 {
            detail += ", \(Formatters.distanceWithUnit(distance))"
        }

        // A comparison is only offered when there is a week to compare against.
        // "Up 100%" from a single session in an otherwise empty fortnight is
        // arithmetic, not insight.
        let previousTime = previous.reduce(0) { $0 + $1.duration }
        var tone: InsightTone = .neutral
        if previousTime > 0 {
            let change = time - previousTime
            let ratio = change / previousTime
            if abs(ratio) < 0.1 {
                detail += " — about the same as the week before"
            } else if change > 0 {
                detail += " — up \(Formatters.compactDuration(change)) on the week before"
                // A jump of more than half again in a week is the classic way
                // people get hurt, so it is flagged rather than congratulated.
                tone = ratio > 0.5 ? .caution : .positive
            } else {
                detail += " — down \(Formatters.compactDuration(-change)) on the week before"
            }
        }

        return TrainingInsight(
            id: "volume",
            title: "This week",
            detail: detail,
            symbol: "figure.run",
            tone: tone
        )
    }

    private static func consistencyInsight(recent: [ActivityRecord], now: Date) -> TrainingInsight? {
        guard !recent.isEmpty else { return nil }
        let calendar = Calendar.current
        let days = Set(recent.map { calendar.startOfDay(for: $0.startDate) }).count
        guard days > 0 else { return nil }

        let detail: String
        let tone: InsightTone
        switch days {
        case 6...7:
            detail = "You trained on \(days) of the last 7 days. That leaves little room to absorb the work."
            tone = .caution
        case 3...5:
            detail = "You trained on \(days) of the last 7 days."
            tone = .positive
        default:
            detail = "You trained on \(days) of the last 7 days."
            tone = .neutral
        }

        return TrainingInsight(
            id: "consistency",
            title: "Consistency",
            detail: detail,
            symbol: "calendar",
            tone: tone
        )
    }

    private static func climbingInsight(recent: [ActivityRecord]) -> TrainingInsight? {
        let gain = recent.reduce(0) { $0 + $1.elevationGain }
        guard gain >= 50 else { return nil }
        return TrainingInsight(
            id: "climbing",
            title: "Climbing",
            detail: "\(Formatters.elevation(gain)) \(Formatters.elevationUnit) of ascent in the last 7 days",
            symbol: "mountain.2.fill",
            tone: .neutral
        )
    }

    private static func longestInsight(recent: [ActivityRecord]) -> TrainingInsight? {
        guard let longest = recent.max(by: { $0.duration < $1.duration }), longest.duration > 0 else { return nil }
        var detail = "\(longest.name) — \(Formatters.compactDuration(longest.duration))"
        if longest.distance > 100 {
            detail += " and \(Formatters.distanceWithUnit(longest.distance))"
        }
        return TrainingInsight(
            id: "longest",
            title: "Longest session",
            detail: detail,
            symbol: longest.activity.symbol,
            tone: .neutral
        )
    }

    // MARK: - Recovery

    private static func restingInsight(snapshot: HealthSnapshot) -> TrainingInsight? {
        let resting = snapshot.restingHeartRate
        let baseline = snapshot.restingBaseline
        guard resting > 0, baseline > 0 else { return nil }

        let drift = resting - baseline
        // Matches the threshold the readiness score uses, so the dashboard and
        // this card can never disagree about the same heart rate.
        guard abs(drift) >= 3 else {
            return TrainingInsight(
                id: "resting",
                title: "Resting heart rate",
                detail: "\(Int(resting.rounded())) bpm, in line with your \(Int(baseline.rounded())) bpm baseline",
                symbol: "heart.fill",
                tone: .positive
            )
        }

        if drift > 0 {
            return TrainingInsight(
                id: "resting",
                title: "Resting heart rate",
                detail: "\(Int(resting.rounded())) bpm, \(Int(drift.rounded())) above your \(Int(baseline.rounded())) bpm baseline. That usually means fatigue or a bug coming on.",
                symbol: "heart.fill",
                tone: .caution
            )
        }
        return TrainingInsight(
            id: "resting",
            title: "Resting heart rate",
            detail: "\(Int(resting.rounded())) bpm, \(Int((-drift).rounded())) below your \(Int(baseline.rounded())) bpm baseline",
            symbol: "heart.fill",
            tone: .positive
        )
    }

    private static func sleepInsight(snapshot: HealthSnapshot) -> TrainingInsight? {
        // Only nights that were actually recorded count. Averaging in zeros for
        // nights the watch was on charge would invent a sleep problem.
        let recorded = snapshot.sleepTrend.suffix(7).filter { $0 > 0 }
        guard recorded.count >= 3 else { return nil }

        let average = recorded.reduce(0, +) / Double(recorded.count)
        let hours = Int(average) / 3600
        let minutes = (Int(average) % 3600) / 60
        let text = "\(hours)h \(minutes)m a night across \(recorded.count) recorded nights"

        return TrainingInsight(
            id: "sleep",
            title: "Sleep",
            detail: average < 7 * 3600
                ? "\(text) — under the 7 hours most training plans assume"
                : text,
            symbol: "moon.zzz.fill",
            tone: average < 7 * 3600 ? .caution : .positive
        )
    }

    // MARK: - Fuel

    private static func fuelInsight(
        day: DayNutrition,
        goals: NutritionGoals,
        snapshot: HealthSnapshot
    ) -> TrainingInsight? {
        guard !day.isEmpty else { return nil }
        let eaten = day.total.energyKilocalories
        let target = goals.energyTarget(activeEnergy: snapshot.activeCalories)
        guard target > 0 else { return nil }

        let remaining = target - eaten
        let detail: String
        if remaining > 50 {
            detail = "\(Int(eaten.rounded())) kcal logged today, \(Int(remaining.rounded())) under your target"
        } else if remaining < -50 {
            detail = "\(Int(eaten.rounded())) kcal logged today, \(Int((-remaining).rounded())) over your target"
        } else {
            detail = "\(Int(eaten.rounded())) kcal logged today, on target"
        }

        return TrainingInsight(
            id: "fuel",
            title: "Fuel",
            detail: detail,
            symbol: "fork.knife",
            tone: .neutral
        )
    }
}
