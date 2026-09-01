import SwiftUI

/// Design the Apple Watch workout screens from the phone, with a live
/// wrist-shaped preview of exactly what you will see mid-effort.
///
/// This screen does one job — arrange the pages for one activity — and the
/// preview, the activity and the page list are the only things on it. Everything
/// that is set once and then left alone (colours, alerts, battery, the state of
/// the link) sits a tap away instead of stacked underneath, because those
/// settings were pushing the actual page list so far down the screen that the
/// thing this screen is for was the hardest part of it to reach.
struct WatchSetupView: View {
    @Environment(WatchLayoutStore.self) private var layout

    @State private var sport: WatchSportProfile = .trailRun
    @State private var previewIndex = 0
    @State private var isAddingPage = false
    @State private var isChoosingSport = false
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
            settingsSection
            sendSection
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
        .sheet(isPresented: $isChoosingSport) {
            NavigationStack {
                WatchSportPickerView(selection: $sport)
            }
        }
        .confirmationDialog("Reset \(sport.title) screens?", isPresented: $showsResetConfirmation, titleVisibility: .visible) {
            Button("Reset to default", role: .destructive) {
                layout.resetPages(for: sport)
                previewIndex = 0
            }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: sport) { _, _ in previewIndex = 0 }
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
        }
    }

    // MARK: - Activity

    /// One row, not two scrollers. Which activity you are editing is a single
    /// fact, so it reads as a single line — and the fifty-odd choices behind it
    /// live in a searchable list where that many entries belong.
    private var sportSection: some View {
        Section {
            Button {
                isChoosingSport = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: sport.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(sport.tint)
                        .frame(width: 32, height: 32)
                        .background(sport.tint.opacity(0.16), in: .circle)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(sport.title)
                            .font(.system(.body, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(layout.isCustomized(sport) ? "Your own screens" : "Default screens")
                            .font(.caption2)
                            .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.4))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        } header: {
            Text("Editing")
        }
    }

    // MARK: - Pages

    private var pagesSection: some View {
        Section {
            ForEach(Array(pages.enumerated()), id: \.element.id) { _, page in
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
                    Label("Reset to default", systemImage: "arrow.counterclockwise")
                }
            }
        } header: {
            Text("Pages")
        } footer: {
            Text("Swipe through these on the watch during a workout — the controls page always comes first. Drag to reorder with Edit, swipe left to delete, swipe right to hide a page without losing its setup.")
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

    // MARK: - Settings

    /// The four things that used to be twenty-odd controls stacked below the
    /// page list. Each row carries what it is currently set to, so the settings
    /// can still be read at a glance without being operated at a glance.
    private var settingsSection: some View {
        Section {
            NavigationLink {
                WatchAppearanceView()
            } label: {
                settingRow(
                    "Appearance",
                    symbol: "paintpalette.fill",
                    tint: Theme.accent,
                    detail: appearanceSummary
                )
            }

            NavigationLink {
                WatchBehaviourView()
            } label: {
                settingRow(
                    "During a workout",
                    symbol: "figure.run",
                    tint: Theme.highlight,
                    detail: behaviourSummary
                )
            }

            NavigationLink {
                WatchPowerView()
            } label: {
                settingRow(
                    "Battery",
                    symbol: "battery.100percent.bolt",
                    tint: Theme.positive,
                    detail: powerSummary
                )
            }

            NavigationLink {
                WatchSyncView()
            } label: {
                settingRow(
                    "Sync",
                    symbol: "applewatch.radiowaves.left.and.right",
                    tint: Theme.textPrimary.opacity(0.7),
                    detail: syncSummary
                )
            }
        } header: {
            Text("Watch settings")
        } footer: {
            Text("These apply to every activity, not just \(sport.title).")
        }
    }

    private func settingRow(
        _ title: String,
        symbol: String,
        tint: Color,
        detail: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                    .lineLimit(1)
            }
        }
    }

    private var appearanceSummary: String {
        [
            MetricTypefaceOption.title(for: layout.metricTypeface),
            MetricTintOption.title(for: layout.fieldTint),
            layout.prefersHybridMap ? "Satellite" : "Topographic",
        ].joined(separator: " · ")
    }

    private var behaviourSummary: String {
        var parts: [String] = []
        parts.append(
            layout.isAutoLapEnabled
                ? "Auto lap \(layout.autoLapKilometres.formatted(.number.precision(.fractionLength(0...1)))) \(layout.unitSystem.distanceUnit)"
                : "No auto lap"
        )
        if layout.isAutoPauseEnabled { parts.append("Auto pause") }
        parts.append("\(layout.maxHeartRate) bpm max")
        return parts.joined(separator: " · ")
    }

    private var powerSummary: String {
        if layout.isPowerSaverEnabled { return "Always on low power" }
        if layout.powerSaverThreshold > 0 { return "Low power at \(layout.powerSaverThreshold)%" }
        return "Full power"
    }

    private var syncSummary: String {
        switch layout.delivery {
        case .sending: "Sending…"
        case .delivered(let date): "Sent \(date.formatted(date: .omitted, time: .shortened))"
        case .failed: "Couldn't send"
        case .idle: WatchLink.shared.isWatchAppInstalled ? "Changes not sent yet" : "No watch detected"
        }
    }

    // MARK: - Send

    /// The one action on this screen, kept where an action belongs: at the end,
    /// alone, after everything it sends has been decided.
    private var sendSection: some View {
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
            case .delivered(let date):
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("On your watch")
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Transferred \(date.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    }
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.positive)
                }
            case .idle:
                Button {
                    layout.sendToWatch()
                } label: {
                    Label("Send to Apple Watch", systemImage: "applewatch.radiowaves.left.and.right")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }
}
