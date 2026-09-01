import SwiftUI
import UniformTypeIdentifiers

/// Library filter shown above the route list. `all` exists so an imported route
/// is never hidden behind the wrong tab.
nonisolated enum RouteFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case mine
    case imported
    case shared

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .mine: "Mine"
        case .imported: "Imported"
        case .shared: "Shared"
        }
    }

    var symbol: String {
        switch self {
        case .all: "square.grid.2x2"
        case .mine: "person.fill"
        case .imported: "square.and.arrow.down"
        case .shared: "person.2.fill"
        }
    }

    var source: RouteSource? {
        switch self {
        case .all: nil
        case .mine: .mine
        case .imported: .imported
        case .shared: .shared
        }
    }
}

struct RoutesView: View {
    @Environment(RouteStore.self) private var store
    @Environment(MapPackStore.self) private var mapPacks
    @Binding var path: NavigationPath

    @State private var draft = RouteDraftModel()
    @State private var filter: RouteFilter = .all
    @State private var selectedRouteID: UUID?
    @State private var showsImporter = false
    @State private var recenterToken = 0
    @State private var locateToken = 0
    @State private var toolFeedback = 0
    @State private var baseStyle: TopoBaseStyle = .trekka
    @State private var notice: ImportNotice?
    /// Set to open the full-screen builder — `nil` route means a new one.
    @State private var builder: BuilderRequest?

    /// Identifies a builder presentation, so a new route and an edit both work
    /// through the same sheet.
    private struct BuilderRequest: Identifiable {
        let id = UUID()
        let route: PlannedRoute?
    }

    private var visibleRoutes: [PlannedRoute] {
        let all = store.routes.sorted { $0.createdAt > $1.createdAt }
        guard let source = filter.source else { return all }
        return all.filter { $0.source == source }
    }

