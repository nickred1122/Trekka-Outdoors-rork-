import Foundation
import Observation

/// The watch's copy of the phone's Today dashboard.
///
/// The phone pushes readings and layout; the watch can rearrange the same
/// dashboard locally and the change travels straight back so both devices agree.
@Observable
final class WatchDashboardStore {
    private(set) var snapshot: DashboardTransfer?
    private(set) var preferences: DashboardPreferencesTransfer = .standard
    private(set) var lastSyncedAt: Date?

    /// Set by the connectivity bridge so wrist edits reach the phone.
    var onPreferencesChanged: ((DashboardPreferencesTransfer) -> Void)?

    private let snapshotKey = "watch.dashboard.v1"
    private let preferencesKey = "watch.dashboard.preferences.v1"
    private let syncedKey = "watch.dashboard.syncedAt"

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: snapshotKey),
           let stored = try? JSONDecoder().decode(DashboardTransfer.self, from: data) {
            snapshot = stored
            preferences = stored.preferences
        }
        if let data = defaults.data(forKey: preferencesKey),
           let stored = try? JSONDecoder().decode(DashboardPreferencesTransfer.self, from: data) {
            preferences = stored
        }
        if let synced = defaults.object(forKey: syncedKey) as? Date {
            lastSyncedAt = synced
        }
    }

    // MARK: - Reading the dashboard

    var hasData: Bool { snapshot != nil }

    var visibleMetrics: [WatchDashboardMetric] {
        orderedMetrics.filter { !preferences.hidden.contains($0.rawValue) }
    }

    var hiddenMetrics: [WatchDashboardMetric] {
        orderedMetrics.filter { preferences.hidden.contains($0.rawValue) }
    }

    private var orderedMetrics: [WatchDashboardMetric] {
        var metrics = preferences.order.compactMap(WatchDashboardMetric.init(rawValue:))
        for metric in WatchDashboardMetric.allCases where !metrics.contains(metric) {
            metrics.append(metric)
        }
        return metrics
    }

    func reading(for metric: WatchDashboardMetric) -> MetricReadingTransfer? {
        snapshot?.readings.first { $0.metric == metric.rawValue }
    }

    func isVisible(_ metric: WatchDashboardMetric) -> Bool {
        !preferences.hidden.contains(metric.rawValue)
    }

    var showsReadinessRing: Bool { preferences.showsReadinessRing }
    var showsZoneChart: Bool { preferences.showsZoneChart }
    var showsRecentActivity: Bool { preferences.showsRecentActivity }

    var activities: [ActivityTransfer] {
        snapshot?.activities ?? []
    }

    func activity(id: UUID) -> ActivityTransfer? {
        activities.first { $0.id == id }
    }

    var zoneMinutes: [Double] {
        let minutes = snapshot?.zoneMinutes ?? []
        return minutes.count == 5 ? minutes : [0, 0, 0, 0, 0]
    }

    // MARK: - Editing from the wrist

    func toggle(_ metric: WatchDashboardMetric) {
        var updated = preferences
        if updated.hidden.contains(metric.rawValue) {
            updated.hidden.removeAll { $0 == metric.rawValue }
        } else {
            updated.hidden.append(metric.rawValue)
        }
        commit(updated)
    }

    func moveToTop(_ metric: WatchDashboardMetric) {
        var updated = preferences
        updated.order = orderedMetrics.map(\.rawValue)
        updated.order.removeAll { $0 == metric.rawValue }
        updated.order.insert(metric.rawValue, at: 0)
        updated.hidden.removeAll { $0 == metric.rawValue }
        commit(updated)
    }

    func move(_ metric: WatchDashboardMetric, by offset: Int) {
        var order = orderedMetrics.map(\.rawValue)
        guard let index = order.firstIndex(of: metric.rawValue) else { return }
        let target = index + offset
        guard target >= 0, target < order.count else { return }
        order.swapAt(index, target)
        var updated = preferences
        updated.order = order
        commit(updated)
    }

    func setShowsReadinessRing(_ shows: Bool) {
        var updated = preferences
        updated.showsReadinessRing = shows
        commit(updated)
    }

    func setShowsZoneChart(_ shows: Bool) {
        var updated = preferences
        updated.showsZoneChart = shows
        commit(updated)
    }

    func setShowsRecentActivity(_ shows: Bool) {
        var updated = preferences
        updated.showsRecentActivity = shows
        commit(updated)
    }

    /// Persists a wrist edit and mirrors it to the phone.
    private func commit(_ updated: DashboardPreferencesTransfer) {
        preferences = updated
        if var current = snapshot {
            current.preferences = updated
            snapshot = current
        }
        persistPreferences()
        onPreferencesChanged?(updated)
    }

    // MARK: - Incoming from the phone

    func apply(_ transfer: DashboardTransfer) {
        snapshot = transfer
        preferences = transfer.preferences
        lastSyncedAt = .now
        persistSnapshot()
        persistPreferences()
        UserDefaults.standard.set(lastSyncedAt, forKey: syncedKey)
    }

    /// Folds a workout just finished on the watch into the local history so the
    /// Activities list updates before the phone pushes a refreshed dashboard.
    func recordLocalWorkout(_ activity: ActivityTransfer) {
        guard var current = snapshot else { return }
        current.activities.removeAll { $0.id == activity.id }
        current.activities.insert(activity, at: 0)
        current.activities = Array(current.activities.prefix(20))
        snapshot = current
        persistSnapshot()
    }

    private func persistSnapshot() {
        guard let snapshot, let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: snapshotKey)
    }

    private func persistPreferences() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        UserDefaults.standard.set(data, forKey: preferencesKey)
    }
}
