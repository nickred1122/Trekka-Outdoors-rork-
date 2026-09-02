import SwiftUI
import WatchKit

/// The live workout screen.
///
/// Vertical swipes move through the data pages the athlete configured. The map
/// is always one swipe to the left, whatever page you are on, and the controls
/// are one swipe to the right or a long press — so pausing never depends on
/// finding the right page in a carousel while running downhill.
struct WorkoutPagerView: View {
    let sport: WatchSport
    let route: WatchRoute?

    @Environment(WorkoutEngine.self) private var engine
    @Environment(WatchScreenSettings.self) private var settings
    @Environment(BreadcrumbStore.self) private var breadcrumbs

    @State private var selection = 0
    @State private var editingScreen: WatchScreen?
    @State private var showsEndConfirmation = false
    /// The map, swiped in from the right-hand side.
    @State private var showsMap = false
    /// Raised while the map has the athlete's finger, so this view stops
    /// competing for the same drag.
    @State private var isExploringMap = false
    /// Pause, lap and stop, swiped in from the left or long-pressed.
    @State private var showsMenu = false

    /// The data pages, without the map: the map has its own gesture now, so
    /// leaving it in the vertical stack too would put it in two places at once.
    private var screens: [WatchScreen] {
        let active = settings.activeScreens(for: sport, hasRoute: route != nil)
            .filter { $0.kind != .map }
        // Map redraws dominate the power budget, so the compass steps aside
        // while power saver is on.
        guard engine.isPowerSaving else { return active }
        return active.filter { $0.kind != .compass }
    }

    /// The map is only worth offering when a fix can place you on it.
    private var mapIsAvailable: Bool {
        sport.usesGPS && !engine.isPowerSaving
    }

    var body: some View {
        ZStack {
            WatchTheme.canvas.ignoresSafeArea()

            switch engine.phase {
            case .countdown(let value):
                countdown(value)
            case .acquiring:
                acquiring
            case .finished:
                SummaryView(sport: sport, metrics: engine.metrics, laps: engine.laps) {
                    engine.reset()
                }
            default:
                workout
            }
        }
        .navigationBarBackButtonHidden(true)
        .sheet(item: $editingScreen) { screen in
            NavigationStack {
                ScreenDetailEditorView(sport: sport, screenID: screen.id)
            }
        }
        .confirmationDialog(
            "Stop this workout?",
            isPresented: $showsEndConfirmation,
            titleVisibility: .visible
        ) {
            Button("Save workout") { engine.end() }
            Button("Discard", role: .destructive) { engine.discard() }
            Button("Keep going", role: .cancel) {}
        }
    }

    // MARK: - Starting

