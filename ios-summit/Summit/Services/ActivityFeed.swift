import Foundation

/// One merged workout history: sessions Summit recorded plus anything already in
/// Apple Health, de-duplicated by start time so a watch workout is not counted twice.
enum ActivityFeed {
    static func merged(store: RouteStore, health: HealthService) -> [ActivityRecord] {
        let recorded = store.recentActivities
        let healthOnly = health.healthActivities.filter { candidate in
            !recorded.contains { abs($0.startDate.timeIntervalSince(candidate.startDate)) < 300 }
        }
        return (recorded + healthOnly).sorted { $0.startDate > $1.startDate }
    }
}
