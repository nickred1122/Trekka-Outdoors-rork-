import SwiftUI

/// The hero training-readiness gauge: a three-quarter arc that fills on appear.
struct ReadinessRing: View {
    let score: Int
    let caption: String

    @State private var animatedFraction: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private let arcSpan: Double = 0.78
    private let diameter: CGFloat = 210
    private let lineWidth: CGFloat = 16

    private var fraction: Double { Double(score) / 100 }

    private var hasScore: Bool { score > 0 }

    private var ringColor: Color {
        switch score {
        case 80...100: Theme.zoneColors[1]
        case 60..<80: Theme.highlight
        case 35..<60: Theme.accent
        default: Theme.danger
        }
    }

    /// Empty space between the lowest point the stroke reaches and the bottom of
    /// the ring's square frame.
    ///
    /// The arc is open at the bottom, so its frame is taller than the drawing.
    /// Measuring that band means the layout can close the gap without guessing —
    /// and without ever overlapping the stroke.
    private var deadBandHeight: CGFloat {
        let radius = (diameter - lineWidth) / 2
        // Half the untrimmed portion of the circle, as an angle from the bottom.
        let halfGap = (1 - arcSpan) * .pi
        let lowestDrawnPoint = diameter / 2 + radius * cos(halfGap) + lineWidth / 2
        // Leave a couple of points so the descenders never touch the stroke.
        return max(0, diameter - lowestDrawnPoint - 2)
    }

    /// The widest a line of text can be and still clear the arc.
    ///
    /// The arc is a circle, so the usable width shrinks the further text sits
    /// from the centre. Sizing to the inscribed square of the inner circle keeps
    /// every line clear of the stroke at any Dynamic Type size, which is what
    /// stopped the caption colliding with the ring.
    private var textWidth: CGFloat {
        let innerRadius = diameter / 2 - lineWidth
        return innerRadius * 2 / sqrt(2)
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .trim(from: 0, to: arcSpan)
                    .stroke(Theme.surfaceRaised, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(129.6))

                Circle()
                    .trim(from: 0, to: arcSpan * animatedFraction)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(129.6))
                    .shadow(color: ringColor.opacity(0.45), radius: 12)

                // Inside the ring: the number and its name, nothing else. The
                // caption is a sentence and sentences do not fit in circles.
                VStack(spacing: 0) {
                    Text(hasScore ? "\(score)" : "--")
                        .font(.system(size: 62, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("Readiness")
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.65))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(width: textWidth)
                .offset(y: 4)
            }
            .frame(width: diameter, height: diameter)
            // The arc stops short of the bottom of its own frame, leaving a band
            // of empty space. Only that dead band is reclaimed — the caption
            // itself is never pulled up into the stroke, which is what made the
            // words collide with the ring.
            .padding(.bottom, -deadBandHeight)

            // The caption sits under the gauge, where it has the full width of
            // the card and can wrap without running into the stroke.
            Text(caption)
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(hasScore ? ringColor : Theme.textPrimary.opacity(0.5))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
        .onAppear { animate() }
        .onChange(of: score) { _, _ in animate() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Training readiness")
        .accessibilityValue(hasScore ? "\(score) out of 100. \(caption)" : "No score yet. \(caption)")
    }

    private func animate() {
        guard !reduceMotion else {
            animatedFraction = fraction
            return
        }
        animatedFraction = 0
        withAnimation(.spring(response: 1.1, dampingFraction: 0.85)) {
            animatedFraction = fraction
        }
    }
}
