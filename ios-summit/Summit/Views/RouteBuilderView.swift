import SwiftUI
import UniformTypeIdentifiers

/// Full-screen route builder: the map fills the display, and every control
/// floats on top of it in a console small enough to keep the terrain visible.
struct RouteBuilderView: View {
    @Environment(RouteStore.self) private var store
    @Environment(AppearanceSettings.self) private var appearance
    @Environment(\.dismiss) private var dismiss

    /// A route being edited, or `nil` for a new one.
    var editing: PlannedRoute?
    /// Handed the saved route so the library can open it.
    var onSaved: (PlannedRoute) -> Void

    @State private var draft = RouteDraftModel()
    @State private var activity: RouteActivityType = .run
    @State private var baseStyle: TopoBaseStyle = .terrain
    @State private var isConsoleExpanded = true
    @State private var showsProfile = false
    @State private var showsSaveDialog = false
    @State private var showsImporter = false
    @State private var showsClearConfirmation = false
    @State private var editingNodeID: UUID?
    @State private var draftName = ""
    @State private var recenterToken = 0
    @State private var feedback = 0

    private var mapMode: MapInteractionMode {
        switch draft.tool {
        case .move: .browse
        case .add: .waypoint
        }
    }

    var body: some View {
        ZStack {
            map
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                console
            }
        }
        .background(Theme.canvas)
        // Follows the app's appearance setting like every other screen. This
        // was pinned to dark, so the planner stayed black however the rest of
        // the app was set — and its chrome was written in fixed white on fixed
        // black to match, which is why none of it moved with the toggle.
        .preferredColorScheme(appearance.colorScheme)
        .sensoryFeedback(.selection, trigger: feedback)
        .animation(.snappy(duration: 0.26), value: isConsoleExpanded)
        .animation(.snappy(duration: 0.22), value: draft.tool)
        .sheet(isPresented: $showsProfile) {
            RouteProfileSheet(draft: draft, activity: activity)
        }
        .sheet(isPresented: Binding(
            get: { editingNodeID != nil },
            set: { if !$0 { editingNodeID = nil } }
        )) {
            if let id = editingNodeID, let node = draft.nodes.first(where: { $0.id == id }) {
                NodeEditorSheet(
                    node: node,
                    index: (draft.nodes.firstIndex(where: { $0.id == id }) ?? 0) + 1,
                    onSave: { name, note in
                        draft.rename(nodeID: id, to: name, note: note)
                        editingNodeID = nil
                    },
                    onPlain: {
                        draft.toggleWaypoint(nodeID: id)
                        editingNodeID = nil
                    },
                    onDelete: {
                        draft.removeNode(id: id)
                        editingNodeID = nil
                    }
                )
            }
        }
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: gpxContentTypes,
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first,
               let route = draft.route(fromGPX: url) {
                draft.load(from: route)
                activity = route.activity
                recenterToken += 1
            }
        }
        .alert("Name this route", isPresented: $showsSaveDialog) {
            TextField("Route name", text: $draftName)
            Button("Save") { save() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saved routes sync to your watch with their offline map pack.")
        }
        .confirmationDialog("Clear the whole route?", isPresented: $showsClearConfirmation, titleVisibility: .visible) {
            Button("Clear", role: .destructive) {
                draft.clear()
                feedback += 1
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear(perform: prepare)
        .onChange(of: activity) { _, newValue in
            // The ground worth following changes with the activity. Straight
            // lines were asked for deliberately, so they are left alone.
            guard draft.snapMode != .direct else { return }
            draft.snapMode = .default(for: newValue)
        }
    }

    // MARK: - Map

    private var map: some View {
        TopoMapView(
            waypoints: [],
            mode: mapMode,
            baseStyle: baseStyle,
            isInteractive: true,
            recenterToken: recenterToken,
            plannerLegs: draft.legs,
            plannerNodes: draft.nodes,
            onTap: { coordinate in
                draft.addNode(at: coordinate)
                feedback += 1
            },
            onNodeMoved: { id, coordinate in
                draft.moveNode(id: id, to: coordinate)
                feedback += 1
            },
            onNodeTapped: { id in
                editingNodeID = id
                feedback += 1
            }
        )
        .overlay(alignment: .trailing) { sideControls }
    }

    private var sideControls: some View {
        VStack(spacing: 8) {
            mapButton(symbol: "scope", label: "Fit route on map") {
                recenterToken += 1
                feedback += 1
            }
            mapButton(symbol: baseStyle.symbol, label: "Switch base map") {
                baseStyle = baseStyle.nextEditable
                feedback += 1
            }
            mapButton(
                symbol: "chart.line.uptrend.xyaxis",
                label: "Elevation profile",
                isEnabled: draft.legs.contains { $0.points.count > 1 }
            ) {
                showsProfile = true
                feedback += 1
            }
        }
        .padding(.trailing, 12)
        .padding(.bottom, isConsoleExpanded ? 165 : 115)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            glassButton(symbol: "xmark") { dismiss() }

            VStack(spacing: 1) {
                Text(editing == nil ? "New route" : "Editing route")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.mapControlLabel.opacity(0.55))
                Text(draft.tool.hint)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.mapControlLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .background(Theme.mapControl, in: .capsule)
            .overlay { Capsule().strokeBorder(Theme.mapControlBorder, lineWidth: 1) }

            Button {
                draftName = suggestedName()
                showsSaveDialog = true
                feedback += 1
            } label: {
                Text("Save")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(
                        draft.nodes.count > 1
                            ? Theme.canvas
                            : Theme.mapControlLabel.opacity(0.35)
                    )
                    .frame(height: 38)
                    .padding(.horizontal, 15)
                    .background(
                        draft.nodes.count > 1 ? Theme.accent : Theme.mapControl,
                        in: .capsule
                    )
            }
            .buttonStyle(.plain)
            .disabled(draft.nodes.count < 2)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    // MARK: - Console

    private var console: some View {
        VStack(spacing: 0) {
            grabber

            if isConsoleExpanded {
                VStack(spacing: 10) {
                    readout
                    toolRow
                    shapeRow
                    if let notice = honestyNotice {
                        Text(notice)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.highlight)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(2)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                compactRow
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .background(Theme.mapPanel, in: .rect(topLeadingRadius: 22, topTrailingRadius: 22))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.mapControlBorder)
                .frame(height: 1)
        }
        .padding(.horizontal, 8)
    }

    private var grabber: some View {
        Button {
            isConsoleExpanded.toggle()
            feedback += 1
        } label: {
            Capsule()
                .fill(Theme.mapControlLabel.opacity(0.3))
                .frame(width: 38, height: 4)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isConsoleExpanded ? "Collapse controls" : "Expand controls")
    }

    /// Distance and climb — nothing else. With trails off every leg is a
    /// straight line by request, so a "how much is routed" figure would only
    /// ever read 0%.
    private var readout: some View {
        HStack(spacing: 0) {
            statCell(
                label: "Distance",
                value: Formatters.distance(draft.distance),
                unit: Formatters.units.distanceUnit,
                tint: Theme.mapControlLabel
            )
            statDivider
            statCell(
                label: "Climb",
                value: draft.elevationGain.map { Formatters.elevation($0) } ?? "--",
                unit: draft.elevationGain == nil ? "" : Formatters.units.elevationUnit,
                tint: Theme.highlight
            )
            if draft.snapMode != .direct {
                statDivider
                statCell(
                    label: "On route",
                    value: draft.legs.isEmpty ? "--" : "\(Int((draft.snappedFraction * 100).rounded()))",
                    unit: draft.legs.isEmpty ? "" : "%",
                    tint: Theme.accent
                )
            }
        }
    }

    private func statCell(label: String, value: String, unit: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(Theme.mapControlLabel.opacity(0.5))
            HStack(alignment: .firstTextBaseline, spacing: 1.5) {
                Text(value)
                    .font(.metric(19))
                    .foregroundStyle(tint)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.mapControlLabel.opacity(0.5))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Theme.mapControlBorder)
            .frame(width: 1, height: 26)
    }

    /// Whether placed points are joined along real ways. On — the default — the
    /// line follows the paths the chosen activity can travel. Off, points are
    /// joined by straight lines, for cross-country ground no path covers.
    private var trailsChip: some View {
        let isActive = draft.snapMode != .direct
        return Button {
            draft.snapMode = isActive ? .direct : .default(for: activity)
            feedback += 1
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 10, weight: .bold))
                Text("Trails")
                    .font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .foregroundStyle(isActive ? Theme.canvas : Theme.mapControlLabel.opacity(0.7))
            .background(isActive ? Theme.accent : Theme.mapFill, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel("Follow trails")
    }

    private var toolRow: some View {
        HStack(spacing: 6) {
            ForEach(PlannerTool.allCases) { tool in
                let isActive = draft.tool == tool
                Button {
                    draft.tool = tool
                    feedback += 1
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tool.symbol)
                            .font(.system(size: 15, weight: .semibold))
                        Text(tool.title)
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(isActive ? Theme.accent : Theme.mapControlLabel.opacity(0.7))
                    .background(
                        isActive ? Theme.accent.opacity(0.16) : Theme.mapFill,
                        in: .rect(cornerRadius: 11)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 11)
                            .strokeBorder(isActive ? Theme.accent : .clear, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
            }

            actionButton(symbol: "arrow.uturn.backward", label: "Undo", isEnabled: draft.canUndo) {
                draft.undo()
                feedback += 1
            }

            Menu {
                Button {
                    draft.reverse()
                    feedback += 1
                } label: {
                    Label("Reverse direction", systemImage: "arrow.left.arrow.right")
                }
                .disabled(draft.nodes.count < 2)

                Button {
                    draft.removeLastNode()
                    feedback += 1
                } label: {
                    Label("Remove last point", systemImage: "minus.circle")
                }
                .disabled(draft.nodes.isEmpty)

                Divider()

                Picker("Activity", selection: $activity) {
                    ForEach(RouteActivityType.allCases, id: \.self) { value in
                        Label(value.rawValue, systemImage: value.symbol).tag(value)
                    }
                }

                Picker(
                    "Route follows",
                    selection: Binding(
                        get: { draft.snapMode },
                        set: { draft.snapMode = $0; feedback += 1 }
                    )
                ) {
                    ForEach(RouteSnapMode.allCases) { mode in
                        Label(mode.summary, systemImage: mode.symbol).tag(mode)
                    }
                }

                Button {
                    showsProfile = true
                } label: {
                    Label("Elevation profile", systemImage: "chart.line.uptrend.xyaxis")
                }
                Button {
                    showsImporter = true
                } label: {
                    Label("Import GPX", systemImage: "square.and.arrow.down")
                }

                Divider()

                Button(role: .destructive) {
                    showsClearConfirmation = true
                } label: {
                    Label("Clear route", systemImage: "trash")
                }
                .disabled(draft.isEmpty)
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                    Text("More")
                        .font(.system(size: 9, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundStyle(Theme.mapControlLabel.opacity(0.7))
                .background(Theme.mapFill, in: .rect(cornerRadius: 11))
            }
            .menuOrder(.fixed)
        }
    }

    /// Turning a tapped-out line into a finished route: walk it home the way you
    /// came, or join the end back to the start. Until there are two points to
    /// work with, this space says how to start instead.
    @ViewBuilder
    private var shapeRow: some View {
        if draft.nodes.count > 1 {
            HStack(spacing: 8) {
                shapeButton(
                    symbol: "arrow.left.arrow.right",
                    title: "Out and back",
                    detail: "Return the way you came",
                    isEnabled: draft.canOutAndBack
                ) {
                    draft.outAndBack()
                    recenterToken += 1
                    feedback += 1
                }

                shapeButton(
                    symbol: "arrow.trianglehead.2.clockwise.rotate.90",
                    title: "Close the loop",
                    detail: "Join the end to the start",
                    isEnabled: draft.canCloseLoop
                ) {
                    draft.closeLoop()
                    recenterToken += 1
                    feedback += 1
                }

                trailsChip
            }
        } else {
            startRow
        }
    }

    /// Nothing placed yet. Says what to do, and offers the other way in — a file
    /// from a watch, a website or another app — rather than leaving the row
    /// empty on the one screen where a beginner needs the most help.
    private var startRow: some View {
        HStack(spacing: 8) {
            Label(
                draft.nodes.isEmpty ? "Tap the map to place your start" : "Tap again to extend the route",
                systemImage: "hand.tap"
            )
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.mapControlLabel.opacity(0.6))
            .lineLimit(1)
            .minimumScaleFactor(0.75)

            Spacer(minLength: 0)

            Button {
                showsImporter = true
                feedback += 1
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 10, weight: .bold))
                    Text("Import")
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .foregroundStyle(Theme.accent)
                .background(Theme.accent.opacity(0.16), in: .capsule)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Import a GPX file")

            trailsChip
        }
    }

    private func shapeButton(
        symbol: String,
        title: String,
        detail: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                    Text(detail)
                        .font(.system(size: 9))
                        .opacity(0.6)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(isEnabled ? Theme.accent : Theme.mapControlLabel.opacity(0.28))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                isEnabled ? Theme.accent.opacity(0.14) : Theme.mapFill.opacity(0.6),
                in: .rect(cornerRadius: 11)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel("\(title). \(detail).")
    }

    /// One-line version so the map can take nearly the whole screen.
    private var compactRow: some View {
        HStack(spacing: 10) {
            Image(systemName: draft.snapMode.symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.accent)
            Text("\(Formatters.distance(draft.distance)) \(Formatters.units.distanceUnit)")
                .font(.metric(15))
                .foregroundStyle(Theme.mapControlLabel)
            if let gain = draft.elevationGain {
                Text("↑\(Formatters.elevation(gain)) \(Formatters.units.elevationUnit)")
                    .font(.metric(13, weight: .semibold))
                    .foregroundStyle(Theme.highlight)
            }
            Spacer(minLength: 0)
            actionButton(symbol: "arrow.uturn.backward", label: "Undo", isEnabled: draft.canUndo) {
                draft.undo()
                feedback += 1
            }
            actionButton(
                symbol: draft.tool == .add ? "plus.circle.fill" : draft.tool.symbol,
                label: "Tools",
                isEnabled: true
            ) {
                isConsoleExpanded = true
                feedback += 1
            }
        }
    }

    /// Says plainly where the line is not routed ground. Direct mode has
    /// nothing to confess: every leg is a straight line, on purpose.
    private var honestyNotice: String? {
        if draft.elevationState == .unavailable {
            return "No terrain data for this area yet — climb will read -- until you have signal."
        }
        if draft.isResolving {
            return "Snapping to the map…"
        }
        if draft.legs.contains(where: \.isAsRecorded) {
            return "Dashed stretches came in with the file — kept exactly as recorded."
        }
        guard draft.snapMode != .direct else { return nil }
        let straight = draft.straightLineLegCount
        if straight > 0 {
            return "\(straight) stretch\(straight == 1 ? "" : "es") had no \(draft.snapMode.title.lowercased()) route — joined straight, shown dashed."
        }
        return nil
    }

    // MARK: - Controls

    private func glassButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.mapControlLabel)
                .frame(width: 38, height: 38)
                .background(Theme.mapControl, in: .circle)
                .overlay { Circle().strokeBorder(Theme.mapControlBorder, lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }

    private func mapButton(
        symbol: String,
        label: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(
                    isEnabled ? Theme.mapControlLabel : Theme.mapControlLabel.opacity(0.3)
                )
                .frame(width: 42, height: 42)
                .background(Theme.mapControl, in: .rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Theme.mapControlBorder, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }

    private func actionButton(
        symbol: String,
        label: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(
                Theme.mapControlLabel.opacity(isEnabled ? 0.75 : 0.25)
            )
            .background(Theme.mapFill, in: .rect(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    // MARK: - Actions

    /// A new route opens following the ground its activity implies — two points
    /// on a hillside should join along the path between them. An existing route
    /// is loaded exactly as saved and follows its own activity.
    private func prepare() {
        guard draft.isEmpty else { return }
        guard let editing else {
            draft.snapMode = .default(for: activity)
            return
        }
        draft.load(from: editing)
        activity = editing.activity
        draft.snapMode = .default(for: editing.activity)
        recenterToken += 1
    }

    private var gpxContentTypes: [UTType] {
        var types: [UTType] = [.xml, .data]
        if let gpx = UTType(filenameExtension: "gpx") {
            types.insert(gpx, at: 0)
        }
        return types
    }

    private func suggestedName() -> String {
        if let editing { return editing.name }
        let hour = Calendar.current.component(.hour, from: Date())
        let period = switch hour {
        case 4..<11: "Morning"
        case 11..<15: "Midday"
        case 15..<19: "Afternoon"
        default: "Evening"
        }
        return "\(period) \(activity.rawValue)"
    }

    private func save() {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        var route = draft.makeRoute(
            name: name.isEmpty ? suggestedName() : name,
            activity: activity,
            source: editing?.source ?? .mine
        )
        if let editing {
            route.id = editing.id
            route.createdAt = editing.createdAt
        }
        store.add(route)
        onSaved(route)
        dismiss()
    }
}

// MARK: - Profile sheet

/// The elevation profile, kept off the map so the map stays whole.
private struct RouteProfileSheet: View {
    let draft: RouteDraftModel
    let activity: RouteActivityType

    @Environment(\.dismiss) private var dismiss

    private var samples: [ElevationSample] {
        ElevationProfile.samples(for: draft.points)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if draft.elevationState == .measured {
                        HStack {
                            Text("Elevation along route")
                                .font(.system(.subheadline, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            if let low = draft.minElevation, let high = draft.maxElevation {
                                Text("\(Formatters.elevation(low)) — \(Formatters.elevation(high)) \(Formatters.units.elevationUnit)")
                                    .font(.system(.caption, weight: .medium))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                            }
                        }
                        ElevationChart(samples: samples, waypoints: draft.waypoints, height: 180)
                        Text(ElevationTileService.attribution)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textPrimary.opacity(0.4))
                    } else {
                        ContentUnavailableView(
                            draft.elevationState == .loading ? "Measuring terrain" : "No terrain data",
                            systemImage: draft.elevationState == .loading ? "arrow.down.circle.dotted" : "wifi.slash",
                            description: Text(
                                draft.elevationState == .loading
                                    ? "Downloading the surveyed ground under your line."
                                    : "Terrain tiles for this area could not be reached. The profile stays blank rather than showing a guess."
                            )
                        )
                        .padding(.top, 40)
                    }

                    if !draft.waypoints.isEmpty {
                        Divider()
                        Text("Waypoints")
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        ForEach(draft.waypoints) { waypoint in
                            HStack(spacing: 10) {
                                Image(systemName: "mappin")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Theme.accent)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(waypoint.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                    if !waypoint.note.isEmpty {
                                        Text(waypoint.note)
                                            .font(.caption2)
                                            .foregroundStyle(Theme.textPrimary.opacity(0.55))
                                    }
                                }
                                Spacer(minLength: 0)
                                Text("\(Formatters.distance(waypoint.distanceAlongRoute)) \(Formatters.units.distanceUnit)")
                                    .font(.metric(12, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                            }
                            .padding(10)
                            .panel(radius: 12)
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.canvas)
            .navigationTitle("\(Formatters.distance(draft.distance)) \(Formatters.units.distanceUnit)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationContentInteraction(.scrolls)
    }
}

// MARK: - Node editor

/// Tapping a point on the map opens this: name it, or take it out.
private struct NodeEditorSheet: View {
    let node: RouteDraftModel.Node
    let index: Int
    let onSave: (String, String) -> Void
    let onPlain: () -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var note: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Waypoint") {
                    TextField("Name", text: $name)
                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section {
                    Button {
                        onSave(name.isEmpty ? "Waypoint \(index)" : name, note)
                    } label: {
                        Label("Save as waypoint", systemImage: "mappin.and.ellipse")
                    }
                    if node.isWaypoint {
                        Button {
                            onPlain()
                        } label: {
                            Label("Make it a plain shaping point", systemImage: "circle")
                        }
                    }
                } footer: {
                    Text("Named waypoints show on your watch mid-workout and in Up Ahead. Plain points only shape the line.")
                }

                Section {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Remove this point", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Point \(index)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            name = node.name
            note = node.note
        }
    }
}
