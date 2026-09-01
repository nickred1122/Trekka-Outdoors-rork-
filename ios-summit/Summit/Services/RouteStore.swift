import Foundation
import Observation

/// Owns planned routes and completed activities, persisting them to disk.
@Observable
final class RouteStore {
    private(set) var routes: [PlannedRoute] = []
    private(set) var activities: [ActivityRecord] = []
    var lastError: String?

    private let routesFile = "routes.json"
    private let activitiesFile = "activities.json"
    private let purgeKey = "library.seedPurged.v1"

    init() {
        load()
    }

    // MARK: - Queries

    func routes(for source: RouteSource) -> [PlannedRoute] {
        routes.filter { $0.source == source }.sorted { $0.createdAt > $1.createdAt }
    }

    func route(id: UUID) -> PlannedRoute? {
        routes.first { $0.id == id }
    }

    var recentActivities: [ActivityRecord] {
        activities.sorted { $0.startDate > $1.startDate }
    }

    var latestActivity: ActivityRecord? { recentActivities.first }

    /// Rolling seven-day zone totals in minutes, sourced from recorded activities.
    var weeklyZoneMinutes: [Double] {
        let cutoff = Date().addingTimeInterval(-7 * 86_400)
        let recent = activities.filter { $0.startDate >= cutoff }
        guard !recent.isEmpty else { return [] }
        return (0..<5).map { index in
            recent.reduce(0) { partial, activity in
                partial + (activity.zoneMinutes.indices.contains(index) ? activity.zoneMinutes[index] : 0)
            }
        }
    }

    // MARK: - Mutations

    func add(_ route: PlannedRoute) {
        routes.append(route)
        persistRoutes()
    }

    func update(_ route: PlannedRoute) {
        guard let index = routes.firstIndex(where: { $0.id == route.id }) else { return }
        routes[index] = route
        persistRoutes()
    }

    func delete(routeID: UUID) {
        routes.removeAll { $0.id == routeID }
        persistRoutes()
    }

    func setOfflineDownloaded(_ downloaded: Bool, routeID: UUID) {
        guard let index = routes.firstIndex(where: { $0.id == routeID }) else { return }
        routes[index].isOfflineDownloaded = downloaded
        persistRoutes()
    }

    func setSyncedToWatch(_ synced: Bool, routeID: UUID) {
        guard let index = routes.firstIndex(where: { $0.id == routeID }) else { return }
        routes[index].isSyncedToWatch = synced
        persistRoutes()
    }

    func add(_ activity: ActivityRecord) {
        activities.append(activity)
        persistActivities()
    }

    func delete(activityID: UUID) {
        activities.removeAll { $0.id == activityID }
        persistActivities()
    }

    // MARK: - Restoring from a backup

    /// Puts back exactly the routes a backup holds, dropping what is here now.
    func replaceRoutes(with restored: [PlannedRoute]) {
        routes = restored.map(withoutDeviceState)
        persistRoutes()
    }

    /// Adds routes a backup holds that this phone does not already have,
    /// matched on identity so restoring twice cannot duplicate anything.
    /// - Returns: how many were actually added.
    @discardableResult
    func mergeRoutes(_ incoming: [PlannedRoute]) -> Int {
        let known = Set(routes.map(\.id))
        let additions = incoming.filter { !known.contains($0.id) }.map(withoutDeviceState)
        guard !additions.isEmpty else { return 0 }
        routes.append(contentsOf: additions)
        persistRoutes()
        return additions.count
    }

    func replaceActivities(with restored: [ActivityRecord]) {
        activities = restored
        persistActivities()
    }

    /// Adds workouts a backup holds that are not already here. Identity is the
    /// first test; a start time within a minute of an existing session is
    /// treated as the same workout, so a re-recorded outing is not doubled up.
    /// - Returns: how many were actually added.
    @discardableResult
    func mergeActivities(_ incoming: [ActivityRecord]) -> Int {
        var known = Set(activities.map(\.id))
        var starts = activities.map(\.startDate)
        var additions: [ActivityRecord] = []
        for candidate in incoming {
            guard !known.contains(candidate.id) else { continue }
            guard !starts.contains(where: { abs($0.timeIntervalSince(candidate.startDate)) < 60 }) else { continue }
            known.insert(candidate.id)
            starts.append(candidate.startDate)
            additions.append(candidate)
        }
        guard !additions.isEmpty else { return 0 }
        activities.append(contentsOf: additions)
        persistActivities()
        return additions.count
    }

    /// Clears the flags that describe this phone and watch rather than the route
    /// itself. Offline maps and watch delivery are not carried in a backup, so a
    /// restored route must not claim to have either until it genuinely does.
    private func withoutDeviceState(_ route: PlannedRoute) -> PlannedRoute {
        var copy = route
        copy.isOfflineDownloaded = false
        copy.isSyncedToWatch = false
        return copy
    }

    // MARK: - Persistence

    private func load() {
        let storedRoutes: [PlannedRoute]? = decode([PlannedRoute].self, from: routesFile)
        let storedActivities: [ActivityRecord]? = decode([ActivityRecord].self, from: activitiesFile)

        routes = storedRoutes ?? []
        activities = storedActivities ?? []
        purgeSeedContentIfNeeded()
    }

    /// Earlier builds shipped with demo routes and a generated training backlog,
    /// and those were written to disk. This clears them out once, leaving
    /// anything genuinely recorded — which always carries a GPS track — alone.
    private func purgeSeedContentIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: purgeKey) else { return }
        defaults.set(true, forKey: purgeKey)

        let seededRoutes: Set<String> = [
            "Morning Ridge Run", "Col du Balme Climb", "Lac Blanc Circuit",
        ]
        let namedSeeds: Set<String> = [
            "Morning Ridge Run", "Col du Balme Climb", "Lac Blanc Hike", "Recovery Shakeout",
        ]
        let periods = ["Morning", "Midday", "Afternoon", "Evening"]
        let generatedNames = Set(
            periods.flatMap { period in
                RouteActivityType.allCases.map { "\(period) \($0.rawValue)" }
            }
        )

        let originalRoutes = routes.count
        let originalActivities = activities.count

        routes.removeAll { seededRoutes.contains($0.name) }
        activities.removeAll { activity in
            // A recorded session always has a track; the seeds never did.
            guard activity.track.isEmpty else { return false }
            return namedSeeds.contains(activity.name) || generatedNames.contains(activity.name)
        }

        if routes.count != originalRoutes { persistRoutes() }
        if activities.count != originalActivities { persistActivities() }
    }

    private func persistRoutes() {
        encode(routes, to: routesFile)
    }

    private func persistActivities() {
        encode(activities, to: activitiesFile)
    }

    private func url(for file: String) -> URL? {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(file)
    }

    private func encode<T: Encodable>(_ value: T, to file: String) {
        guard let url = url(for: file) else { return }
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            lastError = "Could not save your data locally."
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from file: String) -> T? {
        guard let url = url(for: file), FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(type, from: data)
        } catch {
            return nil
        }
    }
}
