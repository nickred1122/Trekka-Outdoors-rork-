import Foundation
import CoreGraphics
import CoreLocation
import ImageIO

/// Real terrain elevation, downloaded from the AWS Terrain Tiles open dataset.
///
/// Tiles are "terrarium" encoded PNGs: each pixel packs a height in metres into
/// its red, green and blue channels. The dataset is public and needs no key, and
/// is derived from SRTM, USGS 3DEP and other national surveys — so what a pack
/// contains is measured ground, not a guess.
nonisolated enum ElevationTileService {
    /// Shown wherever downloaded terrain is presented, as the licence expects.
    static let attribution = "Terrain: AWS Terrain Tiles — SRTM, USGS 3DEP and other public surveys"

    private static let host = "https://s3.amazonaws.com/elevation-tiles-prod/terrarium"
    private static let tileSide = 256
    private static let maxConcurrentDownloads = 5

    // MARK: - Errors

    enum Failure: LocalizedError {
        case offline
        case server(Int)
        case undecodable
        case areaTooLarge

        var errorDescription: String? {
            switch self {
            case .offline:
                "No connection. Offline maps have to be downloaded while you have signal."
            case .server(let code):
                "The terrain service refused the request (\(code)). Try again in a moment."
            case .undecodable:
                "A terrain tile arrived damaged. Try the download again."
            case .areaTooLarge:
                "That area is too large to download in one pack."
            }
        }
    }

    // MARK: - Tiles

    struct TileKey: Hashable, Sendable {
        let z: Int
        let x: Int
        let y: Int
    }

    struct Tile: Sendable {
        let key: TileKey
        /// Row-major metres, north row first, `tileSide` square.
        let samples: [Float]
    }

    /// A downloaded set of tiles that can answer elevation for any coordinate
    /// inside the area it covers.
    struct Coverage: Sendable {
        let zoom: Int
        let tiles: [TileKey: Tile]
        /// Total bytes actually pulled over the network.
        let downloadedBytes: Int

        /// Ground elevation in metres, or `nil` where no tile was downloaded.
        func elevation(at coordinate: CLLocationCoordinate2D) -> Double? {
            let point = ElevationTileService.tilePoint(for: coordinate, zoom: zoom)
            let key = TileKey(z: zoom, x: Int(point.x.rounded(.down)), y: Int(point.y.rounded(.down)))
            guard let tile = tiles[key] else { return nil }

            let side = ElevationTileService.tileSide
            let px = min(side - 1, max(0, Int((point.x - point.x.rounded(.down)) * Double(side))))
            let py = min(side - 1, max(0, Int((point.y - point.y.rounded(.down)) * Double(side))))
            return Double(tile.samples[py * side + px])
        }
    }

    // MARK: - Slippy map maths

    /// Fractional tile coordinates for a location at a zoom level.
    static func tilePoint(for coordinate: CLLocationCoordinate2D, zoom: Int) -> (x: Double, y: Double) {
        let n = pow(2.0, Double(zoom))
        let longitude = min(max(coordinate.longitude, -179.9999), 179.9999)
        let latitude = min(max(coordinate.latitude, -85.05), 85.05)
        let latRad = latitude * .pi / 180

        let x = (longitude + 180) / 360 * n
        let y = (1 - log(tan(latRad) + 1 / cos(latRad)) / .pi) / 2 * n
        return (x, y)
    }

    /// The inclusive tile range covering a box at a zoom level.
    static func tileRange(for bounds: RegionBounds, zoom: Int) -> (x: ClosedRange<Int>, y: ClosedRange<Int>) {
        let limit = Int(pow(2.0, Double(zoom))) - 1
        let topLeft = tilePoint(
            for: CLLocationCoordinate2D(latitude: bounds.maxLatitude, longitude: bounds.minLongitude),
            zoom: zoom
        )
        let bottomRight = tilePoint(
            for: CLLocationCoordinate2D(latitude: bounds.minLatitude, longitude: bounds.maxLongitude),
            zoom: zoom
        )
        let minX = min(max(Int(topLeft.x.rounded(.down)), 0), limit)
        let maxX = min(max(Int(bottomRight.x.rounded(.down)), 0), limit)
        let minY = min(max(Int(topLeft.y.rounded(.down)), 0), limit)
        let maxY = min(max(Int(bottomRight.y.rounded(.down)), 0), limit)
        return (min(minX, maxX)...max(minX, maxX), min(minY, maxY)...max(minY, maxY))
    }

    /// The finest zoom whose tile grid for `bounds` stays within `maxTiles`.
    ///
    /// Detail is always worth having, but a pack has to stay downloadable over a
    /// phone connection — so resolution is chosen by budget, not by hope.
    static func zoomFitting(bounds: RegionBounds, preferred: Int, maxTiles: Int) -> Int {
        var zoom = preferred
        while zoom > 1 {
            let range = tileRange(for: bounds, zoom: zoom)
            if range.x.count * range.y.count <= maxTiles { return zoom }
            zoom -= 1
        }
        return 1
    }

    /// How many tiles a download at this zoom would need.
    static func tileCount(for bounds: RegionBounds, zoom: Int) -> Int {
        let range = tileRange(for: bounds, zoom: zoom)
        return range.x.count * range.y.count
    }

    // MARK: - Download

    /// Downloads every tile covering `bounds`, reporting completed/total as it goes.
    static func coverage(
        for bounds: RegionBounds,
        zoom: Int,
        session: URLSession = .shared,
        onProgress: @Sendable (Int, Int) -> Void
    ) async throws -> Coverage {
        let range = tileRange(for: bounds, zoom: zoom)
        var keys: [TileKey] = []
        for x in range.x {
            for y in range.y {
                keys.append(TileKey(z: zoom, x: x, y: y))
            }
        }
        guard !keys.isEmpty else { throw Failure.areaTooLarge }

        var tiles: [TileKey: Tile] = [:]
        var bytes = 0
        var completed = 0
        onProgress(0, keys.count)

        try await withThrowingTaskGroup(of: (Tile, Int).self) { group in
            var next = 0

            func addTask() {
                guard next < keys.count else { return }
                let key = keys[next]
                next += 1
                group.addTask { try await fetchTile(key, session: session) }
            }

            for _ in 0..<min(maxConcurrentDownloads, keys.count) { addTask() }

            while let (tile, size) = try await group.next() {
                try Task.checkCancellation()
                tiles[tile.key] = tile
                bytes += size
                completed += 1
                onProgress(completed, keys.count)
                addTask()
            }
        }

        return Coverage(zoom: zoom, tiles: tiles, downloadedBytes: bytes)
    }

    /// Downloads one tile. Used by callers that sample scattered coordinates
    /// rather than a whole region, so only the tiles actually needed are pulled.
    static func tile(_ key: TileKey, session: URLSession = .shared) async throws -> Tile {
        try await fetchTile(key, session: session).0
    }

    private static func fetchTile(_ key: TileKey, session: URLSession) async throws -> (Tile, Int) {
        guard let url = URL(string: "\(host)/\(key.z)/\(key.x)/\(key.y).png") else {
            throw Failure.undecodable
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Failure.offline
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Failure.server(http.statusCode)
        }

        guard let samples = decodeTerrarium(data) else { throw Failure.undecodable }
        return (Tile(key: key, samples: samples), data.count)
    }

    // MARK: - Decoding

    /// Unpacks a terrarium PNG into metres: `(red * 256 + green + blue / 256) - 32768`.
    private static func decodeTerrarium(_ data: Data) -> [Float]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width == tileSide, image.height == tileSide else { return nil }

        let bytesPerRow = tileSide * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * tileSide)
        guard let colourSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let context = CGContext(
                      data: base,
                      width: tileSide,
                      height: tileSide,
                      bitsPerComponent: 8,
                      bytesPerRow: bytesPerRow,
                      space: colourSpace,
                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                  ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: tileSide, height: tileSide))
            return true
        }
        guard drawn else { return nil }

        var samples = [Float](repeating: 0, count: tileSide * tileSide)
        for index in 0..<(tileSide * tileSide) {
            let offset = index * 4
            let red = Float(pixels[offset])
            let green = Float(pixels[offset + 1])
            let blue = Float(pixels[offset + 2])
            samples[index] = (red * 256 + green + blue / 256) - 32768
        }
        return samples
    }
}
