import SwiftUI

/// Post-workout recap with the headline numbers, zone split and every lap.
struct SummaryView: View {
    let sport: WatchSport
    let metrics: LiveMetrics
    let laps: [WatchLap]
    var onDone: () -> Void

    private var totalZoneSeconds: TimeInterval {
        max(1, metrics.zoneSeconds.reduce(0, +))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header

                VStack(spacing: 6) {
                    WatchStatRow(title: "Duration", value: WatchFormat.duration(metrics.elapsed))
                    WatchStatRow(
                        title: "Distance",
                        value: "\(WatchFormat.distance(metrics.distance)) \(WatchFormat.units.distanceUnit)"
                    )
                    WatchStatRow(
                        title: sport.usesPace ? "Avg pace" : "Avg speed",
                        value: sport.usesPace
                            ? "\(WatchFormat.pace(metrics.averagePace)) \(WatchFormat.units.paceUnit)"
                            : "\(WatchFormat.speed(metrics.averageSpeed)) \(WatchFormat.units.speedUnit)",
                        tint: WatchTheme.highlight
                    )
                    WatchStatRow(
                        title: "Ascent",
                        value: "\(WatchFormat.elevation(metrics.ascent)) \(WatchFormat.units.elevationUnit)"
                    )
                    WatchStatRow(
                        title: "Avg HR",
                        value: metrics.averageHeartRate > 0 ? "\(WatchFormat.integer(metrics.averageHeartRate)) bpm" : "--",
                        tint: WatchTheme.zoneColor(LiveMetrics.zone(for: metrics.averageHeartRate))
                    )
                    WatchStatRow(title: "Calories", value: "\(WatchFormat.integer(metrics.calories)) kcal")
                }
                .padding(9)
                .watchPanel()

                effortCard

                if !laps.isEmpty {
                    Text("Laps")
                        .fieldLabelStyle()
                    VStack(spacing: 4) {
                        ForEach(laps) { lap in
                            HStack {
                                Text("\(lap.index)")
                                    .font(.metric(12, weight: .bold))
                                    .foregroundStyle(WatchTheme.textSecondary)
                                    .frame(width: 14, alignment: .leading)
                                Text(WatchFormat.duration(lap.duration))
                                    .font(.metric(13, weight: .semibold))
                                    .foregroundStyle(WatchTheme.textPrimary)
                                Spacer()
                                Text(sport.usesPace
                                     ? "\(WatchFormat.pace(lap.pace)) \(WatchFormat.units.paceUnit)"
                                     : "\(WatchFormat.distance(lap.distance)) \(WatchFormat.units.distanceUnit)")
                                    .font(.metric(12))
                                    .foregroundStyle(WatchTheme.highlight)
                            }
                            .padding(.vertical, 5)
                            .padding(.horizontal, 8)
                            .watchPanel(radius: 8)
                        }
                    }
                }

                Button("Done", action: onDone)
                    .buttonStyle(.borderedProminent)
                    .tint(sport.tint)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 4)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(sport.title)
                .font(.watch(12, weight: .semibold))
                .foregroundStyle(sport.tint)
            Text(metrics.startDate.formatted(.dateTime.weekday(.wide).hour().minute()))
                .font(.watch(10))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(WatchTheme.textSecondary)
        }
    }

    private var effortCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Training effect")
                    .fieldLabelStyle()
                Spacer()
                Text(WatchFormat.decimal(metrics.trainingEffect, places: 1))
                    .font(.metric(16, weight: .bold))
                    .foregroundStyle(WatchTheme.accent)
            }
            Text(effectCaption)
                .font(.watch(10))
                .foregroundStyle(WatchTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: WatchDisplay.spacing(4)) {
                ForEach(1...5, id: \.self) { zone in
                    ZoneRow(
                        zone: zone,
                        seconds: metrics.zoneSeconds[zone - 1],
                        fraction: metrics.zoneSeconds[zone - 1] / totalZoneSeconds,
                        isCurrent: false
                    )
                }
            }
        }
        .padding(9)
        .watchPanel()
    }

    private var effectCaption: String {
        switch metrics.trainingEffect {
        case ..<1.0: "Recovery session — no lasting adaptation."
        case ..<2.0: "Maintains your aerobic base."
        case ..<3.0: "Improves aerobic fitness."
        case ..<4.0: "Strong aerobic gain — allow a recovery day."
        default: "Overreaching. Take real rest before the next hard effort."
        }
    }
}
