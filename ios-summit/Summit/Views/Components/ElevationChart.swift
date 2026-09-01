import SwiftUI
import Charts

nonisolated struct ElevationSample: Identifiable, Sendable {
    let id = UUID()
    let distance: Double
    let elevation: Double
}

nonisolated enum ElevationProfile {
    /// Down-samples a track into chart-friendly distance/elevation pairs.
    static func samples(for points: [RoutePoint], limit: Int = 120) -> [ElevationSample] {
        guard points.count > 1 else { return [] }
        let cumulative = RouteMath.cumulativeDistances(of: points)
        let stride = max(1, points.count / limit)
        var result: [ElevationSample] = []
        for index in Swift.stride(from: 0, to: points.count, by: stride) {
            result.append(
                ElevationSample(
                    distance: cumulative[index] / 1_000,
                    elevation: points[index].elevation
                )
            )
        }
        if let lastIndex = points.indices.last, result.last?.distance != cumulative[lastIndex] / 1_000 {
            result.append(ElevationSample(distance: cumulative[lastIndex] / 1_000, elevation: points[lastIndex].elevation))
        }
        return result
    }
}

/// Swift Charts elevation profile with optional waypoint markers and a live cursor.
struct ElevationChart: View {
    let samples: [ElevationSample]
    var waypoints: [Waypoint] = []
    var cursorDistance: Double?
    var showsAxes: Bool = true
    var height: CGFloat = 150

    private var elevationRange: ClosedRange<Double> {
        let values = samples.map(\.elevation)
        let minimum = (values.min() ?? 0) - 60
        let maximum = (values.max() ?? 100) + 60
        return max(0, minimum)...maximum
    }

    var body: some View {
        Chart {
            ForEach(samples) { sample in
                AreaMark(
                    x: .value("Distance", sample.distance),
                    y: .value("Elevation", sample.elevation)
                )
                .foregroundStyle(
                    .linearGradient(
                        colors: [Theme.accent.opacity(0.42), Theme.accent.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                // Monotone, not catmullRom: a Catmull-Rom spline overshoots the
                // points it joins, so between two close samples the curve bulges
                // outside the y domain and spills past the axis.
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value("Distance", sample.distance),
                    y: .value("Elevation", sample.elevation)
                )
                .foregroundStyle(Theme.accent)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)
            }

            ForEach(waypoints) { waypoint in
                RuleMark(x: .value("Waypoint", waypoint.distanceAlongRoute / 1_000))
                    .foregroundStyle(Theme.textPrimary.opacity(0.18))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }

            if let cursorDistance {
                RuleMark(x: .value("Now", cursorDistance / 1_000))
                    .foregroundStyle(Theme.textPrimary.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                PointMark(
                    x: .value("Now", cursorDistance / 1_000),
                    y: .value("Elevation", elevation(at: cursorDistance))
                )
                .symbolSize(120)
                .foregroundStyle(Theme.textPrimary)
            }
        }
        .chartYScale(domain: elevationRange)
        .chartPlotStyle { plot in
            // Anything the renderer still puts outside the plot stays inside it.
            plot.clipped()
        }
        .chartXAxis {
            if showsAxes {
                AxisMarks(preset: .aligned, position: .bottom) { value in
                    AxisValueLabel {
                        if let distance = value.as(Double.self) {
                            Text("\(Formatters.units.distance(fromMetres: distance * 1000), specifier: "%.1f") \(Formatters.units.distanceUnit)")
                                .font(.caption2)
                                .foregroundStyle(Theme.textPrimary.opacity(0.5))
                        }
                    }
                }
            } else {
                AxisMarks { _ in }
            }
        }
        .chartYAxis {
            if showsAxes {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Theme.border.opacity(0.6))
                    AxisValueLabel {
                        if let elevation = value.as(Double.self) {
                            Text("\(Formatters.elevation(elevation)) \(Formatters.units.elevationUnit)")
                                .font(.caption2)
                                .foregroundStyle(Theme.textPrimary.opacity(0.5))
                        }
                    }
                }
            } else {
                AxisMarks { _ in }
            }
        }
        .frame(height: height)
        .accessibilityLabel("Elevation profile")
    }

    private func elevation(at distance: Double) -> Double {
        let target = distance / 1_000
        return samples.min { abs($0.distance - target) < abs($1.distance - target) }?.elevation ?? 0
    }
}
