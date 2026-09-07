import SwiftUI

/// The day's energy, drawn as a ring: how much has been eaten against the target.
///
/// Going over does not simply fill the ring and stop — it draws a second lap in
/// red, because "you are past your target" is a different fact from "you are
/// exactly at it" and the ring should not flatten the two into one full circle.
struct EnergyRing: View {
    let consumed: Double
    let target: Double
    var diameter: CGFloat = 168
    var lineWidth: CGFloat = 15

    private var fraction: Double {
        guard target > 0 else { return 0 }
        return min(1, consumed / target)
    }

    /// How far round the second lap, when the target has been passed.
    private var overFraction: Double {
        guard target > 0, consumed > target else { return 0 }
        return min(1, (consumed - target) / target)
    }

    private var remaining: Double { target - consumed }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.textPrimary.opacity(0.08), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    AngularGradient(
                        colors: [Theme.accent.opacity(0.65), Theme.accent, Theme.highlight],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            if overFraction > 0 {
                Circle()
                    .trim(from: 0, to: overFraction)
                    .stroke(Theme.danger, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }

            centre
        }
        .frame(width: diameter, height: diameter)
        .animation(.snappy(duration: 0.45), value: fraction)
        .animation(.snappy(duration: 0.45), value: overFraction)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var centre: some View {
        VStack(spacing: 1) {
            if target > 0 {
                Text("\(Int(abs(remaining).rounded()))")
                    .font(.metric(34))
                    .foregroundStyle(remaining < 0 ? Theme.danger : Theme.textPrimary)
                    .contentTransition(.numericText())

                Text(remaining < 0 ? "over" : "left")
                    .font(.system(.caption2, weight: .semibold))
                    .textCase(.uppercase)
                    .kerning(0.6)
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
            } else {
                Text("\(Int(consumed.rounded()))")
                    .font(.metric(34))
                    .foregroundStyle(Theme.textPrimary)
                Text("kcal")
                    .font(.system(.caption2, weight: .semibold))
                    .textCase(.uppercase)
                    .kerning(0.6)
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
            }
        }
    }

    private var accessibilityText: String {
        guard target > 0 else { return "\(Int(consumed.rounded())) kilocalories eaten" }
        if remaining < 0 {
            return "\(Int(abs(remaining).rounded())) kilocalories over your target of \(Int(target.rounded()))"
        }
        return "\(Int(remaining.rounded())) kilocalories left of \(Int(target.rounded()))"
    }
}
