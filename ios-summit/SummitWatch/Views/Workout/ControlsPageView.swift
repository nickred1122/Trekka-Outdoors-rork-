import SwiftUI

/// The controls: lap, pause, end, power and quick access to screen setup.
///
/// Reached by swiping right or long-pressing any workout page, so it is never
/// more than one gesture away wherever the athlete happens to be looking.
struct ControlsPageView: View {
    let engine: WorkoutEngine
    let sport: WatchSport
    var onCustomize: () -> Void
    var onEnd: () -> Void
    /// Closes the controls without touching the workout.
    var onDismiss: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(spacing: WatchDisplay.spacing(10)) {
                if let onDismiss {
                    Button(action: onDismiss) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.watch(9, weight: .bold))
                            Text("Back to metrics")
                                .font(.watch(10, weight: .semibold))
                        }
                        .foregroundStyle(WatchTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 6)
                }

                HStack(spacing: WatchDisplay.spacing(12)) {
                    controlButton(
                        systemImage: "flag.checkered",
                        title: "Lap",
                        tint: WatchTheme.highlight
                    ) {
                        engine.markLap()
                    }

                    controlButton(
                        systemImage: engine.phase == .paused ? "play.fill" : "pause.fill",
                        title: engine.phase == .paused ? "Resume" : "Pause",
                        tint: engine.phase == .paused ? WatchTheme.positive : WatchTheme.accent
                    ) {
                        engine.togglePause()
                    }
                }

                HStack(spacing: WatchDisplay.spacing(12)) {
                    controlButton(
                        systemImage: "xmark",
                        title: "End",
                        tint: WatchTheme.danger,
                        action: onEnd
                    )

                    controlButton(
                        systemImage: engine.isPowerSaving ? "leaf.fill" : "battery.50",
                        title: engine.isPowerSaving ? "Saver on" : "Power",
                        tint: engine.isPowerSaving ? WatchTheme.positive : WatchTheme.surfaceRaised,
                        foreground: engine.isPowerSaving ? WatchTheme.canvas : WatchTheme.textPrimary
                    ) {
                        engine.togglePowerSaving()
                    }
                }

                HStack(spacing: WatchDisplay.spacing(12)) {
                    controlButton(
                        systemImage: "slider.horizontal.3",
                        title: "Screens",
                        tint: WatchTheme.surfaceRaised,
                        foreground: WatchTheme.textPrimary,
                        action: onCustomize
                    )

                    if sport.isWaterSport {
                        controlButton(
                            systemImage: "drop.fill",
                            title: "Lock",
                            tint: WatchTheme.surfaceRaised,
                            foreground: WatchTheme.textPrimary
                        ) {
                            engine.lockForWater()
                        }
                    } else {
                        Color.clear.frame(width: buttonDiameter, height: buttonDiameter)
                    }
                }

                batteryStrip

                if engine.isAutoPaused {
                    Label("Auto-paused", systemImage: "pause.circle.fill")
                        .font(.watch(10, weight: .semibold))
                        .foregroundStyle(WatchTheme.highlight)
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// Tap targets never drop below 44 pt, so the smallest watch scales the
    /// gaps and labels instead of the buttons themselves.
    private var buttonDiameter: CGFloat { WatchDisplay.scaled(52, atLeast: 44) }

    /// Honest read on how long the watch can keep recording.
    private var batteryStrip: some View {
        VStack(spacing: 3) {
            HStack(spacing: WatchDisplay.spacing(5)) {
                Image(systemName: engine.isPowerSaving ? "leaf.fill" : "battery.100")
                    .font(.watch(9, weight: .bold))
                    .foregroundStyle(engine.isPowerSaving ? WatchTheme.positive : WatchTheme.textSecondary)
                Text("\(engine.batteryPercent)%")
                    .font(.metric(11, weight: .bold))
                    .foregroundStyle(WatchTheme.textPrimary)
                Text(engine.batteryLabel)
                    .font(.metric(11, weight: .semibold))
                    .foregroundStyle(engine.isPowerSaving ? WatchTheme.positive : WatchTheme.accent)
                Text("left")
                    .font(.watch(9))
                    .foregroundStyle(WatchTheme.textSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            if !engine.isPowerSaving, engine.batteryGainLabel != "--" {
                Text("Power saver adds \(engine.batteryGainLabel)")
                    .font(.watch(9))
                    .foregroundStyle(WatchTheme.textSecondary)
            } else if engine.didAutoArmPowerSaver {
                Text("Armed automatically at \(engine.batteryPercent)%")
                    .font(.watch(9))
                    .foregroundStyle(WatchTheme.positive)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(WatchTheme.surface, in: .rect(cornerRadius: 10))
        .padding(.horizontal, 6)
    }

    private func controlButton(
        systemImage: String,
        title: String,
        tint: Color,
        foreground: Color = WatchTheme.canvas,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.watch(20, weight: .bold))
                    .foregroundStyle(foreground)
                    .frame(width: buttonDiameter, height: buttonDiameter)
                    .background(tint, in: .circle)
                Text(title)
                    .font(.watch(10, weight: .medium))
                    .foregroundStyle(WatchTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
