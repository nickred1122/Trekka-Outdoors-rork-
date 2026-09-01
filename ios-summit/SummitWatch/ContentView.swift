import SwiftUI

/// Where the Start tab can take you.
nonisolated enum WatchStartRoute: Hashable, Sendable {
    case sport(WatchSport)
    /// A specific course — a synced route, or a breadcrumb trail to backtrack.
    case preset(WatchRoute)
    case family(SportFamily)
    /// Every activity in one alphabetical list.
    case allSports
    case settings
}

/// The watch app's home: the same four surfaces as the iPhone app, one swipe apart.
struct ContentView: View {
    @Environment(WatchScreenSettings.self) private var settings
    @Environment(WatchRouteStore.self) private var routeStore
    @Environment(WatchDashboardStore.self) private var dashboard
    @Environment(WorkoutEngine.self) private var engine

    @State private var tab: HomeTab = .today
    @State private var todayPath = NavigationPath()
    @State private var startPath = NavigationPath()
    @State private var routesPath = NavigationPath()
    @State private var activitiesPath = NavigationPath()

    private enum HomeTab: Hashable {
        case today, start, routes, activities
    }

    var body: some View {
        // A workout owns the whole screen. Leaving the dashboard behind it means
        // a stray swipe lands on yesterday's numbers instead of today's pace,
        // and gives the pause button somewhere to hide.
        if engine.isWorkoutInProgress {
            WorkoutPagerView(sport: engine.sport, route: engine.route)
        } else {
            home
        }
    }

    private var home: some View {
        TabView(selection: $tab) {
            NavigationStack(path: $todayPath) {
                TodayWatchView { tab = .start }
                    .navigationDestination(for: TodayWatchRoute.self) { route in
                        todayDestination(route)
                    }
            }
            .tag(HomeTab.today)

            NavigationStack(path: $startPath) {
                startList
                    .navigationDestination(for: WatchStartRoute.self) { route in
                        startDestination(route)
                    }
            }
            .tag(HomeTab.start)

            NavigationStack(path: $routesPath) {
                RoutesWatchView { route in
                    routesPath.append(WatchStartRoute.preset(route))
                }
                .navigationDestination(for: WatchStartRoute.self) { route in
                    startDestination(route)
                }
            }
            .tag(HomeTab.routes)

            NavigationStack(path: $activitiesPath) {
                ActivitiesWatchView()
                    .navigationDestination(for: TodayWatchRoute.self) { route in
                        todayDestination(route)
                    }
            }
            .tag(HomeTab.activities)
        }
        .tabViewStyle(.page)
    }

    // MARK: - Start

    private var recents: [WatchSport] {
        let recent = settings.recentSports
        return recent.isEmpty ? [.trailRun, .ride, .hike] : recent
    }

    private var startList: some View {
        List {
            Section("Start") {
                ForEach(recents) { sport in
                    NavigationLink(value: WatchStartRoute.sport(sport)) {
                        sportRow(sport, isPrimary: true)
                    }
                }
            }

            Section("Activities") {
                ForEach(SportFamily.allCases) { family in
                    NavigationLink(value: WatchStartRoute.family(family)) {
                        SportFamilyRow(family: family)
                    }
                }
            }

            Section {
                NavigationLink(value: WatchStartRoute.allSports) {
                    Label("All activities", systemImage: "list.bullet")
                        .font(.system(size: 13, weight: .medium))
                }
                NavigationLink(value: WatchStartRoute.settings) {
                    Label("Settings", systemImage: "gearshape.fill")
                        .font(.system(size: 13, weight: .medium))
                }
            }
        }
        .navigationTitle("Trekka")
    }

    @ViewBuilder
    private func startDestination(_ route: WatchStartRoute) -> some View {
        switch route {
        case .sport(let sport):
            SportSetupView(sport: sport)
        case .preset(let route):
            SportSetupView(sport: route.sport, presetRoute: route)
        case .family(let family):
            SportFamilyListView(family: family)
        case .allSports:
            AllSportsListView()
        case .settings:
            WatchSettingsView()
        }
    }

    @ViewBuilder
    private func todayDestination(_ route: TodayWatchRoute) -> some View {
        switch route {
        case .metric(let rawValue):
            if let metric = WatchDashboardMetric(rawValue: rawValue) {
                MetricDetailWatchView(metric: metric)
            }
        case .readiness:
            ReadinessDetailWatchView()
        case .customize:
            DashboardEditorWatchView()
        case .activity(let id):
            if let activity = dashboard.activity(id: id) {
                ActivityDetailWatchView(activity: activity)
            } else {
                Text("Workout not available")
                    .font(.system(size: 12))
                    .foregroundStyle(WatchTheme.textSecondary)
            }
        case .settings:
            WatchSettingsView()
        }
    }

