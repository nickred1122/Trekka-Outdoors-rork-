import Foundation

/// The window a dashboard chart covers.
nonisolated enum MetricRange: String, CaseIterable, Codable, Sendable, Identifiable {
    case day
    case week
    case month
    case quarter
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        case .quarter: "Quarter"
        case .year: "Year"
        }
    }

    /// Compact label used inside the segmented selector.
    var shortTitle: String {
        switch self {
        case .day: "D"
        case .week: "W"
        case .month: "M"
        case .quarter: "Q"
        case .year: "Y"
        }
    }

    var caption: String {
        switch self {
        case .day: "Today, by hour"
        case .week: "Last 7 days"
        case .month: "Last 30 days"
        case .quarter: "Last 13 weeks"
        case .year: "Last 12 months"
        }
    }

    /// Prefix for summary statistics, e.g. "7-day avg".
    var summaryLabel: String {
        switch self {
        case .day: "Today"
        case .week: "7-day"
        case .month: "30-day"
        case .quarter: "13-week"
        case .year: "12-month"
        }
    }

    var bucketNoun: String {
        switch self {
        case .day: "hour"
        case .week, .month: "day"
        case .quarter: "week"
        case .year: "month"
        }
    }

    /// How many calendar days the range reaches back.
    var dayCount: Int {
        switch self {
        case .day: 1
        case .week: 7
        case .month: 30
        case .quarter: 91
        case .year: 365
        }
    }

    /// Show one axis label every `axisStride` buckets so labels never collide.
    var axisStride: Int {
        switch self {
        case .day: 6
        case .week: 1
        case .month: 5
        case .quarter: 3
        case .year: 2
        }
    }

    /// The least history this range needs before it can say anything true.
    ///
    /// A twelve-month average built from four days of data is a lie dressed up
    /// as a trend, so a range stays hidden until there is enough behind it.
    var minimumDaysOfData: Int {
        switch self {
        case .day: 1
        case .week: 2
        case .month: 9
        case .quarter: 32
        case .year: 95
        }
    }

    /// The ranges worth offering for a history this long.
    static func available(forDays days: Int) -> [MetricRange] {
        let usable = allCases.filter { days >= $0.minimumDaysOfData }
        return usable.isEmpty ? [.day] : usable
    }

    /// The widest available range at or below this one, for when a metric with
    /// less history is opened while a longer range is selected.
    func clamped(to available: [MetricRange]) -> MetricRange {
        guard !available.contains(self) else { return self }
        return available.last ?? .day
    }
}

/// How finely a chart chops up the days it covers.
///
/// A rolling preset picks this for you — a week is drawn by day, a year by month.
/// A hand-picked range has no such convention, so the choice is offered instead of
/// assumed: the same eight weeks can be read day by day for detail or week by week
/// for shape.
nonisolated enum MetricBucket: String, CaseIterable, Codable, Sendable, Identifiable {
    case hour
    case day
    case week
    case month
    case quarter
    case year

    var id: String { rawValue }

    /// Days per bucket. Zero means sub-daily.
    var days: Int {
        switch self {
        case .hour: 0
        case .day: 1
        case .week: 7
        case .month: 30
        case .quarter: 91
        case .year: 365
        }
    }

    var title: String {
        switch self {
        case .hour: "Hourly"
        case .day: "Daily"
        case .week: "Weekly"
        case .month: "Monthly"
        case .quarter: "Quarterly"
        case .year: "Yearly"
        }
    }

    /// Compact label used inside the segmented selector.
    var shortTitle: String {
        switch self {
        case .hour: "H"
        case .day: "D"
        case .week: "W"
        case .month: "M"
        case .quarter: "Q"
        case .year: "Y"
        }
    }

    var noun: String { rawValue }

    /// How many bars this granularity produces across a span.
    func bucketCount(forDays days: Int) -> Int {
        guard self.days > 0 else { return days * 24 }
        return Int((Double(days) / Double(self.days)).rounded(.up))
    }

    /// The granularities worth offering for a span this long.
    ///
    /// A bucket has to produce at least two bars to be a chart at all, and few
    /// enough that the chart still resolves them. Hourly is offered for a single
    /// day only, because hour-level history is read one day at a time.
    ///
    /// The ceiling is deliberately loose enough that a full year still offers
    /// Daily — dense, but the line rendering reads it fine, and the alternative
    /// was silently taking the choice away.
    static func available(forDays days: Int) -> [MetricBucket] {
        guard days > 1 else { return [.hour] }
        return allCases.filter { bucket in
            guard bucket != .hour else { return false }
            let count = bucket.bucketCount(forDays: days)
            return count >= 2 && count <= 400
        }
    }

    /// The granularity a span gets when nothing has been chosen by hand, matching
    /// the conventions the rolling presets already use.
    static func automatic(forDays days: Int) -> MetricBucket {
        switch days {
        case ...1: .hour
        case 2...92: .day
        case 93...366: .week
        case 367...1_100: .month
        default: .quarter
        }
    }
}

