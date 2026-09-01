import SwiftUI

struct ActivityDetailView: View {
    let activity: ActivityRecord

    @State private var recenterToken = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if activity.track.count > 1 {
                    TrekkaMapSurface(
                        routePoints: activity.track,
                        isInteractive: false,
                        showsUserLocation: false,
                        recenterToken: recenterToken
                    )
                    .frame(height: 220)
                    .clipShape(.rect(cornerRadius: Theme.cardRadius))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.cardRadius)
                            .strokeBorder(Theme.border, lineWidth: 1)
                    }
                }

                StatStrip(items: [
                    StatItem(symbol: "arrow.left.and.right", label: "Distance", value: Formatters.distance(activity.distance), unit: Formatters.units.distanceUnit),
                    StatItem(symbol: "clock", label: "Time", value: Formatters.duration(activity.duration), unit: ""),
                    StatItem(symbol: "speedometer", label: "Avg pace", value: Formatters.pace(activity.averagePace), unit: Formatters.units.paceUnit),
                ])

                StatStrip(items: [
                    StatItem(symbol: "arrow.up.forward", label: "Climb", value: Formatters.elevation(activity.elevationGain), unit: Formatters.units.elevationUnit),
                    StatItem(symbol: "heart.fill", label: "Avg HR", value: Formatters.integer(activity.averageHeartRate), unit: "bpm"),
                    StatItem(symbol: "flame.fill", label: "Calories", value: Formatters.integer(activity.calories), unit: "kcal"),
                ])

                if activity.track.count > 1 {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Elevation")
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        ElevationChart(samples: ElevationProfile.samples(for: activity.track), height: 140)
                    }
                    .padding(16)
                    .panel()
                }

                ZoneBars(minutes: activity.zoneMinutes, title: "Time in zones", subtitle: "This session")

                trainingEffectCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background(Theme.canvas)
        .navigationTitle(activity.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    private var trainingEffectCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Training effect")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(String(format: "%.1f", activity.trainingEffect))
                    .font(.metric(20))
                    .foregroundStyle(Theme.accent)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surfaceRaised)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Theme.zoneColors[1], Theme.highlight, Theme.accent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * min(1, activity.trainingEffect / 5))
                }
            }
            .frame(height: 8)
            Text(effectLabel)
                .font(.caption)
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
        }
        .padding(16)
        .panel()
    }

    private var effectLabel: String {
        switch activity.trainingEffect {
        case ..<1.5: "Recovery — maintains your base"
        case 1.5..<2.5: "Maintaining — holds current fitness"
        case 2.5..<3.5: "Improving — builds aerobic capacity"
        case 3.5..<4.5: "Highly improving — strong stimulus"
        default: "Overreaching — plan recovery next"
        }
    }
}
