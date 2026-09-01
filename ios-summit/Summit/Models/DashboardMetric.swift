import SwiftUI

/// Every metric that can appear as a tile on the Today dashboard.
nonisolated enum DashboardMetric: String, CaseIterable, Codable, Sendable, Identifiable, Hashable {
    case sleep
    case hrv
    case vo2Max
    case load
    case calories
    case steps
    case restingHeartRate
    case distance
    case elevation
    case pace
    case exercise
    case flights
    case respiratoryRate
    case bodyMass

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleep: "Sleep"
        case .hrv: "HRV"
        case .vo2Max: "VO₂ Max"
        case .load: "Load"
        case .calories: "Calories"
        case .steps: "Steps"
        case .restingHeartRate: "Resting HR"
        case .distance: "Distance"
        case .elevation: "Ascent"
        case .pace: "Avg Pace"
        case .exercise: "Exercise"
        case .flights: "Flights"
        case .respiratoryRate: "Breathing"
        case .bodyMass: "Weight"
        }
    }

    /// Trekka's own mark for the metric, drawn in-app.
    var glyph: TrekkaGlyph {
        switch self {
        case .sleep: .sleep
        case .hrv: .hrv
        case .vo2Max: .vo2
        case .load: .load
        case .calories: .calories
        case .steps: .steps
        case .restingHeartRate: .heart
        case .distance: .distance
        case .elevation: .elevation
        case .pace: .pace
        case .exercise: .gym
        case .flights: .elevation
        case .respiratoryRate: .hrv
        case .bodyMass: .load
        }
    }

    var symbol: String {
        switch self {
        case .sleep: "moon.zzz.fill"
        case .hrv: "waveform.path.ecg"
        case .vo2Max: "figure.run"
        case .load: "chart.bar.fill"
        case .calories: "flame.fill"
        case .steps: "shoeprints.fill"
        case .restingHeartRate: "heart.fill"
        case .distance: "point.topleft.down.to.point.bottomright.curvepath.fill"
        case .elevation: "mountain.2.fill"
        case .pace: "stopwatch.fill"
        case .exercise: "figure.mixed.cardio"
        case .flights: "figure.stairs"
        case .respiratoryRate: "lungs.fill"
        case .bodyMass: "scalemass.fill"
        }
    }

    var tint: Color {
        switch self {
        case .sleep: Color(red: 0.55, green: 0.45, blue: 0.95)
        case .hrv: Theme.zoneColors[1]
        case .vo2Max: Theme.accent
        case .load: Theme.highlight
        case .calories: Theme.zoneColors[3]
        case .steps: Theme.zoneColors[1]
        case .restingHeartRate: Theme.danger
        case .distance: Theme.zoneColors[0]
        case .elevation: Theme.accent
        case .pace: Theme.highlight
        case .exercise: Theme.zoneColors[2]
        case .flights: Theme.zoneColors[0]
        case .respiratoryRate: Theme.zoneColors[1]
        case .bodyMass: Theme.textPrimary.opacity(0.8)
        }
    }

    /// What window the headline number covers.
    var periodLabel: String {
        switch self {
        case .sleep: "Last night"
        case .hrv: "7-day average"
        case .vo2Max: "Latest reading"
        case .load: "Rolling 7 days"
        case .calories, .steps: "Today"
        case .restingHeartRate: "7-day average"
        case .distance, .elevation, .pace: "This week"
        case .exercise, .flights: "Today"
        case .respiratoryRate: "7-day average"
        case .bodyMass: "Latest reading"
        }
    }

    /// Whether a day of this metric means a night rather than a calendar day.
    ///
    /// Sleep is the only one: its 24-hour axis opens at 18:00 the evening before,
    /// so the hours before midnight are counted instead of discarded.
    var usesNightAxis: Bool { self == .sleep }

    /// Metrics whose history is rebuilt from recorded workouts rather than Health day totals.
    var usesActivityHistory: Bool {
        switch self {
        case .distance, .elevation, .load, .pace: true
        default: false
        }
    }

    /// Volume metrics add up across a bucket; rate metrics average instead.
    var isCumulative: Bool {
        switch self {
        case .calories, .steps, .distance, .elevation, .load, .exercise, .flights: true
        case .sleep, .hrv, .vo2Max, .restingHeartRate, .pace, .respiratoryRate, .bodyMass: false
        }
    }

    /// How samples collapse into a bucket or headline for a given range.
    func aggregation(for range: MetricRange) -> MetricAggregation {
        if isCumulative { return .sum }
        // A day of sleep is the total of the night's hours, not their average.
        if self == .sleep, range == .day { return .sum }
        return .average
    }

    /// Label above the headline number for a range, e.g. "7-day total".
    func headlineCaption(for range: MetricRange) -> String {
        // A day of sleep is a night, and saying "Today" for it invited the
        // reading that only the hours since midnight were counted.
        if usesNightAxis, range == .day { return "Last night" }
        switch (aggregation(for: range), range) {
        case (.sum, .day): return "Today"
        case (.sum, _): return "\(range.summaryLabel) total"
        case (.average, .day): return "Today"
        case (.average, _): return "\(range.summaryLabel) average"
        }
    }

    /// Label above the headline number for any window, preset or hand-picked.
    func headlineCaption(for window: MetricWindow) -> String {
        guard let span = window.span else { return headlineCaption(for: window.range) }
        guard !span.isSingleDay else {
            guard usesNightAxis else { return span.dayTitle }
            return Calendar.current.isDateInToday(span.end) ? "Last night" : "Night to \(span.dayTitle)"
        }
        let noun = aggregation(for: window.range) == .sum ? "total" : "average"
        return "\(span.dayCount)-day \(noun)"
    }

    /// The headline number split into a value and its unit.
    func valueText(_ value: Double) -> String {
        guard value > 0 else { return self == .pace ? "--:--" : "--" }
        switch self {
        case .sleep:
            let hours = Int(value)
            let minutes = Int((value - Double(hours)) * 60)
            return "\(hours)h \(minutes)m"
        case .hrv, .load, .restingHeartRate: return Formatters.integer(value)
        case .vo2Max: return String(format: "%.1f", value)
        case .calories: return Formatters.integer(value)
        case .steps: return Int(value.rounded()).formatted(.number)
        // Distance is carried in kilometres and weight in kilograms, because
        // that is what the sources hand over. Both are converted here rather
        // than printed raw under an imperial label.
        case .distance: return String(format: "%.1f", Formatters.units.distance(fromMetres: value * 1000))
        case .elevation: return Formatters.elevation(value)
        case .pace: return Formatters.pace(value)
        case .exercise, .flights: return Formatters.integer(value)
        case .respiratoryRate: return String(format: "%.1f", value)
        case .bodyMass: return String(format: "%.1f", Formatters.units.mass(fromKilograms: value))
        }
    }

    /// The label under the headline number, in the athlete's chosen system.
    var unitText: String? {
        switch self {
        case .hrv: "ms"
        case .restingHeartRate: "bpm"
        case .calories: "kcal"
        case .distance: Formatters.units.distanceUnit
        case .elevation: Formatters.units.elevationUnit
        case .pace: Formatters.units.paceUnit
        case .exercise: "min"
        case .respiratoryRate: "br/min"
        case .bodyMass: Formatters.units.massUnit
        case .sleep, .vo2Max, .load, .steps, .flights: nil
        }
    }

    /// Whether the drill-down should list the workouts that produced the number.
    var isActivityDerived: Bool {
        switch self {
        case .load, .calories, .distance, .elevation, .pace: true
        default: false
        }
    }

    var explainer: String {
        switch self {
        case .sleep:
            "Total time asleep across core, deep and REM stages. Sleep is the single biggest input to your readiness score — consistent 7½ to 8½ hour nights keep adaptation ahead of fatigue."
        case .hrv:
            "Heart rate variability is the beat-to-beat variation measured overnight. Higher than your own baseline usually means your nervous system has recovered; a sustained drop is an early warning of illness, stress or overreaching."
        case .vo2Max:
            "An estimate of how much oxygen you can use per kilogram of body weight per minute. It moves slowly — think months, not days — and is the clearest single number for aerobic fitness."
        case .load:
            "Duration weighted by intensity across the last seven days. Staying inside your optimal band builds fitness; spiking above it is where injuries and stagnation usually start."
        case .calories:
            "Active energy burned today, excluding your resting metabolism. Useful for fuelling decisions on big mountain days."
        case .steps:
            "Everything you covered on foot today, including time outside of tracked workouts. A good proxy for how much your legs actually rested."
        case .restingHeartRate:
            "Your lowest sustained heart rate, usually recorded during sleep. A rise of five or more beats above your normal often shows up a day before you feel run down."
        case .distance:
            "Total distance from every workout recorded in the last seven days, in-app and from Apple Health."
        case .elevation:
            "Cumulative vertical gain over the last seven days. Vertical is the load that trail legs are actually built from — flat mileage is not the same stimulus."
        case .pace:
            "Distance-weighted average pace over the last seven days. It blends easy and hard efforts, so read it alongside your zone distribution rather than on its own."
        case .exercise:
            "Minutes today at brisk-walk intensity or above, as Apple Health counts them. A useful floor to hold on rest days, when the temptation is to do nothing at all."
        case .flights:
            "Flights of stairs climbed today, measured by barometer rather than estimated from steps. Everyday vertical that never shows up in a tracked workout still loads the same legs."
        case .respiratoryRate:
            "Breaths per minute measured while you sleep. It is stable night to night, so a sustained rise of a breath or two is one of the earliest signals of illness or a hard day not yet absorbed."
        case .bodyMass:
            "Your most recent recorded weight. Trekka only reads what you or your scales have written to Health — it never estimates."
        }
    }

    /// Formats a single series sample for chart axes and tooltips.
    func seriesLabel(_ value: Double) -> String {
        switch self {
        case .sleep: String(format: "%.1fh", value)
        case .hrv: "\(Int(value.rounded())) ms"
        case .vo2Max: String(format: "%.1f", value)
        case .load: "\(Int(value.rounded()))"
        case .calories: "\(Int(value.rounded())) kcal"
        case .steps: Int(value.rounded()).formatted(.number)
        case .restingHeartRate: "\(Int(value.rounded())) bpm"
        case .distance:
            String(format: "%.1f %@", Formatters.units.distance(fromMetres: value * 1000), Formatters.units.distanceUnit)
        case .elevation: "\(Formatters.elevation(value)) \(Formatters.units.elevationUnit)"
        case .pace: Formatters.pace(value)
        case .exercise: "\(Int(value.rounded())) min"
        case .flights: "\(Int(value.rounded())) flights"
        case .respiratoryRate: String(format: "%.1f br/min", value)
        case .bodyMass:
            String(format: "%.1f %@", Formatters.units.mass(fromKilograms: value), Formatters.units.massUnit)
        }
    }
}

