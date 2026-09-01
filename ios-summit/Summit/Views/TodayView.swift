import SwiftUI

/// Destinations reachable from the Today dashboard.
nonisolated enum DashboardDestination: Hashable, Sendable {
    case metric(DashboardMetric)
    case readiness
    case zones
    case trainingLoad
}

struct TodayView: View {
    @Environment(RouteStore.self) private var store
    @Environment(HealthService.self) private var health
    @Environment(DashboardSettings.self) private var settings
    @Environment(AppearanceSettings.self) private var appearance
    @Environment(WatchLayoutStore.self) private var watchLayout
    @Binding var pendingWorkoutRoute: PlannedRoute?
    @Binding var showsWorkout: Bool

    @State private var showsHealthSheet = false
    @State private var showsCustomizeSheet = false
    @State private var showsWatchSheet = false
    @State private var tileFeedback = 0
    /// Built off the main actor, because a year of sessions through two
    /// exponential averages is not free.
    @State private var load: TrainingLoadModel?

    private var snapshot: HealthSnapshot { health.snapshot }

    private var allActivities: [ActivityRecord] {
        (store.recentActivities + health.healthActivities).sorted { $0.startDate > $1.startDate }
    }

    /// What every tile is scoped to: a rolling preset, or the exact dates picked.
    private var window: MetricWindow {
        settings.window(endingOn: Date(), allowing: availableRanges)
    }

    /// A year back is as far as the stored history reaches.
    private var earliestDay: Date {
        let calendar = Calendar.current
        return calendar.date(
            byAdding: .day,
            value: -(MetricSeries.historyDayCount - 1),
            to: calendar.startOfDay(for: Date())
        ) ?? Date()
    }

    private func samples(for metric: DashboardMetric) -> [MetricSample] {
        MetricSeries.samples(
            metric: metric,
            window: window,
            history: health.history(for: window.hourlyDay ?? Date()),
            activities: allActivities
        )
    }

