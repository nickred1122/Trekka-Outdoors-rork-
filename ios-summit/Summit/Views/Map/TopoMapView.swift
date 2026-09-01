import SwiftUI
import MapKit

nonisolated enum MapInteractionMode: String, Sendable {
    case browse
    case waypoint
}

nonisolated enum TopoBaseStyle: String, CaseIterable, Sendable {
    /// Trekka's own topographic sheet, drawn from OpenStreetMap vector tiles.
    /// The default, and the only one that can work without a signal.
    case trekka
    case terrain
    case satellite

    var symbol: String {
        switch self {
        case .trekka: "mountain.2.fill"
        case .terrain: "square.3.layers.3d"
        case .satellite: "globe.americas.fill"
        }
    }

    var title: String {
        switch self {
        case .trekka: "Topographic"
        case .terrain: "Standard"
        case .satellite: "Satellite"
        }
    }

    var next: TopoBaseStyle {
        switch self {
        case .trekka: .terrain
        case .terrain: .satellite
        case .satellite: .trekka
        }
    }

    /// The cycle offered on the route planner.
    ///
    /// Editing runs on Apple's map, which cannot draw Trekka's own sheet, so the
    /// planner skips it rather than offering a "Topographic" button that quietly
    /// hands back the standard map.
    var nextEditable: TopoBaseStyle {
        self == .satellite ? .terrain : .satellite
    }
}