/// A metric resolved against the current snapshot: headline value, history and coaching line.
nonisolated struct MetricReading: Sendable, Identifiable {
    var metric: DashboardMetric
    var value: Double
    var displayValue: String
    var unit: String?
    var suffix: String?
    /// Seven daily samples, oldest first.
    var series: [Double]
    var insight: String

    var id: String { metric.rawValue }

    var populatedSeries: [Double] { series.filter { $0 > 0 } }

    var average: Double {
        let values = populatedSeries
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    var best: Double { populatedSeries.max() ?? 0 }
    var low: Double { populatedSeries.min() ?? 0 }

    /// True when the latest sample moved up versus the previous one.
    var deltaUp: Bool? {
        guard series.count > 1, let last = series.last, let previous = series.dropLast().last else { return nil }
        guard abs(last - previous) > 0.0001 else { return nil }
        return last > previous
    }
}

/// Builds every dashboard reading from a health snapshot plus recorded activities.
nonisolated enum MetricReadings {
    static func build(
        snapshot: HealthSnapshot,
        activities: [ActivityRecord],
        reference: Date = Date()
    ) -> [DashboardMetric: MetricReading] {
        let distanceSeries = dailyTotals(activities, reference: reference) { $0.distance / 1000 }
        let elevationSeries = dailyTotals(activities, reference: reference) { $0.elevationGain }
        let durationSeries = dailyTotals(activities, reference: reference) { $0.duration }
        let paceSeries = zip(durationSeries, distanceSeries).map { duration, km in
            km > 0.05 ? duration / km : 0
        }

        let weekDistance = distanceSeries.reduce(0, +)
        let weekDuration = durationSeries.reduce(0, +)
        let weekPace = weekDistance > 0.05 ? weekDuration / weekDistance : 0

        var readings: [DashboardMetric: MetricReading] = [:]

        readings[.sleep] = MetricReading(
            metric: .sleep,
            value: snapshot.sleepSeconds / 3600,
            displayValue: snapshot.sleepText,
            unit: nil,
            suffix: snapshot.sleepScore > 0 ? " · \(snapshot.sleepScore)" : nil,
            series: snapshot.sleepTrend,
            insight: sleepInsight(hours: snapshot.sleepSeconds / 3600, score: snapshot.sleepScore)
        )

        readings[.hrv] = MetricReading(
            metric: .hrv,
            value: snapshot.hrv,
            displayValue: Formatters.integer(snapshot.hrv),
            unit: "ms",
            suffix: nil,
            series: snapshot.hrvTrend,
            insight: hrvInsight(value: snapshot.hrv, baseline: snapshot.hrvBaseline)
        )

        readings[.vo2Max] = MetricReading(
            metric: .vo2Max,
            value: snapshot.vo2Max,
            displayValue: snapshot.vo2Max > 0 ? String(format: "%.1f", snapshot.vo2Max) : "--",
            unit: nil,
            suffix: nil,
            series: snapshot.vo2Trend,
            insight: driftInsight(series: snapshot.vo2Trend, unit: "points", positiveIsGood: true)
        )

        readings[.load] = MetricReading(
            metric: .load,
            value: Double(snapshot.trainingLoad),
            displayValue: "\(snapshot.trainingLoad)",
            unit: nil,
            suffix: nil,
            series: snapshot.loadTrend,
            insight: loadInsight(load: snapshot.trainingLoad)
        )

        readings[.calories] = MetricReading(
            metric: .calories,
            value: snapshot.activeCalories,
            displayValue: Formatters.integer(snapshot.activeCalories),
            unit: "kcal",
            suffix: nil,
            series: snapshot.caloriesTrend,
            insight: versusAverageInsight(value: snapshot.activeCalories, series: snapshot.caloriesTrend, noun: "burn")
        )

        readings[.steps] = MetricReading(
            metric: .steps,
            value: Double(snapshot.steps),
            displayValue: snapshot.steps.formatted(.number),
            unit: nil,
            suffix: nil,
            series: snapshot.stepsTrend,
            insight: versusAverageInsight(value: Double(snapshot.steps), series: snapshot.stepsTrend, noun: "step count")
        )

        readings[.restingHeartRate] = MetricReading(
            metric: .restingHeartRate,
            value: snapshot.restingHeartRate,
            displayValue: snapshot.restingHeartRate > 0 ? Formatters.integer(snapshot.restingHeartRate) : "--",
            unit: "bpm",
            suffix: nil,
            series: snapshot.restingTrend,
            insight: restingInsight(value: snapshot.restingHeartRate, series: snapshot.restingTrend)
        )

        readings[.distance] = MetricReading(
            metric: .distance,
            value: weekDistance,
            displayValue: String(format: "%.1f", Formatters.units.distance(fromMetres: weekDistance * 1000)),
            unit: Formatters.units.distanceUnit,
            suffix: nil,
            series: distanceSeries,
            insight: weekVolumeInsight(distanceKm: weekDistance, days: distanceSeries.filter { $0 > 0 }.count)
        )

        readings[.elevation] = MetricReading(
            metric: .elevation,
            value: elevationSeries.reduce(0, +),
            displayValue: Formatters.elevation(elevationSeries.reduce(0, +)),
            unit: Formatters.units.elevationUnit,
            suffix: nil,
            series: elevationSeries,
            insight: elevationInsight(metres: elevationSeries.reduce(0, +), distanceKm: weekDistance)
        )

        readings[.pace] = MetricReading(
            metric: .pace,
            value: weekPace,
            displayValue: weekPace > 0 ? Formatters.pace(weekPace) : "--:--",
            unit: Formatters.units.paceUnit,
            suffix: nil,
            series: paceSeries,
            insight: paceInsight(secondsPerKm: weekPace)
        )

        readings[.exercise] = MetricReading(
            metric: .exercise,
            value: snapshot.exerciseMinutes,
            displayValue: snapshot.exerciseMinutes > 0 ? Formatters.integer(snapshot.exerciseMinutes) : "--",
            unit: "min",
            suffix: nil,
            series: snapshot.exerciseTrend,
            insight: versusAverageInsight(
                value: snapshot.exerciseMinutes,
                series: snapshot.exerciseTrend,
                noun: "exercise time"
            )
        )

        readings[.flights] = MetricReading(
            metric: .flights,
            value: snapshot.flightsClimbed,
            displayValue: snapshot.flightsClimbed > 0 ? Formatters.integer(snapshot.flightsClimbed) : "--",
            unit: nil,
            suffix: nil,
            series: snapshot.flightsTrend,
            insight: versusAverageInsight(
                value: snapshot.flightsClimbed,
                series: snapshot.flightsTrend,
                noun: "stair count"
            )
        )

        readings[.respiratoryRate] = MetricReading(
            metric: .respiratoryRate,
            value: snapshot.respiratoryRate,
            displayValue: snapshot.respiratoryRate > 0 ? String(format: "%.1f", snapshot.respiratoryRate) : "--",
            unit: "br/min",
            suffix: nil,
            series: snapshot.respiratoryTrend,
            insight: respiratoryInsight(value: snapshot.respiratoryRate, series: snapshot.respiratoryTrend)
        )

        readings[.bodyMass] = MetricReading(
            metric: .bodyMass,
            value: snapshot.bodyMass,
            displayValue: snapshot.bodyMass > 0
                ? String(format: "%.1f", Formatters.units.mass(fromKilograms: snapshot.bodyMass))
                : "--",
            unit: Formatters.units.massUnit,
            suffix: nil,
            series: snapshot.bodyMassTrend,
            insight: driftInsight(
                series: snapshot.bodyMassTrend.map { Formatters.units.mass(fromKilograms: $0) },
                unit: Formatters.units.massUnit,
                positiveIsGood: false
            )
        )

        return readings
    }

    private static func dailyTotals(
        _ activities: [ActivityRecord],
        days: Int = 7,
        reference: Date,
        value: (ActivityRecord) -> Double
    ) -> [Double] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: reference)
        return (0..<days).reversed().map { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  let next = calendar.date(byAdding: .day, value: 1, to: day) else { return 0 }
            return activities
                .filter { $0.startDate >= day && $0.startDate < next }
                .reduce(0) { $0 + value($1) }
        }
    }

    /// Activities from the last seven days that feed an activity-derived metric.
    static func contributingActivities(_ activities: [ActivityRecord], reference: Date = Date()) -> [ActivityRecord] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Calendar.current.startOfDay(for: reference)) ?? reference
        return activities
            .filter { $0.startDate >= cutoff }
            .sorted { $0.startDate > $1.startDate }
    }

    // MARK: - Insights

    private static func sleepInsight(hours: Double, score: Int) -> String {
        guard hours > 0 else { return "No sleep recorded for last night." }
        switch hours {
        case 8...: return "A full night — recovery systems had all the time they needed."
        case 7..<8: return "Solid night. Quality score \(score) means most of it counted."
        case 6..<7: return "Just under target. Expect a slightly flatter top-end today."
        default: return "Short night. Keep the session aerobic and bank sleep tonight."
        }
    }

    private static func hrvInsight(value: Double, baseline: Double) -> String {
        guard value > 0 else { return "No overnight HRV recorded yet." }
        guard baseline > 0 else { return "Building your personal baseline — a few more nights needed." }
        let delta = (value - baseline) / baseline * 100
        if delta > 8 { return String(format: "%.0f%% above your 30-day baseline — you are absorbing training well.", delta) }
        if delta < -8 { return String(format: "%.0f%% below your 30-day baseline — favour volume over intensity.", abs(delta)) }
        return "Sitting on your 30-day baseline. Normal recovery state."
    }

    private static func driftInsight(series: [Double], unit: String, positiveIsGood: Bool) -> String {
        let values = series.filter { $0 > 0 }
        guard let first = values.first, let last = values.last, values.count > 1 else {
            return "Not enough history yet to show a trend."
        }
        let delta = last - first
        guard abs(delta) > 0.05 else { return "Holding steady across the last week." }
        let direction = delta > 0 ? "up" : "down"
        return String(format: "%@ %.1f %@ over the last week.", direction.capitalized, abs(delta), unit)
    }

    private static func loadInsight(load: Int) -> String {
        switch load {
        case 0: return "No training load recorded in the last seven days."
        case 1..<300: return "Below your optimal band — there is room to add a quality session."
        case 300..<600: return "Inside the optimal band. Keep the rhythm you are on."
        case 600..<800: return "High but productive. Protect the next easy day."
        default: return "Well above the optimal band — schedule recovery before the next hard effort."
        }
    }

    private static func versusAverageInsight(value: Double, series: [Double], noun: String) -> String {
        let values = series.dropLast().filter { $0 > 0 }
        guard !values.isEmpty, value > 0 else { return "No data recorded for today yet." }
        let average = values.reduce(0, +) / Double(values.count)
        guard average > 0 else { return "No comparison data yet." }
        let delta = (value - average) / average * 100
        if abs(delta) < 8 { return "Right on your weekly \(noun) average." }
        return String(format: "%.0f%% %@ your weekly %@ average.", abs(delta), delta > 0 ? "above" : "below", noun)
    }

    private static func restingInsight(value: Double, series: [Double]) -> String {
        let values = series.filter { $0 > 0 }
        guard value > 0, values.count > 1 else { return "Not enough resting heart rate history yet." }
        let average = values.reduce(0, +) / Double(values.count)
        let delta = value - average
        if delta > 4 { return String(format: "%.0f bpm above your weekly norm — a classic early fatigue signal.", delta) }
        if delta < -3 { return String(format: "%.0f bpm below your weekly norm — strong recovery signal.", abs(delta)) }
        return "In line with your weekly norm."
    }

    /// Breathing is stable night to night, so the useful reading is the size of
    /// the departure from your own norm rather than the number itself.
    private static func respiratoryInsight(value: Double, series: [Double]) -> String {
        let values = series.filter { $0 > 0 }
        guard value > 0, values.count > 1 else { return "Not enough overnight breathing history yet." }
        let average = values.reduce(0, +) / Double(values.count)
        guard average > 0 else { return "No comparison data yet." }
        let delta = value - average
        if delta > 1 {
            return String(format: "%.1f breaths above your weekly norm — often the first sign of illness.", delta)
        }
        if delta < -1 {
            return String(format: "%.1f breaths below your weekly norm.", abs(delta))
        }
        return "In line with your weekly norm."
    }

    private static func weekVolumeInsight(distanceKm: Double, days: Int) -> String {
        guard distanceKm > 0 else { return "No distance recorded in the last seven days." }
        let units = Formatters.units
        return String(
            format: "%.1f %@ across %d active %@.",
            units.distance(fromMetres: distanceKm * 1000),
            units.distanceUnit,
            days,
            days == 1 ? "day" : "days"
        )
    }

    /// Vertical per unit of distance, spoken in whichever pair the athlete uses
    /// — metres per kilometre or feet per mile. The judgement thresholds stay in
    /// metric so the same week reads the same way in either system.
    private static func elevationInsight(metres: Double, distanceKm: Double) -> String {
        guard metres > 0 else { return "No vertical gain recorded in the last seven days." }
        let units = Formatters.units
        guard distanceKm > 0.5 else {
            return "\(Formatters.elevation(metres)) \(units.elevationUnit) of climbing this week."
        }
        let perKm = metres / distanceKm
        let character = perKm > 40 ? "genuinely mountainous" : perKm > 20 ? "rolling" : "mostly flat"
        let shown = units == .metric ? perKm : units.elevation(fromMetres: metres) / units.distance(fromMetres: distanceKm * 1000)
        return String(format: "%.0f %@ — a %@ week.", shown, units.perDistanceUnit, character)
    }

    private static func paceInsight(secondsPerKm: Double) -> String {
        guard secondsPerKm > 0 else { return "No pace data in the last seven days." }
        return "Blended across every workout this week, easy days included."
    }
}
