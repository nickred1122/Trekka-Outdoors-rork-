import SwiftUI

/// Battery charge, drawn as a real gauge rather than a stepped SF Symbol so the
/// level reads at a glance and the number stays exact.
struct BatteryReadout: View {
    let percent: Int
    var isPowerSaving: Bool = false

    private var fraction: Double {
        min(max(Double(percent) / 100, 0), 1)
    }

    /// Amber under a third, red under a sixth: the two moments an athlete needs
    /// to decide whether to switch modes or turn back.
    private var tint: Color {
        if percent <= 15 { return WatchTheme.danger }
        if percent <= 30 { return WatchTheme.highlight }
        return isPowerSaving ? WatchTheme.positive : WatchTheme.textSecondary
    }

    private var shellWidth: CGFloat { WatchDisplay.isCompact ? 12 : 13.5 }
    private var shellHeight: CGFloat { WatchDisplay.isCompact ? 6.5 : 7 }

    var body: some View {
        HStack(spacing: 2.5) {
            if isPowerSaving {
                Image(systemName: "leaf.fill")
                    .font(.watch(8, weight: .bold))
                    .foregroundStyle(WatchTheme.positive)
            }
            HStack(spacing: 0.8) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(tint.opacity(0.55), lineWidth: 1)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(tint)
                        .frame(width: max(1, (shellWidth - 3) * fraction))
                        .padding(1.5)
                }
                .frame(width: shellWidth, height: shellHeight)
                Capsule()
                    .fill(tint.opacity(0.55))
                    .frame(width: 1.5, height: shellHeight * 0.42)
            }
            Text("\(percent)")
                .font(.metric(10, weight: .bold))
                .foregroundStyle(tint)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery \(percent) percent\(isPowerSaving ? ", power saver on" : "")")
    }
}

/// Signal strength for the sports that depend on it. Indoor sports get nothing
/// here rather than a permanently dead antenna.
struct GPSStrengthBadge: View {
    let bars: Int
    let isLive: Bool
    var isSearching: Bool { !isLive || bars <= 0 }

    @State private var isPulsing = false

    private var tint: Color {
        if isSearching { return WatchTheme.textSecondary }
        return bars >= 3 ? WatchTheme.positive : WatchTheme.highlight
    }

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(1...3, id: \.self) { index in
                Capsule()
                    .fill(index <= bars ? tint : WatchTheme.surfaceRaised)
                    .frame(width: 2.5, height: CGFloat(3 + index * 2))
            }
        }
        .opacity(isSearching && isPulsing ? 0.35 : 1)
        .animation(
            isSearching
                ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true)
                : .default,
            value: isPulsing
        )
        .onAppear { isPulsing = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isSearching ? "Searching for GPS" : "GPS signal \(bars) of 3")
    }
}

/// The one row that survives every layout choice: the running clock, and
/// optionally signal and charge.
///
/// Everything sits hard left. This row shares a line with the watch's own clock,
/// which owns the top-right corner and cannot be moved, so the strip keeps to
/// its own half rather than sliding underneath it.
///
/// Signal and charge can also be placed on a data screen as ordinary fields, so
/// the badges here are a choice rather than a fixture — an athlete who has given
/// them a field slot does not want them overlaying the map as well.
struct WorkoutStatusStrip: View {
    let elapsed: TimeInterval
    let isPaused: Bool
    let isAutoPaused: Bool
    let tint: Color
    let usesGPS: Bool
    let gpsBars: Int
    let isGPSLive: Bool
    let batteryPercent: Int
    let isPowerSaving: Bool
    /// Whether signal and charge ride above the page.
    var showsBadges: Bool = true

    private var stateTint: Color {
        isPaused || isAutoPaused ? WatchTheme.highlight : tint
    }

    private var timerText: String {
        if isPaused { return "PAUSED" }
        if isAutoPaused { return "AUTO" }
        return WatchFormat.duration(elapsed)
    }

    var body: some View {
        HStack(spacing: WatchDisplay.isCompact ? 3 : 5) {
            Circle()
                .fill(stateTint)
                .frame(width: 5, height: 5)
            Text(timerText)
                .font(.metric(11, weight: .bold))
                .foregroundStyle(isPaused || isAutoPaused ? WatchTheme.highlight : WatchTheme.textSecondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            if showsBadges {
                if usesGPS {
                    GPSStrengthBadge(bars: gpsBars, isLive: isGPSLive)
                }
                BatteryReadout(percent: batteryPercent, isPowerSaving: isPowerSaving)
            } else if isPowerSaving {
                // Power saver changes what the sensors are doing, so it stays
                // visible even when the badges are off.
                Image(systemName: "leaf.fill")
                    .font(.watch(8, weight: .bold))
                    .foregroundStyle(WatchTheme.positive)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, WatchDisplay.isCompact ? 7 : 10)
        // The watch's clock lives in the far corner. Reserving its room here
        // keeps a long battery reading from ever running under it.
        .padding(.trailing, WatchDisplay.isCompact ? 44 : 52)
        .padding(.bottom, 3)
        .background {
            // The map runs edge to edge underneath, so the strip carries its own
            // fade rather than relying on whatever happens to be behind it.
            LinearGradient(
                colors: [WatchTheme.canvas.opacity(0.95), WatchTheme.canvas.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
    }
}
