import SwiftUI

/// Design the Apple Watch workout screens from the phone, with a live
/// wrist-shaped preview of exactly what you will see mid-effort.
struct WatchSetupView: View {
    @Environment(WatchLayoutStore.self) private var layout
    @Environment(\.dismiss) private var dismiss

    @State private var sport: WatchSportProfile = .trailRun
    @State private var family: WatchSportFamily = .run
    @State private var previewIndex = 0
    @State private var isAddingPage = false
    @State private var showsResetConfirmation = false

    private var pages: [WatchPage] {
        layout.pages(for: sport)
    }

    private var previewPage: WatchPage? {
        guard !pages.isEmpty else { return nil }
        return pages[min(previewIndex, pages.count - 1)]
    }

    var body: some View {
        List {
            previewSection
            sportSection
            pagesSection
            optionsSection
            appearanceSection
            powerSection
            mirrorSection
            deliverySection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("Apple Watch")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
        }
        .sheet(isPresented: $isAddingPage) {
            NavigationStack {
                AddWatchPageView(sport: sport)
            }
            .presentationDetents([.medium, .large])
        }
        .confirmationDialog("Reset \(sport.title) screens?", isPresented: $showsResetConfirmation, titleVisibility: .visible) {
            Button("Reset to default", role: .destructive) {
                layout.resetPages(for: sport)
                previewIndex = 0
            }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: sport) { _, newValue in
            previewIndex = 0
            family = newValue.family
        }
        .onAppear { family = sport.family }
    }

    // MARK: - Preview