/// A day-granular span of dates chosen by hand, rather than a rolling preset.
nonisolated struct MetricSpan: Codable, Sendable, Equatable, Hashable {
    /// Start of the first day covered, inclusive.
    var start: Date
    /// Start of the last day covered, inclusive.
    var end: Date
    /// Granularity chosen by hand. Nil leaves it to `MetricBucket.automatic`.
    var bucket: MetricBucket?

    init(start: Date, end: Date, bucket: MetricBucket? = nil, calendar: Calendar = .current) {
        self.start = calendar.startOfDay(for: min(start, end))
        self.end = calendar.startOfDay(for: max(start, end))
        self.bucket = bucket
    }

    /// Granularities this span is long enough to support.
    var availableBuckets: [MetricBucket] { MetricBucket.available(forDays: dayCount) }

    /// The granularity actually plotted: the chosen one when it still fits the
    /// span, otherwise the automatic choice. Shortening a range therefore never
    /// leaves a chart drawn at a granularity it can no longer support.
    var resolvedBucket: MetricBucket {
        let available = availableBuckets
        if let bucket, available.contains(bucket) { return bucket }
        let automatic = MetricBucket.automatic(forDays: dayCount)
        if available.contains(automatic) { return automatic }
        return available.first ?? .day
    }

    /// One day counts as one, so picking a single date never reads as zero days.
    var dayCount: Int {
        let days = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
        return max(1, days + 1)
    }

    var isSingleDay: Bool { dayCount == 1 }

    /// "Today", "Yesterday", else "Sat 4 Mar".
    var dayTitle: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(end) { return "Today" }
        if calendar.isDateInYesterday(end) { return "Yesterday" }
        return end.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    var title: String {
        guard !isSingleDay else { return dayTitle }
        let from = start.formatted(.dateTime.day().month(.abbreviated))
        let to = end.formatted(.dateTime.day().month(.abbreviated))
        return "\(from) – \(to)"
    }

    var subtitle: String {
        isSingleDay ? "One day, by hour" : "\(dayCount) days, by \(resolvedBucket.noun)"
    }
}

