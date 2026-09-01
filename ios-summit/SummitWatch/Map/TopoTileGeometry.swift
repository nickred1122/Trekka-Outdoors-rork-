import Foundation
import CoreGraphics

/// The subpaths of one bucket inside one tile, in tile-local 0...1 space.
nonisolated struct TopoBucketGeometry: Sendable {
    let bucket: TopoBucket
    let subpaths: [[CGPoint]]
}

/// A settlement or summit name worth putting on the map.
nonisolated struct TopoPlaceLabel: Sendable {
    let name: String
    let className: String
    /// Tile-local anchor, 0...1.
    let point: CGPoint
}

/// Everything drawable from one basemap tile, ready to hand to the renderer.
nonisolated struct TopoTileGeometry: Sendable {
    let key: TopoTileKey
    /// Ordered by bucket, so the renderer can walk it without sorting.
    let buckets: [TopoBucketGeometry]
    let labels: [TopoPlaceLabel]
}

/// Contours live on their own tile grid because terrain is served at a coarser
/// maximum zoom than the basemap, so they cannot share a tile geometry.
nonisolated struct TopoContourGeometry: Sendable {
    let key: TopoTileKey
    let ordinary: [[CGPoint]]
    let index: [[CGPoint]]
}

/// Turns decoded tiles into drawing geometry.
///
/// This is where the map is thinned. Vector tiles describe ground at far more
/// precision than a watch screen can show, and moving every one of those points
/// through a transform each frame is what makes a hand-rolled map feel sluggish.
/// Points closer together than the eye can resolve are dropped once, here,
/// rather than being paid for on every redraw.
nonisolated enum TopoGeometryBuilder {
    static func build(vector: VectorTile, key: TopoTileKey) -> TopoTileGeometry {
        var collected: [TopoBucket: [[CGPoint]]] = [:]
        var labels: [TopoPlaceLabel] = []
        let tolerance = simplificationTolerance(forZoom: key.z)

        for (layerName, features) in vector.layers {
            if TopoStyle.labelLayers.contains(layerName) {
                labels.append(contentsOf: placeLabels(from: features))
                continue
            }

            for feature in features {
                guard let bucket = TopoStyle.bucket(layer: layerName, feature: feature, zoom: key.z) else {
                    continue
                }
                for path in feature.paths {
                    guard path.count >= 2 else { continue }
                    let thinned = simplify(path, tolerance: tolerance)
                    guard thinned.count >= 2 else { continue }
                    if bucket.isArea, !isLargeEnough(thinned, minimumSide: tolerance * 3) { continue }
                    collected[bucket, default: []].append(thinned)
                }
            }
        }

        let buckets: [TopoBucketGeometry] = TopoBucket.allCases.compactMap { bucket in
            guard let subpaths = collected[bucket], !subpaths.isEmpty else { return nil }
            return TopoBucketGeometry(bucket: bucket, subpaths: subpaths)
        }

        return TopoTileGeometry(key: key, buckets: buckets, labels: labels)
    }

    static func build(contour: ContourTile) -> TopoContourGeometry {
        var ordinary: [[CGPoint]] = []
        var index: [[CGPoint]] = []

        for level in contour.levels {
            if level.isIndex {
                index.append(contentsOf: level.segments)
            } else {
                ordinary.append(contentsOf: level.segments)
            }
        }

        return TopoContourGeometry(key: contour.key, ordinary: ordinary, index: index)
    }

    // MARK: - Labels

    private static func placeLabels(from features: [VectorFeature]) -> [TopoPlaceLabel] {
        var labels: [TopoPlaceLabel] = []
        for feature in features {
            guard feature.kind == .point,
                  !feature.name.isEmpty,
                  let point = feature.paths.first?.first else { continue }
            labels.append(
                TopoPlaceLabel(name: feature.name, className: feature.className, point: point)
            )
        }
        return labels
    }

    // MARK: - Thinning

    /// How close two points must be, in tile-local units, before one is dropped.
    ///
    /// A tile is drawn a few hundred points across, so a thousandth of a tile is
    /// comfortably below a pixel at any zoom the tile is used at.
    private static func simplificationTolerance(forZoom zoom: Int) -> Double {
        zoom >= 13 ? 0.0012 : 0.0022
    }

    /// Drops points that sit within `tolerance` of the one before, always
    /// keeping the first and last so lines still meet their neighbours.
    private static func simplify(_ points: [CGPoint], tolerance: Double) -> [CGPoint] {
        guard points.count > 2 else { return points }
        let squaredTolerance = tolerance * tolerance

        var result: [CGPoint] = []
        result.reserveCapacity(points.count)
        guard let first = points.first, let last = points.last else { return points }
        result.append(first)

        var previous = first
        for point in points.dropFirst().dropLast() {
            let dx: Double = Double(point.x - previous.x)
            let dy: Double = Double(point.y - previous.y)
            let distance: Double = dx * dx + dy * dy
            if distance >= squaredTolerance {
                result.append(point)
                previous = point
            }
        }

        result.append(last)
        return result
    }

    /// Whether a filled shape is big enough to be worth drawing.
    private static func isLargeEnough(_ points: [CGPoint], minimumSide: Double) -> Bool {
        var minX = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude

        for point in points {
            let x = Double(point.x)
            let y = Double(point.y)
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
        }

        return (maxX - minX) >= minimumSide || (maxY - minY) >= minimumSide
    }
}
