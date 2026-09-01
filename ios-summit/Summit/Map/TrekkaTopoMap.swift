import SwiftUI
import CoreLocation

/// What Trekka draws on top of the ground.
nonisolated struct TopoOverlay {
    var route: [CLLocationCoordinate2D] = []
    var breadcrumb: [CLLocationCoordinate2D] = []
    /// The way back to the course, present only while off route.
    var guidance: [CLLocationCoordinate2D] = []
    var waypoints: [CLLocationCoordinate2D] = []
    var position: CLLocationCoordinate2D?
    var routeTint: Color = Color(red: 1.0, green: 0.416, blue: 0.075)
    var trailTint: Color = Color(red: 1.0, green: 0.831, blue: 0.286)
    var guidanceTint: Color = Color(red: 1.0, green: 0.271, blue: 0.227)

    /// Everything the map might need to frame itself around.
    ///
    /// Waypoints only count when there is no line to frame on: a single marker
    /// still has to put the map somewhere, but on a real route the line already
    /// covers the waypoints and letting them vote would only widen the view.
    var framingCoordinates: [CLLocationCoordinate2D] {
        var all = route
        all.append(contentsOf: breadcrumb)
        if let position { all.append(position) }
        if all.isEmpty { all.append(contentsOf: waypoints) }
        return all
    }

    /// Cheap change detection, so the view reframes without needing every
    /// coordinate to be Equatable.
    var signature: Int {
        var hasher = Hasher()
        hasher.combine(route.count)
        hasher.combine(breadcrumb.count)
        hasher.combine(guidance.count)
        hasher.combine(waypoints.count)
        if let first = route.first {
            hasher.combine(Int(first.latitude * 10_000))
            hasher.combine(Int(first.longitude * 10_000))
        }
        if let position {
            hasher.combine(Int(position.latitude * 10_000))
            hasher.combine(Int(position.longitude * 10_000))
        }
        return hasher.finalize()
    }
}

