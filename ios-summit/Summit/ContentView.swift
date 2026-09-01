import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    @State private var store = RouteStore()
    @State private var health = HealthService()
    @State private var watchSync = WatchSyncService()
    @State private var dashboardSettings = DashboardSettings()
    @State private var watchLayout = WatchLayoutStore()
    @State private var appearance = AppearanceSettings()
    @State private var units = UnitSettings()
    @State private var mapPacks = MapPackStore()
    @State private var watchLink = WatchLink.shared

    @State private var selectedTab: AppTab = .today
    @State private var todayPath = NavigationPath()
    @State private var routesPath = NavigationPath()
    @State private var calendarPath = NavigationPath()
    @State private var activitiesPath = NavigationPath()
    @State private var settingsPath = NavigationPath()

    @State private var showsWorkout = false
    @State private var pendingWorkoutRoute: PlannedRoute?

    /// The bar stays put on every root screen and steps aside for pushed detail.
    private var showsTabBar: Bool {
        switch selectedTab {
        case .today: todayPath.isEmpty
        case .routes: routesPath.isEmpty
        case .calendar: calendarPath.isEmpty
        case .activities: activitiesPath.isEmpty
        case .settings: settingsPath.isEmpty
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.canvas.ignoresSafeArea()

            TabScreen(tab: .today, selection: selectedTab) { todayScreen }
            TabScreen(tab: .routes, selection: selectedTab) { routesScreen }
            TabScreen(tab: .calendar, selection: selectedTab) { calendarScreen }
            TabScreen(tab: .activities, selection: selectedTab) { activitiesScreen }
            TabScreen(tab: .settings, selection: selectedTab) { settingsScreen }

            if showsTabBar {
                VStack(spacing: 0) {
                    TabBarFade()
                    SummitTabBar(selection: $selectedTab, onReselect: popToRoot)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // Units are converted deep inside child views and model helpers, so no
        // single value can be observed to catch a change. Rebuilding the screens
        // when the setting flips is what makes it actually land everywhere. The
        // navigation paths live in this view's own state, outside the rebuilt
        // subtree, so nobody gets thrown back to a root screen.
        .reformatsOnUnitChange(units.system)
        .animation(.snappy(duration: 0.26), value: showsTabBar)
        .tint(Theme.accent)
        .environment(store)
        .environment(health)
        .environment(watchSync)
        .environment(dashboardSettings)
        .environment(watchLayout)
        .environment(appearance)
        .environment(units)
        .environment(mapPacks)
        .environment(\.unitSystem, units.system)
        .preferredColorScheme(appearance.colorScheme)
        .fullScreenCover(isPresented: $showsWorkout) {
            LiveWorkoutView(initialRoute: pendingWorkoutRoute)
                .environment(store)
                .environment(health)
                .environment(appearance)
                .environment(units)
                .environment(mapPacks)
                .environment(\.unitSystem, units.system)
                .reformatsOnUnitChange(units.system)
        }
        .task {
            watchLink.activate()

            // The watch reads its units out of the layout document, so the two
            // devices are brought into line at launch rather than drifting until
            // somebody happens to open the designer.
            if watchLayout.unitSystem != units.system {
                watchLayout.unitSystem = units.system
            }

            // Watch workouts arrive here and join the phone's activity history.
            watchLink.onWorkout = { record in
                store.add(record)
                pushDashboard()
            }
            // Dashboard rearranged on the wrist.
            watchLink.onPreferences = { preferences in
                dashboardSettings.apply(preferences)
                pushDashboard()
            }
            // Workout screens or behaviour edited on the wrist.
            watchLink.onWatchSettings = { data in
                watchLayout.applyIncoming(data)
            }

            // Access is never requested at launch — but if it was granted in an
            // earlier session, the data loads straight away instead of asking
            // the user to connect Apple Health all over again.
            await health.resume()

            // A route's "has an offline map" flag travels to the watch, so it
            // is kept level with the packs actually on disk rather than being
            // set once and trusted.
            mapPacks.onRouteMapChanged = { routeID, hasMap in
                store.setOfflineDownloaded(hasMap, routeID: routeID)
            }
            mapPacks.reconcile(with: store.routes)

            watchSync.pushLibrary(store: store)
            pushEverything()

            // Keep the ground around regular trailheads ready, so an unplanned
            // outing from a familiar start already has its map. Done after the
            // launch work above so it never competes with it.
            mapPacks.refreshHomeAreas(from: store.activities)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            pushEverything()
            // Health sharing can be changed in the Health app while this app is
            // in the background, so the state is re-read on the way back in.
            Task { await health.resume() }
        }
        .onChange(of: dashboardSettings.preferencesTransfer) { _, _ in
            pushDashboard()
        }
        .onChange(of: store.activities.count) { _, _ in
            pushDashboard()
        }
    }

    // MARK: - Screens

    private var todayScreen: some View {
        NavigationStack(path: $todayPath) {
            TodayView(pendingWorkoutRoute: $pendingWorkoutRoute, showsWorkout: $showsWorkout)
                .navigationTitle("Today")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Theme.canvas, for: .navigationBar)
                .navigationDestination(for: RouteDestination.self) { routeDestinationView($0) }
                .navigationDestination(for: DashboardDestination.self) { dashboardDestinationView($0) }
                .navigationDestination(for: ActivityRecord.self) { ActivityDetailView(activity: $0) }
        }
    }

    private var routesScreen: some View {
        NavigationStack(path: $routesPath) {
            RoutesView(path: $routesPath)
                .navigationTitle("Routes & Maps")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Theme.canvas, for: .navigationBar)
                .navigationDestination(for: RouteDestination.self) { routeDestinationView($0) }
        }
    }

    private var calendarScreen: some View {
        NavigationStack(path: $calendarPath) {
            CalendarView(path: $calendarPath)
                .navigationTitle("Calendar")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Theme.canvas, for: .navigationBar)
                .navigationDestination(for: ActivityRecord.self) { ActivityDetailView(activity: $0) }
        }
    }

    private var activitiesScreen: some View {
        NavigationStack(path: $activitiesPath) {
            ActivitiesView(path: $activitiesPath)
                .navigationTitle("Activities")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Theme.canvas, for: .navigationBar)
                .navigationDestination(for: ActivityRecord.self) { ActivityDetailView(activity: $0) }
                .navigationDestination(for: ActivitiesDestination.self) { destination in
                    switch destination {
                    case .records:
                        RecordsView(path: $activitiesPath)
                    }
                }
        }
    }

    private var settingsScreen: some View {
        NavigationStack(path: $settingsPath) {
            SettingsView(path: $settingsPath)
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Theme.canvas, for: .navigationBar)
                .navigationDestination(for: SettingsDestination.self) { destination in
                    switch destination {
                    case .watch:
                        WatchSetupView()
                    case .backup:
                        BackupView()
                    }
                }
        }
    }

    // MARK: - Navigation helpers

    /// Tapping the active tab again walks back to that tab's root.
    private func popToRoot(_ tab: AppTab) {
        withAnimation(.snappy(duration: 0.26)) {
            switch tab {
            case .today: todayPath = NavigationPath()
            case .routes: routesPath = NavigationPath()
            case .calendar: calendarPath = NavigationPath()
            case .activities: activitiesPath = NavigationPath()
            case .settings: settingsPath = NavigationPath()
            }
        }
    }

    /// Mirrors the Today dashboard — layout, readings, recovery and history — to the watch.
    private func pushDashboard() {
        watchLink.sendDashboard(
            WatchSyncPayloads.dashboard(settings: dashboardSettings, health: health, store: store)
        )
    }

    private func pushEverything() {
        pushDashboard()
        watchLayout.pushSilently()
    }

    @ViewBuilder
    private func dashboardDestinationView(_ destination: DashboardDestination) -> some View {
        switch destination {
        case .metric(let metric):
            MetricDetailView(metric: metric)
        case .readiness:
            ReadinessDetailView()
        case .zones:
            ZonesDetailView()
        case .trainingLoad:
            TrainingLoadView()
        }
    }

    @ViewBuilder
    private func routeDestinationView(_ destination: RouteDestination) -> some View {
        switch destination {
        case .route(let id):
            RouteDetailView(
                routeID: id,
                pendingWorkoutRoute: $pendingWorkoutRoute,
                showsWorkout: $showsWorkout
            )
        case .maps:
            MapLibraryView()
        }
    }
}

/// Keeps each tab's navigation state alive once visited, without building screens
/// the user has never opened.
private struct TabScreen<Content: View>: View {
    let tab: AppTab
    let selection: AppTab
    @ViewBuilder var content: () -> Content

    @State private var hasLoaded = false

    private var isActive: Bool { tab == selection }

    var body: some View {
        ZStack {
            if hasLoaded {
                content()
            }
        }
        .opacity(isActive ? 1 : 0)
        .allowsHitTesting(isActive)
        .accessibilityHidden(!isActive)
        .onAppear { if isActive { hasLoaded = true } }
        .onChange(of: isActive) { _, active in
            if active { hasLoaded = true }
        }
    }
}

#Preview {
    ContentView()
}
