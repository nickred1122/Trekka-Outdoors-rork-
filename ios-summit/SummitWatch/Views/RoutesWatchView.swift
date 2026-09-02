import SwiftUI
import CoreLocation

/// The two surfaces on the watch's Routes tab.
nonisolated enum WatchRoutesSection: String, CaseIterable, Identifiable, Sendable {
    case routes
    case trails

    var id: String { rawValue }

    var title: String {
        switch self {
        case .routes: "Routes"
        case .trails: "Trails"
        }
    }

    var glyph: TrekkaGlyph {
        switch self {
        case .routes: .route
        case .trails: .breadcrumb
        }
    }
}

/// Routes sent from the phone, and the breadcrumb trails recorded on the wrist.
struct RoutesWatchView: View {
    var onStart: (WatchRoute) -> Void

    @Environment(WatchRouteStore.self) private var store
    @Environment(BreadcrumbStore.self) private var breadcrumbs

    @State private var section: WatchRoutesSection = .routes

    var body: some View {
        List {
            Section {
                switcher
                    .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            switch section {
            case .routes:
                routeRows
            case .trails:
                trailRows
            }
        }
        .navigationTitle(section == .routes ? "Routes" : "Trails")
    }

    private var switcher: some View {
        HStack(spacing: 4) {
            ForEach(WatchRoutesSection.allCases) { value in
                let isActive = section == value
                Button {
                    withAnimation(.snappy(duration: 0.22)) { section = value }
                } label: {
                    HStack(spacing: 3) {
                        TrekkaIcon(value.glyph, size: WatchDisplay.scaled(11, atLeast: 10))
                        Text(value.title)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .foregroundStyle(isActive ? WatchTheme.canvas : WatchTheme.textSecondary)
                    .background(
                        isActive ? WatchTheme.accent : WatchTheme.surfaceRaised,
                        in: .rect(cornerRadius: 8)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    // MARK: - Routes

    @ViewBuilder
    private var routeRows: some View {
        if store.routes.isEmpty {
            Text("No routes yet. Send one from Trekka on your iPhone.")
                .font(.system(size: 11))
                .foregroundStyle(WatchTheme.textSecondary)
        } else {
            ForEach(store.routes) { route in
                NavigationLink {
                    RouteDetailWatchView(route: route, onStart: onStart)
                } label: {
                    routeRow(route)
                }
            }
        }

        if let synced = store.lastSyncedAt {
            Section {
                Text("Synced \(synced.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 9))
                    .foregroundStyle(WatchTheme.textSecondary)
            }
        }
    }

    private func routeRow(_ route: WatchRoute) -> some View {
        HStack(spacing: 8) {
            RouteGlyph(points: route.points)
                .frame(width: 30, height: 30)
                .background(WatchTheme.surfaceRaised, in: .rect(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 1) {
                Text(route.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WatchTheme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text("\(WatchFormat.distance(route.distance)) \(WatchFormat.units.distanceUnit)")
                    Text("↑\(WatchFormat.elevation(route.elevationGain)) \(WatchFormat.units.elevationUnit)")
                        .foregroundStyle(WatchTheme.highlight)
                }
                .font(.metric(9, weight: .medium))
                .foregroundStyle(WatchTheme.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Trails

    @ViewBuilder
    private var trailRows: some View {
        if breadcrumbs.trails.isEmpty {
            Text("No trails yet. Crumbs are dropped as you move, so you can always walk your own line back.")
                .font(.system(size: 11))
                .foregroundStyle(WatchTheme.textSecondary)
        } else {
            ForEach(breadcrumbs.trails) { trail in
                NavigationLink {
                    BreadcrumbTrailWatchView(trail: trail, onStart: onStart)
                } label: {
                    trailRow(trail)
                }
            }
        }
    }

    private func trailRow(_ trail: BreadcrumbTrail) -> some View {
        HStack(spacing: 8) {
            TrekkaIcon(.breadcrumb, size: WatchDisplay.scaled(14, atLeast: 12), tint: WatchTheme.highlight)
                .frame(width: 26, height: 26)
                .background(WatchTheme.surfaceRaised, in: .rect(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 1) {
                Text(trail.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WatchTheme.textPrimary)
                    .lineLimit(1)
                Text("\(WatchFormat.distance(trail.distance)) \(WatchFormat.units.distanceUnit) · \(trail.startedAt.formatted(.relative(presentation: .named)))")
                    .font(.metric(9, weight: .medium))
                    .foregroundStyle(WatchTheme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

/// A finished breadcrumb trail, with the option to walk it back the other way.
struct BreadcrumbTrailWatchView: View {
    let trail: BreadcrumbTrail
    var onStart: (WatchRoute) -> Void

    @Environment(BreadcrumbStore.self) private var breadcrumbs
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                NavigationLink {
                    ExpandedMapWatchView(
                        breadcrumb: trail.coordinates,
                        position: trail.crumbs.last?.coordinate,
                        title: trail.name
                    )
                } label: {
                    WatchPreviewMap(
                        breadcrumb: trail.coordinates,
                        position: trail.crumbs.last?.coordinate
                    )
                    .frame(height: 120)
                    .clipShape(.rect(cornerRadius: 10))
                    .overlay(alignment: .bottomTrailing) { MapExpandBadge() }
                }
                .buttonStyle(.plain)

                VStack(spacing: 5) {
                    WatchStatRow(title: "Distance", value: "\(WatchFormat.distance(trail.distance)) \(WatchFormat.units.distanceUnit)")
                    WatchStatRow(title: "Duration", value: WatchFormat.compactDuration(trail.duration))
                    WatchStatRow(title: "Crumbs", value: "\(trail.crumbs.count)", tint: WatchTheme.highlight)
                }
                .padding(9)
                .watchPanel()

                Button {
                    guard let route = breadcrumbs.backtrackRoute(
                        from: trail.crumbs,
                        name: "Back: \(trail.name)",
                        sport: trail.sport
                    ) else { return }
                    onStart(route)
                    dismiss()
                } label: {
                    TrekkaLabel("Backtrack", glyph: .backtrack, size: WatchDisplay.scaled(13, atLeast: 12))
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchTheme.accent)

                Text("Backtrack retraces these crumbs in reverse, so you can follow them home.")
                    .font(.system(size: 9))
                    .foregroundStyle(WatchTheme.textSecondary)

                Button(role: .destructive) {
                    breadcrumbs.delete(trailID: trail.id)
                    dismiss()
                } label: {
                    TrekkaLabel("Delete trail", glyph: .trash, size: WatchDisplay.scaled(12, atLeast: 11))
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle(trail.name)
    }
}

/// Route preview with its profile and a start button.
struct RouteDetailWatchView: View {
    let route: WatchRoute
    var onStart: (WatchRoute) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                NavigationLink {
                    ExpandedMapWatchView(
                        route: route.coordinates,
                        waypoints: route.waypoints,
                        title: route.name
                    )
                } label: {
                    WatchPreviewMap(
                        route: route.coordinates,
                        waypoints: route.waypoints
                    )
                    .frame(height: 110)
                    .clipShape(.rect(cornerRadius: 10))
                    .overlay(alignment: .bottomTrailing) { MapExpandBadge() }
                }
                .buttonStyle(.plain)

                VStack(spacing: 5) {
                    WatchStatRow(title: "Distance", value: "\(WatchFormat.distance(route.distance)) \(WatchFormat.units.distanceUnit)")
                    WatchStatRow(title: "Ascent", value: "\(WatchFormat.elevation(route.elevationGain)) \(WatchFormat.units.elevationUnit)", tint: WatchTheme.highlight)
                    WatchStatRow(title: "High point", value: "\(WatchFormat.elevation(route.maxElevation)) \(WatchFormat.units.elevationUnit)")
                    WatchStatRow(title: "Est. time", value: WatchFormat.compactDuration(route.estimatedDuration(for: route.sport)))
                    WatchStatRow(title: "Waypoints", value: "\(route.waypoints.count)")
                }
                .padding(9)
                .watchPanel()

                if !route.waypoints.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Waypoints")
                            .fieldLabelStyle()
                        ForEach(route.waypoints) { waypoint in
                            HStack {
                                Text(waypoint.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(WatchTheme.textPrimary)
                                Spacer()
                                Text("\(WatchFormat.distance(waypoint.distanceAlongRoute)) \(WatchFormat.units.distanceUnit)")
                                    .font(.metric(10))
                                    .foregroundStyle(WatchTheme.textSecondary)
                            }
                        }
                    }
                    .padding(9)
                    .watchPanel()
                }

                Button {
                    onStart(route)
                    dismiss()
                } label: {
                    TrekkaLabel("Navigate", glyph: .navigate, size: WatchDisplay.scaled(13, atLeast: 12))
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchTheme.accent)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle(route.name)
    }
}

/// Human file sizes for the watch's storage readouts.
nonisolated enum WatchByteText {
    static func format(_ bytes: Int) -> String {
        guard bytes > 0 else { return "0 MB" }
        let megabytes = Double(bytes) / 1_000_000
        if megabytes < 1 { return "\(max(1, Int((Double(bytes) / 1000).rounded()))) KB" }
        if megabytes < 10 { return String(format: "%.1f MB", megabytes) }
        return "\(Int(megabytes.rounded())) MB"
    }
}