/// A one-shot request to put a particular point in the middle of the map.
///
/// Carries a token rather than just a coordinate, so asking to be located twice
/// from the same spot still re-centres after the athlete has panned away.
nonisolated struct TopoFocus: Equatable {
    var latitude: Double
    var longitude: Double
    var token: Int

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Trekka's own topographic map.
///
/// Drawn from OpenStreetMap vector tiles and on-device contour tracing rather
/// than a platform map view, because a map that has to work with no signal must
/// be one we render ourselves — and because the styling for a wrist at arm's
/// length in bright sun is nothing like the styling for a desk.
///
/// The same view serves the phone and the watch; only weights, fonts and
/// interaction differ.
struct TrekkaTopoMap: View {
    var overlay = TopoOverlay()
    /// Where to look when the map is not being dragged. Nil frames the overlay.
    var centre: CLLocationCoordinate2D?
    /// Ground metres across the taller screen edge. Nil fits the overlay.
    var spanMetres: Double?
    /// Degrees clockwise from north the map is turned to.
    var heading: Double = 0
    var rotatesWithHeading = false
    /// Where the camera centre sits vertically, as a fraction of the height.
    ///
    /// Half puts it in the middle. Turning the map to a heading moves it lower,
    /// so more of the screen shows the ground ahead than the ground already
    /// walked — which is the whole reason to rotate in the first place.
    var centreAnchorY: CGFloat = 0.5
    var allowsPan = false
    var allowsZoom = false
    var showsContours = true
    var showsPlaceLabels = true
    /// Chevrons along the planned route showing which way round it runs.
    var showsRouteDirection = true
    var showsAttribution = true
    /// Says so plainly when there is no ground to draw, rather than leaving a
    /// blank sheet that looks like a bug.
    var showsEmptyState = true
    /// Increment to pull the map back onto its content after the athlete has
    /// panned away from it.
    var reframeToken: Int = 0
    /// Puts one specific point in the middle, whatever the content is.
    var focus: TopoFocus?
    /// Reports the camera centre whenever it moves, so a picker can follow
    /// wherever the athlete has panned to.
    var onCameraChange: ((CLLocationCoordinate2D) -> Void)?
    var palette: TopoPalette = .paperSheet
    /// Thickens every stroke for a small screen.
    var compact = false
    var labelFont: Font = .system(size: 10, weight: .semibold)
    var attributionFont: Font = .system(size: 9, weight: .regular)

    @State private var model = TopoMapModel()
    @State private var size: CGSize = .zero
    /// Pan offset in screen points, folded into the camera when the drag ends.
    @State private var dragTranslation: CGSize = .zero
    @State private var pinchScale: CGFloat = 1
    @State private var hasFramed = false

    var body: some View {
        GeometryReader { proxy in
            canvas(size: proxy.size)
                .contentShape(.rect)
                .gesture(panGesture, isEnabled: allowsPan)
                .modifier(TopoPinchToZoom(isEnabled: allowsZoom, scale: $pinchScale, onCommit: commitZoom))
                .onAppear {
                    size = proxy.size
                    applyFraming(force: true)
                }
                .onChange(of: proxy.size) { _, newSize in
                    size = newSize
                    applyFraming(force: true)
                }
        }
        .overlay { emptyState }
        .overlay(alignment: .bottomLeading) { attribution }
        // Not forced: changing the scale should change the scale and nothing
        // else. Forcing it here dragged the camera back onto the content every
        // time the athlete zoomed, undoing wherever they had panned to.
        .onChange(of: spanMetres) { _, _ in applyFraming(force: false) }
        .onChange(of: centre?.latitude) { _, _ in applyFraming(force: false) }
        .onChange(of: centre?.longitude) { _, _ in applyFraming(force: false) }
        .onChange(of: overlay.signature) { _, _ in applyFraming(force: false) }
        .onChange(of: reframeToken) { _, _ in applyFraming(force: true) }
        .onChange(of: focus) { _, newValue in applyFocus(newValue) }
        .onChange(of: showsContours) { _, newValue in
            model.showsContours = newValue
            model.refresh(size: size)
        }
    }

    // MARK: - Framing

    private func applyFraming(force: Bool) {
        guard size.width > 1, size.height > 1 else { return }
        model.showsContours = showsContours

        // A centre was asked for, so honour it.
        if let centre {
            let span: Double = spanMetres ?? currentSpanMetres()
            model.frame(centre: centre, spanMetres: span, size: size)
            hasFramed = true
            model.refresh(size: size)
            onCameraChange?(model.camera.centre)
            return
        }

        // No centre and the map is in the athlete's hands: the zoom may still
        // change, but never the centre, or a Crown turn would tug the ground
        // back from wherever they had panned to. Asking to re-frame overrides
        // this, since that is the athlete asking for their content back.
        if hasFramed, allowsPan, !force {
            if let spanMetres {
                model.zoom(toSpanMetres: spanMetres, size: size)
                model.refresh(size: size)
            }
            return
        }

        let coordinates = overlay.framingCoordinates
        if let spanMetres, let anchor = coordinates.first {
            model.frame(centre: anchor, spanMetres: spanMetres, size: size)
        } else if !coordinates.isEmpty {
            model.frame(fitting: coordinates, size: size)
        }

        hasFramed = true
        model.refresh(size: size)
        onCameraChange?(model.camera.centre)
    }

    /// Centres on an explicit point without disturbing the current zoom.
    private func applyFocus(_ focus: TopoFocus?) {
        guard let focus, size.width > 1, size.height > 1 else { return }
        model.frame(
            centre: focus.coordinate,
            spanMetres: spanMetres ?? currentSpanMetres(),
            size: size
        )
        hasFramed = true
        model.refresh(size: size)
        onCameraChange?(model.camera.centre)
    }

    private func currentSpanMetres() -> Double {
        TopoTileMath.spanMetres(
            zoom: model.camera.zoom,
            latitude: model.camera.centre.latitude,
            pixels: max(Double(size.height), 1)
        )
    }

    // MARK: - Gestures

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragTranslation = value.translation
            }
            .onEnded { value in
                dragTranslation = .zero
                commitPan(translation: value.translation)
            }
    }

    private func commitPan(translation: CGSize) {
        let worldSize: Double = TopoTileMath.worldSize(zoom: model.camera.zoom)
        // Undo the map's rotation so a drag moves the ground the way the finger
        // went, not the way north is pointing.
        let radians: Double = rotatesWithHeading ? heading * .pi / 180 : 0
        let dx: Double = Double(translation.width)
        let dy: Double = Double(translation.height)
        let rotatedX: Double = dx * cos(radians) - dy * sin(radians)
        let rotatedY: Double = dx * sin(radians) + dy * cos(radians)

        let world = TopoTileMath.world(model.camera.centre)
        let newWorldX: Double = Double(world.x) - rotatedX / worldSize
        let newWorldY: Double = Double(world.y) - rotatedY / worldSize
        let clampedY: Double = min(max(newWorldY, 0), 1)

        model.camera.centre = TopoTileMath.coordinate(
            world: CGPoint(x: newWorldX, y: clampedY)
        )
        model.refresh(size: size)
        onCameraChange?(model.camera.centre)
    }

    private func commitZoom(magnification: CGFloat) {
        let delta: Double = log2(max(Double(magnification), 0.1))
        model.camera.zoom = min(max(model.camera.zoom + delta, 3), 18)
        model.refresh(size: size)
    }

    // MARK: - Canvas

    private func canvas(size: CGSize) -> some View {
        Canvas(opaque: true, rendersAsynchronously: false) { context, canvasSize in
            draw(context: &context, size: canvasSize)
        }
    }

    private func draw(context: inout GraphicsContext, size canvasSize: CGSize) {
        let paperRect = CGRect(origin: .zero, size: canvasSize)
        context.fill(Path(paperRect), with: .color(palette.paper))

        let camera = model.camera
        let centreWorld = camera.centreWorldPixels

        // Cull against a circle around the camera centre. With the centre pushed
        // low the far corner is further away than half the diagonal, so the
        // radius is measured from the anchor rather than assumed.
        let anchorY: CGFloat = min(max(centreAnchorY, 0.1), 0.9)
        let verticalReach: Double = Double(max(anchorY, 1 - anchorY)) * Double(canvasSize.height)
        let radius: Double = hypot(Double(canvasSize.width) / 2, verticalReach)

        context.translateBy(x: canvasSize.width / 2, y: canvasSize.height * anchorY)
        // A live pan is shown by shifting what is already drawn, which keeps the
        // gesture at screen framerate instead of waiting on tile maths.
        context.translateBy(x: dragTranslation.width, y: dragTranslation.height)
        if pinchScale != 1 {
            context.scaleBy(x: pinchScale, y: pinchScale)
        }
        if rotatesWithHeading {
            context.rotate(by: .degrees(-heading))
        }

        drawBasemap(context: &context, camera: camera, centreWorld: centreWorld, radius: radius)
        drawOverlay(context: &context, camera: camera, centreWorld: centreWorld, radius: radius)

        if showsPlaceLabels {
            drawLabels(context: &context, camera: camera, centreWorld: centreWorld, radius: radius)
        }
    }

    /// Draws bucket by bucket across every tile, rather than tile by tile.
    ///
    /// This matters: drawn per tile, one tile's woodland would paint over its
    /// neighbour's footpaths at the seam. Bucket-major keeps the layering
    /// continuous across the whole screen.
    private func drawBasemap(
        context: inout GraphicsContext,
        camera: TopoCamera,
        centreWorld: CGPoint,
        radius: Double
    ) {
        for bucket in TopoBucket.allCases {
            let isContour: Bool = bucket == .contour || bucket == .contourIndex
            if isContour && !showsContours { continue }

            let paint = TopoStyle.paint(bucket, zoom: camera.zoom, palette: palette, compact: compact)
            let shading = GraphicsContext.Shading.color(paint.colour.opacity(paint.opacity))

            if isContour {
                for tile in model.contourDrawTiles.values {
                    guard let transform = tileTransform(
                        key: tile.key,
                        camera: camera,
                        centreWorld: centreWorld,
                        radius: radius
                    ) else { continue }
                    let source: Path = bucket == .contour ? tile.ordinary : tile.index
                    guard !source.isEmpty else { continue }
                    let style = StrokeStyle(lineWidth: paint.width, lineCap: .round, lineJoin: .round)
                    context.stroke(source.applying(transform), with: shading, style: style)
                }
                continue
            }

            // A road casing is the road's own geometry drawn wider underneath.
            let geometryBucket: TopoBucket = bucket == .roadCasing ? .road : bucket

            for tile in model.drawTiles.values {
                guard let path = tile.paths[geometryBucket], !path.isEmpty else { continue }
                guard let transform = tileTransform(
                    key: tile.key,
                    camera: camera,
                    centreWorld: centreWorld,
                    radius: radius
                ) else { continue }

                let transformed = path.applying(transform)
                if bucket.isArea {
                    context.fill(transformed, with: shading)
                } else {
                    let style = StrokeStyle(
                        lineWidth: paint.width,
                        lineCap: paint.dash.isEmpty ? .round : .butt,
                        lineJoin: .round,
                        dash: paint.dash
                    )
                    context.stroke(transformed, with: shading, style: style)
                }
            }
        }
    }

    /// Where a tile lands on screen, or nil when it is off it.
    private func tileTransform(
        key: TopoTileKey,
        camera: TopoCamera,
        centreWorld: CGPoint,
        radius: Double
    ) -> CGAffineTransform? {
        let tilePixels: Double = TopoTileMath.tileSide * pow(2, camera.zoom - Double(key.z))
        let originX: Double = Double(key.x) * tilePixels - Double(centreWorld.x)
        let originY: Double = Double(key.y) * tilePixels - Double(centreWorld.y)

        // Cull against the view's bounding circle, which holds under rotation.
        let margin: Double = radius + tilePixels
        if originX > margin || originY > margin { return nil }
        if originX + tilePixels < -margin || originY + tilePixels < -margin { return nil }

        var transform = CGAffineTransform(translationX: originX, y: originY)
        transform = transform.scaledBy(x: tilePixels, y: tilePixels)
        return transform
    }

    // MARK: - Overlay

    private func drawOverlay(
        context: inout GraphicsContext,
        camera: TopoCamera,
        centreWorld: CGPoint,
        radius: Double
    ) {
        let worldSize: Double = TopoTileMath.worldSize(zoom: camera.zoom)

        func project(_ coordinate: CLLocationCoordinate2D) -> CGPoint {
            let world = TopoTileMath.world(coordinate)
            let x: Double = Double(world.x) * worldSize - Double(centreWorld.x)
            let y: Double = Double(world.y) * worldSize - Double(centreWorld.y)
            return CGPoint(x: x, y: y)
        }

        func line(_ coordinates: [CLLocationCoordinate2D]) -> Path {
            var path = Path()
            guard let first = coordinates.first else { return path }
            path.move(to: project(first))
            for coordinate in coordinates.dropFirst() {
                path.addLine(to: project(coordinate))
            }
            return path
        }

        let routeWidth: CGFloat = compact ? 4.5 : 5
        let trailWidth: CGFloat = compact ? 3 : 3.5

        // The travelled trail sits under the plan, so the course stays readable.
        if overlay.breadcrumb.count > 1 {
            let path = line(overlay.breadcrumb)
            let style = StrokeStyle(
                lineWidth: trailWidth,
                lineCap: .round,
                dash: [trailWidth * 0.2, trailWidth * 1.5]
            )
            context.stroke(path, with: .color(overlay.trailTint), style: style)
        }

        if overlay.route.count > 1 {
            let path = line(overlay.route)
            // A soft halo lifts the line off busy ground without hiding it.
            let halo = StrokeStyle(lineWidth: routeWidth * 2.4, lineCap: .round, lineJoin: .round)
            context.stroke(path, with: .color(overlay.routeTint.opacity(0.22)), style: halo)
            let core = StrokeStyle(lineWidth: routeWidth, lineCap: .round, lineJoin: .round)
            context.stroke(path, with: .color(overlay.routeTint), style: core)

            if showsRouteDirection {
                let chevrons = Self.directionChevrons(
                    along: overlay.route.map(project),
                    spacing: compact ? 26 : 34,
                    length: routeWidth * 0.8,
                    halfWidth: routeWidth * 0.46,
                    radius: radius
                )
                if !chevrons.isEmpty {
                    // Cut into the line in the paper's own colour rather than
                    // laid on top of it: the arrows read as part of the route
                    // instead of clutter floating above the ground.
                    context.stroke(
                        chevrons,
                        with: .color(palette.paper),
                        style: StrokeStyle(
                            lineWidth: max(routeWidth * 0.32, 1),
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                }
            }
        }

        if overlay.guidance.count > 1 {
            let path = line(overlay.guidance)
            let style = StrokeStyle(
                lineWidth: routeWidth * 0.8,
                lineCap: .round,
                dash: [routeWidth, routeWidth * 0.9]
            )
            context.stroke(path, with: .color(overlay.guidanceTint), style: style)
        }

        let flagSide: CGFloat = compact ? 7 : 9
        for waypoint in overlay.waypoints {
            let point = project(waypoint)
            var diamond = Path()
            diamond.move(to: CGPoint(x: point.x, y: point.y - flagSide))
            diamond.addLine(to: CGPoint(x: point.x + flagSide, y: point.y))
            diamond.addLine(to: CGPoint(x: point.x, y: point.y + flagSide))
            diamond.addLine(to: CGPoint(x: point.x - flagSide, y: point.y))
            diamond.closeSubpath()
            context.fill(diamond, with: .color(overlay.routeTint))
            context.stroke(diamond, with: .color(palette.paper), lineWidth: 1.5)
        }

        if let position = overlay.position {
            let point = project(position)
            let outer: CGFloat = compact ? 11 : 13
            let inner: CGFloat = compact ? 6 : 7
            let outerRect = CGRect(
                x: point.x - outer / 2,
                y: point.y - outer / 2,
                width: outer,
                height: outer
            )
            let innerRect = CGRect(
                x: point.x - inner / 2,
                y: point.y - inner / 2,
                width: inner,
                height: inner
            )
            context.fill(Path(ellipseIn: outerRect), with: .color(palette.paper))
            context.fill(Path(ellipseIn: innerRect), with: .color(overlay.routeTint))
        }
    }

    /// Chevrons spaced along a projected line, pointing the way it is walked.
    ///
    /// A route line says where, never which way round. On a loop — or when the
    /// athlete joins the course partway along — that is the difference between
    /// walking the climb and walking the descent.
    ///
    /// Spacing is measured in screen points rather than in metres or in route
    /// points, so the arrows stay evenly placed at every zoom instead of
    /// bunching into a solid smear as the view widens.
    private static func directionChevrons(
        along points: [CGPoint],
        spacing: CGFloat,
        length: CGFloat,
        halfWidth: CGFloat,
        radius: Double
    ) -> Path {
        var path = Path()
        guard points.count > 1, spacing > 0 else { return path }

        let cull: Double = radius + Double(spacing)
        // A ceiling, so a long route at a wide zoom cannot turn into thousands
        // of arrows that no eye could read anyway.
        let limit = 400
        var drawn = 0
        // Half a step in, so a route never opens with an arrow on its start cap.
        var untilNext: CGFloat = spacing / 2

        for index in 1..<points.count {
            let start = points[index - 1]
            let end = points[index]
            let dx: CGFloat = end.x - start.x
            let dy: CGFloat = end.y - start.y
            let segment: CGFloat = hypot(dx, dy)
            guard segment > 0.0001 else { continue }

            let ux: CGFloat = dx / segment
            let uy: CGFloat = dy / segment
            var travelled: CGFloat = untilNext

            while travelled <= segment {
                let centre = CGPoint(x: start.x + ux * travelled, y: start.y + uy * travelled)
                travelled += spacing

                guard hypot(Double(centre.x), Double(centre.y)) <= cull else { continue }

                let tip = CGPoint(x: centre.x + ux * length, y: centre.y + uy * length)
                let backX: CGFloat = centre.x - ux * length * 0.35
                let backY: CGFloat = centre.y - uy * length * 0.35
                // Perpendicular to travel, so the wings open out behind the tip.
                let wingX: CGFloat = -uy * halfWidth
                let wingY: CGFloat = ux * halfWidth

                path.move(to: CGPoint(x: backX + wingX, y: backY + wingY))
                path.addLine(to: tip)
                path.addLine(to: CGPoint(x: backX - wingX, y: backY - wingY))

                drawn += 1
                if drawn >= limit { return path }
            }
            untilNext = travelled - segment
        }
        return path
    }

    // MARK: - Labels

    private func drawLabels(
        context: inout GraphicsContext,
        camera: TopoCamera,
        centreWorld: CGPoint,
        radius: Double
    ) {
        for tile in model.drawTiles.values {
            guard !tile.labels.isEmpty else { continue }
            guard let transform = tileTransform(
                key: tile.key,
                camera: camera,
                centreWorld: centreWorld,
                radius: radius
            ) else { continue }

            for label in tile.labels {
                guard TopoStyle.showsPlaceLabel(className: label.className, zoom: camera.zoom) else {
                    continue
                }
                let point = label.point.applying(transform)
                let text = Text(label.name)
                    .font(labelFont)
                    .foregroundStyle(palette.label)

                // Drawn in its own layer with the rotation undone, so names stay
                // upright on a map that turns with the athlete.
                context.drawLayer { layer in
                    layer.translateBy(x: point.x, y: point.y)
                    if rotatesWithHeading {
                        layer.rotate(by: .degrees(heading))
                    }
                    layer.draw(text, at: .zero, anchor: .center)
                }
            }
        }
    }

    // MARK: - Empty state

    /// Shown when a fetch has been tried, nothing is still in flight, and no
    /// ground arrived.
    ///
    /// Almost always means no signal and no downloaded pack for here. Saying that
    /// is far better than an empty sheet, because the athlete can still act on
    /// it — the route line, breadcrumbs and compass carry on regardless.
    @ViewBuilder
    private var emptyState: some View {
        if showsEmptyState, model.didAttemptLoad, !model.isLoading, !model.hasContent {
            VStack(spacing: compact ? 3 : 6) {
                Image(systemName: "square.stack.3d.up.slash")
                    .font(.system(size: compact ? 15 : 22, weight: .semibold))
                Text("No map here yet")
                    .font(compact ? labelFont : .system(size: 14, weight: .semibold))
                if !compact {
                    Text("Download this route's map while you have signal.")
                        .font(.system(size: 11))
                        .multilineTextAlignment(.center)
                        .opacity(0.75)
                }
            }
            .foregroundStyle(palette.label.opacity(0.65))
            .padding(compact ? 8 : 16)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Attribution

    @ViewBuilder
    private var attribution: some View {
        if showsAttribution {
            Text(TopoTileSource.attribution)
                .font(attributionFont)
                .foregroundStyle(palette.label.opacity(0.7))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(palette.paper.opacity(0.7), in: .rect(cornerRadius: 3))
                .padding(4)
                .allowsHitTesting(false)
        }
    }
}

/// Pinch-to-zoom, on the platforms that have pinching.
///
/// The watch has no spare finger — the Digital Crown does the zooming there —
/// and `MagnifyGesture` does not exist on watchOS at all, so the gesture is
/// compiled in only where it can actually be used.
private struct TopoPinchToZoom: ViewModifier {
    let isEnabled: Bool
    @Binding var scale: CGFloat
    let onCommit: (CGFloat) -> Void

    func body(content: Content) -> some View {
        #if os(watchOS)
        content
        #else
        content.gesture(
            MagnifyGesture()
                .onChanged { value in scale = value.magnification }
                .onEnded { value in
                    scale = 1
                    onCommit(value.magnification)
                },
            isEnabled: isEnabled
        )
        #endif
    }
}