    private var zoneMinutes: [Double] {
        let fromStore = store.weeklyZoneMinutes
        if fromStore.contains(where: { $0 > 0 }) { return fromStore }
        return snapshot.zoneMinutes
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header

                if settings.showsReadinessRing {
                    readinessLink
                }

                if health.authorization != .authorized {
                    healthConnectCard
                } else if !health.hasHealthData && !health.isLoading {
                    healthEmptyCard
                }

                rangeRow

                metricGrid

                if !settings.hasExploredMetrics && !settings.visibleMetrics.isEmpty {
                    hintRow
                }

                if settings.showsZoneChart {
                    NavigationLink(value: DashboardDestination.zones) {
                        ZoneBars(minutes: zoneMinutes)
                    }
                    .buttonStyle(TilePressStyle())
                }

                if let load, load.isReady {
                    NavigationLink(value: DashboardDestination.trainingLoad) {
                        trainingLoadCard(load)
                    }
                    .buttonStyle(TilePressStyle())
                }

                startWorkoutCard

                if settings.showsRecentActivity, let latest = store.latestActivity {
                    recentActivityCard(latest)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, TabBarMetrics.scrollInset)
        }
        .background(Theme.canvas)
        .scrollIndicators(.hidden)
        .refreshable { await health.refresh() }
        // An hourly breakdown of a past day is pulled from Health on demand.
        .task(id: window) {
            guard let day = window.hourlyDay else { return }
            await health.loadDay(day)
        }
        .task(id: allActivities.count) { await rebuildLoad() }
        .sensoryFeedback(.selection, trigger: tileFeedback)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsWatchSheet = true
                } label: {
                    Image(systemName: "applewatch")
                }
                .accessibilityLabel("Apple Watch screens")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsCustomizeSheet = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Customize dashboard")
            }
        }
        .sheet(isPresented: $showsHealthSheet) {
            HealthAccessSheet()
        }
        .sheet(isPresented: $showsCustomizeSheet) {
            CustomizeDashboardView()
        }
        .sheet(isPresented: $showsWatchSheet) {
            NavigationStack {
                WatchSetupView()
            }
            .preferredColorScheme(appearance.colorScheme)
        }
    }

    private func rebuildLoad() async {
        let activities = allActivities
        let maximum = Double(watchLayout.maxHeartRate)
        let resting = snapshot.restingHeartRate
        load = await Task.detached(priority: .utility) {
            TrainingLoadModel.build(
                from: activities,
                maxHeartRate: maximum,
                restingHeartRate: resting
            )
        }.value
    }

    /// Fitness and form at a glance, opening the full picture when tapped.
    private func trainingLoadCard(_ model: TrainingLoadModel) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Training load")
                    .metricLabelStyle()
                Text(model.state.title)
                    .font(.system(.headline, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Fitness \(Int(model.fitness.rounded())) · Form \(model.form > 0 ? "+" : "")\(Int(model.form.rounded()))")
                    .font(.metric(12))
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
            }
            Spacer(minLength: 0)
            Sparkline(
                values: model.recent(60).map(\.fitness),
                color: Theme.accent
            )
            .frame(width: 96, height: 34)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.textPrimary.opacity(0.3))
        }
        .padding(14)
        .panel()
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(Date.now, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .font(.system(.headline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(healthStatusLine)
                    .font(.caption)
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
            }
            Spacer()
            Button {
                showsHealthSheet = true
            } label: {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.textPrimary.opacity(0.8))
            }
            .accessibilityLabel("Health data settings")
        }
        .padding(.top, 8)
    }

    private var readinessLink: some View {
        NavigationLink(value: DashboardDestination.readiness) {
            VStack(spacing: 2) {
                ReadinessRing(score: snapshot.readiness, caption: snapshot.readinessCaption)
                Label("See what moved it", systemImage: "chevron.right")
                    .font(.system(.caption, weight: .semibold))
                    .labelStyle(TrailingIconLabelStyle())
                    .foregroundStyle(Theme.textPrimary.opacity(0.45))
            }
            .padding(.bottom, 4)
        }
        .buttonStyle(TilePressStyle())
    }

    /// Says where the numbers stand without overstating the connection.
    private var healthStatusLine: String {
        if health.hasHealthData { return "Synced with Apple Health" }
        return health.authorization == .authorized ? "No Health data readable yet" : "Connect Apple Health"
    }

    /// Access has been answered, but nothing came back. HealthKit never says
    /// whether reading was refused, so the app points at the one place that can.
    private var healthEmptyCard: some View {
        Button {
            showsHealthSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "heart.text.square")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.highlight)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No Health data to read")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Check Trekka Outdoors under Sharing in the Health app")
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.35))
            }
            .padding(14)
            .panel()
        }
        .buttonStyle(.plain)
    }

    private var healthConnectCard: some View {
        Button {
            showsHealthSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect Apple Health")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Pull sleep, HRV, VO₂ max and workouts")
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.35))
            }
            .padding(14)
            .panel()
        }
        .buttonStyle(.plain)
    }

    /// Ranges the dashboard has enough recorded history to justify, measured
    /// against the deepest history any visible tile holds.
    private var availableRanges: [MetricRange] {
        MetricRange.available(
            forDays: MetricSeries.coverageDays(
                metrics: settings.visibleMetrics,
                history: health.history,
                activities: allActivities
            )
        )
    }

    @ViewBuilder
    private var rangeRow: some View {
        @Bindable var settings = settings
        MetricWindowBar(
            range: $settings.chartRange,
            span: $settings.chartSpan,
            ranges: availableRanges,
            caption: window.caption,
            earliest: earliestDay
        )
    }

    @ViewBuilder
    private var metricGrid: some View {
        let metrics = settings.visibleMetrics
        if metrics.isEmpty {
            Button {
                showsCustomizeSheet = true
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 26))
                        .foregroundStyle(Theme.accent)
                    Text("No tiles on your dashboard")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Add the metrics you actually train by")
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .panel()
            }
            .buttonStyle(TilePressStyle())
        } else {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: TileMetrics.minimumWidth), spacing: 12)],
                spacing: 12
            ) {
                ForEach(metrics) { metric in
                    tile(for: metric)
                }
            }
        }
    }

    @ViewBuilder
    private func tile(for metric: DashboardMetric) -> some View {
        let window = window
        let series = samples(for: metric)
        let headline = MetricSeries.headline(metric: metric, window: window, samples: series)
        NavigationLink(value: DashboardDestination.metric(metric)) {
            MetricTile(
                glyph: metric.glyph,
                symbolColor: metric.tint,
                label: metric.title,
                value: metric.valueText(headline),
                unit: headline > 0 ? metric.unitText : nil,
                samples: series,
                trendColor: metric.tint,
                deltaUp: MetricSeries.deltaUp(series),
                caption: metric.headlineCaption(for: window),
                showsSparkline: settings.showsTileCharts
            )
        }
        .buttonStyle(TilePressStyle())
        .contextMenu {
            Button {
                settings.moveToTop(metric)
                tileFeedback += 1
            } label: {
                Label("Move to top", systemImage: "arrow.up.to.line")
            }
            Button {
                settings.hide(metric)
                tileFeedback += 1
            } label: {
                Label("Hide tile", systemImage: "eye.slash")
            }
            Button {
                showsCustomizeSheet = true
            } label: {
                Label("Customize dashboard", systemImage: "slider.horizontal.3")
            }
        }
    }

    private var hintRow: some View {
        Label("Tap a tile for the full breakdown · long-press to switch bars and lines", systemImage: "hand.tap.fill")
            .font(.caption2)
            .foregroundStyle(Theme.textPrimary.opacity(0.45))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
            .transition(.opacity)
    }

    private var startWorkoutCard: some View {
        Button {
            pendingWorkoutRoute = nil
            showsWorkout = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "location.north.line.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.canvas)
                    .frame(width: 38, height: 38)
                    .background(Theme.accent, in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start workout")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Track pace, elevation and zones live")
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.35))
            }
            .padding(14)
            .panel()
        }
        .buttonStyle(TilePressStyle())
    }

    private func recentActivityCard(_ activity: ActivityRecord) -> some View {
        NavigationLink(value: activity) {
            HStack(spacing: 14) {
                Group {
                    if activity.track.count > 1 {
                        RouteThumbnail(points: activity.track)
                    } else {
                        // Workouts read from Health arrive without a track, so
                        // the tile names the activity instead of drawing one.
                        Text(activity.activity.rawValue.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(Theme.accent.opacity(0.7))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Theme.surfaceRaised)
                    }
                }
                .frame(width: 92, height: 78)
                .clipShape(.rect(cornerRadius: 12))
                .overlay(alignment: .bottomLeading) {
                    if activity.elevationGain > 0 {
                        Label("\(Formatters.elevation(activity.elevationGain)) m", systemImage: "triangle.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .background(Theme.mapControl, in: .rect(cornerRadius: 5))
                            .padding(6)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(activity.name)
                        .font(.system(.headline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(summary(for: activity))
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.35))
            }
            .padding(12)
            .panel()
        }
        .buttonStyle(TilePressStyle())
    }

    private func summary(for activity: ActivityRecord) -> String {
        let relative = activity.startDate.formatted(.relative(presentation: .named))
        return "\(relative.capitalized) · \(Formatters.distance(activity.distance)) km · \(Formatters.duration(activity.duration)) · \(Formatters.elevation(activity.elevationGain)) m ↑"
    }
}

/// Places the icon after the title, used for inline "drill in" affordances.
struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
                .font(.system(size: 10, weight: .bold))
        }
    }
}
