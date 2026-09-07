import SwiftUI
import CoreLocation

/// Offline maps, managed on the wrist.
///
/// The watch could previously only receive ground the phone had fetched for it,
/// which fails in exactly the case the feature exists for — the phone left at
/// home, or flat. So the download lives here too, over the watch's own radio.
///
/// Everything shown is read from the files actually on this watch. A map the
/// phone believes it sent but which never landed does not appear here, which is
/// the entire point: this screen is the truth about what the wrist is carrying.
struct OfflineMapsWatchView: View {
    @Environment(WatchMapPackStore.self) private var packs
    @Environment(WatchRouteStore.self) private var routeStore
    @Environment(WatchMapDownloader.self) private var downloader

    @State private var location = PreflightLocation()
    @State private var radiusKilometres: Double = 3
    @State private var showsClearConfirmation = false

    var body: some View {
        List {
            summarySection

            if downloader.phase.isBusy {
                progressSection
            } else if case .finished(let message) = downloader.phase {
                statusSection(message, tint: WatchTheme.positive)
            } else if case .failed(let message) = downloader.phase {
                statusSection(message, tint: WatchTheme.danger)
            }

            aroundMeSection
            routesSection

            if packs.hasPacks {
                storedSection
            }
        }
        .navigationTitle("Offline maps")
        .onAppear { location.start() }
        .onDisappear { location.stop() }
        .confirmationDialog(
            "Delete every stored map?",
            isPresented: $showsClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete all", role: .destructive) { packs.deleteAll() }
            Button("Keep them", role: .cancel) {}
        }
    }

    // MARK: - Summary

    private var summarySection: some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(packs.hasPacks ? packs.totalSizeDescription : "Nothing stored")
                        .font(.metric(17, weight: .semibold))
                        .foregroundStyle(WatchTheme.textPrimary)
                    Text("\(packs.packs.count) of \(packs.packLimit) maps")
                        .font(.system(size: 9))
                        .foregroundStyle(WatchTheme.textSecondary)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(packs.freeSizeDescription)
                        .font(.metric(12, weight: .semibold))
                        .foregroundStyle(WatchTheme.textPrimary)
                    Text("free")
                        .font(.system(size: 9))
                        .foregroundStyle(WatchTheme.textSecondary)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var progressSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(progressLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(WatchTheme.textPrimary)
                ProgressView(value: downloader.phase.fraction)
                    .tint(WatchTheme.accent)
                Button("Stop") { downloader.cancel() }
                    .font(.system(size: 10, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(WatchTheme.danger)
            }
            .padding(.vertical, 2)
        } footer: {
            Text("Keep this screen on until it finishes. The download stops if the app closes.")
                .font(.system(size: 9))
        }
    }

    private var progressLabel: String {
        switch downloader.phase {
        case .planning: "Working out which ground to keep…"
        case .downloading(let completed, let total): "Tile \(completed) of \(total)"
        case .writing: "Saving to your watch…"
        default: "Working…"
        }
    }

    private func statusSection(_ message: String, tint: Color) -> some View {
        Section {
            Button {
                downloader.clearStatus()
            } label: {
                Text(message)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(tint)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Around me

    private var aroundMeSection: some View {
        Section {
            Stepper(value: $radiusKilometres, in: 1...6, step: 1) {
                Text("\(WatchFormat.decimal(radiusKilometres * 2, places: 0)) km across")
                    .font(.system(size: 11, weight: .semibold))
            }

            Button {
                startAreaDownload()
            } label: {
                TrekkaLabel("Download around me", glyph: .compass, size: 12)
                    .font(.system(size: 11, weight: .semibold))
            }
            .disabled(downloader.isBusy || location.coordinate == nil)

            if location.coordinate == nil {
                Text(location.isDenied
                     ? "Location is off for Trekka, so the watch cannot tell where to download."
                     : location.statusText)
                    .font(.system(size: 9))
                    .foregroundStyle(WatchTheme.textSecondary)
            }
        } header: {
            Text("Where you are")
        } footer: {
            Text("Downloads over Wi‑Fi or your watch's own signal. A few kilometres takes a couple of minutes.")
                .font(.system(size: 9))
        }
    }

    // MARK: - Routes

    @ViewBuilder
    private var routesSection: some View {
        Section {
            if routeStore.routes.isEmpty {
                Text("No routes on your watch yet. Send one from Trekka on your iPhone.")
                    .font(.system(size: 10))
                    .foregroundStyle(WatchTheme.textSecondary)
            } else {
                ForEach(routeStore.routes) { route in
                    routeRow(route)
                }
            }
        } header: {
            Text("Your routes")
        }
    }

    private func routeRow(_ route: WatchRoute) -> some View {
        let stored = packs.pack(forRoute: route.id)
        let isActive = downloader.activeRouteID == route.id && downloader.isBusy

        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(route.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WatchTheme.textPrimary)
                    .lineLimit(1)
                if let stored {
                    Text("\(stored.sizeDescription) · \(stored.tileCount) tiles")
                        .font(.metric(9, weight: .medium))
                        .foregroundStyle(WatchTheme.positive)
                } else {
                    Text("\(WatchFormat.distance(route.distance)) \(WatchFormat.units.distanceUnit) · no map")
                        .font(.metric(9, weight: .medium))
                        .foregroundStyle(WatchTheme.textSecondary)
                }
            }

            Spacer(minLength: 0)

            if isActive {
                ProgressView()
                    .controlSize(.mini)
            } else if let stored {
                Button {
                    packs.delete(packID: stored.id)
                } label: {
                    TrekkaIcon(.trash, size: 12, tint: WatchTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete the map for \(route.name)")
            } else {
                Button {
                    downloader.download(route: route)
                } label: {
                    Text("Get")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(WatchTheme.canvas)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(WatchTheme.accent, in: .capsule)
                }
                .buttonStyle(.plain)
                .disabled(downloader.isBusy)
                .accessibilityLabel("Download the map for \(route.name)")
            }
        }
        .padding(.vertical, 1)
    }

    // MARK: - Stored

    private var storedSection: some View {
        Section {
            ForEach(packs.packs) { pack in
                HStack(spacing: 8) {
                    TrekkaIcon(pack.kind == .route ? .route : .compass, size: 11, tint: WatchTheme.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(pack.name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(WatchTheme.textPrimary)
                            .lineLimit(1)
                        Text(packs.isLocal(packID: pack.id) ? "Downloaded here" : "From your iPhone")
                            .font(.system(size: 9))
                            .foregroundStyle(WatchTheme.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Text(pack.sizeDescription)
                        .font(.metric(10, weight: .semibold))
                        .foregroundStyle(WatchTheme.textSecondary)
                }
                .swipeActions {
                    Button(role: .destructive) {
                        packs.delete(packID: pack.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }

            Button(role: .destructive) {
                showsClearConfirmation = true
            } label: {
                Text("Delete all maps")
                    .font(.system(size: 11, weight: .semibold))
            }
        } header: {
            Text("Stored on this watch")
        } footer: {
            Text("The oldest map is dropped automatically once there are more than \(packs.packLimit).")
                .font(.system(size: 9))
        }
    }

    // MARK: - Actions

    private func startAreaDownload() {
        guard let centre = location.coordinate else { return }
        downloader.downloadArea(
            centre: centre,
            radiusMetres: radiusKilometres * 1_000,
            name: "Around me"
        )
    }
}
