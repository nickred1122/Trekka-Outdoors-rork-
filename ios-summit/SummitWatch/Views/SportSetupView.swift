import SwiftUI

/// Pre-workout screen: pick a route, review the page stack, start.
struct SportSetupView: View {
    let sport: WatchSport
    var presetRoute: WatchRoute?

    @Environment(WatchScreenSettings.self) private var settings
    @Environment(WatchRouteStore.self) private var routeStore
    @Environment(WorkoutEngine.self) private var engine

    @State private var selectedRouteID: UUID?
    /// Warms the receiver while this screen is open, so the athlete can see the
    /// signal is good before committing to a workout.
    @State private var preflight = PreflightLocation()

    private var selectedRoute: WatchRoute? {
        guard let selectedRouteID else { return nil }
        return routeStore.route(id: selectedRouteID)
    }

    private var availableRoutes: [WatchRoute] {
        routeStore.routes(for: sport)
    }

    private var activeScreens: [WatchScreen] {
        settings.activeScreens(for: sport, hasRoute: selectedRoute != nil)
    }

    var body: some View {
        List {
            if sport.usesGPS {
                Section {
                    gpsStatus
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(gpsTint.opacity(0.14))
                        )
                }
            }

            Section {
                Button {
                    // The app root swaps the whole screen over to the workout,
                    // so there is no dashboard left behind it to swipe back to
                    // by accident mid-session.
                    engine.start(sport: sport, route: selectedRoute)
                } label: {
                    HStack(spacing: 10) {
                        Capsule()
                            .fill(sport.tint)
                            .frame(width: 4, height: 34)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Start")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(WatchTheme.textPrimary)
                            Text(startDetail)
                                .font(.system(size: 10))
                                .foregroundStyle(WatchTheme.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(sport.tint.opacity(0.16))
                )
            }

            if sport.supportsRoutes && !availableRoutes.isEmpty {
                Section("Course") {
                    Button {
                        selectedRouteID = nil
                    } label: {
                        routeOption(name: "No route", detail: "Free run, no navigation", isSelected: selectedRouteID == nil)
                    }
                    ForEach(availableRoutes) { route in
                        Button {
                            selectedRouteID = route.id
                        } label: {
                            routeOption(
                                name: route.name,
                                detail: "\(WatchFormat.distance(route.distance)) \(WatchFormat.units.distanceUnit) · ↑\(WatchFormat.elevation(route.elevationGain)) \(WatchFormat.units.elevationUnit)",
                                isSelected: selectedRouteID == route.id
                            )
                        }
                    }
                }
            }

            Section {
                NavigationLink {
                    ScreensEditorView(sport: sport)
                } label: {
                    HStack {
                        Label("Screens", systemImage: "square.grid.2x2.fill")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text("\(activeScreens.count)")
                            .font(.metric(13, weight: .semibold))
                            .foregroundStyle(sport.tint)
                    }
                }
            } footer: {
                Text(activeScreens.map(\.title).joined(separator: " → "))
                    .font(.system(size: 9))
                    .foregroundStyle(WatchTheme.textSecondary)
            }

            Section("Options") {
                Toggle(isOn: Binding(
                    get: { settings.usesPreciseStart },
                    set: { settings.usesPreciseStart = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Precise start")
                            .font(.system(size: 12))
                        Text("Hold the clock until GPS is accurate")
                            .font(.system(size: 9))
                            .foregroundStyle(WatchTheme.textSecondary)
                    }
                }
                .tint(sport.tint)
                .disabled(!sport.usesGPS)

                Stepper(
                    value: Binding(
                        get: { settings.countdownSeconds },
                        set: { settings.countdownSeconds = $0 }
                    ),
                    in: 0...10,
                    step: 1
                ) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(settings.countdownSeconds == 0 ? "No countdown" : "Countdown \(settings.countdownSeconds)s")
                            .font(.system(size: 12, weight: .semibold))
                        Text(settings.countdownSeconds == 0 ? "Starts the moment you tap" : "Counts down before recording")
                            .font(.system(size: 9))
                            .foregroundStyle(WatchTheme.textSecondary)
                    }
                }

                Toggle(isOn: Binding(
                    get: { settings.isAutoLapEnabled },
                    set: { settings.isAutoLapEnabled = $0 }
                )) {
                    Text("Auto lap · \(WatchFormat.decimal(settings.autoLapKilometres, places: 1)) \(settings.unitSystem.distanceUnit)")
                        .font(.system(size: 12))
                }
                .tint(sport.tint)

                Toggle(isOn: Binding(
                    get: { settings.isAutoPauseEnabled },
                    set: { settings.isAutoPauseEnabled = $0 }
                )) {
                    Text("Auto pause")
                        .font(.system(size: 12))
                }
                .tint(sport.tint)
            }
        }
        .navigationTitle(sport.title)
        .containerBackground(sport.tint.gradient, for: .navigation)
        .onAppear {
            if selectedRouteID == nil {
                selectedRouteID = presetRoute?.id
            }
            if sport.usesGPS { preflight.start() }
        }
        .onDisappear { preflight.stop() }
    }

    private var gpsTint: Color {
        if preflight.isDenied { return WatchTheme.danger }
        return preflight.isLocked ? WatchTheme.positive : WatchTheme.textSecondary
    }

    /// Says plainly whether the receiver is ready, before Start is tapped.
    private var gpsStatus: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(gpsTint.opacity(0.18))
                    .frame(width: 26, height: 26)
                Image(systemName: lockSymbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(gpsTint)
                    .contentTransition(.symbolEffect(.replace))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(lockTitle)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WatchTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(preflight.statusText)
                    .font(.system(size: 9))
                    .foregroundStyle(WatchTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)

            if !preflight.isDenied {
                GPSStrengthBadge(bars: preflight.bars, isLive: preflight.isLocked)
            }
        }
        .padding(.vertical, 2)
        .animation(.snappy, value: preflight.isLocked)
        .animation(.snappy, value: preflight.isDenied)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(lockTitle). \(preflight.statusText).")
    }

    private var lockSymbol: String {
        if preflight.isDenied { return "location.slash.fill" }
        return preflight.isLocked ? "location.fill" : "location.circle"
    }

    private var lockTitle: String {
        if preflight.isDenied { return "No location access" }
        return preflight.isLocked ? "GPS locked on" : "Finding GPS"
    }

    /// Says what tapping Start will actually do, so a held clock is never a
    /// surprise.
    private var startDetail: String {
        if sport.usesGPS && settings.usesPreciseStart { return "\(sport.title) · waits for GPS" }
        if settings.countdownSeconds > 0 { return "\(sport.title) · \(settings.countdownSeconds)s countdown" }
        return sport.title
    }

    private func routeOption(name: String, detail: String, isSelected: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? sport.tint : WatchTheme.textSecondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WatchTheme.textPrimary)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundStyle(WatchTheme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}
