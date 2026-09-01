import SwiftUI

/// Split list: the lap in progress on top, every completed lap below it.
struct LapsPageView: View {
    let laps: [WatchLap]
    let metrics: LiveMetrics
    let usesPace: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: WatchDisplay.spacing(5)) {
                currentLap

                if laps.isEmpty {
                    Text("Laps appear here as you split")
                        .font(.watch(11))
                        .foregroundStyle(WatchTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 10)
                } else {
                    ForEach(laps.reversed()) { lap in
                        lapRow(lap)
                    }
                }
            }
        }
    }

    private var currentLap: some View {
        VStack(spacing: 3) {
            HStack {
                Text("LAP \(metrics.lapCount)")
                    .fieldLabelStyle(WatchTheme.accent)
                Spacer()
                Text("IN PROGRESS")
                    .font(.watch(8, weight: .heavy))
                    .foregroundStyle(WatchTheme.textSecondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: WatchDisplay.spacing(6)) {
                Text(WatchFormat.duration(metrics.lapElapsed))
                    .font(.metric(22, weight: .bold))
                    .foregroundStyle(WatchTheme.textPrimary)
                Spacer(minLength: 0)
                Text(WatchFormat.distance(metrics.lapDistance))
                    .font(.metric(15, weight: .semibold))
                    .foregroundStyle(WatchTheme.textSecondary)
                Text(WatchFormat.units.distanceUnit)
                    .font(.watch(9))
                    .foregroundStyle(WatchTheme.textSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .padding(WatchDisplay.spacing(8))
        .watchPanel(fill: WatchTheme.accent.opacity(0.14))
    }

    private func lapRow(_ lap: WatchLap) -> some View {
        HStack(spacing: WatchDisplay.spacing(6)) {
            Text("\(lap.index)")
                .font(.metric(13, weight: .bold))
                .foregroundStyle(WatchTheme.textSecondary)
                .frame(width: WatchDisplay.scaled(16, atLeast: 13), alignment: .leading)

            VStack(alignment: .leading, spacing: -1) {
                Text(WatchFormat.duration(lap.duration))
                    .font(.metric(15, weight: .semibold))
                    .foregroundStyle(WatchTheme.textPrimary)
                Text("\(WatchFormat.distance(lap.distance)) \(WatchFormat.units.distanceUnit)")
                    .font(.watch(9))
                    .foregroundStyle(WatchTheme.textSecondary)
            }
            .lineLimit(1)

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: -1) {
                Text(usesPace ? WatchFormat.pace(lap.pace) : WatchFormat.speed(lap.distance / max(1, lap.duration)))
                    .font(.metric(14, weight: .semibold))
                    .foregroundStyle(WatchTheme.highlight)
                if lap.averageHeartRate > 0 {
                    Text("\(WatchFormat.integer(lap.averageHeartRate)) bpm")
                        .font(.watch(9))
                        .foregroundStyle(WatchTheme.zoneColor(LiveMetrics.zone(for: lap.averageHeartRate)))
                }
            }
            .lineLimit(1)
        }
        .padding(.vertical, WatchDisplay.spacing(6))
        .padding(.horizontal, WatchDisplay.spacing(8))
        .watchPanel()
        .accessibilityElement(children: .combine)
    }
}
