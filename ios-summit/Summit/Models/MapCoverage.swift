import Foundation
import CoreLocation

/// Why a piece of ground is part of the offline map.
nonisolated enum MapCoverageKind: String, Codable, Sendable {
    /// Ground following one saved route.
    case route
    /// A square the athlete picked out on the map themselves.
    case area
    /// A square kept ready around a place they keep setting off from.
    case home
}

/// One place the offline map covers.
///
/// Trekka keeps a single offline map rather than one download per route. That
/// is the whole point of this type: coverage is a *request* — "keep this route",
/// "keep this square" — and the map is the union of every request, stored once.
/// Two routes that share a valley share its ground instead of each paying for
/// it, and adding a route that overlaps one already kept costs nothing at all.
///
/// The tiles a piece of coverage needs are recorded here rather than recomputed
/// later. Removing coverage has to work out what the map still needs, and doing
/// that from the original request would mean re-planning against a route that
/// may since have been edited or deleted — the answer would quietly differ from
/// what was actually downloaded, and the map would lose ground it should have
/// kept. The recorded list cannot drift.
nonisolated struct MapCoverage: Identifiable, Codable, Sendable, Hashable {
    var id: UUID
    var name: String
    var kind: MapCoverageKind
    /// The route this follows, when it follows one.
    var routeID: UUID?
    var centreLatitude: Double?
    var centreLongitude: Double?
    var radiusMetres: Double?
    var addedAt: Date

    /// Tiles needed, packed as `z/x/y` separated by spaces.
    ///
    /// Stored as one string rather than an array because a long route needs a
    /// couple of thousand of them, and a JSON array of that many short strings
    /// is mostly quotes and commas.
    var vectorTileList: String
    var terrainTileList: String

    var vectorKeys: [TopoTileKey] { MapCoverage.decode(vectorTileList) }
    var terrainKeys: [TopoTileKey] { MapCoverage.decode(terrainTileList) }

    var tileCount: Int {
        MapCoverage.count(in: vectorTileList) + MapCoverage.count(in: terrainTileList)
    }

    var centre: CLLocationCoordinate2D? {
        guard let centreLatitude, let centreLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: centreLatitude, longitude: centreLongitude)
    }

    /// How this coverage is labelled when a copy is sent to the watch.
    var packKind: MapPackKind {
        switch kind {
        case .route: .route
        case .area: .area
        case .home: .home
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        kind: MapCoverageKind,
        routeID: UUID? = nil,
        centre: CLLocationCoordinate2D? = nil,
        radiusMetres: Double? = nil,
        addedAt: Date = Date(),
        vectorKeys: [TopoTileKey],
        terrainKeys: [TopoTileKey]
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.routeID = routeID
        self.centreLatitude = centre?.latitude
        self.centreLongitude = centre?.longitude
        self.radiusMetres = radiusMetres
        self.addedAt = addedAt
        self.vectorTileList = MapCoverage.encode(vectorKeys)
        self.terrainTileList = MapCoverage.encode(terrainKeys)
    }

    // MARK: - Tile lists

    static func encode(_ keys: [TopoTileKey]) -> String {
        keys.map { "\($0.z)/\($0.x)/\($0.y)" }.joined(separator: " ")
    }

    static func decode(_ text: String) -> [TopoTileKey] {
        guard !text.isEmpty else { return [] }
        return text.split(separator: " ").compactMap { piece in
            let parts = piece.split(separator: "/")
            guard parts.count == 3,
                  let z = Int(parts[0]),
                  let x = Int(parts[1]),
                  let y = Int(parts[2]) else { return nil }
            return TopoTileKey(z: z, x: x, y: y)
        }
    }

    /// Counts without building the keys, for display.
    private static func count(in text: String) -> Int {
        text.isEmpty ? 0 : text.split(separator: " ").count
    }
}
