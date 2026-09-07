import SwiftUI

/// Where daily targets are set: one card per goal, each with today's progress
/// against it.
///
/// Nothing is switched on until the athlete switches it on, and every goal can
/// be turned off again without losing the number it was set to.
struct DailyGoalsView: View {
    @Environment(GoalSettings.self) private var goals
    @Environment(HealthService.self) private var health
    @Environment(RouteStore.self) private var store

    /// Opened straight onto one goal from a metric screen, so the right card is
    /// the first thing in view.
    var focused: DashboardMetric?

    @State private var feedback = 0

    private var activities: [ActivityRecord] {
        (store.recentActivities + health.healthActivities).sorted { $0.startDate > $1.startDate }
    }

    private var progress: [DashboardMetric: GoalProgress] {
        let resolved = DailyGoalEngine.progress(
            goals: goals.snapshot,
            snapshot: health.snapshot,
            activities: activities
        )
        return Dictionary(uniqueKeysWithValues: resolved.map { ($0.metric, $0) })
    }

    var body: some View {
        let progress = progress
        ScrollViewReader { scroll in
            ScrollView {
                VStack(spacing: 12) {
                    intro

                    ForEach(DashboardMetric.goalCapable) { metric in
                        goalCard(metric, progress: progress[metric])
                            .id(metric)
                    }

                    footnote
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 28)
            }
            // Opened from a metric screen, the goal being asked about is put in
            // view rather than leaving it to be hunted for down the list.
            .onAppear {
                guard let focused else { return }
                scroll.scrollTo(focused, anchor: .top)
            }
        }
        .background(Theme.canvas)
        .scrollIndicators(.hidden)
        .navigationTitle("Daily goals")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.canvas, for: .navigationBar)
        .sensoryFeedback(.selection, trigger: feedback)
        .toolbar {
            if !goals.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear all", role: .destructive) {
                        goals.clearAll()
                        feedback += 1
                    }
                    .font(.system(.subheadline, weight: .semibold))
                }
            }
        }
    }

    // MARK: - Sections

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(goals.isEmpty ? "No goals set" : "\(goals.metricsWithGoals.count) goal\(goals.metricsWithGoals.count == 1 ? "" : "s") set")
                .font(.system(.headline, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("A goal shows as a progress bar on its dashboard tile and on your watch. Trekka measures against what Apple Health and your recorded workouts actually say — it never fills in a day you did not record.")
                .font(.caption)
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .panel()
    }

    private func goalCard(_ metric: DashboardMetric, progress: GoalProgress?) -> some View {
        let isOn = goals.hasGoal(for: metric)
        let target = goals.target(for: metric) ?? metric.defaultGoalTarget

        return VStack(alignment: .leading, spacing: isOn ? 14 : 0) {
            HStack(spacing: 12) {
                TrekkaIcon(metric.glyph, size: 15, tint: metric.tint)
                    .frame(width: 34, height: 34)
                    .background(metric.tint.opacity(0.12), in: .rect(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(metric.title)
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(isOn ? metric.goalSummary(target) : "No goal")
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 0)

                Toggle("", isOn: Binding(
                    get: { isOn },
                    set: { _ in
                        goals.toggle(metric)
                        feedback += 1
                    }
                ))
                .labelsHidden()
                .tint(Theme.accent)
            }

            if isOn {
                targetEditor(metric, target: target)

                if let progress {
                    todayRow(progress)
                }

                Text(metric.goalExplainer)
                    .font(.caption2)
                    .foregroundStyle(Theme.textPrimary.opacity(0.42))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .panel()
        .animation(.snappy(duration: 0.28), value: isOn)
    }

    private func targetEditor(_ metric: DashboardMetric, target: Double) -> some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(metric.valueText(target))
                    .font(.metric(30))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                if let unit = metric.unitText {
                    Text(unit)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                }
                Spacer(minLength: 0)
            }

            Slider(
                value: Binding(
                    get: { target },
                    set: { goals.setTarget($0, for: metric) }
                ),
                in: metric.goalRange,
                step: metric.goalStep
            )
            .tint(metric.tint)
        }
    }

    private func todayRow(_ progress: GoalProgress) -> some View {
        VStack(spacing: 8) {
            GoalBar(progress: progress, tint: progress.metric.tint, showsCaption: false)

            HStack(spacing: 10) {
                Text(progress.progressText)
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(progress.isMet ? Theme.positive : Theme.textPrimary.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                if progress.streak > 0 {
                    Label("\(progress.streak) day\(progress.streak == 1 ? "" : "s")", systemImage: "flame.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.highlight)
                }
                Text("\(progress.daysMetThisWeek)/7")
                    .font(.metric(12))
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
            }
        }
        .padding(.vertical, 2)
    }

    private var footnote: some View {
        Text("Goals travel to your Apple Watch with the rest of your dashboard, and a steps goal can sit on your watch face as a complication.")
            .font(.caption2)
            .foregroundStyle(Theme.textPrimary.opacity(0.42))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}
