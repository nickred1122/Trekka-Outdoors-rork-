import Foundation
import CoreLocation
import Observation

/// What the planner does when you touch the map.
nonisolated enum PlannerTool: String, CaseIterable, Sendable, Identifiable {
    /// Pan and zoom only.
    case move
    /// Tap to drop the next point of the route.
    case add

    var id: String { rawValue }

    var title: String {
        switch self {
        case .move: "Move"
        case .add: "Add"
        }
    }

    var symbol: String {
        switch self {
        case .move: "hand.draw"
        case .add: "plus.circle"
        }
    }

    var hint: String {
        switch self {
        case .move: "Pan and zoom the map"
        case .add: "Tap the map to extend the route"
        }
    }
}

/// Whether the route's elevation profile is real measured ground.
nonisolated enum DraftElevationState: Sendable, Equatable {
    case none
    case loading
    case measured
    /// Terrain tiles could not be read for part of the line.
    case unavailable
}

/// Editing state for the route planner.
///
/// A route is a list of nodes the athlete placed, plus the geometry joining
/// each consecutive pair. That geometry is resolved by the snapping service, so
/// changing the snap mode or dragging a node re-routes only the legs affected.
/// Elevation is sampled from downloaded terrain tiles — never modelled — so a
/// profile is either measured ground or openly marked unavailable.
@Observable
final class RouteDraftModel {
    /// A point the athlete placed, which can be promoted to a named waypoint.
    struct Node: Identifiable, Hashable {
        var id: UUID = UUID()
        var latitude: Double
        var longitude: Double
        var isWaypoint: Bool = false
        var name: String = ""
        var note: String = ""

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }

