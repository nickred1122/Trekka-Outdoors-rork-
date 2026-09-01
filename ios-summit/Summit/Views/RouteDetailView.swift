import SwiftUI
import UniformTypeIdentifiers

nonisolated enum RouteDestination: Hashable, Sendable {
    case route(UUID)
    /// The single place where downloaded ground is managed.
    case maps
}

struct RouteDetailView: View {
    let routeID: UUID

    @Environment(RouteStore.self) private var store
    @Environment(WatchSyncService.self) private var watchSync
    @Environment(MapPackStore.self) private var mapPacks
    @Environment(\.dismiss) private var dismiss

    @Binding var pendingWorkoutRoute: PlannedRoute?
    @Binding var showsWorkout: Bool

    @State private var recenterToken = 0
    @State private var locateToken = 0
    @State private var selectedWaypoint: Waypoint?
    @State private var showsExporter = false
    @State private var exportDocument: GPXDocument?
    @State private var showsDeleteConfirmation = false
    @State private var syncFeedback = 0

    private var route: PlannedRoute? { store.route(id: routeID) }

    var body: some View {
        Group {
            if let route {
                content(for: route)
            } else {
                ContentUnavailableView("Route unavailable", systemImage: "map")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.canvas)
            }
        }
        .background(Theme.canvas)
        .navigationTitle(route?.name ?? "Route")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        exportGPX()
                    } label: {
                        Label("Export GPX", systemImage: "square.and.arrow.up")
                    }
                    if let route {
                        if let pack = mapPacks.pack(forRoute: route.id) {
                            Button(role: .destructive) {
                                mapPacks.delete(packID: pack.id)
                                store.setOfflineDownloaded(false, routeID: route.id)
                            } label: {
                                Label("Remove offline map", systemImage: "trash.slash")
                            }
                        } else {
                            Button {
                                mapPacks.download(route: route)
                            } label: {
                                Label("Download offline map", systemImage: "arrow.down.circle")
                            }
                            Button {
                                mapPacks.download(route: route, widened: true)
                            } label: {
                                Label("Download wider area", systemImage: "arrow.down.circle.dotted")
                            }
                        }
                    }
                    Button(role: .destructive) {
                        showsDeleteConfirmation = true
                    } label: {
                        Label("Delete route", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .tint(Theme.accent)
            }
        }
        .sheet(item: $selectedWaypoint) { waypoint in
            WaypointSheet(waypoint: waypoint)
        }
        .fileExporter(
            isPresented: $showsExporter,
            document: exportDocument,
            contentType: .xml,
            defaultFilename: route?.name ?? "route"
        ) { _ in
            exportDocument = nil
        }
        .confirmationDialog("Delete this route?", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                store.delete(routeID: routeID)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
        .sensoryFeedback(.success, trigger: syncFeedback)
        .onDisappear { watchSync.reset() }
    }

    // MARK: - Content

    private func content(for route: PlannedRoute) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                TrekkaMapSurface(
                    routePoints: route.points,
                    waypoints: route.waypoints,
                    showsUserLocation: true,
                    recenterToken: recenterToken,
                    locateToken: locateToken
                )
                .frame(height: 240)
                .clipShape(.rect(cornerRadius: Theme.cardRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.cardRadius)
                        .strokeBorder(Theme.border, lineWidth: 1)
                }
                .overlay(alignment: .topTrailing) {
                    // Two different requests, so two buttons. The single
                    // location-arrow button used to only ever fit the route,
                    // which is why asking to be located appeared to do nothing.
                    VStack(spacing: 8) {
                        mapPill(symbol: "location.fill", label: "Show my location") {
                            MapLocationService.shared.requestAccess()
                            locateToken += 1
                        }
                        mapPill(
                            symbol: "arrow.down.backward.and.arrow.up.forward",
                            label: "Fit route on map"
                        ) {
                            recenterToken += 1
                        }
                    }
                    .padding(10)
                }

                StatStrip(items: [
                    StatItem(symbol: "arrow.left.and.right", label: "Distance", value: Formatters.distance(route.distance), unit: Formatters.units.distanceUnit),
                    StatItem(symbol: "arrow.up.forward", label: "Elev. gain", value: Formatters.elevation(route.elevationGain), unit: "\(Formatters.units.elevationUnit) ↑"),
                    StatItem(symbol: "clock", label: "Est. time", value: Formatters.compactDuration(route.estimatedDuration), unit: "est"),
                ])

                elevationCard(for: route)

                let climbs = route.climbs
                if !climbs.isEmpty {
                    climbsCard(climbs, route: route)
                }

                if !route.waypoints.isEmpty {
                    waypointsCard(for: route)
                }

                offlineCard(for: route)

                actionButtons(for: route)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
    }

    /// Every sustained climb the route actually contains, read off its surveyed
    /// profile — the same detection the watch runs, so the briefing here and the
    /// climb page on the wrist always agree.
    private func climbsCard(_ climbs: [ClimbSegment], route: PlannedRoute) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Climbs")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(climbs.count) · \(Formatters.elevation(climbs.reduce(0) { $0 + $1.gain })) \(Formatters.units.elevationUnit) ↑")
                    .font(.system(.caption, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
            }

            VStack(spacing: 8) {
                ForEach(climbs) { climb in
                    climbRow(climb, routeDistance: route.distance)
                }
            }

            Text("Detected from the route's elevation profile. Your watch counts down each one as you climb it.")
                .font(.caption2)
                .foregroundStyle(Theme.textPrimary.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private func climbRow(_ climb: ClimbSegment, routeDistance: Double) -> some View {
        let tint = Theme.zoneColors[max(0, min(Theme.zoneColors.count - 1, climb.category.tintIndex))]

        return HStack(spacing: 11) {
            VStack(spacing: 1) {
                Text(climb.category.label)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Theme.canvas)
            }
            .frame(width: 44, height: 30)
            .background(tint, in: .rect(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 3) {
                Text("\(Formatters.distance(climb.startDistance)) \(Formatters.units.distanceUnit) → \(Formatters.distance(climb.endDistance)) \(Formatters.units.distanceUnit)")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                // A wedge whose rake matches the climb's real gradient.
                GeometryReader { geometry in
                    Path { path in
                        let width = geometry.size.width
                        let height = geometry.size.height
                        let steepness = min(1, climb.averageGrade / 15)
                        path.move(to: CGPoint(x: 0, y: height))
                        path.addLine(to: CGPoint(x: width, y: height))
                        path.addLine(to: CGPoint(x: width, y: height - height * steepness))
                        path.closeSubpath()
                    }
                    .fill(tint.opacity(0.5))
                }
                .frame(height: 10)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 1) {
                Text("\(Formatters.elevation(climb.gain)) \(Formatters.units.elevationUnit)")
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Text("\(String(format: "%.1f", climb.averageGrade))% avg · \(String(format: "%.0f", climb.maxGrade))% max")
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
            }
            .lineLimit(1)
        }
        .padding(.vertical, 2)
    }

    private func elevationCard(for route: PlannedRoute) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Elevation")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(Formatters.elevation(route.minElevation))–\(Formatters.elevation(route.maxElevation)) \(Formatters.units.elevationUnit)")
                    .font(.system(.caption, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
            }
            ElevationChart(
                samples: ElevationProfile.samples(for: route.points),
                waypoints: route.waypoints,
                height: 160
            )
        }
        .padding(16)
        .panel()
    }

    private func waypointsCard(for route: PlannedRoute) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Waypoints")
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.bottom, 10)

            ForEach(Array(route.waypoints.enumerated()), id: \.element.id) { index, waypoint in
                Button {
                    selectedWaypoint = waypoint
                } label: {
                    HStack(spacing: 12) {
                        DiamondBadge(number: index + 1)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(waypoint.name)
                                .font(.system(.subheadline, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                            Text("\(Formatters.distance(waypoint.distanceAlongRoute)) \(Formatters.units.distanceUnit) in")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(Theme.textPrimary.opacity(0.5))
                        }
                        Spacer(minLength: 0)
                        Text("\(Formatters.elevation(waypoint.elevation)) \(Formatters.units.elevationUnit)")
                            .font(.system(.subheadline, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary.opacity(0.75))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary.opacity(0.3))
                    }
                    .padding(.vertical, 10)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)

                if index < route.waypoints.count - 1 {
                    Rectangle()
                        .fill(Theme.border)
                        .frame(height: 1)
                }
            }
        }
        .padding(16)
        .panel()
    }

    private func offlineCard(for route: PlannedRoute) -> some View {
        VStack(spacing: 10) {
            switch watchSync.state {
            case .sending(let progress):
                progressRow(title: "Sending to Apple Watch", progress: progress, detail: "\(route.waypoints.count) waypoints")
            case .delivered:
                Label("Route is on your watch", systemImage: "checkmark.circle.fill")
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.zoneColors[1])
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.highlight)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .idle:
                HStack(spacing: 10) {
                    Image(systemName: route.isSyncedToWatch ? "checkmark.circle.fill" : "applewatch")
                        .foregroundStyle(route.isSyncedToWatch ? Theme.zoneColors[1] : Theme.textPrimary.opacity(0.5))
                    Text(
                        route.isSyncedToWatch
                            ? "Course and waypoints are on your watch"
                            : "Send this course to your watch to navigate it there"
                    )
                    .font(.footnote)
                    .foregroundStyle(Theme.textPrimary.opacity(0.7))
                    Spacer(minLength: 0)
                }
            }

            Divider().overlay(Theme.border)

            offlineMapRow(for: route)
        }
        .padding(14)
        .panel()
    }

    /// The state of this route's downloaded ground.
    ///
    /// Deliberately explicit about what is stored where: the map on the phone and
    /// the map on the watch are different things, and an athlete about to walk
    /// away from their phone needs to know which they have.
    @ViewBuilder
    private func offlineMapRow(for route: PlannedRoute) -> some View {
        let isActive = mapPacks.activeRouteID == route.id

        if isActive, mapPacks.progress.isBusy {
            VStack(alignment: .leading, spacing: 8) {
                progressRow(
                    title: downloadTitle,
                    progress: mapPacks.progress.fraction,
                    detail: downloadDetail
                )
                Button("Cancel") { mapPacks.cancel() }
                    .font(.caption)
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
            }
        } else if let pack = mapPacks.pack(forRoute: route.id) {
            HStack(spacing: 10) {
                TrekkaIcon(.route, size: 17, tint: Theme.positive)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Map stored for offline use")
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(pack.sizeDescription) · \(pack.tileCount) tiles · sent to your watch")
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                }
                Spacer(minLength: 0)
            }
        } else if case .failed(let message) = mapPacks.progress, isActive {
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.highlight)
                Button("Try again") { mapPacks.download(route: route) }
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Button {
                mapPacks.download(route: route)
            } label: {
                HStack(spacing: 10) {
                    TrekkaIcon(.route, size: 17, tint: Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Download map for offline use")
                            .font(.system(.footnote, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("About \(estimatedPackSize(for: route)) · works with no signal on watch")
                            .font(.caption)
                            .foregroundStyle(Theme.textPrimary.opacity(0.6))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(Theme.accent)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func mapPill(
        symbol: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.mapControlLabel)
                .frame(width: 44, height: 44)
                .background(Theme.mapControl, in: .circle)
                .overlay { Circle().strokeBorder(Theme.mapControlBorder, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var downloadTitle: String {
        switch mapPacks.progress {
        case .planning: "Working out which tiles are needed"
        case .downloading: "Downloading map"
        case .writing: "Saving map"
        case .sendingToWatch: "Sending map to your watch"
        default: "Downloading map"
        }
    }

    private var downloadDetail: String {
        if case .downloading(let completed, let total) = mapPacks.progress {
            return "\(completed) of \(total)"
        }
        return ""
    }

    /// An estimate, and labelled as one. The real size is shown once the pack is
    /// on disk, because that is the only figure that is actually true.
    private func estimatedPackSize(for route: PlannedRoute) -> String {
        let plan = MapPackPlanner.plan(for: route.coordinates, widened: false)
        return MapPackFormat.describe(bytes: plan.estimatedBytes)
    }

    private func progressRow(title: String, progress: Double, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(detail)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
            }
            ProgressView(value: progress)
                .tint(Theme.accent)
        }
    }

    private func actionButtons(for route: PlannedRoute) -> some View {
        VStack(spacing: 10) {
            Button {
                watchSync.send(route: route, store: store)
                // The course and the ground it crosses travel together. Sending
                // a route without its map would put an athlete on a mountain
                // with a line and no terrain, which is the exact situation this
                // whole feature exists to prevent.
                if !mapPacks.hasPack(forRoute: route.id), !mapPacks.progress.isBusy {
                    mapPacks.download(route: route)
                }
                syncFeedback += 1
            } label: {
                Label(
                    route.isSyncedToWatch ? "Re-send to Apple Watch" : "Send to Apple Watch",
                    systemImage: "applewatch"
                )
                .font(.system(.headline, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .tint(Theme.accent)
            .disabled(isTransferring)

            Button {
                pendingWorkoutRoute = route
                showsWorkout = true
            } label: {
                Label("Start workout on this route", systemImage: "play.fill")
                    .font(.system(.headline, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .foregroundStyle(Theme.canvas)
        }
    }

    private var isTransferring: Bool {
        switch watchSync.state {
        case .sending: true
        default: false
        }
    }

    private func exportGPX() {
        guard let route else { return }
        exportDocument = GPXDocument(text: GPXCodec.export(route))
        showsExporter = true
    }
}

/// Small orange diamond badge matching the map markers.
struct DiamondBadge: View {
    let number: Int

    var body: some View {
        Text("\(number)")
            .font(.system(size: 11, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(Theme.accent)
            .frame(width: 24, height: 24)
            .background {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Theme.accent, lineWidth: 1.5)
                    .rotationEffect(.degrees(45))
                    .frame(width: 17, height: 17)
            }
            .accessibilityHidden(true)
    }
}

private struct WaypointSheet: View {
    let waypoint: Waypoint
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TrekkaMapSurface(
                        waypoints: [waypoint],
                        isInteractive: false,
                        showsUserLocation: false
                    )
                    .frame(height: 180)
                    .clipShape(.rect(cornerRadius: 14))

                    StatStrip(items: [
                        StatItem(symbol: "arrow.up.forward", label: "Elevation", value: Formatters.elevation(waypoint.elevation), unit: Formatters.units.elevationUnit),
                        StatItem(symbol: "arrow.left.and.right", label: "Into route", value: Formatters.distance(waypoint.distanceAlongRoute), unit: Formatters.units.distanceUnit),
                    ])

                    if !waypoint.note.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Note")
                                .metricLabelStyle()
                            Text(waypoint.note)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textPrimary.opacity(0.85))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .panel()
                    }
                }
                .padding(16)
            }
            .background(Theme.canvas)
            .navigationTitle(waypoint.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(Theme.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationContentInteraction(.scrolls)
        .tint(Theme.accent)
    }
}
