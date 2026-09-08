import Foundation

/// What one recorded session says, measured against the athlete's own history.
///
/// Deliberately separate from `InsightEngine`, which looks at the last week as a
/// whole. This looks at a single session and answers the question somebody
/// actually has when they open it: was that good, for me?
///
/// Every comparison is against this athlete's own comparable sessions — same
/// activity type, before this one. There is no population data anywhere in here,
/// and an observation is only produced when enough of the athlete's own history
/// exists to support it.
nonisolated enum ActivityInsightEngine {
    /// How many earlier sessions of the same kind are needed before a comparison
    /// is worth making. Two sessions is an anecdote; five is a habit.
    private static let minimumComparable = 4

    static func insights(
        for activity: ActivityRecord,
        history: [ActivityRecord]
    ) -> [TrainingInsight] {
        // Same kind of activity, recorded before this one. Comparing a gym
        // session against a hill walk would be arithmetic without meaning.
        let comparable = history.filter {
            $0.id != activity.id
                && $0.activity == activity.activity
                && $0.startDate < activity.startDate
        }

        var insights: [TrainingInsight] = []

        if let effort = effortInsight(activity) {
            insights.append(effort)
        }

        guard comparable.count >= minimumComparable else {
            // Too early to compare, and saying so is better than staying silent:
            // it tells the athlete the comparisons are coming.
            if let first = firstOfItsKind(activity, comparable: comparable) {
                insights.append(first)
            }
            return insights
        }

        if let distance = distanceInsight(activity, comparable: comparable) {
            insights.append(distance)
        }
        if let pace = paceInsight(activity, comparable: comparable) {
            insights.append(pace)
        }
        if let climb = climbInsight(activity, comparable: comparable) {
            insights.append(climb)
        }
        if let heart = heartInsight(activity, comparable: comparable) {
            insights.append(heart)
        }
        if let volume = strengthInsight(activity, comparable: comparable) {
            insights.append(volume)
        }
        return insights
    }

    // MARK: - Effort

    /// Where the session's time actually went, from the recorded zone minutes.
    private static func effortInsight(_ activity: ActivityRecord) -> TrainingInsight? {
        let minutes = activity.zoneMinutes
        let total = minutes.reduce(0, +)
        guard total > 1 else { return nil }

        let hard = minutes.dropFirst(3).reduce(0, +)
        let easy = minutes.prefix(2).reduce(0, +)
        let hardShare = hard / total
        let easyShare = easy / total

        if hardShare >= 0.4 {
            return TrainingInsight(
                id: "session.effort",
                title: "Hard session",
                detail: "\(Int(hard.rounded())) of \(Int(total.rounded())) minutes in zones 4 and 5. Leave room to recover before the next one.",
                symbol: "flame.fill",
                tone: .caution
            )
        }
        if easyShare >= 0.7 {
            return TrainingInsight(
                id: "session.effort",
                title: "Easy session",
                detail: "\(Int(easy.rounded())) of \(Int(total.rounded())) minutes in zones 1 and 2 — the aerobic work most plans are built on.",
                symbol: "leaf.fill",
                tone: .positive
            )
        }
        return TrainingInsight(
            id: "session.effort",
            title: "Steady session",
            detail: "Most of \(Int(total.rounded())) minutes spent in zone 3.",
            symbol: "gauge.medium",
            tone: .neutral
        )
    }

    private static func firstOfItsKind(
        _ activity: ActivityRecord,
        comparable: [ActivityRecord]
    ) -> TrainingInsight? {
        let needed = minimumComparable - comparable.count
        guard needed > 0 else { return nil }
        let name = activity.activity.title.lowercased()
        return TrainingInsight(
            id: "session.baseline",
            title: comparable.isEmpty ? "Your first \(name)" : "Building a baseline",
            detail: comparable.isEmpty
                ? "Nothing to compare it against yet. Trekka starts measuring your \(name)s against each other from here."
                : "\(needed) more \(name)\(needed == 1 ? "" : "s") and Trekka can tell you how this one compares to your usual.",
            symbol: "chart.line.uptrend.xyaxis",
            tone: .neutral
        )
    }

    // MARK: - Comparisons

    private static func distanceInsight(
        _ activity: ActivityRecord,
        comparable: [ActivityRecord]
    ) -> TrainingInsight? {
        let distances = comparable.map(\.distance).filter { $0 > 100 }
        guard activity.distance > 100, distances.count >= minimumComparable else { return nil }

        let best = distances.max() ?? 0
        let average = distances.reduce(0, +) / Double(distances.count)

        if activity.distance > best {
            return TrainingInsight(
                id: "session.distance",
                title: "Furthest yet",
                detail: "\(Formatters.distanceWithUnit(activity.distance)) — past your previous best of \(Formatters.distanceWithUnit(best)).",
                symbol: "trophy.fill",
                tone: .positive
            )
        }

        let ratio = (activity.distance - average) / average
        guard abs(ratio) >= 0.15 else { return nil }
        return TrainingInsight(
            id: "session.distance",
            title: "Distance",
            detail: ratio > 0
                ? "\(Formatters.distanceWithUnit(activity.distance)) — \(Int((ratio * 100).rounded()))% further than your usual \(Formatters.distanceWithUnit(average))."
                : "\(Formatters.distanceWithUnit(activity.distance)) — a shorter one, against your usual \(Formatters.distanceWithUnit(average)).",
            symbol: "arrow.left.and.right",
            tone: ratio > 0 ? .positive : .neutral
        )
    }

    /// Pace, compared only against sessions with comparable climbing.
    ///
    /// This is the comparison that gets done badly everywhere. Pace on a flat
    /// towpath and pace up a mountain are different measurements, and calling one
    /// an improvement on the other is simply wrong. So sessions whose climbing
    /// per kilometre is wildly different are left out rather than averaged in.
    private static func paceInsight(
        _ activity: ActivityRecord,
        comparable: [ActivityRecord]
    ) -> TrainingInsight? {
        guard activity.averagePace > 0, activity.distance > 500 else { return nil }
        let gradient = climbPerKilometre(activity)

        let similar = comparable.filter { other in
            guard other.averagePace > 0, other.distance > 500 else { return false }
            let difference = abs(climbPerKilometre(other) - gradient)
            // Within 15 m of climb per kilometre counts as comparable ground.
            return difference <= 15
        }
        guard similar.count >= minimumComparable else { return nil }

        let paces = similar.map(\.averagePace)
        let average = paces.reduce(0, +) / Double(paces.count)
        let quickest = paces.min() ?? average
        let terrain = gradient >= 15 ? " on similar climbing" : " on similar ground"

        if activity.averagePace < quickest {
            return TrainingInsight(
                id: "session.pace",
                title: "Quickest yet",
                detail: "\(Formatters.pace(activity.averagePace)) \(Formatters.units.paceUnit) — your best\(terrain).",
                symbol: "bolt.fill",
                tone: .positive
            )
        }

        let delta = average - activity.averagePace
        // Under twenty seconds a kilometre is inside the noise of GPS drift and
        // a different day's weather.
        guard abs(delta) >= 20 else {
            return TrainingInsight(
                id: "session.pace",
                title: "Pace",
                detail: "\(Formatters.pace(activity.averagePace)) \(Formatters.units.paceUnit) — in line with your usual\(terrain).",
                symbol: "speedometer",
                tone: .positive
            )
        }
        return TrainingInsight(
            id: "session.pace",
            title: "Pace",
            detail: delta > 0
                ? "\(Formatters.pace(activity.averagePace)) \(Formatters.units.paceUnit) — \(Formatters.compactDuration(delta)) a \(Formatters.units.distanceUnit) quicker than your usual\(terrain)."
                : "\(Formatters.pace(activity.averagePace)) \(Formatters.units.paceUnit) — \(Formatters.compactDuration(-delta)) a \(Formatters.units.distanceUnit) slower than your usual\(terrain).",
            symbol: "speedometer",
            tone: delta > 0 ? .positive : .neutral
        )
    }

    private static func climbInsight(
        _ activity: ActivityRecord,
        comparable: [ActivityRecord]
    ) -> TrainingInsight? {
        guard activity.elevationGain >= 50 else { return nil }
        let gains = comparable.map(\.elevationGain).filter { $0 > 10 }
        guard gains.count >= minimumComparable else { return nil }

        let best = gains.max() ?? 0
        if activity.elevationGain > best {
            return TrainingInsight(
                id: "session.climb",
                title: "Biggest climb yet",
                detail: "\(Formatters.elevation(activity.elevationGain)) \(Formatters.elevationUnit) of ascent — past your previous best of \(Formatters.elevation(best)) \(Formatters.elevationUnit).",
                symbol: "mountain.2.fill",
                tone: .positive
            )
        }

        let average = gains.reduce(0, +) / Double(gains.count)
        guard average > 0 else { return nil }
        let ratio = (activity.elevationGain - average) / average
        guard abs(ratio) >= 0.25 else { return nil }
        return TrainingInsight(
            id: "session.climb",
            title: "Climbing",
            detail: ratio > 0
                ? "\(Formatters.elevation(activity.elevationGain)) \(Formatters.elevationUnit) — well above your usual \(Formatters.elevation(average)) \(Formatters.elevationUnit)."
                : "\(Formatters.elevation(activity.elevationGain)) \(Formatters.elevationUnit) — a flatter one than usual.",
            symbol: "mountain.2.fill",
            tone: .neutral
        )
    }

    /// Heart rate for the pace held — the closest honest thing to a fitness
    /// signal a single session can offer.
    private static func heartInsight(
        _ activity: ActivityRecord,
        comparable: [ActivityRecord]
    ) -> TrainingInsight? {
        guard activity.averageHeartRate > 0 else { return nil }
        let rates = comparable.map(\.averageHeartRate).filter { $0 > 0 }
        guard rates.count >= minimumComparable else { return nil }

        let average = rates.reduce(0, +) / Double(rates.count)
        let drift = activity.averageHeartRate - average
        guard abs(drift) >= 4 else {
            return TrainingInsight(
                id: "session.heart",
                title: "Average heart rate",
                detail: "\(Int(activity.averageHeartRate.rounded())) bpm, in line with your usual \(Int(average.rounded())) bpm for this.",
                symbol: "heart.fill",
                tone: .neutral
            )
        }
        return TrainingInsight(
            id: "session.heart",
            title: "Average heart rate",
            detail: drift > 0
                ? "\(Int(activity.averageHeartRate.rounded())) bpm, \(Int(drift.rounded())) above your usual for this. Heat, fatigue or a harder effort will all do that."
                : "\(Int(activity.averageHeartRate.rounded())) bpm, \(Int((-drift).rounded())) below your usual for this \u{2014} the same work for less cost.",
            symbol: "heart.fill",
            tone: drift > 0 ? .neutral : .positive
        )
    }

    private static func strengthInsight(
        _ activity: ActivityRecord,
        comparable: [ActivityRecord]
    ) -> TrainingInsight? {
        guard !activity.strengthSets.isEmpty else { return nil }
        let volume = activity.strengthSets.reduce(0) { $0 + $1.volume }
        guard volume > 0 else { return nil }

        let volumes = comparable
            .map { $0.strengthSets.reduce(0) { $0 + $1.volume } }
            .filter { $0 > 0 }
        guard volumes.count >= minimumComparable else { return nil }

        let best = volumes.max() ?? 0
        let shown = Formatters.integer(Formatters.mass(fromKilograms: volume))
        let unit = Formatters.massUnit

        if volume > best {
            return TrainingInsight(
                id: "session.volume",
                title: "Most volume yet",
                detail: "\(shown) \(unit) moved — past your previous best of \(Formatters.integer(Formatters.mass(fromKilograms: best))) \(unit).",
                symbol: "trophy.fill",
                tone: .positive
            )
        }

        let average = volumes.reduce(0, +) / Double(volumes.count)
        guard average > 0 else { return nil }
        let ratio = (volume - average) / average
        guard abs(ratio) >= 0.15 else { return nil }
        return TrainingInsight(
            id: "session.volume",
            title: "Volume",
            detail: ratio > 0
                ? "\(shown) \(unit) moved — \(Int((ratio * 100).rounded()))% above your usual session."
                : "\(shown) \(unit) moved — a lighter session than your usual.",
            symbol: "dumbbell.fill",
            tone: ratio > 0 ? .positive : .neutral
        )
    }

    private static func climbPerKilometre(_ activity: ActivityRecord) -> Double {
        guard activity.distance > 100 else { return 0 }
        return activity.elevationGain / (activity.distance / 1000)
    }
}
