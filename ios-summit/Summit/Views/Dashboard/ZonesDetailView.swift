import SwiftUI

/// Per-zone breakdown of the last seven days: time, share, bpm range and purpose.
struct ZonesDetailView: View {
    @Environment(RouteStore.self) private var store
    @Environment(HealthService.self) private var health

    private var minutes: [Double] {
        let fromStore = store.weeklyZoneMinutes
        if fromStore.contains(where: { $0 > 0 }) { return fromStore }
        return health.snapshot.zoneMinutes
    }

    private var total: Double { minutes.reduce(0, +) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                summaryCard

                VStack(spacing: 12) {
                    ForEach(0..<5, id: \.self) { index in
                        zoneCard(index)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("Polarised or pyramidal?", systemImage: "chart.pie.fill")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(distributionVerdict)
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
        .navigationTitle("Heart Rate Zones")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.canvas, for: .navigationBar)
    }

    private var summaryCard: some View {
        VStack(spacing: 12) {
            Text(Formatters.compactDuration(total * 60))
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            Text("TOTAL TIME IN ZONE · LAST 7 DAYS")
                .font(.system(.caption2, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(Theme.textPrimary.opacity(0.5))

            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { index in
                        let value = minutes.indices.contains(index) ? minutes[index] : 0
                        let width = total > 0 ? geometry.size.width * (value / total) : 0
                        Rectangle()
                            .fill(Theme.zoneColor(index + 1))
                            .frame(width: max(value > 0 ? 4 : 0, width - 2))
                    }
                }
                .clipShape(.capsule)
            }
            .frame(height: 10)
            .padding(.top, 2)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .panel()
    }

    private func zoneCard(_ index: Int) -> some View {
        let value = minutes.indices.contains(index) ? minutes[index] : 0
        let share = total > 0 ? value / total * 100 : 0
        let color = Theme.zoneColor(index + 1)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Z\(index + 1)")
                    .font(.metric(15))
                    .foregroundStyle(Theme.canvas)
                    .frame(width: 32, height: 26)
                    .background(color, in: .rect(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 1) {
                    Text(zoneNames[index])
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(bpmRanges[index])
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(value >= 60 ? String(format: "%.1fh", value / 60) : "\(Int(value.rounded()))m")
                        .font(.metric(17))
                        .foregroundStyle(Theme.textPrimary)
                    Text(String(format: "%.0f%%", share))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                }
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surfaceRaised)
                    Capsule()
                        .fill(color)
                        .frame(width: max(4, geometry.size.width * (total > 0 ? value / total : 0)))
                }
            }
            .frame(height: 6)

            Text(zonePurposes[index])
                .font(.caption2)
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private var distributionVerdict: String {
        guard total > 0 else { return "No zone data recorded in the last seven days." }
        let easy = (minutes.prefix(2).reduce(0, +)) / total
        let hard = (minutes.suffix(2).reduce(0, +)) / total
        if easy > 0.75 && hard > 0.08 {
            return "Classic polarised week — plenty of easy volume with a clear hard edge. This is the distribution most endurance research points to."
        }
        if easy > 0.85 {
            return "Very easy week overall. Good for base building, but add a threshold or hill session if you want the top end to move."
        }
        if hard > 0.25 {
            return "A lot of time above threshold. Productive short term, but fatigue accumulates fast — protect the easy days."
        }
        return "Pyramidal distribution: most time easy, tapering through moderate to hard. Solid for race-specific blocks."
    }

    private let zoneNames = ["Recovery", "Aerobic base", "Tempo", "Threshold", "VO₂ max"]
    private let bpmRanges = ["Below 113 bpm", "113–132 bpm", "132–150 bpm", "150–169 bpm", "169 bpm and up"]
    private let zonePurposes = [
        "Active recovery and warm-ups. Builds blood flow without adding fatigue.",
        "The engine room. Fat oxidation, capillary density and the aerobic base most trail performance rests on.",
        "Comfortably hard. Bridges base and threshold work; useful for sustained climbing.",
        "At or near lactate threshold — the pace you can hold for about an hour. Raises your sustainable ceiling.",
        "Maximal aerobic power. Short intervals only; costly to recover from.",
    ]
}
