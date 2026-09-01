import SwiftUI
import Charts

/// Climb profile for the loaded route with your live position marked, or the
/// altitude you have actually recorded when running free.
struct ElevationPageView: View {
    let route: WatchRoute?
    let track: [WatchTrackPoint]
    let metrics: LiveMetrics

    private struct ProfilePoint: Identifiable {
        var id: Int
        var distance: Double
        var elevation: Double
    }

    private var profile: [ProfilePoint] {
        if let route, route.points.count > 1 {
            let distances = WatchRouteMath.cumulativeDistances(of: route.points)
            return route.points.enumerated().compactMap { index, point in
                guard distances.indices.contains(index) else { return nil }
                return ProfilePoint(
                    id: index,
                    distance: WatchFormat.units.distance(fromMetres: distances[index]),
                    elevation: WatchFormat.units.elevation(fromMetres: point.elevation)
                )
            }
        }
        return track.enumerated().map { index, point in
            ProfilePoint(
                id: index,
                distance: WatchFormat.units.distance(fromMetres: point.distance),
                elevation: WatchFormat.units.elevation(fromMetres: point.altitude)
            )
        }
    }

    /// The position marker shares the chart's axis, so it converts with it.
    private var progressDistance: Double {
        WatchFormat.units.distance(fromMetres: metrics.distance)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WatchDisplay.spacing(6)) {
            HStack(spacing: WatchDisplay.spacing(8)) {
                MetricCell(field: .ascent, value: WatchFormat.elevation(metrics.ascent), size: .compact, tint: WatchTheme.highlight)
                MetricCell(field: .altitude, value: WatchFormat.elevation(metrics.altitude), size: .compact)
                MetricCell(field: .grade, value: WatchFormat.signedDecimal(metrics.grade), size: .compact, tint: gradeTint)
            }

            if profile.count > 1 {
                chart
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var chart: some View {
        Chart {
            ForEach(profile) { point in
                AreaMark(
                    x: .value("Distance", point.distance),
                    y: .value("Elevation", point.elevation)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [WatchTheme.accent.opacity(0.55), WatchTheme.accent.opacity(0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Distance", point.distance),
                    y: .value("Elevation", point.elevation)
                )
                .foregroundStyle(WatchTheme.accent)
                .lineStyle(StrokeStyle(lineWidth: 1.6))
                .interpolationMethod(.catmullRom)
            }

            if progressDistance > 0 {
                RuleMark(x: .value("You", progressDistance))
                    .foregroundStyle(WatchTheme.highlight)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisValueLabel {
                    if let distance = value.as(Double.self) {
                        Text("\(Int(distance))")
                            .font(.watch(8))
                            .foregroundStyle(WatchTheme.textSecondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisValueLabel {
                    if let elevation = value.as(Double.self) {
                        Text("\(Int(elevation))")
                            .font(.watch(8))
                            .foregroundStyle(WatchTheme.textSecondary)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var placeholder: some View {
        VStack(spacing: WatchDisplay.spacing(4)) {
            Image(systemName: "mountain.2")
                .font(.title3)
                .foregroundStyle(WatchTheme.textSecondary)
            Text("Profile builds as you climb")
                .font(.watch(11))
                .foregroundStyle(WatchTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var gradeTint: Color {
        metrics.grade > 3 ? WatchTheme.danger : (metrics.grade < -3 ? WatchTheme.positive : WatchTheme.textPrimary)
    }
}
