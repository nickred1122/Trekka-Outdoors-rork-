import SwiftUI
import WidgetKit

nonisolated struct InsightEntry: TimelineEntry {
    let date: Date
    /// `nil` when the phone has nothing measured to say yet.
    let snapshot: InsightFace.Snapshot?
}

nonisolated struct InsightProvider: TimelineProvider {
    func placeholder(in context: Context) -> InsightEntry {
        InsightEntry(
            date: .now,
            snapshot: InsightFace.Snapshot(
                lines: [
                    InsightFace.Line(
                        id: "volume",
                        title: "This week",
                        detail: "4h 20m across 5 sessions — up 40m on the week before",
                        symbol: "figure.run",
                        tone: .positive
                    ),
                    InsightFace.Line(
                        id: "hrv",
                        title: "HRV",
                        detail: "62 ms, on your 60 ms baseline",
                        symbol: "waveform.path.ecg",
                        tone: .positive
                    ),
                ],
                updatedAt: .now
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (InsightEntry) -> Void) {
        completion(InsightEntry(date: .now, snapshot: InsightFace.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<InsightEntry>) -> Void) {
        let entry = InsightEntry(date: .now, snapshot: InsightFace.load())
        // The app reloads this itself whenever the figures change, so the
        // background cadence only has to cover the hours the app is not opened.
        let next = Calendar.current.date(byAdding: .hour, value: 2, to: .now)
            ?? .now.addingTimeInterval(7_200)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

/// A home-screen widget carrying what Trekka has measured about your training.
///
/// It shows the same observations the app shows, already worded and already in
/// your units — the widget works nothing out for itself, so it can never
/// disagree with the app about a number.
struct SummitInsightWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: InsightFace.widgetKind, provider: InsightProvider()) { entry in
            InsightWidgetView(entry: entry)
                .containerBackground(for: .widget) { LiveTheme.canvas }
        }
        .configurationDisplayName("Training Insights")
        .description("What your own training data says, measured from your recorded workouts.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct InsightWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: InsightEntry

    /// How many observations this size can carry without becoming wallpaper.
    private var lineLimit: Int {
        switch family {
        case .systemLarge: 3
        case .systemMedium: 2
        default: 1
        }
    }

    var body: some View {
        if let snapshot = entry.snapshot, !snapshot.lines.isEmpty {
            content(Array(snapshot.lines.prefix(lineLimit)))
        } else {
            empty
        }
    }

    private func content(_ lines: [InsightFace.Line]) -> some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 9) {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(LiveTheme.accent)
                Text("TREKKA")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(LiveTheme.label.opacity(0.5))
                Spacer(minLength: 0)
            }

            ForEach(lines) { line in
                row(line)
                if line.id != lines.last?.id {
                    Rectangle()
                        .fill(LiveTheme.label.opacity(0.12))
                        .frame(height: 1)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func row(_ line: InsightFace.Line) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: line.symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint(line.tone))
                Text(line.title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LiveTheme.label)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Text(line.detail)
                .font(.system(size: family == .systemSmall ? 10 : 11, weight: .medium))
                .foregroundStyle(LiveTheme.label.opacity(0.7))
                .lineLimit(family == .systemSmall ? 3 : 3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(LiveTheme.accent)
            Text("Nothing measured yet")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(LiveTheme.label)
            Text("Record a workout or connect Apple Health.")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(LiveTheme.label.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func tint(_ tone: InsightFace.Tone) -> Color {
        switch tone {
        case .positive: LiveTheme.positive
        case .neutral: LiveTheme.accent
        case .caution: LiveTheme.paused
        }
    }
}
