import SwiftUI
import CoreGraphics

/// Drawing order for everything on the basemap.
///
/// The order is the cartography: ground cover first, then contours, then water
/// over the contours because a lake is flat, then the built world, then ways
/// with paths last so a trail is never buried under a road.
nonisolated enum TopoBucket: Int, CaseIterable, Sendable {
    case landcoverWood = 0
    case landcoverGrass
    case landcoverBare
    case landuse
    case park
    case contour
    case contourIndex
    case water
    case waterway
    case building
    case roadCasing
    case road
    case track
    case path
    case rail

    /// Filled areas versus stroked lines.
    var isArea: Bool {
        switch self {
        case .landcoverWood, .landcoverGrass, .landcoverBare, .landuse, .park, .water, .building:
            true
        case .contour, .contourIndex, .waterway, .roadCasing, .road, .track, .path, .rail:
            false
        }
    }
}

/// The colours of one map appearance.
nonisolated struct TopoPalette: Sendable {
    let paper: Color
    let wood: Color
    let grass: Color
    let bare: Color
    let landuse: Color
    let park: Color
    let water: Color
    let waterLine: Color
    let building: Color
    let roadFill: Color
    let roadCasing: Color
    let track: Color
    let path: Color
    let contour: Color
    let contourIndex: Color
    let rail: Color
    let label: Color
    let labelHalo: Color

    /// Classic topographic sheet: cream paper, brown lines, muted vegetation.
    static let paperSheet = TopoPalette(
        paper: Color(red: 0.953, green: 0.918, blue: 0.855),
        wood: Color(red: 0.780, green: 0.839, blue: 0.690),
        grass: Color(red: 0.863, green: 0.906, blue: 0.776),
        bare: Color(red: 0.890, green: 0.851, blue: 0.776),
        landuse: Color(red: 0.929, green: 0.894, blue: 0.831),
        park: Color(red: 0.831, green: 0.890, blue: 0.769),
        water: Color(red: 0.659, green: 0.776, blue: 0.855),
        waterLine: Color(red: 0.498, green: 0.651, blue: 0.753),
        building: Color(red: 0.812, green: 0.753, blue: 0.659),
        roadFill: Color(red: 1.0, green: 0.992, blue: 0.969),
        roadCasing: Color(red: 0.745, green: 0.675, blue: 0.569),
        track: Color(red: 0.604, green: 0.420, blue: 0.235),
        path: Color(red: 0.541, green: 0.353, blue: 0.169),
        contour: Color(red: 0.776, green: 0.635, blue: 0.459),
        contourIndex: Color(red: 0.659, green: 0.486, blue: 0.290),
        rail: Color(red: 0.541, green: 0.522, blue: 0.471),
        label: Color(red: 0.290, green: 0.251, blue: 0.204),
        labelHalo: Color(red: 0.973, green: 0.953, blue: 0.910)
    )

    /// The same cartography after dark, for night navigation and battery.
    static let nightSheet = TopoPalette(
        paper: Color(red: 0.071, green: 0.075, blue: 0.067),
        wood: Color(red: 0.106, green: 0.157, blue: 0.106),
        grass: Color(red: 0.114, green: 0.145, blue: 0.098),
        bare: Color(red: 0.145, green: 0.137, blue: 0.118),
        landuse: Color(red: 0.110, green: 0.110, blue: 0.102),
        park: Color(red: 0.098, green: 0.153, blue: 0.106),
        water: Color(red: 0.086, green: 0.188, blue: 0.247),
        waterLine: Color(red: 0.216, green: 0.373, blue: 0.451),
        building: Color(red: 0.149, green: 0.141, blue: 0.121),
        roadFill: Color(red: 0.239, green: 0.231, blue: 0.212),
        roadCasing: Color(red: 0.137, green: 0.133, blue: 0.125),
        track: Color(red: 0.702, green: 0.522, blue: 0.322),
        path: Color(red: 0.788, green: 0.573, blue: 0.325),
        contour: Color(red: 0.278, green: 0.224, blue: 0.161),
        contourIndex: Color(red: 0.400, green: 0.310, blue: 0.204),
        rail: Color(red: 0.353, green: 0.341, blue: 0.310),
        label: Color(red: 0.831, green: 0.792, blue: 0.729),
        labelHalo: Color(red: 0.071, green: 0.075, blue: 0.067)
    )
}

/// How a bucket is painted at a given zoom.
nonisolated struct TopoPaint: Sendable {
    var colour: Color
    var width: CGFloat = 1
    var dash: [CGFloat] = []
    var opacity: Double = 1
}

