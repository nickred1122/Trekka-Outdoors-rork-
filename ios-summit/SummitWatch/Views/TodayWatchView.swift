import SwiftUI

/// Destinations reachable from the watch's Today dashboard.
nonisolated enum TodayWatchRoute: Hashable, Sendable {
    case metric(String)
    case readiness
    case customize
    case activity(UUID)
    case settings
}

/// The phone's Today dashboard, on the wrist.
///
/// Readings are pushed from the phone, so the tiles show exactly the numbers
/// the iPhone shows — and rearranging them here rearranges them there too.
struct TodayWatchView: View {
    @Environment(WatchDashboardStore.self) private var dashboard
    @Environment(WatchGlanceService.self) private var glance

    var onStart: () -> Void

    private var readiness: Int {
        dashboard.snapshot?.readiness ?? glance.readiness
    }

    private var readinessCaption: String {
        dashboard.snapshot?.readinessCaption ?? glance.caption
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                header

                if dashboard.showsReadinessRing {
                    readinessTile
                }

                if dashboard.hasData {
                    metricGrid
                } else {
                    emptyState
                }

                if dashboard.showsZoneChart, dashboard.zoneMinutes.contains(where: { $0 > 0 }) {
                    NavigationLink(value: TodayWatchRoute.readiness) {
                        WatchZoneBars(minutes: dashboard.zoneMinutes)
                    }
                    .buttonStyle(.plain)
                }

                startButton

                if dashboard.showsRecentActivity, let latest = dashboard.activities.first {
                    NavigationLink(value: TodayWatchRoute.activity(latest.id)) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Last workout")
                                .fieldLabelStyle()
                            WatchActivityRow(activity: latest)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .watchPanel()
                    }
                    .buttonStyle(.plain)
                }

