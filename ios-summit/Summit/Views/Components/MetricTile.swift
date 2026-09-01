import SwiftUI

/// One cell of the dashboard bento grid: icon, label, monospaced value and trend.
struct MetricTile: View {
    let glyph: TrekkaGlyph
    let symbolColor: Color
    let label: String
    let value: String
    var unit: String?
    var suffix: String?
    var samples: [MetricSample]
    var trendColor: Color
    var deltaUp: Bool?
    var caption: String?
    var showsSparkline: Bool = true
    var showsDisclosure: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: showsSparkline ? 8 : 6) {
            HStack(spacing: 6) {
                TrekkaIcon(glyph, size: 14, tint: symbolColor)
                Text(label)
                    .font(.system(.footnote, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if let deltaUp {
                    Image(systemName: deltaUp ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(deltaUp ? Theme.zoneColors[1] : Theme.textPrimary.opacity(0.45))
                }
                if showsDisclosure {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.25))
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.metric(showsSparkline ? 28 : 22))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                if let unit {
                    Text(unit)
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                }
                if let suffix {
                    Text(suffix)
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)

            if showsSparkline {
                MiniMetricChart(samples: samples, color: trendColor)
                    .frame(height: 26)
                if let caption {
                    Text(caption)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.42))
                        .lineLimit(1)
                }
            }
        }
        .padding(showsSparkline ? 14 : 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(value) \(unit ?? "")\(suffix ?? "")")
        .accessibilityHint("Opens the \(label) breakdown")
        .accessibilityAddTraits(.isButton)
    }
}

/// Press feedback for dashboard cards: a subtle sink instead of a highlight flash.
struct TilePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
