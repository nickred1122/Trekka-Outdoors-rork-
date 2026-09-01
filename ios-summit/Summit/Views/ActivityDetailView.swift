import SwiftUI

struct ActivityDetailView: View {
    let activity: ActivityRecord

    @State private var recenterToken = 0

    /// One kilometre or one mile, whichever the athlete reads in.
    private var splitDistance: Double {
        Formatters.units.metres(fromDistance: 1)
    }

    /// Everything derived from the recorded track: splits, descent, high and
    /// low point, moving time.
    private var analysis: ActivityAnalysis {
        ActivityAnalysis.analyse(track: activity.track, splitDistance: splitDistance)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if activity.track.count > 1 {
                    TrekkaMapSurface(
                        routePoints: activity.track,
                        isInteractive: false,
                        showsUserLocation: false,
                        recenterToken: recenterToken
                    )
                    .frame(height: 220)
                    .clipShape(.rect(cornerRadius: Theme.cardRadius))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.cardRadius)
                            .strokeBorder(Theme.border, lineWidth: 1)
                    }
                }

                StatStrip(items: [
                    StatItem(symbol: "arrow.left.and.right", label: "Distance", value: Formatters.distance(activity.distance), unit: Formatters.units.distanceUnit),
                    StatItem(symbol: "clock", label: "Time", value: Formatters.duration(activity.duration), unit: ""),
                    StatItem(symbol: "speedometer", label: "Avg pace", value: Formatters.pace(activity.averagePace), unit: Formatters.units.paceUnit),
                ])

                StatStrip(items: [
                    StatItem(symbol: "arrow.up.forward", label: "Climb", value: Formatters.elevation(activity.elevationGain), unit: Formatters.units.elevationUnit),
                    StatItem(symbol: "heart.fill", label: "Avg HR", value: Formatters.integer(activity.averageHeartRate), unit: "bpm"),
                    StatItem(symbol: "flame.fill", label: "Calories", value: Formatters.integer(activity.calories), unit: "kcal"),
                ])

                secondaryStats

                if activity.track.count > 1 {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Elevation")
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        ElevationChart(samples: ElevationProfile.samples(for: activity.track), height: 140)
                    }
                    .padding(16)
                    .panel()
                }

                if analysis.hasSplits {
                    splitsCard
                }

                ZoneBars(minutes: activity.zoneMinutes, title: "Time in zones", subtitle: "This session")

                trainingEffectCard

                sessionCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background(Theme.canvas)
        .navigationTitle(activity.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    /// The second rank of numbers, derived from the track. Each one is absent
    /// rather than shown as zero when the track cannot honestly support it.
    @ViewBuilder
    private var secondaryStats: some View {
        let hasDescent = analysis.elevationLoss > 1
        let hasMoving = analysis.movingTime > 60

        if hasDescent || hasMoving {
            StatStrip(items: [
                StatItem(
                    symbol: "arrow.down.forward",
                    label: "Descent",
                    value: hasDescent ? Formatters.elevation(analysis.elevationLoss) : "--",
                    unit: Formatters.units.elevationUnit
                ),
                StatItem(
                    symbol: "figure.walk.motion",
                    label: "Moving",
                    value: hasMoving ? Formatters.duration(analysis.movingTime) : "--",
                    unit: ""
                ),
                StatItem(
                    symbol: "gauge.with.dots.needle.bottom.50percent",
                    label: "Avg speed",
                    value: activity.duration > 0
                        ? Formatters.speed(activity.distance / activity.duration)
                        : "--",
                    unit: Formatters.units.speedUnit
                ),
            ])
        }

        if analysis.hasElevation {
            StatStrip(items: [
                StatItem(
                    symbol: "mountain.2.fill",
                    label: "High point",
                    value: Formatters.elevation(analysis.highestPoint),
                    unit: Formatters.units.elevationUnit
                ),
                StatItem(
                    symbol: "arrow.down.to.line",
                    label: "Low point",
                    value: Formatters.elevation(analysis.lowestPoint),
                    unit: Formatters.units.elevationUnit
                ),
                StatItem(
                    symbol: "angle",
                    label: "Steepest",
                    value: analysis.steepestGrade > 0
                        ? String(format: "%.0f", analysis.steepestGrade)
                        : "--",
                    unit: "%"
                ),
            ])
        }
    }

    /// Split-by-split pace — the thing an athlete actually reopens a workout for.
    private var splitsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Splits")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("per \(Formatters.units.distanceUnit)")
                    .font(.caption)
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
            }

            let fastest = analysis.fastestSplit?.pace ?? 0
            let slowest = analysis.slowestSplit?.pace ?? 0

            VStack(spacing: 7) {
                ForEach(analysis.splits) { split in
                    splitRow(split, fastest: fastest, slowest: slowest)
                }
            }
        }
        .padding(16)
        .panel()
    }

    /// One split: its number, a bar as long as it was quick, the pace, and any
    /// climbing in it.
    ///
    /// The bar is scaled between this activity's own fastest and slowest split
    /// rather than an absolute pace, because the useful question is which parts
    /// of *this* outing were hard.
    private func splitRow(
        _ split: ActivitySplit,
        fastest: TimeInterval,
        slowest: TimeInterval
    ) -> some View {
        let span = max(slowest - fastest, 1)
        let fraction: Double = split.pace > 0
            ? max(0.12, min(1, 1 - (split.pace - fastest) / span * 0.8))
            : 0.12
        let isFastest = !split.isPartial && split.pace > 0 && split.pace == fastest

        return HStack(spacing: 10) {
            Text(split.isPartial ? "·" : "\(split.index)")
                .font(.metric(13))
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
                .frame(width: 16, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.surfaceRaised)
                    Capsule()
                        .fill(isFastest ? Theme.accent : Theme.accent.opacity(0.45))
                        .frame(width: max(6, geometry.size.width * fraction))
                }
            }
            .frame(height: 8)

            if split.elevationGain > 5 {
                Label(
                    Formatters.elevation(split.elevationGain),
                    systemImage: "arrow.up"
                )
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textPrimary.opacity(0.45))
            }

            Text(Formatters.pace(split.pace))
                .font(.metric(14))
                .foregroundStyle(isFastest ? Theme.accent : Theme.textPrimary)
                .frame(width: 54, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            split.isPartial
                ? "Final part split, \(Formatters.pace(split.pace)) per \(Formatters.units.distanceUnit)"
                : "Split \(split.index), \(Formatters.pace(split.pace)) per \(Formatters.units.distanceUnit)"
        )
    }

    /// When it happened — the first thing you want when scrolling back through a
    /// season and trying to remember which outing this was.
    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Session")
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            detailRow("Activity", activity.activity.rawValue)
            detailRow("Started", activity.startDate.formatted(date: .abbreviated, time: .shortened))
            detailRow(
                "Finished",
                activity.startDate
                    .addingTimeInterval(activity.duration)
                    .formatted(date: .omitted, time: .shortened)
            )
            if let fastest = analysis.fastestSplit {
                detailRow(
                    "Fastest \(Formatters.units.distanceUnit)",
                    "\(Formatters.pace(fastest.pace)) \(Formatters.units.paceUnit) · split \(fastest.index)"
                )
            }
            if activity.track.count > 1 {
                detailRow("Recorded points", "\(activity.track.count)")
            }
        }
        .padding(16)
        .panel()
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
            Spacer(minLength: 8)
            Text(value)
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    private var trainingEffectCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Training effect")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(String(format: "%.1f", activity.trainingEffect))
                    .font(.metric(20))
                    .foregroundStyle(Theme.accent)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surfaceRaised)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Theme.zoneColors[1], Theme.highlight, Theme.accent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * min(1, activity.trainingEffect / 5))
                }
            }
            .frame(height: 8)
            Text(effectLabel)
                .font(.caption)
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
        }
        .padding(16)
        .panel()
    }

    private var effectLabel: String {
        switch activity.trainingEffect {
        case ..<1.5: "Recovery — maintains your base"
        case 1.5..<2.5: "Maintaining — holds current fitness"
        case 2.5..<3.5: "Improving — builds aerobic capacity"
        case 3.5..<4.5: "Highly improving — strong stimulus"
        default: "Overreaching — plan recovery next"
        }
    }
}
