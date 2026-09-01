import Foundation

/// What a stored pack covers.
nonisolated enum MapPackKind: String, Codable, Sendable {
    /// A corridor following one saved route.
    case route
    /// A square of ground kept ready around a place the athlete starts from.
    case home
}

/// The index at the front of a pack file.
nonisolated struct MapPackManifest: Codable, Sendable {
    /// One tile inside the pack, and where to find its bytes.
    nonisolated struct Entry: Codable, Sendable {
        /// `v` for a vector basemap tile, `t` for a terrain height tile.
        var kind: String
        var z: Int
        var x: Int
        var y: Int
        /// Offset from the start of the payload block.
        var offset: Int
        var length: Int
    }

    var id: UUID
    var name: String
    var kind: MapPackKind
    var createdAt: Date
    /// The route this corridor follows, for route packs.
    var routeID: UUID?
    /// Centre of a home area, so it can be matched again later.
    var centreLatitude: Double?
    var centreLongitude: Double?
    var entries: [Entry]

    var tileCount: Int { entries.count }
    var payloadBytes: Int { entries.reduce(0) { $0 + $1.length } }
}

/// A pack on disk, without its tile bytes loaded.
nonisolated struct MapPackSummary: Identifiable, Sendable, Hashable {
    var id: UUID
    var name: String
    var kind: MapPackKind
    var createdAt: Date
    var routeID: UUID?
    var tileCount: Int
    /// Real size of the file on disk. Never an estimate.
    var fileBytes: Int
    /// Centre of a home area, so it can be matched against a location later.
    var centreLatitude: Double?
    var centreLongitude: Double?

    var sizeDescription: String {
        MapPackFormat.describe(bytes: fileBytes)
    }
}

/// Trekka's offline map container.
///
/// One file per pack: a short header, a JSON index, then the raw tile bytes
/// concatenated. Chosen over a folder of loose files for two reasons — the watch
/// bridge can only ship a single file per transfer, and one file keeps a pack
/// atomic, so a pack is either wholly there or not there at all.
///
/// Tiles are stored exactly as they arrived over the network, so reading a pack
/// feeds the very same decoders the online path uses.
nonisolated enum MapPackFormat {
    static let magic = "TRKPACK1"
    private static let magicLength = 8

    static let vectorKind = "v"
    static let terrainKind = "t"

    /// Builds a pack file from tile bytes already in hand.
    static func write(
        manifestID: UUID,
        name: String,
        kind: MapPackKind,
        routeID: UUID?,
        centreLatitude: Double?,
        centreLongitude: Double?,
        vectorTiles: [TopoTileKey: Data],
        terrainTiles: [TopoTileKey: Data],
        to url: URL
    ) throws {
        var entries: [MapPackManifest.Entry] = []
        var payload = Data()

        // Sorted so a pack built from the same tiles is byte-identical, which
        // makes "has this changed?" answerable by size and date alone.
        for key in vectorTiles.keys.sorted(by: MapPackFormat.ordered) {
            guard let data = vectorTiles[key], !data.isEmpty else { continue }
            entries.append(
                MapPackManifest.Entry(
                    kind: vectorKind,
                    z: key.z,
                    x: key.x,
                    y: key.y,
                    offset: payload.count,
                    length: data.count
                )
            )
            payload.append(data)
        }

        for key in terrainTiles.keys.sorted(by: MapPackFormat.ordered) {
            guard let data = terrainTiles[key], !data.isEmpty else { continue }
            entries.append(
                MapPackManifest.Entry(
                    kind: terrainKind,
                    z: key.z,
                    x: key.x,
                    y: key.y,
                    offset: payload.count,
                    length: data.count
                )
            )
            payload.append(data)
        }

        let manifest = MapPackManifest(
            id: manifestID,
            name: name,
            kind: kind,
            createdAt: Date(),
            routeID: routeID,
            centreLatitude: centreLatitude,
            centreLongitude: centreLongitude,
            entries: entries
        )

        let manifestData = try JSONEncoder().encode(manifest)
        var file = Data()
        file.append(contentsOf: Array(magic.utf8))
        var length = UInt32(manifestData.count).littleEndian
        withUnsafeBytes(of: &length) { file.append(contentsOf: $0) }
        file.append(manifestData)
        file.append(payload)

        try file.write(to: url, options: .atomic)
    }

    /// Reads the index and says where the tile bytes begin.
    ///
    /// The payload offset comes from the length written into the header, never
    /// from re-encoding the manifest. Re-encoding looks equivalent but is not:
    /// a date or a float that round-trips to a different number of characters
    /// would shift the offset, and every tile in the pack would then be read
    /// from the wrong place — silently, as plausible-looking rubbish.
    static func read(at url: URL) throws -> (manifest: MapPackManifest, payloadStart: Int) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        guard let header = try handle.read(upToCount: magicLength + 4),
              header.count == magicLength + 4 else {
            throw MapPackError.malformed
        }
        guard String(decoding: header.prefix(magicLength), as: UTF8.self) == magic else {
            throw MapPackError.malformed
        }

        let lengthBytes = header.suffix(4)
        let manifestLength = lengthBytes.withUnsafeBytes { raw in
            Int(UInt32(littleEndian: raw.loadUnaligned(as: UInt32.self)))
        }
        guard manifestLength > 0, manifestLength < 32 * 1024 * 1024 else {
            throw MapPackError.malformed
        }

        guard let manifestData = try handle.read(upToCount: manifestLength),
              manifestData.count == manifestLength else {
            throw MapPackError.malformed
        }

        let manifest = try JSONDecoder().decode(MapPackManifest.self, from: manifestData)
        return (manifest, magicLength + 4 + manifestLength)
    }

    /// Human-readable size, rounded the way people talk about files.
    static func describe(bytes: Int) -> String {
        let megabytes = Double(bytes) / 1_048_576
        if megabytes >= 10 {
            return "\(Int(megabytes.rounded())) MB"
        }
        if megabytes >= 1 {
            return String(format: "%.1f MB", megabytes)
        }
        let kilobytes = max(1, Int((Double(bytes) / 1024).rounded()))
        return "\(kilobytes) KB"
    }

    private static func ordered(_ lhs: TopoTileKey, _ rhs: TopoTileKey) -> Bool {
        if lhs.z != rhs.z { return lhs.z < rhs.z }
        if lhs.x != rhs.x { return lhs.x < rhs.x }
        return lhs.y < rhs.y
    }
}

