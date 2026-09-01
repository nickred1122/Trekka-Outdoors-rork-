import SwiftUI

/// Heart-rate zone distribution bars with the shared blue-to-red ramp.
struct ZoneBars: View {
    let minutes: [Double]
    var title: String = "Heart Rate Zones"
    var subtitle: String = "Last 7 days"

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var maximum: Double {
        max(1, minutes.max() ?? 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
            }

            VStack(spacing: 9) {
                ForEach(0..<5, id: \.self) { index in
                    let value = minutes.indices.contains(index) ? minutes[index] : 0
                    HStack(spacing: 10) {
                        Text("Z\(index + 1)")
                            .font(.system(.caption, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary.opacity(0.65))
                            .frame(width: 22, alignment: .leading)

                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Theme.surfaceRaised)
                                Capsule()
                                    .fill(Theme.zoneColor(index + 1))
                                    .frame(width: appeared ? max(6, geometry.size.width * (value / maximum)) : 0)
                            }
                        }
                        .frame(height: 8)

                        Text(label(for: value))
                            .font(.system(.caption, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary.opacity(0.75))
                            .frame(width: 46, alignment: .trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Zone \(index + 1)")
                    .accessibilityValue(label(for: value))
                }
            }
        }
        .padding(16)
        .panel()
        .onAppear {
            guard !reduceMotion else {
                appeared = true
                return
            }
            withAnimation(.easeOut(duration: 0.7).delay(0.1)) { appeared = true }
        }
    }

    private func label(for minutes: Double) -> String {
        if minutes >= 60 {
            return String(format: "%.1fh", minutes / 60)
        }
        return "\(Int(minutes.rounded()))m"
    }
}
