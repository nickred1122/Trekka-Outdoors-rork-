import SwiftUI

/// Explains exactly how today's readiness score was assembled.
struct ReadinessDetailView: View {
    @Environment(HealthService.self) private var health

    private var snapshot: HealthSnapshot { health.snapshot }
    private var factors: [ReadinessFactor] { ReadinessCalculator.factors(for: snapshot) }

    private var ringColor: Color {
        switch snapshot.readiness {
        case 80...100: Theme.zoneColors[1]
        case 60..<80: Theme.highlight
        case 35..<60: Theme.accent
        default: Theme.danger
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ReadinessRing(score: snapshot.readiness, caption: snapshot.readinessCaption)

                guidanceCard

                VStack(alignment: .leading, spacing: 14) {
                    Text("Score breakdown")
                        .metricLabelStyle()
                    ForEach(factors) { factor in
                        factorRow(factor)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .panel()

                sessionCard

                VStack(alignment: .leading, spacing: 8) {
                    Label("How it is calculated", systemImage: "function")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Readiness weights sleep duration up to 40 points, overnight HRV against your own 30-day baseline up to 35, sleep quality up to 15, then subtracts up to 20 when your seven-day load climbs past the comfort ceiling. It is a relative measure — the trend across a week tells you far more than any single morning.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textPrimary.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .panel()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(Theme.canvas)
        .scrollIndicators(.hidden)
        .navigationTitle("Readiness")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.canvas, for: .navigationBar)
        .refreshable { await health.refresh() }
    }

    private var guidanceCard: some View {
        HStack(spacing: 12) {
            Image(systemName: guidanceSymbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.canvas)
                .frame(width: 38, height: 38)
                .background(ringColor, in: .circle)
            VStack(alignment: .leading, spacing: 3) {
                Text(guidanceTitle)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(guidanceDetail)
                    .font(.caption)
                    .foregroundStyle(Theme.textPrimary.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .panel()
    }

    private func factorRow(_ factor: ReadinessFactor) -> some View {
        let tint = factor.isPenalty ? Theme.danger : Theme.accent
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: factor.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 18)
                Text(factor.title)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                Text(factor.isPenalty
                     ? (factor.points > 0 ? "−\(Int(factor.points.rounded()))" : "0")
                     : "+\(Int(factor.points.rounded()))")
                    .font(.metric(15))
                    .foregroundStyle(factor.isPenalty && factor.points > 0 ? Theme.danger : Theme.textPrimary)
                Text("/ \(Int(factor.maxPoints))")
                    .font(.system(.caption2, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.4))
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surfaceRaised)
                    Capsule()
                        .fill(tint)
                        .frame(width: max(4, geometry.size.width * factor.fraction))
                }
            }
            .frame(height: 6)

            Text(factor.detail)
                .font(.caption2)
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
        }
    }

    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Suggested session")
                .metricLabelStyle()
            ForEach(sessionSuggestions, id: \.self) { suggestion in
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "chevron.forward.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(ringColor)
                        .padding(.top, 1)
                    Text(suggestion)
                        .font(.footnote)
                        .foregroundStyle(Theme.textPrimary.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private var guidanceSymbol: String {
        switch snapshot.readiness {
        case 80...100: "bolt.fill"
        case 60..<80: "figure.run"
        case 35..<60: "tortoise.fill"
        default: "bed.double.fill"
        }
    }

    private var guidanceTitle: String {
        switch snapshot.readiness {
        case 80...100: "Green light"
        case 60..<80: "Train as planned"
        case 35..<60: "Hold the intensity back"
        default: "Recovery day"
        }
    }

    private var guidanceDetail: String {
        switch snapshot.readiness {
        case 80...100: "Everything points the right way. This is the day for the session you have been saving."
        case 60..<80: "Normal recovery. Your planned quality work should land well."
        case 35..<60: "Recovery is lagging. Keep the effort conversational and skip the top end."
        default: "Your body is asking for rest. Walk, stretch, sleep — training on this rarely pays."
        }
    }

    private var sessionSuggestions: [String] {
        switch snapshot.readiness {
        case 80...100:
            ["Hill repeats or a threshold block with full recoveries",
             "Push the vertical — your legs can take the eccentric load today",
             "Fuel early; the session will be long enough to need it"]
        case 60..<80:
            ["Steady aerobic run with a few strides at the end",
             "Keep zone 4 and 5 to under 20 minutes total",
             "Aim for the same bedtime as last night to hold the trend"]
        case 35..<60:
            ["Zone 2 only — cap the effort where you can still talk",
             "Trade vertical for flat mileage if the legs feel heavy",
             "Bank an extra hour of sleep tonight"]
        default:
            ["Walk, mobility or complete rest",
             "Watch resting heart rate tomorrow — a further rise means back off again",
             "Hydrate and eat carbohydrate earlier in the day"]
        }
    }
}
