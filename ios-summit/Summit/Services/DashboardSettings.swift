import Foundation
import Observation
import SwiftUI

/// How wide a dashboard tile has to be before the grid puts another beside it.
///
/// A single value now that compact tiles are gone: they saved a little space and
/// paid for it with the trend chart, which was the most useful thing on a tile.
nonisolated enum TileMetrics {
    static let minimumWidth: Double = 150
}

/// Everything the user can change about the Today dashboard, stored as one value.
nonisolated struct DashboardPreferences: Codable, Sendable, Equatable {
    var order: [DashboardMetric]
    var hidden: [DashboardMetric]
    var showsReadinessRing: Bool
    var showsZoneChart: Bool
    var showsRecentActivity: Bool
    /// Whether tiles carry their trend chart. Optional so dashboards saved
    /// before this switch existed still decode, defaulting to showing them.
    var showsTileCharts: Bool?
    var hasExploredMetrics: Bool
    /// Optional so dashboards saved before ranges existed still decode.
    var chartRange: MetricRange?
    /// A hand-picked day or date range, which takes over from the preset when set.
    var chartSpan: MetricSpan?

    static let defaultOrder: [DashboardMetric] = [
        .sleep, .hrv, .vo2Max, .load, .calories, .steps, .distance, .elevation, .restingHeartRate, .pace,
    ]

    static let standard = DashboardPreferences(
        order: defaultOrder,
        hidden: [.restingHeartRate, .pace],
        showsReadinessRing: true,
        showsZoneChart: true,
        showsRecentActivity: true,
        showsTileCharts: true,
        hasExploredMetrics: false,
        chartRange: .week,
        chartSpan: nil
    )

    /// Repairs stored data when metrics are added or removed between versions.
    func normalized() -> DashboardPreferences {
        let known = Set(DashboardMetric.allCases)
        var repaired = self
        repaired.order = order.filter { known.contains($0) }
        for metric in DashboardMetric.allCases where !repaired.order.contains(metric) {
            repaired.order.append(metric)
        }
        repaired.hidden = hidden.filter { known.contains($0) }
        return repaired
    }
}

/// User-owned layout of the Today dashboard, persisted between launches.
@Observable
final class DashboardSettings {
    private var preferences: DashboardPreferences

