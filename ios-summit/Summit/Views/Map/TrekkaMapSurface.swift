import SwiftUI
import CoreLocation

/// The phone's read-only map surface.
///
/// Picks the renderer from the chosen base style: Trekka's own topographic
/// sheet, or Apple's map when the athlete wants familiar surroundings and points
/// of interest. Only the topographic sheet can work without a signal, so it is
/// the default.
///
/// The route planner deliberately keeps using `TopoMapView` directly: editing
/// needs tap, drag and freehand gestures that belong to that view.
struct TrekkaMapSurface: View {
    var routePoints: [RoutePoint] = []
    var waypoints: [Waypoint] = []
    var breadcrumb: [RoutePoint] = []
    var currentPosition: RoutePoint?
    var baseStyle: TopoBaseStyle = .trekka
    var isInteractive: Bool = true
    var showsUserLocation: Bool = true
    /// Hold the map on one spot — used while a workout follows the athlete.
    /// Nil lets the map frame itself on whatever it has been given.
    var centre: CLLocationCoordinate2D?
    /// Ground metres across the taller edge, when following a fixed centre.
    var spanMetres: Double?
    /// Increment to fit the content back on screen.
    var recenterToken: Int = 0
    /// Increment to put the athlete's own position in the middle.
    ///
    /// Separate from `recenterToken` because they are different requests: one
    /// means "show me the route", the other means "show me where I am".
    var locateToken: Int = 0

    private let location = MapLocationService.shared

    var body: some View {
        switch baseStyle {
        case .trekka:
            TrekkaTopoMap(
                overlay: overlay,
                centre: centre,
                spanMetres: spanMetres,
                allowsPan: isInteractive,
                allowsZoom: isInteractive,
                showsContours: true,
                showsPlaceLabels: true,
                reframeToken: recenterToken,
                focus: focus,
                palette: .paperSheet,
                compact: false,
                labelFont: .system(size: 11, weight: .semibold),
                attributionFont: .system(size: 9)
            )
            .overlay(alignment: .top) { locateStatus }
            .onAppear { if showsUserLocation { location.start() } }
            .onDisappear { if showsUserLocation { location.stop() } }
        case .terrain, .satellite:
            TopoMapView(
                routePoints: routePoints,
                breadcrumb: breadcrumb,
                waypoints: waypoints,
                mode: .browse,
                baseStyle: baseStyle,
                showsUserLocation: showsUserLocation,
                isInteractive: isInteractive,
                currentPosition: currentPosition,
                recenterToken: recenterToken
            )
        }
    }

    /// Where to put the camera when the athlete asks to be located.
    private var focus: TopoFocus? {
        guard locateToken > 0, let coordinate = location.coordinate else { return nil }
        return TopoFocus(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            token: locateToken
        )
    }

    /// Says why the locate button did nothing, rather than leaving it silent.
    ///
    /// Trekka's own renderer has no system location control to fall back on, so
    /// if this is missing a denied permission looks exactly like a broken button.
    @ViewBuilder
    private var locateStatus: some View {
        if locateToken > 0, showsUserLocation {
            if location.isDenied {
                locateBanner("Location is off for Trekka. Turn it on in Settings.")
            } else if location.coordinate == nil {
                locateBanner("Finding your position\u{2026}")
            }
        }
    }

    private func locateBanner(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.canvas)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.textPrimary.opacity(0.85), in: .capsule)
            .padding(.top, 8)
            .transition(.opacity)
            .allowsHitTesting(false)
    }

    private var overlay: TopoOverlay {
        TopoOverlay(
            route: routePoints.map(\.coordinate),
            breadcrumb: breadcrumb.map(\.coordinate),
            waypoints: waypoints.map(\.coordinate),
            // A live workout supplies its own position; anywhere else the dot is
            // the athlete's actual location, which the renderer cannot know on
            // its own the way Apple's map view does.
            position: currentPosition?.coordinate ?? (showsUserLocation ? location.coordinate : nil),
            // The athlete's chosen line colours, so a course reads the same on
            // the phone as it does on the wrist.
            routeTint: TrailStyle.route.color,
            trailTint: TrailStyle.breadcrumb.color
        )
    }
}
