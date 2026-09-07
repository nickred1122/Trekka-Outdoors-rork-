import SwiftUI

/// What the Apple Watch is actually carrying.
///
/// Everything here is reported by the watch itself. The phone deliberately does
/// not infer it from what it once sent, because those are different facts: a
/// transfer can fail, the watch drops its oldest map when space runs short, and
/// the watch can now download maps on its own that the phone has never seen.
/// Showing the phone's assumptions instead of the watch's contents is precisely
/// how an athlete ends up on a hillside with a map they were told they had.
struct WatchMapsView: View {
    @Environment(MapPackStore.self) private var mapPacks
    @State private var link = WatchLink.shared
    @State private var feedback = 0

    private var inventory: WatchInventory? { link.watchInventory }

    /// Maps on the phone that the watch is not holding. Home areas are excluded
    /// deliberately: they are the phone's own convenience cache, and the watch's
    /// storage is better spent on the route being walked.
    private var missingFromWatch: [MapCoverage] {
        mapPacks.coverage.filter { entry in
            entry.kind != .home && inventory?.hasPack(id: entry.id) != true
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                connectionCard

                if let inventory {
                    storageCard(inventory)

                    if !inventory.packs.isEmpty {
                        packsSection(inventory)
                    }

                    if !inventory.routes.isEmpty {
                        routesSection(inventory)
                    }
                }

                if !missingFromWatch.isEmpty {
                    missingSection
                }

                footnote
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(Theme.canvas)
        .navigationTitle("On your watch")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: feedback)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    link.requestInventory()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(!isConnected)
                .accessibilityLabel("Ask the watch what it is carrying")
            }
        }
        .task {
            link.requestInventory()
        }
    }

    private var isConnected: Bool {
        link.isPaired && link.isWatchAppInstalled
    }

    // MARK: - Connection

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: isConnected ? "applewatch.radiowaves.left.and.right" : "applewatch.slash")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isConnected ? Theme.positive : Theme.textPrimary.opacity(0.4))
                    .frame(width: 38, height: 38)
                    .background(Theme.surfaceRaised, in: .rect(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(connectionTitle)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(connectionDetail)
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if link.outstandingTransferCount > 0 {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.accent)
                    Text("\(link.outstandingTransferCount) map\(link.outstandingTransferCount == 1 ? "" : "s") still crossing to the watch")
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                }
            }
        }
        .padding(16)
        .panel()
    }

    private var connectionTitle: String {
        if !link.isPaired { return "No Apple Watch paired" }
        if !link.isWatchAppInstalled { return "Trekka isn't on your watch" }
        return link.isReachable ? "Connected" : "Paired, not in range"
    }

    private var connectionDetail: String {
        if !link.isPaired {
            return "Pair an Apple Watch to keep maps on your wrist."
        }
        if !link.isWatchAppInstalled {
            return "Install Trekka on your watch from the Watch app on this iPhone."
        }
        guard let reported = inventory?.reportedAt else {
            return "Waiting for your watch to report what it is carrying. Open Trekka on your wrist."
        }
        return "Last reported \(reported.formatted(.relative(presentation: .named)))."
    }

    // MARK: - Storage

    private func storageCard(_ inventory: WatchInventory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(inventory.packs.isEmpty ? "Nothing stored" : inventory.packBytesDescription)
                    .font(.metric(30))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(inventory.freeBytesDescription)
                        .font(.system(.caption, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary.opacity(0.7))
                    Text("free on watch")
                        .font(.caption2)
                        .foregroundStyle(Theme.textPrimary.opacity(0.45))
                }
            }

            Text("\(inventory.packs.count) of \(inventory.packLimit) maps · \(inventory.routes.count) route\(inventory.routes.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
        }
        .padding(16)
        .panel()
    }

    // MARK: - Packs

    private func packsSection(_ inventory: WatchInventory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Maps on the watch", trailing: inventory.packBytesDescription)

            VStack(spacing: 0) {
                ForEach(Array(inventory.packs.enumerated()), id: \.element.id) { index, pack in
                    if index > 0 { divider }
                    packRow(pack)
                }
            }
            .panel()

            Text("Maps downloaded on the wrist stay on the wrist — they are not copied back to your phone.")
                .font(.caption2)
                .foregroundStyle(Theme.textPrimary.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    private func packRow(_ pack: WatchPackReport) -> some View {
        HStack(spacing: 12) {
            TrekkaIcon(pack.kind == MapPackKind.route.rawValue ? .route : .compass, size: 15, tint: Theme.accent)
                .frame(width: 34, height: 34)
                .background(Theme.surfaceRaised, in: .rect(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text(pack.name)
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text("\(pack.tileCount) tiles")
                        .monospacedDigit()
                    if pack.isLocal {
                        Text("· downloaded on watch")
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
            }

            Spacer(minLength: 0)

            Text(pack.sizeDescription)
                .font(.system(.caption, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary.opacity(0.7))

            Button {
                link.requestPackDeletion(packID: pack.id)
                feedback += 1
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.textPrimary.opacity(0.35))
            }
            .buttonStyle(.plain)
            .disabled(!isConnected)
            .accessibilityLabel("Remove \(pack.name) from the watch")
        }
        .padding(12)
    }

    // MARK: - Routes

    private func routesSection(_ inventory: WatchInventory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                "Routes on the watch",
                trailing: "\(inventory.routes.filter(\.hasStoredMap).count) with maps"
            )

            VStack(spacing: 0) {
                ForEach(Array(inventory.routes.enumerated()), id: \.element.id) { index, route in
                    if index > 0 { divider }
                    routeRow(route)
                }
            }
            .panel()
        }
    }

    private func routeRow(_ route: WatchRouteReport) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
                .frame(width: 34, height: 34)
                .background(Theme.surfaceRaised, in: .rect(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text(route.name)
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("\(Formatters.distance(route.distanceMetres)) \(Formatters.units.distanceUnit)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
            }

            Spacer(minLength: 0)

            if route.hasStoredMap {
                Label("Map stored", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.positive)
                    .accessibilityLabel("Map stored for \(route.name)")
            } else {
                Text("No map")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.4))
            }
        }
        .padding(12)
    }

    // MARK: - Missing

    private var missingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("On this phone only", trailing: "\(missingFromWatch.count)")

            VStack(spacing: 0) {
                ForEach(Array(missingFromWatch.enumerated()), id: \.element.id) { index, pack in
                    if index > 0 { divider }
                    missingRow(pack)
                }
            }
            .panel()

            if let block = mapPacks.lastSendBlock {
                Text(block.message)
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }

            Button {
                mapPacks.sendMissingToWatch()
                feedback += 1
            } label: {
                Text("Send all to watch")
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.canvas)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(isConnected ? Theme.accent : Theme.textPrimary.opacity(0.25), in: .rect(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(!isConnected)
        }
    }

    private func missingRow(_ pack: MapCoverage) -> some View {
        let state = link.packTransfers[pack.id]

        return HStack(spacing: 12) {
            TrekkaIcon(pack.kind == .route ? .route : .compass, size: 15, tint: Theme.textPrimary.opacity(0.5))
                .frame(width: 34, height: 34)
                .background(Theme.surfaceRaised, in: .rect(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text(pack.name)
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(sendDetail(for: state, pack: pack))
                    .font(.caption)
                    .foregroundStyle(detailTint(for: state))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            if state?.isSending == true {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.accent)
            } else {
                Button {
                    mapPacks.sendToWatch(coverageID: pack.id)
                    feedback += 1
                } label: {
                    Text("Send")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(Theme.accent.opacity(0.14), in: .capsule)
                }
                .buttonStyle(.plain)
                .disabled(!isConnected)
                .accessibilityLabel("Send \(pack.name) to the watch")
            }
        }
        .padding(12)
    }

    private func sendDetail(for state: WatchPackTransfer?, pack: MapCoverage) -> String {
        switch state {
        case .sending:
            "Crossing to the watch. This carries on in the background."
        case .failed(let message):
            message
        case .delivered, .none:
            // Coverage on the phone shares its ground with everything else on
            // the map, so it has no size of its own to quote. The size the
            // watch reports once it holds a copy is a real file, and that is
            // shown in the list above.
            "\(pack.tileCount) pieces of ground"
        }
    }

    private func detailTint(for state: WatchPackTransfer?) -> Color {
        if case .failed = state { return Theme.danger }
        return Theme.textPrimary.opacity(0.55)
    }

    // MARK: - Furniture

    private func sectionHeader(_ title: String, trailing: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(trailing)
                .font(.system(.caption, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
        }
    }

    private var footnote: some View {
        Text("Your watch reports this itself, so it is what is genuinely on the wrist rather than what this phone believes it sent. You can also download maps directly on the watch, in Trekka's watch settings.")
            .font(.caption2)
            .foregroundStyle(Theme.textPrimary.opacity(0.4))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: 1)
            .padding(.leading, 12)
    }
}
