import SwiftUI

/// Edits one page: its position in the stack and, for data screens, the shape
/// of the screen and the metric in every block, with a live preview.
struct ScreenDetailEditorView: View {
    let sport: WatchSport
    let screenID: UUID

    @Environment(WatchScreenSettings.self) private var settings
    @State private var editingSlot: Int?
    @State private var isAddingField = false

    private var screen: WatchScreen? {
        settings.screen(id: screenID, for: sport)
    }

    var body: some View {
        List {
            if let screen {
                Section {
                    DataPageView(screen: screen, metrics: Self.previewMetrics, sport: sport)
                        .frame(height: previewHeight(for: screen))
                        .padding(8)
                        .watchPanel()
                        .listRowBackground(Color.clear)
                        .allowsHitTesting(false)
                } header: {
                    Text("Preview")
                }

                if screen.kind == .data {
                    Section {
                        NavigationLink {
                            LayoutBuilderView(
                                sport: sport,
                                initial: screen.layout,
                                fieldCount: screen.fields.count
                            ) { layout in
                                settings.setLayout(layout, screenID: screenID, sport: sport)
                            }
                        } label: {
                            layoutRow(screen)
                        }
                    } header: {
                        Text("Layout")
                    }

                    Section {
                        ForEach(Array(screen.fields.enumerated()), id: \.offset) { slot, field in
                            Button {
                                editingSlot = slot
                            } label: {
                                slotRow(slot: slot, field: field, screen: screen)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    settings.removeField(at: slot, screenID: screenID, sport: sport)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }

                        // With a chosen layout the block count is fixed, so the
                        // way to make room is to pick a bigger arrangement. An
                        // automatic screen stops growing at what this watch holds.
                        if screen.layout == nil, screen.fields.count < WatchDisplay.capacity.maxSlots {
                            Button {
                                isAddingField = true
                            } label: {
                                Label("Add metric", systemImage: "plus.circle.fill")
                                    .foregroundStyle(WatchTheme.accent)
                            }
                        }
                    } header: {
                        Text("Blocks · \(screen.fields.count)")
                    } footer: {
                        Text(blockHint(for: screen))
                            .font(.system(size: 10))
                    }
                }

                Section("Page position") {
                    Button {
                        settings.move(screenID: screenID, by: -1, for: sport)
                    } label: {
                        Label("Move earlier", systemImage: "arrow.up")
                    }
                    Button {
                        settings.move(screenID: screenID, by: 1, for: sport)
                    } label: {
                        Label("Move later", systemImage: "arrow.down")
                    }
                    Button {
                        settings.toggleScreen(id: screenID, for: sport)
                    } label: {
                        Label(
                            screen.isEnabled ? "Hide during workouts" : "Show during workouts",
                            systemImage: screen.isEnabled ? "eye.slash" : "eye"
                        )
                    }
                }
            } else {
                Text("This page was removed.")
                    .foregroundStyle(WatchTheme.textSecondary)
            }
        }
        .navigationTitle(screen?.kind.title ?? "Page")
        .sheet(item: Binding(get: { editingSlot.map(SlotSelection.init) }, set: { editingSlot = $0?.slot })) { selection in
            NavigationStack {
                FieldPickerView(sport: sport, title: "Block \(selection.slot + 1)") { field in
                    settings.replaceField(at: selection.slot, with: field, screenID: screenID, sport: sport)
                    editingSlot = nil
                }
            }
        }
        .sheet(isPresented: $isAddingField) {
            NavigationStack {
                FieldPickerView(sport: sport, title: "Add Metric") { field in
                    settings.addField(field, screenID: screenID, sport: sport)
                    isAddingField = false
                }
            }
        }
    }

    private struct SlotSelection: Identifiable {
        let slot: Int
        var id: Int { slot }
    }

    /// The layout row: a diagram of the current shape and what it holds.
    private func layoutRow(_ screen: WatchScreen) -> some View {
        HStack(spacing: 8) {
            WatchLayoutDiagram(layout: screen.layout, tint: sport.tint, isSelected: true)
                .frame(width: 24, height: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(screen.layout?.title ?? "Automatic")
                    .font(.metric(13, weight: .semibold))
                    .foregroundStyle(WatchTheme.textPrimary)
                Text(screen.layout == nil
                     ? "Fits itself to your metrics"
                     : "Rows and fields you set")
                    .font(.system(size: 9))
                    .foregroundStyle(WatchTheme.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    private func blockHint(for screen: WatchScreen) -> String {
        screen.layout == nil
            ? "Tap a block to swap its metric, swipe to remove. Open Layout to set the rows yourself."
            : "Tap a block to swap its metric. Add or remove blocks by changing the rows in Layout."
    }

    private func slotRow(slot: Int, field: WatchDataField, screen: WatchScreen) -> some View {
        HStack(spacing: 8) {
            Text("\(slot + 1)")
                .font(.metric(12, weight: .bold))
                .foregroundStyle(slot == 0 ? sport.tint : WatchTheme.textSecondary)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 0) {
                Text(field.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WatchTheme.textPrimary)
                    .lineLimit(1)
                Text(screen.resolvedLayout.position(ofSlot: slot))
                    .font(.system(size: 9))
                    .foregroundStyle(WatchTheme.textSecondary)
            }

            Spacer(minLength: 0)

            if slot > 0 {
                Button {
                    settings.moveField(at: slot, by: -1, screenID: screenID, sport: sport)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(WatchTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Move \(field.title) up")
            }
        }
    }

    /// Tall enough for the arrangement being drawn, so the preview is a fair
    /// picture of the real page rather than a squashed one.
    private func previewHeight(for screen: WatchScreen) -> CGFloat {
        guard !screen.fields.isEmpty else { return 72 }
        switch screen.resolvedLayout.rows.count {
        case 1: return 78
        case 2: return 100
        case 3: return 122
        default: return 142
        }
    }

    /// Frozen mid-run values so the preview reads like a real workout.
    static let previewMetrics: LiveMetrics = {
        var metrics = LiveMetrics()
        metrics.elapsed = 2892
        metrics.movingTime = 2810
        metrics.distance = 8420
        metrics.lapDistance = 620
        metrics.lapElapsed = 364
        metrics.lapCount = 8
        metrics.currentSpeed = 3.21
        metrics.maxSpeed = 5.05
        metrics.bestPace = 276
        metrics.heartRate = 154
        metrics.averageHeartRate = 147
        metrics.maxHeartRate = 172
        metrics.isHeartRateEstimated = false
        metrics.calories = 612
        metrics.trainingEffect = 3.4
        metrics.power = 268
        metrics.cadence = 172
        metrics.averageCadence = 168
        metrics.ascent = 612
        metrics.descent = 418
        metrics.altitude = 1284
        metrics.grade = 6.4
        metrics.verticalSpeed = 684
        metrics.zoneSeconds = [180, 640, 1120, 720, 210]
        metrics.remainingDistance = 4100
        metrics.distanceToWaypoint = 480
        metrics.nextWaypointName = "Saddle"
        metrics.etaSeconds = 1280
        metrics.batteryFraction = 0.78
        return metrics
    }()
}

