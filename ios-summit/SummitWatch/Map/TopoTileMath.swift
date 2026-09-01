import Foundation
import CoreGraphics
import CoreLocation

/// Web Mercator maths for Trekka's own map.
///
/// Everything here works in one of three spaces:
///
/// - **world**: normalised 0...1 across the whole planet, y running south.
/// - **world pixels**: world scaled by `worldSize(zoom:)`, the space tiles and
///   overlays are laid out in.
/// - **tile-local**: normalised 0...1 inside a single tile, which is how decoded
///   geometry is stored so a tile can be drawn at any zoom without re-decoding.
nonisolated enum TopoTileMath {
    /// Slippy-map tiles are 256 pt square by convention.
    static let tileSide: Double = 256

    /// Web Mercator cannot represent the poles, so latitude is clamped to the
    /// standard limit rather than producing an infinity.
    static let latitudeLimit: Double = 85.05112878

    static func world(_ coordinate: CLLocationCoordinate2D) -> CGPoint {
        let longitude = min(max(coordinate.longitude, -179.9999), 179.9999)
        let latitude = min(max(coordinate.latitude, -latitudeLimit), latitudeLimit)
        let latitudeRadians: Double = latitude * .pi / 180
        let sinLatitude: Double = sin(latitudeRadians)
        let x: Double = (longitude + 180) / 360
        let y: Double = 0.5 - log((1 + sinLatitude) / (1 - sinLatitude)) / (4 * .pi)
        return CGPoint(x: x, y: y)
    }

    static func coordinate(world point: CGPoint) -> CLLocationCoordinate2D {
        let longitude: Double = Double(point.x) * 360 - 180
        let n: Double = .pi - 2 * .pi * Double(point.y)
        let latitude: Double = 180 / .pi * atan(0.5 * (exp(n) - exp(-n)))
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Width of the whole planet in pixels at a zoom level.
    static func worldSize(zoom: Double) -> Double {
        tileSide * pow(2, zoom)
    }

    /// Ground metres covered by one screen pixel.
    static func metresPerPixel(latitude: Double, zoom: Double) -> Double {
        let latitudeRadians: Double = latitude * .pi / 180
        return 156_543.03392 * cos(latitudeRadians) / pow(2, zoom)
    }

    /// The zoom at which `metres` of ground fills `pixels` of screen.
    static func zoom(forSpanMetres metres: Double, latitude: Double, pixels: Double) -> Double {
        guard metres > 0, pixels > 0 else { return 14 }
        let latitudeRadians: Double = latitude * .pi / 180
        let ratio: Double = 156_543.03392 * cos(latitudeRadians) * pixels / metres
        return log2(max(ratio, 1))
    }

    /// How many metres of ground the taller screen edge spans at a zoom.
    static func spanMetres(zoom: Double, latitude: Double, pixels: Double) -> Double {
        metresPerPixel(latitude: latitude, zoom: zoom) * pixels
    }
}

/// A slippy-map tile address.
nonisolated struct TopoTileKey: Hashable, Sendable {
    let z: Int
    let x: Int
    let y: Int

    /// The tile at a coarser zoom that contains this one.
    func parent(atZoom zoom: Int) -> TopoTileKey {
        guard zoom < z else { return self }
        let shift: Int = z - zoom
        return TopoTileKey(z: zoom, x: x >> shift, y: y >> shift)
    }

    /// Ground box covered by the tile, needed to sample terrain for contours.
    var bounds: (minLatitude: Double, maxLatitude: Double, minLongitude: Double, maxLongitude: Double) {
        let side: Double = pow(2, Double(z))
        let northWest = TopoTileMath.coordinate(world: CGPoint(x: Double(x) / side, y: Double(y) / side))
        let southEast = TopoTileMath.coordinate(world: CGPoint(x: Double(x + 1) / side, y: Double(y + 1) / side))
        return (southEast.latitude, northWest.latitude, northWest.longitude, southEast.longitude)
    }
}

/// Where the map is looking.
nonisolated struct TopoCamera: Equatable, Sendable {
    var centre: CLLocationCoordinate2D
    /// Fractional slippy zoom, so pinching and the Crown stay smooth.
    var zoom: Double
    /// Degrees clockwise from north. 0 keeps north at the top.
    var heading: Double = 0

    static func == (lhs: TopoCamera, rhs: TopoCamera) -> Bool {
        lhs.centre.latitude == rhs.centre.latitude
            && lhs.centre.longitude == rhs.centre.longitude
            && lhs.zoom == rhs.zoom
            && lhs.heading == rhs.heading
    }

    /// Camera centre in world pixels at the current zoom.
    var centreWorldPixels: CGPoint {
        let size: Double = TopoTileMath.worldSize(zoom: zoom)
        let world = TopoTileMath.world(centre)
        return CGPoint(x: Double(world.x) * size, y: Double(world.y) * size)
    }

    /// Integer zoom to request tiles at. Vector tiles are cut to zoom 14 on the
    /// source, so beyond that the z14 tile is simply drawn larger.
    func tileZoom(maximum: Int) -> Int {
        let rounded: Int = Int(zoom.rounded(.down))
        return min(max(rounded, 0), maximum)
    }
}
