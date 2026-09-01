import SwiftUI

/// Seven-day history drawn as a trend line, mirroring the phone tiles.
struct WatchSparkline: View {
    let values: [Double]
    var tint: Color = WatchTheme.accent

    var body: some View {
        Canvas { context, size in
            let samples = values.filter { $0.isFinite }
            guard samples.count > 1, size.width > 1, size.height > 1 else { return }
            drawLine(samples, in: &context, size: size)
        }
        .accessibilityHidden(true)
    }

    /// A trend line is about movement, so it is scaled to the band the values
    /// actually occupy rather than to zero.
    private func drawLine(_ samples: [Double], in context: inout GraphicsContext, size: CGSize) {
        let populated = samples.filter { $0 > 0 }
        guard populated.count > 1,
              let minimum = populated.min(),
              let maximum = populated.max() else { return }
        let span = max(0.0001, maximum - minimum)
        let inset: CGFloat = 2.6

        func y(_ value: Double) -> CGFloat {
            let fraction = CGFloat((value - minimum) / span)
            let raw = size.height - inset - fraction * max(1, size.height - inset * 2)
            return min(max(raw, 0), size.height)
        }

        var path = Path()
        let step = size.width / CGFloat(samples.count - 1)
        var started = false
        for (index, value) in samples.enumerated() where value > 0 {
            let point = CGPoint(x: step * CGFloat(index), y: y(value))
            if started {
                path.addLine(to: point)
            } else {
                path.move(to: point)
                started = true
            }
        }
        context.stroke(
            path,
            with: .color(tint),
            style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
        )

        if let last = samples.last, last > 0 {
            let dot = CGRect(x: size.width - 2.6, y: y(last) - 2.6, width: 5.2, height: 5.2)
            context.fill(Path(ellipseIn: dot), with: .color(tint))
        }
    }
}

/// One dashboard tile: icon, label, tabular value and its trend.
struct WatchMetricTile: View {
    let metric: WatchDashboardMetric
    let reading: MetricReadingTransfer?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                TrekkaIcon(metric.glyph, size: 11, tint: metric.tint)
                Text(metric.title)
                    .fieldLabelStyle()
                Spacer(minLength: 0)
                if let deltaUp {
                    Image(systemName: deltaUp ? "arrow.up.right" : "arrow.down.right")
                        .font(.watch(8, weight: .bold))
                        .foregroundStyle(deltaUp ? WatchTheme.positive : WatchTheme.textSecondary)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(reading?.displayValue ?? "--")
                    .font(.metric(22, weight: .bold))
                    .foregroundStyle(WatchTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit = reading?.unit, !unit.isEmpty {
                    Text(unit)
                        .font(.watch(10, weight: .medium))
                        .foregroundStyle(WatchTheme.textSecondary)
                }
                Spacer(minLength: 0)
            }

            if let series = reading?.series, series.contains(where: { $0 > 0 }) {
                WatchSparkline(values: series, tint: metric.tint)
                    .frame(height: WatchDisplay.scaled(18, atLeast: 13))
            }
        }
        .padding(.horizontal, WatchDisplay.spacing(8))
        .padding(.vertical, WatchDisplay.spacing(8))
        .frame(maxWidth: .infinity, alignment: .leading)
        .watchPanel()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(metric.title) \(reading?.displayValue ?? "no data") \(reading?.unit ?? "")")
    }

    private var deltaUp: Bool? {
        guard let series = reading?.series, series.count > 1,
              let last = series.last, let previous = series.dropLast().last,
              abs(last - previous) > 0.0001 else { return nil }
        return last > previous
    }
}

/// Weekly time-in-zone bars, matching the phone's zone chart.
struct WatchZoneBars: View {
    let minutes: [Double]

    private var total: Double { minutes.reduce(0, +) }

    var body: some View {
        VStack(alignment: .leading, spacing: WatchDisplay.spacing(5)) {
            HStack {
                Text("Time in zones")
                    .fieldLabelStyle()
                Spacer(minLength: 0)
                Text(total > 0 ? WatchFormat.compactDuration(total * 60) : "--")
                    .font(.metric(11, weight: .semibold))
                    .foregroundStyle(WatchTheme.textSecondary)
            }

            ForEach(Array(minutes.enumerated()), id: \.offset) { index, value in
                ZoneRow(
                    zone: index + 1,
                    seconds: value * 60,
                    fraction: total > 0 ? value / (minutes.max() ?? 1) : 0,
                    isCurrent: false
                )
            }
        }
        .padding(WatchDisplay.spacing(9))
        .frame(maxWidth: .infinity)
        .watchPanel()
    }
}

/// A completed workout as a compact row with its track shape.
struct WatchActivityRow: View {
    let activity: ActivityTransfer

    private var kind: WatchActivityKind {
        WatchActivityKind(rawValue: activity.activity) ?? .hike
    }

    var body: some View {
        HStack(spacing: WatchDisplay.spacing(8)) {
            // Workouts without a track get no tile at all rather than a stand-in
            // mark, so the name and numbers take the full width.
            if activity.track.count > 1 {
                RouteGlyph(points: activity.routePoints, tint: kind.tint)
                    .frame(width: WatchDisplay.scaled(30, atLeast: 26), height: WatchDisplay.scaled(30, atLeast: 26))
                    .background(WatchTheme.surfaceRaised, in: .rect(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(activity.name)
                    .font(.watch(13, weight: .semibold))
                    .foregroundStyle(WatchTheme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: WatchDisplay.spacing(5)) {
                    Text("\(WatchFormat.distance(activity.distance)) \(WatchFormat.units.distanceUnit)")
                    Text(WatchFormat.compactDuration(activity.duration))
                    Text("↑\(WatchFormat.elevation(activity.elevationGain))")
                        .foregroundStyle(WatchTheme.highlight)
                }
                .font(.metric(9, weight: .medium))
                .foregroundStyle(WatchTheme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