    private var previewSection: some View {
        Section {
            VStack(spacing: 12) {
                if let previewPage {
                    WatchPagePreview(page: previewPage, sport: sport)
                        .id(previewPage.id)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        .shadow(color: .black.opacity(0.6), radius: 18, y: 10)
                } else {
                    Text("No pages yet")
                        .font(.footnote)
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                        .frame(height: 204)
                }

                if pages.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                            Button {
                                withAnimation(.snappy(duration: 0.25)) { previewIndex = index }
                            } label: {
                                Capsule()
                                    .fill(index == previewIndex ? sport.tint : Theme.surfaceRaised)
                                    .frame(width: index == previewIndex ? 18 : 6, height: 6)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Preview \(page.title)")
                        }
                    }
                }

                if let previewPage {
                    VStack(spacing: 2) {
                        Text(previewPage.title)
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Page \(min(previewIndex, pages.count - 1) + 1) of \(pages.count)")
                            .font(.caption2)
                            .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        } footer: {
            Text("Swipe through these pages on the watch during a workout. The controls page — lap, pause, end — always comes first.")
        }
    }

    // MARK: - Sport

    /// Family first, then the sports inside it — with fifty-odd activities a
    /// single row would be an endless scroll.
    private var sportSection: some View {
        Section {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(WatchSportFamily.allCases) { candidate in
                        Button {
                            withAnimation(.snappy(duration: 0.2)) { family = candidate }
                        } label: {
                            Text(candidate.title)
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .foregroundStyle(candidate == family ? candidate.tint : Theme.textPrimary.opacity(0.65))
                                .background(
                                    candidate == family ? candidate.tint.opacity(0.16) : Theme.surfaceRaised,
                                    in: .capsule
                                )
                                .overlay {
                                    Capsule().strokeBorder(
                                        candidate == family ? candidate.tint : Color.clear,
                                        lineWidth: 1
                                    )
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 0, trailing: 0))

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(family.sports) { candidate in
                        Button {
                            withAnimation(.snappy(duration: 0.2)) { sport = candidate }
                        } label: {
                            Text(candidate.title)
                                .font(.system(size: 11, weight: .semibold))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                                .padding(.horizontal, 6)
                                .frame(width: 72, height: 56)
                            .foregroundStyle(candidate == sport ? Theme.canvas : Theme.textPrimary.opacity(0.75))
                            .background(
                                candidate == sport ? candidate.tint : Theme.surfaceRaised,
                                in: .rect(cornerRadius: 12)
                            )
                            .overlay(alignment: .topTrailing) {
                                if layout.isCustomized(candidate) {
                                    Circle()
                                        .fill(candidate == sport ? Theme.canvas : Theme.accent)
                                        .frame(width: 5, height: 5)
                                        .padding(5)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 4, trailing: 0))
        } header: {
            Text("Activity")
        } footer: {
            Text("\(family.title) · \(family.summary). Editing \(sport.title).")
        }
    }

    // MARK: - Pages

    private var pagesSection: some View {
        Section {
            ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                NavigationLink {
                    WatchPageEditorView(sport: sport, pageID: page.id)
                } label: {
                    pageRow(page)
                }
                // Nothing may be attached here that competes for the tap. A tap
                // gesture on the row — even a simultaneous one — races the link
                // and the row stops opening. The preview is driven by the dots
                // above and by opening a page, never by a gesture on the link.
                .swipeActions(edge: .leading) {
                    Button {
                        layout.togglePage(id: page.id, for: sport)
                    } label: {
                        Label(page.isEnabled ? "Hide" : "Show", systemImage: page.isEnabled ? "eye.slash" : "eye")
                    }
                    .tint(Theme.highlight)
                }
            }
            .onMove { offsets, destination in
                layout.movePages(fromOffsets: offsets, toOffset: destination, for: sport)
            }
            .onDelete { offsets in
                layout.removePages(at: offsets, from: sport)
                previewIndex = 0
            }

            Button {
                isAddingPage = true
            } label: {
                Label("Add page", systemImage: "plus.circle.fill")
                    .foregroundStyle(Theme.accent)
            }

            if layout.isCustomized(sport) {
                Button(role: .destructive) {
                    showsResetConfirmation = true
                } label: {
                    Label("Reset \(sport.title) to default", systemImage: "arrow.counterclockwise")
                }
            }
        } header: {
            Text("Pages · \(sport.title)")
        } footer: {
            Text("Drag to reorder with Edit, swipe left to delete, swipe right to hide a page without losing its setup.")
        }
    }

    private func pageRow(_ page: WatchPage) -> some View {
        HStack(spacing: 12) {
            Image(systemName: page.kind.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(page.isEnabled ? sport.tint : Theme.textPrimary.opacity(0.35))
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(page.title)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(page.isEnabled ? Theme.textPrimary : Theme.textPrimary.opacity(0.45))
                Text(page.summary)
                    .font(.caption2)
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if !page.isEnabled {
                Image(systemName: "eye.slash.fill")
                    .font(.caption2)
                    .foregroundStyle(Theme.textPrimary.opacity(0.4))
            }
        }
        .contentShape(.rect)
    }

    // MARK: - Options

    @ViewBuilder
    private var optionsSection: some View {
        @Bindable var bindableLayout = layout

        Section("Workout behaviour") {
            Toggle("Auto lap", isOn: $bindableLayout.isAutoLapEnabled)
            if layout.isAutoLapEnabled {
                Stepper(value: $bindableLayout.autoLapKilometres, in: 0.5...10, step: 0.5) {
                    HStack {
                        Text("Every")
                        Spacer()
                        Text("\(layout.autoLapKilometres, specifier: "%.1f") \(layout.unitSystem.distanceUnit)")
                            .font(.metric(15))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            Toggle("Auto pause", isOn: $bindableLayout.isAutoPauseEnabled)
            Toggle("Haptic alerts", isOn: $bindableLayout.usesHapticAlerts)
            Toggle("Satellite map", isOn: $bindableLayout.prefersHybridMap)
            Toggle("Always-on metrics", isOn: $bindableLayout.keepsScreenOn)

            Stepper(value: $bindableLayout.maxHeartRate, in: 140...220) {
                HStack {
                    Text("Max heart rate")
                    Spacer()
                    Text("\(layout.maxHeartRate) bpm")
                        .font(.metric(15))
                        .foregroundStyle(Theme.danger)
                }
            }
        }
    }

    // MARK: - Appearance

    /// Line colours and metric type, set here because a phone is a far easier
    /// place to make a visual choice than a watch — then carried to the wrist in
    /// the same document as the pages.
    @ViewBuilder
    private var appearanceSection: some View {
        @Bindable var bindableLayout = layout

        Section {
            trailColorRow(
                title: "Course line",
                caption: "The route you planned",
                selection: $bindableLayout.routeTrailColor
            )
            trailColorRow(
                title: "Your trail",
                caption: "The breadcrumb behind you",
                selection: $bindableLayout.breadcrumbTrailColor
            )

            Picker("Metric typeface", selection: $bindableLayout.metricTypeface) {
                Text("Rounded").tag("rounded")
                Text("Instrument").tag("instrument")
                Text("Classic").tag("classic")
                Text("Serif").tag("serif")
            }

            Picker("Metric weight", selection: $bindableLayout.metricWeight) {
                Text("Light").tag("light")
                Text("Standard").tag("standard")
                Text("Heavy").tag("heavy")
            }

            Picker("Readout colour", selection: $bindableLayout.fieldTint) {
                Text("Automatic").tag("auto")
                Text("Plain white").tag("mono")
                Text("Orange").tag("orange")
                Text("Amber").tag("amber")
                Text("Lime").tag("lime")
                Text("Cyan").tag("cyan")
                Text("Blue").tag("blue")
                Text("Violet").tag("violet")
                Text("Magenta").tag("magenta")
            }
        } header: {
            Text("Colours & type")
        } footer: {
            Text("Line colours apply to maps on both devices. Typeface and readout colour apply to the watch's metric screens.")
        }
    }

    /// A colour choice shown as colour, not as a list of names.
    private func trailColorRow(
        title: String,
        caption: String,
        selection: Binding<TrailColor>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .foregroundStyle(Theme.textPrimary)
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                }
                Spacer()
                Text(selection.wrappedValue.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(selection.wrappedValue.color)
            }

            HStack(spacing: 10) {
                ForEach(TrailColor.allCases) { option in
                    Button {
                        selection.wrappedValue = option
                    } label: {
                        Circle()
                            .fill(option.color)
                            .frame(width: 26, height: 26)
                            .overlay {
                                Circle()
                                    .strokeBorder(
                                        Theme.textPrimary,
                                        lineWidth: selection.wrappedValue == option ? 2.5 : 0
                                    )
                                    .padding(-3)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.title)
                    .accessibilityAddTraits(
                        selection.wrappedValue == option ? [.isSelected, .isButton] : .isButton
                    )
                }
            }
            .animation(.snappy(duration: 0.2), value: selection.wrappedValue)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Power

    /// Power saver, set up here and applied on the wrist.
    private var powerSection: some View {
        @Bindable var bindableLayout = layout

        return Section {
            Toggle(isOn: $bindableLayout.isPowerSaverEnabled) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Power saver")
                    Text("Start every watch workout in low power")
                        .font(.caption2)
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                }
            }

            // No hours are quoted here on purpose. Only the watch can watch its
            // own battery, and that measurement never reaches this phone — so
            // anything printed here would be a constant pretending to be a
            // forecast, and wrong by hours on a cold day.
            Label(
                "Your watch measures its own battery drain during workouts and shows the hours it has left under Power on the wrist.",
                systemImage: "battery.100percent.bolt"
            )
            .font(.caption)
            .foregroundStyle(Theme.textPrimary.opacity(0.6))

            Stepper(value: $bindableLayout.powerSaverThreshold, in: 0...50, step: 5) {
                HStack {
                    Text("Switch on at")
                    Spacer()
                    Text(layout.powerSaverThreshold == 0 ? "Off" : "\(layout.powerSaverThreshold)%")
                        .font(.metric(15))
                        .foregroundStyle(layout.powerSaverThreshold == 0 ? Theme.textPrimary.opacity(0.5) : Theme.positive)
                }
            }

            Toggle(isOn: $bindableLayout.usesWaterLock) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Auto water lock")
                    Text("Locks the watch screen for swims")
                        .font(.caption2)
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                }
            }

            Toggle(isOn: $bindableLayout.confirmsWorkoutEnd) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Confirm before stopping")
                    Text(layout.confirmsWorkoutEnd
                         ? "The watch asks before ending a workout"
                         : "End saves the workout straight away")
                        .font(.caption2)
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                }
            }

            DisclosureGroup("What power saver changes") {
                ForEach(PowerSaverPlan.changes) { change in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(change.title)
                                .font(.system(.subheadline, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text(change.detail)
                                .font(.caption2)
                                .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        }
                    } icon: {
                        Image(systemName: change.symbol)
                            .foregroundStyle(Theme.positive)
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            Text("Battery")
        } footer: {
            Text("Estimates assume a full charge with GPS recording. Time, distance, elevation and laps are recorded exactly the same in either mode — heart rate is the one thing you trade away.")
        }
    }

    private func batteryEstimate(title: String, value: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
            Text(value)
                .font(.metric(24, weight: .bold))
                .foregroundStyle(tint)
            Text("of recording")
                .font(.caption2)
                .foregroundStyle(Theme.textPrimary.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.surfaceRaised, in: .rect(cornerRadius: 14))
    }

    // MARK: - Mirror

    /// Explains the two-way relationship and surfaces the last wrist edit.
    private var mirrorSection: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Today dashboard mirrored")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Your tiles, readiness, zones and history appear on the watch with the same layout.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                }
            } icon: {
                Image(systemName: "square.grid.2x2.fill")
                    .foregroundStyle(Theme.accent)
            }

            if let summary = WatchLink.shared.lastWatchEditSummary,
               let date = WatchLink.shared.lastWatchEditAt {
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(summary)
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Applied here \(date.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    }
                } icon: {
                    Image(systemName: "arrow.down.left.arrow.up.right")
                        .foregroundStyle(Theme.highlight)
                }
            }
        } header: {
            Text("Two-way sync")
        } footer: {
            Text("Edit on either device. Changes made on the watch — screens, options or dashboard tiles — come straight back to this app.")
        }
    }

    // MARK: - Delivery

    private var deliverySection: some View {
        Section {
            switch layout.delivery {
            case .sending(let progress):
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sending layout…")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    ProgressView(value: progress)
                        .tint(Theme.accent)
                }
            case .delivered(let date):
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Layout on your watch")
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Transferred \(date.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    }
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(red: 0.32, green: 0.85, blue: 0.55))
                }
            case .failed(let message):
                VStack(alignment: .leading, spacing: 6) {
                    Label("Couldn't send", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.danger)
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                    Button("Try again") { layout.sendToWatch() }
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            case .idle:
                Button {
                    layout.sendToWatch()
                } label: {
                    Label("Send layout to Apple Watch", systemImage: "applewatch.radiowaves.left.and.right")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }

            if let workout = WatchLink.shared.lastWorkout {
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Workout received from watch")
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("\(WatchSportProfile(rawValue: workout.sport)?.title ?? workout.sport) · \(Formatters.compactDuration(workout.duration)) · \(Formatters.distance(workout.distance)) km")
                            .font(.caption2)
                            .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    }
                } icon: {
                    Image(systemName: "arrow.down.heart")
                        .foregroundStyle(Theme.highlight)
                }
            }
        } footer: {
            Text(WatchLink.shared.isPaired && WatchLink.shared.isWatchAppInstalled
                ? "Transfers run over WatchConnectivity. The watch stores the layout itself, so your screens work with the phone left at home."
                : "No Apple Watch running Trekka detected. Pair your watch, install the app, then send again.")
        }
    }
}

