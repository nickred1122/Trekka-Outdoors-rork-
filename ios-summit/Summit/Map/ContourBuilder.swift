import Foundation
import CoreGraphics
import ImageIO

/// One height line on the map.
nonisolated struct ContourLevel: Sendable {
    let elevation: Double
    /// Index contours are the heavier, labelled lines every fifth interval.
    let isIndex: Bool
    /// Segments in tile-local space, normalised 0...1.
    let segments: [[CGPoint]]
}

nonisolated struct ContourTile: Sendable {
    let key: TopoTileKey
    let levels: [ContourLevel]
    let interval: Double

    var isEmpty: Bool { levels.isEmpty }
}

/// Turns terrain height tiles into contour lines.
///
/// Vector basemaps carry no contours, so rather than pay a provider for a
/// topographic raster we derive the lines ourselves from open elevation data.
/// The upside is that the cartography stays ours, the contour interval can
/// follow the zoom, and the same height tiles that draw a route's climb profile
/// draw the ground it crosses.
///
/// Heights come from the AWS Terrain Tiles open dataset as "terrarium" PNGs,
/// which pack metres into the red, green and blue channels. The data is derived
/// from SRTM, USGS 3DEP and other national surveys, so the lines are measured
/// ground rather than an approximation.
nonisolated enum ContourBuilder {
    static let attribution = "Terrain: AWS Terrain Tiles — SRTM, USGS 3DEP and other public surveys"

    /// Terrarium tiles are 256 px square.
    private static let demSide = 256

    /// Heights are averaged down to this grid before tracing. Full resolution
    /// traces every bump in the source data, which reads as noise at watch
    /// size; halving it costs no visible detail and smooths the line.
    private static let gridSide = 128

    /// Terrarium coverage stops at zoom 15, and past zoom 13 the lines get so
    /// dense they stop being readable, so tiles are requested no finer.
    static let maximumZoom = 13

    /// Contour spacing in metres for a zoom level.
    ///
    /// Close in, fine intervals describe the ground; far out they would collapse
    /// into a solid brown mass, so the interval opens up.
    static func interval(forZoom zoom: Int) -> Double {
        switch zoom {
        case 13...: 10
        case 12: 25
        case 11: 50
        case 10: 100
        default: 200
        }
    }

    // MARK: - Decoding

    /// Unpacks a terrarium PNG into metres: `(red * 256 + green + blue / 256) - 32768`.
    static func decodeTerrarium(_ data: Data) -> [Float]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width == demSide, image.height == demSide else { return nil }

        let bytesPerRow = demSide * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * demSide)
        guard let colourSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let context = CGContext(
                      data: base,
                      width: demSide,
                      height: demSide,
                      bitsPerComponent: 8,
                      bytesPerRow: bytesPerRow,
                      space: colourSpace,
                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                  ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: demSide, height: demSide))
            return true
        }
        guard drawn else { return nil }

        var samples = [Float](repeating: 0, count: demSide * demSide)
        for index in 0..<(demSide * demSide) {
            let offset = index * 4
            let red = Float(pixels[offset])
            let green = Float(pixels[offset + 1])
            let blue = Float(pixels[offset + 2])
            samples[index] = (red * 256 + green + blue / 256) - 32768
        }
        return samples
    }

    // MARK: - Tracing

    /// Traces contour lines across one terrain tile.
    static func build(samples: [Float], key: TopoTileKey) -> ContourTile {
        guard samples.count == demSide * demSide else {
            return ContourTile(key: key, levels: [], interval: interval(forZoom: key.z))
        }

        let grid = smoothed(downsample(samples))
        let side = gridSide
        let spacing = interval(forZoom: key.z)

        var lowest = Float.greatestFiniteMagnitude
        var highest = -Float.greatestFiniteMagnitude
        for value in grid {
            if value < lowest { lowest = value }
            if value > highest { highest = value }
        }
        // Flat ground, or sea, has nothing to draw.
        guard highest > lowest, highest > -400 else {
            return ContourTile(key: key, levels: [], interval: spacing)
        }

        let firstStep = Int((Double(lowest) / spacing).rounded(.up))
        let lastStep = Int((Double(highest) / spacing).rounded(.down))
        guard lastStep >= firstStep else {
            return ContourTile(key: key, levels: [], interval: spacing)
        }
        // A hard ceiling keeps a mountainside from generating hundreds of lines.
        let stepLimit = min(lastStep, firstStep + 60)

        var levels: [ContourLevel] = []
        let divisor = Double(side - 1)

        for step in firstStep...stepLimit {
            let elevation = Double(step) * spacing
            let target = Float(elevation)
            var segments: [[CGPoint]] = []

            for row in 0..<(side - 1) {
                let rowOffset = row * side
                let nextRowOffset = rowOffset + side
                for column in 0..<(side - 1) {
                    let topLeft = grid[rowOffset + column]
                    let topRight = grid[rowOffset + column + 1]
                    let bottomLeft = grid[nextRowOffset + column]
                    let bottomRight = grid[nextRowOffset + column + 1]

                    // Cheap reject: a cell entirely above or below the level
                    // cannot contain the line.
                    let lowestCorner = min(min(topLeft, topRight), min(bottomLeft, bottomRight))
                    let highestCorner = max(max(topLeft, topRight), max(bottomLeft, bottomRight))
                    if target < lowestCorner || target > highestCorner { continue }

                    var crossings: [CGPoint] = []
                    let columnBase = Double(column)
                    let rowBase = Double(row)

                    if let t = crossing(topLeft, topRight, target) {
                        crossings.append(CGPoint(x: (columnBase + t) / divisor, y: rowBase / divisor))
                    }
                    if let t = crossing(topRight, bottomRight, target) {
                        crossings.append(CGPoint(x: (columnBase + 1) / divisor, y: (rowBase + t) / divisor))
                    }
                    if let t = crossing(bottomLeft, bottomRight, target) {
                        crossings.append(CGPoint(x: (columnBase + t) / divisor, y: (rowBase + 1) / divisor))
                    }
                    if let t = crossing(topLeft, bottomLeft, target) {
                        crossings.append(CGPoint(x: columnBase / divisor, y: (rowBase + t) / divisor))
                    }

                    // Two crossings is one line through the cell. Four is a
                    // saddle: pairing them adjacently keeps the lines apart,
                    // which is the visually safer of the two readings.
                    if crossings.count == 2 {
                        segments.append([crossings[0], crossings[1]])
                    } else if crossings.count == 4 {
                        segments.append([crossings[0], crossings[1]])
                        segments.append([crossings[2], crossings[3]])
                    }
                }
            }

            guard !segments.isEmpty else { continue }
            let isIndex = step % 5 == 0
            levels.append(ContourLevel(elevation: elevation, isIndex: isIndex, segments: segments))
        }

        return ContourTile(key: key, levels: levels, interval: spacing)
    }

    /// Where along an edge the contour crosses, or nil if it does not.
    private static func crossing(_ a: Float, _ b: Float, _ target: Float) -> Double? {
        let above = a >= target
        let bAbove = b >= target
        guard above != bAbove else { return nil }
        let span = Double(b - a)
        guard abs(span) > 0.0001 else { return nil }
        let t = Double(target - a) / span
        return min(max(t, 0), 1)
    }

    /// Averages the 256-wide height grid down to `gridSide`.
    private static func downsample(_ samples: [Float]) -> [Float] {
        let factor = demSide / gridSide
        guard factor > 1 else { return samples }

        var result = [Float](repeating: 0, count: gridSide * gridSide)
        let divisor = Float(factor * factor)

        for row in 0..<gridSide {
            for column in 0..<gridSide {
                var total: Float = 0
                for subRow in 0..<factor {
                    let sourceRow = row * factor + subRow
                    let sourceOffset = sourceRow * demSide + column * factor
                    for subColumn in 0..<factor {
                        total += samples[sourceOffset + subColumn]
                    }
                }
                result[row * gridSide + column] = total / divisor
            }
        }
        return result
    }

    /// A light box blur. Elevation data carries step artefacts from its source
    /// surveys, and without this they show up as small rectangular kinks along
    /// every line.
    private static func smoothed(_ grid: [Float]) -> [Float] {
        let side = gridSide
        guard grid.count == side * side else { return grid }
        var result = grid

        for row in 1..<(side - 1) {
            let rowOffset = row * side
            for column in 1..<(side - 1) {
                let index = rowOffset + column
                var total: Float = 0
                total += grid[index - side - 1] + grid[index - side] + grid[index - side + 1]
                total += grid[index - 1] + grid[index] + grid[index + 1]
                total += grid[index + side - 1] + grid[index + side] + grid[index + side + 1]
                result[index] = total / 9
            }
        }
        return result
    }
}
