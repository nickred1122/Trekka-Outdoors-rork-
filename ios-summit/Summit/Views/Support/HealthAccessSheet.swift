import SwiftUI

/// Explains what Trekka reads from Apple Health and lets the user grant access.
struct HealthAccessSheet: View {
    @Environment(HealthService.self) private var health
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Trekka Outdoors reads your training data from Apple Health to build readiness, load and zone insights. Nothing leaves your device.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary.opacity(0.75))

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(dataPoints, id: \.self) { item in
                            Label(item, systemImage: "checkmark.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textPrimary.opacity(0.85))
                                .labelStyle(.titleAndIcon)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panel()

                    statusRow

                    Button {
                        Task {
                            await health.requestAuthorization()
                            if health.authorization == .authorized { dismiss() }
                        }
                    } label: {
                        Text(health.authorization == .authorized ? "Refresh Health data" : "Connect Apple Health")
                            .font(.system(.headline, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(health.authorization == .requesting || !health.isHealthDataAvailable)
                }
                .padding(20)
            }
            .background(Theme.canvas)
            .navigationTitle("Health Access")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .tint(Theme.accent)
                }
            }
        }
        .tint(Theme.accent)
    }

    private var dataPoints: [String] {
        ["Workouts and routes", "Heart rate and HRV", "Sleep stages", "Active energy and steps", "VO₂ max and resting heart rate"]
    }

    @ViewBuilder
    private var statusRow: some View {
        switch health.authorization {
        case .authorized:
            Label("Connected", systemImage: "checkmark.seal.fill")
                .foregroundStyle(Theme.zoneColors[1])
                .font(.subheadline.weight(.semibold))
        case .denied:
            Label("Access declined — enable Trekka Outdoors in the Health app under Sharing.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.highlight)
                .font(.footnote)
        case .unavailable:
            Label("Health data isn't available on this device.", systemImage: "info.circle")
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
                .font(.footnote)
        case .requesting:
            ProgressView().tint(Theme.accent)
        case .unknown:
            EmptyView()
        }
    }
}
