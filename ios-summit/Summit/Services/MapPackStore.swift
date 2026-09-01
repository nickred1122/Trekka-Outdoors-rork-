import Foundation
import Observation
import CoreLocation

/// Where a pack download has got to.
nonisolated enum MapPackProgress: Equatable, Sendable {
    case idle
    case planning
    case downloading(completed: Int, total: Int)
    case writing
    case sendingToWatch
    case ready
    case failed(String)

    var fraction: Double {
        switch self {
        case .idle, .planning: 0
        case .downloading(let completed, let total):
            total > 0 ? Double(completed) / Double(total) : 0
        case .writing: 0.95
        case .sendingToWatch: 0.98
        case .ready: 1
        case .failed: 0
        }
    }

    var isBusy: Bool {
        switch self {
        case .planning, .downloading, .writing, .sendingToWatch: true
        case .idle, .ready, .failed: false
        }
    }
}

/// Owns Trekka's offline maps on the phone.
///
/// Downloads the corridor along a route, writes it as one pack file, hands it to
/// the map renderer so the ground is available with no signal, and ships a copy
/// to the watch so the wrist works with no phone either.
@Observable
@MainActor
final class MapPackStore {
    private(set) var packs: [MapPackSummary] = []
    private(set) var progress: MapPackProgress = .idle
    /// The route currently downloading, so its own card can show the bar.
    private(set) var activeRouteID: UUID?

    /// Told whenever a route's stored ground appears or goes away, so the route
    /// library stays truthful about it. The watch is sent that flag, and a route
    /// claiming a map it does not have is the one lie this feature cannot afford.
    var onRouteMapChanged: ((UUID, Bool) -> Void)?

    private var readers: [UUID: MapPackReader] = [:]
    private var task: Task<Void, Never>?

    /// Reads pack tiles for the renderer. Held separately so the actor can keep
    /// a weak reference without owning the store.
    private let bridge = MapPackBridge()

    private let directoryName = "OfflineMaps"

    var totalBytes: Int {
        packs.reduce(0) { $0 + $1.fileBytes }
    }

    var totalSizeDescription: String {
        MapPackFormat.describe(bytes: totalBytes)
    }

    var routePacks: [MapPackSummary] {
        packs.filter { $0.kind == .route }.sorted { $0.createdAt > $1.createdAt }
    }

    var homePacks: [MapPackSummary] {
        packs.filter { $0.kind == .home }.sorted { $0.createdAt > $1.createdAt }
    }

    var areaPacks: [MapPackSummary] {
        packs.filter { $0.kind == .area }.sorted { $0.createdAt > $1.createdAt }
    }

    /// Average bytes a stored tile has actually taken, across everything on
    /// disk. Nil until something has been downloaded, because there is nothing
    /// honest to base a figure on before that.
    var averageBytesPerTile: Int? {
        let tiles: Int = packs.reduce(0) { $0 + $1.tileCount }
        guard tiles > 0 else { return nil }
        return totalBytes / tiles
    }

    /// What an area would actually store, for the picker to show before the
    /// athlete commits.
    ///
    /// `tileCount` is exact. `isReduced` says the area was too big for one pack
    /// and the closest zoom levels were dropped to fit — worth saying out loud,
    /// because the map will be coarser than the athlete asked for.
    nonisolated static func areaPlan(
        centre: CLLocationCoordinate2D,
        radiusMetres: Double
    ) -> (tileCount: Int, isReduced: Bool) {
        var requested = 0
        for zoom in MapPackPlanner.vectorZooms {
            requested += MapPackPlanner.areaTiles(around: centre, radiusMetres: radiusMetres, zoom: zoom).count
        }
        for zoom in MapPackPlanner.terrainZooms {
            requested += MapPackPlanner.areaTiles(around: centre, radiusMetres: radiusMetres, zoom: zoom).count
        }

        let plan = MapPackPlanner.plan(around: centre, radiusMetres: radiusMetres)
        let stored: Int = plan.vector.count + plan.terrain.count
        return (stored, stored < requested)
    }

    /// Downloads a square of ground the athlete picked out themselves.
    func downloadArea(
        centre: CLLocationCoordinate2D,
        radiusMetres: Double,
        name: String,
        sendToWatch: Bool = false
    ) {
        guard !progress.isBusy else { return }
        progress = .planning

        task = Task { [weak self] in
            guard let self else { return }
            await self.run(
                plan: MapPackPlanner.plan(around: centre, radiusMetres: radiusMetres),
                id: UUID(),
                name: name,
                kind: .area,
                routeID: nil,
                centre: centre,
                sendToWatch: sendToWatch
            )
        }
    }

