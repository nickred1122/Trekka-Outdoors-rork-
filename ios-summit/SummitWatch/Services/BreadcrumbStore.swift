import Foundation
import CoreLocation
import Observation

/// One dropped crumb: a place you were, and when.
nonisolated struct Breadcrumb: Codable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double
    var elevation: Double
    var at: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// A complete trail of where a workout actually went.
nonisolated struct BreadcrumbTrail: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var sport: WatchSport
    var startedAt: Date
    var crumbs: [Breadcrumb]

    var distance: Double {
        guard crumbs.count > 1 else { return 0 }
        var total: Double = 0
        for index in 1..<crumbs.count {
            let from = CLLocation(latitude: crumbs[index - 1].latitude, longitude: crumbs[index - 1].longitude)
            let to = CLLocation(latitude: crumbs[index].latitude, longitude: crumbs[index].longitude)
            total += to.distance(from: from)
        }
        return total
    }

    var duration: TimeInterval {
        guard let first = crumbs.first, let last = crumbs.last else { return 0 }
        return last.at.timeIntervalSince(first.at)
    }

    var coordinates: [CLLocationCoordinate2D] { crumbs.map(\.coordinate) }
}

/// Records and keeps the breadcrumb trail of every outdoor workout.
///
/// The live trail is written to disk as it grows, so a watch that reboots
/// mid-hike still knows the way back. Finished trails are kept so you can
/// retrace or backtrack them later.
@Observable
final class BreadcrumbStore {
    /// The trail being laid right now.
    private(set) var activeCrumbs: [Breadcrumb] = []
    private(set) var isRecording = false
    private(set) var trails: [BreadcrumbTrail] = []

    /// Minimum spacing between crumbs, in metres. Dense enough to retrace a
    /// switchback, sparse enough to store a long day out.
    private let spacingMetres: Double = 12
    private let maxActiveCrumbs = 4_000
    private let maxTrails = 12
    /// Metres per second beyond which a step is a GPS jump, not travel.
    private static let maxPlausibleSpeed: Double = 45

    private let activeKey = "watch.breadcrumbs.active.v1"
    private let trailsKey = "watch.breadcrumbs.trails.v1"
    private var crumbsSinceSave = 0

    init() {
        load()
    }

    // MARK: - Recording

    func beginRecording() {
        activeCrumbs = []
        isRecording = true
        crumbsSinceSave = 0
        persistActive()
    }

    /// Adds a crumb if you have moved far enough since the last one.
    ///
    /// Only positions the workout engine has already accepted as real reach this
    /// point, so the trail is a record of ground actually covered. The extra
    /// checks here guard the one thing a trail cannot survive: a single bogus
    /// point, which would put a false turn on the map you navigate home by.
    func record(coordinate: CLLocationCoordinate2D, elevation: Double, at date: Date = .now) {
        guard isRecording else { return }
        guard coordinate.latitude.isFinite, coordinate.longitude.isFinite else { return }
        guard abs(coordinate.latitude) <= 90, abs(coordinate.longitude) <= 180 else { return }
        // Null Island is what a zeroed coordinate looks like, never a trail.
        guard abs(coordinate.latitude) > 0.000_01 || abs(coordinate.longitude) > 0.000_01 else { return }

        if let last = activeCrumbs.last {
            guard date > last.at else { return }
            let previous = CLLocation(latitude: last.latitude, longitude: last.longitude)
            let current = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let step = current.distance(from: previous)
            guard step >= spacingMetres else { return }

            // A step that implies an impossible speed is a receiver glitch. It
            // is dropped rather than drawn, because a retrace that cuts across a
            // valley is worse than one that is briefly missing a section.
            let seconds = date.timeIntervalSince(last.at)
            if seconds > 0, step / seconds > Self.maxPlausibleSpeed { return }
        }

        activeCrumbs.append(
            Breadcrumb(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                elevation: elevation.isFinite ? elevation : 0,
                at: date
            )
        )

        // Thin the oldest half rather than dropping the trail when a very long
        // day runs past the cap.
        if activeCrumbs.count > maxActiveCrumbs {
            let head = stride(from: 0, to: maxActiveCrumbs / 2, by: 2).map { activeCrumbs[$0] }
            activeCrumbs = head + activeCrumbs.suffix(maxActiveCrumbs / 2)
        }

        crumbsSinceSave += 1
        if crumbsSinceSave >= 10 {
            crumbsSinceSave = 0
            persistActive()
        }
    }

