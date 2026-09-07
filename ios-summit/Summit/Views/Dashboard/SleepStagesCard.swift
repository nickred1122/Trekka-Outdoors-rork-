import SwiftUI

/// Last night drawn as a hypnogram, with the stage breakdown underneath.
///
/// The stage data was always coming back from Health; it was being merged into a
/// single duration on the way in, which is why the sleep tile could only ever say
/// how long you were asleep and never how well.
struct SleepStagesCard: View {
    let night: SleepNight
    /// The morning this night ended on, for the header.
    let day: Date

    private var calendar: Calendar { Calendar.current }

    private var title: String {
        if calendar.isDateInToday(day) { return "Last night" }
        if calendar.isDateInYesterday(day) { return "The night before" }
        return "Night of " + day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if night.isEmpty {
                emptyState
            } else {
                if night.hasStageDetail {
                    Hypnogram(segments: night.segments)
                        .frame(height: 116)
                    timeAxis
                } else {
                    SleepRibbon(segments: night.segments)
                        .frame(height: 26)
                    timeAxis
                }

                Divider().overlay(Theme.border)
                stageRows
                Divider().overlay(Theme.border)
                footerStats
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .metricLabelStyle()
                Text(night.isEmpty ? "--" : Self.duration(night.asleepSeconds))
                    .font(.metric(30))
                    .foregroundStyle(Theme.textPrimary)
            }

            Spacer()

            if !night.isEmpty {
                VStack(alignment: .trailing, spacing: 3) {
                    Text("Quality")
                        .metricLabelStyle()
                    Text("\(night.quality)")
                        .font(.metric(30))
                        .foregroundStyle(DashboardMetric.sleep.tint)
                }
            }
        }
    }

    private var emptyState: some View {
        Text("No sleep recorded for this night.")
            .font(.system(.footnote))
            .foregroundStyle(Theme.textPrimary.opacity(0.55))
            .padding(.vertical, 6)
    }

    // MARK: - Axis

    private var timeAxis: some View {
        HStack {
            Text(night.bedtime.map(Self.clock) ?? "--")
            Spacer()
            Text(night.summary)
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer()
            Text(night.wakeTime.map(Self.clock) ?? "--")
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Theme.textPrimary.opacity(0.7))
    }

    // MARK: - Stage rows

    private var stageRows: some View {
        VStack(spacing: 9) {
            ForEach(presentStages, id: \.self) { stage in
                stageRow(stage)
            }
        }
    }

    /// Only stages that actually occurred, so a night without REM does not show
    /// an empty REM row implying the tracker measured zero.
    private var presentStages: [SleepStage] {
        SleepStage.allCases.filter { night.total($0) > 0 }
    }

    private func stageRow(_ stage: SleepStage) -> some View {
        let seconds = night.total(stage)
        // Awake time is not part of the asleep total, so showing it as a share of
        // sleep would be arithmetic nonsense.
        let share = stage.isAsleep ? night.fraction(stage) : 0

        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(stage.tint)
                .frame(width: 4, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(stage.title)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(stage.meaning)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(Self.duration(seconds))
                    .font(.metric(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                if stage.isAsleep, share > 0 {
                    Text("\(Int((share * 100).rounded()))%")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                }
            }
        }
    }

    // MARK: - Footer

    private var footerStats: some View {
        HStack(spacing: 0) {
            footerStat("In bed", Self.duration(night.timeInBedSeconds))
            footerStat("Efficiency", "\(Int((night.efficiency * 100).rounded()))%")
            footerStat("Wakings", "\(night.awakenings)")
        }
    }

    private func footerStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.metric(17, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Formatting

    private static func duration(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "--" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    private static func clock(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }
}

/// The classic stepped sleep chart: shallowest stage at the top, deepest at the
/// bottom, time running left to right.
private struct Hypnogram: View {
    let segments: [SleepSegment]

    var body: some View {
        // Captured out here rather than inside the drawing closure, so the view
        // redraws when they change.
        let blocks = segments
        let span = totalSpan

        Canvas(rendersAsynchronously: false) { context, size in
            guard span > 0, let origin = blocks.first?.start else { return }
            let laneCount = CGFloat(SleepStage.lanes.count)
            let laneHeight = size.height / laneCount
            let barHeight = max(6, laneHeight - 7)

            for stage in SleepStage.lanes {
                let y = CGFloat(stage.lane) * laneHeight + (laneHeight - barHeight) / 2
                let track = CGRect(x: 0, y: y, width: size.width, height: barHeight)
                context.fill(
                    Path(roundedRect: track, cornerRadius: barHeight / 2),
                    with: .color(stage.tint.opacity(0.09))
                )
            }

            for block in blocks {
                let startFraction = block.start.timeIntervalSince(origin) / span
                let widthFraction = block.duration / span
                let x = CGFloat(startFraction) * size.width
                // A two-minute stage would otherwise be a sub-pixel sliver and
                // vanish, making a fragmented night look unbroken.
                let width = max(2.5, CGFloat(widthFraction) * size.width)
                let y = CGFloat(block.stage.lane) * laneHeight + (laneHeight - barHeight) / 2
                let rect = CGRect(x: x, y: y, width: width, height: barHeight)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: min(barHeight / 2, width / 2)),
                    with: .color(block.stage.tint)
                )
            }
        }
        .accessibilityLabel("Sleep stages through the night")
    }

    private var totalSpan: TimeInterval {
        guard let first = segments.first, let last = segments.last else { return 0 }
        return last.end.timeIntervalSince(first.start)
    }
}

/// A single bar for nights recorded without stage detail — honest about the fact
/// that only asleep and awake are known.
private struct SleepRibbon: View {
    let segments: [SleepSegment]

    var body: some View {
        let blocks = segments
        let span = totalSpan

        Canvas(rendersAsynchronously: false) { context, size in
            guard span > 0, let origin = blocks.first?.start else { return }
            let radius = size.height / 2
            context.fill(
                Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: radius),
                with: .color(SleepStage.unspecified.tint.opacity(0.12))
            )
            for block in blocks {
                let startFraction = block.start.timeIntervalSince(origin) / span
                let widthFraction = block.duration / span
                let x = CGFloat(startFraction) * size.width
                let width = max(2.5, CGFloat(widthFraction) * size.width)
                let rect = CGRect(x: x, y: 0, width: width, height: size.height)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: min(radius, width / 2)),
                    with: .color(block.stage.tint)
                )
            }
        }
        .accessibilityLabel("Time asleep through the night")
    }

    private var totalSpan: TimeInterval {
        guard let first = segments.first, let last = segments.last else { return 0 }
        return last.end.timeIntervalSince(first.start)
    }
}
