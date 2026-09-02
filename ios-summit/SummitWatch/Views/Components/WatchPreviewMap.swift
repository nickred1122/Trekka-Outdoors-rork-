import SwiftUI
import CoreLocation

/// A small, still topographic map for route and trail cards.
///
/// Draws Trekka's own map rather than the platform's, because the watch has to
/// be able to show ground with no signal and no phone — and because a map this
/// small needs its own line weights to stay readable.
struct WatchPreviewMap: View {
    var route: [CLLocationCoordinate2D] = []
    var breadcrumb: [CLLocationCoordinate2D] = []
    var waypoints: [WatchWaypoint] = []
    var position: CLLocationCoordinate2D?
    /// Fixed centre. Nil frames the map on whatever is drawn on it.
    var centre: CLLocationCoordinate2D?
    /// How many metres the taller edge spans. Nil frames to fit the content.
    var spanMetres: Double?
    var routeTint: Color = WatchTheme.accent
    var breadcrumbTint: Color = WatchTheme.highlight
    var usesNightSheet: Bool = false
    /// Lets a finger drag the ground about. Off for cards, which live inside
    /// scrolling pages and must not swallow the scroll.
    var allowsPan: Bool = false

    var body: some View {
        TrekkaTopoMap(
            overlay: overlay,
            centre: centre,
            spanMetres: spanMetres,
            allowsPan: allowsPan,
            showsContours: true,
            // A card this small has no room for names.
            showsPlaceLabels: false,
            // Nor for direction arrows: at card scale they only thicken the
            // line. Direction is shown where it is acted on — the workout map.
            showsRouteDirection: false,
            showsAttribution: false,
            palette: usesNightSheet ? .nightSheet : .paperSheet,
            compact: true,
            labelFont: .watch(9, weight: .semibold),
            attributionFont: .watch(8)
        )
    }

    private var overlay: TopoOverlay {
        TopoOverlay(
            route: route,
            breadcrumb: breadcrumb,
            waypoints: waypoints.map(\.coordinate),
            position: position,
            routeTint: routeTint,
            trailTint: breadcrumbTint
        )
    }
}
