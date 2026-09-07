import Foundation
import Observation
import CoreLocation

/// Downloads offline maps on the watch itself, with no phone involved.
///
/// Until now the wrist could only receive ground the phone had fetched for it,
/// which fails in exactly the situation the feature exists for: the phone is at
/// home, or flat, or the athlete simply never opened it. The watch has its own
/// radio, so it can do this itself.
///
/// What it cannot do is pretend to be a phone about it. A pack is fetched over a
/// slower link, into a fraction of the storage, while holding the screen awake,
/// so the plan is deliberately smaller (`MapPackPlanner.watchCeiling`) and the
/// download is checked against free space before a byte is written.
@Observable
@MainActor
final class WatchMapDownloader {
    /// Where a wrist download has got to.
    nonisolated enum Phase: Equatable, Sendable {
        case idle
        case planning
        case downloading(completed: Int, total: Int)
        case writing
        case finished(String)
        case failed(String)

        var fraction: Double {
            switch self {
            case .idle, .planning: 0
            case .downloading(let completed, let total):
                total > 0 ? Double(completed) / Double(total) : 0
            case .writing: 0.96
            case .finished: 1
            case .failed: 0
            }
        }

        var isBusy: Bool {
            switch self {
            case .planning, .downloading, .writing: true
            case .idle, .finished, .failed: false
            }
        }
    }

    private(set) var phase: Phase = .idle
    /// The route being fetched, so only its own row shows the progress.
    private(set) var activeRouteID: UUID?

    private weak var packs: WatchMapPackStore?
    private var task: Task<Void, Never>?

    /// How many tiles are fetched at once.
    ///
    /// Enough to keep the radio busy through the latency of each request, but
    /// not so many that the watch is holding a pile of tile bodies in memory at
    /// the same time as tracing contours.
    private let concurrency = 5

    /// Never fill the watch. Below this much free space the download is refused
    /// rather than risking a workout that cannot write its own track.
    private let reserveBytes = 220 * 1024 * 1024

    func configure(packs: WatchMapPackStore) {
        self.packs = packs
    }

    var isBusy: Bool { phase.isBusy }

    /// What a route's corridor will cost, worked out before committing.
    func plan(for route: WatchRoute) -> MapPackPlanner.Plan {
        MapPackPlanner.plan(
            for: route.coordinates,
            widened: false,
            ceiling: MapPackPlanner.watchCeiling
        )
    }

    // MARK: - Starting

    /// Downloads the ground along a route already on the watch.
    func download(route: WatchRoute) {
        guard !phase.isBusy else { return }
        guard !route.points.isEmpty else {
            phase = .failed(MapPackError.noRoute.localizedDescription)
            return
        }

        activeRouteID = route.id
        phase = .planning
        let plan = plan(for: route)

        task = Task { [weak self] in
            await self?.run(
                plan: plan,
                name: route.name,
                kind: .route,
                routeID: route.id,
                centre: nil
            )
            self?.activeRouteID = nil
        }
    }

    /// Downloads a square of ground around where the athlete is standing.
    func downloadArea(centre: CLLocationCoordinate2D, radiusMetres: Double, name: String) {
        guard !phase.isBusy else { return }
        phase = .planning
        let plan = MapPackPlanner.plan(
            around: centre,
            radiusMetres: radiusMetres,
            ceiling: MapPackPlanner.watchCeiling
        )

        task = Task { [weak self] in
            await self?.run(
                plan: plan,
                name: name,
                kind: .area,
                routeID: nil,
                centre: centre
            )
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        activeRouteID = nil
        phase = .idle
    }

    /// Clears a finished or failed message without disturbing a live download.
    func clearStatus() {
        guard !phase.isBusy else { return }
        phase = .idle
    }

    // MARK: - Running

    private func run(
        plan: MapPackPlanner.Plan,
        name: String,
        kind: MapPackKind,
        routeID: UUID?,
        centre: CLLocationCoordinate2D?
    ) async {
        guard !plan.isEmpty else {
            phase = .failed(MapPackError.noRoute.localizedDescription)
            return
        }

        // Refuse before spending the athlete's battery, not after.
        let free = WatchMapPackStore.freeBytes()
        if free > 0, free - plan.estimatedBytes < reserveBytes {
            phase = .failed("Not enough space on your watch. Delete a stored map and try again.")
            return
        }

        let total = plan.total
        var completed = 0
        phase = .downloading(completed: 0, total: total)

        var vectorData: [TopoTileKey: Data] = [:]
        var terrainData: [TopoTileKey: Data] = [:]

        do {
            vectorData = try await fetch(plan.vector, isTerrain: false, total: total, completed: &completed)
            terrainData = try await fetch(plan.terrain, isTerrain: true, total: total, completed: &completed)
        } catch is CancellationError {
            phase = .idle
            return
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }

        // Every tile came back empty, which means the plan covered ground the
        // sources do not have rather than a download that failed.
        guard !vectorData.isEmpty || !terrainData.isEmpty else {
            phase = .failed("No map data covers that area.")
            return
        }

        phase = .writing

        let packID = packs?.pack(forRoute: routeID ?? UUID())?.id ?? UUID()
        do {
            let url = try WatchMapPackStore.packURL(for: packID)
            try MapPackFormat.write(
                manifestID: packID,
                name: name,
                kind: kind,
                routeID: routeID,
                centreLatitude: centre?.latitude,
                centreLongitude: centre?.longitude,
                vectorTiles: vectorData,
                terrainTiles: terrainData,
                to: url
            )
            packs?.adopt(packID: packID, isLocal: true)

            let stored = packs?.pack(forRoute: routeID ?? packID)
            let size = stored?.sizeDescription ?? MapPackFormat.describe(bytes: plan.estimatedBytes)
            phase = .finished("\(name) is on your watch · \(size)")
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Fetches a batch of tiles, a few at a time, reporting progress as it goes.
    private func fetch(
        _ keys: [TopoTileKey],
        isTerrain: Bool,
        total: Int,
        completed: inout Int
    ) async throws -> [TopoTileKey: Data] {
        var result: [TopoTileKey: Data] = [:]
        var index = 0

        while index < keys.count {
            try Task.checkCancellation()
            let upper = min(index + concurrency, keys.count)
            let batch = Array(keys[index..<upper])
            index = upper

            let fetched = try await withThrowingTaskGroup(
                of: (TopoTileKey, Data?).self
            ) { group -> [(TopoTileKey, Data?)] in
                for key in batch {
                    group.addTask {
                        let data = isTerrain
                            ? try await TopoTileSource.shared.rawTerrainTileData(key)
                            : try await TopoTileSource.shared.rawVectorTileData(key)
                        return (key, data)
                    }
                }
                var pairs: [(TopoTileKey, Data?)] = []
                for try await pair in group {
                    pairs.append(pair)
                }
                return pairs
            }

            for (key, data) in fetched {
                if let data { result[key] = data }
            }
            completed += batch.count
            phase = .downloading(completed: completed, total: total)
        }

        return result
    }
}