                footerRow
            }
            .padding(.horizontal, 3)
            .padding(.bottom, 6)
        }
        .navigationTitle("Today")
        .task { await glance.refresh() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text(Date.now, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                    .font(.watch(13, weight: .bold))
                    .foregroundStyle(WatchTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(syncCaption)
                    .font(.watch(8))
                    .foregroundStyle(WatchTheme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            NavigationLink(value: TodayWatchRoute.customize) {
                Image(systemName: "slider.horizontal.3")
                    .font(.watch(12, weight: .semibold))
                    .foregroundStyle(WatchTheme.accent)
                    .frame(width: WatchDisplay.scaled(28, atLeast: 26), height: WatchDisplay.scaled(28, atLeast: 26))
                    .background(WatchTheme.surfaceRaised, in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Customize dashboard")
        }
        .padding(.horizontal, 3)
    }

    private var syncCaption: String {
        guard let synced = dashboard.lastSyncedAt else { return "Waiting for iPhone" }
        return "Synced \(synced.formatted(.relative(presentation: .named)))"
    }

    private var readinessTile: some View {
        NavigationLink(value: TodayWatchRoute.readiness) {
            VStack(spacing: WatchDisplay.spacing(4)) {
                WatchRing(
                    progress: Double(readiness) / 100,
                    tint: readinessTint,
                    lineWidth: WatchDisplay.scaled(8, atLeast: 6),
                    label: "\(readiness)",
                    caption: "READY"
                )
                .frame(width: ringDiameter, height: ringDiameter)

                Text(readinessCaption)
                    .font(.watch(10, weight: .medium))
                    .foregroundStyle(WatchTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, WatchDisplay.spacing(8))
            .watchPanel()
        }
        .buttonStyle(.plain)
    }

    private var ringDiameter: CGFloat { WatchDisplay.scaled(82, atLeast: 62) }

    private var readinessTint: Color {
        switch readiness {
        case 70...: WatchTheme.positive
        case 45..<70: WatchTheme.highlight
        default: WatchTheme.danger
        }
    }

    @ViewBuilder
    private var metricGrid: some View {
        let metrics = dashboard.visibleMetrics
        if metrics.isEmpty {
            NavigationLink(value: TodayWatchRoute.customize) {
                VStack(spacing: WatchDisplay.spacing(4)) {
                    Image(systemName: "square.grid.2x2")
                        .font(.watch(18))
                        .foregroundStyle(WatchTheme.accent)
                    Text("No tiles yet")
                        .font(.watch(12, weight: .semibold))
                        .foregroundStyle(WatchTheme.textPrimary)
                    Text("Add the metrics you train by")
                        .font(.watch(9))
                        .foregroundStyle(WatchTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, WatchDisplay.spacing(14))
                .watchPanel()
            }
            .buttonStyle(.plain)
        } else {
            VStack(spacing: WatchDisplay.spacing(6)) {
                ForEach(metrics) { metric in
                    tile(metric)
                }
            }
        }
    }

    private func tile(_ metric: WatchDashboardMetric) -> some View {
        NavigationLink(value: TodayWatchRoute.metric(metric.rawValue)) {
            WatchMetricTile(
                metric: metric,
                reading: dashboard.reading(for: metric)
            )
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: WatchDisplay.spacing(5)) {
            Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                .font(.watch(20))
                .foregroundStyle(WatchTheme.accent)
            Text("No dashboard yet")
                .font(.watch(12, weight: .semibold))
                .foregroundStyle(WatchTheme.textPrimary)
            Text("Open Trekka on your iPhone with the watch nearby and your tiles appear here.")
                .font(.watch(9))
                .foregroundStyle(WatchTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(WatchDisplay.spacing(10))
        .watchPanel()
    }

    private var startButton: some View {
        Button(action: onStart) {
            HStack(spacing: WatchDisplay.spacing(8)) {
                Image(systemName: "location.north.line.fill")
                    .font(.watch(14, weight: .bold))
                    .foregroundStyle(WatchTheme.canvas)
                    .frame(width: WatchDisplay.scaled(30, atLeast: 27), height: WatchDisplay.scaled(30, atLeast: 27))
                    .background(WatchTheme.accent, in: .circle)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Start workout")
                        .font(.watch(14, weight: .bold))
                        .foregroundStyle(WatchTheme.textPrimary)
                        .lineLimit(1)
                    Text("Pace, elevation and zones live")
                        .font(.watch(8))
                        .foregroundStyle(WatchTheme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            .padding(WatchDisplay.spacing(8))
            .frame(maxWidth: .infinity)
            .watchPanel(fill: WatchTheme.accent.opacity(0.14))
        }
        .buttonStyle(.plain)
    }

    private var footerRow: some View {
        NavigationLink(value: TodayWatchRoute.settings) {
            Label("Settings", systemImage: "gearshape.fill")
                .font(.watch(12, weight: .medium))
                .foregroundStyle(WatchTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(WatchDisplay.spacing(8))
                .watchPanel()
        }
        .buttonStyle(.plain)
    }
}

/// Tile drill-down: history, extremes and the same coaching line as the phone.
struct MetricDetailWatchView: View {
    let metric: WatchDashboardMetric

    @Environment(WatchDashboardStore.self) private var dashboard

    private var reading: MetricReadingTransfer? {
        dashboard.reading(for: metric)
    }

    private var samples: [Double] {
        (reading?.series ?? []).filter { $0 > 0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(reading?.displayValue ?? "--")
                        .font(.metric(34, weight: .bold))
                        .foregroundStyle(WatchTheme.textPrimary)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    if let unit = reading?.unit, !unit.isEmpty {
                        Text(unit)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(WatchTheme.textSecondary)
                    }
                    Spacer(minLength: 0)
                }

                Text(metric.periodLabel)
                    .fieldLabelStyle(metric.tint)

                if samples.count > 1 {
                    WatchSparkline(values: reading?.series ?? [], tint: metric.tint)
                        .frame(height: 54)
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .watchPanel()

                    VStack(spacing: 5) {
                        WatchStatRow(title: "Average", value: format(average))
                        WatchStatRow(title: "Best", value: format(samples.max() ?? 0), tint: metric.tint)
                        WatchStatRow(title: "Low", value: format(samples.min() ?? 0))
                    }
                    .padding(9)
                    .watchPanel()
                }

                if let insight = reading?.insight, !insight.isEmpty {
                    Text(insight)
                        .font(.system(size: 11))
                        .foregroundStyle(WatchTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .watchPanel(fill: metric.tint.opacity(0.12))
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle(metric.title)
    }

    private var average: Double {
        guard !samples.isEmpty else { return 0 }
        return samples.reduce(0, +) / Double(samples.count)
    }

    private func format(_ value: Double) -> String {
        switch metric {
        case .sleep: WatchFormat.decimal(value, places: 1) + " h"
        case .hrv: WatchFormat.integer(value) + " ms"
        case .vo2Max: WatchFormat.decimal(value, places: 1)
        case .load, .steps: WatchFormat.integer(value)
        case .calories: WatchFormat.integer(value) + " kcal"
        case .restingHeartRate: WatchFormat.integer(value) + " bpm"
        // The dashboard carries kilometres and metres from the phone, so both
        // are converted here rather than printed with a borrowed unit label.
        case .distance: WatchFormat.decimal(
            WatchFormat.units.distance(fromMetres: value * 1000),
            places: 1
        ) + " \(WatchFormat.units.distanceUnit)"
        case .elevation: WatchFormat.elevation(value) + " \(WatchFormat.units.elevationUnit)"
        case .pace: WatchFormat.pace(value)
        case .exercise: WatchFormat.integer(value) + " min"
        case .flights: WatchFormat.integer(value)
        case .respiratoryRate: WatchFormat.decimal(value, places: 1) + " br/min"
        case .bodyMass: WatchFormat.decimal(value, places: 1) + " kg"
        }
    }
}

/// Readiness drill-down: what moved the score and what to do about it.
struct ReadinessDetailWatchView: View {
    @Environment(WatchDashboardStore.self) private var dashboard
    @Environment(WatchGlanceService.self) private var glance

    private var snapshot: DashboardTransfer? { dashboard.snapshot }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                WatchRing(
                    progress: Double(snapshot?.readiness ?? glance.readiness) / 100,
                    tint: WatchTheme.accent,
                    lineWidth: 9,
                    label: "\(snapshot?.readiness ?? glance.readiness)",
                    caption: "READY"
                )
                .frame(width: 92, height: 92)
                .padding(.top, 2)

                Text(snapshot?.readinessCaption ?? glance.caption)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WatchTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 6) {
                    WatchStatRow(title: "Sleep", value: snapshot?.sleepText ?? glance.sleepText)
                    WatchStatRow(
                        title: "HRV",
                        value: "\(WatchFormat.integer(snapshot?.hrv ?? glance.hrv)) ms",
                        tint: hrvTint
                    )
                    WatchStatRow(
                        title: "Resting HR",
                        value: "\(WatchFormat.integer(snapshot?.restingHeartRate ?? glance.restingHeartRate)) bpm"
                    )
                    WatchStatRow(title: "Load", value: "\(snapshot?.trainingLoad ?? glance.trainingLoad)")
                }
                .padding(9)
                .watchPanel()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Today's move")
                        .fieldLabelStyle()
                    Text(snapshot?.readinessSuggestion ?? glance.suggestion)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(WatchTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(9)
                .watchPanel(fill: WatchTheme.accent.opacity(0.12))

                if dashboard.zoneMinutes.contains(where: { $0 > 0 }) {
                    WatchZoneBars(minutes: dashboard.zoneMinutes)
                }

                if !(snapshot?.hasHealthData ?? glance.hasHealthData) {
                    Text("No Health data yet — connect Apple Health on iPhone.")
                        .font(.system(size: 9))
                        .foregroundStyle(WatchTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Readiness")
    }

    private var hrvTint: Color {
        let value = snapshot?.hrv ?? glance.hrv
        let baseline = snapshot?.hrvBaseline ?? glance.hrvBaseline
        return value >= baseline ? WatchTheme.positive : WatchTheme.highlight
    }
}
