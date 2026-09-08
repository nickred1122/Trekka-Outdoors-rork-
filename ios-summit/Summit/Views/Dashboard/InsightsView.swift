import SwiftUI

/// Everything Trekka can honestly say about this athlete's training, in one
/// place.
///
/// The dashboard shows a handful of observations because it has a dashboard's
/// worth of room. This is the screen for the whole picture: today against the
/// goals, the week's training, recovery, fuel, and what the most recent sessions
/// said about themselves.
///
/// Nothing here is estimated. Every line is arithmetic on recorded workouts and
/// Apple Health, and an observation only appears when the data behind it exists.
struct InsightsView: View {
    @Environment(RouteStore.self) private var store
    @Environment(HealthService.self) private var health
    @Environment(NutritionStore.self) private var nutrition
    @Environment(GoalSettings.self) private var goals
    @Environment(ProfileSettings.self) private var profile

    @State private var intelligence = IntelligenceService()

    private var allActivities: [ActivityRecord] {
        (store.activities + health.healthActivities).sorted { $0.startDate > $1.startDate }
    }

    private var snapshot: HealthSnapshot { health.snapshot }

    /// The week as a whole: goals, volume, consistency, recovery, fuel.
    private var overview: [TrainingInsight] {
        InsightEngine.insights(
            activities: allActivities,
            snapshot: snapshot,
            day: nutrition.day(Date()),
            fuelGoals: nutrition.goals,
            dailyGoals: goals.snapshot
        )
    }

    /// The most recent sessions that had something to say about themselves.
    ///
    /// Capped at three, because this is a summary of what is worth reopening —
    /// not a second copy of the activity list.
    private var sessionHighlights: [SessionHighlight] {
        let history = allActivities
        var found: [SessionHighlight] = []

        for activity in history.prefix(12) {
            let insights = ActivityInsightEngine.insights(for: activity, history: history)
            // Only the sessions that produced a real comparison, not the ones
            // still building a baseline.
            let notable = insights.filter { $0.id != "session.baseline" && $0.tone != .neutral }
            guard let best = notable.first else { continue }
            found.append(SessionHighlight(activity: activity, insight: best))
            if found.count == 3 { break }
        }
        return found
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if overview.isEmpty && sessionHighlights.isEmpty {
                    emptyState
                } else {
                    if !overview.isEmpty {
                        overviewCard
                    }
                    if !sessionHighlights.isEmpty {
                        highlightsCard
                    }
                    sourceNote
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, TabBarMetrics.scrollInset)
        }
        .background(Theme.canvas)
        .scrollIndicators(.hidden)
        .refreshable { await health.refresh() }
    }

    // MARK: - Overview

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text(profile.possessive("training"))
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }

            if intelligence.isWorking {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.accent)
                    Text("Writing a summary on your iPhone…")
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                    Spacer(minLength: 0)
                }
            } else if let summary = intelligence.summary {
                Text(summary)
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }

            InsightRows(insights: overview)
        }
        .padding(16)
        .panel()
        .animation(.snappy(duration: 0.3), value: intelligence.summary)
        .task {
            intelligence.refreshAvailability()
            await intelligence.summarise(facts: overview.map(\.fact), name: profile.firstName)
        }
    }

    // MARK: - Sessions

    private var highlightsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "figure.run")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text("Recent sessions")
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
            }

            VStack(spacing: 8) {
                ForEach(sessionHighlights) { highlight in
                    NavigationLink(value: highlight.activity) {
                        highlightRow(highlight)
                    }
                    .buttonStyle(TilePressStyle())
                }
            }
        }
        .padding(16)
        .panel()
    }

    private func highlightRow(_ highlight: SessionHighlight) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: highlight.insight.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(InsightTint.color(highlight.insight.tone))
                .frame(width: 28, height: 28)
                .background(
                    InsightTint.color(highlight.insight.tone).opacity(0.12),
                    in: .rect(cornerRadius: 8)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(highlight.activity.name)
                    .font(.system(.caption, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(highlight.insight.detail)
                    .font(.caption)
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Text(highlight.activity.startDate.formatted(.relative(presentation: .named)).capitalized)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.4))
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.textPrimary.opacity(0.3))
                .padding(.top, 8)
        }
        .padding(10)
        .background(Theme.surface, in: .rect(cornerRadius: 10))
    }

    // MARK: - Supporting

    private var sourceNote: some View {
        Text("Every figure here is measured from your recorded workouts and Apple Health. Comparisons are against your own history, never anybody else's.")
            .font(.caption2)
            .foregroundStyle(Theme.textPrimary.opacity(0.4))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.accent.opacity(0.7))
            Text("Nothing to say yet")
                .font(.system(.headline, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Record a workout or connect Apple Health, and Trekka starts measuring your training against itself.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .panel()
    }
}

/// One recent session worth reopening, and the reason why.
private struct SessionHighlight: Identifiable {
    let activity: ActivityRecord
    let insight: TrainingInsight

    var id: UUID { activity.id }
}
