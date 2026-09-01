import SwiftUI

/// Live heart-rate zone page: current bpm, the zone you are sitting in, and
/// accumulated time in each of the five zones.
struct ZonePageView: View {
    let metrics: LiveMetrics

    private var totalSeconds: TimeInterval {
        max(1, metrics.zoneSeconds.reduce(0, +))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WatchDisplay.spacing(8)) {
            HStack(alignment: .firstTextBaseline, spacing: WatchDisplay.spacing(6)) {
                Text(metrics.heartRate > 0 ? WatchFormat.integer(metrics.heartRate) : "--")
                    .font(.metric(38, weight: .bold))
                    .foregroundStyle(metrics.heartRate > 0 ? WatchTheme.zoneColor(metrics.heartRateZone) : WatchTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                VStack(alignment: .leading, spacing: -2) {
                    Text("BPM")
                        .fieldLabelStyle()
                    Text("Zone \(metrics.heartRateZone)")
                        .font(.watch(11, weight: .bold))
                        .foregroundStyle(WatchTheme.zoneColor(metrics.heartRateZone))
                }
                Spacer(minLength: 0)
                if metrics.isHeartRateEstimated {
                    Text("EST")
                        .font(.watch(8, weight: .heavy))
                        .foregroundStyle(WatchTheme.highlight)
                }
            }

            Text(zoneCaption)
                .font(.watch(10, weight: .medium))
                .foregroundStyle(WatchTheme.textSecondary)
                // The caption is the first thing worth losing when the five zone
                // bars need the room.
                .lineLimit(WatchDisplay.isCompact ? 1 : 2)
                .minimumScaleFactor(0.75)

            VStack(spacing: WatchDisplay.spacing(5)) {
                ForEach(1...5, id: \.self) { zone in
                    ZoneRow(
                        zone: zone,
                        seconds: metrics.zoneSeconds[zone - 1],
                        fraction: metrics.zoneSeconds[zone - 1] / totalSeconds,
                        isCurrent: metrics.heartRate > 0 && metrics.heartRateZone == zone
                    )
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var zoneCaption: String {
        let range = LiveMetrics.zoneRange(metrics.heartRateZone)
        let name: String
        switch metrics.heartRateZone {
        case 1: name = "Recovery"
        case 2: name = "Aerobic base"
        case 3: name = "Tempo"
        case 4: name = "Threshold"
        default: name = "VO₂ max"
        }
        return "\(name) · \(range.lowerBound)-\(range.upperBound) bpm"
    }
}
