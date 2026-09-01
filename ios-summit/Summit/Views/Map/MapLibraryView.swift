import SwiftUI

/// One place for everything Trekka keeps on the ground.
///
/// This was split in two before: routes lived on the Routes tab, and the list
/// of downloaded packs sat in Settings. Deciding whether to clear space meant
/// visiting two screens that each knew half the answer. Everything is here now
/// — which routes have their map, which squares were kept by hand, what the
/// watch is carrying, and exactly what all of it occupies.
///
/// Every size is read from the file on disk. An athlete freeing space the night
/// before a trip is badly served by an estimate.
struct MapLibraryView: View {
    @Environment(RouteStore.self) private var store
    @Environment(MapPackStore.self) private var mapPacks

    @State private var showsAreaDownload = false
    @State private var showsClearConfirmation = false
    @State private var feedback = 0

    private var routes: [PlannedRoute] {
        store.routes.sorted { $0.createdAt > $1.createdAt }
    }

    /// Route corridors whose route has since been deleted. Rare, but they still
    /// occupy space, so they are shown rather than quietly held.
    private var orphanedRoutePacks: [MapPackSummary] {
        mapPacks.routePacks.filter { pack in
            guard let routeID = pack.routeID else { return true }
            return store.route(id: routeID) == nil
        }
    }

