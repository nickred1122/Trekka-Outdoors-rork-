import SwiftUI

/// Morning readiness glance, mirroring the phone's Today dashboard.
struct GlanceView: View {
    @Environment(WatchGlanceService.self) private var glance

    var body: some View {
        ScrollView {
            VStack(spacing: WatchDisplay.spacing(10)) {
                WatchRing(
                    progress: Double(glance.readiness) / 100,
                    tint: readinessTint,
                    lineWidth: WatchDisplay.scaled(9, atLeast: 7),
                    label: "\(glance.readiness)",
                    caption: "READY"
                )
                .frame(width: ringDiameter, height: ringDiameter)
                .padding(.top, 2)

                Text(glance.caption)
                    .font(.watch(11, weight: .medium))
                    .foregroundStyle(WatchTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: WatchDisplay.spacing(6)) {
                    WatchStatRow(title: "Sleep", value: glance.sleepText)
                    WatchStatRow(title: "HRV", value: "\(WatchFormat.integer(glance.hrv)) ms", tint: hrvTint)
                    WatchStatRow(title: "Resting HR", value: "\(WatchFormat.integer(glance.restingHeartRate)) bpm")
                    WatchStatRow(title: "Load", value: "\(glance.trainingLoad)")
                }
                .padding(WatchDisplay.spacing(9))
                .watchPanel()

                VStack(alignment: .leading, spacing: WatchDisplay.spacing(4)) {
                    Text("Today's move")
                        .fieldLabelStyle()
                    Text(glance.suggestion)
                        .font(.watch(11, weight: .medium))
                        .foregroundStyle(WatchTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(WatchDisplay.spacing(9))
                .watchPanel(fill: WatchTheme.accent.opacity(0.12))

                if !glance.hasHealthData {
                    Text("No Health data yet — grant access on iPhone to see your numbers.")
                        .font(.watch(9))
                        .foregroundStyle(WatchTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Today")
        .task { await glance.refresh() }
    }

    private var ringDiameter: CGFloat { WatchDisplay.scaled(96, atLeast: 72) }

    private var readinessTint: Color {
        switch glance.readiness {
        case 70...: WatchTheme.positive
        case 45..<70: WatchTheme.highlight
        default: WatchTheme.danger
        }
    }

    private var hrvTint: Color {
        glance.hrv >= glance.hrvBaseline ? WatchTheme.positive : WatchTheme.highlight
    }
}
