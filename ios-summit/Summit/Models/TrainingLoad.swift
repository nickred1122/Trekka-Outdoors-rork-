import Foundation

/// One day of training stress, and the fitness and fatigue it left behind.
nonisolated struct TrainingLoadDay: Identifiable, Sendable, Hashable {
    var date: Date
    /// Stress earned on this day alone. Zero on a rest day.
    var load: Double
    /// The slow-moving average: what the body has adapted to.
    var fitness: Double
    /// The fast-moving average: what it has not recovered from yet.
    var fatigue: Double

    var id: Date { date }

    /// Fitness minus fatigue. Positive means fresh, negative means buried.
    var form: Double { fitness - fatigue }
}

/// How the balance between fitness and fatigue reads today.
nonisolated enum TrainingForm: String, Sendable {
    case resting
    case fresh
    case steady
    case building
    case overreaching

    var title: String {
        switch self {
        case .resting: "Rested"
        case .fresh: "Fresh"
        case .steady: "Steady"
        case .building: "Building"
        case .overreaching: "Overreaching"
        }
    }

    var detail: String {
        switch self {
        case .resting:
            "You have been taking it easy for a while. Fitness fades if this holds — a hard session would land well."
        case .fresh:
            "Recovered and carrying your fitness. This is the state you want on a start line."
        case .steady:
            "Training and recovery are roughly in balance. You can keep this going indefinitely."
        case .building:
            "Fatigue is running ahead of fitness, which is how fitness is built. Worth easing off within a week or two."
        case .overreaching:
            "Fatigue is a long way ahead of fitness. This is where injury and illness tend to arrive."
        }
    }
}

/// Whether the numbers are worth believing yet.
nonisolated enum TrainingLoadConfidence: Sendable {
    /// Not enough history behind today for the averages to mean anything.
    case building(daysSoFar: Int)
    case ready

    /// Fitness is a 42-day average, so it is not honest until roughly that
    /// much history exists behind it.
    static let daysNeeded = 28
}

