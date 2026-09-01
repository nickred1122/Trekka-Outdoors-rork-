import SwiftUI
import CoreLocation
import WatchKit

/// Live map page: planned route, breadcrumb of where you have actually been,
/// waypoints, and an off-course warning. The Digital Crown zooms.
///
/// The map is Trekka's own — OpenStreetMap ground traced with our contour lines
/// and our line weights — because a navigation map on a wrist has to keep
/// working when the signal and the phone are both gone.
struct MapPageView: View {
    let route: WatchRoute?
    let track: [WatchTrackPoint]
    let coordinate: CLLocationCoordinate2D?
    let metrics: LiveMetrics
    /// Draws the map on a dark sheet instead of cream paper.
    var usesNightSheet: Bool = false
    var breadcrumb: [CLLocationCoordinate2D] = []
    /// The way back to the course, present only while off route.
    var reroute: RerouteAdvice?
    var heading: Double = 0
    /// Line colours chosen by the athlete.
    var routeTint: Color = WatchTheme.accent
    var trailTint: Color = WatchTheme.highlight
    /// Room already taken at the top by the workout's status strip, so this
    /// page's own chips sit under it instead of on top of it.
    var topInset: CGFloat = 0

    /// Panning is off until asked for, because a map that swallows every swipe
    /// traps you on this page. Off, the map follows you and swipes change page.
    ///
    /// Owned by the pager, which has to stop its own side-swipe from firing at
    /// the same time as a pan.
    @Binding var isExploring: Bool

    /// The Crown drives an exponent, not metres directly.
    ///
    /// Zoom is multiplicative: going 900 m → 1,800 m has to cost the same wrist
    /// movement as 200 m → 400 m. Driven linearly in metres, a detent worth 60 m
    /// is half the view at the close end and a rounding error at the wide end —
    /// the athlete turns and turns and the map barely moves, which is exactly
    /// what "zoom doesn't work" feels like. Each detent here is a fixed
    /// percentage instead, so the whole range is about fifty comfortable steps.
    @State private var zoomExponent: Double = Self.defaultExponent
    @State private var isFollowing = true
    /// Turns the map to your heading instead of holding north at the top.
    @State private var rotatesWithHeading = false

    /// The Crown only turns the thing that holds focus, and the workout's page
    /// carousel holds it until something takes it away. Without claiming it here
    /// the map was being turned past — the Crown scrolled the pager underneath
    /// instead of zooming, which reads on the wrist as zoom being broken.
    @FocusState private var isCrownFocused: Bool
    /// The map's own focus scope.
    ///
    /// Writing `true` into a `@FocusState` is a request, and watchOS declines it
    /// whenever something else already holds system focus — silently, with no
    /// way to tell from the app that it was refused. Three attempts at claiming
    /// the Crown that way all failed on the wrist for exactly this reason. A
    /// scope plus `resetFocus` is the imperative form: it tells watchOS to run
    /// focus again inside this region and hand it to the preferred view, rather
    /// than politely asking for it.
    @Namespace private var crownScope
    @Environment(\.resetFocus) private var resetFocus
    /// The running claim, so a fresh one replaces it rather than racing it.
    @State private var crownClaim: Task<Void, Never>?
    /// Bumped on every Crown step, so the scale chip can appear while zooming
    /// and stand down again shortly after it stops.
    @State private var zoomToken = 0
    @State private var showsScaleChip = false

    /// Closest useful look: a street's width across the screen.
    private static let minimumSpanMetres: Double = 120
    /// Widest: enough ground to see a whole day's route.
    private static let maximumSpanMetres: Double = 24_000
    private static let minimumExponent: Double = log2(minimumSpanMetres)
    private static let maximumExponent: Double = log2(maximumSpanMetres)
    private static let defaultExponent: Double = log2(900)
    /// About 9% of ground per detent — fine enough to feel continuous, coarse
    /// enough to cross the whole range without winding the Crown all day.
    private static let exponentStep: Double = 0.125
    /// One tap of the on-screen zoom: about 40% of ground, so the whole range is
    /// a dozen or so taps rather than fifty.
    private static let buttonStep: Double = 0.5

