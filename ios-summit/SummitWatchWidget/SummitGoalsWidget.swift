import SwiftUI
import WidgetKit

nonisolated struct GoalEntry: TimelineEntry {
    let date: Date
    /// `nil` when no goal has been set on the phone yet.
    let snapshot: GoalsFace.Snapshot?
}

nonisolated struct GoalProvider: TimelineProvider {
    func placeholder(in context: Context) -> GoalEntry {
        GoalEntry(
            date: .now,
            snapshot: GoalsFace.Snapshot(
                metric: "steps",
                title: "Steps",
                symbol: "shoeprints.fill",
                valueText: "6,240",
                targetText: "10,000",
                fraction: 0.62,
                streak: 3,
                updatedAt: .now
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (GoalEntry) -> Void) {
        completion(GoalEntry(date: .now, snapshot: GoalsFace.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GoalEntry>) -> Void) {
        let entry = GoalEntry(date: .now, snapshot: GoalsFace.load())
        // The watch reloads this the moment a fresh dashboard lands from the
        // phone, so the background cadence only has to catch the quiet hours.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

/// A watch-face complication showing today against your first daily goal.
struct SummitGoalsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: GoalsFace.widgetKind, provider: GoalProvider()) { entry in
            GoalComplicationView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Daily Goal")
        .description("Today against your daily goal, from your iPhone dashboard.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryRectangular,
            .accessoryInline,
        ])
    }
}

struct GoalComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GoalEntry

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

    private var circular: some View {
        Gauge(value: entry.snapshot?.fraction ?? 0) {
            Image(systemName: entry.snapshot?.symbol ?? "target")
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(entry.snapshot?.isMet == true ? WidgetTheme.positive : WidgetTheme.accent)
        .widgetAccentable()
    }

    private var corner: some View {
        Image(systemName: entry.snapshot?.symbol ?? "target")
            .font(.system(size: 16, weight: .bold))
            .widgetLabel {
                // With no goal set there is no ring to fill and nothing to
                // count, so the complication says so instead of showing a zero.
                if let snapshot = entry.snapshot {
                    Gauge(value: snapshot.fraction) {
                        Text(snapshot.title)
                    } currentValueLabel: {
                        Text(snapshot.valueText)
                    }
                    .tint(snapshot.isMet ? WidgetTheme.positive : WidgetTheme.accent)
                } else {
                    Text("No goal set")
                }
            }
    }

    private var rectangular: some View {
        HStack(spacing: 8) {
            if let snapshot = entry.snapshot {
                VStack(alignment: .leading, spacing: 1) {
                    Text(snapshot.title.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .lineLimit(1)
                        .widgetAccentable()
                    Text(snapshot.valueText)
                        .font(.summitMetric(20))
                        .lineLimit(1)
                    Text(caption(for: snapshot))
                        .font(.system(size: 10))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Gauge(value: snapshot.fraction) {
                    Image(systemName: snapshot.symbol)
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(snapshot.isMet ? WidgetTheme.positive : WidgetTheme.accent)
                .scaleEffect(0.72)
                .frame(width: 34, height: 34)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text("DAILY GOAL")
                        .font(.system(size: 11, weight: .bold))
                        .widgetAccentable()
                    Text("Not set")
                        .font(.summitMetric(18))
                    Text("Set one in Trekka on iPhone")
                        .font(.system(size: 10))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func caption(for snapshot: GoalsFace.Snapshot) -> String {
        guard !snapshot.isMet else {
            return snapshot.streak > 1 ? "Done · \(snapshot.streak) days" : "Goal met"
        }
        return "of \(snapshot.targetText)"
    }

    private var inline: some View {
        Label(
            entry.snapshot.map { "\($0.valueText) of \($0.targetText)" } ?? "No goal set",
            systemImage: entry.snapshot?.symbol ?? "target"
        )
    }
}
