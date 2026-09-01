import Foundation
import CoreLocation

/// Samples measured ground elevation for planned routes.
///
/// Every value comes from a terrain tile that was actually downloaded from the
/// AWS Terrain Tiles open dataset. Where a tile is missing — no signal, or a
/// gap in the survey — this returns `nil` rather than a plausible-looking
/// number, so the planner can show `--` instead of a guess.
actor RouteElevationService {
    static let shared = RouteElevationService()

    /// Zoom 13 is roughly 20 m per pixel at mid latitudes: enough to resolve the
    /// shape of a climb without pulling a tile per switchback.
    private let zoom = 13
    private let tileBudget = 220

    private var tiles: [ElevationTileService.TileKey: ElevationTileService.Tile] = [:]
    /// Tiles that came back empty or failed, so one bad area is not retried on
    /// every keystroke of a redraw.
    private var unavailable: Set<ElevationTileService.TileKey> = []

    private init() {}

    /// Elevations in metres for each coordinate, `nil` where no tile could be read.
    func elevations(at coordinates: [CLLocationCoordinate2D]) async -> [Double?] {
        guard !coordinates.isEmpty else { return [] }

        let keys = Set(coordinates.map(key(for:)))
        let missing = keys.subtracting(tiles.keys).subtracting(unavailable)
        if !missing.isEmpty {
            await download(missing)
        }

        return coordinates.map { coordinate in
            guard let tile = tiles[key(for: coordinate)] else { return nil }
            return sample(tile, at: coordinate)
        }
    }

    /// Elevation for a single coordinate, `nil` when unmeasured.
    func elevation(at coordinate: CLLocationCoordinate2D) async -> Double? {
        await elevations(at: [coordinate]).first ?? nil
    }

    // MARK: - Tiles

    private func key(for coordinate: CLLocationCoordinate2D) -> ElevationTileService.TileKey {
        let point = ElevationTileService.tilePoint(for: coordinate, zoom: zoom)
        return ElevationTileService.TileKey(
            z: zoom,
            x: Int(point.x.rounded(.down)),
            y: Int(point.y.rounded(.down))
        )
    }

    private func download(_ keys: Set<ElevationTileService.TileKey>) async {
        // Keep the working set bounded; planning a route across a state should
        // not grow into a cache the size of the pack downloader's.
        if tiles.count > tileBudget {
            tiles.removeAll(keepingCapacity: true)
        }

        await withTaskGroup(of: (ElevationTileService.TileKey, ElevationTileService.Tile?).self) { group in
            for key in keys {
                group.addTask {
                    do {
                        return (key, try await ElevationTileService.tile(key))
                    } catch {
                        return (key, nil)
                    }
                }
            }
            for await (key, tile) in group {
                if let tile {
                    tiles[key] = tile
                } else {
                    unavailable.insert(key)
                }
            }
        }
    }

    /// Bilinear read from the tile's 256×256 metre grid.
    private func sample(_ tile: ElevationTileService.Tile, at coordinate: CLLocationCoordinate2D) -> Double? {
        let side = 256
        guard tile.samples.count == side * side else { return nil }

        let point = ElevationTileService.tilePoint(for: coordinate, zoom: zoom)
        let fx = (point.x - point.x.rounded(.down)) * Double(side - 1)
        let fy = (point.y - point.y.rounded(.down)) * Double(side - 1)

        let x0 = min(side - 1, max(0, Int(fx.rounded(.down))))
        let y0 = min(side - 1, max(0, Int(fy.rounded(.down))))
        let x1 = min(side - 1, x0 + 1)
        let y1 = min(side - 1, y0 + 1)
        let tx = fx - Double(x0)
        let ty = fy - Double(y0)

        let topLeft = Double(tile.samples[y0 * side + x0])
        let topRight = Double(tile.samples[y0 * side + x1])
        let bottomLeft = Double(tile.samples[y1 * side + x0])
        let bottomRight = Double(tile.samples[y1 * side + x1])

        let top = topLeft + (topRight - topLeft) * tx
        let bottom = bottomLeft + (bottomRight - bottomLeft) * tx
        let value = top + (bottom - top) * ty

        // The dataset writes ocean and voids as a sentinel far below sea level.
        guard value > -400, value < 9_000 else { return nil }
        return value
    }
}