    private var zoomMetres: Double { pow(2, zoomExponent) }

    private var trackCoordinates: [CLLocationCoordinate2D] {
        track.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    /// Breadcrumbs come from the trail store when it has them, and fall back to
    /// the workout's own track so the page is never blank.
    private var trailCoordinates: [CLLocationCoordinate2D] {
        breadcrumb.count > 1 ? breadcrumb : trackCoordinates
    }

    private var mapCentre: CLLocationCoordinate2D? {
        coordinate ?? route?.coordinates.first ?? trailCoordinates.first
    }

    private func stopExploring() {
        isExploring = false
        isFollowing = true
    }

    var body: some View {
        // The scope has to wrap the focusable view rather than being the
        // focusable view, so `resetFocus` has a region to re-run focus inside.
        mapPage
            .focusScope(crownScope)
            // Claimed as the map appears, and re-claimed after every tap: a
            // Button takes focus with it, and a map whose Crown works only until
            // you touch something is worse than one that never worked.
            .onAppear { claimCrown() }
            .onDisappear {
                crownClaim?.cancel()
                crownClaim = nil
            }
            .animation(.snappy, value: reroute)
            .animation(.snappy, value: isExploring)
            .animation(.snappy, value: rotatesWithHeading)
            .animation(.snappy(duration: 0.2), value: showsScaleChip)
    }

    private var mapPage: some View {
        // The map has to be a real sibling, not a background. A background sits
        // *behind* its content, and the clear layer in front of it was taking
        // every touch — so the pan gesture never saw a single drag and exploring
        // did nothing at all.
        ZStack {
            mapBody
                .ignoresSafeArea()

            // Chips and buttons keep to the safe area, where the curved corners
            // and the system clock cannot clip them. The layer holding them is
            // transparent to touches, so everywhere the athlete has not actually
            // aimed at a button still belongs to the map.
            Color.clear
                .allowsHitTesting(false)
                .overlay(alignment: .top) { topChip }
                .overlay(alignment: .bottom) { rerouteCard }
                .overlay(alignment: .leading) { zoomControls }
                .overlay(alignment: .bottomTrailing) { controls }
        }
        .focusable(true)
        .focused($isCrownFocused)
        // Names this as the view focus should land on whenever the scope is
        // reset — the map, never one of the buttons floating over it.
        .prefersDefaultFocus(true, in: crownScope)
        .digitalCrownRotation(
            $zoomExponent,
            from: Self.minimumExponent,
            through: Self.maximumExponent,
            by: Self.exponentStep,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: zoomExponent) { _, _ in
            zoomToken += 1
        }
        .task(id: zoomToken) {
            guard zoomToken > 0 else { return }
            showsScaleChip = true
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            showsScaleChip = false
        }
    }

    /// Takes the Crown for the map, and keeps asking until it sticks.
    ///
    /// One claim on appear is not enough. The map slides in over about 0.28s,
    /// and SwiftUI keeps the outgoing page carousel mounted for the whole of
    /// that transition — still holding the Crown. A claim made in that window is
    /// handed straight back, and by the time the carousel finally leaves,
    /// nothing is asking for the Crown any more: the map ends up focusable but
    /// unfocused, which is why panning worked and zooming did nothing.
    ///
    /// So the claim is re-asserted across a window that outlasts the transition.
    /// It stops early the moment focus is actually held, and the same retry
    /// covers focus lost to a button tap.
    /// Moves the scale by one deliberate step.
    ///
    /// Negative closes in, positive pulls back — the exponent counts ground
    /// covered, so zooming in makes it smaller.
    private func stepZoom(_ direction: Double) {
        let next: Double = zoomExponent + direction * Self.buttonStep
        zoomExponent = min(max(next, Self.minimumExponent), Self.maximumExponent)
        WKInterfaceDevice.current().play(.click)
        claimCrown()
    }

    /// Zoom that does not depend on who holds the Crown.
    ///
    /// The Crown is the better control when it works, but focus is invisible:
    /// when something else has quietly taken it there is nothing on screen to
    /// say so and no way for the athlete to get it back. These two always work,
    /// so the map can always be read.
    private var zoomControls: some View {
        VStack(spacing: 0) {
            circleButton(
                symbol: "plus",
                isOn: false,
                label: "Zoom in",
                isEnabled: zoomExponent > Self.minimumExponent
            ) {
                stepZoom(-1)
            }
            circleButton(
                symbol: "minus",
                isOn: false,
                label: "Zoom out",
                isEnabled: zoomExponent < Self.maximumExponent
            ) {
                stepZoom(1)
            }
        }
        .padding(2)
    }

    private func claimCrown() {
        crownClaim?.cancel()
        isCrownFocused = true
        resetFocus(in: crownScope)
        crownClaim = Task {
            for _ in 0..<8 {
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                if isCrownFocused { return }
                isCrownFocused = true
                // The part the previous attempts were missing: forcing focus to
                // be worked out again, rather than asking for it and being
                // quietly refused.
                resetFocus(in: crownScope)
            }
        }
    }

    private var mapBody: some View {
        TrekkaTopoMap(
            overlay: overlay,
            // Following hands the centre to the map; exploring lets go of it so
            // a drag stays where the athlete put it.
            centre: isFollowing ? mapCentre : nil,
            spanMetres: zoomMetres,
            heading: heading,
            // Turning with the athlete only makes sense while the map is still
            // following them; mid-pan it would spin the ground out from under
            // the finger.
            rotatesWithHeading: turnsWithAthlete,
            // Sitting low leaves more of the screen for the ground ahead than
            // for the ground already walked.
            centreAnchorY: turnsWithAthlete ? 0.66 : 0.5,
            allowsPan: isExploring,
            showsContours: true,
            // Names cost room and redraw time; the route and the ground matter
            // more mid-workout.
            showsPlaceLabels: false,
            showsAttribution: false,
            palette: usesNightSheet ? .nightSheet : .paperSheet,
            compact: true,
            labelFont: .watch(9, weight: .semibold),
            attributionFont: .watch(8)
        )
    }

    private var turnsWithAthlete: Bool {
        rotatesWithHeading && isFollowing && !isExploring
    }

    private var overlay: TopoOverlay {
        TopoOverlay(
            route: route?.coordinates ?? [],
            breadcrumb: trailCoordinates,
            guidance: reroute?.coordinates ?? [],
            waypoints: route?.waypoints.map(\.coordinate) ?? [],
            position: coordinate,
            routeTint: routeTint,
            trailTint: trailTint,
            guidanceTint: WatchTheme.danger
        )
    }

    /// One slot at the top, shared: the scale while zooming, otherwise whatever
    /// the athlete most needs to know about the course.
    @ViewBuilder
    private var topChip: some View {
        if showsScaleChip {
            scaleChip
        } else {
            navigationChip
        }
    }

    /// Says what the Crown just did, in ground covered rather than a zoom number.
    private var scaleChip: some View {
        Label(
            "\(WatchFormat.shortDistance(zoomMetres)) \(WatchFormat.shortDistanceUnit(zoomMetres)) across",
            systemImage: "arrow.left.and.right"
        )
        .font(.watch(10, weight: .bold))
        .foregroundStyle(WatchTheme.canvas)
        .lineLimit(1)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(WatchTheme.accent, in: .capsule)
        .padding(.top, topInset)
        .transition(.opacity)
    }

    @ViewBuilder
    private var navigationChip: some View {
        if metrics.offCourseMetres > 45 {
            Label("Off course \(WatchFormat.integer(metrics.offCourseMetres)) m", systemImage: "exclamationmark.triangle.fill")
                .font(.watch(10, weight: .bold))
                .foregroundStyle(WatchTheme.canvas)
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(WatchTheme.danger, in: .capsule)
                .padding(.top, topInset)
        } else if isExploring {
            // Says why swiping stopped working, and how to get it back.
            Label("Panning · tap \u{2713} to page", systemImage: "hand.draw.fill")
                .font(.watch(9, weight: .bold))
                .foregroundStyle(WatchTheme.canvas)
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(WatchTheme.highlight, in: .capsule)
                .padding(.top, topInset)
                .transition(.opacity)
        } else if route != nil {
            HStack(spacing: 4) {
                TrekkaIcon(.flag, size: WatchDisplay.scaled(9, atLeast: 8))
                Text(metrics.nextWaypointName)
                    .font(.watch(10, weight: .semibold))
                    .lineLimit(1)
                Text(WatchFormat.shortDistance(metrics.distanceToWaypoint))
                    .font(.metric(10, weight: .bold))
                    .foregroundStyle(WatchTheme.highlight)
            }
            .foregroundStyle(WatchTheme.textPrimary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(WatchTheme.canvas.opacity(0.82), in: .capsule)
            .padding(.top, topInset)
        }
    }

    /// The way back, once straying off the line is real rather than GPS drift.
    /// The arrow turns with you, so it works without looking at the map itself.
    @ViewBuilder
    private var rerouteCard: some View {
        if let reroute {
            HStack(spacing: 7) {
                Image(systemName: "arrow.up")
                    .font(.watch(14, weight: .black))
                    .rotationEffect(.degrees(reroute.relativeBearing(heading: heading)))
                    .animation(.snappy, value: reroute.bearing)
                    .animation(.snappy, value: heading)

                VStack(alignment: .leading, spacing: 1) {
                    Text(reroute.turnHint(heading: heading))
                        .font(.watch(11, weight: .bold))
                        .lineLimit(1)
                    Text("\(reroute.strategy.title) · \(WatchFormat.shortDistance(reroute.distance))")
                        .font(.watch(9, weight: .semibold))
                        .opacity(0.75)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(WatchTheme.canvas)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(WatchTheme.danger, in: .rect(cornerRadius: 11))
            .padding(.horizontal, 5)
            .padding(.bottom, 5)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(reroute.strategy.title). \(reroute.turnHint(heading: heading)). \(WatchFormat.shortDistance(reroute.distance)) away.")
        }
    }

    private var controls: some View {
        VStack(spacing: 0) {
            if !isExploring {
                // North-up or heading-up, the way a compass rose works on paper:
                // one tap, and the needle itself says which you are in.
                circleButton(
                    symbol: rotatesWithHeading ? "location.north.line.fill" : "location.north.line",
                    isOn: rotatesWithHeading,
                    label: rotatesWithHeading
                        ? "Map turns with you. Tap to keep north at the top."
                        : "North is at the top. Tap to turn the map with you."
                ) {
                    rotatesWithHeading.toggle()
                    isFollowing = true
                    claimCrown()
                }

                circleButton(
                    symbol: isFollowing ? "location.fill" : "location",
                    isOn: isFollowing,
                    label: "Recentre map"
                ) {
                    isFollowing = true
                    claimCrown()
                }
            }

            // Explore is deliberately a deliberate act: turning it on hands the
            // swipe to the map, turning it off gives it back to the pager and
            // snaps you back to where you actually are.
            circleButton(
                symbol: isExploring ? "checkmark" : "arrow.up.and.down.and.arrow.left.and.right",
                isOn: isExploring,
                tint: isExploring ? WatchTheme.positive : WatchTheme.surface,
                label: isExploring ? "Done exploring. Restores page swiping." : "Explore map. Lets you drag the map around."
            ) {
                if isExploring {
                    stopExploring()
                } else {
                    isExploring = true
                    isFollowing = false
                }
                claimCrown()
            }
        }
        .padding(2)
    }

    private func circleButton(
        symbol: String,
        isOn: Bool,
        tint: Color = WatchTheme.accent,
        label: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.watch(11, weight: .bold))
                .foregroundStyle(
                    isOn
                        ? WatchTheme.canvas
                        : WatchTheme.textPrimary.opacity(isEnabled ? 1 : 0.3)
                )
                .frame(width: WatchDisplay.scaled(26, atLeast: 24), height: WatchDisplay.scaled(26, atLeast: 24))
                .background(isOn ? tint : WatchTheme.surface.opacity(0.9), in: .circle)
                // The dot stays small so it does not cover the ground, but the
                // area that answers a finger is a good deal bigger than the dot.
                // A 26pt target on a wrist, over a map that also wants the touch,
                // is most of why these buttons felt dead.
                .padding(6)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }
}