/// What a chart is scoped to: a rolling preset ending on a chosen day, or an
/// explicit span of dates the user picked.
nonisolated enum MetricWindow: Sendable, Equatable, Hashable {
    case preset(MetricRange, anchor: Date)
    case span(MetricSpan)

    var span: MetricSpan? {
        guard case .span(let span) = self else { return nil }
        return span
    }

    /// The preset whose wording and aggregation fit this window, so a hand-picked
    /// span still says "total" or "average" in the right places.
    var range: MetricRange {
        switch self {
        case .preset(let range, _):
            return range
        case .span(let span):
            switch span.dayCount {
            case 1: return .day
            case 2...10: return .week
            case 11...45: return .month
            case 46...180: return .quarter
            default: return .year
            }
        }
    }

    var dayCount: Int {
        switch self {
        case .preset(let range, _): range.dayCount
        case .span(let span): span.dayCount
        }
    }

    /// The last day covered.
    var endDay: Date {
        switch self {
        case .preset(_, let anchor): Calendar.current.startOfDay(for: anchor)
        case .span(let span): span.end
        }
    }

    var isToday: Bool { Calendar.current.isDateInToday(endDay) }

    /// Today runs up to this minute; a past day is read in full.
    var reference: Date {
        guard !isToday else { return Date() }
        return Calendar.current.date(byAdding: .hour, value: 23, to: endDay) ?? endDay
    }

    /// The day whose hourly breakdown this window needs, if it needs one at all.
    var hourlyDay: Date? {
        switch self {
        case .preset(let range, _): range == .day ? endDay : nil
        case .span(let span): span.isSingleDay ? span.start : nil
        }
    }

    var bucketNoun: String {
        switch self {
        case .preset(let range, _):
            return range.bucketNoun
        case .span(let span):
            return span.resolvedBucket.noun
        }
    }

    /// Prefix for summary statistics, e.g. "7-day avg" or "15-day avg".
    var summaryLabel: String {
        switch self {
        case .preset(let range, _): range.summaryLabel
        case .span(let span): span.isSingleDay ? "Day" : "\(span.dayCount)-day"
        }
    }

    /// "Today", "Yesterday", else the dated weekday of the last day covered.
    var dayLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(endDay) { return "Today" }
        if calendar.isDateInYesterday(endDay) { return "Yesterday" }
        return endDay.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// Plain description of exactly what is plotted.
    var caption: String {
        switch self {
        case .preset(let range, _):
            guard !isToday else { return range.caption }
            if range == .day { return "\(dayLabel), by hour" }
            return "\(range.caption) to \(endDay.formatted(.dateTime.day().month(.abbreviated)))"
        case .span(let span):
            guard !span.isSingleDay else { return "\(span.dayTitle), by hour" }
            return "\(span.title) · \(span.dayCount) days, by \(span.resolvedBucket.noun)"
        }
    }

    /// The days this window covers, used to pick out the workouts behind it.
    var dateInterval: DateInterval {
        let calendar = Calendar.current
        let exclusiveEnd = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
        switch self {
        case .preset(let range, _):
            let start = calendar.date(byAdding: .day, value: -(range.dayCount - 1), to: endDay) ?? endDay
            return DateInterval(start: start, end: exclusiveEnd)
        case .span(let span):
            return DateInterval(start: span.start, end: exclusiveEnd)
        }
    }

    /// One axis label every N buckets so labels never collide.
    func axisStride(bucketCount: Int) -> Int {
        switch self {
        case .preset(let range, _): max(1, range.axisStride)
        case .span: max(1, Int((Double(bucketCount) / 7).rounded(.up)))
        }
    }
}

/// How several samples collapse into one bucket or one headline number.
nonisolated enum MetricAggregation: Sendable {
    case sum
    case average
}

/// One plotted bucket of a metric series.
nonisolated struct MetricSample: Identifiable, Sendable, Equatable {
    var index: Int
    var start: Date
    /// Short axis label, e.g. "Mon" or "Mar".
    var label: String
    /// Long label used in the scrub read-out, e.g. "Mon 4 Mar".
    var title: String
    var value: Double
    /// True for the bucket that contains right now.
    var isCurrent: Bool

    var id: Int { index }
}

/// Long-window history read from Apple Health, used by every range above a week.
nonisolated struct MetricHistory: Sendable, Equatable {
    /// Hourly values for the current day, index 0 = midnight.
    var hourly: [DashboardMetric: [Double]]
    /// Daily values, oldest first; the final entry is today.
    var daily: [DashboardMetric: [Double]]

    static let empty = MetricHistory(hourly: [:], daily: [:])

    func hourlyValues(_ metric: DashboardMetric) -> [Double] { hourly[metric] ?? [] }
    func dailyValues(_ metric: DashboardMetric) -> [Double] { daily[metric] ?? [] }

    var hasData: Bool {
        daily.values.contains { values in values.contains { $0 > 0 } }
    }
}

