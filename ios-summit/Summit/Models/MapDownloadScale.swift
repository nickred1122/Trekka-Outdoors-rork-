import Foundation
import CoreLocation

/// How much ground one download covers, and how closely it is kept.
///
/// These are two settings that cannot be separated, which is why they are one
/// type. Trekka's map is cut into pieces at fixed zoom levels, and each step
/// closer quadruples the number of pieces a given patch of ground needs. So
/// "trail detail" and "a whole state" are mutually exclusive requests: a state
/// at the zoom level where footpaths appear is tens of gigabytes and days of
/// downloading. Offering them as one slider would be a lie by omission.
///
/// Instead the athlete picks the *job*. Close detail is for the ground being
/// walked. Region is for the ground being driven across to get there — the state
/// or the park, kept at the scale a road atlas is drawn at, so somewhere with no
/// signal still has a map under it even if it was never planned for.
nonisolated enum MapDownloadScale: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Every path, at the zoom levels walking needs.
    case close
    /// A state, a park or a county, at the scale of a road atlas.
    case region

    var id: String { rawValue }

    /// Basemap zooms this scale stores.
    ///
    /// Close detail reuses the shared planner's levels exactly, because a pack
    /// cut for the watch has to contain what the watch expects to find. Region
    /// starts four levels wider and stops before the level where footpaths are
    /// drawn — that level is the entire cost of a fine map, and a state cannot
    /// afford it.
    var vectorZooms: [Int] {
        switch self {
        case .close: MapPackPlanner.vectorZooms
        case .region: [8, 9, 10, 11, 12]
        }
    }

    var terrainZooms: [Int] {
        switch self {
        case .close: MapPackPlanner.terrainZooms
        case .region: [8, 9, 10, 11]
        }
    }

    var minRadiusMetres: Double {
        switch self {
        case .close: AreaDownloadLimits.minRadiusMetres
        case .region: AreaDownloadLimits.minRegionRadiusMetres
        }
    }

    var maxRadiusMetres: Double {
        switch self {
        case .close: AreaDownloadLimits.maxRadiusMetres
        case .region: AreaDownloadLimits.maxRegionRadiusMetres
        }
    }

    /// Slider granularity. Half a kilometre is a meaningful step for a valley
    /// and meaningless for a state.
    var radiusStep: Double {
        switch self {
        case .close: 500
        case .region: 10_000
        }
    }

    /// The most pieces one download may contain.
    ///
    /// Close detail keeps the planner's own ceiling. Region's is far higher
    /// because that is the point of it — but still a ceiling, so a slip of the
    /// finger cannot start a download that never ends.
    var tileCeiling: Int {
        switch self {
        case .close: MapPackPlanner.tileCeiling
        case .region: 14_000
        }
    }

    /// Whether this scale can travel to the wrist.
    ///
    /// A region is hundreds of megabytes and the watch has a few gigabytes for
    /// everything it owns, so sending one would fill it. The watch gets close
    /// detail along the route it is actually walking.
    var allowsWatch: Bool { self == .close }

    var title: String {
        switch self {
        case .close: "Close detail"
        case .region: "Whole region"
        }
    }

    var detail: String {
        switch self {
        case .close: "Every path and track, for ground you are walking"
        case .region: "A state or park at road-atlas scale"
        }
    }

    var symbol: String {
        switch self {
        case .close: "figure.hiking"
        case .region: "globe.americas.fill"
        }
    }

    /// Said next to the option, because the trade is the whole decision.
    var sizeNote: String {
        switch self {
        case .close: "Up to 120 km across"
        case .region: "Up to 600 km across, coarser"
        }
    }

    /// What this scale genuinely cannot show, said before the download starts
    /// rather than discovered on a hillside.
    var limitNote: String? {
        switch self {
        case .close: nil
        case .region: "Roads, rivers, woodland, towns and the shape of the land. Footpaths and small tracks are not drawn at this scale — zoom in close and the map stays coarse. Download the ground you are actually walking at close detail as well."
        }
    }

    /// Clamps a radius to what this scale allows.
    func clamp(radiusMetres: Double) -> Double {
        min(max(radiusMetres, minRadiusMetres), maxRadiusMetres)
    }

    /// Everything a download at this scale should contain.
    ///
    /// Close detail defers to the shared planner so its answer is byte-for-byte
    /// the one the watch would compute for the same ground. Region is planned
    /// here, because those zoom levels exist only on the phone.
    func plan(
        around centre: CLLocationCoordinate2D,
        radiusMetres: Double,
        detail: MapDownloadDetail
    ) -> MapPackPlanner.Plan {
        switch self {
        case .close:
            return detail.trim(
                MapPackPlanner.plan(
                    around: centre,
                    radiusMetres: radiusMetres,
                    ceiling: tileCeiling
                )
            )
        case .region:
            var vector: [TopoTileKey] = []
            for zoom in vectorZooms {
                vector.append(
                    contentsOf: MapPackPlanner.areaTiles(
                        around: centre,
                        radiusMetres: radiusMetres,
                        zoom: zoom
                    )
                )
            }

            var terrain: [TopoTileKey] = []
            if detail.includesTerrain {
                for zoom in terrainZooms {
                    terrain.append(
                        contentsOf: MapPackPlanner.areaTiles(
                            around: centre,
                            radiusMetres: radiusMetres,
                            zoom: zoom
                        )
                    )
                }
            }

            return Self.clamped(
                MapPackPlanner.Plan(vector: vector, terrain: terrain),
                ceiling: tileCeiling
            )
        }
    }

    /// How many pieces this scale would ask for with nothing dropped, so the
    /// picker can tell whether the ceiling had to bite.
    func requestedTileCount(
        around centre: CLLocationCoordinate2D,
        radiusMetres: Double,
        detail: MapDownloadDetail
    ) -> Int {
        var count = 0
        for zoom in vectorZooms {
            count += MapPackPlanner.areaTiles(
                around: centre,
                radiusMetres: radiusMetres,
                zoom: zoom
            ).count
        }
        guard detail.includesTerrain else { return count }
        for zoom in terrainZooms {
            count += MapPackPlanner.areaTiles(
                around: centre,
                radiusMetres: radiusMetres,
                zoom: zoom
            ).count
        }
        return count
    }

    /// Drops the closest zoom levels until the plan fits the ceiling.
    ///
    /// Same reasoning as the shared planner's: a coarser map that finishes
    /// downloading beats a finer one that never does.
    private static func clamped(
        _ plan: MapPackPlanner.Plan,
        ceiling: Int
    ) -> MapPackPlanner.Plan {
        var vector = plan.vector
        var terrain = plan.terrain

        while vector.count + terrain.count > ceiling {
            let deepestVector = vector.map(\.z).max() ?? 0
            let deepestTerrain = terrain.map(\.z).max() ?? 0
            let shallowestVector = vector.map(\.z).min() ?? 0
            let shallowestTerrain = terrain.map(\.z).min() ?? 0

            if deepestVector >= deepestTerrain, deepestVector > shallowestVector {
                vector.removeAll { $0.z == deepestVector }
            } else if deepestTerrain > shallowestTerrain {
                terrain.removeAll { $0.z == deepestTerrain }
            } else {
                break
            }
        }

        return MapPackPlanner.Plan(vector: vector, terrain: terrain)
    }
}