/// Dark topographic map: Apple base map with contour lines, an Ultra-orange
/// route line, breadcrumb trail and diamond waypoint markers.
struct TopoMapView: UIViewRepresentable {
    var routePoints: [RoutePoint] = []
    var breadcrumb: [RoutePoint] = []
    var waypoints: [Waypoint] = []
    var mode: MapInteractionMode = .browse
    var baseStyle: TopoBaseStyle = .terrain
    var showsUserLocation: Bool = true
    var isInteractive: Bool = true
    var currentPosition: RoutePoint?
    var region: MKCoordinateRegion?
    /// Increment to re-frame the map on the route or the user.
    var recenterToken: Int = 0
    var followsUser: Bool = false
    /// Planner geometry. When set, each leg is drawn in the style that tells the
    /// truth about it: solid for routed ways, dashed where the line came in with
    /// a file, and dashed amber where snapping fell back to a straight line.
    var plannerLegs: [RouteDraftModel.Leg] = []
    var plannerNodes: [RouteDraftModel.Node] = []
    var onTap: ((CLLocationCoordinate2D) -> Void)?
    /// A planner node was dragged to a new place.
    var onNodeMoved: ((UUID, CLLocationCoordinate2D) -> Void)?
    var onNodeTapped: ((UUID) -> Void)?

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.overrideUserInterfaceStyle = .dark
        mapView.pointOfInterestFilter = .excludingAll
        mapView.showsCompass = false
        mapView.showsScale = true
        mapView.showsUserLocation = showsUserLocation
        mapView.isPitchEnabled = false
        mapView.isRotateEnabled = false
        mapView.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .realistic, emphasisStyle: .muted)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        mapView.addGestureRecognizer(tap)
        context.coordinator.mapView = mapView

        if let region {
            mapView.setRegion(region, animated: false)
        } else if !routePoints.isEmpty {
            context.coordinator.frame(points: routePoints, animated: false)
        } else if showsUserLocation {
            // No route to frame yet, so open on wherever the athlete is.
            mapView.userTrackingMode = .follow
        }
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self
        mapView.showsUserLocation = showsUserLocation
        if context.coordinator.appliedBaseStyle != baseStyle {
            context.coordinator.appliedBaseStyle = baseStyle
            mapView.preferredConfiguration = baseStyle == .satellite
                ? MKHybridMapConfiguration(elevationStyle: .realistic)
                : MKStandardMapConfiguration(elevationStyle: .realistic, emphasisStyle: .muted)
            mapView.pointOfInterestFilter = .excludingAll
        }
        mapView.isScrollEnabled = isInteractive
        mapView.isZoomEnabled = isInteractive

        context.coordinator.syncOverlays(
            on: mapView,
            routePoints: routePoints,
            breadcrumb: breadcrumb,
            plannerLegs: plannerLegs
        )
        context.coordinator.syncAnnotations(
            on: mapView,
            waypoints: waypoints,
            position: currentPosition,
            plannerNodes: plannerNodes
        )

        if context.coordinator.lastRecenterToken != recenterToken {
            context.coordinator.lastRecenterToken = recenterToken
            if followsUser, let location = mapView.userLocation.location {
                mapView.setRegion(
                    MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 1_200, longitudinalMeters: 1_200),
                    animated: true
                )
            } else if !routePoints.isEmpty {
                context.coordinator.frame(points: routePoints, animated: true)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: TopoMapView
        weak var mapView: MKMapView?
        var lastRecenterToken: Int = 0
        var appliedBaseStyle: TopoBaseStyle = .terrain

        private var routeSignature: Int = -1
        private var breadcrumbSignature: Int = -1
        private var legsSignature: Int = -1
        private var waypointSignature: Int = -1

        init(parent: TopoMapView) {
            self.parent = parent
        }

        // MARK: - Overlays

        func syncOverlays(
            on mapView: MKMapView,
            routePoints: [RoutePoint],
            breadcrumb: [RoutePoint],
            plannerLegs: [RouteDraftModel.Leg]
        ) {
            let newRouteSignature = signature(for: routePoints)
            let newBreadcrumbSignature = signature(for: breadcrumb)
            let newLegSignature = legSignature(for: plannerLegs)
            guard newRouteSignature != routeSignature
                || newBreadcrumbSignature != breadcrumbSignature
                || newLegSignature != legsSignature else { return }
            routeSignature = newRouteSignature
            breadcrumbSignature = newBreadcrumbSignature
            legsSignature = newLegSignature

            mapView.removeOverlays(mapView.overlays)

            if plannerLegs.isEmpty {
                if routePoints.count > 1 {
                    var coordinates = routePoints.map(\.coordinate)
                    let glow = RouteGlowPolyline(coordinates: &coordinates, count: coordinates.count)
                    let line = RouteLinePolyline(coordinates: &coordinates, count: coordinates.count)
                    mapView.addOverlay(glow, level: .aboveLabels)
                    mapView.addOverlay(line, level: .aboveLabels)
                }
            } else {
                // One overlay per leg, so the map itself distinguishes routed
                // ground from an imported line or a snap that failed.
                for leg in plannerLegs where leg.points.count > 1 {
                    var coordinates = leg.points.map(\.coordinate)
                    let glow = RouteGlowPolyline(coordinates: &coordinates, count: coordinates.count)
                    mapView.addOverlay(glow, level: .aboveLabels)

                    let line: MKPolyline = if leg.isSnapped {
                        RouteLinePolyline(coordinates: &coordinates, count: coordinates.count)
                    } else if leg.isAsRecorded {
                        PlannerRecordedPolyline(coordinates: &coordinates, count: coordinates.count)
                    } else {
                        PlannerStraightPolyline(coordinates: &coordinates, count: coordinates.count)
                    }
                    mapView.addOverlay(line, level: .aboveLabels)
                }
            }

            if breadcrumb.count > 1 {
                var coordinates = breadcrumb.map(\.coordinate)
                let trail = BreadcrumbPolyline(coordinates: &coordinates, count: coordinates.count)
                mapView.addOverlay(trail, level: .aboveLabels)
            }
        }

        func syncAnnotations(
            on mapView: MKMapView,
            waypoints: [Waypoint],
            position: RoutePoint?,
            plannerNodes: [RouteDraftModel.Node]
        ) {
            var hasher = Hasher()
            hasher.combine(waypoints)
            hasher.combine(plannerNodes)
            if let position {
                hasher.combine(Int(position.latitude * 10_000))
                hasher.combine(Int(position.longitude * 10_000))
            }
            let newSignature = hasher.finalize()
            guard newSignature != waypointSignature else { return }
            waypointSignature = newSignature

            let stale = mapView.annotations.filter { !($0 is MKUserLocation) }
            mapView.removeAnnotations(stale)

            if plannerNodes.isEmpty {
                for (index, waypoint) in waypoints.enumerated() {
                    mapView.addAnnotation(WaypointAnnotation(waypoint: waypoint, index: index + 1))
                }
            } else {
                for (index, node) in plannerNodes.enumerated() {
                    mapView.addAnnotation(
                        NodeAnnotation(
                            node: node,
                            index: index + 1,
                            isStart: index == 0,
                            isEnd: index == plannerNodes.count - 1 && plannerNodes.count > 1
                        )
                    )
                }
            }
            if let position {
                mapView.addAnnotation(PositionAnnotation(coordinate: position.coordinate))
            }
        }

        func frame(points: [RoutePoint], animated: Bool) {
            guard let mapView, points.count > 1 else { return }
            var coordinates = points.map(\.coordinate)
            let polyline = MKPolyline(coordinates: &coordinates, count: coordinates.count)
            mapView.setVisibleMapRect(
                polyline.boundingMapRect,
                edgePadding: UIEdgeInsets(top: 48, left: 40, bottom: 48, right: 40),
                animated: animated
            )
        }

        private func legSignature(for legs: [RouteDraftModel.Leg]) -> Int {
            var hasher = Hasher()
            hasher.combine(legs.count)
            for leg in legs {
                hasher.combine(leg.id)
                hasher.combine(leg.points.count)
                hasher.combine(leg.isSnapped)
                hasher.combine(leg.isAsRecorded)
                if let last = leg.points.last {
                    hasher.combine(Int(last.latitude * 100_000))
                    hasher.combine(Int(last.longitude * 100_000))
                }
            }
            return hasher.finalize()
        }

        private func signature(for points: [RoutePoint]) -> Int {
            var hasher = Hasher()
            hasher.combine(points.count)
            if let first = points.first {
                hasher.combine(Int(first.latitude * 100_000))
                hasher.combine(Int(first.longitude * 100_000))
            }
            if let last = points.last {
                hasher.combine(Int(last.latitude * 100_000))
                hasher.combine(Int(last.longitude * 100_000))
            }
            return hasher.finalize()
        }

        // MARK: - MKMapViewDelegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? RouteGlowPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor(red: 1.0, green: 0.416, blue: 0.075, alpha: 0.22)
                renderer.lineWidth = 12
                renderer.lineCap = .round
                return renderer
            }
            if let polyline = overlay as? PlannerRecordedPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor(red: 1.0, green: 0.478, blue: 0.153, alpha: 1.0)
                renderer.lineWidth = 4
                renderer.lineDashPattern = [2, 7]
                renderer.lineCap = .round
                return renderer
            }
            if let polyline = overlay as? PlannerStraightPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor(red: 1.0, green: 0.831, blue: 0.286, alpha: 0.95)
                renderer.lineWidth = 4
                renderer.lineDashPattern = [8, 6]
                renderer.lineCap = .butt
                return renderer
            }
            if let polyline = overlay as? BreadcrumbPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor(red: 1.0, green: 0.31, blue: 0.06, alpha: 1.0)
                renderer.lineWidth = 6
                renderer.lineCap = .round
                return renderer
            }
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor(red: 1.0, green: 0.478, blue: 0.153, alpha: 1.0)
                renderer.lineWidth = 4
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }

            if let waypoint = annotation as? WaypointAnnotation {
                let identifier = "waypoint"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                    ?? MKAnnotationView(annotation: waypoint, reuseIdentifier: identifier)
                view.annotation = waypoint
                view.image = MarkerImages.diamond(number: waypoint.index)
                view.canShowCallout = true
                view.centerOffset = .zero
                return view
            }

            if let node = annotation as? NodeAnnotation {
                let identifier = "node"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                    ?? MKAnnotationView(annotation: node, reuseIdentifier: identifier)
                view.annotation = node
                view.image = MarkerImages.node(
                    index: node.index,
                    isWaypoint: node.isWaypoint,
                    isStart: node.isStart,
                    isEnd: node.isEnd
                )
                view.canShowCallout = false
                view.centerOffset = .zero
                // Dragging a node is how the route gets refined; MapKit gives us
                // this for free once the view opts in.
                view.isDraggable = parent.onNodeMoved != nil
                return view
            }

            if let position = annotation as? PositionAnnotation {
                let identifier = "position"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                    ?? MKAnnotationView(annotation: position, reuseIdentifier: identifier)
                view.annotation = position
                view.image = MarkerImages.positionDot()
                view.canShowCallout = false
                return view
            }
            return nil
        }

        func mapView(
            _ mapView: MKMapView,
            annotationView view: MKAnnotationView,
            didChange newState: MKAnnotationView.DragState,
            fromOldState oldState: MKAnnotationView.DragState
        ) {
            guard let node = view.annotation as? NodeAnnotation else { return }
            switch newState {
            case .ending, .canceling:
                view.setDragState(.none, animated: false)
                parent.onNodeMoved?(node.nodeID, view.annotation?.coordinate ?? node.coordinate)
            default:
                break
            }
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let node = view.annotation as? NodeAnnotation else { return }
            mapView.deselectAnnotation(view.annotation, animated: false)
            parent.onNodeTapped?(node.nodeID)
        }

        // MARK: - Gestures

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard parent.mode == .waypoint, let mapView else { return }
            let point = gesture.location(in: mapView)
            // A tap that lands on a node belongs to the node, not the map.
            for annotation in mapView.annotations {
                guard annotation is NodeAnnotation,
                      let view = mapView.view(for: annotation) else { continue }
                if view.frame.insetBy(dx: -8, dy: -8).contains(point) { return }
            }
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            parent.onTap?(coordinate)
        }

        /// The tap that places a point has to coexist with the map's own pan and
        /// zoom, which is what this allows.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

