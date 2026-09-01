import SwiftUI
import CoreLocation

/// Picks a square of ground to keep offline.
///
/// Until now the only ground that could be stored was a corridor along a saved
/// route, or the starting areas Trekka cached on its own. This is the athlete
/// choosing for themselves: pan to a place, size the square, see exactly how
/// many tiles that is, and keep it.
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
        return MapPackStore.areaPlan(centre: centre, radiusMetres: radiusMetres)
    }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                mapArea
                controls
            }
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
                    focus: focus,
                    onCameraChange: handleCamera,
                    palette: .paperSheet,
                    labelFont: .system(size: 11, weight: .semibold),
                    attributionFont: .system(size: 9)
                )
                .overlay { selectionFrame(side: side) }
                .overlay { if isDrawing { drawCatcher(size: proxy.size) } }
                .overlay(alignment: .topTrailing) { mapButtons }
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
                        radiusMetres = min(max(fromCentre * scale, 1_000), 15_000)
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

            Slider(value: $radiusMetres, in: 1_000...15_000, step: 500)
                .tint(Theme.accent)

            TextField(suggestedName.isEmpty ? "Name this area" : suggestedName, text: $name)
                .textFieldStyle(.plain)
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Theme.surfaceRaised, in: .rect(cornerRadius: 10))

            if let plan, plan.isReduced {
                warning("This area is too large to keep at full detail, so the closest zoom levels are left out. The ground still draws, just less finely. A smaller area keeps everything.")
            }

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

    /// Exact tile count, and a size only when there is real data to base it on.
    private var coverageDetail: String {
        guard let plan else { return "Pan the map to choose where" }
        guard let average = mapPacks.averageBytesPerTile else {
            return "\(plan.tileCount) tiles \u{00b7} size known once downloaded"
        }
        let estimate: Int = plan.tileCount * average
        return "\(plan.tileCount) tiles \u{00b7} roughly \(MapPackFormat.describe(bytes: estimate)) (estimated)"
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
        case .idle, .ready, .failed:
            Button {
                startDownload()
            } label: {
                Text("Keep this area offline")
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
        case .planning: "Working out which ground to keep\u{2026}"
        case .downloading(let completed, let total): "Downloading \(completed) of \(total) tiles"
        case .writing: "Saving to your phone\u{2026}"
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
        mapPacks.downloadArea(
            centre: centre,
            radiusMetres: radiusMetres,
            name: resolved
        )
    }
}
