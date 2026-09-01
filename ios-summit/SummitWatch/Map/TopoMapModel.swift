import SwiftUI
import CoreLocation

/// One tile's geometry converted to drawable paths.
///
/// Paths are built once, on arrival, and kept in tile-local space so panning and
/// zooming only cost a transform rather than a rebuild.
struct TopoDrawTile {
    let key: TopoTileKey
    let paths: [TopoBucket: Path]
    let labels: [TopoPlaceLabel]
}

struct TopoContourDrawTile {
    let key: TopoTileKey
    let ordinary: Path
    let index: Path
}

/// Holds the camera and the tiles currently worth drawing.
@Observable
@MainActor
final class TopoMapModel {
    var camera = TopoCamera(
        centre: CLLocationCoordinate2D(latitude: 51.5, longitude: -0.12),
        zoom: 13
    )
    var showsContours = true

    private(set) var drawTiles: [TopoTileKey: TopoDrawTile] = [:]
    private(set) var contourDrawTiles: [TopoTileKey: TopoContourDrawTile] = [:]
    /// True once a fetch has been attempted, so the view can tell "still
    /// loading" apart from "nothing here".
    private(set) var didAttemptLoad = false

    private var tileOrder: [TopoTileKey] = []
    private var contourOrder: [TopoTileKey] = []
    private var inflight: Set<TopoTileKey> = []
    private var contourInflight: Set<TopoTileKey> = []

    /// Room for a screen of tiles several times over, so a short pan back does
    /// not have to re-fetch.
    private let tileLimit = 64
    private let contourLimit = 40

    var isLoading: Bool { !inflight.isEmpty || !contourInflight.isEmpty }
    var hasContent: Bool { !drawTiles.isEmpty }

    // MARK: - Framing

    /// Points the camera at a coordinate with a given screen-edge span.
    func frame(centre: CLLocationCoordinate2D, spanMetres: Double, size: CGSize) {
        camera.centre = centre
        zoom(toSpanMetres: spanMetres, size: size)
    }

    /// Changes only the zoom, leaving the centre where it is.
    ///
    /// This is what the Crown drives while the athlete is panning: the ground
    /// under their finger must not jump back to their position just because they
    /// asked for a wider view.
    func zoom(toSpanMetres metres: Double, size: CGSize) {
        let pixels: Double = max(Double(size.height), 1)
        let value = TopoTileMath.zoom(
            forSpanMetres: metres,
            latitude: camera.centre.latitude,
            pixels: pixels
        )
        camera.zoom = min(max(value, 3), 18)
    }

    /// Frames a set of coordinates with a margin, for previews.
    func frame(fitting coordinates: [CLLocationCoordinate2D], size: CGSize) {
        guard !coordinates.isEmpty else { return }
        var minLatitude = Double.greatestFiniteMagnitude
        var maxLatitude = -Double.greatestFiniteMagnitude
        var minLongitude = Double.greatestFiniteMagnitude
        var maxLongitude = -Double.greatestFiniteMagnitude

        for coordinate in coordinates {
            minLatitude = min(minLatitude, coordinate.latitude)
            maxLatitude = max(maxLatitude, coordinate.latitude)
            minLongitude = min(minLongitude, coordinate.longitude)
            maxLongitude = max(maxLongitude, coordinate.longitude)
        }

        let centre = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
        // A fifth of margin keeps the line off the bezel, and a floor stops a
        // single-point track zooming to rooftop level.
        let latitudeSpan: Double = max(maxLatitude - minLatitude, 0.0015) * 1.25
        let metres: Double = latitudeSpan * 111_000
        frame(centre: centre, spanMetres: metres, size: size)
    }

    // MARK: - Tile loading

    /// Works out which tiles the current camera needs and fetches the missing
    /// ones. Safe to call every time the camera or the view size changes.
    func refresh(size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        didAttemptLoad = true

        let vectorZoom = camera.tileZoom(maximum: TopoTileSource.maximumVectorZoom)
        let vectorKeys = visibleKeys(size: size, zoom: vectorZoom)
        for key in vectorKeys where drawTiles[key] == nil {
            load(key)
        }

        if showsContours {
            let contourZoom = min(vectorZoom, ContourBuilder.maximumZoom)
            let contourKeys = visibleKeys(size: size, zoom: contourZoom)
            for key in contourKeys where contourDrawTiles[key] == nil {
                loadContour(key)
            }
        }
    }

