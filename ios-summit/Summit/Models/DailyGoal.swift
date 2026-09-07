import Foundation

/// The daily targets an athlete has set for themselves.
///
/// Targets are held in the same unit the metric is stored in — steps, kcal,
/// minutes, flights, hours of sleep, kilometres, metres of ascent — so a goal
/// set in miles and read back in kilometres is still the same goal. Nothing is
/// set by default: a target nobody chose is a target nobody owns.
nonisolated struct DailyGoals: Codable, Sendable, Equatable {
    private var targets: [String: Double]

    init(targets: [String: Double] = [:]) {
        self.targets = targets
    }

    static let empty = DailyGoals()

    /// The target for a metric, or `nil` when none was set.
    func target(for metric: DashboardMetric) -> Double? {
        guard metric.supportsDailyGoal,
              let value = targets[metric.rawValue],
              value > 0 else { return nil }
        return value
    }

    func hasGoal(for metric: DashboardMetric) -> Bool { target(for: metric) != nil }

    mutating func set(_ value: Double, for metric: DashboardMetric) {
        guard metric.supportsDailyGoal else { return }
        let range = metric.goalRange
        targets[metric.rawValue] = min(max(value, range.lowerBound), range.upperBound)
    }

    mutating func clear(_ metric: DashboardMetric) {
        targets.removeValue(forKey: metric.rawValue)
    }

    /// Metrics with a goal, in the order the goals screen lists them.
    var metrics: [DashboardMetric] {
        DashboardMetric.goalCapable.filter(hasGoal(for:))
    }

    var isEmpty: Bool { metrics.isEmpty }
    var count: Int { metrics.count }
}

// MARK: - Which metrics can carry a goal
//
// Everything here is `nonisolated` because goals are resolved off the main actor
// when a dashboard is built for the watch, and none of it touches UI state.

extension DashboardMetric {
    /// Metrics a person can sensibly aim at each day.
    ///
    /// Everything here is something you do, not something that happens to you.
    /// HRV, resting heart rate and VO₂ max are deliberately absent: they are
    /// outcomes, and turning them into daily targets invites chasing a number
    /// that only moves over months, in ways training cannot direct day to day.
    nonisolated static let goalCapable: [DashboardMetric] = [
        .steps, .exercise, .calories, .distance, .elevation, .flights, .sleep,
    ]

    nonisolated var supportsDailyGoal: Bool { Self.goalCapable.contains(self) }

    /// Where a goal starts when it is first switched on — round numbers people
    /// actually say out loud, not derived from anything about this person.
    nonisolated var defaultGoalTarget: Double {
        switch self {
        case .steps: 10_000
        case .exercise: 30
        case .calories: 500
        case .distance: 5
        case .elevation: 300
        case .flights: 10
        case .sleep: 8
        default: 0
        }
    }

    /// The span a goal can be set across, in the metric's storage unit.
    nonisolated var goalRange: ClosedRange<Double> {
        switch self {
        case .steps: 1_000...40_000
        case .exercise: 5...240
        case .calories: 100...2_000
        case .distance: 0.5...80
        case .elevation: 25...3_000
        case .flights: 1...100
        case .sleep: 4...12
        default: 0...1
        }
    }

    /// One notch of the goal slider, in storage units but sized so the number
    /// the athlete reads moves in round steps in whichever units they use.
    nonisolated var goalStep: Double {
        switch self {
        case .steps: 250
        case .exercise: 5
        case .calories: 25
        case .flights: 1
        case .sleep: 0.25
        // A quarter of a kilometre, or a quarter of a mile — the stored value
        // is kilometres either way, so the step is converted rather than fixed.
        case .distance: Formatters.units.metres(fromDistance: 0.25) / 1000
        // 25 m, or 100 ft. Dividing by what one metre reads as gives the metres
        // behind a round step in the athlete's own vertical unit.
        case .elevation: (Formatters.elevationSystem == .metric ? 25 : 100)
            / max(0.001, Formatters.elevationSystem.elevation(fromMetres: 1))
        default: 1
        }
    }

