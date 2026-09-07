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
    /// Today against this metric's daily target, when the athlete set one.
    var goal: GoalProgress?
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
                if goal?.isMet == true {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.positive)
                        .transition(.scale.combined(with: .opacity))
                }
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

            if let goal {
                GoalBar(progress: goal, tint: symbolColor)
            }

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
        .animation(.snappy(duration: 0.3), value: goal?.fraction)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Opens the \(label) breakdown")
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityValue: String {
        let headline = "\(value) \(unit ?? "")\(suffix ?? "")"
        guard let goal else { return headline }
        return "\(headline). \(goal.progressText) of today's goal, \(goal.remainingText)"
    }
}

/// Today against a daily target: a filled track, the two numbers, and what is
/// left of it.
///
/// The track is drawn even at zero so a goal that has not been started yet
/// still reads as a goal rather than as missing data.
struct GoalBar: View {
    let progress: GoalProgress
    var tint: Color
    var showsCaption: Bool = true

    private var fillColor: Color { progress.isMet ? Theme.positive : tint }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.textPrimary.opacity(0.1))
                    Capsule()
                        .fill(fillColor)
                        .frame(width: max(progress.fraction > 0 ? 4 : 0, geometry.size.width * progress.fraction))
                }
            }
            .frame(height: 5)

            if showsCaption {
                HStack(spacing: 4) {
                    Text(progress.progressText)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 0)
                    if progress.streak > 1 {
                        Label("\(progress.streak)", systemImage: "flame.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.highlight)
                            .labelStyle(.titleAndIcon)
                    }
                }
            }
        }
        .accessibilityHidden(true)
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