    private var selectedRoute: PlannedRoute? {
        if let selectedRouteID, let match = store.route(id: selectedRouteID) { return match }
        return visibleRoutes.first
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    mapCanvas

                    VStack(spacing: 14) {
                        browsePanel
                        savedRoutesSection
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, TabBarMetrics.scrollInset)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.canvas)
        .sensoryFeedback(.selection, trigger: toolFeedback)
        .animation(.snappy(duration: 0.25), value: filter)
        .fullScreenCover(item: $builder) { request in
            RouteBuilderView(editing: request.route) { saved in
                filter = .all
                selectedRouteID = saved.id
                recenterToken += 1
                path.append(RouteDestination.route(saved.id))
            }
        }
        .onChange(of: selectedRouteID) { _, _ in
            recenterToken += 1
        }
        .onChange(of: filter) { _, _ in
            // Keep the map on a route that is actually in the current list.
            if let id = selectedRouteID, visibleRoutes.contains(where: { $0.id == id }) { return }
            selectedRouteID = visibleRoutes.first?.id
        }
        .task(id: notice?.id) {
            guard notice != nil else { return }
            try? await Task.sleep(for: .seconds(7))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { notice = nil }
        }
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: gpxContentTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { importRoute(from: url) }
            case .failure:
                draft.importError = "The file could not be opened."
            }
        }
        .alert(
            "Import failed",
            isPresented: Binding(
                get: { draft.importError != nil },
                set: { if !$0 { draft.importError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { draft.importError = nil }
        } message: {
            Text(draft.importError ?? "")
        }
    }

    // MARK: - Map

    private var mapCanvas: some View {
        TrekkaMapSurface(
            routePoints: selectedRoute?.points ?? [],
            waypoints: selectedRoute?.waypoints ?? [],
            baseStyle: baseStyle,
            isInteractive: true,
            recenterToken: recenterToken,
            locateToken: locateToken
        )
        .frame(height: 420)
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, Theme.canvas.opacity(0.55), Theme.canvas],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 150)
            .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) { mapControls }
        .overlay(alignment: .topLeading) { mapBadge }
        .overlay(alignment: .bottom) {
            if !visibleRoutes.isEmpty {
                routeCarousel
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)
        }
    }

    private var mapControls: some View {
        VStack(spacing: 8) {
            // Being located and framing the route are different requests; one
            // button doing only the latter is why locating looked broken.
            mapButton(symbol: "location.fill", label: "Show my location") {
                MapLocationService.shared.requestAccess()
                locateToken += 1
                toolFeedback += 1
            }
            mapButton(
                symbol: "arrow.down.backward.and.arrow.up.forward",
                label: "Fit route on map"
            ) {
                recenterToken += 1
                toolFeedback += 1
            }
            mapButton(symbol: baseStyle.symbol, label: "Switch base map") {
                baseStyle = baseStyle.next
                toolFeedback += 1
            }
            if let route = selectedRoute {
                mapButton(symbol: "pencil.and.outline", label: "Edit this route") {
                    builder = BuilderRequest(route: route)
                    toolFeedback += 1
                }
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var mapBadge: some View {
        if let route = selectedRoute {
            HStack(spacing: 6) {
                Text(route.name)
                    .font(.system(.caption, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(Theme.mapControlLabel)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Theme.mapControl, in: .capsule)
            .overlay { Capsule().strokeBorder(Theme.mapControlBorder, lineWidth: 1) }
            .padding(12)
            .frame(maxWidth: 220, alignment: .leading)
        }
    }

    /// Swipe the deck to flip the map between every route in the library.
    private var routeCarousel: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(visibleRoutes) { route in
                    carouselCard(route)
                        .id(route.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $selectedRouteID, anchor: .center)
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .frame(height: 96)
    }

    private func carouselCard(_ route: PlannedRoute) -> some View {
        let isSelected = route.id == selectedRoute?.id
        return Button {
            if isSelected {
                path.append(RouteDestination.route(route.id))
            } else {
                withAnimation(.snappy(duration: 0.3)) { selectedRouteID = route.id }
            }
            toolFeedback += 1
        } label: {
            HStack(spacing: 10) {
                RouteThumbnail(points: route.points, showsContours: false)
                    .frame(width: 58, height: 58)
                    .clipShape(.rect(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(route.name)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text("\(Formatters.distance(route.distance)) \(Formatters.units.distanceUnit) · \(Formatters.elevation(route.elevationGain)) \(Formatters.units.elevationUnit) ↑")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                    Label(isSelected ? "Open route" : "Show on map", systemImage: isSelected ? "chevron.right" : "scope")
                        .font(.system(size: 10, weight: .bold))
                        .labelStyle(TrailingIconLabelStyle())
                        .foregroundStyle(Theme.accent)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(width: 248, height: 78)
            .background(Theme.mapPanel, in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isSelected ? Theme.accent : Theme.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Browse panel

    private var browsePanel: some View {
        VStack(spacing: 12) {
            if let notice {
                importNoticeCard(notice)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            filterChips

            HStack(spacing: 10) {
                Button {
                    builder = BuilderRequest(route: nil)
                    toolFeedback += 1
                } label: {
                    Label("Build a route", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.system(.subheadline, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .foregroundStyle(Theme.canvas)
                        .background(Theme.accent, in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                Button {
                    showsImporter = true
                } label: {
                    Label("Import GPX", systemImage: "square.and.arrow.down")
                        .font(.system(.subheadline, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .foregroundStyle(Theme.accent)
                        .background(Theme.surface, in: .rect(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }

            offlineMapsRow
        }
    }

    /// The one way into map management. Offline maps used to be listed in
    /// Settings, a tab away from the routes they belong to; they live here now,
    /// beside the library they cover.
    private var offlineMapsRow: some View {
        Button {
            path.append(RouteDestination.maps)
            toolFeedback += 1
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "square.and.arrow.down.on.square.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 32, height: 32)
                    .background(Theme.surfaceRaised, in: .rect(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 1) {
                    Text("Offline maps")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(offlineMapsDetail)
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if mapPacks.progress.isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.accent)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.3))
                }
            }
            .padding(10)
            .panel(radius: 14)
        }
        .buttonStyle(.plain)
    }

    private var offlineMapsDetail: String {
        guard !mapPacks.packs.isEmpty else {
            return "Keep ground on your phone and watch for no signal"
        }
        let stored = store.routes.filter { mapPacks.hasPack(forRoute: $0.id) }.count
        let routePart = stored > 0 ? "\(stored) route\(stored == 1 ? "" : "s") covered · " : ""
        return "\(routePart)\(mapPacks.totalSizeDescription) stored"
    }

    private var filterChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(RouteFilter.allCases) { value in
                    let count = value.source.map { source in store.routes.filter { $0.source == source }.count }
                        ?? store.routes.count
                    Button {
                        filter = value
                        toolFeedback += 1
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: value.symbol)
                                .font(.system(size: 11, weight: .bold))
                            Text(value.title)
                                .font(.system(.caption, weight: .semibold))
                            Text("\(count)")
                                .font(.system(size: 10, weight: .bold))
                                .monospacedDigit()
                                .opacity(0.6)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(filter == value ? Theme.accent.opacity(0.16) : Theme.surface, in: .capsule)
                        .overlay {
                            Capsule().strokeBorder(filter == value ? Theme.accent : Theme.border, lineWidth: 1)
                        }
                        .foregroundStyle(filter == value ? Theme.accent : Theme.textPrimary.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(filter == value ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 0, for: .scrollContent)
    }

    private func importNoticeCard(_ notice: ImportNotice) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(Theme.positive)

            VStack(alignment: .leading, spacing: 2) {
                Text("Imported \(notice.name)")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("\(Formatters.distance(notice.distance)) \(Formatters.units.distanceUnit) · \(notice.waypointCount) waypoint\(notice.waypointCount == 1 ? "" : "s") · saved to your library")
                    .font(.caption2)
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)

            Button("Open") {
                path.append(RouteDestination.route(notice.routeID))
            }
            .font(.system(.caption, weight: .bold))
            .foregroundStyle(Theme.accent)
        }
        .padding(12)
        .panel(radius: 14)
    }

    // MARK: - Library list

    private var savedRoutesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(filter == .all ? "All routes" : filter.title)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(visibleRoutes.count)")
                    .font(.system(.caption, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
            }

            if visibleRoutes.isEmpty {
                Text(emptyMessage)
                    .font(.caption)
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .panel()
            } else {
                ForEach(visibleRoutes) { route in
                    Button {
                        path.append(RouteDestination.route(route.id))
                    } label: {
                        RouteRow(route: route, isSelected: route.id == selectedRoute?.id)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            selectedRouteID = route.id
                        } label: {
                            Label("Show on map", systemImage: "scope")
                        }
                        Button {
                            builder = BuilderRequest(route: route)
                        } label: {
                            Label("Edit on the map", systemImage: "pencil.and.outline")
                        }
                        Button(role: .destructive) {
                            if selectedRouteID == route.id { selectedRouteID = nil }
                            store.delete(routeID: route.id)
                        } label: {
                            Label("Delete route", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .padding(.top, 2)
    }

    private var emptyMessage: String {
        switch filter {
        case .all: "Build a route or import a GPX file to start your library."
        case .mine: "Routes you build appear here."
        case .imported: "Import a .gpx file to add routes from your other devices."
        case .shared: "Routes shared with you by other athletes appear here."
        }
    }

    // MARK: - Helpers

    private func mapButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.mapControlLabel)
                .frame(width: 44, height: 44)
                .background(Theme.mapControl, in: .rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Theme.mapControlBorder, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var gpxContentTypes: [UTType] {
        var types: [UTType] = [.xml, .data]
        if let gpx = UTType(filenameExtension: "gpx") {
            types.insert(gpx, at: 0)
        }
        return types
    }

    /// Imported routes are saved straight into the library so they can be opened,
    /// exported and sent to the watch like any other route.
    private func importRoute(from url: URL) {
        guard var route = draft.route(fromGPX: url) else { return }
        route.source = .imported
        store.add(route)

        filter = .all
        selectedRouteID = route.id
        recenterToken += 1
        toolFeedback += 1
        withAnimation(.snappy) {
            notice = ImportNotice(
                routeID: route.id,
                name: route.name,
                distance: route.distance,
                waypointCount: route.waypoints.count
            )
        }
    }
}

/// Transient confirmation shown after a GPX file lands in the library.
private struct ImportNotice: Identifiable, Equatable {
    let id = UUID()
    let routeID: UUID
    let name: String
    let distance: Double
    let waypointCount: Int
}

/// Row summarising a saved route in the Routes list.
struct RouteRow: View {
    let route: PlannedRoute
    var isSelected: Bool = false

    @Environment(MapPackStore.self) private var mapPacks

    var body: some View {
        HStack(spacing: 14) {
            RouteThumbnail(points: route.points)
                .frame(width: 76, height: 68)
                .clipShape(.rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 5) {
                Text(route.name)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("\(Formatters.distance(route.distance)) \(Formatters.units.distanceUnit) · \(Formatters.elevation(route.elevationGain)) \(Formatters.units.elevationUnit) ↑ · \(Formatters.compactDuration(route.estimatedDuration))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                HStack(spacing: 8) {
                    Text(route.activity.rawValue.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(Theme.accent)
                    if route.isSyncedToWatch {
                        Label("On watch", systemImage: "applewatch")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.zoneColors[1])
                    }
                    // Read from the packs on disk rather than a stored flag, so
                    // the mark cannot claim ground the athlete does not have.
                    if mapPacks.hasPack(forRoute: route.id) {
                        Label("Map offline", systemImage: "arrow.down.circle.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.positive)
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary.opacity(0.35))
        }
        .padding(10)
        .background(Theme.surface, in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isSelected ? Theme.accent.opacity(0.8) : Theme.border, lineWidth: 1)
        }
    }
}