/// Buckets health history and recorded activities into a chartable series for any range.
nonisolated enum MetricSeries {
    /// Three years, so the wider granularities are real choices rather than
    /// single-bar charts: a quarterly or yearly view needs more than one year of
    /// history behind it to plot anything.
    static let historyDayCount = 1_095

    /// How many days of real history a metric actually has, counted from its
    /// earliest recorded value to the reference day.
    ///
    /// This is what decides which ranges the selector offers, so a brand-new
    /// account is never invited to read a year-long trend that does not exist.
    static func coverageDays(
        metric: DashboardMetric,
        history: MetricHistory,
        activities: [ActivityRecord],
        reference: Date = Date()
    ) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: reference)

        if metric.usesActivityHistory {
            let dates = activities.compactMap { activity -> Date? in
                switch metric {
                case .distance where activity.distance > 0: activity.startDate
                case .elevation where activity.elevationGain > 0: activity.startDate
                case .pace where activity.distance > 50: activity.startDate
                case .load where activity.duration > 0: activity.startDate
                default: nil
                }
            }
            guard let earliest = dates.min() else { return 0 }
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: earliest), to: today).day ?? 0
            return max(1, days + 1)
        }

        let daily = history.dailyValues(metric)
        guard let firstPopulated = daily.firstIndex(where: { $0 > 0 }) else { return 0 }
        return daily.count - firstPopulated
    }

    /// The deepest history any of these metrics has, used by the dashboard where
    /// one selector governs several tiles at once.
    static func coverageDays(
        metrics: [DashboardMetric],
        history: MetricHistory,
        activities: [ActivityRecord],
        reference: Date = Date()
    ) -> Int {
        metrics
            .map { coverageDays(metric: $0, history: history, activities: activities, reference: reference) }
            .max() ?? 0
    }

    /// Days per bucket for a hand-picked span — the granularity chosen on the
    /// window bar, or the automatic one when none was.
    static func bucketDays(for span: MetricSpan) -> Int {
        span.resolvedBucket.days
    }

    /// Samples for any window, preset or hand-picked.
    static func samples(
        metric: DashboardMetric,
        window: MetricWindow,
        history: MetricHistory,
        activities: [ActivityRecord]
    ) -> [MetricSample] {
        let calendar = Calendar.current
        switch window {
        case .preset(let range, _):
            return samples(
                metric: metric,
                range: range,
                history: history,
                activities: activities,
                reference: window.reference
            )
        case .span(let span):
            let bucket = bucketDays(for: span)
            guard bucket > 0 else {
                return hourlySamples(
                    metric: metric,
                    history: history,
                    activities: activities,
                    reference: window.reference,
                    calendar: calendar
                )
            }
            return spanSamples(
                metric: metric,
                span: span,
                bucketDays: bucket,
                history: history,
                activities: activities,
                reference: window.reference,
                calendar: calendar
            )
        }
    }

    static func samples(
        metric: DashboardMetric,
        range: MetricRange,
        history: MetricHistory,
        activities: [ActivityRecord],
        reference: Date = Date()
    ) -> [MetricSample] {
        let calendar = Calendar.current
        switch range {
        case .day:
            return hourlySamples(metric: metric, history: history, activities: activities, reference: reference, calendar: calendar)
        case .week, .month:
            return daySamples(
                metric: metric,
                days: range.dayCount,
                history: history,
                activities: activities,
                reference: reference,
                calendar: calendar,
                isWeek: range == .week
            )
        case .quarter:
            return weekSamples(metric: metric, history: history, activities: activities, reference: reference, calendar: calendar)
        case .year:
            return monthSamples(metric: metric, history: history, activities: activities, reference: reference, calendar: calendar)
        }
    }

    /// Headline number for the whole range: a total for volume metrics, an average otherwise.
    static func headline(metric: DashboardMetric, range: MetricRange, samples: [MetricSample]) -> Double {
        aggregate(samples.map(\.value), using: metric.aggregation(for: range))
    }

    static func headline(metric: DashboardMetric, window: MetricWindow, samples: [MetricSample]) -> Double {
        headline(metric: metric, range: window.range, samples: samples)
    }

    static func average(metric: DashboardMetric, samples: [MetricSample]) -> Double {
        aggregate(samples.map(\.value), using: .average)
    }

    static func best(metric: DashboardMetric, samples: [MetricSample]) -> Double {
        let values = samples.map(\.value).filter { $0 > 0 }
        return metric == .pace ? (values.min() ?? 0) : (values.max() ?? 0)
    }

    static func low(metric: DashboardMetric, samples: [MetricSample]) -> Double {
        let values = samples.map(\.value).filter { $0 > 0 }
        return metric == .pace ? (values.max() ?? 0) : (values.min() ?? 0)
    }

    /// True when the final populated bucket sits above the one before it.
    static func deltaUp(_ samples: [MetricSample]) -> Bool? {
        let values = samples.map(\.value).filter { $0 > 0 }
        guard values.count > 1, let last = values.last, let previous = values.dropLast().last else { return nil }
        guard abs(last - previous) > 0.0001 else { return nil }
        return last > previous
    }

    static func aggregate(_ values: [Double], using aggregation: MetricAggregation) -> Double {
        switch aggregation {
        case .sum:
            return values.reduce(0, +)
        case .average:
            let populated = values.filter { $0 > 0 }
            guard !populated.isEmpty else { return 0 }
            return populated.reduce(0, +) / Double(populated.count)
        }
    }

    // MARK: - Bucket builders

    private static func hourlySamples(
        metric: DashboardMetric,
        history: MetricHistory,
        activities: [ActivityRecord],
        reference: Date,
        calendar: Calendar
    ) -> [MetricSample] {
        let startOfDay = calendar.startOfDay(for: reference)
        // Most metrics run midnight to midnight. Sleep runs 18:00 the evening
        // before to 18:00 on the day itself, because a night belongs to the
        // morning it ends on — counting only the hours after midnight lost every
        // minute spent in bed the night before.
        let axisStart = metric.usesNightAxis
            ? calendar.date(byAdding: .hour, value: -6, to: startOfDay) ?? startOfDay
            : startOfDay
        var values = metric.usesActivityHistory
            ? activityHourly(metric: metric, activities: activities, reference: reference, calendar: calendar)
            : history.hourlyValues(metric)

        if values.count < 24 {
            values.append(contentsOf: Array(repeating: 0, count: 24 - values.count))
        }

        // Metrics that are only sampled once a day (VO₂ max, resting HR) read flat across the day.
        if metric.aggregation(for: .day) == .average, !values.contains(where: { $0 > 0 }) {
            let today = history.dailyValues(metric).last ?? 0
            if today > 0 {
                values = Array(repeating: today, count: 24)
            }
        }

        // A past day is shown in full; today stops at the bucket we are in.
        let isToday = calendar.isDateInToday(reference)
        let elapsed = calendar.dateComponents([.hour], from: axisStart, to: reference).hour ?? 23
        let lastIndex = isToday ? min(23, max(0, elapsed)) : 23
        return (0...lastIndex).map { index in
            let start = calendar.date(byAdding: .hour, value: index, to: axisStart) ?? axisStart
            let clockHour = calendar.component(.hour, from: start)
            return MetricSample(
                index: index,
                start: start,
                label: hourLabel(clockHour),
                title: start.formatted(.dateTime.hour()),
                value: values.indices.contains(index) ? values[index] : 0,
                isCurrent: isToday && index == lastIndex
            )
        }
    }

    private static func daySamples(
        metric: DashboardMetric,
        days: Int,
        history: MetricHistory,
        activities: [ActivityRecord],
        reference: Date,
        calendar: Calendar,
        isWeek: Bool
    ) -> [MetricSample] {
        let daily = dailyValues(metric: metric, history: history, activities: activities, reference: reference, calendar: calendar)
        let today = calendar.startOfDay(for: reference)
        let slice = Array(daily.suffix(days))
        let count = slice.count
        return slice.enumerated().map { offset, value in
            let daysBack = count - 1 - offset
            let date = calendar.date(byAdding: .day, value: -daysBack, to: today) ?? today
            let isToday = calendar.isDateInToday(date)
            let label = isWeek
                ? (isToday ? "Today" : date.formatted(.dateTime.weekday(.abbreviated)))
                : date.formatted(.dateTime.day())
            return MetricSample(
                index: offset,
                start: date,
                label: label,
                title: isToday ? "Today" : date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)),
                value: value,
                isCurrent: daysBack == 0
            )
        }
    }

    /// Buckets exactly the days that were picked — never rounding up to whole
    /// weeks — so a total covers the span and nothing either side of it.
    private static func spanSamples(
        metric: DashboardMetric,
        span: MetricSpan,
        bucketDays: Int,
        history: MetricHistory,
        activities: [ActivityRecord],
        reference: Date,
        calendar: Calendar
    ) -> [MetricSample] {
        let daily = dailyValues(
            metric: metric,
            history: history,
            activities: activities,
            reference: reference,
            calendar: calendar
        )
        let values = Array(daily.suffix(span.dayCount))
        guard !values.isEmpty else { return [] }

        let aggregation = metric.aggregation(for: MetricWindow.span(span).range)
        let today = calendar.startOfDay(for: Date())
        // The stored series may not reach as far back as the span asks for, so
        // labels are anchored on the last day and counted backwards.
        let firstDay = calendar.date(byAdding: .day, value: -(values.count - 1), to: span.end) ?? span.end
        let usesWeekdayLabels = bucketDays == 1 && values.count <= 10

        var samples: [MetricSample] = []
        var offset = 0
        while offset < values.count {
            let upper = min(offset + bucketDays, values.count)
            let start = calendar.date(byAdding: .day, value: offset, to: firstDay) ?? firstDay
            let last = calendar.date(byAdding: .day, value: upper - 1, to: firstDay) ?? start
            let isSingleDayBucket = bucketDays == 1
            let label: String = isSingleDayBucket
                ? (usesWeekdayLabels
                    ? start.formatted(.dateTime.weekday(.abbreviated))
                    : start.formatted(.dateTime.day()))
                : start.formatted(.dateTime.day().month(.abbreviated))
            let title: String = isSingleDayBucket
                ? (calendar.isDateInToday(start)
                    ? "Today"
                    : start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                : "\(start.formatted(.dateTime.day().month(.abbreviated))) – \(last.formatted(.dateTime.day().month(.abbreviated)))"
            samples.append(
                MetricSample(
                    index: samples.count,
                    start: start,
                    label: label,
                    title: title,
                    value: aggregate(Array(values[offset..<upper]), using: aggregation),
                    isCurrent: start <= today && today <= last
                )
            )
            offset = upper
        }
        return samples
    }

    private static func weekSamples(
        metric: DashboardMetric,
        history: MetricHistory,
        activities: [ActivityRecord],
        reference: Date,
        calendar: Calendar
    ) -> [MetricSample] {
        let daily = dailyValues(metric: metric, history: history, activities: activities, reference: reference, calendar: calendar)
        let today = calendar.startOfDay(for: reference)
        let aggregation = metric.aggregation(for: .quarter)
        let weeks = 13
        return (0..<weeks).map { index in
            let weeksBack = weeks - 1 - index
            let bucketEndOffset = weeksBack * 7
            let upper = daily.count - bucketEndOffset
            let lower = max(0, upper - 7)
            let values = upper > lower ? Array(daily[lower..<max(lower, upper)]) : []
            let start = calendar.date(byAdding: .day, value: -(bucketEndOffset + 6), to: today) ?? today
            return MetricSample(
                index: index,
                start: start,
                label: start.formatted(.dateTime.day().month(.abbreviated)),
                title: "Week of \(start.formatted(.dateTime.day().month(.abbreviated)))",
                value: aggregate(values, using: aggregation),
                isCurrent: weeksBack == 0
            )
        }
    }

    private static func monthSamples(
        metric: DashboardMetric,
        history: MetricHistory,
        activities: [ActivityRecord],
        reference: Date,
        calendar: Calendar
    ) -> [MetricSample] {
        let daily = dailyValues(metric: metric, history: history, activities: activities, reference: reference, calendar: calendar)
        let today = calendar.startOfDay(for: reference)
        let aggregation = metric.aggregation(for: .year)
        let count = daily.count

        // Index every daily value by the month it belongs to.
        var buckets: [Date: [Double]] = [:]
        for (offset, value) in daily.enumerated() {
            let daysBack = count - 1 - offset
            guard let date = calendar.date(byAdding: .day, value: -daysBack, to: today),
                  let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) else { continue }
            buckets[monthStart, default: []].append(value)
        }

        let currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
        return (0..<12).map { index in
            let monthsBack = 11 - index
            let monthStart = calendar.date(byAdding: .month, value: -monthsBack, to: currentMonth) ?? currentMonth
            return MetricSample(
                index: index,
                start: monthStart,
                label: monthStart.formatted(.dateTime.month(.narrow)),
                title: monthStart.formatted(.dateTime.month(.wide).year()),
                value: aggregate(buckets[monthStart] ?? [], using: aggregation),
                isCurrent: monthsBack == 0
            )
        }
    }

    // MARK: - Sources

    /// A year of daily values, oldest first, from Health history or recorded activities.
    ///
    /// Health history is always stored ending on today, so when the user has
    /// scrubbed back to an earlier day it is trimmed to end there instead.
    private static func dailyValues(
        metric: DashboardMetric,
        history: MetricHistory,
        activities: [ActivityRecord],
        reference: Date,
        calendar: Calendar
    ) -> [Double] {
        if metric.usesActivityHistory {
            return activityDaily(metric: metric, activities: activities, reference: reference, calendar: calendar)
        }
        var values = history.dailyValues(metric)
        if values.count > historyDayCount {
            values = Array(values.suffix(historyDayCount))
        } else if values.count < historyDayCount {
            values = Array(repeating: 0, count: historyDayCount - values.count) + values
        }

        let daysBack = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: reference),
            to: calendar.startOfDay(for: Date())
        ).day ?? 0
        if daysBack > 0 {
            values = Array(values.dropLast(min(daysBack, values.count)))
            values = Array(repeating: 0, count: historyDayCount - values.count) + values
        }
        return values
    }

    private static func activityDaily(
        metric: DashboardMetric,
        activities: [ActivityRecord],
        reference: Date,
        calendar: Calendar
    ) -> [Double] {
        let days = historyDayCount
        let today = calendar.startOfDay(for: reference)
        var totals = [Double](repeating: 0, count: days)
        var seconds = [Double](repeating: 0, count: days)
        var kilometres = [Double](repeating: 0, count: days)

        for activity in activities {
            let start = calendar.startOfDay(for: activity.startDate)
            guard let offset = calendar.dateComponents([.day], from: start, to: today).day,
                  offset >= 0, offset < days else { continue }
            let index = days - 1 - offset
            switch metric {
            case .distance:
                totals[index] += activity.distance / 1000
            case .elevation:
                totals[index] += activity.elevationGain
            case .calories:
                totals[index] += activity.calories
            case .load:
                totals[index] += (activity.duration / 60) * max(1, activity.averageHeartRate / 100)
            case .pace:
                seconds[index] += activity.duration
                kilometres[index] += activity.distance / 1000
            default:
                break
            }
        }

        if metric == .pace {
            return zip(seconds, kilometres).map { duration, km in km > 0.05 ? duration / km : 0 }
        }
        return totals
    }

    private static func activityHourly(
        metric: DashboardMetric,
        activities: [ActivityRecord],
        reference: Date,
        calendar: Calendar
    ) -> [Double] {
        let startOfDay = calendar.startOfDay(for: reference)
        var totals = [Double](repeating: 0, count: 24)
        var seconds = [Double](repeating: 0, count: 24)
        var kilometres = [Double](repeating: 0, count: 24)

        for activity in activities where activity.startDate >= startOfDay {
            let hour = calendar.component(.hour, from: activity.startDate)
            guard totals.indices.contains(hour) else { continue }
            switch metric {
            case .distance:
                totals[hour] += activity.distance / 1000
            case .elevation:
                totals[hour] += activity.elevationGain
            case .calories:
                totals[hour] += activity.calories
            case .load:
                totals[hour] += (activity.duration / 60) * max(1, activity.averageHeartRate / 100)
            case .pace:
                seconds[hour] += activity.duration
                kilometres[hour] += activity.distance / 1000
            default:
                break
            }
        }

        if metric == .pace {
            return zip(seconds, kilometres).map { duration, km in km > 0.05 ? duration / km : 0 }
        }
        return totals
    }

    private static func hourLabel(_ hour: Int) -> String {
        switch hour {
        case 0: "12a"
        case 12: "12p"
        case 1..<12: "\(hour)a"
        default: "\(hour - 12)p"
        }
    }
}