    /// Closes the trail and files it in history.
    @discardableResult
    func finishRecording(name: String, sport: WatchSport) -> BreadcrumbTrail? {
        isRecording = false
        defer {
            activeCrumbs = []
            persistActive()
        }
        guard activeCrumbs.count > 2 else { return nil }

        let trail = BreadcrumbTrail(
            name: name,
            sport: sport,
            startedAt: activeCrumbs.first?.at ?? .now,
            crumbs: activeCrumbs
        )
        trails.insert(trail, at: 0)
        if trails.count > maxTrails { trails = Array(trails.prefix(maxTrails)) }
        persistTrails()
        return trail
    }

    func cancelRecording() {
        isRecording = false
        activeCrumbs = []
        persistActive()
    }

    func delete(trailID: UUID) {
        trails.removeAll { $0.id == trailID }
        persistTrails()
    }

    // MARK: - Backtracking

    /// Distance in metres back along the crumbs to the start.
    var distanceHome: Double {
        guard activeCrumbs.count > 1 else { return 0 }
        var total: Double = 0
        for index in 1..<activeCrumbs.count {
            let from = CLLocation(latitude: activeCrumbs[index - 1].latitude, longitude: activeCrumbs[index - 1].longitude)
            let to = CLLocation(latitude: activeCrumbs[index].latitude, longitude: activeCrumbs[index].longitude)
            total += to.distance(from: from)
        }
        return total
    }

    /// Turns a trail inside out so it can be navigated as a route home.
    func backtrackRoute(from crumbs: [Breadcrumb], name: String, sport: WatchSport) -> WatchRoute? {
        guard crumbs.count > 2 else { return nil }
        let reversed = Array(crumbs.reversed())
        let points = reversed.map {
            WatchRoutePoint(latitude: $0.latitude, longitude: $0.longitude, elevation: $0.elevation)
        }
        let distances = WatchRouteMath.cumulativeDistances(of: points)

        var waypoints: [WatchWaypoint] = []
        if let start = points.first {
            waypoints.append(WatchWaypoint(name: "Turnaround", point: start, distanceAlongRoute: 0))
        }
        if let finish = points.last {
            waypoints.append(
                WatchWaypoint(name: "Start", point: finish, distanceAlongRoute: distances.last ?? 0)
            )
        }

        return WatchRoute(
            name: name,
            sport: sport,
            points: points,
            waypoints: waypoints,
            hasOfflineMap: true
        )
    }

    /// Backtrack route for the trail currently being recorded.
    func backtrackActiveRoute(sport: WatchSport) -> WatchRoute? {
        backtrackRoute(from: activeCrumbs, name: "Backtrack", sport: sport)
    }

    // MARK: - Storage

    private func load() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: activeKey),
           let stored = try? JSONDecoder().decode([Breadcrumb].self, from: data) {
            activeCrumbs = stored
        }
        if let data = defaults.data(forKey: trailsKey),
           let stored = try? JSONDecoder().decode([BreadcrumbTrail].self, from: data) {
            trails = stored
        }
    }

    private func persistActive() {
        guard let data = try? JSONEncoder().encode(activeCrumbs) else { return }
        UserDefaults.standard.set(data, forKey: activeKey)
    }

    private func persistTrails() {
        guard let data = try? JSONEncoder().encode(trails) else { return }
        UserDefaults.standard.set(data, forKey: trailsKey)
    }
}
