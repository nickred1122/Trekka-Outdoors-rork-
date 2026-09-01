import SwiftUI

struct LiveWorkoutView: View {
    @Environment(RouteStore.self) private var store
    @Environment(HealthService.self) private var health
    @Environment(AppearanceSettings.self) private var appearance
    @Environment(\.dismiss) private var dismiss

    let initialRoute: PlannedRoute?

    @State private var tracker = WorkoutTracker()
    @State private var showsMetricsSheet = false
    @State private var showsSummary = false
    @State private var completed: ActivityRecord?
    @State private var recenterToken = 0
    @State private var setupRoute: PlannedRoute?
    @State private var setupActivity: RouteActivityType = .run
    @State private var lapFeedback = 0
    @State private var offRouteFeedback = 0
    @State private var showsDiscardConfirmation = false
    @State private var mapStyle: TopoBaseStyle = .trekka

    /// Hold the map on the athlete only while the fix is real. With a stale or
    /// missing position, pinning the camera to the last known point would look
    /// like the map had frozen; letting it frame the route instead is honest.
    private var followsAthlete: Bool {
        tracker.gpsQuality == .live && tracker.track.last != nil
    }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            switch tracker.state {
            case .idle:
                setupScreen
            case .running, .paused:
                trackingScreen
            case .finished:
                trackingScreen
            }
        }
        .preferredColorScheme(appearance.colorScheme)
        .tint(Theme.accent)
        .onAppear {
            setupRoute = initialRoute
            setupActivity = initialRoute?.activity ?? .run
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: lapFeedback)
        .sensoryFeedback(.warning, trigger: offRouteFeedback)
        .onChange(of: tracker.isOffRoute) { _, isOff in
            if isOff { offRouteFeedback += 1 }
        }
        .sheet(isPresented: $showsMetricsSheet) {
            MetricsSheet(tracker: tracker)
        }
        .sheet(isPresented: $showsSummary, onDismiss: { dismiss() }) {
            if let completed {
                WorkoutSummarySheet(activity: completed) {
                    store.add(completed)
                    // Mirror the session into Apple Health, route included.
                    Task { await health.save(completed) }
                    showsSummary = false
                }
            }
        }
        .confirmationDialog(
            "Discard this workout?",
            isPresented: $showsDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) {
                tracker.reset()
                dismiss()
            }
            Button("Keep tracking", role: .cancel) {}
        }
    }

    // MARK: - Setup

    private var setupScreen: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(Theme.surface, in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                Spacer()
                Text("New workout")
                    .font(.system(.headline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 16)

            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Activity")
                            .metricLabelStyle()
                        HStack(spacing: 10) {
                            ForEach(RouteActivityType.allCases, id: \.self) { type in
                                Button {
                                    setupActivity = type
                                } label: {
                                    Text(type.rawValue)
                                        .font(.system(size: 13, weight: .semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 16)
                                    .background(
                                        setupActivity == type ? Theme.accent.opacity(0.16) : Theme.surface,
                                        in: .rect(cornerRadius: 12)
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 12)
                                            .strokeBorder(setupActivity == type ? Theme.accent : Theme.border, lineWidth: 1)
                                    }
                                    .foregroundStyle(setupActivity == type ? Theme.accent : Theme.textPrimary.opacity(0.75))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Follow a route")
                            .metricLabelStyle()

                        Button {
                            setupRoute = nil
                        } label: {
                            routeOptionRow(
                                title: "Free run",
                                detail: "No navigation — just record the track",
                                isSelected: setupRoute == nil
                            )
                        }
                        .buttonStyle(.plain)

                        ForEach(store.routes) { route in
                            Button {
                                setupRoute = route
                                setupActivity = route.activity
                            } label: {
                                routeOptionRow(
                                    title: route.name,
                                    detail: "\(Formatters.distance(route.distance)) km · \(Formatters.elevation(route.elevationGain)) m ↑",
                                    isSelected: setupRoute?.id == route.id
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)

            Button {
                tracker.start(route: setupRoute, activity: setupActivity)
                recenterToken += 1
            } label: {
                Label("Start", systemImage: "play.fill")
                    .font(.system(.headline, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .foregroundStyle(Theme.canvas)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private func routeOptionRow(title: String, detail: String, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
            }
            Spacer(minLength: 0)
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Theme.accent : Theme.textPrimary.opacity(0.25))
        }
        .padding(12)
        .panel(radius: 12)
    }

    // MARK: - Tracking

    private var trackingScreen: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .top) {
                // Trekka's own sheet rather than Apple's. This is the screen
                // most likely to be looked at with no signal, so it has to be
                // the map that can actually be stored on the device.
                TrekkaMapSurface(
                    routePoints: tracker.route?.points ?? [],
                    waypoints: tracker.route?.waypoints ?? [],
                    breadcrumb: tracker.track,
                    currentPosition: tracker.track.last,
                    baseStyle: mapStyle,
                    showsUserLocation: tracker.gpsQuality == .live,
                    centre: followsAthlete ? tracker.track.last?.coordinate : nil,
                    spanMetres: followsAthlete ? 1_200 : nil,
                    recenterToken: recenterToken
                )
                .ignoresSafeArea(edges: .top)

                VStack(spacing: 8) {
                    HStack {
                        Button {
                            showsDiscardConfirmation = true
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Theme.mapControlLabel)
                                .frame(width: 44, height: 44)
                                .background(Theme.mapControl, in: .circle)
                                .overlay { Circle().strokeBorder(Theme.mapControlBorder, lineWidth: 1) }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Discard workout")

                        Spacer()

                        statusPill

                        Spacer()

                        Button {
                            recenterToken += 1
                        } label: {
                            Image(systemName: "location.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.mapControlLabel)
                                .frame(width: 44, height: 44)
                                .background(Theme.mapControl, in: .circle)
                                .overlay { Circle().strokeBorder(Theme.mapControlBorder, lineWidth: 1) }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Recenter map")
                    }

                    if tracker.isOffRoute, let last = tracker.track.last {
                        Label("Off route — \(Int(RouteMath.distanceFromTrack(last.coordinate, points: tracker.route?.points ?? []))) m from the track", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(.caption, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Theme.danger, in: .capsule)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    } else if let waypoint = tracker.nextWaypoint {
                        Label("\(waypoint.name) in \(Formatters.distance(tracker.distanceToNextTurn)) km", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            .font(.system(.caption, weight: .semibold))
                            .foregroundStyle(Theme.canvas)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Theme.accent, in: .capsule)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .animation(.snappy, value: tracker.isOffRoute)
            }

            metricStrip
            elevationStrip
            controlRow
        }
        .background(Theme.canvas)
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(gpsColor)
                .frame(width: 7, height: 7)
            Text(gpsLabel)
                .font(.system(size: 11, weight: .semibold))
            Text("·")
                .foregroundStyle(Theme.textPrimary.opacity(0.4))
            Text(tracker.elapsedText)
                .font(.system(size: 12, weight: .bold))
                .monospacedDigit()
        }
        .foregroundStyle(Theme.mapControlLabel)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Theme.mapControl, in: .capsule)
        .overlay { Capsule().strokeBorder(Theme.mapControlBorder, lineWidth: 1) }
    }

    private var gpsColor: Color {
        switch tracker.gpsQuality {
        case .live: Theme.zoneColors[1]
        case .acquiring: Theme.highlight
        case .noFix: Theme.danger
        case .denied: Theme.danger
        }
    }

    private var gpsLabel: String {
        switch tracker.gpsQuality {
        case .live: "GPS"
        case .acquiring: "Acquiring"
        case .noFix: "No GPS fix · paused"
        case .denied: "Location off"
        }
    }

    private var metricStrip: some View {
        HStack(spacing: 0) {
            liveMetric(label: "Distance", value: Formatters.distance(tracker.distance), unit: Formatters.units.distanceUnit)
            Rectangle().fill(Theme.border).frame(width: 1, height: 42)
            liveMetric(label: "Pace", value: Formatters.pace(tracker.currentPace), unit: Formatters.units.paceUnit)
            Rectangle().fill(Theme.border).frame(width: 1, height: 42)
            VStack(alignment: .leading, spacing: 5) {
                Text("Heart rate")
                    .metricLabelStyle()
                if tracker.heartRate > 0 {
                    Text("\(Int(tracker.heartRate.rounded())) bpm · Z\(tracker.heartRateZone)")
                        .font(.system(size: 13, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Theme.zoneColor(tracker.heartRateZone), in: .capsule)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    // The phone has no heart-rate sensor, and a guessed number
                    // would be worse than none.
                    Text("Wear your watch")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.45))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
        }
        .padding(.vertical, 12)
        .panel()
        .padding(.horizontal, 16)
    }

    private func liveMetric(label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .metricLabelStyle()
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.metric(26))
                    .foregroundStyle(Theme.textPrimary)
                Text(unit)
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .accessibilityElement(children: .combine)
    }

    private var elevationStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(Formatters.elevation(tracker.currentElevation)) \(Formatters.units.elevationUnit) now")
                    .font(.system(.footnote, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(Formatters.elevation(tracker.elevationGain)) \(Formatters.units.elevationUnit) ↑ climbed")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
            }
            ElevationChart(
                samples: profileSamples,
                cursorDistance: tracker.distance,
                showsAxes: false,
                height: 74
            )
        }
        .padding(12)
        .panel()
        .padding(.horizontal, 16)
    }

    private var profileSamples: [ElevationSample] {
        if let route = tracker.route, route.points.count > 1 {
            return ElevationProfile.samples(for: route.points)
        }
        return ElevationProfile.samples(for: tracker.track)
    }

    private var controlRow: some View {
        HStack(spacing: 10) {
            controlButton(
                symbol: tracker.state == .paused ? "play.circle" : "pause.circle",
                title: tracker.state == .paused ? "Resume" : "Pause"
            ) {
                if tracker.state == .paused { tracker.resume() } else { tracker.pause() }
            }

            controlButton(symbol: "map", title: "Metrics") {
                showsMetricsSheet = true
            }

            if tracker.state == .paused {
                controlButton(symbol: "stop.circle", title: "Finish", tint: Theme.danger) {
                    finish()
                }
            } else {
                controlButton(symbol: "flag.circle", title: "Lap") {
                    tracker.lap()
                    lapFeedback += 1
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    private func controlButton(
        symbol: String,
        title: String,
        tint: Color = Theme.accent,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 25, weight: .regular))
                    .foregroundStyle(tint)
                    .contentTransition(.symbolEffect(.replace))
                Text(title)
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .panel(radius: 14)
        }
        .buttonStyle(.plain)
    }

    private func finish() {
        if let record = tracker.finish() {
            completed = record
            showsSummary = true
        } else {
            tracker.reset()
            dismiss()
        }
    }
}

// MARK: - Metrics sheet

private struct MetricsSheet: View {
    let tracker: WorkoutTracker
    @Environment(AppearanceSettings.self) private var appearance
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    StatStrip(items: [
                        StatItem(symbol: "clock", label: "Elapsed", value: tracker.elapsedText, unit: ""),
                        StatItem(symbol: "arrow.left.and.right", label: "Distance", value: Formatters.distance(tracker.distance), unit: Formatters.units.distanceUnit),
                        StatItem(symbol: "arrow.up.forward", label: "Climb", value: Formatters.elevation(tracker.elevationGain), unit: Formatters.units.elevationUnit),
                    ])

                    if let route = tracker.route {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Route progress")
                                    .font(.system(.subheadline, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Text("\(Int(tracker.progressAlongRoute * 100))%")
                                    .font(.metric(16))
                                    .foregroundStyle(Theme.accent)
                            }
                            ProgressView(value: tracker.progressAlongRoute)
                                .tint(Theme.accent)
                            Text("\(Formatters.distance(max(0, route.distance - tracker.distance))) \(Formatters.units.distanceUnit) remaining")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(Theme.textPrimary.opacity(0.6))
                        }
                        .padding(16)
                        .panel()
                    }

                    ZoneBars(minutes: tracker.zoneSeconds.map { $0 / 60 }, title: "Time in zones", subtitle: "This session")

                    if !tracker.laps.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Laps")
                                .font(.system(.subheadline, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .padding(.bottom, 8)
                            ForEach(tracker.laps) { lap in
                                HStack {
                                    Text("Lap \(lap.index)")
                                        .font(.system(.subheadline, weight: .medium))
                                        .foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    Text("\(Formatters.distance(lap.distance)) \(Formatters.units.distanceUnit)")
                                        .font(.system(.subheadline, weight: .medium))
                                        .monospacedDigit()
                                        .foregroundStyle(Theme.textPrimary.opacity(0.7))
                                    Text(Formatters.duration(lap.duration))
                                        .font(.system(.subheadline, weight: .semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(Theme.accent)
                                        .frame(width: 70, alignment: .trailing)
                                }
                                .padding(.vertical, 8)
                            }
                        }
                        .padding(16)
                        .panel()
                    }
                }
                .padding(16)
            }
            .background(Theme.canvas)
            .navigationTitle("Live metrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(Theme.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationContentInteraction(.scrolls)
        .preferredColorScheme(appearance.colorScheme)
        .tint(Theme.accent)
    }
}

// MARK: - Summary sheet

private struct WorkoutSummarySheet: View {
    let activity: ActivityRecord
    let onSave: () -> Void
    @Environment(AppearanceSettings.self) private var appearance

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if activity.track.count > 1 {
                        RouteThumbnail(points: activity.track)
                            .frame(height: 170)
                            .clipShape(.rect(cornerRadius: Theme.cardRadius))
                    }

                    StatStrip(items: [
                        StatItem(symbol: "arrow.left.and.right", label: "Distance", value: Formatters.distance(activity.distance), unit: Formatters.units.distanceUnit),
                        StatItem(symbol: "clock", label: "Time", value: Formatters.duration(activity.duration), unit: ""),
                        StatItem(symbol: "speedometer", label: "Avg pace", value: Formatters.pace(activity.averagePace), unit: Formatters.units.paceUnit),
                    ])

                    StatStrip(items: [
                        StatItem(symbol: "arrow.up.forward", label: "Climb", value: Formatters.elevation(activity.elevationGain), unit: Formatters.units.elevationUnit),
                        StatItem(symbol: "flame.fill", label: "Calories", value: Formatters.integer(activity.calories), unit: "kcal"),
                        StatItem(symbol: "bolt.heart", label: "Effect", value: String(format: "%.1f", activity.trainingEffect), unit: ""),
                    ])

                    ZoneBars(minutes: activity.zoneMinutes, title: "Time in zones", subtitle: "This session")

                    Button(action: onSave) {
                        Label("Save activity", systemImage: "checkmark.circle.fill")
                            .font(.system(.headline, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .foregroundStyle(Theme.canvas)
                }
                .padding(16)
            }
            .background(Theme.canvas)
            .navigationTitle("Workout complete")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
        .preferredColorScheme(appearance.colorScheme)
        .tint(Theme.accent)
    }
}
