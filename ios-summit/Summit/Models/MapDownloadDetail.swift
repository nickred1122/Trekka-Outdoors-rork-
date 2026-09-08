import Foundation

/// What an offline download should actually contain.
///
/// The choice here is real rather than cosmetic. Trekka's map is drawn from two
/// separate sets of tiles fetched from two different servers: vector tiles carry
/// the paths, roads, water and woodland, and terrain tiles carry the heights the
/// contour lines are traced from. Terrain is the heavier half, so leaving it out
/// roughly halves both the download and the space it takes.
///
/// Paper versus night is deliberately *not* offered here. That is a drawing
/// choice made when the map is shown, and offering it at download time would
/// imply it changed what gets stored, which it does not.
nonisolated enum MapDownloadDetail: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Ground plus contour lines — what the outdoors actually needs.
    case topographic
    /// Paths, tracks, roads, water and woodland, with no contours.
    case trailsOnly

    var id: String { rawValue }

    /// The only behavioural difference, and the reason this type exists.
    var includesTerrain: Bool { self == .topographic }

    var title: String {
        switch self {
        case .topographic: "Topographic"
        case .trailsOnly: "Trails only"
        }
    }

    var detail: String {
        switch self {
        case .topographic: "Contour lines, ground cover, every path"
        case .trailsOnly: "Paths, roads and water — no contours"
        }
    }

    /// What choosing this costs or saves, said plainly next to the option.
    var sizeNote: String {
        switch self {
        case .topographic: "Full detail"
        case .trailsOnly: "About half the size"
        }
    }

    var symbol: String {
        switch self {
        case .topographic: "mountain.2.fill"
        case .trailsOnly: "point.topleft.down.curvedto.point.bottomright.up.fill"
        }
    }

    /// Trims a planned download to what this choice asks for.
    ///
    /// Done here rather than inside the planner on purpose: the planner file is
    /// duplicated byte-for-byte in the watch target so both devices agree about
    /// which tiles a route needs, and a phone-only preference has no business
    /// changing that shared arithmetic.
    func trim(_ plan: MapPackPlanner.Plan) -> MapPackPlanner.Plan {
        guard !includesTerrain else { return plan }
        return MapPackPlanner.Plan(vector: plan.vector, terrain: [])
    }
}