    private var storedRouteCount: Int {
        routes.filter { mapPacks.hasPack(forRoute: $0.id) }.count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                summaryCard

                if mapPacks.progress.isBusy {
                    progressCard
                }

                areaDownloadButton

                routesSection

                if !mapPacks.areaPacks.isEmpty {
                    packSection(
                        title: "Areas you kept",
                        caption: "Squares of ground you chose on the map.",
                        packs: mapPacks.areaPacks
                    )
                }

                if !mapPacks.homePacks.isEmpty {
                    packSection(
                        title: "Kept ready for you",
                        caption: "Where you usually set off from, cached in the background so a spontaneous outing is already covered.",
                        packs: mapPacks.homePacks
                    )
                }

                if !orphanedRoutePacks.isEmpty {
                    packSection(
                        title: "Routes since deleted",
                        caption: "The route is gone but its ground is still stored.",
                        packs: orphanedRoutePacks
                    )
                }

                if !mapPacks.packs.isEmpty {
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
        .navigationTitle("Offline maps")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: feedback)
        .sheet(isPresented: $showsAreaDownload) {
            NavigationStack { AreaDownloadView() }
        }
        .confirmationDialog(
            "Delete every offline map?",
            isPresented: $showsClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete all maps", role: .destructive) {
                mapPacks.deleteAll()
                feedback += 1
            }
            Button("Keep them", role: .cancel) {}
        } message: {
            Text("Your routes stay. Only the downloaded ground goes, and you will need a signal to see the map again.")
        }
    }

    // MARK: - Summary

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(mapPacks.packs.isEmpty ? "Nothing stored" : mapPacks.totalSizeDescription)
                    .font(.metric(30))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                Text("\(mapPacks.packs.count) map\(mapPacks.packs.count == 1 ? "" : "s")")
                    .font(.system(.caption, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
            }

            if !mapPacks.packs.isEmpty {
                storageBar
                legend
            } else {
                Text("Send a route to your watch and its map comes down with it, so the ground is there when the signal is not. You can also keep any square of ground you like.")
                    .font(.caption)
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .panel()
    }

    /// Real bytes, split by what the ground was kept for.
    private var storageBar: some View {
        GeometryReader { proxy in
            let total = max(1, mapPacks.totalBytes)
            let width = proxy.size.width

            HStack(spacing: 2) {
                ForEach(barSegments, id: \.kind) { segment in
                    Capsule()
                        .fill(colour(for: segment.kind))
                        .frame(width: max(2, width * Double(segment.bytes) / Double(total)) - 2)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 8)
    }

    private var barSegments: [(kind: MapPackKind, bytes: Int)] {
        [MapPackKind.route, .area, .home].compactMap { kind in
            let bytes = mapPacks.packs.filter { $0.kind == kind }.reduce(0) { $0 + $1.fileBytes }
            return bytes > 0 ? (kind, bytes) : nil
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach(barSegments, id: \.kind) { segment in
                HStack(spacing: 5) {
                    Circle()
                        .fill(colour(for: segment.kind))
                        .frame(width: 7, height: 7)
                    Text("\(label(for: segment.kind)) \(MapPackFormat.describe(bytes: segment.bytes))")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func colour(for kind: MapPackKind) -> Color {
        switch kind {
        case .route: Theme.accent
        case .area: Theme.highlight
        case .home: Theme.zoneColors[1]
        }
    }

    private func label(for kind: MapPackKind) -> String {
        switch kind {
        case .route: "Routes"
        case .area: "Areas"
        case .home: "Ready"
        }
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(progressLabel)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            ProgressView(value: mapPacks.progress.fraction)
                .tint(Theme.accent)
        }
        .padding(14)
        .panel()
    }

    private var progressLabel: String {
        switch mapPacks.progress {
        case .planning: "Working out which ground to keep…"
        case .downloading(let completed, let total): "Downloading \(completed) of \(total) tiles"
        case .writing: "Saving to your phone…"
        case .sendingToWatch: "Sending to your watch…"
        default: "Working…"
        }
    }

    // MARK: - Actions

    private var areaDownloadButton: some View {
        Button {
            showsAreaDownload = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "square.dashed.inset.filled")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.canvas)
                    .frame(width: 34, height: 34)
                    .background(Theme.accent, in: .rect(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Download an area")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Draw a square of ground and keep it")
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
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
        .disabled(mapPacks.progress.isBusy)
    }

    private var clearAllButton: some View {
        Button(role: .destructive) {
            showsClearConfirmation = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                Text("Delete all offline maps")
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
        Text("Maps have to be downloaded while you still have a connection. Sizes shown are the real files on your phone, not estimates.")
            .font(.caption2)
            .foregroundStyle(Theme.textPrimary.opacity(0.4))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    // MARK: - Routes

    private var routesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your routes")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(routes.isEmpty ? "None yet" : "\(storedRouteCount) of \(routes.count) stored")
                    .font(.system(.caption, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
            }

            if routes.isEmpty {
                Text("Build or import a route and you can keep its ground offline from here.")
                    .font(.caption)
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .panel()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(routes.enumerated()), id: \.element.id) { index, route in
                        if index > 0 { divider }
                        routeRow(route)
                    }
                }
                .panel()
            }
        }
    }

    private func routeRow(_ route: PlannedRoute) -> some View {
        let pack = mapPacks.pack(forRoute: route.id)
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
                HStack(spacing: 6) {
                    Text("\(Formatters.distance(route.distance)) \(Formatters.units.distanceUnit)")
                        .monospacedDigit()
                    if let pack {
                        Text("· \(pack.tileCount) tiles")
                            .monospacedDigit()
                    }
                    if route.isSyncedToWatch {
                        Image(systemName: "applewatch")
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
            }

            Spacer(minLength: 0)

            if isDownloading {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.accent)
            } else if let pack {
                Text(pack.sizeDescription)
                    .font(.system(.caption, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.positive)

                Button {
                    mapPacks.delete(packID: pack.id)
                    feedback += 1
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.textPrimary.opacity(0.35))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete the offline map for \(route.name)")
            } else {
                Button {
                    mapPacks.download(route: route)
                    feedback += 1
                } label: {
                    Text("Download")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(Theme.accent.opacity(0.14), in: .capsule)
                }
                .buttonStyle(.plain)
                .disabled(mapPacks.progress.isBusy)
                .accessibilityLabel("Download the offline map for \(route.name)")
            }
        }
        .padding(12)
    }

    // MARK: - Packs

    private func packSection(title: String, caption: String, packs: [MapPackSummary]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(MapPackFormat.describe(bytes: packs.reduce(0) { $0 + $1.fileBytes }))
                    .font(.system(.caption, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
            }

            VStack(spacing: 0) {
                ForEach(Array(packs.enumerated()), id: \.element.id) { index, pack in
                    if index > 0 { divider }
                    packRow(pack)
                }
            }
            .panel()

            Text(caption)
                .font(.caption2)
                .foregroundStyle(Theme.textPrimary.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    private func packRow(_ pack: MapPackSummary) -> some View {
        HStack(spacing: 12) {
            TrekkaIcon(pack.kind == .route ? .route : .compass, size: 15, tint: colour(for: pack.kind))
                .frame(width: 34, height: 34)
                .background(Theme.surfaceRaised, in: .rect(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text(pack.name)
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("\(pack.tileCount) tiles")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
            }

            Spacer(minLength: 0)

            Text(pack.sizeDescription)
                .font(.system(.caption, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary.opacity(0.7))

            Button {
                mapPacks.delete(packID: pack.id)
                feedback += 1
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.textPrimary.opacity(0.35))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(pack.name)")
        }
        .padding(12)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: 1)
            .padding(.leading, 12)
    }
}