/// Fitness, fatigue and form from the workouts already recorded.
///
/// This is the Banister impulse-response model, the same shape used by every
/// serious training platform: each session adds a dose of stress, and the body
/// carries that stress forward in two exponential averages moving at different
/// speeds. The slow one (42 days) is fitness — adaptation that took weeks to
/// build and fades slowly. The fast one (7 days) is fatigue — cost that arrives
/// immediately and clears in days. The gap between them is form.
///
/// Nothing here is invented. Every number traces back to a workout that was
/// actually recorded, and where a session has no heart rate its stress is
/// counted by duration alone and the app says so rather than guessing an
/// intensity it cannot know.
nonisolated struct TrainingLoadModel: Sendable {
    var days: [TrainingLoadDay]
    /// Sessions counted by duration alone because they carried no heart rate.
    var sessionsWithoutHeartRate: Int
    var totalSessions: Int
    var confidence: TrainingLoadConfidence

    /// Fitness time constant, in days. Six weeks of adaptation.
    private static let fitnessConstant: Double = 42
    /// Fatigue time constant, in days. One week of recovery.
    private static let fatigueConstant: Double = 7
    /// How far back the model looks. A year is what Health hands us.
    private static let historyDays = 365

    var today: TrainingLoadDay? { days.last }

    var fitness: Double { today?.fitness ?? 0 }
    var fatigue: Double { today?.fatigue ?? 0 }
    var form: Double { today?.form ?? 0 }

    var isReady: Bool {
        if case .ready = confidence { return true }
        return false
    }

    /// Change in fitness across the last seven days.
    ///
    /// The rate of change matters more than the number: fitness climbing faster
    /// than roughly five points a week is the classic run-up to an injury,
    /// which is why this is surfaced rather than buried.
    var weeklyRamp: Double {
        guard days.count > 7 else { return 0 }
        return days[days.count - 1].fitness - days[days.count - 8].fitness
    }

    var isRampingHard: Bool { weeklyRamp > 5 }

    var state: TrainingForm {
        switch form {
        case 20...: .resting
        case 5..<20: .fresh
        case -10..<5: .steady
        case -30 ..< -10: .building
        default: .overreaching
        }
    }

    /// The last `count` days, for a chart that does not need the whole year.
    func recent(_ count: Int) -> [TrainingLoadDay] {
        guard days.count > count else { return days }
        return Array(days.suffix(count))
    }

    /// Total stress earned in the last seven days.
    var weeklyLoad: Double {
        days.suffix(7).reduce(0) { $0 + $1.load }
    }

    /// The same figure for the seven days before those, so the app can say
    /// whether this week is heavier or lighter than last.
    var previousWeeklyLoad: Double {
        guard days.count > 7 else { return 0 }
        return days.suffix(14).prefix(7).reduce(0) { $0 + $1.load }
    }

    // MARK: - Building

    /// Builds the model from a workout history.
    ///
    /// - Parameters:
    ///   - activities: every recorded and Health-imported session.
    ///   - maxHeartRate: the athlete's own maximum, from settings.
    ///   - restingHeartRate: measured resting rate, when Health has one. Without
    ///     it the reserve is estimated from the maximum, which is less precise
    ///     but never fabricated from nothing.
    static func build(
        from activities: [ActivityRecord],
        maxHeartRate: Double,
        restingHeartRate: Double
    ) -> TrainingLoadModel {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let windowStart = calendar.date(byAdding: .day, value: -(historyDays - 1), to: today) else {
            return TrainingLoadModel(
                days: [],
                sessionsWithoutHeartRate: 0,
                totalSessions: 0,
                confidence: .building(daysSoFar: 0)
            )
        }

        let considered = activities.filter { $0.startDate >= windowStart && $0.duration > 60 }

        var dailyLoad: [Date: Double] = [:]
        var withoutHeartRate = 0
        for activity in considered {
            let day = calendar.startOfDay(for: activity.startDate)
            if activity.averageHeartRate <= 0 { withoutHeartRate += 1 }
            dailyLoad[day, default: 0] += stress(
                for: activity,
                maxHeartRate: maxHeartRate,
                restingHeartRate: restingHeartRate
            )
        }

        // The averages have to run forward through every day, rest days
        // included — a day off is a real input to fatigue, not a gap to skip.
        var days: [TrainingLoadDay] = []
        days.reserveCapacity(historyDays)
        var fitness: Double = 0
        var fatigue: Double = 0
        let fitnessAlpha = 1 - exp(-1 / fitnessConstant)
        let fatigueAlpha = 1 - exp(-1 / fatigueConstant)

        for offset in 0..<historyDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: windowStart) else { continue }
            let load = dailyLoad[day] ?? 0
            fitness += (load - fitness) * fitnessAlpha
            fatigue += (load - fatigue) * fatigueAlpha
            days.append(TrainingLoadDay(date: day, load: load, fitness: fitness, fatigue: fatigue))
        }

        // Confidence comes from how long ago training actually started, not from
        // how many days the window covers — a year of empty days behind a first
        // week of running would otherwise look like a year of history.
        let firstSession = considered.map(\.startDate).min()
        let daysOfHistory: Int = firstSession
            .flatMap { calendar.dateComponents([.day], from: calendar.startOfDay(for: $0), to: today).day }
            .map { $0 + 1 } ?? 0

        return TrainingLoadModel(
            days: days,
            sessionsWithoutHeartRate: withoutHeartRate,
            totalSessions: considered.count,
            confidence: daysOfHistory >= TrainingLoadConfidence.daysNeeded
                ? .ready
                : .building(daysSoFar: daysOfHistory)
        )
    }

    /// Stress for one session.
    ///
    /// Uses Banister's TRIMP where a heart rate exists: minutes weighted by how
    /// deep into your heart-rate reserve the session sat, with an exponential
    /// term so hard minutes count for far more than easy ones — twenty minutes
    /// near maximum is genuinely more costly than an hour of jogging, and a
    /// linear weighting says otherwise.
    ///
    /// With no heart rate there is no honest way to know the intensity, so the
    /// session counts its minutes at an easy-aerobic weighting and the app
    /// reports how many sessions were counted that way.
    static func stress(
        for activity: ActivityRecord,
        maxHeartRate: Double,
        restingHeartRate: Double
    ) -> Double {
        let minutes = activity.duration / 60
        guard minutes > 0 else { return 0 }

        let ceiling = maxHeartRate > 0 ? maxHeartRate : 188
        guard activity.averageHeartRate > 0 else {
            // Counted, but at a weighting that cannot flatter the session.
            return minutes * 1.0
        }

        // Without a measured resting rate the reserve is anchored at half of
        // maximum, which is the conventional stand-in and is stated as such.
        let floor = restingHeartRate > 0 ? restingHeartRate : ceiling * 0.5
        let reserve = max(1, ceiling - floor)
        let fraction = min(1.1, max(0.05, (activity.averageHeartRate - floor) / reserve))
        return minutes * fraction * 0.64 * exp(1.92 * fraction)
    }
}