    /// What a goal is counted in, for lines like "3,760 steps to go".
    nonisolated var goalNoun: String {
        switch self {
        case .steps: "steps"
        case .exercise: "min"
        case .calories: "kcal"
        case .distance: Formatters.units.distanceUnit
        case .elevation: Formatters.elevationUnit
        case .flights: "flights"
        case .sleep: "sleep"
        default: ""
        }
    }

    /// A value on the goal scale, printed as zero rather than as "--".
    ///
    /// `valueText` prints "--" for nothing, which is right on a tile with no
    /// data but wrong inside a goal: a day with no steps yet has genuinely
    /// taken zero of them, and "-- of 10,000" reads like a fault.
    nonisolated func goalValueText(_ value: Double) -> String {
        guard value > 0 else {
            switch self {
            case .sleep: return "0h 0m"
            case .distance: return String(format: "%.1f", 0)
            default: return "0"
            }
        }
        return valueText(value)
    }

    /// The goal as one line, e.g. "10,000 steps a day" or "8h 0m a night".
    nonisolated func goalSummary(_ target: Double) -> String {
        let value = valueText(target)
        switch self {
        case .sleep: return "\(value) a night"
        case .steps: return "\(value) steps a day"
        case .flights: return "\(value) flights a day"
        default:
            guard let unit = unitText else { return "\(value) a day" }
            return "\(value) \(unit) a day"
        }
    }

    /// Why this goal is worth having, shown when it is being set.
    nonisolated var goalExplainer: String {
        switch self {
        case .steps:
            "Everything you cover on foot, workouts included. The most honest measure of whether a rest day was actually restful."
        case .exercise:
            "Minutes at brisk-walk intensity or above, as Apple Health counts them. A good floor to hold on days you are not training."
        case .calories:
            "Active energy, excluding what you burn at rest. Useful if you are fuelling deliberately."
        case .distance:
            "Distance from workouts you record here and in Apple Health. Walking about the house does not count towards it."
        case .elevation:
            "Vertical gain from recorded workouts. Trail legs are built from climbing, not flat mileage."
        case .flights:
            "Flights of stairs, measured by the barometer. Everyday vertical that never shows up in a workout."
        case .sleep:
            "Time actually asleep last night. The single biggest input to how you will feel tomorrow."
        default: explainer
        }
    }
}

// MARK: - Progress

/// How today is going against one goal.
nonisolated struct GoalProgress: Sendable, Hashable, Identifiable {
    var metric: DashboardMetric
    var target: Double
    /// Today's value so far, in the metric's storage unit.
    var value: Double
    /// Days in a row this goal has been met, counting back from the last
    /// completed day. Zero when the run has been broken.
    var streak: Int = 0
    /// Days met out of the last seven.
    var daysMetThisWeek: Int = 0

    var id: String { metric.rawValue }

    var fraction: Double {
        guard target > 0 else { return 0 }
        return min(1, max(0, value / target))
    }

    /// Unclamped, so a 140% day can still be described as one.
    var rawFraction: Double {
        guard target > 0 else { return 0 }
        return max(0, value / target)
    }

    var isMet: Bool { target > 0 && value >= target }
    var remaining: Double { max(0, target - value) }

    var valueText: String { metric.goalValueText(value) }
    var targetText: String { metric.valueText(target) }

    /// "6,240 of 10,000" — the two numbers, without a unit repeated twice.
    var progressText: String { "\(valueText) of \(targetText)" }

    var percentText: String { "\(Int((rawFraction * 100).rounded()))%" }

    /// What is left, or that it is done. Sleep reads as a shortfall rather than
    /// something still to go, because you cannot go and get it now.
    var remainingText: String {
        guard !isMet else {
            return metric == .sleep ? "Slept your target" : "Goal met"
        }
        let left = metric.goalValueText(remaining)
        switch metric {
        case .sleep: return "\(left) short of target"
        case .exercise: return "\(left) min to go"
        case .steps: return "\(left) steps to go"
        case .flights: return "\(left) flights to go"
        default: return "\(left) \(metric.goalNoun) to go"
        }
    }
}

