import Foundation
import Observation

/// The athlete's own daily targets, persisted between launches.
///
/// Deliberately empty until somebody sets something. A dashboard that arrives
/// with a 10,000-step goal already switched on is telling a person what to want,
/// and the first thing they learn is that the app makes things up.
@Observable
final class GoalSettings {
    private static let storageKey = "dashboard.goals.v1"

    private(set) var goals: DailyGoals

    /// Called after any change, so the watch can be brought into line.
    var onChange: (() -> Void)?

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode(DailyGoals.self, from: data) {
            goals = stored
        } else {
            goals = .empty
        }
    }

    // MARK: - Reading

    func target(for metric: DashboardMetric) -> Double? { goals.target(for: metric) }

    func hasGoal(for metric: DashboardMetric) -> Bool { goals.hasGoal(for: metric) }

    var metricsWithGoals: [DashboardMetric] { goals.metrics }

    var isEmpty: Bool { goals.isEmpty }

    /// The goals as one value, for backing up and for sending to the watch.
    var snapshot: DailyGoals { goals }

    // MARK: - Writing

    func setTarget(_ value: Double, for metric: DashboardMetric) {
        guard goals.target(for: metric) != value else { return }
        goals.set(value, for: metric)
        persist()
    }

    /// Switches a goal on at its starting value, leaving an existing one alone.
    func enable(_ metric: DashboardMetric) {
        guard metric.supportsDailyGoal, !goals.hasGoal(for: metric) else { return }
        goals.set(metric.defaultGoalTarget, for: metric)
        persist()
    }

    func clear(_ metric: DashboardMetric) {
        guard goals.hasGoal(for: metric) else { return }
        goals.clear(metric)
        persist()
    }

    func toggle(_ metric: DashboardMetric) {
        if goals.hasGoal(for: metric) {
            clear(metric)
        } else {
            enable(metric)
        }
    }

    func clearAll() {
        guard !goals.isEmpty else { return }
        goals = .empty
        persist()
    }

    /// Puts back goals from a backup.
    func restore(_ restored: DailyGoals) {
        goals = restored
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(goals) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
        onChange?()
    }
}
