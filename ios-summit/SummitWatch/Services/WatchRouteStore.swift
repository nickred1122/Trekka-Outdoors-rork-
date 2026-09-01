import Foundation
import Observation

/// Routes cached on the watch for offline navigation.
///
/// Routes arrive from the phone. Until a transfer lands the list is empty —
/// the watch never shows a course the athlete did not put there.
@Observable
final class WatchRouteStore {
    private(set) var routes: [WatchRoute] = []
    private(set) var lastSyncedAt: Date?

    private let defaultsKey = "watch.routes.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let stored = try? JSONDecoder().decode([WatchRoute].self, from: data) {
            routes = stored
        }
    }

    func route(id: UUID) -> WatchRoute? {
        routes.first { $0.id == id }
    }

    /// Replaces the cache with a fresh set delivered from the phone.
    func replace(with incoming: [WatchRoute]) {
        routes = incoming
        lastSyncedAt = .now
        persist()
    }

    /// Merges a delivery from the phone: refreshes routes you already have,
    /// appends new ones, keeps anything local the phone does not know about.
    func upsert(_ incoming: [WatchRoute]) {
        guard !incoming.isEmpty else { return }
        var merged = routes
        for route in incoming {
            if let index = merged.firstIndex(where: { $0.id == route.id }) {
                merged[index] = route
            } else {
                merged.append(route)
            }
        }
        routes = merged
        lastSyncedAt = .now
        persist()
    }

    func routes(for sport: WatchSport) -> [WatchRoute] {
        guard sport.supportsRoutes else { return [] }
        let matching = routes.filter { $0.sport.family == sport.family }
        return matching.isEmpty ? routes : matching
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(routes) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}