    /// Tiles covering the view.
    ///
    /// The bounding circle is used rather than the exact rectangle so the answer
    /// stays right when the map is rotated to a heading — it fetches a little
    /// extra at the corners in exchange for not recomputing on every degree.
    private func visibleKeys(size: CGSize, zoom: Int) -> [TopoTileKey] {
        let worldSize: Double = TopoTileMath.worldSize(zoom: camera.zoom)
        let centreWorld = camera.centreWorldPixels
        let radius: Double = hypot(Double(size.width), Double(size.height)) / 2

        let minX: Double = (Double(centreWorld.x) - radius) / worldSize
        let maxX: Double = (Double(centreWorld.x) + radius) / worldSize
        let minY: Double = (Double(centreWorld.y) - radius) / worldSize
        let maxY: Double = (Double(centreWorld.y) + radius) / worldSize

        let tilesPerSide: Int = Int(pow(2, Double(zoom)))
        let limit: Int = tilesPerSide - 1

        let fromX: Int = min(max(Int((minX * Double(tilesPerSide)).rounded(.down)), 0), limit)
        let toX: Int = min(max(Int((maxX * Double(tilesPerSide)).rounded(.down)), 0), limit)
        let fromY: Int = min(max(Int((minY * Double(tilesPerSide)).rounded(.down)), 0), limit)
        let toY: Int = min(max(Int((maxY * Double(tilesPerSide)).rounded(.down)), 0), limit)

        var keys: [TopoTileKey] = []
        for x in fromX...toX {
            for y in fromY...toY {
                keys.append(TopoTileKey(z: zoom, x: x, y: y))
                // A hard ceiling: a camera in a strange state must never queue
                // hundreds of requests.
                if keys.count >= 36 { return keys }
            }
        }
        return keys
    }

    private func load(_ key: TopoTileKey) {
        guard !inflight.contains(key) else { return }
        inflight.insert(key)

        Task { [weak self] in
            let tile = await TopoTileSource.shared.vectorTile(key)
            guard let self else { return }

            if let tile, !tile.isEmpty {
                let geometry = await Task.detached(priority: .userInitiated) {
                    TopoGeometryBuilder.build(vector: tile, key: key)
                }.value
                self.store(geometry)
            }
            self.inflight.remove(key)
        }
    }

    private func loadContour(_ key: TopoTileKey) {
        guard !contourInflight.contains(key) else { return }
        contourInflight.insert(key)

        Task { [weak self] in
            let tile = await TopoTileSource.shared.contourTile(key)
            guard let self else { return }

            if let tile, !tile.isEmpty {
                let geometry = await Task.detached(priority: .utility) {
                    TopoGeometryBuilder.build(contour: tile)
                }.value
                self.store(geometry)
            }
            self.contourInflight.remove(key)
        }
    }

    // MARK: - Path building

    private func store(_ geometry: TopoTileGeometry) {
        var paths: [TopoBucket: Path] = [:]
        for bucket in geometry.buckets {
            paths[bucket.bucket] = Self.path(from: bucket.subpaths, closed: bucket.bucket.isArea)
        }

        let tile = TopoDrawTile(key: geometry.key, paths: paths, labels: geometry.labels)
        if drawTiles[geometry.key] == nil {
            tileOrder.append(geometry.key)
        }
        drawTiles[geometry.key] = tile

        while tileOrder.count > tileLimit {
            let oldest = tileOrder.removeFirst()
            drawTiles[oldest] = nil
        }
    }

    private func store(_ geometry: TopoContourGeometry) {
        let tile = TopoContourDrawTile(
            key: geometry.key,
            ordinary: Self.path(from: geometry.ordinary, closed: false),
            index: Self.path(from: geometry.index, closed: false)
        )
        if contourDrawTiles[geometry.key] == nil {
            contourOrder.append(geometry.key)
        }
        contourDrawTiles[geometry.key] = tile

        while contourOrder.count > contourLimit {
            let oldest = contourOrder.removeFirst()
            contourDrawTiles[oldest] = nil
        }
    }

    private static func path(from subpaths: [[CGPoint]], closed: Bool) -> Path {
        var path = Path()
        for subpath in subpaths {
            guard let first = subpath.first else { continue }
            path.move(to: first)
            for point in subpath.dropFirst() {
                path.addLine(to: point)
            }
            if closed {
                path.closeSubpath()
            }
        }
        return path
    }
}
