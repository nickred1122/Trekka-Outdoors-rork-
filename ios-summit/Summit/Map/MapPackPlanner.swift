import Foundation
import CoreLocation

/// Works out exactly which tiles an offline map needs.
///
/// The naive approach — take the box around a route and download every tile in
/// it — is enormously wasteful, because a route is a thin line and its bounding
/// box is mostly ground the athlete will never see. A 26-mile route needs on the
/// order of a thousand tiles as a corridor, against roughly sixteen thousand as
/// a rectangle.
///
/// So the corridor is walked instead: step along each leg of the route across the
/// tile grid, keep the tiles it crosses, and pad by a ring of neighbours so
/// there is ground either side of the line rather than a bare edge.
nonisolated enum MapPackPlanner {
    /// Basemap zooms stored in a pack.
    ///
    /// Four levels rather than one so the map can still be zoomed out offline.
    /// Coarser levels cost almost nothing — a tile covers four times the ground
    /// each step down — while 14 is where the paths and contours live.
    static let vectorZooms = [11, 12, 13, 14]

    /// Terrain stops at 13, which is the finest the height data is served at
    /// and already tighter than the contour interval needs.
    static let terrainZooms = [11, 12, 13]

    /// How wide the corridor is, as a ring of tiles either side of the line.
    ///
    /// One ring at the finest zoom is roughly a kilometre of margin, which is
    /// enough to see the valley you are walking through without paying for the
    /// next one over.
    static func padding(forZoom zoom: Int, widened: Bool) -> Int {
        if widened {
            return zoom >= 14 ? 3 : 2
        }
        return zoom >= 14 ? 1 : 1
    }

    /// A hard ceiling on any single pack, so a mistake cannot start a download
    /// that never ends.
    static let tileCeiling = 2_600

    // MARK: - Corridors

    /// Tiles covering a corridor along `coordinates` at one zoom.
    static func corridorTiles(
        along coordinates: [CLLocationCoordinate2D],
        zoom: Int,
        padding: Int
    ) -> Set<TopoTileKey> {
        guard !coordinates.isEmpty else { return [] }
        let tilesPerSide: Int = Int(pow(2.0, Double(zoom)))
        let limit: Int = tilesPerSide - 1

        // The line's own tiles first, then the padding ring, so a wide corridor
        // does not pad the padding.
        var spine: Set<TopoTileKey> = []

        func tileIndex(_ coordinate: CLLocationCoordinate2D) -> (x: Int, y: Int) {
            let world = TopoTileMath.world(coordinate)
            let x = Int((Double(world.x) * Double(tilesPerSide)).rounded(.down))
            let y = Int((Double(world.y) * Double(tilesPerSide)).rounded(.down))
            return (min(max(x, 0), limit), min(max(y, 0), limit))
        }

        if coordinates.count == 1 {
            let point = tileIndex(coordinates[0])
            spine.insert(TopoTileKey(z: zoom, x: point.x, y: point.y))
        }

        for index in 1..<max(coordinates.count, 1) {
            let from = tileIndex(coordinates[index - 1])
            let to = tileIndex(coordinates[index])
            for tile in line(from: from, to: to) {
                spine.insert(TopoTileKey(z: zoom, x: tile.x, y: tile.y))
            }
        }

        guard padding > 0 else { return spine }

        var result = spine
        for key in spine {
            for dx in -padding...padding {
                for dy in -padding...padding {
                    let x = key.x + dx
                    let y = key.y + dy
                    guard x >= 0, x <= limit, y >= 0, y <= limit else { continue }
                    result.insert(TopoTileKey(z: zoom, x: x, y: y))
                }
            }
        }
        return result
    }

    /// Tiles covering a square of ground around a point.
    static func areaTiles(
        around centre: CLLocationCoordinate2D,
        radiusMetres: Double,
        zoom: Int
    ) -> Set<TopoTileKey> {
        let tilesPerSide: Int = Int(pow(2.0, Double(zoom)))
        let limit: Int = tilesPerSide - 1
        let metresPerTile: Double = TopoTileMath.metresPerPixel(
            latitude: centre.latitude,
            zoom: Double(zoom)
        ) * TopoTileMath.tileSide
        guard metresPerTile > 0 else { return [] }

        let reach: Int = max(0, Int((radiusMetres / metresPerTile).rounded(.up)))
        let world = TopoTileMath.world(centre)
        let centreX = Int((Double(world.x) * Double(tilesPerSide)).rounded(.down))
        let centreY = Int((Double(world.y) * Double(tilesPerSide)).rounded(.down))

        var result: Set<TopoTileKey> = []
        for dx in -reach...reach {
            for dy in -reach...reach {
                let x = centreX + dx
                let y = centreY + dy
                guard x >= 0, x <= limit, y >= 0, y <= limit else { continue }
                result.insert(TopoTileKey(z: zoom, x: x, y: y))
            }
        }
        return result
    }

    // MARK: - Plans

    /// Everything one pack should contain.
    nonisolated struct Plan: Sendable {
        var vector: [TopoTileKey]
        var terrain: [TopoTileKey]

        var total: Int { vector.count + terrain.count }
        var isEmpty: Bool { total == 0 }

        /// Roughly what the download will weigh.
        ///
        /// Deliberately conservative, and only ever shown as an estimate — the
        /// figure the athlete is told after the fact is the real file size.
        var estimatedBytes: Int {
            vector.count * 46_000 + terrain.count * 62_000
        }
    }

    /// The corridor plan for a route.
    static func plan(for coordinates: [CLLocationCoordinate2D], widened: Bool) -> Plan {
        guard !coordinates.isEmpty else { return Plan(vector: [], terrain: []) }
        let thinned = thin(coordinates)

        var vector: [TopoTileKey] = []
        for zoom in vectorZooms {
            let tiles = corridorTiles(
                along: thinned,
                zoom: zoom,
                padding: padding(forZoom: zoom, widened: widened)
            )
            vector.append(contentsOf: tiles)
        }

        var terrain: [TopoTileKey] = []
        for zoom in terrainZooms {
            let tiles = corridorTiles(
                along: thinned,
                zoom: zoom,
                padding: padding(forZoom: zoom, widened: widened)
            )
            terrain.append(contentsOf: tiles)
        }

        return clamped(Plan(vector: vector, terrain: terrain))
    }

    /// The plan for a home area.
    static func plan(around centre: CLLocationCoordinate2D, radiusMetres: Double) -> Plan {
        var vector: [TopoTileKey] = []
        for zoom in vectorZooms {
            vector.append(contentsOf: areaTiles(around: centre, radiusMetres: radiusMetres, zoom: zoom))
        }

        var terrain: [TopoTileKey] = []
        for zoom in terrainZooms {
            terrain.append(contentsOf: areaTiles(around: centre, radiusMetres: radiusMetres, zoom: zoom))
        }

        return clamped(Plan(vector: vector, terrain: terrain))
    }

    /// Drops the finest zoom levels until the plan fits the ceiling.
    ///
    /// Losing close-in detail on a very long route is a far better failure than
    /// a download that never finishes, and the coarser levels still show the
    /// shape of the ground.
    private static func clamped(_ plan: Plan) -> Plan {
        var vector = plan.vector
        var terrain = plan.terrain

        while vector.count + terrain.count > tileCeiling {
            let deepestVector = vector.map(\.z).max() ?? 0
            let deepestTerrain = terrain.map(\.z).max() ?? 0

            if deepestVector >= deepestTerrain, deepestVector > vectorZooms.first ?? 11 {
                vector.removeAll { $0.z == deepestVector }
            } else if deepestTerrain > terrainZooms.first ?? 11 {
                terrain.removeAll { $0.z == deepestTerrain }
            } else {
                break
            }
        }

        return Plan(vector: vector, terrain: terrain)
    }

    // MARK: - Helpers

    /// Walks the tile grid between two tiles.
    ///
    /// Bresenham's line algorithm: integer arithmetic only, and it visits every
    /// tile the leg passes through without gaps.
    private static func line(
        from: (x: Int, y: Int),
        to: (x: Int, y: Int)
    ) -> [(x: Int, y: Int)] {
        var points: [(x: Int, y: Int)] = []
        var x = from.x
        var y = from.y
        let dx = abs(to.x - from.x)
        let dy = abs(to.y - from.y)
        let stepX = from.x < to.x ? 1 : -1
        let stepY = from.y < to.y ? 1 : -1
        var error = dx - dy

        // A guard against a pathological pair of coordinates.
        let ceiling = dx + dy + 2
        var visited = 0

        while visited < ceiling {
            points.append((x, y))
            visited += 1
            if x == to.x, y == to.y { break }
            let doubled = error * 2
            if doubled > -dy {
                error -= dy
                x += stepX
            }
            if doubled < dx {
                error += dx
                y += stepY
            }
        }
        return points
    }

    /// Thins a track before planning.
    ///
    /// A recorded route can carry a point every second; consecutive points a few
    /// metres apart land in the same tile, so walking all of them is wasted work
    /// for an identical answer.
    private static func thin(_ coordinates: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        guard coordinates.count > 2 else { return coordinates }
        var result: [CLLocationCoordinate2D] = []
        result.reserveCapacity(coordinates.count / 2)

        guard let first = coordinates.first, let last = coordinates.last else { return coordinates }
        result.append(first)
        var previous = CLLocation(latitude: first.latitude, longitude: first.longitude)

        for coordinate in coordinates.dropFirst().dropLast() {
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            // A z14 tile is on the order of a kilometre; 60 m keeps every tile
            // crossing while discarding the rest.
            if location.distance(from: previous) >= 60 {
                result.append(coordinate)
                previous = location
            }
        }

        result.append(last)
        return result
    }
}