/// Trekka's map style.
///
/// The vector tiles carry OpenStreetMap's own categories; this is where they
/// become a map. Two decisions drive everything:
///
/// - **A trail is not a small road.** On foot the difference between a lane and
///   a footpath is the whole plan, so paths and tracks get their own brown,
///   their own dash, and the top of the drawing order.
/// - **Weights are tuned for a watch, not a desk.** Lines that read well on a
///   phone disappear at 45mm in bright sun, so the compact variant thickens
///   every stroke rather than scaling the whole map down.
nonisolated enum TopoStyle {
    /// Only the source layers the style actually draws are decoded.
    ///
    /// Summits arrive in a layer of their own rather than alongside the
    /// settlements, so they have to be asked for separately. On a map for the
    /// outdoors a peak name earns its room more than most place names do.
    static let sourceLayers: Set<String> = [
        "water", "waterway", "landcover", "landuse", "park",
        "transportation", "building", "place", "mountain_peak",
    ]

    /// Layers that contribute names rather than geometry.
    static let labelLayers: Set<String> = ["place", "mountain_peak"]

    /// Which bucket a feature belongs in, or nil to leave it undrawn.
    static func bucket(layer: String, feature: VectorFeature, zoom: Int) -> TopoBucket? {
        switch layer {
        case "water":
            return .water

        case "waterway":
            // Ditches and drains are noise below close zoom.
            if zoom < 13, feature.className == "ditch" || feature.className == "drain" { return nil }
            return .waterway

        case "landcover":
            switch feature.className {
            case "wood", "forest": return .landcoverWood
            case "grass", "wetland", "scrub": return .landcoverGrass
            case "rock", "sand", "ice", "bare_rock", "glacier": return .landcoverBare
            case "farmland": return .landuse
            default: return nil
            }

        case "landuse":
            // Built-up shading only helps once you can see streets.
            guard zoom >= 11 else { return nil }
            return .landuse

        case "park":
            return .park

        case "building":
            guard zoom >= 14 else { return nil }
            return .building

        case "transportation":
            return transportBucket(feature: feature, zoom: zoom)

        default:
            return nil
        }
    }

    private static func transportBucket(feature: VectorFeature, zoom: Int) -> TopoBucket? {
        let className = feature.className
        let subclass = feature.subclass

        if className == "path" || className == "track" {
            // Paths are the reason this map exists, so they show early.
            guard zoom >= 11 else { return nil }
            if className == "track" || subclass == "track" { return .track }
            return .path
        }
        if className == "rail" || className == "transit" {
            guard zoom >= 12 else { return nil }
            return .rail
        }
        if className == "ferry" || className == "aerialway" { return nil }
        if className == "service" || className == "minor" {
            guard zoom >= 13 else { return nil }
            return .road
        }
        return .road
    }

    /// True where a road wants a darker casing drawn beneath it.
    static func hasCasing(bucket: TopoBucket) -> Bool {
        bucket == .road
    }

    // MARK: - Paint

    static func paint(
        _ bucket: TopoBucket,
        zoom: Double,
        palette: TopoPalette,
        compact: Bool
    ) -> TopoPaint {
        let boost: CGFloat = compact ? 1.4 : 1.0

        switch bucket {
        case .landcoverWood:
            return TopoPaint(colour: palette.wood, opacity: 0.9)
        case .landcoverGrass:
            return TopoPaint(colour: palette.grass, opacity: 0.75)
        case .landcoverBare:
            return TopoPaint(colour: palette.bare, opacity: 0.8)
        case .landuse:
            return TopoPaint(colour: palette.landuse, opacity: 0.7)
        case .park:
            return TopoPaint(colour: palette.park, opacity: 0.5)
        case .water:
            return TopoPaint(colour: palette.water, opacity: 1)

        case .contour:
            let width: CGFloat = compact ? 0.7 : 0.6
            return TopoPaint(colour: palette.contour, width: width, opacity: compact ? 0.85 : 0.7)
        case .contourIndex:
            let width: CGFloat = compact ? 1.2 : 1.0
            return TopoPaint(colour: palette.contourIndex, width: width, opacity: compact ? 0.95 : 0.8)

        case .waterway:
            let width = interpolate(zoom: zoom, stops: [(10, 0.6), (13, 1.2), (16, 2.4)]) * boost
            return TopoPaint(colour: palette.waterLine, width: width)

        case .building:
            return TopoPaint(colour: palette.building, opacity: 0.75)

        case .roadCasing:
            let width = interpolate(zoom: zoom, stops: [(10, 1.8), (13, 3.4), (16, 7.0)]) * boost
            return TopoPaint(colour: palette.roadCasing, width: width)
        case .road:
            let width = interpolate(zoom: zoom, stops: [(10, 1.0), (13, 2.2), (16, 5.0)]) * boost
            return TopoPaint(colour: palette.roadFill, width: width)

        case .track:
            let width = interpolate(zoom: zoom, stops: [(11, 1.0), (14, 2.0), (16, 3.0)]) * boost
            // Long dashes read as a vehicle track rather than a footpath.
            return TopoPaint(colour: palette.track, width: width, dash: [width * 3.0, width * 1.6])
        case .path:
            let width = interpolate(zoom: zoom, stops: [(11, 0.9), (14, 1.8), (16, 2.8)]) * boost
            return TopoPaint(colour: palette.path, width: width, dash: [width * 1.8, width * 1.5])

        case .rail:
            let width = interpolate(zoom: zoom, stops: [(12, 0.8), (16, 1.8)]) * boost
            return TopoPaint(colour: palette.rail, width: width, opacity: 0.8)
        }
    }

    /// Linear interpolation between zoom stops, clamped at both ends.
    private static func interpolate(zoom: Double, stops: [(Double, CGFloat)]) -> CGFloat {
        guard let first = stops.first else { return 1 }
        if zoom <= first.0 { return first.1 }
        guard let last = stops.last else { return first.1 }
        if zoom >= last.0 { return last.1 }

        var index = 1
        while index < stops.count {
            let lower = stops[index - 1]
            let upper = stops[index]
            if zoom <= upper.0 {
                let span: Double = upper.0 - lower.0
                guard span > 0 else { return lower.1 }
                let t: Double = (zoom - lower.0) / span
                let delta: CGFloat = upper.1 - lower.1
                return lower.1 + delta * CGFloat(t)
            }
            index += 1
        }
        return last.1
    }

    // MARK: - Labels

    /// Which place labels earn room on the screen at this zoom.
    ///
    /// A watch has space for a handful of names, so the bar is deliberately
    /// high: settlements only, and only those big enough to orient by.
    static func showsPlaceLabel(className: String, zoom: Double) -> Bool {
        switch className {
        case "city": return zoom >= 8
        case "town": return zoom >= 10
        case "village": return zoom >= 12
        case "hamlet", "suburb": return zoom >= 13.5
        case "peak", "mountain": return zoom >= 12
        default: return false
        }
    }
}