    private func countdown(_ value: Int) -> some View {
        VStack(spacing: 6) {
            Text("\(value)")
                .font(.metric(64, weight: .bold))
                .foregroundStyle(sport.tint)
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy, value: value)
            Text(sport.title)
                .font(.watch(12, weight: .semibold))
                .foregroundStyle(WatchTheme.textSecondary)
            if let route {
                Text(route.name)
                    .font(.watch(10))
                    .foregroundStyle(WatchTheme.accent)
                    .lineLimit(1)
            }
        }
    }

    /// Precise start: the sensors are running, the clock is not, and the screen
    /// says exactly what it is waiting for rather than pretending to record.
    private var acquiring: some View {
        VStack(spacing: WatchDisplay.spacing(8)) {
            Image(systemName: "location.circle")
                .font(.watch(26, weight: .semibold))
                .foregroundStyle(sport.tint)
                .symbolEffect(.pulse)

            VStack(spacing: 2) {
                Text("Waiting for a precise fix")
                    .font(.watch(11, weight: .semibold))
                    .foregroundStyle(WatchTheme.textPrimary)
                    .multilineTextAlignment(.center)
                Text(engine.acquiringText)
                    .font(.metric(10, weight: .semibold))
                    .foregroundStyle(WatchTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            GPSStrengthBadge(bars: engine.gpsBars, isLive: engine.isGPSLive)

            Button {
                engine.startWithoutFix()
            } label: {
                Text("Start now")
                    .font(.watch(12, weight: .bold))
                    .foregroundStyle(WatchTheme.canvas)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(sport.tint, in: .capsule)
            }
            .buttonStyle(.plain)

            Button("Cancel") { engine.discard() }
                .font(.watch(10, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(WatchTheme.textSecondary)
        }
        .padding(.horizontal, WatchDisplay.spacing(10))
    }

    // MARK: - Running

    private var workout: some View {
        ZStack {
            // Taken out of the hierarchy rather than merely hidden. A vertical
            // page TabView owns the Digital Crown for its own scrolling, and it
            // keeps owning it while invisible — hiding it and refusing its
            // touches is not enough. Left in place it swallowed every Crown turn
            // meant for the map, which on the wrist reads as zoom being dead.
            if !showsMap {
                pager
                    .allowsHitTesting(!showsMenu)
            }

            if showsMap {
                mapLayer
                    .transition(.move(edge: .trailing))
            }

            if showsMenu {
                menuLayer
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .overlay(alignment: .top) { if !showsMenu { statusBar } }
        .overlay(alignment: .bottom) { lapBanner }
        .overlay(alignment: .center) { powerBanner }
        .overlay(alignment: .top) { if !showsMenu { navigationBanner } }
        .overlay(alignment: .bottom) { startBanner }
        // Horizontal swipes are the app's own navigation; the vertical page
        // carousel keeps the vertical ones. While the map is being explored the
        // drag belongs to the map alone, or every pan would turn the page too.
        .simultaneousGesture(sideSwipe, including: isExploringMap ? .none : .all)
        // The press-and-hold shortcut to the controls has to stand down over the
        // map. It was racing every tap on the map's own buttons, so a quick tap
        // did nothing and only a deliberate hold ever registered — and the map
        // page already has visible buttons for everything it does.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45).onEnded { _ in openMenu() },
            including: showsMap ? .none : .all
        )
        .animation(.snappy(duration: 0.28), value: showsMap)
        .animation(.snappy(duration: 0.24), value: showsMenu)
        .animation(.snappy, value: engine.isPowerSaving)
        .animation(.snappy, value: engine.navigationBanner)
        .animation(.snappy, value: engine.startBanner)
    }

    /// Left for the map, right for the controls, in both directions.
    private var sideSwipe: some Gesture {
        DragGesture(minimumDistance: 26)
            .onEnded { value in
                // Vertical intent belongs to the page carousel underneath.
                guard abs(value.translation.width) > abs(value.translation.height) * 1.4 else { return }

                if value.translation.width < 0 {
                    // Swipe left: into the map, or back out of the controls.
                    if showsMenu {
                        closeMenu()
                    } else if mapIsAvailable, !showsMap {
                        openMap()
                    }
                } else {
                    // Swipe right: out of the map, then on into the controls.
                    if showsMap {
                        closeMap()
                    } else if !showsMenu {
                        openMenu()
                    }
                }
            }
    }

    private func openMap() {
        showsMenu = false
        showsMap = true
        WKInterfaceDevice.current().play(.click)
    }

    private func closeMap() {
        isExploringMap = false
        showsMap = false
        WKInterfaceDevice.current().play(.click)
    }

    private func openMenu() {
        guard !showsMenu else { return }
        showsMenu = true
        WKInterfaceDevice.current().play(.start)
    }

    private func closeMenu() {
        showsMenu = false
        WKInterfaceDevice.current().play(.click)
    }

    private var pager: some View {
        TabView(selection: $selection) {
            ForEach(Array(screens.enumerated()), id: \.element.id) { index, screen in
                page(for: screen)
                    .tag(index)
            }
        }
        .tabViewStyle(.verticalPage)
    }

    @ViewBuilder
    private var mapLayer: some View {
        MapPageView(
            route: route,
            track: engine.track,
            coordinate: engine.currentCoordinate,
            metrics: engine.metrics,
            usesNightSheet: settings.prefersHybridMap,
            breadcrumb: breadcrumbs.activeCrumbs.map(\.coordinate),
            reroute: engine.reroute,
            heading: engine.heading,
            routeTint: settings.routeTrailColor.color,
            trailTint: settings.breadcrumbTrailColor.color,
            topInset: statusBarInset,
            isExploring: $isExploringMap
        )
        .overlay(alignment: .bottomLeading) {
            // The way back, for anyone who has not found the swipe yet.
            Button(action: closeMap) {
                Image(systemName: "chevron.right")
                    .font(.watch(11, weight: .bold))
                    .foregroundStyle(WatchTheme.textPrimary)
                    .frame(width: WatchDisplay.scaled(26, atLeast: 24), height: WatchDisplay.scaled(26, atLeast: 24))
                    .background(WatchTheme.surface.opacity(0.9), in: .circle)
            }
            .buttonStyle(.plain)
            // Out of the focus system, like the map's own controls: a Button
            // over the map is a rival for the Crown the map needs.
            .focusable(false)
            .padding(6)
            .accessibilityLabel("Back to metrics")
        }
    }

    /// Pause, lap and stop, reachable from every page by swipe or long press.
    private var menuLayer: some View {
        ZStack {
            WatchTheme.canvas.opacity(0.94).ignoresSafeArea()
            ControlsPageView(
                engine: engine,
                sport: sport,
                onCustomize: {
                    showsMenu = false
                    editingScreen = screens.first { $0.kind == .data }
                },
                onEnd: {
                    showsMenu = false
                    // Asking is the default because ending cannot be undone.
                    // An athlete who has turned the question off has said they
                    // would rather have the tap, so it saves and stops there.
                    if settings.confirmsWorkoutEnd {
                        showsEndConfirmation = true
                    } else {
                        engine.end()
                    }
                },
                onDismiss: closeMenu
            )
        }
    }

    @ViewBuilder
    private func page(for screen: WatchScreen) -> some View {
        Group {
            switch screen.kind {
            case .data:
                DataPageView(
                    screen: screen,
                    metrics: engine.metrics,
                    sport: sport,
                    onCustomize: { editingScreen = screen }
                )
                .padding(.horizontal, WatchDisplay.spacing(6))
                .padding(.top, statusBarInset)
            case .map:
                // The map has its own gesture; it is never a carousel page.
                EmptyView()
            case .elevation:
                ElevationPageView(route: route, track: engine.track, metrics: engine.metrics)
                    .padding(.horizontal, WatchDisplay.spacing(6))
                    .padding(.top, statusBarInset)
            case .climb:
                ClimbPageView(route: route, metrics: engine.metrics)
                    .padding(.horizontal, WatchDisplay.spacing(6))
                    .padding(.top, statusBarInset)
            case .upAhead:
                UpAheadPageView(route: route, metrics: engine.metrics)
                    .padding(.horizontal, WatchDisplay.spacing(4))
                    .padding(.top, statusBarInset)
            case .zones:
                ZonePageView(metrics: engine.metrics)
                    .padding(.horizontal, WatchDisplay.spacing(6))
                    .padding(.top, statusBarInset)
            case .laps:
                LapsPageView(laps: engine.laps, metrics: engine.metrics, usesPace: sport.usesPace)
                    .padding(.horizontal, WatchDisplay.spacing(4))
                    .padding(.top, statusBarInset)
            case .compass:
                CompassPageView(heading: engine.heading, metrics: engine.metrics, route: route)
                    .padding(.horizontal, WatchDisplay.spacing(6))
                    .padding(.top, statusBarInset)
            }
        }
    }

    /// Room the pages leave at the top.
    ///
    /// The status strip no longer sits in this space — it has moved up into the
    /// watch's own clock row — so the pages start immediately below the clock
    /// instead of below a strip that was itself below the clock. That band of
    /// empty black above the first metric was this inset.
    private var statusBarInset: CGFloat { WatchDisplay.scaled(3, atLeast: 2) }

    private var statusBar: some View {
        WorkoutStatusStrip(
            isPaused: engine.phase == .paused,
            isAutoPaused: engine.isAutoPaused,
            tint: sport.tint,
            usesGPS: sport.usesGPS,
            gpsBars: engine.gpsBars,
            isGPSLive: engine.isGPSLive,
            batteryPercent: engine.batteryPercent,
            isPowerSaving: engine.isPowerSaving,
            showsBadges: settings.showsStatusBadges
        )
        // Lifted into the clock's own row. The strip keeps to the left and the
        // watch's clock keeps to the right, so the two share one line rather
        // than the workout losing a whole band of screen to the gap between
        // them. Everything below then moves up with it.
        .padding(.top, WatchDisplay.scaled(4, atLeast: 3))
        .ignoresSafeArea(.container, edges: .top)
    }

    /// Confirms a power-mode change, including one the watch armed by itself.
    @ViewBuilder
    private var powerBanner: some View {
        if let banner = engine.powerBanner {
            VStack(spacing: 2) {
                Image(systemName: engine.isPowerSaving ? "leaf.fill" : "bolt.fill")
                    .font(.watch(16, weight: .bold))
                Text(banner)
                    .font(.watch(10, weight: .bold))
                    .multilineTextAlignment(.center)
                Text(engine.batteryLabel + " left")
                    .font(.metric(9, weight: .semibold))
                    .opacity(0.7)
            }
            .foregroundStyle(WatchTheme.canvas)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(engine.isPowerSaving ? WatchTheme.positive : WatchTheme.accent, in: .rect(cornerRadius: 14))
            .transition(.scale.combined(with: .opacity))
        }
    }

    /// Course callouts: waypoint reached, off course, back on route. Sits at the
    /// top so it reads without covering the metric the athlete is watching.
    @ViewBuilder
    private var navigationBanner: some View {
        if let banner = engine.navigationBanner {
            let isWarning = engine.metrics.isOffCourse
            Label(banner, systemImage: isWarning ? "exclamationmark.triangle.fill" : "flag.fill")
                .font(.watch(11, weight: .bold))
                .foregroundStyle(WatchTheme.canvas)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isWarning ? WatchTheme.danger : WatchTheme.highlight, in: .capsule)
                .padding(.top, statusBarInset)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    /// Says how the workout began, for the seconds just after it does.
    ///
    /// Precise start used to hand back a screen that had flashed something
    /// unreadable and then vanished. This is the other half of that sentence:
    /// the wait is over, and here is the accuracy it waited for.
    @ViewBuilder
    private var startBanner: some View {
        if let banner = engine.startBanner {
            Label(banner, systemImage: engine.startedWithPreciseFix ? "location.fill" : "location.slash.fill")
                .font(.watch(10, weight: .bold))
                .foregroundStyle(WatchTheme.canvas)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    engine.startedWithPreciseFix ? WatchTheme.positive : WatchTheme.highlight,
                    in: .capsule
                )
                .padding(.bottom, 6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityLabel(banner)
        }
    }

    @ViewBuilder
    private var lapBanner: some View {
        if let banner = engine.lastLapBanner {
            Text(banner)
                .font(.watch(11, weight: .bold))
                .foregroundStyle(WatchTheme.canvas)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(WatchTheme.highlight, in: .capsule)
                .padding(.bottom, 6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// Bearing page for navigation-heavy sports.
struct CompassPageView: View {
    let heading: Double
    let metrics: LiveMetrics
    let route: WatchRoute?

    /// Whether a direction has actually been measured, rather than the zero a
    /// fresh reading starts at — which would point the needle due north and
    /// look entirely convincing.
    private var hasHeading: Bool { metrics.hasHeading }

    var body: some View {
        VStack(spacing: WatchDisplay.spacing(8)) {
            ZStack {
                Circle()
                    .stroke(WatchTheme.surfaceRaised, lineWidth: WatchDisplay.scaled(6, atLeast: 4))
                ForEach(0..<4, id: \.self) { index in
                    Text(["N", "E", "S", "W"][index])
                        .font(.watch(9, weight: .bold))
                        .foregroundStyle(index == 0 ? WatchTheme.accent : WatchTheme.textSecondary)
                        .offset(y: -dialDiameter * 0.405)
                        .rotationEffect(.degrees(Double(index) * 90))
                }
                // The dial has to keep turning the short way as the athlete
                // walks through north, where the heading jumps 359 -> 1.
                .compassRotation(degrees: hasHeading ? -heading : 0)

                Image(systemName: "location.north.fill")
                    .font(.watch(20, weight: .bold))
                    .foregroundStyle(hasHeading ? WatchTheme.accent : WatchTheme.textSecondary)
                    .opacity(hasHeading ? 1 : 0.4)
            }
            .frame(width: dialDiameter, height: dialDiameter)

            // The compass point first, because it is what gets said out loud and
            // what gets matched against a paper map. The degrees are the detail
            // underneath it, not the headline.
            if hasHeading {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(WatchFormat.cardinal(heading))
                        .font(.metric(22, weight: .bold))
                        .foregroundStyle(WatchTheme.accent)
                    Text("\(WatchFormat.integer(heading))°")
                        .font(.metric(16, weight: .semibold))
                        .foregroundStyle(WatchTheme.textPrimary)
                }
            } else {
                // No invented north. A compass that guesses is worse than one
                // that admits it cannot read.
                Text("No compass signal")
                    .font(.watch(10, weight: .semibold))
                    .foregroundStyle(WatchTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            if route != nil {
                HStack(spacing: WatchDisplay.spacing(8)) {
                    MetricCell(field: .distanceToWaypoint, value: WatchFormat.shortDistance(metrics.distanceToWaypoint), size: .compact, tint: WatchTheme.accent)
                    MetricCell(field: .nextWaypoint, value: metrics.nextWaypointName, size: .compact)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var dialDiameter: CGFloat { WatchDisplay.scaled(84, atLeast: 62) }
}