/// Resolves goals against what was actually recorded.
///
/// Every value here comes from Apple Health or a recorded workout. Where a day
/// has no data it counts as zero for progress but is never claimed as a missed
/// goal in a streak, because a watch left on charge is not a rest day.
nonisolated enum DailyGoalEngine {
    /// Today's value for a goal metric, in the unit its target is held in.
    static func todayValue(
        _ metric: DashboardMetric,
        snapshot: HealthSnapshot,
        activities: [ActivityRecord],
        now: Date = .now
    ) -> Double {
        switch metric {
        case .steps: Double(snapshot.steps)
        case .exercise: snapshot.exerciseMinutes
        case .calories: snapshot.activeCalories
        case .flights: snapshot.flightsClimbed
        // Held in hours, matching both the target and the nightly history.
        case .sleep: snapshot.sleepSeconds / 3600
        case .distance: todayTotal(activities, now: now) { $0.distance / 1000 }
        case .elevation: todayTotal(activities, now: now) { $0.elevationGain }
        default: 0
        }
    }

    /// The last seven days of this metric, oldest first, with today last.
    static func history(
        _ metric: DashboardMetric,
        snapshot: HealthSnapshot,
        activities: [ActivityRecord],
        now: Date = .now
    ) -> [Double] {
        switch metric {
        case .steps: snapshot.stepsTrend
        case .exercise: snapshot.exerciseTrend
        case .calories: snapshot.caloriesTrend
        case .flights: snapshot.flightsTrend
        // Nightly totals in hours, each attributed to the morning it ended on.
        case .sleep: snapshot.sleepTrend
        case .distance: dailyTotals(activities, now: now) { $0.distance / 1000 }
        case .elevation: dailyTotals(activities, now: now) { $0.elevationGain }
        default: []
        }
    }

    /// Every goal resolved against today, in the order the dashboard lists them.
    static func progress(
        goals: DailyGoals,
        snapshot: HealthSnapshot,
        activities: [ActivityRecord],
        now: Date = .now
    ) -> [GoalProgress] {
        goals.metrics.compactMap { metric in
            progress(for: metric, goals: goals, snapshot: snapshot, activities: activities, now: now)
        }
    }

    static func progress(
        for metric: DashboardMetric,
        goals: DailyGoals,
        snapshot: HealthSnapshot,
        activities: [ActivityRecord],
        now: Date = .now
    ) -> GoalProgress? {
        guard let target = goals.target(for: metric) else { return nil }
        let series = history(metric, snapshot: snapshot, activities: activities, now: now)
        return GoalProgress(
            metric: metric,
            target: target,
            value: todayValue(metric, snapshot: snapshot, activities: activities, now: now),
            streak: streak(series: series, target: target),
            daysMetThisWeek: series.suffix(7).filter { $0 >= target }.count
        )
    }

    /// Days in a row the target was met, reading back from the end of a series.
    ///
    /// Today is allowed not to count yet: a 10,000-step streak should not read
    /// as broken at nine in the morning. So a run that stops at yesterday is
    /// still a run, and today only ever adds to it.
    static func streak(series: [Double], target: Double) -> Int {
        guard target > 0, !series.isEmpty else { return 0 }
        var values = series
        let todayMet = (values.last ?? 0) >= target
        if !todayMet { values = values.dropLast() }

        var count = 0
        for value in values.reversed() {
            guard value >= target else { break }
            count += 1
        }
        return count
    }

    // MARK: - Activity totals

    private static func todayTotal(
        _ activities: [ActivityRecord],
        now: Date,
        value: (ActivityRecord) -> Double
    ) -> Double {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        return activities
            .filter { $0.startDate >= start && $0.startDate <= now }
            .reduce(0) { $0 + value($1) }
    }

    private static func dailyTotals(
        _ activities: [ActivityRecord],
        days: Int = 7,
        now: Date,
        value: (ActivityRecord) -> Double
    ) -> [Double] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        return (0..<days).reversed().map { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  let next = calendar.date(byAdding: .day, value: 1, to: day) else { return 0 }
            return activities
                .filter { $0.startDate >= day && $0.startDate < next }
                .reduce(0) { $0 + value($1) }
        }
    }
}
