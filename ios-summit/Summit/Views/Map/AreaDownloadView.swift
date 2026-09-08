import SwiftUI
import CoreLocation

/// Picks a square of ground to add to the offline map.
///
/// Until now the only ground that could be stored was a corridor along a saved
/// route, or the starting areas Trekka cached on its own. This is the athlete
/// choosing for themselves: pan to a place, size the square, see exactly what
/// it would add to the map, and keep it.
struct AreaDownloadView: View {
    @Environment(MapPackStore.self) private var mapPacks
    @Environment(UnitSettings.self) private var units
    @Environment(\.dismiss) private var dismiss

    /// Somewhere sensible to open, when the athlete's own position is unknown.
    var fallbackCentre: CLLocationCoordinate2D?

    @State private var cameraCentre: CLLocationCoordinate2D?
    @State private var radiusMetres: Double = 5_000
    @State private var name: String = ""
    @State private var suggestedName: String = ""
    @State private var locateToken = 0
    @State private var namingTask: Task<Void, Never>?

    /// Searching for somewhere by name, rather than panning to it.
    ///
    /// Panning from where you stand to a national park three states away is
    /// minutes of dragging, and it was the only way to aim this screen.
    @State private var query: String = ""
    @State private var search = PlaceSearchService.shared
    /// Moves the map when a search result is chosen. Separate from `focus`,
    /// which belongs to the locate button.
    @State private var searchFocus: TopoFocus?
    /// Counts chosen results, so two searches landing on the same place still
    /// each move the camera. A focus with an unchanged token is ignored.
    @State private var searchToken = 0
    /// Whether this square should also go to the wrist.
    ///
    /// It could not before: an area kept by hand stayed on the phone, with no
    /// way to say otherwise, which made "download an area" useless to anyone
    /// whose reason for downloading it was the watch.
    @State private var sendsToWatch = true

    /// What goes into the download. Topographic by default — contour lines are
    /// the reason to carry a map into the hills at all — but a city runner or
    /// somebody short of space can leave them out and halve the wait.
    @State private var detail: MapDownloadDetail = .topographic

    @State private var link = WatchLink.shared

    /// Drawing the square, rather than panning the ground under it.
    @State private var isDrawing = false
    /// Ground metres per screen point, frozen when a drag starts. The map's
    /// scale is derived from the radius, so reading it live while the radius is
    /// being dragged would chase its own tail.
    @State private var dragScale: Double?

    private let location = MapLocationService.shared

    /// How much wider the map is than the square being kept, so the frame sits
    /// inside the view rather than running off the edges.
    private let viewFactor: Double = 1.7

    /// Where the picker should open.
    private var anchor: CLLocationCoordinate2D? {
        cameraCentre ?? location.coordinate ?? fallbackCentre
    }

    /// Ground metres across the taller edge of the map.
    private var spanMetres: Double {
        radiusMetres * 2 * viewFactor
    }

