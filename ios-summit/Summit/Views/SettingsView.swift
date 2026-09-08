import SwiftUI

nonisolated enum SettingsDestination: Hashable, Sendable {
    case watch
    case backup
    case goals
    case eventLog
}

/// Everything that configures Trekka, gathered in one place instead of hiding
/// behind toolbar glyphs on the dashboard.
struct SettingsView: View {
    @Environment(RouteStore.self) private var store
    @Environment(HealthService.self) private var health
    @Environment(DashboardSettings.self) private var dashboard
    @Environment(WatchLayoutStore.self) private var watchLayout
    @Environment(AppearanceSettings.self) private var appearance
    @Environment(UnitSettings.self) private var units
    @Environment(MapPackStore.self) private var mapPacks
    @Environment(ProfileSettings.self) private var profile
    @Environment(GoalSettings.self) private var goals
    @Environment(ConsentSettings.self) private var consent
    @Binding var path: NavigationPath

    @State private var showsHealthSheet = false
    @State private var showsCustomizeSheet = false
    @State private var readingDocument: LegalDocument?
    @State private var draftName = ""
    @FocusState private var isEditingName: Bool
    @State private var feedback = 0

    private var syncedRouteCount: Int {
        store.routes.filter(\.isSyncedToWatch).count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                identityCard

                section("Dashboard") {
                    row(
                        symbol: "target",
                        title: "Daily goals",
                        detail: goalDetail
                    ) {
                        path.append(SettingsDestination.goals)
                    }
                    divider
                    row(
                        symbol: "square.grid.2x2.fill",
                        title: "Customize tiles",
                        detail: "\(dashboard.visibleMetrics.count) shown · \(dashboard.showsTileCharts ? "with charts" : "no charts")"
                    ) {
                        showsCustomizeSheet = true
                    }
                    divider
                    row(
                        symbol: "arrow.counterclockwise",
                        title: "Reset to defaults",
                        detail: "Restores Trekka's original layout",
                        showsChevron: false
                    ) {
                        dashboard.resetToDefaults()
                        feedback += 1
                    }
                }

                section("Appearance") {
                    HStack(spacing: 8) {
                        appearanceOption(.system)
                        appearanceOption(.dark)
                        appearanceOption(.light)
                    }
                    .padding(12)
                }

                section("Units") {
                    HStack(spacing: 8) {
                        unitOption(.metric)
                        unitOption(.imperial)
                    }
                    .padding(12)

                    divider

                    unitOverrideRow(
                        symbol: "dumbbell.fill",
                        title: "Weight",
                        metricLabel: "kg",
                        imperialLabel: "lb",
                        selection: units.massUnits,
                        onChange: { system in
                            units.setMass(system)
                            watchLayout.massSystem = system
                            watchLayout.pushSilently()
                            feedback += 1
                        }
                    )

                    divider

                    unitOverrideRow(
                        symbol: "mountain.2.fill",
                        title: "Elevation",
                        metricLabel: "m",
                        imperialLabel: "ft",
                        selection: units.elevationUnits,
                        onChange: { system in
                            units.setElevation(system)
                            watchLayout.elevationSystem = system
                            watchLayout.pushSilently()
                            feedback += 1
                        }
                    )

                    divider

                    // Say plainly that this is a display choice. Nothing already
                    // recorded changes, and the watch follows the phone, so
                    // neither device can end up quietly quoting the other's unit.
                    Text("Applies everywhere on the phone and on your watch. Weight and elevation can each follow their own unit. Recorded workouts are unchanged — only how they are shown.")
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary.opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }

                section("Apple Watch") {
                    row(
                        symbol: "applewatch",
                        title: "Watch screens & power",
                        detail: watchDetail
                    ) {
                        path.append(SettingsDestination.watch)
                    }
                }

                section("Apple Health") {
                    row(
                        symbol: "heart.text.square.fill",
                        title: health.authorization == .authorized ? "Connected" : "Connect Apple Health",
                        detail: healthDetail,
                        tint: health.authorization == .authorized ? Theme.positive : Theme.accent
                    ) {
                        showsHealthSheet = true
                    }
                }

                section("Your data") {
                    row(
                        symbol: "icloud",
                        title: "Backup & restore",
                        detail: "Save to iCloud or export a file"
                    ) {
                        path.append(SettingsDestination.backup)
                    }
                }

                section("Storage") {
                    infoRow(symbol: "map", title: "Routes", value: "\(store.routes.count)")
                    divider
                    infoRow(symbol: "waveform.path.ecg", title: "Recorded activities", value: "\(store.activities.count)")
                    divider
                    // The offline map is managed on the Routes tab, beside the
                    // routes it covers. The figure is here because this is
                    // where anyone freeing up space will look first.
                    infoRow(
                        symbol: "internaldrive",
                        title: "Offline map",
                        value: mapPacks.isEmpty ? "None" : mapPacks.totalSizeDescription
                    )
                    Text("One map covers everywhere you go. It is managed on the Routes tab, under Offline map.")
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary.opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                }

                section("Diagnostics") {
                    row(
                        symbol: "list.bullet.rectangle",
                        title: "Event log",
                        detail: eventLogDetail,
                        tint: EventLog.shared.failureCount > 0 ? Theme.danger : Theme.accent
                    ) {
                        path.append(SettingsDestination.eventLog)
                    }
                }

                legalSection

                aboutCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, TabBarMetrics.scrollInset)
        }
        .scrollIndicators(.hidden)
        .background(Theme.canvas)
        .sensoryFeedback(.success, trigger: feedback)
        .sheet(isPresented: $showsHealthSheet) { HealthAccessSheet() }
        .sheet(isPresented: $showsCustomizeSheet) { CustomizeDashboardView() }
        .sheet(item: $readingDocument) { LegalDocumentView(document: $0) }
        .onAppear { draftName = profile.name }
        // Committed when the field loses focus as well as on return, so a name
        // typed and then scrolled away from is not quietly thrown away.
        .onChange(of: isEditingName) { _, editing in
            guard !editing else { return }
            commitName()
        }
    }

    private func commitName() {
        profile.setName(draftName)
        draftName = profile.name
    }

    private var eventLogDetail: String {
        let log = EventLog.shared
        guard !log.events.isEmpty else { return "Nothing recorded yet" }
        let failures = log.failureCount
        guard failures > 0 else {
            return "\(log.events.count) event\(log.events.count == 1 ? "" : "s") · no failures"
        }
        return "\(failures) failure\(failures == 1 ? "" : "s") of \(log.events.count) event\(log.events.count == 1 ? "" : "s")"
    }

    private var goalDetail: String {
        let metrics = goals.metricsWithGoals
        guard let first = metrics.first else { return "None set — tap to add one" }
        guard let target = goals.target(for: first) else { return "None set — tap to add one" }
        let extra = metrics.count - 1
        return extra > 0
            ? "\(first.goalSummary(target)) · +\(extra) more"
            : first.goalSummary(target)
    }

    /// The agreements, kept reachable after they were accepted. Somebody who
    /// ticked three boxes on their first morning should be able to find out
    /// later what they actually agreed to.
    private var legalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Legal")
                .metricLabelStyle()
                .padding(.leading, 4)
            VStack(spacing: 0) {
                ForEach(Array(LegalDocument.all.enumerated()), id: \.element.id) { index, document in
                    if index > 0 { divider }
                    row(
                        symbol: document.symbol,
                        title: document.title,
                        detail: document.summary
                    ) {
                        readingDocument = document
                    }
                }

                if let accepted = consent.acceptedDateText {
                    Text("Accepted \(accepted). Trekka is a fitness app, not a medical device — it gives an overview of your health and training, never a diagnosis.")
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary.opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
            }
            .panel()
        }
    }

    // MARK: - Cards

    /// Who the app is for, and what it is called. The name is editable in place
    /// rather than behind another screen — it is one field, and burying it would
    /// cost more taps than it saves.
    private var identityCard: some View {
        HStack(spacing: 14) {
            Group {
                if profile.hasName {
                    Text(initials)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.canvas)
                } else {
                    Image(systemName: "mountain.2.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.canvas)
                }
            }
            .frame(width: 52, height: 52)
            .background(Theme.accent, in: .rect(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 3) {
                TextField("Your name", text: $draftName)
                    .font(.system(.title3, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($isEditingName)
                    .onSubmit { commitName() }
                Text(health.hasHealthData ? "Training data from Apple Health" : "Not connected to Apple Health")
                    .font(.caption)
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
            }
            Spacer(minLength: 0)

            if isEditingName {
                Button("Done") {
                    isEditingName = false
                }
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.accent)
            }
        }
        .padding(16)
        .panel()
        .animation(.snappy(duration: 0.2), value: isEditingName)
    }

    private var initials: String {
        let parts = profile.name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init)
        return letters.isEmpty ? "T" : letters.joined().uppercased()
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Version")
                    .font(.system(.footnote, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                Spacer()
                Text(versionString)
                    .font(.system(.footnote, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary.opacity(0.8))
            }
            Text("Routes, activities and settings live on this device. Back them up to iCloud or a file so a new phone can pick up where this one left off.")
                .font(.caption)
                .foregroundStyle(Theme.textPrimary.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var watchDetail: String {
        let customized = WatchSportProfile.allCases.filter { watchLayout.isCustomized($0) }.count
        let layouts = customized == 0 ? "Default screens" : "\(customized) custom sport layout\(customized == 1 ? "" : "s")"
        let power = watchLayout.isPowerSaverEnabled ? "power saver on" : "\(syncedRouteCount) route\(syncedRouteCount == 1 ? "" : "s") synced"
        return "\(layouts) · \(power)"
    }

    private var healthDetail: String {
        switch health.authorization {
        case .authorized: "Sleep, HRV, VO₂ max and workouts"
        case .denied: "Access declined — open the Health app"
        case .unavailable: "Not available on this device"
        case .requesting: "Requesting access…"
        case .unknown: "Not connected yet"
        }
    }

    // MARK: - Building blocks

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .metricLabelStyle()
                .padding(.leading, 4)
            VStack(spacing: 0) {
                content()
            }
            .panel()
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: 1)
            .padding(.leading, 54)
    }

    private func row(
        symbol: String,
        title: String,
        detail: String,
        tint: Color = Theme.accent,
        showsChevron: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.12), in: .rect(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.3))
                }
            }
            .padding(12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func appearanceOption(_ mode: AppearanceMode) -> some View {
        let isSelected = appearance.mode == mode
        return Button {
            appearance.set(mode)
            feedback += 1
        } label: {
            VStack(spacing: 6) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 16, weight: .semibold))
                Text(mode.title)
                    .font(.system(.caption, weight: .semibold))
            }
            .foregroundStyle(isSelected ? Theme.canvas : Theme.textPrimary.opacity(0.55))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isSelected ? Theme.accent : Theme.surfaceRaised, in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mode.title) appearance")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// One independent unit choice — weight or elevation — as a labelled row of
    /// two small options, so it reads as its own toggle rather than a second
    /// unit system hiding behind the metric/imperial cards above it.
    private func unitOverrideRow(
        symbol: String,
        title: String,
        metricLabel: String,
        imperialLabel: String,
        selection: UnitSystem,
        onChange: @escaping (UnitSystem) -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30)
                .background(Theme.accent.opacity(0.12), in: .rect(cornerRadius: 9))

            Text(title)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Spacer(minLength: 8)

            overrideOption(metricLabel, isSelected: selection == .metric) { onChange(.metric) }
            overrideOption(imperialLabel, isSelected: selection == .imperial) { onChange(.imperial) }
        }
        .padding(12)
    }

    private func overrideOption(
        _ label: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(.subheadline, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(isSelected ? Theme.canvas : Theme.textPrimary.opacity(0.55))
                .frame(width: 46)
                .padding(.vertical, 8)
                .background(isSelected ? Theme.accent : Theme.surfaceRaised, in: .rect(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func unitOption(_ system: UnitSystem) -> some View {
        let isSelected = units.system == system
        return Button {
            units.set(system)
            // The watch reads its units from the layout document, so the choice
            // travels with the next push rather than needing its own channel.
            watchLayout.unitSystem = system
            watchLayout.pushSilently()
            feedback += 1
        } label: {
            VStack(spacing: 4) {
                Text(system.title)
                    .font(.system(.subheadline, weight: .bold))
                Text(system.subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? Theme.canvas : Theme.textPrimary.opacity(0.55))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isSelected ? Theme.accent : Theme.surfaceRaised, in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(system.title) units")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func infoRow(symbol: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
                .frame(width: 30, height: 30)
                .background(Theme.surfaceRaised, in: .rect(cornerRadius: 9))
            Text(title)
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 0)
            Text(value)
                .font(.system(.subheadline, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary.opacity(0.7))
        }
        .padding(12)
    }
}