/// Adds a new page to a sport, either a preset data screen or a special page.
struct AddWatchPageView: View {
    let sport: WatchSportProfile

    @Environment(WatchLayoutStore.self) private var layout
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section("Data screens") {
                ForEach(presets, id: \.name) { preset in
                    Button {
                        layout.addPage(.data(preset.fields, layout: preset.layout), to: sport)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            WatchLayoutGlyph(layout: preset.layout, tint: sport.tint, isSelected: true)
                                .frame(width: 30, height: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name)
                                    .font(.system(.subheadline, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text(preset.fields.isEmpty ? "Start from nothing" : preset.fields.map(\.title).joined(separator: " · "))
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }

            Section("Special pages") {
                ForEach(WatchPageKind.allCases.filter { $0 != .data }) { kind in
                    Button {
                        layout.addPage(.page(kind), to: sport)
                        dismiss()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.title)
                                    .font(.system(.subheadline, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text(kind.detail)
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                            }
                        } icon: {
                            Image(systemName: kind.symbol)
                                .foregroundStyle(sport.tint)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("Add Page")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    /// Starting points, each with the shape it is meant to be read in. Every one
    /// can be rearranged afterwards.
    private var presets: [(name: String, fields: [WatchMetric], layout: WatchPageLayout?)] {
        let tempo: WatchMetric = sport.usesPace ? .pace : .speed
        return [
            ("Single big number", [tempo], WatchPageLayout(rows: [1])),
            ("Classic three", [.duration, .distance, tempo], WatchPageLayout(rows: [1, 2])),
            ("Four up", [.duration, .distance, tempo, .heartRate], WatchPageLayout(rows: [2, 2])),
            ("One, pair, one", [tempo, .distance, .heartRate, .duration], WatchPageLayout(rows: [1, 2, 1])),
            ("Climbing", [.grade, .ascent, .altitude, .verticalSpeed], WatchPageLayout(rows: [1, 3])),
            ("Lap focus", [.lapTime, .lapDistance, .lapPace, .averageHeartRate], WatchPageLayout(rows: [2, 2])),
            ("Navigation", [.eta, .remainingDistance, .distanceToWaypoint, .nextWaypoint], WatchPageLayout(rows: [1, 2, 1])),
            ("Everything", [.duration, .distance, tempo, .heartRate, .ascent, .calories], WatchPageLayout(rows: [2, 2, 2])),
            ("Blank screen", [], nil),
        ]
    }
}