    init() {
        loadFromDisk()
        Task { [bridge] in
            await TopoTileSource.shared.attach(local: bridge)
        }
    }

    // MARK: - Queries

    func pack(forRoute routeID: UUID) -> MapPackSummary? {
        packs.first { $0.routeID == routeID }
    }

    func hasPack(forRoute routeID: UUID) -> Bool {
        pack(forRoute: routeID) != nil
    }

    /// Whether a coordinate is already covered by a home area.
    func hasHomeArea(near coordinate: CLLocationCoordinate2D, withinMetres metres: Double) -> Bool {
        homeCentres.contains { centre in
            CLLocation(latitude: centre.latitude, longitude: centre.longitude)
                .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) < metres
        }
    }

    private var homeCentres: [CLLocationCoordinate2D] {
        homePacks.compactMap { summary in
            guard let latitude = summary.centreLatitude,
                  let longitude = summary.centreLongitude else { return nil }
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    // MARK: - Downloading

    /// Downloads the corridor for a route, then sends it to the watch.
    func download(route: PlannedRoute, widened: Bool = false, sendToWatch: Bool = true) {
        guard !progress.isBusy else { return }
        let coordinates = route.coordinates
        guard !coordinates.isEmpty else {
            progress = .failed(MapPackError.noRoute.localizedDescription)
            return
        }

        activeRouteID = route.id
        progress = .planning

        task = Task { [weak self] in
            guard let self else { return }
            await self.run(
                plan: MapPackPlanner.plan(for: coordinates, widened: widened),
                id: existingPackID(forRoute: route.id) ?? UUID(),
                name: route.name,
                kind: .route,
                routeID: route.id,
                centre: nil,
                sendToWatch: sendToWatch
            )
            self.activeRouteID = nil
        }
    }

    /// Tops up the areas the athlete keeps setting off from.
    ///
    /// Deliberately unobtrusive: one area per call, never while another download
    /// is running, and never in front of a route the athlete actually asked for.
    /// The aim is that a spontaneous outing from a regular trailhead simply has
    /// its ground already there.
    func refreshHomeAreas(from activities: [ActivityRecord], limit: Int = 2) {
        guard !progress.isBusy else { return }

        let areas = HomeAreaFinder.areas(from: activities).prefix(limit)
        for area in areas {
            // Already covered, so leave it alone.
            if hasHomeArea(near: area.centre, withinMetres: HomeAreaFinder.clusterRadiusMetres) {
                continue
            }
            cacheHomeArea(centre: area.centre, name: area.name)
            // One at a time. The next launch picks up the next one.
            return
        }
    }

    /// Quietly keeps a square of ground around a place the athlete sets off from.
    func cacheHomeArea(
        centre: CLLocationCoordinate2D,
        name: String,
        radiusMetres: Double = 4_000
    ) {
        guard !progress.isBusy else { return }
        progress = .planning

        task = Task { [weak self] in
            guard let self else { return }
            await self.run(
                plan: MapPackPlanner.plan(around: centre, radiusMetres: radiusMetres),
                id: UUID(),
                name: name,
                kind: .home,
                routeID: nil,
                centre: centre,
                // Home areas stay on the phone. The watch's storage is better
                // spent on the route actually being walked.
                sendToWatch: false
            )
        }
    }

    private func existingPackID(forRoute routeID: UUID) -> UUID? {
        pack(forRoute: routeID)?.id
    }

    private func run(
        plan: MapPackPlanner.Plan,
        id: UUID,
        name: String,
        kind: MapPackKind,
        routeID: UUID?,
        centre: CLLocationCoordinate2D?,
        sendToWatch: Bool
    ) async {
        guard !plan.isEmpty else {
            progress = .failed(MapPackError.noRoute.localizedDescription)
            return
        }

        var vectorData: [TopoTileKey: Data] = [:]
        var terrainData: [TopoTileKey: Data] = [:]
        let total = plan.total
        var completed = 0
        progress = .downloading(completed: 0, total: total)

        do {
            for key in plan.vector {
                try Task.checkCancellation()
                if let data = try await TopoTileSource.shared.rawVectorTileData(key) {
                    vectorData[key] = data
                }
                completed += 1
                progress = .downloading(completed: completed, total: total)
            }

            for key in plan.terrain {
                try Task.checkCancellation()
                if let data = try await TopoTileSource.shared.rawTerrainTileData(key) {
                    terrainData[key] = data
                }
                completed += 1
                progress = .downloading(completed: completed, total: total)
            }
        } catch is CancellationError {
            progress = .idle
            return
        } catch {
            progress = .failed(error.localizedDescription)
            return
        }

        // Every tile 404'd, which means the plan covered ground the sources do
        // not have rather than a download that failed.
        guard !vectorData.isEmpty || !terrainData.isEmpty else {
            progress = .failed("No map data covers that area.")
            return
        }

        progress = .writing

        do {
            let url = try fileURL(for: id)
            try MapPackFormat.write(
                manifestID: id,
                name: name,
                kind: kind,
                routeID: routeID,
                centreLatitude: centre?.latitude,
                centreLongitude: centre?.longitude,
                vectorTiles: vectorData,
                terrainTiles: terrainData,
                to: url
            )

            // Replacing a pack means the old reader still holds the old bytes.
            readers[id] = nil
            let reader = try MapPackReader(url: url)
            readers[id] = reader
            bridge.replace(readers: Array(readers.values))
            refreshSummaries()
            if let routeID {
                onRouteMapChanged?(routeID, true)
            }
            // The renderer may be holding tiles fetched over the network for
            // this ground; dropping them lets the pack take over.
            await TopoTileSource.shared.purge()

            if sendToWatch {
                progress = .sendingToWatch
                let summary = reader.summary
                let sent = WatchLink.shared.sendMapPack(
                    fileURL: url,
                    regionID: id.uuidString,
                    name: name,
                    sizeBytes: summary.fileBytes
                )
                if !sent {
                    // The phone still has the map, so this is not a failure of
                    // the download — say exactly that.
                    progress = .failed("Map saved on your phone. Pair your watch to send it there too.")
                    return
                }
            }

            progress = .ready
        } catch {
            progress = .failed(error.localizedDescription)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        activeRouteID = nil
        progress = .idle
    }

    func clearStatus() {
        guard !progress.isBusy else { return }
        progress = .idle
    }

    // MARK: - Deleting

    func delete(packID: UUID) {
        let routeID = readers[packID]?.summary.routeID
        readers[packID] = nil
        bridge.replace(readers: Array(readers.values))
        if let url = try? fileURL(for: packID) {
            try? FileManager.default.removeItem(at: url)
        }
        refreshSummaries()
        if let routeID {
            onRouteMapChanged?(routeID, false)
        }
        Task { await TopoTileSource.shared.purge() }
    }

    func deleteAll() {
        let routeIDs = packs.compactMap(\.routeID)
        for pack in packs {
            readers[pack.id] = nil
            if let url = try? fileURL(for: pack.id) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        bridge.replace(readers: [])
        refreshSummaries()
        for routeID in routeIDs {
            onRouteMapChanged?(routeID, false)
        }
        Task { await TopoTileSource.shared.purge() }
    }

    // MARK: - Disk

    private func directory() throws -> URL {
        guard let documents = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first else {
            throw MapPackError.malformed
        }
        let directory = documents.appendingPathComponent(directoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    private func fileURL(for id: UUID) throws -> URL {
        try directory().appendingPathComponent("\(id.uuidString).trekkapack")
    }

    /// Brings the route library into line with the packs actually on disk.
    ///
    /// Called at launch because a pack can be removed by iOS reclaiming storage,
    /// and a stale flag would then promise the watch ground that is gone.
    func reconcile(with routes: [PlannedRoute]) {
        for route in routes {
            let stored = hasPack(forRoute: route.id)
            if stored != route.isOfflineDownloaded {
                onRouteMapChanged?(route.id, stored)
            }
        }
    }

    private func loadFromDisk() {
        guard let directory = try? directory(),
              let files = try? FileManager.default.contentsOfDirectory(
                  at: directory,
                  includingPropertiesForKeys: nil
              ) else { return }

        for file in files where file.pathExtension == "trekkapack" {
            guard let reader = try? MapPackReader(url: file) else {
                // A damaged pack is worse than no pack: it would render holes
                // in ground the athlete was told they had.
                try? FileManager.default.removeItem(at: file)
                continue
            }
            readers[reader.summary.id] = reader
        }

        bridge.replace(readers: Array(readers.values))
        refreshSummaries()
    }

    private func refreshSummaries() {
        packs = readers.values.map(\.summary).sorted { $0.createdAt > $1.createdAt }
    }
}


