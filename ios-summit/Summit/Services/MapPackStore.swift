import Foundation
import Observation
import CoreLocation

/// Which of the two tile sources a batch is being fetched from.
nonisolated enum MapTileFlavour: Sendable {
    /// Paths, roads, water and woodland.
    case vector
    /// The height data contour lines are traced from.
    case terrain
}

nonisolated extension Array {
    /// Splits into runs of at most `size`, preserving order.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return isEmpty ? [] : [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

/// Where a change to the offline map has got to.
nonisolated enum MapPackProgress: Equatable, Sendable {
    case idle
    case planning
    case downloading(completed: Int, total: Int)
    case writing
    case sendingToWatch
    case ready
    /// Nothing needed fetching — the map already covered that ground.
    case alreadyCovered
    case failed(String)

    var fraction: Double {
        switch self {
        case .idle, .planning: 0
        case .downloading(let completed, let total):
            total > 0 ? Double(completed) / Double(total) : 0
        case .writing: 0.95
        case .sendingToWatch: 0.98
        case .ready, .alreadyCovered: 1
        case .failed: 0
        }
    }

    var isBusy: Bool {
        switch self {
        case .planning, .downloading, .writing, .sendingToWatch: true
        case .idle, .ready, .alreadyCovered, .failed: false
        }
    }
}

/// Owns Trekka's offline map on the phone.
///
/// There is one map, not one download per route. This is the second design: the
/// first kept a separate file for every route, and it was wrong in a way that
/// got worse the more the app was used. Two routes up the same valley each
/// stored that valley. A route overlapping one already downloaded paid for the
/// shared ground again, over the network, and again on disk. And "how much
/// space are my maps taking?" had no single answer.
///
/// Now the phone keeps one library of ground, and a list of *coverage* — the
/// places the athlete asked to be covered. Adding a route contributes only the
/// tiles the map does not already hold, so the second route over a hillside is
/// nearly free, and often completely free. Removing coverage rebuilds the map
/// from what the remaining coverage still needs, entirely from bytes already on
/// the phone.
///
/// The watch is deliberately not given the whole map: its storage is a fraction
/// of the phone's. What travels to the wrist is a pack cut out of the library
/// for one route or area, built on demand without re-downloading anything.
@Observable
@MainActor
final class MapPackStore {
    /// Every place the one map covers.
    private(set) var coverage: [MapCoverage] = []
    private(set) var progress: MapPackProgress = .idle
    /// The route currently being added, so its own card can show the bar.
    private(set) var activeRouteID: UUID?
    /// What is being downloaded right now, by name.
    private(set) var activeName: String?
    /// Places lined up behind it, in order.
    ///
    /// Downloads used to be refused outright while another was running, which
    /// made covering several places a chore of waiting and remembering. They now
    /// queue: ask for four states and walk away.
    private(set) var queuedNames: [String] = []

    /// Real size of the map on disk. Never an estimate.
    private(set) var totalBytes: Int = 0
    /// Distinct pieces of ground stored, after sharing.
    private(set) var tileCount: Int = 0

    /// Why the last attempt to send a map to the watch could not start, if it
    /// could not. Kept apart from `progress` because a phone download that
    /// succeeded is not a failure just because the watch was out of range.
    private(set) var lastSendBlock: WatchSendBlock?

    /// Told whenever a route's stored ground appears or goes away, so the route
    /// library stays truthful about it. The watch is sent that flag, and a route
    /// claiming a map it does not have is the one lie this feature cannot afford.
    var onRouteMapChanged: ((UUID, Bool) -> Void)?

    private var library: MapPackReader?
    private var task: Task<Void, Never>?
    private var queue: [CoverageRequest] = []
    /// Bumped whenever everything is stopped, so a run that is still unwinding
    /// cannot start the next one after being cancelled.
    private var generation = 0

    /// How many tiles are fetched before what has arrived is written to disk.
    ///
    /// A region is thousands of pieces. Holding all of them in memory until the
    /// end would be hundreds of megabytes of resident data — a plausible way to
    /// be killed by the system halfway through — and would throw away everything
    /// fetched if the download stopped. Writing as it goes fixes both.
    private static let writeBatchSize = 320

    /// How many tiles are fetched at once.
    ///
    /// One at a time meant a large download took its slowest tile times its tile
    /// count: a state would have run for the better part of an hour. Six at a
    /// time is several times quicker while staying polite to a community-run
    /// tile server.
    private static let fetchConcurrency = 6

    /// Reads map tiles for the renderer, on whatever thread it likes.
    private let bridge = MapPackBridge()

    private let directoryName = "OfflineMaps"
    private let libraryFileName = "library.trekkapack"
    private let coverageFileName = "coverage.json"

    /// Fixed identity for the one map file, so a rebuild replaces it rather
    /// than accumulating another.
    private let libraryID = UUID(uuidString: "7A9E0B2C-4D1F-4A6B-9C3E-000000000001") ?? UUID()

    init() {
        loadFromDisk()
        Task { [bridge] in
            await TopoTileSource.shared.attach(local: bridge)
        }
    }

    // MARK: - Summary

    var totalSizeDescription: String {
        MapPackFormat.describe(bytes: totalBytes)
    }

    var isEmpty: Bool { coverage.isEmpty }

    /// Whether anything is downloading or waiting to.
    var isWorking: Bool { progress.isBusy || !queuedNames.isEmpty }

    /// Coverage the athlete asked for, newest first. Home areas are Trekka's
    /// own doing, so they are listed separately.
    var chosenCoverage: [MapCoverage] {
        coverage.filter { $0.kind != .home }.sorted { $0.addedAt > $1.addedAt }
    }

    var routeCoverage: [MapCoverage] {
        coverage.filter { $0.kind == .route }.sorted { $0.addedAt > $1.addedAt }
    }

    var areaCoverage: [MapCoverage] {
        coverage.filter { $0.kind == .area }.sorted { $0.addedAt > $1.addedAt }
    }

    var homeCoverage: [MapCoverage] {
        coverage.filter { $0.kind == .home }.sorted { $0.addedAt > $1.addedAt }
    }

    /// Average bytes a stored tile has actually taken. Nil until something has
    /// been downloaded, because there is nothing honest to base a figure on.
    var averageBytesPerTile: Int? {
        guard tileCount > 0 else { return nil }
        return totalBytes / tileCount
    }

    // MARK: - Queries

    func entry(id: UUID) -> MapCoverage? {
        coverage.first { $0.id == id }
    }

    func entry(forRoute routeID: UUID) -> MapCoverage? {
        coverage.first { $0.routeID == routeID }
    }

    func covers(routeID: UUID) -> Bool {
        entry(forRoute: routeID) != nil
    }

    /// Whether a coordinate is already covered by a cached starting area.
    func hasHomeArea(near coordinate: CLLocationCoordinate2D, withinMetres metres: Double) -> Bool {
        coverage.contains { entry in
            guard entry.kind == .home, let centre = entry.centre else { return false }
            return CLLocation(latitude: centre.latitude, longitude: centre.longitude)
                .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) < metres
        }
    }

    /// How much ground adding this route would actually fetch.
    ///
    /// The number that makes the shared map worth having: for a route crossing
    /// somewhere already covered it can be a small fraction of the total, or
    /// nothing at all.
    func newTileCount(
        forRoute coordinates: [CLLocationCoordinate2D],
        widened: Bool = false,
        detail: MapDownloadDetail = .topographic
    ) -> Int {
        newTileCount(in: detail.trim(MapPackPlanner.plan(for: coordinates, widened: widened)))
    }

    func newTileCount(
        forArea centre: CLLocationCoordinate2D,
        radiusMetres: Double,
        detail: MapDownloadDetail = .topographic,
        scale: MapDownloadScale = .close
    ) -> Int {
        newTileCount(in: scale.plan(around: centre, radiusMetres: radiusMetres, detail: detail))
    }

    private func newTileCount(in plan: MapPackPlanner.Plan) -> Int {
        var count = 0
        for key in plan.vector where !holds(kind: MapPackFormat.vectorKind, key: key) {
            count += 1
        }
        for key in plan.terrain where !holds(kind: MapPackFormat.terrainKind, key: key) {
            count += 1
        }
        return count
    }

    private func holds(kind: String, key: TopoTileKey) -> Bool {
        library?.contains(kind: kind, key: key) ?? false
    }

    /// What an area would cover, for the picker to show before committing.
    ///
    /// `tileCount` is exact. `isReduced` says the area was too big to keep at
    /// full detail and the closest zoom levels were dropped — worth saying out
    /// loud, because the map will be coarser than the athlete asked for.
    nonisolated static func areaPlan(
        centre: CLLocationCoordinate2D,
        radiusMetres: Double,
        detail: MapDownloadDetail = .topographic,
        scale: MapDownloadScale = .close
    ) -> (tileCount: Int, isReduced: Bool) {
        let requested = scale.requestedTileCount(
            around: centre,
            radiusMetres: radiusMetres,
            detail: detail
        )
        let plan = scale.plan(around: centre, radiusMetres: radiusMetres, detail: detail)
        let stored: Int = plan.vector.count + plan.terrain.count
        return (stored, stored < requested)
    }

    // MARK: - Adding ground

    /// Adds the ground along a route to the map.
    func add(
        route: PlannedRoute,
        widened: Bool = false,
        detail: MapDownloadDetail = .topographic,
        sendToWatch: Bool = true
    ) {
        let coordinates = route.coordinates
        guard !coordinates.isEmpty else {
            progress = .failed(MapPackError.noRoute.localizedDescription)
            return
        }
        // Asking twice for the same route while it waits its turn should not
        // queue it twice.
        guard !queue.contains(where: { $0.routeID == route.id }),
              activeRouteID != route.id else { return }

        enqueue(
            CoverageRequest(
                id: entry(forRoute: route.id)?.id ?? UUID(),
                name: route.name,
                kind: .route,
                routeID: route.id,
                centre: nil,
                radiusMetres: nil,
                plan: detail.trim(MapPackPlanner.plan(for: coordinates, widened: widened)),
                sendToWatch: sendToWatch
            )
        )
    }

    /// Adds a square of ground the athlete picked out themselves — a valley at
    /// close detail, or a whole state at region scale.
    func addArea(
        centre: CLLocationCoordinate2D,
        radiusMetres: Double,
        name: String,
        detail: MapDownloadDetail = .topographic,
        scale: MapDownloadScale = .close,
        sendToWatch: Bool = false
    ) {
        enqueue(
            CoverageRequest(
                id: UUID(),
                name: name,
                kind: .area,
                routeID: nil,
                centre: centre,
                radiusMetres: radiusMetres,
                plan: scale.plan(around: centre, radiusMetres: radiusMetres, detail: detail),
                sendToWatch: sendToWatch && scale.allowsWatch
            )
        )
    }

    /// Covers every route not already part of the map.
    ///
    /// The "everywhere I go" button. Each route in turn — and because the map is
    /// shared, every route after the first only fetches ground the ones before
    /// it did not already bring in.
    func addAll(routes: [PlannedRoute], sendToWatch: Bool = false) {
        let pending = routes.filter { !covers(routeID: $0.id) && !$0.coordinates.isEmpty }
        guard !pending.isEmpty else {
            progress = .alreadyCovered
            return
        }

        for route in pending {
            add(route: route, sendToWatch: sendToWatch)
        }
    }

    // MARK: - The queue

    /// Lines a download up and starts it if nothing else is running.
    private func enqueue(_ request: CoverageRequest) {
        queue.append(request)
        queuedNames = queue.map(\.name)
        startNext()
    }

    private func startNext() {
        guard task == nil, !queue.isEmpty else { return }

        let request = queue.removeFirst()
        queuedNames = queue.map(\.name)
        activeRouteID = request.routeID
        activeName = request.name
        progress = .planning

        let generation = self.generation
        task = Task { [weak self] in
            guard let self else { return }
            await self.run(request)
            // Everything was stopped while this was unwinding; the cancel has
            // already cleared the queue and the state, so leave it alone.
            guard self.generation == generation else { return }
            self.activeRouteID = nil
            self.activeName = nil
            self.task = nil
            self.startNext()
        }
    }

    /// Drops a download that has not started yet.
    func removeFromQueue(at index: Int) {
        guard queue.indices.contains(index) else { return }
        queue.remove(at: index)
        queuedNames = queue.map(\.name)
    }

    /// Tops up the areas the athlete keeps setting off from.
    ///
    /// Deliberately unobtrusive: one area per call, never while another download
    /// is running, and never in front of something they actually asked for.
    func refreshHomeAreas(from activities: [ActivityRecord], limit: Int = 2) {
        guard !isWorking else { return }

        let areas = HomeAreaFinder.areas(from: activities).prefix(limit)
        for area in areas {
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
        // Trekka's own housekeeping never queues in front of something the
        // athlete asked for, and never joins a queue either.
        guard !isWorking else { return }

        enqueue(
            CoverageRequest(
                id: UUID(),
                name: name,
                kind: .home,
                routeID: nil,
                centre: centre,
                radiusMetres: radiusMetres,
                plan: MapPackPlanner.plan(around: centre, radiusMetres: radiusMetres),
                // Starting areas stay on the phone. The watch's storage is
                // better spent on the route actually being walked.
                sendToWatch: false
            )
        )
    }

    private struct CoverageRequest {
        var id: UUID
        var name: String
        var kind: MapCoverageKind
        var routeID: UUID?
        var centre: CLLocationCoordinate2D?
        var radiusMetres: Double?
        var plan: MapPackPlanner.Plan
        var sendToWatch: Bool
    }

    private func run(_ request: CoverageRequest) async {
        guard !request.plan.isEmpty else {
            progress = .failed(MapPackError.noRoute.localizedDescription)
            return
        }

        // Only ground the map does not already hold. This subtraction is the
        // whole reason there is one map: shared ground is fetched once, ever.
        let missingVector = request.plan.vector.filter {
            !holds(kind: MapPackFormat.vectorKind, key: $0)
        }
        let missingTerrain = request.plan.terrain.filter {
            !holds(kind: MapPackFormat.terrainKind, key: $0)
        }
        let total = missingVector.count + missingTerrain.count

        if total == 0 {
            register(request)
            deliver(request)
            if case .failed = progress { return }
            progress = .alreadyCovered
            return
        }

        var completed = 0
        var storedTiles = 0
        progress = .downloading(completed: 0, total: total)

        // Fetched and written in batches rather than all at once: a region is
        // thousands of pieces, and a download that has to finish before a single
        // byte is saved is one that loses everything when it is interrupted.
        let batches: [(flavour: MapTileFlavour, keys: [TopoTileKey])] =
            missingVector.chunked(into: Self.writeBatchSize).map { (.vector, $0) }
            + missingTerrain.chunked(into: Self.writeBatchSize).map { (.terrain, $0) }

        for batch in batches {
            let alreadyDone = completed
            do {
                try Task.checkCancellation()
                let fetched = try await fetch(batch.flavour, keys: batch.keys) { [weak self] arrived in
                    self?.progress = .downloading(completed: alreadyDone + arrived, total: total)
                }
                completed = alreadyDone + batch.keys.count
                progress = .downloading(completed: completed, total: total)

                // A batch of open sea legitimately comes back with nothing.
                guard !fetched.isEmpty else { continue }
                try rebuild(
                    addingVector: batch.flavour == .vector ? fetched : [:],
                    addingTerrain: batch.flavour == .terrain ? fetched : [:]
                )
                storedTiles += fetched.count
            } catch is CancellationError {
                keepWhatArrived(request, storedTiles: storedTiles)
                progress = .idle
                return
            } catch {
                keepWhatArrived(request, storedTiles: storedTiles)
                progress = .failed(error.localizedDescription)
                EventLog.shared.failure(
                    "Offline map",
                    "Download of \(request.name) stopped after \(completed) of \(total) tiles",
                    detail: error.localizedDescription
                )
                return
            }
        }

        // Every tile 404'd, which means the plan covered ground the sources do
        // not have rather than a download that failed.
        guard storedTiles > 0 else {
            progress = .failed("No map data covers that area.")
            EventLog.shared.warning(
                "Offline map",
                "No map data covers \(request.name)",
                detail: "All \(total) tiles came back empty, so the area has no coverage upstream."
            )
            return
        }

        progress = .writing
        register(request)
        // The renderer may be holding tiles fetched over the network for this
        // ground; dropping them lets the stored map take over.
        await TopoTileSource.shared.purge()

        deliver(request)
        if case .failed = progress { return }

        // Ready means the phone has it. Whether the watch has it is a separate
        // question, answered by the watch itself.
        progress = .ready
        EventLog.shared.info(
            "Offline map",
            "Stored \(request.name)",
            detail: "\(storedTiles) new pieces of ground, of \(total) planned."
        )
    }

    /// Fetches a batch of tiles several at a time.
    ///
    /// `onArrival` is called with the running count so a long batch still moves
    /// the bar, rather than jumping once at the end.
    private func fetch(
        _ flavour: MapTileFlavour,
        keys: [TopoTileKey],
        onArrival: @escaping (Int) -> Void
    ) async throws -> [TopoTileKey: Data] {
        guard !keys.isEmpty else { return [:] }
        var result: [TopoTileKey: Data] = [:]
        var arrived = 0

        try await withThrowingTaskGroup(of: (TopoTileKey, Data?).self) { group in
            var next = 0
            // A fixed number in flight: the group is topped up as answers come
            // back rather than being handed every tile at once, which would put
            // thousands of requests on a community tile server in one breath.
            while next < min(Self.fetchConcurrency, keys.count) {
                group.addTask { [key = keys[next]] in
                    (key, try await Self.download(flavour, key))
                }
                next += 1
            }

            while let (key, data) = try await group.next() {
                if let data { result[key] = data }
                arrived += 1
                onArrival(arrived)

                if next < keys.count {
                    group.addTask { [key = keys[next]] in
                        (key, try await Self.download(flavour, key))
                    }
                    next += 1
                }
            }
        }

        return result
    }

    private nonisolated static func download(
        _ flavour: MapTileFlavour,
        _ key: TopoTileKey
    ) async throws -> Data? {
        switch flavour {
        case .vector: try await TopoTileSource.shared.rawVectorTileData(key)
        case .terrain: try await TopoTileSource.shared.rawTerrainTileData(key)
        }
    }

    /// Keeps the ground a stopped download had already written.
    ///
    /// Bytes on disk are bytes nobody has to fetch again, so a region download
    /// that was cancelled halfway is recorded for exactly what it holds. A route
    /// is the one exception: it claims to be usable offline, and a half-covered
    /// route making that claim is the single lie this feature cannot afford, so
    /// its part-finished ground is given back instead.
    private func keepWhatArrived(_ request: CoverageRequest, storedTiles: Int) {
        guard storedTiles > 0 else { return }
        guard request.kind != .route else {
            compact()
            return
        }

        let heldVector = request.plan.vector.filter {
            holds(kind: MapPackFormat.vectorKind, key: $0)
        }
        let heldTerrain = request.plan.terrain.filter {
            holds(kind: MapPackFormat.terrainKind, key: $0)
        }
        guard !heldVector.isEmpty || !heldTerrain.isEmpty else {
            compact()
            return
        }

        var partial = request
        partial.plan = MapPackPlanner.Plan(vector: heldVector, terrain: heldTerrain)
        register(partial)
        EventLog.shared.info(
            "Offline map",
            "Kept the part of \(request.name) that had downloaded",
            detail: "\(heldVector.count + heldTerrain.count) of \(request.plan.total) pieces stored."
        )
    }

    /// Records what the map now covers.
    private func register(_ request: CoverageRequest) {
        let entry = MapCoverage(
            id: request.id,
            name: request.name,
            kind: request.kind,
            routeID: request.routeID,
            centre: request.centre,
            radiusMetres: request.radiusMetres,
            vectorKeys: request.plan.vector,
            terrainKeys: request.plan.terrain
        )

        if let index = coverage.firstIndex(where: { $0.id == entry.id }) {
            coverage[index] = entry
        } else {
            coverage.append(entry)
        }
        persistCoverage()

        if let routeID = request.routeID {
            onRouteMapChanged?(routeID, true)
        }
    }

    private func deliver(_ request: CoverageRequest) {
        guard request.sendToWatch else { return }
        progress = .sendingToWatch
        if let block = sendToWatch(coverageID: request.id) {
            // The phone still has the ground, so this is not a failure of the
            // download — say exactly that, and name the real reason.
            progress = .failed("Map saved on your phone. \(block.message)")
            EventLog.shared.warning(
                "Watch",
                "\(request.name) saved on the phone but not sent to the watch",
                detail: block.message
            )
        }
    }

    /// Stops the download in progress and empties the queue behind it.
    func cancel() {
        generation += 1
        queue.removeAll()
        queuedNames = []
        task?.cancel()
        task = nil
        activeRouteID = nil
        activeName = nil
        progress = .idle
    }

    func clearStatus() {
        guard !progress.isBusy else { return }
        progress = .idle
    }

    // MARK: - Writing the map

    /// Writes the map again with new ground folded in.
    ///
    /// The old file stays open while the new one is written, so ground already
    /// stored is streamed straight across — never loaded into memory whole, and
    /// never fetched a second time.
    private func rebuild(
        addingVector: [TopoTileKey: Data],
        addingTerrain: [TopoTileKey: Data]
    ) throws {
        var writes: [MapPackFormat.TileWrite] = []

        if let library {
            for ref in library.tileRefs {
                // A tile being replaced by a fresh download is written from the
                // new bytes rather than copied from the old file.
                if ref.kind == MapPackFormat.vectorKind, addingVector[ref.key] != nil { continue }
                if ref.kind == MapPackFormat.terrainKind, addingTerrain[ref.key] != nil { continue }
                let kind = ref.kind
                let key = ref.key
                writes.append(
                    MapPackFormat.TileWrite(kind: kind, key: key, length: ref.length) {
                        library.rawData(kind: kind, key: key)
                    }
                )
            }
        }

        for (key, data) in addingVector {
            writes.append(
                MapPackFormat.TileWrite(
                    kind: MapPackFormat.vectorKind,
                    key: key,
                    length: data.count
                ) { data }
            )
        }
        for (key, data) in addingTerrain {
            writes.append(
                MapPackFormat.TileWrite(
                    kind: MapPackFormat.terrainKind,
                    key: key,
                    length: data.count
                ) { data }
            )
        }

        try write(tiles: writes)
    }

    private func write(tiles: [MapPackFormat.TileWrite]) throws {
        guard !tiles.isEmpty else {
            clearLibraryFile()
            return
        }

        let url = try libraryURL()
        try MapPackFormat.compose(
            manifestID: libraryID,
            name: "Trekka offline map",
            kind: .area,
            routeID: nil,
            centreLatitude: nil,
            centreLongitude: nil,
            tiles: tiles,
            to: url
        )

        library = nil
        let reader = try MapPackReader(url: url)
        library = reader
        bridge.replace(readers: [reader])
        refreshTotals()
    }

    private struct TileAddress: Hashable {
        let kind: String
        let key: TopoTileKey
    }

    /// Rewrites the map keeping only ground something still needs.
    ///
    /// Because coverage shares tiles, removing one place cannot just delete a
    /// file: the valley it crossed may be the same valley another route needs.
    /// So the map is rebuilt from what remains — entirely from bytes already on
    /// the phone, with no network and nothing re-downloaded.
    private func compact() {
        guard let library else { return }

        var needed: Set<TileAddress> = []
        for entry in coverage {
            for key in entry.vectorKeys {
                needed.insert(TileAddress(kind: MapPackFormat.vectorKind, key: key))
            }
            for key in entry.terrainKeys {
                needed.insert(TileAddress(kind: MapPackFormat.terrainKind, key: key))
            }
        }

        guard !needed.isEmpty else {
            clearLibraryFile()
            Task { await TopoTileSource.shared.purge() }
            return
        }

        let refs = library.tileRefs
        let keep = refs.filter { needed.contains(TileAddress(kind: $0.kind, key: $0.key)) }
        // Everything left is still wanted, so there is nothing to reclaim and
        // no reason to rewrite a large file.
        guard keep.count < refs.count else { return }

        let writes = keep.map { ref -> MapPackFormat.TileWrite in
            let kind = ref.kind
            let key = ref.key
            return MapPackFormat.TileWrite(kind: kind, key: key, length: ref.length) {
                library.rawData(kind: kind, key: key)
            }
        }

        do {
            try write(tiles: writes)
            Task { await TopoTileSource.shared.purge() }
        } catch {
            // The map on disk is untouched when a rewrite fails, so the only
            // cost is space not reclaimed. Nothing the athlete has is lost.
        }
    }

    // MARK: - Removing

    func remove(coverageID: UUID) {
        guard let index = coverage.firstIndex(where: { $0.id == coverageID }) else { return }
        let removed = coverage.remove(at: index)
        persistCoverage()
        compact()
        if let routeID = removed.routeID {
            onRouteMapChanged?(routeID, false)
        }
    }

    func removeAll() {
        let routeIDs = coverage.compactMap(\.routeID)
        coverage = []
        persistCoverage()
        clearLibraryFile()
        for routeID in routeIDs {
            onRouteMapChanged?(routeID, false)
        }
        Task { await TopoTileSource.shared.purge() }
    }

    private func clearLibraryFile() {
        library = nil
        bridge.replace(readers: [])
        if let url = try? libraryURL() {
            try? FileManager.default.removeItem(at: url)
        }
        refreshTotals()
    }

    // MARK: - The watch

    /// Builds a copy of one piece of coverage and sends it to the watch.
    ///
    /// The watch cannot take the whole map — its storage is a fraction of the
    /// phone's — so what travels is a pack cut from the library for that route
    /// or area alone. No tiles are re-downloaded: every byte comes off the disk.
    @discardableResult
    func sendToWatch(coverageID: UUID) -> WatchSendBlock? {
        guard let entry = entry(id: coverageID), let library else {
            lastSendBlock = nil
            return nil
        }

        var writes: [MapPackFormat.TileWrite] = []
        for key in entry.vectorKeys {
            guard let length = library.length(kind: MapPackFormat.vectorKind, key: key) else { continue }
            writes.append(
                MapPackFormat.TileWrite(
                    kind: MapPackFormat.vectorKind,
                    key: key,
                    length: length
                ) { library.rawData(kind: MapPackFormat.vectorKind, key: key) }
            )
        }
        for key in entry.terrainKeys {
            guard let length = library.length(kind: MapPackFormat.terrainKind, key: key) else { continue }
            writes.append(
                MapPackFormat.TileWrite(
                    kind: MapPackFormat.terrainKind,
                    key: key,
                    length: length
                ) { library.rawData(kind: MapPackFormat.terrainKind, key: key) }
            )
        }

        guard !writes.isEmpty else {
            lastSendBlock = nil
            return nil
        }

        do {
            // Built into the temporary directory: WatchConnectivity takes its
            // own copy, and keeping a second permanent copy of ground the map
            // already holds is exactly the duplication this design removed.
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(entry.id.uuidString).trekkapack")
            try MapPackFormat.compose(
                manifestID: entry.id,
                name: entry.name,
                kind: entry.packKind,
                routeID: entry.routeID,
                centreLatitude: entry.centreLatitude,
                centreLongitude: entry.centreLongitude,
                tiles: writes,
                to: url
            )

            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let bytes = (attributes?[.size] as? Int) ?? 0

            let block = WatchLink.shared.sendMapPack(
                fileURL: url,
                packID: entry.id,
                name: entry.name,
                sizeBytes: bytes
            )
            lastSendBlock = block
            return block
        } catch {
            lastSendBlock = nil
            return nil
        }
    }

    /// Sends everything the watch is not already holding.
    @discardableResult
    func sendMissingToWatch() -> WatchSendBlock? {
        let onWatch = WatchLink.shared.watchInventory
        var firstBlock: WatchSendBlock?
        for entry in coverage where entry.kind != .home {
            if onWatch?.hasPack(id: entry.id) == true { continue }
            if let block = sendToWatch(coverageID: entry.id), firstBlock == nil {
                firstBlock = block
            }
        }
        lastSendBlock = firstBlock
        return firstBlock
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

    private func libraryURL() throws -> URL {
        try directory().appendingPathComponent(libraryFileName)
    }

    private func coverageURL() throws -> URL {
        try directory().appendingPathComponent(coverageFileName)
    }

    private func persistCoverage() {
        guard let url = try? coverageURL() else { return }
        do {
            let data = try JSONEncoder().encode(coverage)
            try data.write(to: url, options: .atomic)
        } catch {
            // Coverage describes the map rather than being it, so a failed
            // write costs the list, not the ground.
        }
    }

    private func loadCoverage() {
        guard let url = try? coverageURL(),
              let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode([MapCoverage].self, from: data) else { return }
        coverage = stored
    }

    private func refreshTotals() {
        guard let url = try? libraryURL(),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let bytes = attributes[.size] as? Int else {
            totalBytes = 0
            tileCount = 0
            return
        }
        totalBytes = bytes
        tileCount = library?.summary.tileCount ?? 0
    }

    /// Brings the route library into line with the map actually on disk.
    ///
    /// Called at launch because the map can be removed by iOS reclaiming
    /// storage, and a stale flag would then promise the watch ground that is
    /// gone. Coverage for routes that no longer exist is dropped here too.
    func reconcile(with routes: [PlannedRoute]) {
        let live = Set(routes.map(\.id))
        let staleIDs = Set(
            coverage
                .filter { entry in
                    guard let routeID = entry.routeID else { return false }
                    return !live.contains(routeID)
                }
                .map(\.id)
        )

        if !staleIDs.isEmpty {
            coverage.removeAll { staleIDs.contains($0.id) }
            persistCoverage()
            compact()
        }

        for route in routes {
            let stored = covers(routeID: route.id)
            if stored != route.isOfflineDownloaded {
                onRouteMapChanged?(route.id, stored)
            }
        }
    }

    private func loadFromDisk() {
        migrateLegacyPacks()
        loadCoverage()

        if let url = try? libraryURL(), FileManager.default.fileExists(atPath: url.path) {
            if let reader = try? MapPackReader(url: url) {
                library = reader
                bridge.replace(readers: [reader])
            } else {
                // A damaged map is worse than no map: it would draw holes in
                // ground the athlete was told they had.
                try? FileManager.default.removeItem(at: url)
                coverage = []
                persistCoverage()
            }
        } else if !coverage.isEmpty {
            // The map went without the list, so the list is a lie. Say nothing
            // is covered rather than claim ground that is not there.
            coverage = []
            persistCoverage()
        }

        refreshTotals()
    }

    /// Folds the old one-file-per-route packs into the single map.
    ///
    /// Trekka used to keep a separate download for every route, so two routes
    /// over the same ground stored it twice. Those files are merged here, once,
    /// and each becomes a piece of coverage holding exactly the tiles it had —
    /// so nothing the athlete downloaded is lost, and the duplication between
    /// them disappears on the way in.
    private func migrateLegacyPacks() {
        guard let directory = try? directory(),
              let files = try? FileManager.default.contentsOfDirectory(
                  at: directory,
                  includingPropertiesForKeys: nil
              ) else { return }

        let legacy = files.filter {
            $0.pathExtension == "trekkapack" && $0.lastPathComponent != libraryFileName
        }
        guard !legacy.isEmpty else { return }

        var readers: [MapPackReader] = []
        for file in legacy {
            if let reader = try? MapPackReader(url: file) {
                readers.append(reader)
            } else {
                try? FileManager.default.removeItem(at: file)
            }
        }
        guard !readers.isEmpty else { return }

        var sources: [MapPackReader] = []
        if let url = try? libraryURL(),
           FileManager.default.fileExists(atPath: url.path),
           let existing = try? MapPackReader(url: url) {
            sources.append(existing)
        }
        sources.append(contentsOf: readers)

        var seen: Set<TileAddress> = []
        var writes: [MapPackFormat.TileWrite] = []
        for source in sources {
            for ref in source.tileRefs {
                let address = TileAddress(kind: ref.kind, key: ref.key)
                guard !seen.contains(address) else { continue }
                seen.insert(address)
                let kind = ref.kind
                let key = ref.key
                writes.append(
                    MapPackFormat.TileWrite(kind: kind, key: key, length: ref.length) {
                        source.rawData(kind: kind, key: key)
                    }
                )
            }
        }
        guard !writes.isEmpty else { return }

        var migrated: [MapCoverage] = []
        for reader in readers {
            let summary = reader.summary
            var vector: [TopoTileKey] = []
            var terrain: [TopoTileKey] = []
            for ref in reader.tileRefs {
                if ref.kind == MapPackFormat.vectorKind {
                    vector.append(ref.key)
                } else {
                    terrain.append(ref.key)
                }
            }
            migrated.append(
                MapCoverage(
                    id: summary.id,
                    name: summary.name,
                    kind: MapPackStore.coverageKind(from: summary.kind),
                    routeID: summary.routeID,
                    centre: summary.centreLatitude.flatMap { latitude in
                        summary.centreLongitude.map {
                            CLLocationCoordinate2D(latitude: latitude, longitude: $0)
                        }
                    },
                    radiusMetres: nil,
                    addedAt: summary.createdAt,
                    vectorKeys: vector,
                    terrainKeys: terrain
                )
            )
        }

        do {
            try MapPackFormat.compose(
                manifestID: libraryID,
                name: "Trekka offline map",
                kind: .area,
                routeID: nil,
                centreLatitude: nil,
                centreLongitude: nil,
                tiles: writes,
                to: try libraryURL()
            )
        } catch {
            // Leave the old files exactly where they are. A failed merge must
            // not be the reason someone loses maps they already downloaded.
            return
        }

        // The merge succeeded, so the old files are safe to remove.
        for file in legacy {
            try? FileManager.default.removeItem(at: file)
        }

        loadCoverage()
        let known = Set(coverage.map(\.id))
        coverage.append(contentsOf: migrated.filter { !known.contains($0.id) })
        persistCoverage()
    }

    private nonisolated static func coverageKind(from kind: MapPackKind) -> MapCoverageKind {
        switch kind {
        case .route: .route
        case .area: .area
        case .home: .home
        }
    }
}