nonisolated enum MapPackError: LocalizedError {
    case malformed
    case noRoute
    case tooLarge
    case offline

    var errorDescription: String? {
        switch self {
        case .malformed:
            "That offline map is damaged. Delete it and download it again."
        case .noRoute:
            "This route has no points to download a map for."
        case .tooLarge:
            "That area is too large for one offline map. Try a shorter route."
        case .offline:
            "No connection. Offline maps have to be downloaded while you have signal."
        }
    }
}

/// Hands pack tiles to the tile source.
///
/// Deliberately a plain reference type with its own lock rather than an actor or
/// a main-actor store: the tile source reads from it on whatever thread it likes,
/// and it must not have to hop actors to answer. Both apps share it, which is why
/// it lives beside the pack format rather than with either store.
nonisolated final class MapPackBridge: TopoLocalTileStore, @unchecked Sendable {
    private var readers: [MapPackReader] = []
    private let lock = NSLock()

    func replace(readers newReaders: [MapPackReader]) {
        lock.lock()
        readers = newReaders
        lock.unlock()
    }

    func vectorTileData(_ key: TopoTileKey) -> Data? {
        for reader in current() {
            if let data = reader.vectorTileData(key) { return data }
        }
        return nil
    }

    func terrainTileData(_ key: TopoTileKey) -> Data? {
        for reader in current() {
            if let data = reader.terrainTileData(key) { return data }
        }
        return nil
    }

    private func current() -> [MapPackReader] {
        lock.lock()
        defer { lock.unlock() }
        return readers
    }
}

/// Random access to the tiles inside one pack file.
///
/// Reads through a file handle rather than loading the pack into memory: a
/// pack can run to tens of megabytes, and the watch has none to spare.
nonisolated final class MapPackReader: @unchecked Sendable {
    let summary: MapPackSummary
    private let url: URL
    private let payloadStart: Int
    private var index: [TileIndexKey: (offset: Int, length: Int)]
    private let handle: FileHandle
    private let lock = NSLock()

    private struct TileIndexKey: Hashable {
        let kind: String
        let z: Int
        let x: Int
        let y: Int
    }

    init(url: URL) throws {
        self.url = url
        let (manifest, payloadStart) = try MapPackFormat.read(at: url)
        self.payloadStart = payloadStart
        self.handle = try FileHandle(forReadingFrom: url)

        var index: [TileIndexKey: (offset: Int, length: Int)] = [:]
        for entry in manifest.entries {
            let key = TileIndexKey(kind: entry.kind, z: entry.z, x: entry.x, y: entry.y)
            index[key] = (entry.offset, entry.length)
        }
        self.index = index

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileBytes = (attributes?[.size] as? Int) ?? 0
        self.summary = MapPackSummary(
            id: manifest.id,
            name: manifest.name,
            kind: manifest.kind,
            createdAt: manifest.createdAt,
            routeID: manifest.routeID,
            tileCount: manifest.tileCount,
            fileBytes: fileBytes,
            centreLatitude: manifest.centreLatitude,
            centreLongitude: manifest.centreLongitude
        )
    }

    deinit {
        try? handle.close()
    }

    func vectorTileData(_ key: TopoTileKey) -> Data? {
        data(kind: MapPackFormat.vectorKind, key: key)
    }

    func terrainTileData(_ key: TopoTileKey) -> Data? {
        data(kind: MapPackFormat.terrainKind, key: key)
    }

    private func data(kind: String, key: TopoTileKey) -> Data? {
        let indexKey = TileIndexKey(kind: kind, z: key.z, x: key.x, y: key.y)
        guard let entry = index[indexKey] else { return nil }

        // One handle shared across readers, so seek and read must not interleave.
        lock.lock()
        defer { lock.unlock() }
        do {
            try handle.seek(toOffset: UInt64(payloadStart + entry.offset))
            return try handle.read(upToCount: entry.length)
        } catch {
            return nil
        }
    }
}
