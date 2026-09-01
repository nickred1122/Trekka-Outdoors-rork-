import Charts
import SwiftUI

/// Fitness, fatigue and form, built from the workouts already recorded.
struct TrainingLoadView: View {
    @Environment(RouteStore.self) private var store
    @Environment(HealthService.self) private var health
    @Environment(WatchLayoutStore.self) private var layout

    @State private var model: TrainingLoadModel?
    @State private var range: LoadRange = .quarter

    /// How far back the chart looks.
    private enum LoadRange: String, CaseIterable, Identifiable {
        case month = "30d"
        case quarter = "90d"
        case year = "1y"

        var id: String { rawValue }

        var days: Int {
            switch self {
            case .month: 30
            case .quarter: 90
            case .year: 365
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let model, model.isReady {
                    headline(model)
                    chartCard(model)
                    numbersCard(model)
                    weekCard(model)
                    if model.isRampingHard { rampCard(model) }
                    honestyCard(model)
                } else if let model {
                    buildingCard(model)
                } else {
                    ProgressView()
                        .tint(Theme.accent)
                        .frame(maxWidth: .infinity, minHeight: 220)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, TabBarMetrics.scrollInset)
        }
        .background(Theme.canvas)
        .scrollIndicators(.hidden)
        .navigationTitle("Training load")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: activitySignature) { await rebuild() }
    }

    /// Rebuilds only when the history or the athlete's ceiling actually changes.
    private var activitySignature: String {
        "\(store.recentActivities.count)-\(health.healthActivities.count)-\(layout.maxHeartRate)"
    }

    private func rebuild() async {
        let activities = ActivityFeed.merged(store: store, health: health)
        let maximum = Double(layout.maxHeartRate)
        let resting = health.snapshot.restingHeartRate
        // A year of sessions run through two exponential averages is real work;
        // done off the main actor so the screen never stutters opening.
        model = await Task.detached(priority: .userInitiated) {
            TrainingLoadModel.build(
                from: activities,
                maxHeartRate: maximum,
                restingHeartRate: resting
            )
        }.value
    }

    // MARK: - Headline

    private func headline(_ model: TrainingLoadModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(stateColor(model.state).opacity(0.16))
                    Image(systemName: stateSymbol(model.state))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(stateColor(model.state))
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.state.title)
                        .font(.system(.title3, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Form \(signed(model.form))")
                        .font(.metric(13))
                        .foregroundStyle(stateColor(model.state))
                }
                Spacer(minLength: 0)
            }