    private var plan: (tileCount: Int, isReduced: Bool)? {
        guard let centre = cameraCentre else { return nil }
        return MapPackStore.areaPlan(centre: centre, radiusMetres: radiusMetres, detail: detail)
    }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                mapArea
                controls
            }
            .overlay(alignment: .top) { searchResults }
        }
        .navigationTitle("Download an area")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .onAppear { location.start() }
        .onDisappear {
            location.stop()
            namingTask?.cancel()
            search.clear()
        }
    }

    // MARK: - Map

    @ViewBuilder
    private var mapArea: some View {
        if let anchor {
            GeometryReader { proxy in
                let side: CGFloat = proxy.size.height / viewFactor

                TrekkaTopoMap(
                    overlay: TopoOverlay(position: location.coordinate),
                    spanMetres: spanMetres,
                    allowsPan: !isDrawing,
                    showsContours: true,
                    showsPlaceLabels: true,
                    focus: searchFocus ?? focus,
                    onCameraChange: handleCamera,
                    palette: .paperSheet,
                    labelFont: .system(size: 11, weight: .semibold),
                    attributionFont: .system(size: 9)
                )
                .overlay { selectionFrame(side: side) }
                .overlay { if isDrawing { drawCatcher(size: proxy.size) } }
                .overlay(alignment: .topTrailing) { mapButtons }
                .overlay(alignment: .topLeading) { searchBar }
                .onAppear {
                    if cameraCentre == nil { cameraCentre = anchor }
                }
            }
        } else {
            waiting
        }
    }

    /// The square that will actually be kept.
    private func selectionFrame(side: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    isDrawing ? Theme.highlight : Theme.accent,
                    style: StrokeStyle(lineWidth: 2, dash: [7, 5])
                )
                .frame(width: side, height: side)

            Circle()
                .fill(isDrawing ? Theme.highlight : Theme.accent)
                .frame(width: 6, height: 6)
        }
        .allowsHitTesting(false)
    }

    /// While drawing, this layer takes the drag instead of the map: the square
    /// is centred on the map, so wherever the finger goes is a corner of it and
    /// the square grows out to meet it.
    private func drawCatcher(size: CGSize) -> some View {
        let centreX = Double(size.width) / 2
        let centreY = Double(size.height) / 2

        return Color.black.opacity(0.001)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Frozen at the start of the drag: the map's scale is
                        // derived from the radius, and reading it live while the
                        // radius is what we are setting would chase its own tail.
                        let scale = dragScale ?? (spanMetres / Double(max(size.height, 1)))
                        if dragScale == nil { dragScale = scale }

                        let fromCentre = max(
                            abs(Double(value.location.x) - centreX),
                            abs(Double(value.location.y) - centreY)
                        )
                        radiusMetres = min(
                            max(fromCentre * scale, AreaDownloadLimits.minRadiusMetres),
                            AreaDownloadLimits.maxRadiusMetres
                        )
                    }
                    .onEnded { _ in dragScale = nil }
            )
    }

    private var mapButtons: some View {
        VStack(spacing: 8) {
            Button {
                location.requestAccess()
                locateToken += 1
            } label: {
                Image(systemName: "location.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.mapControlLabel)
                    .frame(width: 44, height: 44)
                    .background(Theme.mapControl, in: .circle)
                    .overlay { Circle().strokeBorder(Theme.mapControlBorder, lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show my location")

            Button {
                isDrawing.toggle()
            } label: {
                Image(systemName: isDrawing ? "checkmark" : "square.dashed")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isDrawing ? Theme.canvas : Theme.mapControlLabel)
                    .frame(width: 44, height: 44)
                    .background(isDrawing ? Theme.highlight : Theme.mapControl, in: .circle)
                    .overlay {
                        Circle().strokeBorder(
                            isDrawing ? .clear : Theme.mapControlBorder,
                            lineWidth: 1
                        )
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isDrawing ? "Done drawing. Restores panning." : "Draw the square by dragging on the map.")
        }
        .padding(10)
    }

    private var focus: TopoFocus? {
        guard locateToken > 0, let coordinate = location.coordinate else { return nil }
        return TopoFocus(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            token: locateToken
        )
    }

    // MARK: - Search

    /// Aiming the screen by name.
    ///
    /// Panning from where you stand to a national park in the next state was
    /// minutes of dragging, and it used to be the only way to point this screen
    /// at anywhere but your own doorstep.
    private var searchBar: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.mapControlLabel.opacity(0.6))

            TextField("Search for a place", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.mapControlLabel)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onChange(of: query) { _, newValue in
                    search.search(newValue, near: cameraCentre)
                }

            if search.isSearching {
                ProgressView()
                    .controlSize(.mini)
            } else if !query.isEmpty {
                Button {
                    query = ""
                    search.clear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.mapControlLabel.opacity(0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear the search")
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(Theme.mapControl, in: .capsule)
        .overlay { Capsule().strokeBorder(Theme.mapControlBorder, lineWidth: 1) }
        .frame(maxWidth: 230)
        .padding(10)
    }

    @ViewBuilder
    private var searchResults: some View {
        if !query.isEmpty, !search.results.isEmpty || search.foundNothing {
            VStack(spacing: 0) {
                if search.foundNothing {
                    Text("Nothing found for \u{201c}\(query)\u{201d}")
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                } else {
                    ForEach(search.results) { result in
                        resultRow(result)
                        if result.id != search.results.last?.id {
                            Divider().overlay(Theme.border)
                        }
                    }
                }
            }
            .background(Theme.mapPanel, in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Theme.border, lineWidth: 1)
            }
            .padding(.horizontal, 12)
            .padding(.top, 62)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func resultRow(_ result: PlaceResult) -> some View {
        Button {
            choose(result)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(result.name)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if !result.context.isEmpty {
                        Text(result.context)
                            .font(.caption2)
                            .foregroundStyle(Theme.textPrimary.opacity(0.55))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Text("\(Formatters.distance(result.radiusMetres * 2)) \(units.system.distanceUnit)")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// Moves the map to a found place and opens the square at roughly its size.
    ///
    /// A national park comes back many kilometres across and a trailhead comes
    /// back a few hundred metres, so sizing the square to the answer saves the
    /// slider work in the overwhelming majority of cases. It is only ever a
    /// starting point — the slider and the drawing gesture still have the last
    /// word.
    private func choose(_ result: PlaceResult) {
        cameraCentre = result.centre
        radiusMetres = min(
            max(result.radiusMetres, AreaDownloadLimits.minRadiusMetres),
            AreaDownloadLimits.maxRadiusMetres
        )
        suggestedName = result.name
        searchToken += 1
        searchFocus = TopoFocus(
            latitude: result.centre.latitude,
            longitude: result.centre.longitude,
            token: searchToken
        )
        query = ""
        search.clear()
    }

    private var waiting: some View {
        VStack(spacing: 10) {
            Image(systemName: location.isDenied ? "location.slash" : "location.magnifyingglass")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
            Text(location.isDenied ? "Location is off for Trekka" : "Finding your position\u{2026}")
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(location.isDenied
                 ? "Turn location on in Settings to choose an area around you."
                 : "The picker opens where you are, so you can pan from there.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 14) {
            sizeRow

            Slider(
                value: $radiusMetres,
                in: AreaDownloadLimits.minRadiusMetres...AreaDownloadLimits.maxRadiusMetres,
                step: 500
            )
            .tint(Theme.accent)

            TextField(suggestedName.isEmpty ? "Name this area" : suggestedName, text: $name)
                .textFieldStyle(.plain)
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Theme.surfaceRaised, in: .rect(cornerRadius: 10))

            detailPicker

            if let plan, plan.isReduced {
                warning("This area is too large to keep at full detail, so the closest zoom levels are left out. The ground still draws, just less finely. A smaller area keeps everything.")
            }

            watchToggle

            downloadControl
        }
        .padding(16)
        .background(Theme.surface)
    }

    private var sizeRow: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Formatters.distance(radiusMetres * 2)) \(units.system.distanceUnit) across")
                    .font(.system(.headline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                Text(coverageDetail)
                    .font(.caption)
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
            }
            Spacer(minLength: 0)
        }
    }

    /// What this square would actually add.
    ///
    /// The total stopped being the interesting number once Trekka kept one
    /// shared map: what matters is how much of this square is ground the map
    /// does not already hold. Over a place already covered, that can be none of
    /// it, and quoting the full figure would talk someone out of a free square.
    private var coverageDetail: String {
        guard let plan, let centre = cameraCentre else { return "Pan the map to choose where" }
        let new = mapPacks.newTileCount(forArea: centre, radiusMetres: radiusMetres, detail: detail)

        guard new > 0 else {
            return "\(plan.tileCount) pieces \u{00b7} all of it is already on your map"
        }
        let shared = plan.tileCount - new
        let sharedPart = shared > 0 ? " \u{00b7} \(shared) already covered" : ""

        guard let average = mapPacks.averageBytesPerTile else {
            return "\(new) new pieces\(sharedPart) \u{00b7} size known once downloaded"
        }
        return "\(new) new pieces\(sharedPart) \u{00b7} roughly \(MapPackFormat.describe(bytes: new * average)) added"
    }

    /// Which map to keep.
    ///
    /// Both options draw the same cartography in the same colours — the paper
    /// and night sheets are a display choice made later, and putting them here
    /// would suggest they changed what gets stored. What genuinely differs is
    /// whether the height data behind the contour lines comes down too.
    private var detailPicker: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Map type")
                .metricLabelStyle()

            HStack(spacing: 8) {
                ForEach(MapDownloadDetail.allCases) { option in
                    detailOption(option)
                }
            }
        }
    }

    private func detailOption(_ option: MapDownloadDetail) -> some View {
        let isSelected = detail == option
        return Button {
            detail = option
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: option.symbol)
                        .font(.system(size: 13, weight: .semibold))
                    Text(option.title)
                        .font(.system(.subheadline, weight: .bold))
                    Spacer(minLength: 0)
                }
                Text(option.detail)
                    .font(.caption2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(option.sizeNote)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textPrimary.opacity(0.4))
            }
            .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textPrimary.opacity(0.6))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Theme.surfaceRaised, in: .rect(cornerRadius: 11))
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(
                        isSelected ? Theme.accent.opacity(0.7) : Color.clear,
                        lineWidth: 1.5
                    )
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(option.title). \(option.detail). \(option.sizeNote).")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var watchToggle: some View {
        if link.isPaired, link.isWatchAppInstalled {
            Toggle(isOn: $sendsToWatch) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Send to Apple Watch")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Keeps this ground on your wrist as well as your phone")
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                }
            }
            .tint(Theme.accent)
        }
    }

    private func warning(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.highlight)
            Text(text)
                .font(.caption)
                .foregroundStyle(Theme.textPrimary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.surfaceRaised, in: .rect(cornerRadius: 10))
    }

    @ViewBuilder
    private var downloadControl: some View {
        switch mapPacks.progress {
        case .idle, .ready, .alreadyCovered, .failed:
            Button {
                startDownload()
            } label: {
                Text("Add this area to my map")
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.canvas)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(cameraCentre == nil ? Theme.textPrimary.opacity(0.3) : Theme.accent, in: .rect(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(cameraCentre == nil)

            if case .failed(let message) = mapPacks.progress {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
            }
        default:
            VStack(spacing: 8) {
                ProgressView(value: mapPacks.progress.fraction)
                    .tint(Theme.accent)
                Text(progressLabel)
                    .font(.caption)
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
            }
            .padding(.vertical, 6)
        }
    }

    private var progressLabel: String {
        switch mapPacks.progress {
        case .planning: "Working out what is missing\u{2026}"
        case .downloading(let completed, let total): "Downloading \(completed) of \(total) new pieces"
        case .writing: "Adding it to your map\u{2026}"
        case .sendingToWatch: "Sending to your watch\u{2026}"
        default: "Working\u{2026}"
        }
    }

    // MARK: - Actions

    private func handleCamera(_ coordinate: CLLocationCoordinate2D) {
        cameraCentre = coordinate
        scheduleNameLookup(for: coordinate)
    }

    /// Suggests a name for wherever the athlete has landed, debounced so panning
    /// does not fire a lookup on every frame.
    private func scheduleNameLookup(for coordinate: CLLocationCoordinate2D) {
        namingTask?.cancel()
        namingTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            let found = await AreaNameService.shared.name(for: coordinate)
            guard !Task.isCancelled, let found else { return }
            suggestedName = found
        }
    }

    private func startDownload() {
        guard let centre = cameraCentre else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty
            ? (suggestedName.isEmpty ? "Saved area" : suggestedName)
            : trimmed
        mapPacks.addArea(
            centre: centre,
            radiusMetres: radiusMetres,
            name: resolved,
            detail: detail,
            sendToWatch: sendsToWatch && link.isPaired && link.isWatchAppInstalled
        )
    }
}