    private func sportRow(_ sport: WatchSport, isPrimary: Bool) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(sport.tint)
                .frame(width: 3, height: isPrimary ? 20 : 16)
            Text(sport.title)
                .font(.system(size: 13, weight: isPrimary ? .semibold : .medium))
                .foregroundStyle(WatchTheme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if settings.isCustomized(sport) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 8))
                    .foregroundStyle(WatchTheme.textSecondary)
            }
        }
        .padding(.vertical, 1)
    }
}

/// Global watch preferences that apply across every sport.
struct WatchSettingsView: View {
    @Environment(WatchScreenSettings.self) private var settings
    @Environment(WatchDashboardStore.self) private var dashboard

    var body: some View {
        List {
            Section("Laps") {
                Toggle(isOn: Binding(
                    get: { settings.isAutoLapEnabled },
                    set: { settings.isAutoLapEnabled = $0 }
                )) {
                    Text("Auto lap").font(.system(size: 12))
                }
                .tint(WatchTheme.accent)

                Stepper(
                    value: Binding(
                        get: { settings.autoLapKilometres },
                        set: { settings.autoLapKilometres = $0 }
                    ),
                    in: 0.5...10,
                    step: 0.5
                ) {
                    // The stored number is a count of whole units, so "every 1"
                    // means every mile for an imperial athlete without the value
                    // itself having to change.
                    Text("Every \(WatchFormat.decimal(settings.autoLapKilometres, places: 1)) \(settings.unitSystem.distanceUnit)")
                        .font(.system(size: 12))
                }
            }

            Section {
                Stepper(
                    value: Binding(
                        get: { settings.countdownSeconds },
                        set: { settings.countdownSeconds = $0 }
                    ),
                    in: 0...10,
                    step: 1
                ) {
                    Text(settings.countdownSeconds == 0 ? "No countdown" : "Countdown \(settings.countdownSeconds)s")
                        .font(.system(size: 12, weight: .semibold))
                }

                Toggle(isOn: Binding(
                    get: { settings.usesPreciseStart },
                    set: { settings.usesPreciseStart = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Precise start").font(.system(size: 12))
                        Text("Wait for an accurate fix")
                            .font(.system(size: 9))
                            .foregroundStyle(WatchTheme.textSecondary)
                    }
                }
                .tint(WatchTheme.accent)
            } header: {
                Text("Starting")
            } footer: {
                Text("Precise start holds the clock until GPS can place you, so the first metres are measured rather than guessed. The elapsed time always begins when recording does.")
                    .font(.system(size: 9))
            }

            Section("During workouts") {
                Toggle(isOn: Binding(
                    get: { settings.isAutoPauseEnabled },
                    set: { settings.isAutoPauseEnabled = $0 }
                )) {
                    Text("Auto pause").font(.system(size: 12))
                }
                .tint(WatchTheme.accent)

                Toggle(isOn: Binding(
                    get: { settings.usesHapticAlerts },
                    set: { settings.usesHapticAlerts = $0 }
                )) {
                    Text("Haptic alerts").font(.system(size: 12))
                }
                .tint(WatchTheme.accent)

                Toggle(isOn: Binding(
                    get: { settings.confirmsWorkoutEnd },
                    set: { settings.confirmsWorkoutEnd = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Confirm before stopping").font(.system(size: 12))
                        Text(settings.confirmsWorkoutEnd
                             ? "Asks before ending a workout"
                             : "End saves straight away")
                            .font(.system(size: 9))
                            .foregroundStyle(WatchTheme.textSecondary)
                    }
                }
                .tint(WatchTheme.accent)

                Toggle(isOn: Binding(
                    get: { settings.usesNavigationAlerts },
                    set: { settings.usesNavigationAlerts = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Course alerts").font(.system(size: 12))
                        Text("Buzz off course and at waypoints")
                            .font(.system(size: 9))
                            .foregroundStyle(WatchTheme.textSecondary)
                    }
                }
                .tint(WatchTheme.accent)

                Toggle(isOn: Binding(
                    get: { settings.isReroutingEnabled },
                    set: { settings.isReroutingEnabled = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Rerouting").font(.system(size: 12))
                        Text("Show the way back to the route")
                            .font(.system(size: 9))
                            .foregroundStyle(WatchTheme.textSecondary)
                    }
                }
                .tint(WatchTheme.accent)

                Toggle(isOn: Binding(
                    get: { settings.prefersHybridMap },
                    set: { settings.prefersHybridMap = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Night map").font(.system(size: 12))
                        Text("Dark sheet instead of cream paper")
                            .font(.system(size: 9))
                            .foregroundStyle(WatchTheme.textSecondary)
                    }
                }
                .tint(WatchTheme.accent)

                Toggle(isOn: Binding(
                    get: { settings.keepsScreenOn },
                    set: { settings.keepsScreenOn = $0 }
                )) {
                    Text("Always-on metrics").font(.system(size: 12))
                }
                .tint(WatchTheme.accent)
            }

            Section {
                Toggle(isOn: Binding(
                    get: { settings.showsStatusBadges },
                    set: { settings.showsStatusBadges = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("GPS & battery overlay").font(.system(size: 12))
                        Text(settings.showsStatusBadges ? "Above every page" : "Use data fields instead")
                            .font(.system(size: 9))
                            .foregroundStyle(WatchTheme.textSecondary)
                    }
                }
                .tint(WatchTheme.accent)

                NavigationLink {
                    TrailColorsWatchView()
                } label: {
                    HStack {
                        Label("Map line colours", systemImage: "scribble")
                            .font(.system(size: 12))
                        Spacer()
                        HStack(spacing: 3) {
                            Circle().fill(settings.routeTrailColor.color).frame(width: 9, height: 9)
                            Circle().fill(settings.breadcrumbTrailColor.color).frame(width: 9, height: 9)
                        }
                    }
                }

                NavigationLink {
                    MetricStyleWatchView()
                } label: {
                    HStack {
                        Label("Metric style", systemImage: "textformat.123")
                            .font(.system(size: 12))
                        Spacer()
                        Text(settings.metricTypeface.title)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(settings.fieldTint.swatch)
                    }
                }
            } header: {
                Text("Workout display")
            } footer: {
                Text("Signal strength, GPS accuracy and battery can all be placed on a data screen as ordinary fields. The workout timer is a field too — add it to any screen.")
                    .font(.system(size: 9))
            }

            Section {
                Picker(
                    selection: Binding(
                        get: { settings.unitSystem },
                        set: { settings.unitSystem = $0 }
                    )
                ) {
                    ForEach(UnitSystem.allCases) { system in
                        Text(system.title)
                            .font(.system(size: 13))
                            .tag(system)
                    }
                } label: {
                    Text("Units").font(.system(size: 12))
                }
                .pickerStyle(.navigationLink)
            } header: {
                Text("Units")
            } footer: {
                Text(settings.unitSystem == .metric
                     ? "Kilometres, metres, km/h"
                     : "Miles, feet, mph")
                    .font(.system(size: 9))
            }

            Section("Battery") {
                NavigationLink {
                    PowerSaverWatchView()
                } label: {
                    HStack {
                        Label("Power saver", systemImage: settings.isPowerSaverEnabled ? "leaf.fill" : "battery.50")
                            .font(.system(size: 12))
                        Spacer()
                        Text(settings.isPowerSaverEnabled ? "On" : "Off")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(settings.isPowerSaverEnabled ? WatchTheme.positive : WatchTheme.textSecondary)
                    }
                }
            }

            Section("Zones") {
                Stepper(
                    value: Binding(
                        get: { settings.maxHeartRate },
                        set: { settings.maxHeartRate = $0 }
                    ),
                    in: 140...220,
                    step: 1
                ) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Max HR \(settings.maxHeartRate)")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Zone 2 · \(LiveMetrics.zoneRange(2).lowerBound)-\(LiveMetrics.zoneRange(2).upperBound) bpm")
                            .font(.system(size: 9))
                            .foregroundStyle(WatchTheme.textSecondary)
                    }
                }
            }

            Section("Dashboard") {
                NavigationLink {
                    DashboardEditorWatchView()
                } label: {
                    HStack {
                        Label("Today tiles", systemImage: "square.grid.2x2.fill")
                            .font(.system(size: 12))
                        Spacer()
                        Text("\(dashboard.visibleMetrics.count)")
                            .font(.metric(12, weight: .semibold))
                            .foregroundStyle(WatchTheme.accent)
                    }
                }
            }

            Section("Screens by sport") {
                ForEach(SportFamily.allCases) { family in
                    NavigationLink {
                        SportFamilyScreensView(family: family)
                    } label: {
                        HStack {
                            Text(family.title)
                                .font(.system(size: 12))
                            Spacer()
                            let customized = family.sports.filter { settings.isCustomized($0) }.count
                            if customized > 0 {
                                Text("\(customized)")
                                    .font(.metric(11, weight: .semibold))
                                    .foregroundStyle(WatchTheme.accent)
                            }
                        }
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 3) {
                    Label(syncTitle, systemImage: "iphone.gen3.radiowaves.left.and.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WatchTheme.textPrimary)
                    Text("Anything you change here also changes on your iPhone.")
                        .font(.system(size: 9))
                        .foregroundStyle(WatchTheme.textSecondary)
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("Settings")
    }

    private var syncTitle: String {
        guard let synced = dashboard.lastSyncedAt else { return "Waiting for iPhone" }
        return "Synced \(synced.formatted(.relative(presentation: .named)))"
    }
}
