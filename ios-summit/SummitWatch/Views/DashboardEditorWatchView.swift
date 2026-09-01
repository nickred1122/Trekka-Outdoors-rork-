import SwiftUI

/// Rearranges the Today dashboard from the wrist.
///
/// Every change is mirrored straight back to the iPhone, so the two dashboards
/// never disagree about what you want to see.
struct DashboardEditorWatchView: View {
    @Environment(WatchDashboardStore.self) private var dashboard

    var body: some View {
        List {
            Section {
                Toggle(isOn: Binding(
                    get: { dashboard.showsReadinessRing },
                    set: { dashboard.setShowsReadinessRing($0) }
                )) {
                    Text("Readiness ring").font(.system(size: 12))
                }
                .tint(WatchTheme.accent)

                Toggle(isOn: Binding(
                    get: { dashboard.showsZoneChart },
                    set: { dashboard.setShowsZoneChart($0) }
                )) {
                    Text("Zone chart").font(.system(size: 12))
                }
                .tint(WatchTheme.accent)

                Toggle(isOn: Binding(
                    get: { dashboard.showsRecentActivity },
                    set: { dashboard.setShowsRecentActivity($0) }
                )) {
                    Text("Last workout").font(.system(size: 12))
                }
                .tint(WatchTheme.accent)
            } header: {
                Text("Layout")
            }

            Section {
                ForEach(dashboard.visibleMetrics) { metric in
                    metricRow(metric, isVisible: true)
                }
            } header: {
                Text("On the dashboard")
            } footer: {
                Text("Changes apply on your iPhone too.")
                    .font(.system(size: 9))
            }

            if !dashboard.hiddenMetrics.isEmpty {
                Section("Hidden") {
                    ForEach(dashboard.hiddenMetrics) { metric in
                        metricRow(metric, isVisible: false)
                    }
                }
            }
        }
        .navigationTitle("Dashboard")
    }

    private func metricRow(_ metric: WatchDashboardMetric, isVisible: Bool) -> some View {
        HStack(spacing: 7) {
            TrekkaIcon(metric.glyph, size: 13, tint: isVisible ? metric.tint : WatchTheme.textSecondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 0) {
                Text(metric.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isVisible ? WatchTheme.textPrimary : WatchTheme.textSecondary)
                if let reading = dashboard.reading(for: metric) {
                    Text("\(reading.displayValue) \(reading.unit ?? "")")
                        .font(.metric(9))
                        .foregroundStyle(WatchTheme.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Button {
                dashboard.toggle(metric)
            } label: {
                Image(systemName: isVisible ? "eye.fill" : "eye.slash.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(isVisible ? WatchTheme.accent : WatchTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isVisible ? "Hide \(metric.title)" : "Show \(metric.title)")
        }
        .padding(.vertical, 1)
        .swipeActions(edge: .leading) {
            Button {
                dashboard.moveToTop(metric)
            } label: {
                Label("Top", systemImage: "arrow.up.to.line")
            }
            .tint(WatchTheme.accent)
        }
        .swipeActions(edge: .trailing) {
            if isVisible {
                Button {
                    dashboard.move(metric, by: 1)
                } label: {
                    Label("Down", systemImage: "arrow.down")
                }
                .tint(WatchTheme.surfaceRaised)
            }
        }
    }
}