// MARK: - Overlay + annotation types

nonisolated final class RouteGlowPolyline: MKPolyline {}
nonisolated final class RouteLinePolyline: MKPolyline {}
nonisolated final class BreadcrumbPolyline: MKPolyline {}
/// A stretch that came in with a file — dashed, kept as recorded rather than
/// passed off as a routed way.
nonisolated final class PlannerRecordedPolyline: MKPolyline {}
/// A stretch that asked to snap and could not — dashed amber, so the plan is
/// honest about crossing ground with no known route.
nonisolated final class PlannerStraightPolyline: MKPolyline {}

/// A draggable planner node.
nonisolated final class NodeAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    let nodeID: UUID
    let index: Int
    let isWaypoint: Bool
    let isStart: Bool
    let isEnd: Bool

    init(node: RouteDraftModel.Node, index: Int, isStart: Bool, isEnd: Bool) {
        self.coordinate = node.coordinate
        self.nodeID = node.id
        self.index = index
        self.isWaypoint = node.isWaypoint
        self.isStart = isStart
        self.isEnd = isEnd
    }
}

nonisolated final class WaypointAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?
    let index: Int

    init(waypoint: Waypoint, index: Int) {
        self.coordinate = waypoint.coordinate
        self.title = waypoint.name
        self.subtitle = "\(Int(waypoint.elevation.rounded())) m · \(Formatters.distance(waypoint.distanceAlongRoute)) km in"
        self.index = index
    }
}

