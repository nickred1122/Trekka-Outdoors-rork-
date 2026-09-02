import SwiftUI
import CoreLocation
import WatchKit

/// A full-screen map you can actually work with: the Crown zooms, a drag pans.
///
/// The small map on a route or trail card deliberately does not take the Crown.
/// It lives inside a scrolling page, and a map that grabs the Crown there would
/// trap the athlete on one card with no way to scroll past it. So the
/// interactive map is somewhere you go, and once you are there the Crown has
/// only one job and there is nothing else on screen competing for it.
/// The corner mark that says a small map card opens into a real one.
///
/// Without it the card looks like a picture, and the full map — the only place
/// the Crown zooms — goes undiscovered.
struct MapExpandBadge: View {
    var body: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.watch(9, weight: .bold))
            .foregroundStyle(WatchTheme.canvas)
            .frame(width: WatchDisplay.scaled(20, atLeast: 18), height: WatchDisplay.scaled(20, atLeast: 18))
            .background(WatchTheme.accent.opacity(0.92), in: .circle)
            .padding(5)
            .accessibilityHidden(true)
    }
}

struct ExpandedMapWatchView: View {
    var route: [CLLocationCoordinate2D] = []
    var breadcrumb: [CLLocationCoordinate2D] = []
    var waypoints: [WatchWaypoint] = []
    var position: CLLocationCoordinate2D?
    var title: String

    @Environment(WatchScreenSettings.self) private var settings

    /// Zoom is driven as an exponent so every detent changes the ground shown
    /// by the same percentage. Driven linearly in metres a detent is half the
    /// view up close and invisible when zoomed out.
    @State private var zoomExponent: Double = Self.defaultExponent
    @FocusState private var isCrownFocused: Bool

    private static let minimumSpanMetres: Double = 120
    private static let maximumSpanMetres: Double = 24_000
    private static let minimumExponent: Double = log2(minimumSpanMetres)
    private static let maximumExponent: Double = log2(maximumSpanMetres)
    private static let defaultExponent: Double = log2(1_200)
    private static let exponentStep: Double = 0.25
    private static let buttonStep: Double = 0.5

    private var zoomMetres: Double { pow(2, zoomExponent) }


    var body: some View {
        ZStack {
            // The Crown listens on the map and on nothing else, and the map
            // never changes shape, so nothing appearing over it can cost it
            // the focus the Crown follows.
            map
                .ignoresSafeArea()
                .focusable(true)
                .focused($isCrownFocused)
                .digitalCrownRotation(
                    $zoomExponent,
                    from: Self.minimumExponent,
                    through: Self.maximumExponent,
                    by: Self.exponentStep,
                    sensitivity: .high,
                    isContinuous: false,
                    isHapticFeedbackEnabled: true
                )

            Color.clear
                .allowsHitTesting(false)
                .overlay(alignment: .topLeading) { scaleChip }
                .overlay(alignment: .bottomTrailing) { zoomControls }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { isCrownFocused = true }
    }

    private var map: some View {
        WatchPreviewMap(
            route: route,
            breadcrumb: breadcrumb,
            waypoints: waypoints,
            position: position,
            // No centre on purpose. The map frames what is drawn on it once,
            // and from then on a zoom changes only the scale — handing it a
            // centre would tug the ground back from wherever the athlete had
            // dragged it every time they turned the Crown.
            centre: nil,
            spanMetres: zoomMetres,
            routeTint: settings.routeTrailColor.color,
            breadcrumbTint: settings.breadcrumbTrailColor.color,
            usesNightSheet: settings.prefersHybridMap,
            allowsPan: true
        )
    }

    /// Says what the Crown just did in ground covered, not a zoom number.
    private var scaleChip: some View {
        Text("\(WatchFormat.shortDistance(zoomMetres)) \(WatchFormat.shortDistanceUnit(zoomMetres)) across")
            .font(.watch(9, weight: .bold))
            .foregroundStyle(WatchTheme.canvas)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(WatchTheme.accent, in: .capsule)
            .padding(4)
    }

    /// Zoom that works whoever holds the Crown, so the map can always be read.
    private var zoomControls: some View {
        VStack(spacing: 0) {
            zoomButton(symbol: "plus", label: "Zoom in", isEnabled: zoomExponent > Self.minimumExponent) {
                stepZoom(-1)
            }
            zoomButton(symbol: "minus", label: "Zoom out", isEnabled: zoomExponent < Self.maximumExponent) {
                stepZoom(1)
            }
        }
        .padding(2)
    }

    private func stepZoom(_ direction: Double) {
        let next: Double = zoomExponent + direction * Self.buttonStep
        zoomExponent = min(max(next, Self.minimumExponent), Self.maximumExponent)
        WKInterfaceDevice.current().play(.click)
    }

    private func zoomButton(
        symbol: String,
        label: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.watch(11, weight: .bold))
                .foregroundStyle(WatchTheme.textPrimary.opacity(isEnabled ? 1 : 0.3))
                .frame(width: WatchDisplay.scaled(26, atLeast: 24), height: WatchDisplay.scaled(26, atLeast: 24))
                .background(WatchTheme.surface.opacity(0.9), in: .circle)
                .padding(5)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        // Every focusable view over the map is a rival for the Crown the map
        // needs. Focus governs the Crown, not the finger, so these stay fully
        // tappable while leaving exactly one focus candidate on the page.
        .focusable(false)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }
}