        init(coordinate: CLLocationCoordinate2D, isWaypoint: Bool = false) {
            self.latitude = coordinate.latitude
            self.longitude = coordinate.longitude
            self.isWaypoint = isWaypoint
        }
    }

    /// The resolved line between node `index` and node `index + 1`.
    struct Leg: Identifiable, Hashable {
        var id: UUID = UUID()
        var points: [RoutePoint]
        var isSnapped: Bool
        var failureReason: String?
        /// True when this stretch arrived with a file or a saved route and is
        /// kept exactly as recorded rather than routed by us.
        var isAsRecorded: Bool = false
        var isResolving: Bool = false

        /// A leg that asked to snap and had to settle for a straight line.
        var isStraightFallback: Bool { !isSnapped && !isAsRecorded && failureReason != nil }
    }

    private(set) var nodes: [Node] = []
    private(set) var legs: [Leg] = []
    private(set) var elevationState: DraftElevationState = .none
    /// Set when the last snap attempt fell back to a straight line.
    private(set) var snapNotice: String?

    /// The planner opens ready to place points: tapping the map is how a route
    /// is built by hand.
    var tool: PlannerTool = .add

    /// How two placed points are joined. The builder sets this from the
    /// activity as it opens — two points on a hillside should follow the path
    /// between them rather than cut across the contours — and the "Trails" chip
    /// turns it off for cross-country lines.
    var snapMode: RouteSnapMode = .foot {
        didSet {
            guard oldValue != snapMode else { return }
            resnapAll()
        }
    }
    var importError: String?

    /// Cached elevations by rounded coordinate, so redraws reuse measured ground.
    private var elevationCache: [Int: Double] = [:]
    private var undoStack: [Snapshot] = []
    private var elevationTask: Task<Void, Never>?
    private var resolveGeneration = 0

    private struct Snapshot {
        let nodes: [Node]
        let legs: [Leg]
    }

    // MARK: - Derived

    /// The full track, start node first.
    var points: [RoutePoint] {
        guard let first = nodes.first else { return [] }
        guard !legs.isEmpty else { return [pointForNode(first)] }
        var result: [RoutePoint] = [legs[0].points.first ?? pointForNode(first)]
        for leg in legs {
            result.append(contentsOf: leg.points.dropFirst())
        }
        return result
    }

    var waypoints: [Waypoint] {
        guard !nodes.isEmpty else { return [] }
        let track = points
        let cumulative = RouteMath.cumulativeDistances(of: track)
        var counter = 0
        return nodes.compactMap { node -> Waypoint? in
            guard node.isWaypoint else { return nil }
            counter += 1
            let elevation = elevationCache[cacheKey(for: node.coordinate)] ?? 0
            let point = RoutePoint(coordinate: node.coordinate, elevation: elevation)
            return Waypoint(
                id: node.id,
                name: node.name.isEmpty ? "Waypoint \(counter)" : node.name,
                note: node.note,
                point: point,
                distanceAlongRoute: distanceAlong(track: track, cumulative: cumulative, to: node.coordinate)
            )
        }
    }

    var isEmpty: Bool { nodes.isEmpty }
    var canUndo: Bool { !undoStack.isEmpty }
    var isResolving: Bool { legs.contains { $0.isResolving } }

    var distance: Double { RouteMath.distance(of: points) }

    /// Climb in metres, or `nil` when the profile is not measured ground.
    var elevationGain: Double? {
        guard elevationState == .measured else { return nil }
        return RouteMath.elevationGain(of: points)
    }

    var minElevation: Double? {
        guard elevationState == .measured else { return nil }
        return points.map(\.elevation).min()
    }

    var maxElevation: Double? {
        guard elevationState == .measured else { return nil }
        return points.map(\.elevation).max()
    }

    /// How much of the route follows real routed ways, 0–1.
    var snappedFraction: Double {
        let total = legs.reduce(0.0) { $0 + RouteMath.distance(of: $1.points) }
        guard total > 0 else { return 0 }
        let snapped = legs.filter(\.isSnapped).reduce(0.0) { $0 + RouteMath.distance(of: $1.points) }
        return snapped / total
    }

    /// Legs that wanted to snap and could not, for the planner's honesty note.
    var straightLineLegCount: Int {
        legs.filter { $0.isStraightFallback }.count
    }

    var isLoop: Bool {
        guard let first = nodes.first, let last = nodes.last, nodes.count > 2 else { return false }
        return CLLocation(latitude: first.latitude, longitude: first.longitude)
            .distance(from: CLLocation(latitude: last.latitude, longitude: last.longitude)) < 25
    }

    // MARK: - Editing

    /// Adds the next node and routes the leg that reaches it.
    func addNode(at coordinate: CLLocationCoordinate2D) {
        pushUndo()
        let node = Node(coordinate: coordinate)
        let previous = nodes.last
        nodes.append(node)

        guard let previous else {
            sampleElevation()
            return
        }
        legs.append(Leg(points: [], isSnapped: false, isResolving: true))
        resolveLeg(at: legs.count - 1, from: previous.coordinate, to: coordinate)
    }

    /// Moves an existing node, re-routing only the legs it touches.
    func moveNode(id: UUID, to coordinate: CLLocationCoordinate2D) {
        guard let index = nodes.firstIndex(where: { $0.id == id }) else { return }
        pushUndo()
        nodes[index].latitude = coordinate.latitude
        nodes[index].longitude = coordinate.longitude

        if index > 0, legs.indices.contains(index - 1) {
            legs[index - 1].isResolving = true
            legs[index - 1].isAsRecorded = false
            resolveLeg(at: index - 1, from: nodes[index - 1].coordinate, to: coordinate)
        }
        if legs.indices.contains(index) {
            legs[index].isResolving = true
            legs[index].isAsRecorded = false
            resolveLeg(at: index, from: coordinate, to: nodes[index + 1].coordinate)
        }
    }

    /// Removes a node and rejoins its neighbours.
    func removeNode(id: UUID) {
        guard let index = nodes.firstIndex(where: { $0.id == id }) else { return }
        pushUndo()
        nodes.remove(at: index)

        if index == 0 {
            if !legs.isEmpty { legs.removeFirst() }
        } else if index == nodes.count {
            if !legs.isEmpty { legs.removeLast() }
        } else if legs.indices.contains(index) {
            // Drop the outgoing leg and re-route the incoming one to the next node.
            legs.remove(at: index)
            legs[index - 1].isResolving = true
            legs[index - 1].isAsRecorded = false
            resolveLeg(at: index - 1, from: nodes[index - 1].coordinate, to: nodes[index].coordinate)
        }
        sampleElevation()
    }

    /// Removes the last node placed — the planner's main undo gesture.
    func removeLastNode() {
        guard let last = nodes.last else { return }
        removeNode(id: last.id)
    }

    /// Joins the end back to the start, turning an out-and-back into a loop.
    func closeLoop() {
        guard canCloseLoop else { return }
        pushUndo()
        joinEndToStart()
    }

    var canCloseLoop: Bool { nodes.count > 2 && !isLoop }

    /// The join itself, without an undo step, so shaping a fresh stroke stays a
    /// single edit rather than something the athlete has to undo twice.
    private func joinEndToStart() {
        guard let first = nodes.first, let last = nodes.last else { return }
        nodes.append(Node(coordinate: first.coordinate))
        legs.append(Leg(points: [], isSnapped: false, isResolving: true))
        resolveLeg(at: legs.count - 1, from: last.coordinate, to: first.coordinate)
    }

    /// Whether there is a line to fold back on itself.
    var canOutAndBack: Bool { nodes.count > 1 && !isLoop }

    /// Turns the line into a there-and-back: walk it out, then walk it home.
    ///
    /// The return leg reuses the geometry already resolved on the way out rather
    /// than asking the router again — it is the same ground, and re-routing it
    /// would risk coming home by a different path than the one just drawn.
    func outAndBack() {
        guard canOutAndBack else { return }
        pushUndo()
        foldOutAndBack()
    }

    private func foldOutAndBack() {
        let outboundNodes = nodes
        let outboundLegs = legs

        for index in stride(from: outboundNodes.count - 2, through: 0, by: -1) {
            guard outboundLegs.indices.contains(index) else { continue }
            // A fresh node, not the original: waypoint names belong to the
            // outbound pass, and duplicated identifiers would break the list.
            nodes.append(Node(coordinate: outboundNodes[index].coordinate))

            var leg = outboundLegs[index]
            leg.id = UUID()
            leg.points.reverse()
            legs.append(leg)
        }

        sampleElevation()
    }

    /// Reverses the direction of travel.
    func reverse() {
        guard nodes.count > 1 else { return }
        pushUndo()
        nodes.reverse()
        legs.reverse()
        for index in legs.indices {
            legs[index].points.reverse()
        }
        sampleElevation()
    }

    func toggleWaypoint(nodeID: UUID) {
        guard let index = nodes.firstIndex(where: { $0.id == nodeID }) else { return }
        pushUndo()
        nodes[index].isWaypoint.toggle()
        if !nodes[index].isWaypoint {
            nodes[index].name = ""
            nodes[index].note = ""
        }
    }

    func rename(nodeID: UUID, to name: String, note: String) {
        guard let index = nodes.firstIndex(where: { $0.id == nodeID }) else { return }
        pushUndo()
        nodes[index].isWaypoint = true
        nodes[index].name = name
        nodes[index].note = note
    }

    // MARK: - Snapping

    /// Routes one leg, replacing its geometry when the router answers.
    ///
    /// A straight line stands in while the request is out, so the route always
    /// shows something between two placed points; it is replaced the moment the
    /// router answers, and stays — marked as a fallback — if it cannot.
    private func resolveLeg(
        at index: Int,
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) {
        resolveGeneration += 1
        let generation = resolveGeneration
        let legID = legs.indices.contains(index) ? legs[index].id : nil
        let mode = snapMode

        // Show something immediately; the routed line replaces it when it lands.
        if legs.indices.contains(index), legs[index].points.isEmpty {
            legs[index].points = RouteSnapService.straightLine(from: start, to: end)
        }

        Task { [weak self] in
            let resolved = await RouteSnapService.shared.leg(from: start, to: end, mode: mode)
            guard let self, generation <= self.resolveGeneration else { return }
            guard let legID, let current = self.legs.firstIndex(where: { $0.id == legID }) else { return }

            self.legs[current] = Leg(
                id: legID,
                points: resolved.coordinates,
                isSnapped: resolved.isSnapped,
                failureReason: resolved.failureReason
            )
            self.snapNotice = resolved.failureReason
            self.sampleElevation()
        }
    }

    /// Re-routes every leg after a change of snapping mode.
    ///
    /// Legs that came in with a file are left alone: their geometry is a record
    /// of ground already travelled, and re-routing it would replace what was
    /// surveyed with what a routing service guesses.
    private func resnapAll() {
        guard nodes.count > 1 else { return }
        for index in legs.indices {
            guard !legs[index].isAsRecorded else { continue }
            guard nodes.indices.contains(index + 1) else { continue }
            legs[index].isResolving = true
            resolveLeg(
                at: index,
                from: nodes[index].coordinate,
                to: nodes[index + 1].coordinate
            )
        }
    }

    // MARK: - Elevation

    /// Fills the track's elevations from downloaded terrain tiles.
    private func sampleElevation() {
        elevationTask?.cancel()
        let track = points
        guard track.count > 1 else {
            elevationState = .none
            return
        }

        // Reuse anything already measured so the profile does not blank out
        // while a new stretch is being fetched.
        applyCachedElevations()
        let needed = track.filter { elevationCache[cacheKey(for: $0.coordinate)] == nil }
        guard !needed.isEmpty else {
            elevationState = .measured
            return
        }

        elevationState = .loading
        elevationTask = Task { [weak self] in
            guard let self else { return }
            // Sampling every point of a long route would pull far more tiles
            // than the shape needs; one in four is plenty at tile resolution.
            let stride = max(1, needed.count / 400)
            let queried = Swift.stride(from: 0, to: needed.count, by: stride).map { needed[$0].coordinate }
            let results = await RouteElevationService.shared.elevations(at: queried)
            guard !Task.isCancelled else { return }

            var measured = 0
            for (coordinate, value) in zip(queried, results) {
                guard let value else { continue }
                self.elevationCache[self.cacheKey(for: coordinate)] = value
                measured += 1
            }

            self.applyCachedElevations()
            self.elevationState = measured == 0 ? .unavailable : .measured
        }
    }

    /// Writes cached elevations onto the legs, interpolating between the points
    /// that were sampled so the profile stays continuous.
    private func applyCachedElevations() {
        for legIndex in legs.indices {
            var known: [(index: Int, value: Double)] = []
            for (pointIndex, point) in legs[legIndex].points.enumerated() {
                if let value = elevationCache[cacheKey(for: point.coordinate)] {
                    known.append((pointIndex, value))
                }
            }
            guard let firstKnown = known.first, let lastKnown = known.last else { continue }

            for pointIndex in legs[legIndex].points.indices {
                if pointIndex <= firstKnown.index {
                    legs[legIndex].points[pointIndex].elevation = firstKnown.value
                    continue
                }
                if pointIndex >= lastKnown.index {
                    legs[legIndex].points[pointIndex].elevation = lastKnown.value
                    continue
                }
                // Between two measured samples, walk along the straight line
                // joining them. This is interpolation of measured ground, not
                // invented relief.
                guard let upper = known.first(where: { $0.index >= pointIndex }),
                      let lower = known.last(where: { $0.index <= pointIndex }) else { continue }
                if upper.index == lower.index {
                    legs[legIndex].points[pointIndex].elevation = upper.value
                } else {
                    let t = Double(pointIndex - lower.index) / Double(upper.index - lower.index)
                    legs[legIndex].points[pointIndex].elevation = lower.value + (upper.value - lower.value) * t
                }
            }
        }
    }

    private func cacheKey(for coordinate: CLLocationCoordinate2D) -> Int {
        var hasher = Hasher()
        hasher.combine(Int((coordinate.latitude * 60_000).rounded()))
        hasher.combine(Int((coordinate.longitude * 60_000).rounded()))
        return hasher.finalize()
    }

    private func pointForNode(_ node: Node) -> RoutePoint {
        RoutePoint(
            coordinate: node.coordinate,
            elevation: elevationCache[cacheKey(for: node.coordinate)] ?? 0
        )
    }

    private func distanceAlong(
        track: [RoutePoint],
        cumulative: [Double],
        to coordinate: CLLocationCoordinate2D
    ) -> Double {
        guard !track.isEmpty else { return 0 }
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        var bestIndex = 0
        var bestDistance = Double.infinity
        for (index, point) in track.enumerated() {
            let candidate = location.distance(
                from: CLLocation(latitude: point.latitude, longitude: point.longitude)
            )
            if candidate < bestDistance {
                bestDistance = candidate
                bestIndex = index
            }
        }
        return cumulative.indices.contains(bestIndex) ? cumulative[bestIndex] : 0
    }

    // MARK: - Import / load

    /// Loads a saved route back into the planner for editing.
    ///
    /// Its waypoints become editable nodes and the track between them is kept
    /// exactly as saved, so opening a route to change one thing never silently
    /// re-routes the rest of it.
    func load(from route: PlannedRoute) {
        pushUndo()
        nodes = []
        legs = []
        elevationCache = [:]

        guard route.points.count > 1 else { return }

        for point in route.points where point.elevation != 0 {
            elevationCache[cacheKey(for: point.coordinate)] = point.elevation
        }

        var anchors: [(index: Int, isWaypoint: Bool, name: String, note: String)] = [
            (0, false, "", "")
        ]
        let cumulative = RouteMath.cumulativeDistances(of: route.points)
        for waypoint in route.waypoints.sorted(by: { $0.distanceAlongRoute < $1.distanceAlongRoute }) {
            var bestIndex = 0
            var bestDelta = Double.infinity
            for (index, value) in cumulative.enumerated() {
                let delta = abs(value - waypoint.distanceAlongRoute)
                if delta < bestDelta {
                    bestDelta = delta
                    bestIndex = index
                }
            }
            guard bestIndex > 0, bestIndex < route.points.count - 1 else { continue }
            anchors.append((bestIndex, true, waypoint.name, waypoint.note))
        }
        anchors.append((route.points.count - 1, false, "", ""))
        anchors.sort { $0.index < $1.index }

        for anchor in anchors {
            var node = Node(coordinate: route.points[anchor.index].coordinate, isWaypoint: anchor.isWaypoint)
            node.name = anchor.name
            node.note = anchor.note
            nodes.append(node)
        }

        for index in 0..<(anchors.count - 1) {
            let slice = Array(route.points[anchors[index].index...anchors[index + 1].index])
            legs.append(Leg(points: slice, isSnapped: false, isAsRecorded: true))
        }

        tool = .move
        elevationState = route.points.contains { $0.elevation != 0 } ? .measured : .none
    }

    /// Reads a GPX file into a route without disturbing the planner canvas, so an
    /// import can go straight into the library instead of becoming an unsaved draft.
    func route(fromGPX url: URL) -> PlannedRoute? {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let fallbackName = url.deletingPathExtension().lastPathComponent
            let route = try GPXCodec.parse(data: data, fallbackName: fallbackName)
            importError = nil
            return route
        } catch let error as GPXError {
            importError = error.errorDescription
            return nil
        } catch {
            importError = "That file could not be opened."
            return nil
        }
    }

    // MARK: - Undo / clear

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        nodes = previous.nodes
        legs = previous.legs
        sampleElevation()
    }

    func clear() {
        pushUndo()
        nodes = []
        legs = []
        snapNotice = nil
        elevationState = .none
    }

    // MARK: - Output

    func makeRoute(name: String, activity: RouteActivityType, source: RouteSource) -> PlannedRoute {
        PlannedRoute(
            name: name,
            source: source,
            activity: activity,
            points: points,
            waypoints: waypoints
        )
    }

    private func pushUndo() {
        undoStack.append(Snapshot(nodes: nodes, legs: legs))
        if undoStack.count > 40 { undoStack.removeFirst() }
    }
}