nonisolated final class PositionAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
    }
}

/// Renders the small orange diamond and position markers used on every map.
nonisolated enum MarkerImages {
    static func diamond(number: Int) -> UIImage {
        let size = CGSize(width: 30, height: 30)
        return UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            let path = UIBezierPath()
            let inset: CGFloat = 4
            path.move(to: CGPoint(x: size.width / 2, y: inset))
            path.addLine(to: CGPoint(x: size.width - inset, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width / 2, y: size.height - inset))
            path.addLine(to: CGPoint(x: inset, y: size.height / 2))
            path.close()
            cg.setFillColor(UIColor(red: 1.0, green: 0.416, blue: 0.075, alpha: 1).cgColor)
            cg.addPath(path.cgPath)
            cg.fillPath()
            cg.setStrokeColor(UIColor(white: 0.05, alpha: 1).cgColor)
            cg.setLineWidth(1.5)
            cg.addPath(path.cgPath)
            cg.strokePath()

            let text = "\(number)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .bold),
                .foregroundColor: UIColor(white: 0.04, alpha: 1),
            ]
            let textSize = text.size(withAttributes: attributes)
            text.draw(
                at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2),
                withAttributes: attributes
            )
        }
    }

    /// Planner handles: a green start, a chequered-feel finish, orange diamonds
    /// for named waypoints and small dots for plain shaping nodes.
    static func node(index: Int, isWaypoint: Bool, isStart: Bool, isEnd: Bool) -> UIImage {
        if isWaypoint { return diamond(number: index) }

        let side: CGFloat = isStart || isEnd ? 24 : 17
        let size = CGSize(width: side, height: side)
        let fill: UIColor = if isStart {
            UIColor(red: 0.32, green: 0.85, blue: 0.55, alpha: 1)
        } else if isEnd {
            UIColor.white
        } else {
            UIColor(red: 1.0, green: 0.416, blue: 0.075, alpha: 1)
        }

        return UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            let inset: CGFloat = 3
            let rect = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
            cg.setShadow(offset: .zero, blur: 4, color: UIColor.black.withAlphaComponent(0.7).cgColor)
            cg.setFillColor(fill.cgColor)
            cg.fillEllipse(in: rect)
            cg.setShadow(offset: .zero, blur: 0, color: nil)
            cg.setStrokeColor(UIColor(white: 0.04, alpha: 1).cgColor)
            cg.setLineWidth(isStart || isEnd ? 2.5 : 2)
            cg.strokeEllipse(in: rect)
        }
    }

    static func positionDot() -> UIImage {
        let size = CGSize(width: 22, height: 22)
        return UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            cg.setFillColor(UIColor.white.cgColor)
            cg.fillEllipse(in: CGRect(x: 2, y: 2, width: 18, height: 18))
            cg.setFillColor(UIColor(red: 1.0, green: 0.416, blue: 0.075, alpha: 1).cgColor)
            cg.fillEllipse(in: CGRect(x: 6, y: 6, width: 10, height: 10))
        }
    }
}
