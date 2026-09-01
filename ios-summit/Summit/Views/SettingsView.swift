import SwiftUI

nonisolated enum SettingsDestination: Hashable, Sendable {
    case watch
    case backup
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
    @Binding var path: NavigationPath

    @State private var showsHealthSheet = false
    @State private var showsCustomizeSheet = false
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

                    // Say plainly that this is a display choice. Nothing already
                    // recorded changes, and the watch follows the phone, so
                    // neither device can end up quietly quoting the other's unit.
                    Text("Applies everywhere on the phone and on your watch. Recorded workouts are unchanged — only how they are shown.")
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
                    // Offline maps are managed on the Routes tab, beside the
                    // routes they cover. The figure is here because this is
                    // where anyone freeing up space will look first.
                    infoRow(
                        symbol: "internaldrive",
                        title: "Offline maps",
                        value: mapPacks.packs.isEmpty ? "None" : mapPacks.totalSizeDescription
                    )
                    Text("Downloaded ground is managed on the Routes tab, under Offline maps.")
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary.opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                }

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
    }

    // MARK: - Cards

    private var identityCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "mountain.2.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.canvas)
                .frame(width: 52, height: 52)
                .background(Theme.accent, in: .rect(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 3) {
                Text("Trekka Outdoors")
                    .font(.system(.title3, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(health.hasHealthData ? "Training data from Apple Health" : "Not connected to Apple Health")
                    .font(.caption)
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .panel()
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