            Text(model.state.detail)
                .font(.system(.subheadline))
                .foregroundStyle(Theme.textPrimary.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    // MARK: - Chart

    private func chartCard(_ model: TrainingLoadModel) -> some View {
        let days = model.recent(range.days)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Fitness and fatigue")
                    .metricLabelStyle()
                Spacer()
                Picker("Range", selection: $range) {
                    ForEach(LoadRange.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 168)
            }

            Chart {
                ForEach(days) { day in
                    // Daily stress as the faint ground the two lines sit on, so
                    // a hard session is visible as the cause of the fatigue
                    // spike that follows it.
                    BarMark(
                        x: .value("Day", day.date),
                        y: .value("Load", day.load)
                    )
                    .foregroundStyle(Theme.textPrimary.opacity(0.12))
                }
                ForEach(days) { day in
                    LineMark(
                        x: .value("Day", day.date),
                        y: .value("Fitness", day.fitness),
                        series: .value("Series", "Fitness")
                    )
                    .foregroundStyle(Theme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    .interpolationMethod(.monotone)
                }
                ForEach(days) { day in
                    LineMark(
                        x: .value("Day", day.date),
                        y: .value("Fatigue", day.fatigue),
                        series: .value("Series", "Fatigue")
                    )
                    .foregroundStyle(Theme.danger.opacity(0.85))
                    .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, dash: [4, 3]))
                    .interpolationMethod(.monotone)
                }
            }
            .chartLegend(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Theme.border)
                    AxisValueLabel()
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                }
            }
            .frame(height: 190)

            HStack(spacing: 14) {
                legendKey(color: Theme.accent, label: "Fitness", isDashed: false)
                legendKey(color: Theme.danger.opacity(0.85), label: "Fatigue", isDashed: true)
                legendKey(color: Theme.textPrimary.opacity(0.25), label: "Daily load", isDashed: false)
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .panel()
    }

    private func legendKey(color: Color, label: String, isDashed: Bool) -> some View {
        HStack(spacing: 5) {
            Capsule()
                .fill(color)
                .frame(width: isDashed ? 6 : 14, height: 3)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
        }
    }

    // MARK: - Numbers

    private func numbersCard(_ model: TrainingLoadModel) -> some View {
        HStack(spacing: 0) {
            figure("Fitness", value: rounded(model.fitness), tint: Theme.accent)
            divider
            figure("Fatigue", value: rounded(model.fatigue), tint: Theme.danger)
            divider
            figure("Form", value: signed(model.form), tint: stateColor(model.state))
        }
        .padding(.vertical, 14)
        .panel()
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(width: 1, height: 30)
    }

    private func figure(_ label: String, value: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.metric(22))
                .foregroundStyle(tint)
            Text(label)
                .metricLabelStyle()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - This week

    private func weekCard(_ model: TrainingLoadModel) -> some View {
        let thisWeek = model.weeklyLoad
        let lastWeek = model.previousWeeklyLoad
        let change = lastWeek > 0 ? (thisWeek - lastWeek) / lastWeek : 0

        return VStack(alignment: .leading, spacing: 10) {
            Text("This week")
                .metricLabelStyle()
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(rounded(thisWeek))
                    .font(.metric(26))
                    .foregroundStyle(Theme.textPrimary)
                if lastWeek > 0 {
                    Label(
                        "\(change > 0 ? "+" : "")\(Int((change * 100).rounded()))%",
                        systemImage: change >= 0 ? "arrow.up.right" : "arrow.down.right"
                    )
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(change > 0.35 ? Theme.danger : Theme.textPrimary.opacity(0.6))
                }
                Spacer(minLength: 0)
            }
            Text(
                lastWeek > 0
                    ? "Against \(rounded(lastWeek)) the week before."
                    : "No training the week before to compare against."
            )
            .font(.system(.footnote))
            .foregroundStyle(Theme.textPrimary.opacity(0.6))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    // MARK: - Warnings and honesty

    private func rampCard(_ model: TrainingLoadModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Fitness climbing fast", systemImage: "exclamationmark.triangle.fill")
                .font(.system(.subheadline, weight: .bold))
                .foregroundStyle(Theme.highlight)
            Text(
                "Your fitness is up \(rounded(model.weeklyRamp)) points in a week. Building faster than about five a week is the pattern that tends to end in an injury rather than a personal best."
            )
            .font(.system(.footnote))
            .foregroundStyle(Theme.textPrimary.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.highlight.opacity(0.1), in: .rect(cornerRadius: Theme.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(Theme.highlight.opacity(0.35), lineWidth: 1)
        }
    }

    private func honestyCard(_ model: TrainingLoadModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How this is worked out")
                .metricLabelStyle()
            Text(
                "Every session adds stress based on how long it lasted and how hard your heart was working. Fitness is a six-week average of that stress, fatigue is a one-week average, and form is the gap between them."
            )
            .font(.system(.footnote))
            .foregroundStyle(Theme.textPrimary.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)

            if model.sessionsWithoutHeartRate > 0 {
                Text(
                    "\(model.sessionsWithoutHeartRate) of your \(model.totalSessions) sessions had no heart rate recorded. Those are counted by duration alone rather than being given an intensity they cannot prove."
                )
                .font(.system(.footnote))
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
            }

            if health.snapshot.restingHeartRate <= 0 {
                Text(
                    "Your resting heart rate is not in Health yet, so the effort scale is anchored at half of your maximum instead of your own measured floor."
                )
                .font(.system(.footnote))
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private func buildingCard(_ model: TrainingLoadModel) -> some View {
        let days: Int = {
            if case .building(let soFar) = model.confidence { return soFar }
            return 0
        }()

        return VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.accent)
            Text("Still building your baseline")
                .font(.system(.headline, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text(
                days > 0
                    ? "Fitness is a six-week average, so it needs about a month of training behind it before it means anything. You have \(days) \(days == 1 ? "day" : "days") so far."
                    : "Record a few workouts and this will start to fill in. Fitness is a six-week average, so it needs about a month behind it before it means anything."
            )
            .font(.system(.subheadline))
            .multilineTextAlignment(.center)
            .foregroundStyle(Theme.textPrimary.opacity(0.65))
            .fixedSize(horizontal: false, vertical: true)

            if days > 0 {
                ProgressView(value: Double(days), total: Double(TrainingLoadConfidence.daysNeeded))
                    .tint(Theme.accent)
                    .padding(.top, 2)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .panel()
    }

    // MARK: - Formatting

    private func rounded(_ value: Double) -> String {
        String(Int(value.rounded()))
    }

    private func signed(_ value: Double) -> String {
        let whole = Int(value.rounded())
        return whole > 0 ? "+\(whole)" : "\(whole)"
    }

    private func stateColor(_ state: TrainingForm) -> Color {
        switch state {
        case .resting: Theme.textPrimary.opacity(0.6)
        case .fresh: Theme.positive
        case .steady: Theme.accent
        case .building: Theme.highlight
        case .overreaching: Theme.danger
        }
    }

    private func stateSymbol(_ state: TrainingForm) -> String {
        switch state {
        case .resting: "zzz"
        case .fresh: "bolt.fill"
        case .steady: "equal.circle.fill"
        case .building: "arrow.up.forward.circle.fill"
        case .overreaching: "exclamationmark.triangle.fill"
        }
    }
}
