import Foundation

/// Somewhere tiles can be read with no network — an offline pack.
///
/// Kept as a protocol so the renderer never learns whether ground came off the
/// wire or off the disk. That is precisely what lets one map work in both cases
/// instead of there being an "offline map" with its own quirks.
nonisolated protocol TopoLocalTileStore: AnyObject, Sendable {
    func vectorTileData(_ key: TopoTileKey) -> Data?
    func terrainTileData(_ key: TopoTileKey) -> Data?
}

/// Fetches and decodes the tiles Trekka's map is drawn from.
///
/// Two independent sources feed one map:
///
/// - **Vector basemap** — OpenStreetMap data served as Mapbox Vector Tiles by
///   OpenFreeMap's public instance. Vector rather than pre-rendered pictures for
///   three reasons: the styling stays ours, one tile serves every zoom, and the
///   payload is small enough to keep on a watch.
/// - **Terrain** — height tiles from the AWS Terrain Tiles open dataset, traced
///   into contour lines on the device.
///
/// Decoding happens inside the actor, off the main thread, and results are held
/// in a small cache so panning does not re-parse ground already seen.
actor TopoTileSource {
    static let shared = TopoTileSource()

    /// Shown wherever the map appears, as both licences expect.
    static let attribution = "© OpenStreetMap contributors · OpenFreeMap · AWS Terrain Tiles"

    /// The basemap is cut to zoom 14; past that the z14 tile is drawn larger.
    static let maximumVectorZoom = 14

    private let tileJSONEndpoint = "https://tiles.openfreemap.org/planet"
    private let terrainHost = "https://s3.amazonaws.com/elevation-tiles-prod/terrarium"

    /// The tile path carries a build date that rolls over weekly, so it is
    /// discovered from the source's TileJSON rather than hardcoded, then
    /// remembered for next launch.
    private let templateDefaultsKey = "topo.tileTemplate"
    private var cachedTemplate: String?
    private var templateTask: Task<String?, Never>?

    private let session: URLSession

    /// Consulted before the network, so downloaded ground is both instant and
    /// free of data charges.
    private weak var localStore: (any TopoLocalTileStore)?

    private var vectorTiles: [TopoTileKey: VectorTile] = [:]
    private var vectorOrder: [TopoTileKey] = []
    private var vectorTasks: [TopoTileKey: Task<VectorTile?, Never>] = [:]

    private var contourTiles: [TopoTileKey: ContourTile] = [:]
    private var contourOrder: [TopoTileKey] = []
    private var contourTasks: [TopoTileKey: Task<ContourTile?, Never>] = [:]

    /// Enough to cover a screen and its surroundings several times over without
    /// letting a long pan grow without bound.
    private let vectorCacheLimit = 90
    private let contourCacheLimit = 60

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 20
            // The system cache absorbs the repeated fetches that panning back
            // and forth would otherwise cause.
            configuration.requestCachePolicy = .returnCacheDataElseLoad
            configuration.urlCache = URLCache(
                memoryCapacity: 8 * 1024 * 1024,
                diskCapacity: 96 * 1024 * 1024,
                diskPath: "topo-tiles"
            )
            self.session = URLSession(configuration: configuration)
        }
        self.cachedTemplate = UserDefaults.standard.string(forKey: templateDefaultsKey)
    }

    /// Points the source at the offline packs.
    func attach(local store: (any TopoLocalTileStore)?) {
        localStore = store
    }

    // MARK: - Cached reads

    /// A decoded tile if it is already in hand, for drawing without waiting.
    func cachedVectorTile(_ key: TopoTileKey) -> VectorTile? {
        vectorTiles[key]
    }

    func cachedContourTile(_ key: TopoTileKey) -> ContourTile? {
        contourTiles[key]
    }

    // MARK: - Vector basemap

    func vectorTile(_ key: TopoTileKey) async -> VectorTile? {
        if let tile = vectorTiles[key] { return tile }
        if let existing = vectorTasks[key] { return await existing.value }

        let task = Task<VectorTile?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.loadVectorTile(key)
        }
        vectorTasks[key] = task
        let tile = await task.value
        vectorTasks[key] = nil

        if let tile {
            store(vector: tile, for: key)
        }
        return tile
    }

    private func loadVectorTile(_ key: TopoTileKey) async -> VectorTile? {
        // Downloaded ground wins: it is on disk, so it is faster than the
        // network and works when there is none.
        if let data = localStore?.vectorTileData(key) {
            return VectorTileDecoder.decode(data, layers: TopoStyle.sourceLayers)
        }
        guard let template = await tileTemplate() else { return nil }
        let path = template
            .replacingOccurrences(of: "{z}", with: String(key.z))
            .replacingOccurrences(of: "{x}", with: String(key.x))
            .replacingOccurrences(of: "{y}", with: String(key.y))
        guard let url = URL(string: path) else { return nil }

        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse {
                // Empty ocean tiles legitimately come back as 404s.
                guard (200..<300).contains(http.statusCode) else { return nil }
            }
            guard !data.isEmpty else { return VectorTile.empty }
            return VectorTileDecoder.decode(data, layers: TopoStyle.sourceLayers)
        } catch is CancellationError {
            return nil
        } catch {
            return nil
        }
    }

    private func store(vector tile: VectorTile, for key: TopoTileKey) {
        if vectorTiles[key] == nil {
            vectorOrder.append(key)
        }
        vectorTiles[key] = tile
        while vectorOrder.count > vectorCacheLimit {
            let oldest = vectorOrder.removeFirst()
            vectorTiles[oldest] = nil
        }
    }

    // MARK: - Contours

    func contourTile(_ key: TopoTileKey) async -> ContourTile? {
        if let tile = contourTiles[key] { return tile }
        if let existing = contourTasks[key] { return await existing.value }

        let task = Task<ContourTile?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.loadContourTile(key)
        }
        contourTasks[key] = task
        let tile = await task.value
        contourTasks[key] = nil

        if let tile {
            store(contour: tile, for: key)
        }
        return tile
    }

    private func loadContourTile(_ key: TopoTileKey) async -> ContourTile? {
        if let data = localStore?.terrainTileData(key) {
            guard let samples = ContourBuilder.decodeTerrarium(data) else { return nil }
            return await Task.detached(priority: .utility) {
                ContourBuilder.build(samples: samples, key: key)
            }.value
        }

        let path = "\(terrainHost)/\(key.z)/\(key.x)/\(key.y).png"
        guard let url = URL(string: path) else { return nil }

        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse {
                guard (200..<300).contains(http.statusCode) else { return nil }
            }
            guard let samples = ContourBuilder.decodeTerrarium(data) else { return nil }
            // Tracing is pure computation, so it runs off the actor rather than
            // holding it while a mountainside is worked through.
            return await Task.detached(priority: .utility) {
                ContourBuilder.build(samples: samples, key: key)
            }.value
        } catch is CancellationError {
            return nil
        } catch {
            return nil
        }
    }

    private func store(contour tile: ContourTile, for key: TopoTileKey) {
        if contourTiles[key] == nil {
            contourOrder.append(key)
        }
        contourTiles[key] = tile
        while contourOrder.count > contourCacheLimit {
            let oldest = contourOrder.removeFirst()
            contourTiles[oldest] = nil
        }
    }

    // MARK: - Raw tiles, for building packs

    /// A basemap tile's bytes exactly as served.
    ///
    /// Packs store tiles unaltered, so reading one back feeds the very same
    /// decoder the online path uses. There is no second rendering path that
    /// could quietly drift out of agreement with the first.
    func rawVectorTileData(_ key: TopoTileKey) async throws -> Data? {
        guard let template = await tileTemplate() else { throw MapPackError.offline }
        let path = template
            .replacingOccurrences(of: "{z}", with: String(key.z))
            .replacingOccurrences(of: "{x}", with: String(key.x))
            .replacingOccurrences(of: "{y}", with: String(key.y))
        guard let url = URL(string: path) else { return nil }
        return try await fetchRaw(url)
    }

    func rawTerrainTileData(_ key: TopoTileKey) async throws -> Data? {
        let path = "\(terrainHost)/\(key.z)/\(key.x)/\(key.y).png"
        guard let url = URL(string: path) else { return nil }
        return try await fetchRaw(url)
    }

    /// Returns nil for a tile the server genuinely does not have — open sea and
    /// the like answer 404 — and throws only when the network itself fails, so a
    /// download can tell "nothing there" from "no signal".
    private func fetchRaw(_ url: URL) async throws -> Data? {
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return nil
            }
            return data.isEmpty ? nil : data
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw MapPackError.offline
        }
    }

    // MARK: - Tile template discovery

    private func tileTemplate() async -> String? {
        if let cachedTemplate { return cachedTemplate }
        if let templateTask { return await templateTask.value }

        let task = Task<String?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.fetchTileTemplate()
        }
        templateTask = task
        let template = await task.value
        templateTask = nil

        if let template {
            cachedTemplate = template
            UserDefaults.standard.set(template, forKey: templateDefaultsKey)
        }
        return template
    }

    private func fetchTileTemplate() async -> String? {
        guard let url = URL(string: tileJSONEndpoint) else { return nil }
        do {
            let (data, _) = try await session.data(from: url)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tiles = object["tiles"] as? [String],
                  let first = tiles.first else { return nil }
            return first
        } catch {
            // Offline on first run. A remembered template from a previous launch
            // is the fallback; without one the map simply has nothing to draw,
            // which the view reports honestly rather than showing a blank grid.
            return UserDefaults.standard.string(forKey: templateDefaultsKey)
        }
    }

    // MARK: - Housekeeping

    /// Drops everything held in memory. Used when the map goes away.
    func purge() {
        vectorTiles.removeAll()
        vectorOrder.removeAll()
        contourTiles.removeAll()
        contourOrder.removeAll()
    }
}
