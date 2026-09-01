import SwiftUI
import WidgetKit

nonisolated struct PowerEntry: TimelineEntry {
    let date: Date
    let snapshot: PowerFace.Snapshot

    /// Whatever the watch last measured, or `--` if it has not measured yet.
    var remainingLabel: String {
        PowerBudget.label(hours: snapshot.projectedHours)
    }

    var hasProjection: Bool { snapshot.projectedHours != nil }

    var batteryPercent: Int {
        Int((min(max(snapshot.batteryFraction, 0), 1) * 100).rounded())
    }
}

nonisolated struct PowerProvider: TimelineProvider {
    func placeholder(in context: Context) -> PowerEntry {
        PowerEntry(date: .now, snapshot: PowerFace.Snapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (PowerEntry) -> Void) {
        completion(PowerEntry(date: .now, snapshot: PowerFace.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PowerEntry>) -> Void) {
        let entry = PowerEntry(date: .now, snapshot: PowerFace.load())
        // The app reloads this timeline whenever the picture actually changes,
        // so a slow background cadence is enough on its own.
        let next = Calendar.current.date(byAdding: .minute, value: 20, to: .now) ?? .now.addingTimeInterval(1200)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

/// A watch-face complication that shows how long Summit can keep recording and
/// arms power saver with one tap.
struct SummitPowerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PowerFace.widgetKind, provider: PowerProvider()) { entry in
            PowerComplicationView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Power Saver")
        .description("Recording time left, and a one-tap power saver switch.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryRectangular,
            .accessoryInline,
        ])
    }
}

struct PowerComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PowerEntry

    private var isSaving: Bool { entry.snapshot.isPowerSaving }

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular
        case .accessoryCorner:
            corner
        case .accessoryRectangular:
            rectangular
        default:
            inline
        }
    }

    /// One tap flips power saver. The ring is the charge, the glyph is the mode.
    private var circular: some View {
        Button(intent: TogglePowerSaverIntent()) {
            ZStack {
                Gauge(value: min(max(entry.snapshot.batteryFraction, 0), 1)) {
                    Image(systemName: isSaving ? "leaf.fill" : "bolt.fill")
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(isSaving ? WidgetTheme.positive : WidgetTheme.accent)
            }
        }
        .buttonStyle(.plain)
        .widgetAccentable()
    }

    private var corner: some View {
        Image(systemName: isSaving ? "leaf.fill" : "bolt.fill")
            .font(.system(size: 16, weight: .bold))
            .widgetLabel {
                Text(entry.hasProjection
                     ? "\(entry.remainingLabel) · \(entry.batteryPercent)%"
                     : "\(entry.batteryPercent)%")
            }
    }

    private var rectangular: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(isSaving ? "POWER SAVER" : entry.snapshot.sportTitle.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .lineLimit(1)
                    .widgetAccentable()
                // With no measured drain there is nothing honest to project, so
                // the charge itself becomes the headline rather than a made-up
                // number of hours.
                Text(entry.hasProjection ? entry.remainingLabel : "\(entry.batteryPercent)%")
                    .font(.summitMetric(20))
                    .lineLimit(1)
                Text(entry.hasProjection
                     ? "\(entry.batteryPercent)% · \(isSaving ? "saving" : "full power")"
                     : (isSaving ? "power saver" : "full power"))
                    .font(.system(size: 10))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button(intent: TogglePowerSaverIntent()) {
                Image(systemName: isSaving ? "leaf.fill" : "leaf")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(.fill.tertiary, in: .circle)
            }
            .buttonStyle(.plain)
        }
    }

    private var inline: some View {
        Label(
            entry.hasProjection
                ? "\(entry.remainingLabel) left\(isSaving ? " · saver" : "")"
                : "\(entry.batteryPercent)%\(isSaving ? " · saver" : "")",
            systemImage: isSaving ? "leaf.fill" : "bolt.fill"
        )
    }
}
