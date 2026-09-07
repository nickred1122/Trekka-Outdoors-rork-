import SwiftUI

/// What the athlete's own week says, with an optional written summary on top.
///
/// The figures are computed and always shown. The summary paragraph is written
/// on the device by Apple Intelligence when the phone supports it, and is a
/// bonus layer — when it is missing, unavailable, or was discarded for quoting a
/// number that was not in the data, the card is still complete.
struct TrainingInsightsCard: View {
    let activities: [ActivityRecord]
    let snapshot: HealthSnapshot

    @Environment(NutritionStore.self) private var nutrition
    @Environment(GoalSettings.self) private var goals
    @Environment(ProfileSettings.self) private var profile
    @State private var intelligence = IntelligenceService()

    private var insights: [TrainingInsight] {
        InsightEngine.insights(
            activities: activities,
            snapshot: snapshot,
            day: nutrition.day(Date()),
            fuelGoals: nutrition.goals,
            dailyGoals: goals.snapshot
        )
    }

    var body: some View {
        // Nothing recorded means nothing honest to say, and an empty card is
        // worse than no card.
        if insights.isEmpty {
            EmptyView()
        } else {
            content(insights)
        }
    }

    private func content(_ insights: [TrainingInsight]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if intelligence.isWorking {
                writingRow
            } else if let summary = intelligence.summary {
                Text(summary)
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }

            VStack(spacing: 0) {
                ForEach(Array(insights.enumerated()), id: \.element.id) { index, insight in
                    if index > 0 {
                        Rectangle()
                            .fill(Theme.border)
                            .frame(height: 1)
                            .padding(.leading, 38)
                    }
                    row(insight)
                }
            }

            if let note = footnote {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(Theme.textPrimary.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .panel()
        .animation(.snappy(duration: 0.3), value: intelligence.summary)
        .animation(.snappy(duration: 0.3), value: intelligence.isWorking)
        .task {
            intelligence.refreshAvailability()
            await intelligence.summarise(facts: insights.map(\.fact), name: profile.firstName)
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)

            Text(profile.possessive("week"))
                .font(.system(.subheadline, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)

            if intelligence.availability.isReady && !intelligence.isWorking {
                Button {
                    Task {
                        await intelligence.summarise(
                            facts: insights.map(\.fact),
                            name: profile.firstName,
                            force: true
                        )
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.4))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Write the summary again")
            }
        }
    }

    private var writingRow: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(Theme.accent)
            Text("Writing a summary on your iPhone…")
                .font(.caption)
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
            Spacer(minLength: 0)
        }
    }

    private func row(_ insight: TrainingInsight) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: insight.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint(insight.tone))
                .frame(width: 28, height: 28)
                .background(tint(insight.tone).opacity(0.12), in: .rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(insight.title)
                    .font(.system(.caption, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(insight.detail)
                    .font(.caption)
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
    }

    private func tint(_ tone: InsightTone) -> Color {
        switch tone {
        case .positive: Theme.positive
        case .neutral: Theme.accent
        case .caution: Theme.highlight
        }
    }

    /// Says why there is no written summary, but only when that is worth saying.
    /// A phone that simply cannot run Apple Intelligence is not told repeatedly
    /// about a feature it will never have.
    private var footnote: String? {
        if intelligence.wasDiscarded {
            return "The written summary didn't match your figures, so it was discarded. The numbers above are measured."
        }
        if case .unavailable(let reason) = intelligence.availability,
           reason.contains("Apple Intelligence is still") || reason.contains("Turn on") {
            return reason
        }
        return nil
    }
}
