import Foundation
import Observation

nonisolated enum WatchTransferState: Equatable, Sendable {
    case idle
    case sending(progress: Double)
    case delivered
    case failed(String)
}

/// The wire format for a route crossing to the watch; decodes directly into
/// the watch app's `WatchRoute`.
nonisolated struct WatchRouteTransfer: Codable, Sendable {
    nonisolated struct Point: Codable, Sendable {
        var latitude: Double
        var longitude: Double
        var elevation: Double
    }

    nonisolated struct Waypoint: Codable, Sendable {
        var id: UUID
        var name: String
        var point: Point
        var distanceAlongRoute: Double
    }

    var id: UUID
    var name: String
    var sport: String
    var points: [Point]
    var waypoints: [Waypoint]
    var hasOfflineMap: Bool

    init(route: PlannedRoute) {
        id = route.id
        name = route.name
        sport = Self.sportRawValue(for: route.activity)
        points = route.points.map { point in
            Point(latitude: point.latitude, longitude: point.longitude, elevation: point.elevation)
        }
        waypoints = route.waypoints.map { waypoint in
            Waypoint(
                id: waypoint.id,
                name: waypoint.name,
                point: Point(
                    latitude: waypoint.point.latitude,
                    longitude: waypoint.point.longitude,
                    elevation: waypoint.point.elevation
                ),
                distanceAlongRoute: waypoint.distanceAlongRoute
            )
        }
        hasOfflineMap = route.isOfflineDownloaded
    }

    private static func sportRawValue(for activity: RouteActivityType) -> String {
        switch activity {
        case .run: return "trailRun"
        case .ride: return "ride"
        case .hike: return "hike"
        }
    }
}

/// Delivers routes to the paired watch over WatchConnectivity.
@Observable
final class WatchSyncService {
    private(set) var state: WatchTransferState = .idle
    private(set) var isWatchPaired: Bool = true
    private var hasPushedLibrary = false
    private var task: Task<Void, Never>?

    /// Transfers the route library to the watch.
    func send(route: PlannedRoute, store: RouteStore) {
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await stage(steps: 6) { progress in
                    self.state = .sending(progress: progress)
                }

                guard WatchLink.shared.sendRoutes(store.routes.map(WatchRouteTransfer.init)) else {
                    state = .failed("No Apple Watch with Trekka detected. Pair the watch and install the app, then try again.")
                    return
                }

                store.setSyncedToWatch(true, routeID: route.id)
                state = .delivered
            } catch is CancellationError {
                state = .idle
            } catch {
                state = .failed("Transfer interrupted. Keep the watch nearby and try again.")
            }
        }
    }

    /// One-shot full-library push so the watch starts out with every saved route.
    func pushLibrary(store: RouteStore) {
        guard !hasPushedLibrary, !store.routes.isEmpty else { return }
        hasPushedLibrary = true
        WatchLink.shared.sendRoutes(store.routes.map(WatchRouteTransfer.init))
    }

    func reset() {
        task?.cancel()
        task = nil
        state = .idle
    }

    private func stage(steps: Int, update: (Double) -> Void) async throws {
        for step in 1...steps {
            try await Task.sleep(for: .milliseconds(110))
            update(Double(step) / Double(steps))
        }
    }
}
