import SwiftUI

/// Lets the user choose which tiles appear on Today, in what order, and how dense they are.
struct CustomizeDashboardView: View {
    @Environment(DashboardSettings.self) private var settings
    @Environment(AppearanceSettings.self) private var appearance
    @Environment(\.dismiss) private var dismiss

    @State private var showsResetConfirmation = false

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            List {
                Section {
                    Toggle("Charts on tiles", isOn: $settings.showsTileCharts)
                        .tint(Theme.accent)
                        .listRowBackground(Theme.surface)

                } header: {
                    Text("Charts")
                } footer: {
                    Text("Each tile carries a small trend line of the range you are viewing.")
                }

                Section("Sections") {
                    Toggle("Readiness ring", isOn: $settings.showsReadinessRing)
                    Toggle("Heart rate zones", isOn: $settings.showsZoneChart)
                    Toggle("Latest activity", isOn: $settings.showsRecentActivity)
                }
                .listRowBackground(Theme.surface)
                .tint(Theme.accent)

                Section {
                    ForEach(settings.visibleMetrics) { metric in
                        row(metric, isVisible: true)
                    }
                    .onMove { offsets, destination in
                        settings.moveVisible(fromOffsets: offsets, toOffset: destination)
                    }
                } header: {
                    Text("On the dashboard")
                } footer: {
                    Text("Drag to reorder. Tiles appear in this order, two per row.")
                }

                if !settings.hiddenMetrics.isEmpty {
                    Section("More tiles") {
                        ForEach(settings.hiddenMetrics) { metric in
                            row(metric, isVisible: false)
                        }
                    }
                }

                Section {
                    Button("Reset to defaults", role: .destructive) {
                        showsResetConfirmation = true
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Customize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .confirmationDialog(
                "Reset the dashboard?",
                isPresented: $showsResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset", role: .destructive) { settings.resetToDefaults() }
                Button("Cancel", role: .cancel) {}
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(appearance.colorScheme)
    }

    private func row(_ metric: DashboardMetric, isVisible: Bool) -> some View {
        HStack(spacing: 12) {
            Button {
                settings.toggle(metric)
            } label: {
                Image(systemName: isVisible ? "minus.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(isVisible ? Theme.danger : Theme.zoneColors[1])
            }
            .buttonStyle(.plain)

            TrekkaIcon(metric.glyph, size: 15, tint: metric.tint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(metric.title)
                    .font(.system(.body, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(metric.periodLabel)
                    .font(.caption2)
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
            }
            Spacer(minLength: 0)
        }
        .listRowBackground(Theme.surface)
    }
}

