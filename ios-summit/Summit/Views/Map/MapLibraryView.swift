import SwiftUI

/// Trekka's one offline map, and everywhere it covers.
///
/// This screen used to list a separate download per route, which is how the
/// storage worked underneath. It no longer does: there is a single map, and the
/// routes and areas here are the places it has been asked to cover. That is why
/// sizes are shown once, at the top, and not against each row — after ground is
/// shared between overlapping routes, no honest number can be attributed to any
/// one of them.
struct MapLibraryView: View {
    @Environment(RouteStore.self) private var store
    @Environment(MapPackStore.self) private var mapPacks

    @State private var link = WatchLink.shared
    @State private var showsAreaDownload = false
    @State private var showsClearConfirmation = false
    @State private var feedback = 0

    private var routes: [PlannedRoute] {
        store.routes.sorted { $0.createdAt > $1.createdAt }
    }

    private var uncoveredRoutes: [PlannedRoute] {
        routes.filter { !mapPacks.covers(routeID: $0.id) && !$0.points.isEmpty }
    }

    private var coveredRouteCount: Int {
        routes.filter { mapPacks.covers(routeID: $0.id) }.count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                summaryCard

                if mapPacks.isWorking {
                    progressCard
                } else if case .failed(let message) = mapPacks.progress {
                    failureCard(message)
                }

                addSection

                watchButton

                if !mapPacks.chosenCoverage.isEmpty {
                    coveredSection
                }

                if !uncoveredRoutes.isEmpty {
                    uncoveredSection
                }

                if !mapPacks.homeCoverage.isEmpty {
                    homeSection
                }

                if !mapPacks.isEmpty {
                    clearAllButton
                }

                footnote
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(Theme.canvas)
        .navigationTitle("Offline map")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: feedback)
        .sheet(isPresented: $showsAreaDownload) {
            NavigationStack { AreaDownloadView() }
        }
        .confirmationDialog(
            "Delete your offline map?",
            isPresented: $showsClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete the map", role: .destructive) {
                mapPacks.removeAll()
                feedback += 1
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("Your routes stay. Only the downloaded ground goes, and you will need a signal to see the map again.")
        }
    }

    // MARK: - Summary

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(mapPacks.isEmpty ? "Nothing stored" : mapPacks.totalSizeDescription)
                    .font(.metric(30))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                if !mapPacks.isEmpty {
                    Text("one map")
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                }
            }

            if mapPacks.isEmpty {
                Text("One map covers everywhere you go. Add a route or a square of ground and it joins the same map, so places your routes share are only ever stored once.")
                    .font(.caption)
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(summaryDetail)
                    .font(.caption)
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .panel()
    }

    private var summaryDetail: String {
        let places = mapPacks.coverage.count
        let placePart = "\(places) place\(places == 1 ? "" : "s") covered"
        let routePart = routes.isEmpty
            ? ""
            : " · \(coveredRouteCount) of \(routes.count) route\(routes.count == 1 ? "" : "s")"
        return "\(placePart)\(routePart) · \(mapPacks.tileCount) pieces of ground, each stored once"
    }

    /// What is downloading, and what is lined up behind it.
    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let name = mapPacks.activeName {
                Text(name)
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            }

            Text(progressLabel)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary.opacity(0.7))

            ProgressView(value: mapPacks.progress.fraction)
                .tint(Theme.accent)

            if !mapPacks.queuedNames.isEmpty {
                Text("Then: \(mapPacks.queuedNames.joined(separator: " · "))")
                    .font(.caption2)
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                    .lineLimit(2)
            }

            Button(mapPacks.queuedNames.isEmpty ? "Stop" : "Stop everything") {
                mapPacks.cancel()
            }
            .font(.system(.caption, weight: .semibold))
            .foregroundStyle(Theme.textPrimary.opacity(0.6))

            // A big download is worth being honest about: it takes as long as it
            // takes, and leaving the screen does not stop it.
            Text("Keep Trekka open while this runs. Anything already downloaded is kept if you stop.")
                .font(.caption2)
                .foregroundStyle(Theme.textPrimary.opacity(0.4))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .panel()
    }

    private var progressLabel: String {
        switch mapPacks.progress {
        case .planning: "Working out what is missing…"
        case .downloading(let completed, let total):
            "\(completed) of \(total) pieces · \(Int((Double(completed) / Double(max(total, 1))) * 100))%"
        case .writing: "Adding it to your map…"
        case .sendingToWatch: "Sending to your watch…"
        case .ready, .alreadyCovered, .idle, .failed:
            mapPacks.queuedNames.isEmpty ? "Working…" : "Starting the next one…"
        }
    }

    private func failureCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.highlight)
            Text(message)
                .font(.caption)
                .foregroundStyle(Theme.textPrimary.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Dismiss") { mapPacks.clearStatus() }
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(Theme.accent)
        }
        .padding(14)
        .panel()
    }

    // MARK: - Actions

    /// The two ways ground gets onto the map, in one block rather than loose
    /// buttons stacked down the screen.
    private var addSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add ground")
                .metricLabelStyle()
                .padding(.leading, 4)

            VStack(spacing: 0) {
                areaDownloadButton
                if !uncoveredRoutes.isEmpty {
                    divider
                    coverEverythingButton
                }
            }
            .panel()

            if mapPacks.isWorking {
                Text("Downloads queue, so you can line up several places and leave it running.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textPrimary.opacity(0.45))
                    .padding(.leading, 4)
            }
        }
    }

    /// The one button that does what most people actually want: cover
    /// everywhere they go, in one go.
    private var coverEverythingButton: some View {
        Button {
            mapPacks.addAll(routes: routes)
            feedback += 1
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "square.stack.3d.down.right.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.canvas)
                    .frame(width: 34, height: 34)
                    .background(Theme.accent, in: .rect(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 1) {
                    Text(mapPacks.isEmpty ? "Cover all my routes" : "Add my other routes")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(coverEverythingDetail)
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.3))
            }
            .padding(12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var coverEverythingDetail: String {
        let count = uncoveredRoutes.count
        let noun = "\(count) route\(count == 1 ? "" : "s") not covered yet"
        guard !mapPacks.isEmpty else { return noun }
        return "\(noun) · ground they share with your map is already here"
    }

    private var areaDownloadButton: some View {
        Button {
            showsAreaDownload = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "square.dashed.inset.filled")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 34, height: 34)
                    .background(Theme.surfaceRaised, in: .rect(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Add an area or a region")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("A valley at full detail, or a whole state at road-atlas scale")
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.3))
            }
            .padding(12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// A way through to the watch's real contents.
    ///
    /// Kept as its own door rather than a section inlined here, because what is
    /// on the watch is reported by the watch and can differ from what this
    /// phone holds — conflating the two lists is what made the old screen
    /// quietly misleading.
    private var watchButton: some View {
        NavigationLink {
            WatchMapsView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "applewatch")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.canvas)
                    .frame(width: 34, height: 34)
                    .background(Theme.highlight, in: .rect(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 1) {
                    Text("On your watch")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(watchDetail)
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.3))
            }
            .padding(12)
            .panel()
        }
        .buttonStyle(.plain)
    }

    private var watchDetail: String {
        guard link.isPaired else { return "No Apple Watch paired" }
        guard link.isWatchAppInstalled else { return "Trekka isn't installed on your watch yet" }
        guard let inventory = link.watchInventory else {
            return "Open Trekka on your wrist to see what it is carrying"
        }
        if inventory.packs.isEmpty {
            return "No maps stored on the watch · \(inventory.routes.count) route\(inventory.routes.count == 1 ? "" : "s")"
        }
        return "\(inventory.packs.count) map\(inventory.packs.count == 1 ? "" : "s") · \(inventory.packBytesDescription) · \(inventory.freeBytesDescription) free"
    }

    private var clearAllButton: some View {
        Button(role: .destructive) {
            showsClearConfirmation = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                Text("Delete the whole map")
                    .font(.system(.subheadline, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.danger)
            .padding(14)
            .panel()
        }
        .buttonStyle(.plain)
    }

    private var footnote: some View {
        Text("Places that overlap share their ground, so the map grows by less than the sum of its parts. Ground has to be downloaded while you still have a connection, and the size shown is the real file on your phone.")
            .font(.caption2)
            .foregroundStyle(Theme.textPrimary.opacity(0.4))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    // MARK: - Covered

    private var coveredSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your map covers")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(mapPacks.chosenCoverage.count)")
                    .font(.system(.caption, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
            }

            VStack(spacing: 0) {
                ForEach(Array(mapPacks.chosenCoverage.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { divider }
                    coverageRow(entry)
                }
            }
            .panel()
        }
    }

    private func coverageRow(_ entry: MapCoverage) -> some View {
        let route = entry.routeID.flatMap { store.route(id: $0) }

        return HStack(spacing: 12) {
            if let route {
                RouteThumbnail(points: route.points, showsContours: false)
                    .frame(width: 44, height: 44)
                    .clipShape(.rect(cornerRadius: 9))
            } else {
                TrekkaIcon(icon(for: entry.kind), size: 15, tint: colour(for: entry.kind))
                    .frame(width: 44, height: 44)
                    .background(Theme.surfaceRaised, in: .rect(cornerRadius: 9))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(label(for: entry.kind))
                    Text("· \(entry.tileCount) pieces")
                        .monospacedDigit()
                    if isOnWatch(entry) {
                        Image(systemName: "applewatch")
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
            }

            Spacer(minLength: 0)

            // The phone has this ground but the watch does not, so offer to
            // send it. Nothing is re-downloaded: the copy is cut out of the
            // map already on the phone.
            if isMissingFromWatch(entry) {
                Button {
                    mapPacks.sendToWatch(coverageID: entry.id)
                    feedback += 1
                } label: {
                    Image(systemName: "applewatch.radiowaves.left.and.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Send \(entry.name) to the watch")
            }

            Button {
                mapPacks.remove(coverageID: entry.id)
                feedback += 1
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.textPrimary.opacity(0.35))
            }
            .buttonStyle(.plain)
            .disabled(mapPacks.progress.isBusy)
            .accessibilityLabel("Stop covering \(entry.name)")
        }
        .padding(12)
    }

    // MARK: - Not covered

    private var uncoveredSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Not covered yet")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(uncoveredRoutes.count)")
                    .font(.system(.caption, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
            }

            VStack(spacing: 0) {
                ForEach(Array(uncoveredRoutes.enumerated()), id: \.element.id) { index, route in
                    if index > 0 { divider }
                    uncoveredRow(route)
                }
            }
            .panel()
        }
    }

    private func uncoveredRow(_ route: PlannedRoute) -> some View {
        let isDownloading = mapPacks.activeRouteID == route.id && mapPacks.progress.isBusy

        return HStack(spacing: 12) {
            RouteThumbnail(points: route.points, showsContours: false)
                .frame(width: 44, height: 44)
                .clipShape(.rect(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text(route.name)
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(addDetail(for: route))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
            }

            Spacer(minLength: 0)

            if isDownloading {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.accent)
            } else {
                Button {
                    mapPacks.add(route: route)
                    feedback += 1
                } label: {
                    Text("Add")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .background(Theme.accent.opacity(0.14), in: .capsule)
                }
                .buttonStyle(.plain)
                .disabled(mapPacks.progress.isBusy)
                .accessibilityLabel("Add \(route.name) to your offline map")
            }
        }
        .padding(12)
    }

    /// What adding this route would actually cost, which is the point of the
    /// shared map: for a route over ground already kept, it can be nothing.
    private func addDetail(for route: PlannedRoute) -> String {
        let distance = "\(Formatters.distance(route.distance)) \(Formatters.units.distanceUnit)"
        guard !mapPacks.isEmpty else { return distance }
        let new = mapPacks.newTileCount(forRoute: route.coordinates)
        if new == 0 {
            return "\(distance) · already covered, adds nothing"
        }
        return "\(distance) · adds \(new) new pieces"
    }

    // MARK: - Kept ready

    private var homeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Kept ready for you")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(mapPacks.homeCoverage.count)")
                    .font(.system(.caption, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
            }

            VStack(spacing: 0) {
                ForEach(Array(mapPacks.homeCoverage.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { divider }
                    coverageRow(entry)
                }
            }
            .panel()

            Text("Where you usually set off from, added in the background so a spontaneous outing is already covered.")
                .font(.caption2)
                .foregroundStyle(Theme.textPrimary.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Helpers

    /// Whether the watch has said it is holding this ground. Only ever answered
    /// from the watch's own report; an unanswered watch is left alone rather
    /// than assumed empty.
    private func isOnWatch(_ entry: MapCoverage) -> Bool {
        guard let inventory = link.watchInventory else { return false }
        return inventory.hasPack(id: entry.id)
    }

    private func isMissingFromWatch(_ entry: MapCoverage) -> Bool {
        guard link.isPaired, link.isWatchAppInstalled else { return false }
        guard link.watchInventory != nil else { return false }
        return !isOnWatch(entry)
    }

    private func colour(for kind: MapCoverageKind) -> Color {
        switch kind {
        case .route: Theme.accent
        case .area: Theme.highlight
        case .home: Theme.zoneColors[1]
        }
    }

    private func icon(for kind: MapCoverageKind) -> TrekkaGlyph {
        kind == .route ? .route : .compass
    }

    private func label(for kind: MapCoverageKind) -> String {
        switch kind {
        case .route: "Route"
        case .area: "Area"
        case .home: "Starting area"
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: 1)
            .padding(.leading, 12)
    }
}