    private let defaultsKey = "dashboard.preferences.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: "dashboard.preferences.v1"),
           let stored = try? JSONDecoder().decode(DashboardPreferences.self, from: data) {
            preferences = stored.normalized()
        } else {
            preferences = .standard
        }
    }

    // MARK: - Sections

    var showsReadinessRing: Bool {
        get { preferences.showsReadinessRing }
        set { preferences.showsReadinessRing = newValue; persist() }
    }

    var showsZoneChart: Bool {
        get { preferences.showsZoneChart }
        set { preferences.showsZoneChart = newValue; persist() }
    }

    var showsRecentActivity: Bool {
        get { preferences.showsRecentActivity }
        set { preferences.showsRecentActivity = newValue; persist() }
    }

    /// Trend charts on the tiles themselves. Turning them off keeps the value
    /// and the label, so the dashboard reads as numbers rather than shrinking.
    var showsTileCharts: Bool {
        get { preferences.showsTileCharts ?? true }
        set { preferences.showsTileCharts = newValue; persist() }
    }

    var hasExploredMetrics: Bool { preferences.hasExploredMetrics }

    // MARK: - Charts

    /// The rolling window every dashboard chart is scoped to. Choosing one drops
    /// any hand-picked dates, since the two would otherwise fight over the chart.
    var chartRange: MetricRange {
        get { preferences.chartRange ?? .week }
        set {
            preferences.chartRange = newValue
            preferences.chartSpan = nil
            persist()
        }
    }

    /// An exact day or date range chosen by hand, when a rolling preset is not
    /// what the user wants to look at.
    var chartSpan: MetricSpan? {
        get { preferences.chartSpan }
        set { preferences.chartSpan = newValue; persist() }
    }

    /// What the charts are scoped to: the hand-picked dates if there are any,
    /// else the preset ending on `anchor`.
    ///
    /// The anchor is normalised to the start of its day so the window stays a
    /// stable value through a redraw and can safely drive `task(id:)`.
    func window(endingOn anchor: Date, allowing ranges: [MetricRange]) -> MetricWindow {
        if let span = preferences.chartSpan { return .span(span) }
        return .preset(chartRange.clamped(to: ranges), anchor: Calendar.current.startOfDay(for: anchor))
    }

    // MARK: - Tiles

    var visibleMetrics: [DashboardMetric] {
        preferences.order.filter { !preferences.hidden.contains($0) }
    }

    var hiddenMetrics: [DashboardMetric] {
        preferences.order.filter { preferences.hidden.contains($0) }
    }

    func isVisible(_ metric: DashboardMetric) -> Bool {
        !preferences.hidden.contains(metric)
    }

    func hide(_ metric: DashboardMetric) {
        guard !preferences.hidden.contains(metric) else { return }
        preferences.hidden.append(metric)
        persist()
    }

    func show(_ metric: DashboardMetric) {
        preferences.hidden.removeAll { $0 == metric }
        persist()
    }

    func toggle(_ metric: DashboardMetric) {
        if preferences.hidden.contains(metric) { show(metric) } else { hide(metric) }
    }

    func moveToTop(_ metric: DashboardMetric) {
        guard let index = preferences.order.firstIndex(of: metric) else { return }
        preferences.order.remove(at: index)
        preferences.order.insert(metric, at: 0)
        preferences.hidden.removeAll { $0 == metric }
        persist()
    }

    /// Reorders the visible tiles while leaving hidden entries in their slots.
    func moveVisible(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        var visible = visibleMetrics
        visible.move(fromOffsets: offsets, toOffset: destination)
        var iterator = visible.makeIterator()
        let hidden = preferences.hidden
        preferences.order = preferences.order.map { metric in
            hidden.contains(metric) ? metric : (iterator.next() ?? metric)
        }
        persist()
    }

    // MARK: - Watch mirror

    /// The dashboard layout in the shape the watch mirrors.
    var preferencesTransfer: DashboardPreferencesTransfer {
        DashboardPreferencesTransfer(
            order: preferences.order.map(\.rawValue),
            hidden: preferences.hidden.map(\.rawValue),
            showsReadinessRing: preferences.showsReadinessRing,
            showsZoneChart: preferences.showsZoneChart,
            showsRecentActivity: preferences.showsRecentActivity
        )
    }

    /// Applies a dashboard edit made on the watch.
    func apply(_ incoming: DashboardPreferencesTransfer) {
        var updated = preferences
        updated.order = incoming.order.compactMap(DashboardMetric.init(rawValue:))
        updated.hidden = incoming.hidden.compactMap(DashboardMetric.init(rawValue:))
        updated.showsReadinessRing = incoming.showsReadinessRing
        updated.showsZoneChart = incoming.showsZoneChart
        updated.showsRecentActivity = incoming.showsRecentActivity
        preferences = updated.normalized()
        persist()
    }

    // MARK: - Backup

    /// The dashboard layout as one value, for backing up and exporting.
    var snapshot: DashboardPreferences { preferences }

    /// Puts back a dashboard layout from a backup, repairing it against the
    /// metrics this version of the app actually has.
    func restore(_ restored: DashboardPreferences) {
        preferences = restored.normalized()
        persist()
    }

    func markExplored() {
        guard !preferences.hasExploredMetrics else { return }
        preferences.hasExploredMetrics = true
        persist()
    }

    func resetToDefaults() {
        let explored = preferences.hasExploredMetrics
        let range = preferences.chartRange
        let span = preferences.chartSpan
        preferences = .standard
        preferences.chartRange = range
        preferences.showsTileCharts = true
        preferences.chartSpan = span
        preferences.hasExploredMetrics = explored
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
